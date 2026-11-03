import 'package:flutter_test/flutter_test.dart';

import 'package:gosleep/engine/engine_params.dart';
import 'package:gosleep/engine/patent_engine.dart';
import 'package:gosleep/sensors/breath_source.dart';

/// 专利 CN112972862A 实施例 2 数值流验证：
/// 校准 Fa=20 → Fb=20 同步播放 → 每 T1(10min) 评估：
/// Fa=20(>16, ≤Fb) → Fb=19 → 用户跟随 19 呼吸 → … → Fb=16；
/// 当 Fa≤16 且 起伏≤8mm → 判定深度睡眠，停止音乐。
void main() {
  late DateTime now;
  late PatentEngine engine;

  BreathSample sample(double fa, double amp, {double quality = 0.9}) =>
      BreathSample(
        rateBpm: fa,
        amplitudeMm: amp,
        quality: quality,
        at: now,
      );

  /// 模拟流逝 1 分钟：每秒喂一个样本并驱动 tick（贴近真实采集节奏）。
  void elapseMinute(double fa, double amp) {
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(fa, amp));
      engine.tick();
    }
  }

  setUp(() {
    now = DateTime(2026, 1, 1, 22, 0, 0);
    engine = PatentEngine(params: EngineParams(), clock: () => now);
  });

  test('校准期低质量样本不计入，校准完成后同步跟随（Fb=Fa）', () {
    engine.start();
    expect(engine.phase, SessionPhase.calibrating);

    // 100 秒低质量信号不应推进校准。
    for (var i = 0; i < 100; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12, quality: 0.1));
    }
    expect(engine.phase, SessionPhase.calibrating);
    expect(engine.outputBpm, 0);

    // 60 秒有效信号完成校准。
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12));
    }
    expect(engine.phase, SessionPhase.syncFollowing);
    expect(engine.outputBpm, 20);
  });

  test('实施例 2 主流程：20 → 19 → 18 → 17 → 16 → 深睡停止', () {
    engine.start();

    // 第 1 分钟：采集 Fa=20（实施例：检测一分钟）。
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12));
    }
    expect(engine.outputBpm, 20, reason: '校准完成即同步跟随，Fb=Fa=20');

    // 专利实施例：播放 10 分钟后评估，Fa=20>16 且 ≤Fb → Fb=19。
    elapseMinute(20, 12); // 第 2 分钟
    // …累计 10 分钟于第 11 分钟末评估：
    for (var m = 0; m < 9; m++) {
      elapseMinute(20, 12);
    }
    expect(engine.outputBpm, 19, reason: 'T1 评估：诱导降频 Fb=20-1=19');
    expect(engine.phase, SessionPhase.inducing);
    expect(engine.stepDownCount, 1);

    // 用户跟随 19 呼吸 10 分钟 → Fb=18。
    for (var m = 0; m < 10; m++) {
      elapseMinute(19, 12);
    }
    expect(engine.outputBpm, 18);
    expect(engine.stepDownCount, 2);

    // 跟随 18 → 17。
    for (var m = 0; m < 10; m++) {
      elapseMinute(18, 12);
    }
    expect(engine.outputBpm, 17);
    expect(engine.stepDownCount, 3);

    // 跟随 17 → 16。
    for (var m = 0; m < 10; m++) {
      elapseMinute(17, 12);
    }
    expect(engine.outputBpm, 16);
    expect(engine.stepDownCount, 4);

    // Fa=16 ≤ 预设值，但幅度 10 > 8：不再降频，也暂不判深睡。
    for (var m = 0; m < 10; m++) {
      elapseMinute(16, 10);
    }
    expect(engine.outputBpm, 16, reason: '呼吸已达标但幅度未达标，保持');
    expect(engine.stepDownCount, 4);

    // 呼吸变浅（幅度 7 ≤ 8）且持续 60 秒 → 深度睡眠，音乐停止。
    for (var i = 0; i < 70; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(16, 7));
      engine.tick();
    }
    expect(engine.phase, SessionPhase.deepSleep);
    expect(engine.deepSleepAt, isNotNull);
    expect(engine.outputBpm, 16);
    expect(engine.stepDownCount, 4);
    expect(engine.resyncCount, 0);

    // 深睡后不再处理样本。
    engine.onSample(sample(20, 12));
    expect(engine.phase, SessionPhase.deepSleep);
  });

  test('呼吸不减反增（Fa>Fb）→ 重新同步 Fb=Fa', () {
    engine.start();
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(18, 12));
    }
    expect(engine.outputBpm, 18);

    // 第一次评估：18>16 且 ≤18 → Fb=17。
    for (var m = 0; m < 10; m++) {
      elapseMinute(18, 12);
    }
    expect(engine.outputBpm, 17);

    // 用户呼吸加快到 21 > Fb=17 → 重新同步。
    for (var m = 0; m < 10; m++) {
      elapseMinute(21, 12);
    }
    expect(engine.outputBpm, 21, reason: '重新跟随：Fb=Fa=21');
    expect(engine.phase, SessionPhase.resyncing);
    expect(engine.resyncCount, 1);
  });

  test('入睡快（校准时呼吸已低于预设值）：不降频，幅度达标即深睡', () {
    engine.start();
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(14, 12));
    }
    expect(engine.outputBpm, 14);

    // 评估：Fa=14 ≤ 16，幅度 12>8 → 保持播放。
    for (var m = 0; m < 10; m++) {
      elapseMinute(14, 12);
    }
    expect(engine.outputBpm, 14);
    expect(engine.stepDownCount, 0);

    // 幅度下降并持续 → 深睡。
    for (var i = 0; i < 70; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(14, 6));
      engine.tick();
    }
    expect(engine.phase, SessionPhase.deepSleep);
  });

  test('演示加速 60×：T1=10 分钟压缩为 10 秒', () {
    final p = EngineParams()..timeScale = 60.0;
    engine = PatentEngine(params: p, clock: () => now);
    engine.start();
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12));
    }
    expect(engine.outputBpm, 20);

    // 真实仅流逝 10 秒（每秒喂样本保持新鲜）。
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12));
      engine.tick();
    }
    expect(engine.outputBpm, 19, reason: '60× 加速下 10 秒即完成首次评估');
  });

  test('样本过期时评估顺延，不使用陈旧 Fa', () {
    engine.start();
    for (var i = 0; i < 60; i++) {
      now = now.add(const Duration(seconds: 1));
      engine.onSample(sample(20, 12));
    }
    expect(engine.outputBpm, 20);

    // 10 分钟无任何样本：评估应顺延。
    now = now.add(const Duration(minutes: 11));
    engine.tick();
    expect(engine.outputBpm, 20, reason: '样本过期，不执行降频');

    // 恢复样本后下一 tick 立即评估。
    now = now.add(const Duration(seconds: 1));
    engine.onSample(sample(20, 12));
    engine.tick();
    expect(engine.outputBpm, 19);
  });
}
