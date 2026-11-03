import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/pcm_player.dart';
import '../audio/soundscape_synth.dart';
import '../engine/engine_params.dart';
import '../engine/patent_engine.dart';
import '../engine/session_log.dart';
import '../sensors/breath_source.dart';
import '../sensors/mic_breath_source.dart';

/// 全局应用状态：设置持久化、会话生命周期（采集→引擎→音频）。
class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _params = _loadParams();
    engine = PatentEngine(params: _params);
  }

  final SharedPreferences _prefs;

  static const _kParams = 'gosleep.params';
  static const _kVolume = 'gosleep.volume';
  static const _kScape = 'gosleep.scape';
  static const _kSensitivity = 'gosleep.sensitivity';
  static const _kHistory = 'gosleep.history';

  late final EngineParams _params;
  late final PatentEngine engine;

  /// 引擎参数（设置页实时修改）。
  EngineParams get params => _params;

  MicBreathSource? _source;
  PcmPlayer? _player;
  SoundscapeSynth? _synth;

  StreamSubscription<BreathSample>? _sampleSub;
  StreamSubscription<double>? _levelSub;
  StreamSubscription<SessionEvent>? _eventSub;
  Timer? _tickTimer;
  Timer? _fadeTimer;

  /// 音景音量（0~1）。
  double volume = 0.7;

  /// 音景类型。
  Soundscape scape = Soundscape.ocean;

  /// 麦克风幅度灵敏度（0.5~2.0，下次会话生效）。
  double sensitivity = 1.0;

  /// 实时输入电平（0~1）。
  double liveLevel = 0;

  /// 会话是否进行中。
  bool get isRunning =>
      engine.phase != SessionPhase.idle &&
      engine.phase != SessionPhase.stopped &&
      engine.phase != SessionPhase.deepSleep;

  /// 历史会话（最新在前）。
  List<StoredSession> history = <StoredSession>[];

  EngineParams _loadParams() {
    final raw = _prefs.getString(_kParams);
    if (raw == null) return EngineParams();
    try {
      final map = jsonDecode(raw);
      if (map is Map<String, Object?>) return EngineParams.fromJson(map);
      return EngineParams();
    } catch (_) {
      return EngineParams();
    }
  }

  Future<void> load() async {
    volume = _clampDouble(_prefs.getDouble(_kVolume) ?? 0.7, 0.0, 1.0);
    final scapeIndex = _prefs.getInt(_kScape) ?? 0;
    scape = Soundscape.values[scapeIndex < 0 || scapeIndex >= Soundscape.values.length
        ? 0
        : scapeIndex];
    sensitivity = _clampDouble(_prefs.getDouble(_kSensitivity) ?? 1.0, 0.5, 2.0);
    history = _loadHistory();
    notifyListeners();
  }

  List<StoredSession> _loadHistory() {
    final raw = _prefs.getString(_kHistory);
    if (raw == null) return <StoredSession>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <StoredSession>[];
      return list
          .whereType<Map>()
          .map((m) => StoredSession.fromJson(Map<String, Object?>.from(m)))
          .toList();
    } catch (_) {
      return <StoredSession>[];
    }
  }

  // ---------------- 会话生命周期 ----------------

  /// 开始催眠会话：启动麦克风采集与引擎。
  Future<void> startSession() async {
    if (isRunning) return;
    await WakelockPlus.enable();

    final source = MicBreathSource(
      sensitivity: sensitivity,
      calibrationSeconds: params.calibrationSeconds,
    );
    _source = source;
    _synth = SoundscapeSynth(scape: scape, gain: volume);
    _player = PcmPlayer();

    _sampleSub = source.samples.listen((s) {
      engine.onSample(s);
      notifyListeners();
    });
    _levelSub = source.level.listen((l) {
      liveLevel = l;
      notifyListeners();
    });
    _eventSub = engine.eventStream.listen(_onEngineEvent);

    try {
      await source.start();
    } catch (e) {
      // 麦克风启动失败（如权限被拒）：清理并向上抛出。
      engine.stopManual();
      await _endSession();
      rethrow;
    }

    engine.start();

    _tickTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => engine.tick(),
    );
    notifyListeners();
  }

  Future<void> _onEngineEvent(SessionEvent e) async {
    switch (e.type) {
      case SessionEventType.calibrated:
        // 音乐开始：输出频率 = 校准呼吸频率。
        if (_synth != null && _player != null) {
          _synth!.outputBpm = (e.fb ?? 16).toDouble();
          await _player!.start(_synth!);
        }
        break;
      case SessionEventType.stepDown:
      case SessionEventType.resynced:
      case SessionEventType.trackDown:
        // 更新音乐输出频率（波浪周期即时跟随）。
        if (_synth != null && e.fb != null) {
          _synth!.outputBpm = e.fb!.toDouble();
        }
        break;
      case SessionEventType.deepSleep:
        // 深度睡眠：音乐淡出停止。
        await _fadeOutAndStop();
        await _endSession();
        break;
    }
    notifyListeners();
  }

  /// 手动停止会话。
  Future<void> stopSession() async {
    if (!isRunning) return;
    engine.stopManual();
    await _fadeOutAndStop();
    await _endSession();
    notifyListeners();
  }

  Future<void> _fadeOutAndStop() async {
    final synth = _synth;
    final player = _player;
    if (synth == null || player == null) return;

    const steps = 30;
    const stepMs = 100;
    final startGain = synth.masterGain;
    final completer = Completer<void>();
    var i = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (t) {
      i++;
      synth.masterGain = startGain * (1 - i / steps);
      if (i >= steps) {
        t.cancel();
        synth.masterGain = startGain;
        player.stop().then((_) => completer.complete());
      }
    });
    await completer.future.timeout(const Duration(seconds: 6), onTimeout: () {
      _fadeTimer?.cancel();
      return player.stop();
    });
  }

  Future<void> _endSession() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    await _sampleSub?.cancel();
    _sampleSub = null;
    await _levelSub?.cancel();
    _levelSub = null;
    await _eventSub?.cancel();
    _eventSub = null;
    await _source?.dispose();
    _source = null;

    final end = DateTime.now();
    if (engine.sessionStart != null &&
        (engine.samples.isNotEmpty || engine.stepDownCount > 0)) {
      final stored = StoredSession.fromEngine(engine, end);
      history.insert(0, stored);
      if (history.length > 30) history.removeRange(30, history.length);
      await _saveHistory();
    }

    _player = null;
    _synth = null;
    await WakelockPlus.disable();
  }

  Future<void> _saveHistory() async {
    try {
      final raw = jsonEncode(history.map((s) => s.toJson()).toList());
      await _prefs.setString(_kHistory, raw);
    } catch (_) {
      // 序列化失败不阻塞会话结束。
    }
  }

  Future<void> clearHistory() async {
    history = <StoredSession>[];
    await _prefs.remove(_kHistory);
    notifyListeners();
  }

  // ---------------- 设置 ----------------

  Future<void> _saveParams() async {
    await _prefs.setString(_kParams, jsonEncode(params.toJson()));
  }

  void setPresetBreathRate(int v) {
    params.presetBreathRate = _clampInt(v, 12, 18);
    _saveParams();
    notifyListeners();
  }

  void setStepBpm(int v) {
    params.stepBpm = _clampInt(v, 1, 2);
    _saveParams();
    notifyListeners();
  }

  void setPresetIntervalMinutes(int v) {
    params.presetIntervalMinutes = _clampInt(v, 5, 30);
    _saveParams();
    notifyListeners();
  }

  void setAmplitudeThreshold(double v) {
    params.amplitudeThresholdMm = _clampDouble(v, 4.0, 10.0);
    _saveParams();
    notifyListeners();
  }

  void setDemoAccelerated(bool on) {
    params.timeScale = on ? 60.0 : 1.0;
    _saveParams();
    notifyListeners();
  }

  bool get demoAccelerated => params.timeScale > 1.5;

  void setVolume(double v) {
    volume = _clampDouble(v, 0.0, 1.0);
    _synth?.masterGain = volume;
    _prefs.setDouble(_kVolume, volume);
    notifyListeners();
  }

  void setScape(Soundscape v) {
    scape = v;
    _synth?.scape = v;
    _prefs.setInt(_kScape, v.index);
    notifyListeners();
  }

  void setSensitivity(double v) {
    sensitivity = _clampDouble(v, 0.5, 2.0);
    _prefs.setDouble(_kSensitivity, sensitivity);
    notifyListeners();
  }

  static int _clampInt(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);

  static double _clampDouble(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);

  @override
  void dispose() {
    _tickTimer?.cancel();
    _fadeTimer?.cancel();
    _sampleSub?.cancel();
    _levelSub?.cancel();
    _eventSub?.cancel();
    engine.dispose();
    super.dispose();
  }
}
