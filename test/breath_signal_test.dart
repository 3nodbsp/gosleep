import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:gosleep/sensors/breath_signal.dart';

void main() {
  /// 生成呼吸包络（周期性起伏 + 少量噪声），单位与 RMS 包络一致。
  List<double> synthEnvelope({
    required double breathsPerMin,
    required double depth,
    required double seconds,
    int seed = 7,
  }) {
    final rng = math.Random(seed);
    final proc = BreathSignalProcessor();
    final rate = proc.envRate; // ≈ 31.25 Hz
    final n = (seconds * rate).round();
    return List<double>.generate(n, (i) {
      final t = i / rate;
      final base = 0.6 + depth * math.sin(2 * math.pi * breathsPerMin / 60 * t);
      return base * 5000 + rng.nextDouble() * 60;
    });
  }

  /// 生成呼吸调制噪声 PCM（模拟麦克风拾取呼吸声）。
  Uint8List synthBreathPcm({
    required double breathsPerMin,
    required double depth,
    required double seconds,
    int seed = 11,
  }) {
    final rng = math.Random(seed);
    const sr = 16000;
    final bytes = Uint8List(sr * seconds.toInt() * 2);
    final bd = ByteData.view(bytes.buffer);
    for (var i = 0; i < bytes.length ~/ 2; i++) {
      final t = i / sr;
      final m = 0.6 + depth * math.sin(2 * math.pi * breathsPerMin / 60 * t);
      final s = (rng.nextDouble() * 2 - 1) * m * 9000;
      bd.setInt16(i * 2, s.toInt(), Endian.little);
    }
    return bytes;
  }

  void pushInChunks(BreathSignalProcessor p, Uint8List bytes) {
    for (var off = 0; off < bytes.length; off += 4096) {
      final end = math.min(off + 4096, bytes.length);
      p.pushPcm(Uint8List.sublistView(bytes, off, end));
    }
  }

  test('包络自相关测频：18 次/分', () {
    final p = BreathSignalProcessor();
    p.debugPushEnvelope(
        synthEnvelope(breathsPerMin: 18, depth: 0.4, seconds: 50));
    final est = p.estimate();
    expect(est, isNotNull);
    expect((est!.rateBpm - 18).abs(), lessThan(1.0));
    expect(est.quality, greaterThan(0.5));
  });

  test('包络自相关测频：12 与 24 次/分', () {
    final slow = BreathSignalProcessor();
    slow.debugPushEnvelope(
        synthEnvelope(breathsPerMin: 12, depth: 0.4, seconds: 50));
    final estSlow = slow.estimate()!;
    expect((estSlow.rateBpm - 12).abs(), lessThan(1.0));

    final fast = BreathSignalProcessor();
    fast.debugPushEnvelope(
        synthEnvelope(breathsPerMin: 24, depth: 0.4, seconds: 50));
    final estFast = fast.estimate()!;
    expect((estFast.rateBpm - 24).abs(), lessThan(1.0));
  });

  test('包络含直流与慢漂移时仍能测频', () {
    final rng = math.Random(3);
    final p = BreathSignalProcessor();
    final rate = p.envRate;
    final n = (50 * rate).round();
    final env = List<double>.generate(n, (i) {
      final t = i / rate;
      return 4000 + // 直流
          1500 * math.sin(2 * math.pi * 0.02 * t) + // 慢漂移
          1200 * math.sin(2 * math.pi * 15 / 60 * t) + // 15 次/分呼吸
          rng.nextDouble() * 40;
    });
    p.debugPushEnvelope(env);
    final est = p.estimate()!;
    expect((est.rateBpm - 15).abs(), lessThan(1.0));
  });

  test('静音（无起伏）包络：返回空或极低质量', () {
    final p = BreathSignalProcessor();
    p.debugPushEnvelope(List<double>.filled(1500, 5000));
    final est = p.estimate();
    if (est != null) {
      expect(est.quality, lessThan(0.15));
    }
  });

  test('全链路 PCM：呼吸调制噪声 → 18 次/分，质量达标', () {
    final p = BreathSignalProcessor();
    pushInChunks(
        p, synthBreathPcm(breathsPerMin: 18, depth: 0.4, seconds: 50));
    final est = p.estimate();
    expect(est, isNotNull, reason: '50 秒 PCM 应足以估计');
    expect((est!.rateBpm - 18).abs(), lessThan(1.5));
    expect(est.quality, greaterThan(0.35));
  });

  test('幅度映射：校准（清醒）≈10mm，呼吸变浅（幅度减半）<8mm 达到深睡阈值', () {
    final p = BreathSignalProcessor();

    // 清醒期（深度 0.4）45 秒 → 校准。
    pushInChunks(
        p, synthBreathPcm(breathsPerMin: 18, depth: 0.4, seconds: 45, seed: 5));
    // 校准前的临时幅度。
    final pre = p.estimate()!;
    expect(pre.amplitudeMm, 12.0);

    p.calibrate();
    expect(p.isCalibrated, isTrue);
    final awake = p.estimate()!;
    // 清醒映射值应在 9~12 区间。
    expect(awake.amplitudeMm, greaterThan(9));
    expect(awake.amplitudeMm, lessThan(12));

    // 入睡后呼吸声变浅（调制深度减半 → 幅度约一半）。
    pushInChunks(
        p, synthBreathPcm(breathsPerMin: 14, depth: 0.2, seconds: 46, seed: 6));
    final asleep = p.estimate()!;
    expect(asleep.amplitudeMm, lessThan(8.5),
        reason: '幅度减半应低于专利 8mm 深睡阈值');
    expect(asleep.amplitudeMm, greaterThan(4));
  });
}
