import 'patent_engine.dart';

/// 会话标记类型（报告图上的事件点）。
/// 0=校准完成 1=诱导降频 2=重新同步 3=向下跟随 4=深度睡眠
const List<int> kMarkCodes = <int>[0, 1, 2, 3, 4];

/// 持久化的会话记录（约 10 秒一个采样点，单会话最多 720 点 ≈ 2 小时）。
class StoredSession {
  StoredSession({
    required this.startedIso,
    required this.endedIso,
    required this.deepSleepIso,
    required this.startBpm,
    required this.finalBpm,
    required this.stepDowns,
    required this.resyncs,
    required this.fa,
    required this.fb,
    required this.amp,
    required this.marks,
  });

  /// 会话开始时间（ISO8601）。
  final String startedIso;

  /// 会话结束时间。
  final String endedIso;

  /// 判定深度睡眠的时间（未达成为 null）。
  final String? deepSleepIso;

  /// 校准期呼吸频率（次/分）。
  final int startBpm;

  /// 结束时输出频率。
  final int? finalBpm;

  final int stepDowns;
  final int resyncs;

  /// 当前呼吸频率 Fa 序列（10 秒步长）。
  final List<double> fa;

  /// 输出频率 Fb 序列（10 秒步长）。
  final List<double> fb;

  /// 呼吸幅度指数序列（10 秒步长）。
  final List<double> amp;

  /// 事件标记：[分钟数, 类型码]，类型码见 [kMarkCodes]。
  final List<List<double>> marks;

  DateTime get started => DateTime.parse(startedIso);

  DateTime? get deepSleepAt =>
      deepSleepIso == null ? null : DateTime.parse(deepSleepIso!);

  /// 入睡时长（开始 → 深睡判定）。未达成返回 null。
  Duration? get fallAsleepIn {
    final d = deepSleepAt;
    if (d == null) return null;
    return d.difference(started);
  }

  /// 序列点间隔（秒）。
  static const int seriesStepSeconds = 10;

  static StoredSession fromEngine(PatentEngine engine, DateTime end) {
    // Fa/amp：有效样本按 10 秒分桶取均值；空桶记 0（绘制时作断点）。
    final faBuckets = <double>[];
    final ampBuckets = <double>[];
    var bucketStart = engine.sessionStart!;
    var faSum = 0.0;
    var ampSum = 0.0;
    var faCount = 0;
    var ampCount = 0;
    for (final s in engine.samples) {
      while (s.at.difference(bucketStart).inSeconds >= seriesStepSeconds) {
        faBuckets.add(faCount == 0 ? 0.0 : faSum / faCount);
        ampBuckets.add(ampCount == 0 ? 0.0 : ampSum / ampCount);
        faSum = 0;
        ampSum = 0;
        faCount = 0;
        ampCount = 0;
        bucketStart = bucketStart.add(
          const Duration(seconds: seriesStepSeconds),
        );
      }
      if (s.quality >= 0.35) {
        faSum += s.rateBpm;
        faCount++;
        ampSum += s.amplitudeMm;
        ampCount++;
      }
    }
    if (faCount > 0 || ampCount > 0) {
      faBuckets.add(faCount == 0 ? 0.0 : faSum / faCount);
      ampBuckets.add(ampCount == 0 ? 0.0 : ampSum / ampCount);
    }

    // Fb：tick 序列按 10 秒分桶取末值（阶梯信号，约 4 tick/秒）。
    final fbBuckets = <double>[];
    if (engine.fbSeries.isNotEmpty) {
      var fbCount = 0;
      var fbLast = engine.fbSeries.first;
      for (final v in engine.fbSeries) {
        fbCount++;
        fbLast = v;
        if (fbCount >= seriesStepSeconds * 4) {
          fbBuckets.add(fbLast);
          fbCount = 0;
        }
      }
      if (fbCount > 0) fbBuckets.add(fbLast);
    }

    // 事件标记。
    final marks = <List<double>>[];
    for (final e in engine.events) {
      marks.add(<double>[e.minuteOfSession, e.type.index.toDouble()]);
    }

    final calibrated = engine.events
        .where((e) => e.type == SessionEventType.calibrated)
        .toList();

    return StoredSession(
      startedIso: engine.sessionStart!.toIso8601String(),
      endedIso: end.toIso8601String(),
      deepSleepIso: engine.deepSleepAt?.toIso8601String(),
      startBpm: calibrated.isEmpty ? 0 : (calibrated.first.fb ?? 0),
      finalBpm: engine.outputBpm == 0 ? null : engine.outputBpm,
      stepDowns: engine.stepDownCount,
      resyncs: engine.resyncCount,
      fa: _decimate(faBuckets, 720),
      fb: _decimate(fbBuckets, 720),
      amp: _decimate(ampBuckets, 720),
      marks: marks,
    );
  }

  /// 点数过多时做 2 倍抽稀。
  static List<double> _decimate(List<double> src, int maxPoints) {
    var list = src;
    while (list.length > maxPoints) {
      final out = <double>[];
      for (var i = 0; i < list.length; i += 2) {
        out.add(list[i]);
      }
      list = out;
    }
    return list;
  }

  Map<String, Object> toJson() => <String, Object>{
        'started': startedIso,
        'ended': endedIso,
        'deepSleep': deepSleepIso ?? '',
        'startBpm': startBpm,
        'finalBpm': finalBpm ?? 0,
        'stepDowns': stepDowns,
        'resyncs': resyncs,
        'fa': fa,
        'fb': fb,
        'amp': amp,
        'marks': marks,
      };

  static StoredSession fromJson(Map<String, Object?> json) {
    return StoredSession(
      startedIso: json['started'] as String? ??
          DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      endedIso:
          json['ended'] as String? ?? DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      deepSleepIso: (json['deepSleep'] as String?)?.isEmpty == true
          ? null
          : json['deepSleep'] as String?,
      startBpm: (json['startBpm'] as num?)?.toInt() ?? 0,
      finalBpm: (json['finalBpm'] as num?)?.toInt() == 0
          ? null
          : (json['finalBpm'] as num?)?.toInt(),
      stepDowns: (json['stepDowns'] as num?)?.toInt() ?? 0,
      resyncs: (json['resyncs'] as num?)?.toInt() ?? 0,
      fa: _doubleList(json['fa']),
      fb: _doubleList(json['fb']),
      amp: _doubleList(json['amp']),
      marks: _markList(json['marks']),
    );
  }

  static List<double> _doubleList(Object? v) {
    if (v is! List) return const <double>[];
    return v
        .whereType<num>()
        .map((e) => e.toDouble())
        .toList(growable: false);
  }

  static List<List<double>> _markList(Object? v) {
    if (v is! List) return const <List<double>>[];
    final out = <List<double>>[];
    for (final item in v) {
      if (item is List && item.length >= 2) {
        final a = item[0];
        final b = item[1];
        if (a is num && b is num) {
          out.add(<double>[a.toDouble(), b.toDouble()]);
        }
      }
    }
    return out;
  }
}
