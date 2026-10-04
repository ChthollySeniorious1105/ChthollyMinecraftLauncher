import 'package:flutter/material.dart';

import '../main.dart';
import '../i18n/aurora_i18n.dart';
import '../platform/sfx.dart';
import '../theme/themes.dart';
import '../widgets/chat_panel.dart';
import '../widgets/mahjong_table.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final v = app.voice;
    return Scaffold(
      appBar: AppBar(title: AuroraText('主题与设置')),
      body: ListenableBuilder(
        listenable: v,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (hostTheme != null) ...[
              const AuroraText(
                '界面主题',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              AuroraText('主题跟随 CML 启动器，在 CML「设置 → 外观」中切换。'),
            ] else ...[
              Text(
                '${context.at('界面主题')} (${auroraThemes.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in auroraThemes)
                    _ThemeTile(
                      t,
                      selected: t.id == app.themeId,
                      onTap: () => app.setTheme(t.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            const AuroraText(
              '界面缩放',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: app.uiScale,
              min: 0.8,
              max: 1.4,
              divisions: 6,
              label: '${(app.uiScale * 100).round()}%',
              onChanged: app.setUiScale,
            ),
            const SizedBox(height: 16),
            const AuroraText(
              '音效',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AuroraText('游戏音效'),
              subtitle: const AuroraText('轮到我、开局、胜利/失败、表情提示音'),
              value: app.sfx.enabled,
              onChanged: app.setSfx,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const AuroraText('音效音量'),
              trailing: SizedBox(
                width: 220,
                child: Slider(
                  value: app.sfx.volume.clamp(0.0, 1.0),
                  divisions: 10,
                  label: '${(app.sfx.volume * 100).round()}%',
                  onChanged: app.sfx.enabled ? app.setSfxVolume : null,
                  onChangeEnd: (_) => app.sfx.play(SfxKind.turn),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const AuroraText(
              '麻将',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: MjAutoState.doubleTap,
              builder: (context, dbl, _) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: const AuroraText('出牌方式'),
                subtitle: Text(
                  dbl
                      ? context.at('双击：先点选中，再点同一张打出')
                      : context.at('单击：点一下直接打出'),
                ),
                trailing: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: AuroraText('单击')),
                    ButtonSegment(value: true, label: AuroraText('双击')),
                  ],
                  selected: {dbl},
                  onSelectionChanged: (s) => MjAutoState.setDoubleTap(s.first),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const AuroraText(
              '语音',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const AuroraText('降噪强度'),
              subtitle: Text(
                context.at(
                  const ['关闭降噪', '轻度', '标准', '强力'][v.noiseLevel.round().clamp(
                    0,
                    3,
                  )],
                ),
              ),
              trailing: SizedBox(
                width: 220,
                child: Slider(
                  value: v.noiseLevel,
                  min: 0,
                  max: 3,
                  divisions: 3,
                  onChanged: app.setNoise,
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AuroraText('按键说话'),
              subtitle: AuroraText('开启后需按住房间内的“按住说话”按钮才会发送语音'),
              value: v.pushToTalk,
              onChanged: app.setPtt,
            ),
            const SizedBox(height: 16),
            const AuroraText(
              '语言',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh', label: AuroraText('简体中文')),
                ButtonSegment(value: 'en', label: AuroraText('English')),
              ],
              selected: {app.language},
              onSelectionChanged: (v) => app.setLanguage(v.first),
            ),
            const VolumeSliders(),
          ],
        ),
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final AuroraTheme t;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile(this.t, {required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 118,
        height: 78,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: t.background,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? t.primary : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _dot(t.primary),
                _dot(t.accent),
                _dot(t.table),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, color: t.primary, size: 18),
              ],
            ),
            const Spacer(),
            Text(
              t.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: t.dark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 14,
    height: 14,
    margin: const EdgeInsets.only(right: 4),
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white54),
    ),
  );
}
