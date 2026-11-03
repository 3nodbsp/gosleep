import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 呼吸波浪动画。
///
/// 波浪周期 = 60/bpm 秒，与音景的节奏（音乐输出频率）严格一致，
/// 波峰经过屏幕上任意固定点的时间间隔即一个呼吸周期。
class BreathingWave extends StatefulWidget {
  const BreathingWave({
    super.key,
    required this.bpm,
    required this.active,
    this.height = 200,
  });

  /// 节奏（次/分）。
  final double bpm;

  /// 是否处于活跃（播放）状态。
  final bool active;

  final double height;

  @override
  State<BreathingWave> createState() => _BreathingWaveState();
}

class _BreathingWaveState extends State<BreathingWave>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (_lastElapsed == Duration.zero) {
        _lastElapsed = elapsed;
        return;
      }
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
      _lastElapsed = elapsed;
      final bpm = widget.bpm < 4 ? 4 : widget.bpm;
      if (widget.active) {
        final next = _phase.value + dt / (60.0 / bpm);
        _phase.value = next >= 1 ? next % 1.0 : next;
      }
    });
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: CustomPaint(
        painter: _WavePainter(
          phase: _phase,
          color: Theme.of(context).colorScheme.primary,
          dim: !widget.active,
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.phase,
    required this.color,
    required this.dim,
  }) : super(repaint: phase);

  final ValueNotifier<double> phase;
  final Color color;
  final bool dim;

  /// 与音频合成一致的浪涌包络。
  static double _swell(double s) {
    final t = s - s.floor();
    final base = 0.5 - 0.5 * math.cos(2 * math.pi * t);
    return base * math.sqrt(base);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = phase.value;
    final w = size.width;
    final h = size.height;
    final midY = h * 0.62;
    final amp = h * 0.30;

    final opacity = dim ? 0.22 : 1.0;

    // 波浪填充。
    final path = Path()..moveTo(0, h);
    for (double px = 0; px <= w; px += 3) {
      final s = px * 1.25 / w + p;
      final y = midY - amp * _swell(s);
      path.lineTo(px, y);
    }
    path.lineTo(w, h);
    path.close();

    final rect = Rect.fromLTWH(0, 0, w, h);
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        color.withOpacity(0.35 * opacity),
        color.withOpacity(0.02 * opacity),
      ],
    ).createShader(rect);
    final fillPaint = Paint()..shader = gradient;
    canvas.drawPath(path, fillPaint);

    // 波峰亮线。
    final linePaint = Paint()
      ..color = color.withOpacity(0.85 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final linePath = Path();
    var first = true;
    for (double px = 0; px <= w; px += 3) {
      final s = px * 1.25 / w + p;
      final y = midY - amp * _swell(s);
      if (first) {
        linePath.moveTo(px, y);
        first = false;
      } else {
        linePath.lineTo(px, y);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // 中央呼吸环：半径随浪涌胀缩，作为呼吸引导。
    final ringPhase = _swell(p);
    final ringR = h * 0.10 + h * 0.10 * ringPhase;
    final ringPaint = Paint()
      ..color = color.withOpacity((0.25 + 0.45 * ringPhase) * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(Offset(w / 2, h * 0.40), ringR, ringPaint);
    final corePaint = Paint()
      ..color = color.withOpacity((0.06 + 0.18 * ringPhase) * opacity);
    canvas.drawCircle(Offset(w / 2, h * 0.40), ringR * 0.85, corePaint);
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dim != dim;
}
