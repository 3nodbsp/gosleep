/// 专利 CN112972862A《催眠音乐控制方法、装置、计算机设备和存储介质》算法参数。
///
/// 参数名称与取值范围均对应专利说明书：
/// - 预设呼吸值：12~18 次/分，默认 16（深睡判定的呼吸频率上限）；
/// - 缓和频率值降低步长：1~2 次/分，默认 1；
/// - 预设时间 T1：默认 10 分钟（每隔 T1 重新采集呼吸频率并评估）；
/// - 预设起伏值：4~10 mm，默认 8（深睡判定的胸腔起伏上限）。
class EngineParams {
  EngineParams({
    this.presetBreathRate = 16,
    this.stepBpm = 1,
    this.presetIntervalMinutes = 10,
    this.amplitudeThresholdMm = 8.0,
    this.minOutputBpm = 10,
    this.calibrationSeconds = 60,
    this.minSignalQuality = 0.35,
    this.deepSleepSustainSeconds = 60,
    this.sampleFreshnessSeconds = 90,
    this.timeScale = 1.0,
  });

  /// 预设呼吸值（次/分）。当前呼吸频率大于该值且不大于输出频率时，执行诱导降频。
  int presetBreathRate;

  /// 缓和频率值的降低步长（次/分）。
  int stepBpm;

  /// 预设时间 T1（分钟）：评估周期。
  int presetIntervalMinutes;

  /// 预设起伏值（mm 等效呼吸强度指数）。与呼吸频率共同构成深睡判定条件。
  double amplitudeThresholdMm;

  /// 音乐输出频率安全下限（次/分）。
  int minOutputBpm;

  /// 初始校准采集时长（秒）。对应专利实施例“检测一分钟获得当前呼吸频率”。
  int calibrationSeconds;

  /// 呼吸样本最低可信质量（0~1），低于该值的样本不参与算法。
  double minSignalQuality;

  /// 深睡条件需持续满足的时长（秒，真实时间）。
  /// 专利判定为即时条件；此处加持续时间是 v1 的稳健性扩展，防止瞬时误判停止音乐。
  int deepSleepSustainSeconds;

  /// 呼吸样本的最大有效期（秒，真实时间）。评估时样本过期则顺延评估。
  int sampleFreshnessSeconds;

  /// 演示加速倍率：仅作用于 T1 评估计时（60 表示 10 分钟周期压缩为 10 秒），
  /// 不影响校准采集与深睡持续判定（二者依赖真实呼吸信号节奏）。
  double timeScale;

  Map<String, Object> toJson() => <String, Object>{
        'presetBreathRate': presetBreathRate,
        'stepBpm': stepBpm,
        'presetIntervalMinutes': presetIntervalMinutes,
        'amplitudeThresholdMm': amplitudeThresholdMm,
        'minSignalQuality': minSignalQuality,
        'deepSleepSustainSeconds': deepSleepSustainSeconds,
        'timeScale': timeScale,
      };

  factory EngineParams.fromJson(Map<String, Object?> json) => EngineParams(
        presetBreathRate: _clampedInt(json['presetBreathRate'], 16, 12, 18),
        stepBpm: _clampedInt(json['stepBpm'], 1, 1, 2),
        presetIntervalMinutes: _clampedInt(json['presetIntervalMinutes'], 10, 5, 30),
        amplitudeThresholdMm: _clampedDouble(json['amplitudeThresholdMm'], 8.0, 4.0, 10.0),
        minSignalQuality: _clampedDouble(json['minSignalQuality'], 0.35, 0.1, 0.9),
        deepSleepSustainSeconds: _clampedInt(json['deepSleepSustainSeconds'], 60, 0, 300),
        timeScale: _clampedDouble(json['timeScale'], 1.0, 1.0, 120.0),
      );

  static int _clampedInt(Object? v, int def, int min, int max) {
    if (v is num) {
      final i = v.round();
      return i < min ? min : (i > max ? max : i);
    }
    return def;
  }

  static double _clampedDouble(Object? v, double def, double min, double max) {
    if (v is num) {
      final d = v.toDouble();
      return d < min ? min : (d > max ? max : d);
    }
    return def;
  }
}
