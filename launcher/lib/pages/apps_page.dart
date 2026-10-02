import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'modules_page.dart';

/// Built-in desktop apps shipped with CML. They follow the CML theme through theme.json.
class AppsPage extends StatelessWidget {
  const AppsPage({super.key});

  static List<_AppEntry> get _entries => [
        _AppEntry('desktoppet', trGlobal('桌面宠物'), trGlobal('桌宠养成、20+ 小游戏、番茄钟、待办、键鼠看板'), Icons.pets_outlined, Color(0xFFFF8A65)),
        _AppEntry('liteeditor', trGlobal('轻量编辑器'), trGlobal('图像 / 几何画板 / 文档 / 表格 / 演示 / 视频 / MIDI'), Icons.edit_note_outlined, Color(0xFF7C5CFF)),
        _AppEntry('litereader', trGlobal('轻量阅读器'), trGlobal('电子书、PDF、Office、音视频、压缩包阅读与格式转换'), Icons.menu_book_outlined, Color(0xFF26A69A)),
        _AppEntry('lumikeymapper', trGlobal('键鼠映射'), trGlobal('键盘、鼠标、滚轮单键映射，按应用生效'), Icons.keyboard_alt_outlined, Color(0xFF42A5F5), exe: Bundled.lumiKeyMapper),
      ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return PageBody(children: [
      LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth > 900 ? 2 : 1;
          final w = (c.maxWidth - (cols - 1) * 16) / cols;
          return Wrap(spacing: 16, runSpacing: 16, children: [for (final e in _entries) SizedBox(width: w, child: _AppCard(e))]);
        },
      ),
      Section(
        title: trGlobal('分包'),
        icon: Icons.inventory_2_outlined,
        subtitle: trGlobal('大体积 AI 模型权重单独下载，按需安装'),
        actions: [FilledButton.tonalIcon(onPressed: () => showAddonsDialog(context), icon: const Icon(Icons.download_outlined), label: Text(trGlobal('管理分包')))],
        child: Text(trGlobal('主题统一由 CML 管理：在「设置 → 外观」切换后，所有内置应用会实时跟随。'), style: TextStyle(color: t.hintColor)),
      ),
    ]);
  }
}

class _AppEntry {
  final String id;
  final String name;
  final String desc;
  final IconData icon;
  final Color color;
  final String? exe; // native exe; null = Electron app under apps\<id>
  const _AppEntry(this.id, this.name, this.desc, this.icon, this.color, {this.exe});

  bool get available => exe != null ? File(exe!).existsSync() : Bundled.hasApp(id);
}

class _AppCard extends StatelessWidget {
  final _AppEntry e;
  const _AppCard(this.e);

  Future<void> _open(BuildContext context) async {
    try {
      if (e.exe != null) {
        await Bundled.launchExe(e.exe!);
      } else {
        await Bundled.launchApp(e.id);
      }
      if (context.mounted) toast(context, trGlobal('正在启动 {0}', [e.name]));
    } catch (err) {
      if (context.mounted) toast(context, errText(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ok = e.available;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ok ? () => _open(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [e.color, Color.lerp(e.color, CmlColors.of(context).gradientB, 0.5)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: e.color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Icon(e.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(e.desc, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor), maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 12),
            ok
                ? FilledButton.icon(onPressed: () => _open(context), icon: const Icon(Icons.open_in_new, size: 18), label: Text(trGlobal('打开')))
                : Tooltip(message: trGlobal('此安装中缺少该应用，请重新下载完整版 CML'), child: Pill(trGlobal('缺失'), color: t.colorScheme.error)),
          ]),
        ),
      ),
    );
  }
}
