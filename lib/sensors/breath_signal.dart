import 'dart:math' as math;
import 'dart:typed_data';

/// 呼吸音频信号估计结果。
class BreathEstimate {
  const BreathEstimate({
    required this.rateBpm,
    required this.amplitudeMm,
    required this.quality,
    required this.snrDb,
  });

  /// 呼吸频率（次/分）。
  final double rateBpm;

  /// 呼吸幅度指数（mm 等效，0~16）。
  final double amplitudeMm;

  /// 综合质量（0~1）= 自相关峰高度 × 信噪比因子。
  final double quality;

  /// 呼吸包络信噪比（dB）。
  final double snrDb;
}

/// 麦克风 PCM → 呼吸包络 → 呼吸频率/幅度估计（纯 Dart，可独立测试）。
///
/// 处理链：
/// 1. 16kHz PCM16LE 按 [windowSamples]（默认 512 ≈ 32ms）分窗；
///    窗内先做一阶高通（去直流与传感器漂移），再求 RMS 得呼吸包络（约 31.25 Hz）；
/// 2. 维护最近约 45 秒包络滚动缓冲；
/// 3. 包络去趋势（减 8 秒滑动平均）后做自相关，在 4~30 次/分
///    （周期 2~15 秒）滞后范围内找峰，抛物线插值精化周期；
/// 4. 幅度指数：以校准期（清醒）呼吸幅度为基准做饱和映射——
///    清醒 ≈ 10.4 mm，幅度降至清醒的一半 ≈ 7.9 mm，
///    从而与专利预设起伏值 8mm（深睡判定）自然衔接。
class BreathSignalProcessor {
  BreathSignalProcessor({
    this.pcmSampleRate = 16000,
    this.windowSamples = 512,
    this.sensitivity = 1.0,
  });

  final int pcmSampleRate;
  final int windowSamples;

  /// 幅度映射灵敏度（设置页 0.5~2.0）：越大越容易判定呼吸变浅。
  double sensitivity;

  static const int _envKeep = 1400; // ~45s @ 31.25Hz

  final List<double> _env = <double>[];

  // 高通滤波器状态。
  double _hpPrevIn = 0;
  double _hpPrevOut = 0;

  double _winEnergy = 0;
  int _winCount = 0;

  double _lastInputDb = -80;

  bool _calibrated = false;
  double _awakeBreathAmp = 0;

  /// 包络采样率（Hz）。
  double get envRate => pcmSampleRate / windowSamples;

  /// 最近一个窗口的输入电平（dBFS，用于 UI 电平条）。
  double get lastInputDb => _lastInputDb;

  bool get isCalibrated => _calibrated;

  /// 输入一段 PCM16LE 字节流。
  void pushPcm(Uint8List bytes) {
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final raw = bytes[i] | (bytes[i + 1] << 8);
      final s = raw.toSigned(16).toDouble();

      // 一阶高通 y = a·(y' + x - x')，截止约 50Hz。
      const hpA = 0.980;
      final y = hpA * (_hpPrevOut + s - _hpPrevIn);
      _hpPrevIn = s;
      _hpPrevOut = y;

      _winEnergy += y * y;
      _winCount++;

      if (_winCount >= windowSamples) {
        final rms = math.sqrt(_winEnergy / _winCount);
        _winEnergy = 0;
        _winCount = 0;
        _lastInputDb = 20 * math.log(math.max(rms, 1e-9) / 32768) / math.ln10;
        _env.add(rms);
        if (_env.length > _envKeep) {
          _env.removeRange(0, _env.length - _envKeep);
        }
      }
    }
  }

  /// 校准：以当前缓冲（清醒期呼吸）确立幅度基准。
  void calibrate() {
    final analysis = _analyzeEnvelope(_env);
    if (analysis == null) return;
    // 清醒基准幅度：至少为估计噪声底的两倍，防止静音环境下校准失效。
    final floor = math.max(analysis.noiseAmp * 2.0, 1e-4);
    _awakeBreathAmp = math.max(analysis.breathAmp, floor);
    _calibrated = true;
  }

  /// 基于当前缓冲给出估计；数据不足时返回 null。
  BreathEstimate? estimate() {
    final analysis = _analyzeEnvelope(_env);
    if (analysis == null) return null;

    final rate = analysis.periodSec <= 0 ? 0.0 : 60.0 / analysis.periodSec;
    final amp = analysis.breathAmp;
    final noise = math.max(analysis.noiseAmp, 1e-6);
    final snrDb = 20 * math.log(math.max(amp, 1e-6) / noise) / math.ln10;
    final snrFactor = _clamp01((snrDb - 2.0) / 8.0);
    final quality = _clamp01(analysis.corrPeak * snrFactor);

    double ampMm;
    if (_calibrated && _awakeBreathAmp > 0) {
      // 饱和映射：清醒(amp=awake) ≈ 10.4mm，一半 ≈ 7.9mm。
      ampMm = 15.0 * amp / (amp + _awakeBreathAmp / 2.25);
    } else {
      ampMm = 12.0; // 校准前的临时值（算法仅在校准后使用幅度）。
    }
    ampMm = _clampRange(ampMm * sensitivity, 0.0, 16.0);

    return BreathEstimate(
      rateBpm: _clampRange(rate, 3.0, 35.0),
      amplitudeMm: ampMm,
      quality: quality,
      snrDb: snrDb,
    );
  }

  /// 输入电平归一化（0~1，映射 -55dB ~ -20dB）。
  double get inputLevel01 => _clamp01((_lastInputDb + 55) / 35);

  /// 供测试直接注入包络序列。
  void debugPushEnvelope(List<double> values) {
    _env.addAll(values);
    if (_env.length > _envKeep) {
      _env.removeRange(0, _env.length - _envKeep);
    }
  }

  static const int _detrendHalfWindow = 125; // 8s 滑动平均 @31.25Hz

  _EnvelopeAnalysis? _analyzeEnvelope(List<double> env) {
    final n = env.length;
    // 至少 22 秒数据，且去趋势后仍能覆盖最长滞后（15s）。
    if (n < (envRate * 22).round()) return null;

    // 前缀和 → 去趋势（减 8s 滑动平均），裁掉两端半窗。
    final half = _detrendHalfWindow;
    final prefix = List<double>.filled(n + 1, 0);
    for (var i = 0; i < n; i++) {
      prefix[i + 1] = prefix[i] + env[i];
    }
    final lo = half;
    final hi = n - half;
    if (hi - lo < (envRate * 17).round()) return null;
    final m = hi - lo;
    final x = List<double>.filled(m, 0);
    var mean = 0.0;
    for (var i = lo; i < hi; i++) {
      final a = i - half < 0 ? 0 : i - half;
      final b = i + half > n ? n : i + half;
      final v = env[i] - (prefix[b] - prefix[a]) / (b - a);
      x[i - lo] = v;
      mean += v;
    }
    mean /= m;
    if (mean != 0) {
      for (var i = 0; i < m; i++) {
        x[i] -= mean;
      }
    }

    // 自相关：滞后 2s~15s（对应 30~4 次/分）。
    final r0 = _meanProduct0(x);
    if (r0 <= 1e-12) return null;
    final minLag = (envRate * 2).round();
    final maxLag = math.min((envRate * 15).round(), m ~/ 2 + 1);
    if (maxLag <= minLag + 2) return null;

    var bestLag = minLag;
    var bestR = -1.0;
    final rs = List<double>.filled(maxLag + 1, 0);
    for (var lag = minLag; lag <= maxLag; lag++) {
      final r = _meanProduct(x, lag) / r0;
      rs[lag] = r;
      if (r > bestR) {
        bestR = r;
        bestLag = lag;
      }
    }
    if (bestR < 0.05) return null;

    // 抛物线插值精化峰位。
    var lagF = bestLag.toDouble();
    if (bestLag > minLag && bestLag < maxLag) {
      final yl = rs[bestLag - 1];
      final y0 = rs[bestLag];
      final yr = rs[bestLag + 1];
      final denom = yl - 2 * y0 + yr;
      if (denom != 0) {
        final delta = 0.5 * (yl - yr) / denom;
        if (delta > -1 && delta < 1) lagF = bestLag + delta;
      }
    }
    final periodSec = lagF / envRate;

    // 幅度：去趋势序列 |x| 的前 10% 均值（呼吸峰）与后 20% 均值（噪声底）。
    final abs = List<double>.generate(m, (i) => x[i].abs());
    abs.sort();
    final topCount = math.max(1, m ~/ 10);
    var breathSum = 0.0;
    for (var i = m - topCount; i < m; i++) {
      breathSum += abs[i];
    }
    final breathAmp = breathSum / topCount;
    final botCount = math.max(1, m ~/ 5);
    var noiseSum = 0.0;
    for (var i = 0; i < botCount; i++) {
      noiseSum += abs[i];
    }
    final noiseAmp = noiseSum / botCount;

    return _EnvelopeAnalysis(
      corrPeak: _clamp01(bestR),
      periodSec: periodSec,
      breathAmp: breathAmp,
      noiseAmp: noiseAmp,
    );
  }

  /// Σ x[i]·x[i] / n。
  static double _meanProduct0(List<double> x) {
    var s = 0.0;
    for (var i = 0; i < x.length; i++) {
      s += x[i] * x[i];
    }
    return s / x.length;
  }

  /// Σ x[i]·x[i+lag] / (n-lag)。
  static double _meanProduct(List<double> x, int lag) {
    var s = 0.0;
    final n = x.length;
    for (var i = 0; i + lag < n; i++) {
      s += x[i] * x[i + lag];
    }
    return s / (n - lag);
  }

  static double _clamp01(double v) => _clampRange(v, 0.0, 1.0);

  static double _clampRange(double v, double min, double max) =>
      v < min ? min : (v > max ? max : v);
}

class _EnvelopeAnalysis {
  const _EnvelopeAnalysis({
    required this.corrPeak,
    required this.periodSec,
    required this.breathAmp,
    required this.noiseAmp,
  });

  final double corrPeak;
  final double periodSec;
  final double breathAmp;
  final double noiseAmp;
}
