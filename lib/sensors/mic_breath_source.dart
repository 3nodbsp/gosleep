import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'breath_signal.dart';
import 'breath_source.dart';

/// 麦克风呼吸采集源。
///
/// 对应专利的“检测模块”（原方案为 UWB 脉冲雷达；本 APP 以麦克风拾取呼吸音频）。
/// PCM 流（16kHz/16bit/单声道）→ [BreathSignalProcessor] → 每秒输出一个呼吸样本。
///
/// 采集配置说明：显式关闭自动增益 / 回声消除 / 降噪，
/// 这些系统处理会抹平呼吸声的幅度起伏，破坏包络与幅度估计。
class MicBreathSource implements BreathSource {
  MicBreathSource({
    double sensitivity = 1.0,
    int calibrationSeconds = 60,
  })  : _processor = BreathSignalProcessor(sensitivity: sensitivity),
        _calibrationSeconds = calibrationSeconds;

  static const int _pcmSampleRate = 16000;

  final BreathSignalProcessor _processor;
  final int _calibrationSeconds;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _emitTimer;
  DateTime? _startedAt;

  final _samplesCtrl = StreamController<BreathSample>.broadcast();
  final _levelCtrl = StreamController<double>.broadcast();

  @override
  Stream<BreathSample> get samples => _samplesCtrl.stream;

  @override
  Stream<double> get level => _levelCtrl.stream;

  /// 处理器直通（测试与高级设置用）。
  BreathSignalProcessor get processor => _processor;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('未获得麦克风权限，无法采集呼吸音频');
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _pcmSampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    _startedAt = DateTime.now();
    _pcmSub = stream.listen(_processor.pushPcm);
    _emitTimer = Timer.periodic(const Duration(seconds: 1), (_) => _emitOnce());
  }

  void _emitOnce() {
    _levelCtrl.add(_processor.inputLevel01);

    final started = _startedAt;
    if (started != null &&
        !_processor.isCalibrated &&
        DateTime.now().difference(started).inSeconds >= _calibrationSeconds) {
      _processor.calibrate();
    }

    final est = _processor.estimate();
    if (est == null) return;
    _samplesCtrl.add(BreathSample(
      rateBpm: est.rateBpm,
      amplitudeMm: est.amplitudeMm,
      quality: est.quality,
      at: DateTime.now(),
    ));
  }

  @override
  Future<void> stop() async {
    _emitTimer?.cancel();
    _emitTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // 停止时录制器可能已停止，忽略。
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _samplesCtrl.close();
    await _levelCtrl.close();
    await _recorder.dispose();
  }
}
