import 'dart:async';
import 'dart:math' as math;

import 'engine_params.dart';
import '../sensors/breath_source.dart';

/// 会话阶段（对应专利方法步骤）。
enum SessionPhase {
  /// 未开始。
  idle,

  /// 采集初始呼吸频率（实施例：检测一分钟）。
  calibrating,

  /// 同步跟随：音乐输出频率 = 当前呼吸频率。
  syncFollowing,

  /// 诱导降频：当前呼吸频率 > 预设呼吸值 且 ≤ 输出频率，输出频率 -= 步长。
  inducing,

  /// 重新同步：呼吸不减反增（当前呼吸频率 > 输出频率），输出频率 = 当前呼吸频率。
  resyncing,

  /// 深度睡眠：呼吸频率 ≤ 预设呼吸值 且 起伏 ≤ 预设起伏值，停止音乐。
  deepSleep,

  /// 手动停止。
  stopped,
}

/// 会话事件类型。
enum SessionEventType {
  /// 校准完成，音乐开始（输出频率 = 校准呼吸频率）。
  calibrated,

  /// 诱导降频一次。
  stepDown,

  /// 重新同步（输出频率 = 当前呼吸频率）。
  resynced,

  /// 呼吸已慢于预设值但起伏未达标时的向下跟随（v1 扩展）。
  trackDown,

  /// 判定进入深度睡眠，停止音乐。
  deepSleep,
}

/// 会话事件记录（用于 UI 与报告）。
class SessionEvent {
  const SessionEvent({
    required this.at,
    required this.type,
    required this.minuteOfSession,
    this.fa,
    this.fb,
    this.amp,
  });

  final DateTime at;
  final SessionEventType type;

  /// 事件发生在会话开始后的第几分钟（报告图横轴定位）。
  final double minuteOfSession;

  /// 事件时的当前呼吸频率 Fa。
  final double? fa;

  /// 事件时的输出频率 Fb。
  final int? fb;

  /// 事件时的呼吸幅度指数。
  final double? amp;
}

/// 专利 CN112972862A 核心算法状态机（纯 Dart，无 Flutter 依赖）。
///
/// 流程：
/// 1. 采集用户当前呼吸频率 Fa（校准 [EngineParams.calibrationSeconds] 秒的有效信号）；
/// 2. 同步跟随：令催眠音乐输出频率 Fb = Fa；
/// 3. 每隔预设时间 T1 评估一次：
///    - 若 Fa > Fb（呼吸不减反增）→ 重新同步，Fb = Fa；
///    - 否则若 Fa > 预设呼吸值 → 诱导降频，Fb -= 步长；
///    - 否则（Fa ≤ 预设呼吸值）检查起伏；
/// 4. 当 Fa ≤ 预设呼吸值 且 起伏 ≤ 预设起伏值（并持续
///    [EngineParams.deepSleepSustainSeconds] 秒）→ 判定深度睡眠，停止音乐。
class PatentEngine {
  PatentEngine({required this.params, DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  /// 引擎参数（可被设置页实时修改）。
  EngineParams params;

  final DateTime Function() _now;

  /// 当前阶段。
  SessionPhase phase = SessionPhase.idle;

  /// 音乐输出频率 Fb（次/分），0 表示尚未开始。
  int outputBpm = 0;

  /// 最近一次有效（质量达标）的呼吸频率 Fa。
  double? latestFa;

  /// 最近一次有效呼吸幅度指数。
  double? latestAmp;

  /// 最近一次有效样本时间。
  DateTime? latestGoodAt;

  /// 校准期累计有效样本数（约等于秒数，采集源 1 次/秒）。
  int goodSampleCount = 0;

  DateTime? sessionStart;
  DateTime? calibratedAt;
  DateTime? lastEvaluationAt;
  DateTime? deepSleepAt;

  int stepDownCount = 0;
  int resyncCount = 0;

  /// 有效样本序列（呼吸频率，用于报告曲线）。
  final List<BreathSample> samples = [];

  /// 输出频率序列（每 tick 记录一次，用于报告曲线）。
  final List<double> fbSeries = [];

  /// 事件序列。
  final List<SessionEvent> events = [];

  DateTime? _deepCandidateSince;

  final _phaseCtrl = StreamController<SessionPhase>.broadcast();
  final _fbCtrl = StreamController<int>.broadcast();
  final _eventCtrl = StreamController<SessionEvent>.broadcast();

  /// 阶段变化流。
  Stream<SessionPhase> get phaseStream => _phaseCtrl.stream;

  /// 输出频率变化流（音频层订阅）。
  Stream<int> get outputBpmStream => _fbCtrl.stream;

  /// 事件流。
  Stream<SessionEvent> get eventStream => _eventCtrl.stream;

  bool get isMusicPlaying =>
      phase == SessionPhase.syncFollowing ||
      phase == SessionPhase.inducing ||
      phase == SessionPhase.resyncing;

  /// 会话已进行时长。
  Duration get sessionElapsed =>
      sessionStart == null ? Duration.zero : _now().difference(sessionStart!);

  /// 校准进度（0~1）。
  double get calibrationProgress =>
      (goodSampleCount / math.max(1, params.calibrationSeconds)).clamp(0.0, 1.0);

  /// 开始会话：进入校准采集阶段。
  void start() {
    phase = SessionPhase.calibrating;
    outputBpm = 0;
    latestFa = null;
    latestAmp = null;
    latestGoodAt = null;
    goodSampleCount = 0;
    sessionStart = _now();
    calibratedAt = null;
    lastEvaluationAt = null;
    deepSleepAt = null;
    stepDownCount = 0;
    resyncCount = 0;
    samples.clear();
    fbSeries.clear();
    events.clear();
    _deepCandidateSince = null;
    _phaseCtrl.add(phase);
  }

  /// 手动停止。
  void stopManual() {
    if (phase == SessionPhase.deepSleep || phase == SessionPhase.stopped) return;
    phase = SessionPhase.stopped;
    _phaseCtrl.add(phase);
  }

  /// 输入一个呼吸样本（采集源约 1 次/秒调用）。
  void onSample(BreathSample s) {
    if (phase == SessionPhase.idle ||
        phase == SessionPhase.stopped ||
        phase == SessionPhase.deepSleep) {
      return;
    }
    samples.add(s);
    if (samples.length > 40000) {
      samples.removeRange(0, samples.length - 40000);
    }

    if (s.quality < params.minSignalQuality) {
      return; // 低质量样本：保留用于曲线，但不参与算法
    }

    latestFa = s.rateBpm;
    latestAmp = s.amplitudeMm;
    latestGoodAt = s.at;
    goodSampleCount++;

    if (phase == SessionPhase.calibrating) {
      if (goodSampleCount >= params.calibrationSeconds) {
        _finishCalibration();
      }
      return;
    }

    // 深睡即时判定（持续条件在 _checkDeepSleep 内部维护）。
    _checkDeepSleep(s.at);
  }

  /// 周期调用（约 4 次/秒）：驱动 T1 评估计时与 Fb 曲线记录。
  void tick() {
    if (isMusicPlaying) {
      fbSeries.add(outputBpm.toDouble());
      if (fbSeries.length > 200000) {
        fbSeries.removeRange(0, 100000);
      }
    }
    if (!isMusicPlaying || lastEvaluationAt == null) return;

    final intervalMs =
        params.presetIntervalMinutes * 60 * 1000 / params.timeScale;
    final elapsedMs = _now().difference(lastEvaluationAt!).inMilliseconds;
    if (elapsedMs >= intervalMs) {
      _evaluate();
    }
  }

  void _finishCalibration() {
    final fa = latestFa ?? params.presetBreathRate.toDouble();
    outputBpm = _clampBpm(fa.round());
    calibratedAt = _now();
    lastEvaluationAt = calibratedAt;
    _setPhase(SessionPhase.syncFollowing);
    _emit(SessionEventType.calibrated, fa: fa, fb: outputBpm);
    _fbCtrl.add(outputBpm);
  }

  /// T1 评估：核心决策（对应专利 S104 诱导降频 / S105 重新同步 / 深睡检查）。
  void _evaluate() {
    final fa = latestFa;
    if (fa == null) return;

    // 样本过期（传感器长时间无有效信号）：顺延本次评估，等待新样本。
    final ageMs = _now().difference(latestGoodAt!).inMilliseconds;
    if (ageMs > params.sampleFreshnessSeconds * 1000) return;

    final amp = latestAmp ?? 999;
    lastEvaluationAt = _now();

    if (fa > outputBpm) {
      // 呼吸不减反增：重新跟随，令输出频率 = 当前呼吸频率。
      outputBpm = _clampBpm(fa.round());
      resyncCount++;
      _setPhase(SessionPhase.resyncing);
      _emit(SessionEventType.resynced, fa: fa, fb: outputBpm, amp: amp);
    } else if (fa > params.presetBreathRate) {
      // 诱导降频：设定一个降低步长的缓和频率值并更新输出频率。
      final next = outputBpm - params.stepBpm;
      outputBpm = next < params.minOutputBpm ? params.minOutputBpm : next;
      stepDownCount++;
      _setPhase(SessionPhase.inducing);
      _emit(SessionEventType.stepDown, fa: fa, fb: outputBpm, amp: amp);
    } else {
      // 呼吸频率已不大于预设呼吸值。
      if (amp <= params.amplitudeThresholdMm) {
        _checkDeepSleep(_now()); // 幅度也已达标 → 走持续判定
      } else if (fa < outputBpm - 0.5) {
        // v1 扩展：呼吸慢于音乐时向下跟随，避免音乐节奏快于用户呼吸。
        outputBpm = _clampBpm(fa.round());
        _emit(SessionEventType.trackDown, fa: fa, fb: outputBpm, amp: amp);
      }
    }
    _fbCtrl.add(outputBpm);
  }

  /// 深睡判定：呼吸频率 ≤ 预设呼吸值 且 起伏 ≤ 预设起伏值，且持续满足。
  void _checkDeepSleep(DateTime at) {
    final fa = latestFa;
    final amp = latestAmp;
    if (fa == null || amp == null) return;

    final met = fa <= params.presetBreathRate && amp <= params.amplitudeThresholdMm;
    if (!met) {
      _deepCandidateSince = null;
      return;
    }
    final since = _deepCandidateSince ??= at;
    if (at.difference(since).inMilliseconds >=
        params.deepSleepSustainSeconds * 1000) {
      deepSleepAt = at;
      _setPhase(SessionPhase.deepSleep);
      _emit(SessionEventType.deepSleep, fa: fa, fb: outputBpm, amp: amp);
    }
  }

  int _clampBpm(int v) => v < 8 ? 8 : (v > 30 ? 30 : v);

  void _setPhase(SessionPhase p) {
    phase = p;
    _phaseCtrl.add(p);
  }

  void _emit(
    SessionEventType type, {
    double? fa,
    int? fb,
    double? amp,
  }) {
    final start = sessionStart ?? _now();
    final minute = _now().difference(start).inMilliseconds / 60000.0;
    final e = SessionEvent(
      at: _now(),
      type: type,
      minuteOfSession: minute,
      fa: fa,
      fb: fb,
      amp: amp,
    );
    events.add(e);
    _eventCtrl.add(e);
  }

  void dispose() {
    _phaseCtrl.close();
    _fbCtrl.close();
    _eventCtrl.close();
  }
}
