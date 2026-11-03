import 'dart:math' as math;
import 'dart:typed_data';

/// 催眠音景类型（专利：白噪声类催眠音乐，如海浪声、下雨声）。
enum Soundscape {
  /// 海浪：低通粉噪 + 随呼吸节奏起伏的浪涌。
  ocean,

  /// 细雨：高通噪声声床 + 轻微节奏调制。
  rain,

  /// 溪流：带通噪声 + 随机水泡点缀。
  stream,
}

/// 催眠音景实时合成器（纯 Dart，输出 PCM16LE 单声道字节流）。
///
/// 专利要求：催眠音乐的节奏（如海浪周期）与输出频率一致——
/// 输出频率为 F（次/分）时，每个波浪周期为 60/F 秒。
/// 合成完全程序化，不依赖任何音频素材；输出频率可随时调整，
/// 波浪相位连续，切换无爆音。
class SoundscapeSynth {
  SoundscapeSynth({
    this.sampleRate = 48000,
    this.scape = Soundscape.ocean,
    double initialBpm = 16,
    double gain = 0.7,
  })  : outputBpm = initialBpm,
        masterGain = gain;

  final int sampleRate;

  Soundscape scape;

  /// 音乐输出频率 Fb（次/分），即波浪节奏。
  double outputBpm;

  /// 总增益（0~1）。
  double masterGain;

  // Paul Kellet 粉噪发生器状态。
  double _p0 = 0, _p1 = 0, _p2 = 0, _p3 = 0, _p4 = 0, _p5 = 0, _p6 = 0;

  // 一阶低通状态（浪涌亮度调制 / 声床整形）。
  double _lpSlow = 0; // 固定低截止（雨声高通用）
  double _lpFast = 0; // 海浪可变截止

  // 波浪相位（0~1，周期 = 60/outputBpm 秒）。
  double _phase = 0;

  // 水泡（溪流）状态。
  double _bubbleAmp = 0;
  double _bubbleFreq = 0;
  double _bubblePhase = 0;
  double _bubbleDamp = 0;

  final math.Random _rng = math.Random(20261103);

  /// 生成 [frames] 帧的 PCM 数据。
  Uint8List generateChunk(int frames) {
    final out = Uint8List(frames * 2);
    final bd = ByteData.view(out.buffer);

    final bpm = outputBpm < 4 ? 4 : (outputBpm > 40 ? 40 : outputBpm);
    final periodSamples = sampleRate * 60.0 / bpm;
    final sr = sampleRate.toDouble();
    const twoPi = 2 * math.pi;

    var idx = 0;
    for (var i = 0; i < frames; i++) {
      final pink = _pink();

      // 浪涌包络：s = ((1 - cos(2πφ)) / 2)^1.5，慢起缓落近似海浪。
      final swellBase = 0.5 - 0.5 * math.cos(twoPi * _phase);
      final swell = swellBase * math.sqrt(swellBase);

      double src;
      double bed;
      double depth;

      switch (scape) {
        case Soundscape.ocean:
          // 浪越大低通截止越高（越亮）。
          final fc = 400.0 + 2800.0 * swell;
          final alpha = (twoPi * fc / sr).clamp(0.0, 0.9).toDouble();
          _lpFast += (pink - _lpFast) * alpha;
          src = _lpFast;
          bed = 0.06;
          depth = 0.90;
          break;
        case Soundscape.rain:
          // 高通噪声 = 原信号 - 低通。
          final alpha = (twoPi * 400.0 / sr).clamp(0.0, 0.9).toDouble();
          _lpSlow += (pink - _lpSlow) * alpha;
          src = pink - _lpSlow;
          bed = 0.50;
          depth = 0.28;
          break;
        case Soundscape.stream:
          final alphaHi = (twoPi * 3000.0 / sr).clamp(0.0, 0.9).toDouble();
          _lpFast += (pink - _lpFast) * alphaHi;
          final alphaLo = (twoPi * 400.0 / sr).clamp(0.0, 0.9).toDouble();
          _lpSlow += (_lpFast - _lpSlow) * alphaLo;
          src = _lpFast - _lpSlow + _bubble(sr);
          bed = 0.42;
          depth = 0.22;
          break;
      }

      _phase += 1.0 / periodSamples;
      if (_phase >= 1.0) _phase -= 1.0;

      var s = src * (bed + depth * swell) * masterGain * 1.4;
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;

      bd.setInt16(idx, (s * 32000).round(), Endian.little);
      idx += 2;
    }
    return out;
  }

  /// 溪流水泡：偶发短促阻尼振荡。
  double _bubble(double sr) {
    if (_bubbleAmp <= 0.0005) {
      // 平均约每 0.5 秒一个气泡。
      if (_rng.nextDouble() < sr / 24000.0) {
        _bubbleAmp = 0.25 + _rng.nextDouble() * 0.2;
        _bubbleFreq = 700 + _rng.nextDouble() * 1400;
        _bubbleDamp = math.exp(-1.0 / (0.025 * sr));
        _bubblePhase = 0;
      }
      return 0;
    }
    _bubblePhase += _bubbleFreq / sr;
    _bubbleAmp *= _bubbleDamp;
    if (_bubblePhase > 2 * math.pi * 40) _bubblePhase = 0;
    return _bubbleAmp * math.sin(2 * math.pi * _bubblePhase);
  }

  /// Paul Kellet 粉噪滤波器。
  double _pink() {
    final white = _rng.nextDouble() * 2 - 1;
    _p0 = 0.99886 * _p0 + white * 0.0555179;
    _p1 = 0.99332 * _p1 + white * 0.0750759;
    _p2 = 0.96900 * _p2 + white * 0.1538520;
    _p3 = 0.86650 * _p3 + white * 0.3104856;
    _p4 = 0.55000 * _p4 + white * 0.5329522;
    _p5 = -0.7616 * _p5 - white * 0.0168980;
    final out =
        _p0 + _p1 + _p2 + _p3 + _p4 + _p5 + _p6 + white * 0.5362;
    _p6 = white * 0.115926;
    return out * 0.11;
  }
}
