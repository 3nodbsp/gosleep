import 'package:flutter/material.dart';

import '../audio/soundscape_synth.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// 设置页：专利算法参数（含专利默认值与取值范围）、音景、麦克风灵敏度、演示加速。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = state.params;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _sectionTitle(context, '催眠算法参数（对应专利 CN112972862A）'),
            _sliderTile(
              context,
              title: '预设呼吸值',
              subtitle: '呼吸降到该值以下视为入睡（专利默认 16，范围 12~18）',
              value: p.presetBreathRate.toDouble(),
              min: 12,
              max: 18,
              divisions: 6,
              unit: ' 次/分',
              formatWhole: true,
              onChanged: (v) => state.setPresetBreathRate(v.round()),
            ),
            _sliderTile(
              context,
              title: '诱导降频步长',
              subtitle: '缓和频率值 = 输出频率 − 步长（专利默认 1，范围 1~2）',
              value: p.stepBpm.toDouble(),
              min: 1,
              max: 2,
              divisions: 1,
              unit: ' 次/分',
              formatWhole: true,
              onChanged: (v) => state.setStepBpm(v.round()),
            ),
            _sliderTile(
              context,
              title: '评估周期 T1',
              subtitle: '每隔该时长重新采集呼吸并评估是否降频（专利默认 10 分钟）',
              value: p.presetIntervalMinutes.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              unit: ' 分钟',
              formatWhole: true,
              onChanged: (v) => state.setPresetIntervalMinutes(v.round()),
            ),
            _sliderTile(
              context,
              title: '深睡幅度阈值',
              subtitle: '呼吸幅度指数低于该值且呼吸足够慢时判定深睡（专利默认 8mm）',
              value: p.amplitudeThresholdMm,
              min: 4,
              max: 10,
              divisions: 6,
              unit: ' mm',
              formatWhole: true,
              onChanged: (v) => state.setAmplitudeThreshold(v.roundToDouble()),
            ),
            _sectionTitle(context, '音景与音量'),
            Card(
              color: kCardColor,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('催眠音景（白噪声类，实时合成）'),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<Soundscape>(
                        segments: const [
                          ButtonSegment(
                            value: Soundscape.ocean,
                            icon: Icon(Icons.waves, size: 18),
                            label: Text('海浪'),
                          ),
                          ButtonSegment(
                            value: Soundscape.rain,
                            icon: Icon(Icons.water_drop_outlined, size: 18),
                            label: Text('细雨'),
                          ),
                          ButtonSegment(
                            value: Soundscape.stream,
                            icon: Icon(Icons.air, size: 18),
                            label: Text('溪流'),
                          ),
                        ],
                        selected: {state.scape},
                        onSelectionChanged: (sel) =>
                            state.setScape(sel.first),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            _sliderTile(
              context,
              title: '音量',
              subtitle: '会话中也可随时调整',
              value: state.volume,
              min: 0,
              max: 1,
              divisions: 20,
              unit: '',
              formatWhole: false,
              onChanged: state.setVolume,
            ),
            _sectionTitle(context, '麦克风'),
            _sliderTile(
              context,
              title: '幅度灵敏度',
              subtitle: '呼吸声较轻时调高，更容易判定呼吸变浅（下次会话生效）',
              value: state.sensitivity,
              min: 0.5,
              max: 2.0,
              divisions: 6,
              unit: '×',
              formatWhole: false,
              onChanged: state.setSensitivity,
            ),
            _sectionTitle(context, '演示与数据'),
            Card(
              color: kCardColor,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                title: const Text('演示加速（60×）'),
                subtitle: const Text(
                  '将评估周期压缩 60 倍用于快速演示算法闭环（如 10 分钟周期 → 10 秒）。\n'
                  '校准采集与深睡持续判定仍按真实时间。',
                ),
                value: state.demoAccelerated,
                onChanged: (v) => state.setDemoAccelerated(v),
              ),
            ),
            Card(
              color: kCardColor,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                title: const Text('清除全部会话记录'),
                leading: const Icon(Icons.delete_outline),
                onTap: () => _confirmClear(context),
              ),
            ),
            _aboutCard(context),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Colors.white60, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sliderTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required bool formatWhole,
    required ValueChanged<double> onChanged,
  }) {
    final shown = formatWhole
        ? value.round().toString()
        : value.toStringAsFixed(2);
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                Text('$shown$unit',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 11, color: Colors.white38)),
            Slider(
              value: value < min ? min : (value > max ? max : value),
              min: min,
              max: max,
              divisions: divisions,
              label: shown,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return Card(
      color: kCardColor,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('关于', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 6),
            Text(
              '本 APP 实现专利 CN112972862A《催眠音乐控制方法、装置、计算机设备和存储介质》'
              '的核心算法：采集呼吸频率 → 音乐节奏同步跟随 → 按预设周期诱导降频 → '
              '呼吸频率与起伏达标后判定深睡并停止音乐。\n'
              '呼吸采集原方案为 UWB 脉冲雷达，本 APP 以麦克风呼吸音频估算替代。\n\n'
              '本应用为助眠工具，不构成医疗建议；如有睡眠障碍请咨询医生。',
              style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除会话记录'),
        content: const Text('将删除全部历史会话与报告，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok == true) await state.clearHistory();
  }
}
