/// 呼吸样本：算法的基本输入。
///
/// 对应专利中检测模块的输出（原方案为 UWB 脉冲雷达测得的呼吸频率与胸腔起伏度；
/// 本 APP 采用麦克风拾取呼吸音频估算，[amplitudeMm] 为“mm 等效呼吸强度指数”）。
class BreathSample {
  const BreathSample({
    required this.rateBpm,
    required this.amplitudeMm,
    required this.quality,
    required this.at,
  });

  /// 呼吸频率（次/分）。
  final double rateBpm;

  /// 呼吸幅度指数（mm 等效，0~16）。清醒校准值约 10，深睡（幅度减半）约 8。
  final double amplitudeMm;

  /// 信号质量（0~1），综合自相关峰高度与信噪比。
  final double quality;

  /// 采样时间。
  final DateTime at;
}

/// 输入信号电平等级（UI 提示用）。
enum SignalLevel { good, weak, tooWeak }

/// 呼吸采集源抽象。
abstract class BreathSource {
  /// 呼吸样本流（约 1 次/秒）。
  Stream<BreathSample> get samples;

  /// 实时输入电平（0~1），用于 UI 电平条。
  Stream<double> get level;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
