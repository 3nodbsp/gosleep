import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/session_log.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// 报告页：最近会话的频率曲线、幅度曲线、事件标记与历史列表。
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _selected = 0;

  String _fmtDuration(Duration? d) {
    if (d == null) return '--';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h 小时 $m 分';
    }
    if (m > 0) return '$m 分 $s 秒';
    return '$s 秒';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final history = widget.state.history;
        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.nightlight, size: 56, color: Colors.white24),
                const SizedBox(height: 12),
                const Text('暂无会话记录', style: TextStyle(color: Colors.white54)),
                const SizedBox(height: 4),
                const Text('完成一次催眠会话后这里会生成睡眠报告',
                    style: TextStyle(color: Colors.white30, fontSize: 12)),
              ],
            ),
          );
        }

        if (_selected >= history.length) _selected = 0;
        final session = history[_selected];

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _buildSummaryCard(context, session),
            _ChartCard(
              title: '呼吸频率曲线（Fa 实测 / Fb 音乐节奏）',
              height: 180,
              painter: _FreqChartPainter(session: session),
            ),
            _ChartCard(
              title: '呼吸幅度指数',
              height: 120,
              painter: _AmpChartPainter(session: session),
            ),
            _buildLegendCard(context),
            _buildHistoryList(context, history),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(BuildContext context, StoredSession s) {
    final fallAsleep = s.fallAsleepIn;
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(k,
                    style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ),
              Expanded(
                  child: Text(v,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500))),
            ],
          ),
        );

    final total = DateTime.parse(s.endedIso).difference(s.started);

    return Card(
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _fmtDate(s.started),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            kv('会话时长', _fmtDuration(total)),
            kv('入睡用时', fallAsleep == null ? '未判定深睡' : _fmtDuration(fallAsleep)),
            kv('起始呼吸', '${s.startBpm} 次/分'),
            kv('最终节奏', s.finalBpm == null ? '--' : '${s.finalBpm} 次/分'),
            kv('诱导降频', '${s.stepDowns} 次'),
            kv('重新同步', '${s.resyncs} 次'),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildLegendCard(BuildContext context) {
    Widget dot(Color c, String t) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        );
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            dot(const Color(0xFF7FA8E8), '实测 Fa'),
            dot(const Color(0xFFB69CFF), '音乐 Fb'),
            dot(Colors.amber, '降频'),
            dot(Colors.redAccent, '重同步'),
            dot(Colors.tealAccent, '深睡判定'),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryList(BuildContext context, List<StoredSession> history) {
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('历史会话',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          for (var i = 0; i < history.length; i++)
            ListTile(
              dense: true,
              selected: i == _selected,
              selectedTileColor: Colors.white.withAlpha(18),
              leading: Icon(
                history[i].deepSleepIso == null
                    ? Icons.nightlight_round
                    : Icons.nights_stay,
                color: history[i].deepSleepIso == null
                    ? Colors.white38
                    : Colors.tealAccent,
                size: 20,
              ),
              title: Text(_fmtDate(history[i].started),
                  style: const TextStyle(fontSize: 13)),
              subtitle: Text(
                history[i].deepSleepIso == null
                    ? '未判定深睡 · 降频 ${history[i].stepDowns} 次'
                    : '深睡达成 · 降频 ${history[i].stepDowns} 次 · 重同步 ${history[i].resyncs} 次',
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => setState(() => _selected = i),
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.height,
    required this.painter,
  });

  final String title;
  final double height;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 8),
            SizedBox(
              height: height,
              width: double.infinity,
              child: CustomPaint(painter: painter),
            ),
          ],
        ),
      ),
    );
  }
}

/// 频率曲线：Fa 折线 + Fb 阶梯线 + 预设呼吸值虚线 + 事件标记。
class _FreqChartPainter extends CustomPainter {
  _FreqChartPainter({required this.session});

  final StoredSession session;

  static const double _minBpm = 8;
  static const double _maxBpm = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final s = session;
    final w = size.width;
    final h = size.height;
    final leftPad = 26.0;
    final plotW = w - leftPad;
    final plotH = h - 14;

    final maxMinutes = math.max(
      s.fa.length * StoredSession.seriesStepSeconds / 60.0,
      _lastMarkMinute(s),
    );
    if (maxMinutes <= 0) return;

    double xOf(double minute) => leftPad + minute / maxMinutes * plotW;
    double yOf(double bpm) =>
        plotH - (bpm - _minBpm) / (_maxBpm - _minBpm) * plotH;

    // 网格线与刻度。
    final grid = Paint()
      ..color = Colors.white.withAlpha(20)
      ..strokeWidth = 0.6;
    final labelStyle = const TextStyle(fontSize: 9, color: Colors.white38);
    for (final bpm in const [10.0, 16.0, 24.0]) {
      final y = yOf(bpm);
      canvas.drawLine(Offset(leftPad, y), Offset(w, y), grid);
      _drawText(canvas, '${bpm.toInt()}', Offset(0, y - 5), labelStyle);
    }

    // 预设呼吸值（16）虚线。
    final dash = Paint()
      ..color = Colors.white.withAlpha(70)
      ..strokeWidth = 1;
    final yPreset = yOf(16);
    for (double x = leftPad; x < w; x += 8) {
      canvas.drawLine(Offset(x, yPreset), Offset(x + 4, yPreset), dash);
    }

    // Fb 阶梯线。
    final fbPaint = Paint()
      ..color = const Color(0xFFB69CFF)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    _drawSeries(canvas, s.fb, xOf, yOf, fbPaint, stepMode: true);

    // Fa 折线。
    final faPaint = Paint()
      ..color = const Color(0xFF7FA8E8)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    _drawSeries(canvas, s.fa, xOf, yOf, faPaint);

    // 事件标记。
    for (final mark in s.marks) {
      final minute = mark[0];
      final code = mark[1].toInt();
      Color c;
      switch (code) {
        case 1:
          c = Colors.amber;
          break;
        case 2:
          c = Colors.redAccent;
          break;
        case 4:
          c = Colors.tealAccent;
          break;
        default:
          c = Colors.white24;
      }
      final x = xOf(minute);
      final y = yOf(s.fb.isEmpty ? 16 : _fbAtMinute(s, minute));
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()..color = c,
      );
    }
  }

  static double _lastMarkMinute(StoredSession s) {
    var m = 0.0;
    for (final mark in s.marks) {
      if (mark[0] > m) m = mark[0];
    }
    return m;
  }

  static double _fbAtMinute(StoredSession s, double minute) {
    final idx = (minute * 60 / StoredSession.seriesStepSeconds).round();
    if (idx < 0) return s.fb.first;
    if (idx >= s.fb.length) return s.fb.last;
    return s.fb[idx];
  }

  void _drawSeries(
    Canvas canvas,
    List<double> values,
    double Function(double) xOf,
    double Function(double) yOf,
    Paint paint, {
    bool stepMode = false,
  }) {
    if (values.isEmpty) return;
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final x = xOf(i * StoredSession.seriesStepSeconds / 60.0);
      if (v <= 0) {
        started = false; // 0 = 无数据断点
        continue;
      }
      final y = yOf(v);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else if (stepMode) {
        path.lineTo(x, values[i - 1] > 0 ? yOf(values[i - 1]) : y);
        path.lineTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_FreqChartPainter oldDelegate) =>
      oldDelegate.session != session;
}

/// 幅度指数曲线 + 阈值虚线。
class _AmpChartPainter extends CustomPainter {
  _AmpChartPainter({required this.session});

  final StoredSession session;

  @override
  void paint(Canvas canvas, Size size) {
    final s = session;
    final w = size.width;
    final h = size.height;
    final leftPad = 26.0;
    final plotW = w - leftPad;
    final plotH = h - 12;

    final n = s.amp.length;
    if (n == 0) return;
    final maxMinutes = n * StoredSession.seriesStepSeconds / 60.0;
    if (maxMinutes <= 0) return;

    double xOf(double m) => leftPad + m / maxMinutes * plotW;
    double yOf(double v) {
      final t = v / 16.0;
      return plotH - (t < 0 ? 0 : (t > 1 ? 1 : t)) * plotH;
    }

    final labelStyle = const TextStyle(fontSize: 9, color: Colors.white38);
    _drawText(canvas, '16', Offset(0, 0), labelStyle);
    _drawText(canvas, '8', Offset(0, yOf(8) - 5), labelStyle);
    _drawText(canvas, '0', Offset(0, plotH - 5), labelStyle);

    // 阈值 8 虚线。
    final dash = Paint()
      ..color = Colors.amber.withAlpha(90)
      ..strokeWidth = 1;
    final yT = yOf(8);
    for (double x = leftPad; x < w; x += 8) {
      canvas.drawLine(Offset(x, yT), Offset(x + 4, yT), dash);
    }

    final paint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    var started = false;
    for (var i = 0; i < n; i++) {
      final v = s.amp[i];
      if (v <= 0) {
        started = false;
        continue;
      }
      final x = xOf(i * StoredSession.seriesStepSeconds / 60.0);
      final y = yOf(v);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_AmpChartPainter oldDelegate) => oldDelegate.session != session;
}
