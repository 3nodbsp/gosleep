import 'package:flutter/material.dart';

import '../engine/engine_params.dart';
import '../engine/patent_engine.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'wave_widget.dart';

/// 睡眠页：会话控制、呼吸波浪引导、实时 Fa/Fb/幅度、信号质量。
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  Future<void> _start() async {
    try {
      await widget.state.startSession();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法开始会话：$e')),
      );
    }
  }

  Future<void> _stop() async {
    await widget.state.stopSession();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('会话已结束，报告已保存')),
    );
  }

  String _phaseLabel(SessionPhase p) {
    switch (p) {
      case SessionPhase.idle:
        return '准备就绪';
      case SessionPhase.calibrating:
        return '校准采集呼吸频率';
      case SessionPhase.syncFollowing:
        return '同步跟随 · 音乐节奏 = 您的呼吸';
      case SessionPhase.inducing:
        return '诱导降频 · 音乐节奏已下调';
      case SessionPhase.resyncing:
        return '重新同步 · 音乐节奏已跟随您的呼吸';
      case SessionPhase.deepSleep:
        return '深度睡眠 · 音乐已停止';
      case SessionPhase.stopped:
        return '会话已结束';
    }
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final engine = state.engine;
        final running = state.isRunning;
        final fa = engine.latestFa;
        final fb = engine.outputBpm;
        final amp = engine.latestAmp;
        final params = state.params;

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _buildPhaseCard(context, engine, params),
            const SizedBox(height: 4),
            BreathingWave(
              bpm: fb > 0 ? fb.toDouble() : 16,
              active: engine.isMusicPlaying,
            ),
            const SizedBox(height: 4),
            _buildMetricsRow(context, fa, fb, amp, params),
            _buildSignalCard(context, state, running),
            const SizedBox(height: 4),
            _buildControlCard(context, state, running),
            if (engine.phase == SessionPhase.idle) _buildTipsCard(context),
            if (engine.phase == SessionPhase.deepSleep) _buildDeepSleepCard(engine),
          ],
        );
      },
    );
  }

  Widget _buildPhaseCard(
    BuildContext context,
    PatentEngine engine,
    EngineParams params,
  ) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bedtime, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _phaseLabel(engine.phase),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _fmtDuration(engine.sessionElapsed),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white70,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            if (engine.phase == SessionPhase.calibrating) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: engine.calibrationProgress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                '安静呼吸，保持手机麦克风距您 30~50 厘米'
                '（有效信号 ${engine.goodSampleCount}/${params.calibrationSeconds} 秒）',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow(
    BuildContext context,
    double? fa,
    int fb,
    double? amp,
    EngineParams params,
  ) {
    Widget metric(String label, String value, String unit) {
      return Expanded(
        child: Card(
          color: kCardColor,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            metric(
              '实测呼吸 Fa',
              fa == null ? '--' : fa.toStringAsFixed(1),
              '次/分',
            ),
            metric('音乐节奏 Fb', fb > 0 ? '$fb' : '--', '次/分'),
          ],
        ),
        Card(
          color: kCardColor,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '呼吸幅度指数'
                        '（深睡判定阈值 ${params.amplitudeThresholdMm.toStringAsFixed(0)}）',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.white60),
                      ),
                    ),
                    Text(
                      amp == null ? '--' : amp.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: amp == null ? 0 : _clamp01(amp / 16),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                    backgroundColor: Colors.white12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSignalCard(
    BuildContext context,
    AppState state,
    bool running,
  ) {
    final level = state.liveLevel;
    String label;
    if (!running) {
      label = '未采集';
    } else if (level > 0.35) {
      label = '信号良好';
    } else if (level > 0.15) {
      label = '信号较弱，请靠近麦克风';
    } else {
      label = '信号过弱，请调整手机位置';
    }
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              level > 0.35
                  ? Icons.mic
                  : (level > 0.15 ? Icons.mic_none : Icons.mic_off),
              color: level > 0.35 ? Colors.tealAccent : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 5,
                    child: LinearProgressIndicator(
                      value: running ? level : 0,
                      minHeight: 5,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(
    BuildContext context,
    AppState state,
    bool running,
  ) {
    return Card(
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: running
              ? FilledButton.tonalIcon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('结束会话'),
                )
              : FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    state.engine.phase == SessionPhase.idle ? '开始催眠' : '再次开始',
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildTipsCard(BuildContext context) {
    return Card(
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('使用步骤',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _tip('1', '手机放在床头，麦克风朝向您的口鼻方向（30~50 厘米）。'),
            _tip('2', '点击“开始催眠”，安静呼吸，APP 采集 1 分钟校准呼吸频率。'),
            _tip('3', '校准完成即播放与您呼吸同节奏的音景，随后逐步诱导降频。'),
            _tip('4', '呼吸与幅度达到深睡标准后，音乐自动停止。'),
            const SizedBox(height: 8),
            Text(
              '说明：会话期间保持屏幕常亮以保证麦克风持续采集（系统限制，'
              '详见设置页与 README）；屏幕会以暗色显示降低干扰。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tip(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(n, style: const TextStyle(color: Colors.white38)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }

  Widget _buildDeepSleepCard(PatentEngine engine) {
    final at = engine.deepSleepAt;
    final dur = at == null || engine.sessionStart == null
        ? null
        : at.difference(engine.sessionStart!);
    return Card(
      color: kCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.nights_stay, color: Colors.tealAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '已进入深度睡眠，催眠音乐已停止',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (dur != null)
                    Text(
                      '入睡用时 ${_fmtDuration(dur)}，共降频 ${engine.stepDownCount} 次',
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
