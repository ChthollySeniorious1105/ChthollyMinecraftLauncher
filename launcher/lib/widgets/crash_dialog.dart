import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../i18n/i18n.dart';
import '../state.dart';
import 'account.dart' show revealInExplorer, showLoginDialog;
import 'common.dart';

/// Crash analysis dialog: the most certain finding first with one-click fixes, other possible causes,
/// the relevant log lines, and the files that were read.
Future<void> showCrashDialog(BuildContext context, CrashReport r, {required String gameDir, String? versionId}) =>
    showDialog(context: context, builder: (_) => CrashDialog(report: r, gameDir: gameDir, versionId: versionId));

class CrashDialog extends StatefulWidget {
  final CrashReport report;
  final String gameDir;
  final String? versionId;
  const CrashDialog({super.key, required this.report, required this.gameDir, this.versionId});
  @override
  State<CrashDialog> createState() => _CrashDialogState();
}

class _CrashDialogState extends State<CrashDialog> {
  bool showLog = false;

  String get modsDir => p.join(widget.gameDir, 'mods');

  Future<void> _fix(CrashFix fix, CrashFinding f) async {
    final app = App.read(context);
    switch (fix) {
      case CrashFix.moreMemory:
      case CrashFix.changeJava:
        Navigator.pop(context);
        app.goTo(AppPage.settings);
      case CrashFix.installMod:
        app.pendingModSearch = f.mods.isEmpty ? null : f.mods.first;
        Navigator.pop(context);
        app.goTo(AppPage.download);
      case CrashFix.repairFiles:
        final id = widget.versionId;
        if (id == null) {
          Navigator.pop(context);
          app.goTo(AppPage.versions);
          return;
        }
        Navigator.pop(context);
        await app.runTask(trGlobal('补全 {0}', [id]), (t) => app.ctx.installer.completeFiles(app.ctx.gameDir, id, task: t));
      case CrashFix.removeMod:
        await _disableMods(f.mods);
      case CrashFix.openMods:
        await Directory(modsDir).create(recursive: true);
        await revealInExplorer(modsDir);
      case CrashFix.updateDriver:
        await Process.start('explorer.exe', ['ms-settings:windowsupdate-optionalupdates'], mode: ProcessStartMode.detached);
      case CrashFix.relogin:
        Navigator.pop(context);
        await showLoginDialog(context);
      case CrashFix.movePath:
        Navigator.pop(context);
        app.goTo(AppPage.settings);
    }
  }

  /// Renames the jars matching [mods] to `.disabled` (reversible from the version's Mod tab).
  Future<void> _disableMods(List<String> mods) async {
    final items = await LocalContent.list(modsDir, exts: const ['.jar', '.litemod']);
    final hits = <LocalContent>[];
    for (final it in items.where((i) => i.enabled)) {
      final file = it.displayName.toLowerCase();
      final meta = await it.readMeta();
      for (final m in mods) {
        final k = m.toLowerCase();
        if (file == k || (meta != null && meta.id.toLowerCase() == k) || (k.length >= 4 && file.contains(k.split('.').last))) {
          hits.add(it);
          break;
        }
      }
    }
    if (!mounted) return;
    if (hits.isEmpty) {
      toast(context, trGlobal('在 mods 文件夹里没有找到对应的 Mod，已打开文件夹'));
      await Directory(modsDir).create(recursive: true);
      await revealInExplorer(modsDir);
      return;
    }
    final ok = await confirm(context, trGlobal('禁用 Mod'), trGlobal('将禁用以下 Mod（文件改名为 .disabled，可在「版本 → Mod」中重新启用）：\n{0}', [hits.map((h) => h.displayName).join('\n')]),
        ok: trGlobal('禁用'));
    if (!ok) return;
    for (final h in hits) {
      await h.setEnabled(false);
    }
    if (mounted) toast(context, trGlobal('已禁用 {0} 个 Mod，可以重新启动游戏试试', [hits.length]));
  }

  String _fixLabel(CrashFix f) => switch (f) {
        CrashFix.moreMemory => trGlobal('调整内存'),
        CrashFix.changeJava => trGlobal('更换 Java'),
        CrashFix.installMod => trGlobal('去下载'),
        CrashFix.removeMod => trGlobal('禁用该 Mod'),
        CrashFix.repairFiles => trGlobal('补全文件'),
        CrashFix.updateDriver => trGlobal('检查驱动更新'),
        CrashFix.relogin => trGlobal('重新登录'),
        CrashFix.movePath => trGlobal('更改游戏目录'),
        CrashFix.openMods => trGlobal('打开 mods 文件夹'),
      };

  IconData _fixIcon(CrashFix f) => switch (f) {
        CrashFix.moreMemory => Icons.memory,
        CrashFix.changeJava => Icons.coffee_outlined,
        CrashFix.installMod => Icons.download_outlined,
        CrashFix.removeMod => Icons.block,
        CrashFix.repairFiles => Icons.build_outlined,
        CrashFix.updateDriver => Icons.system_update_alt,
        CrashFix.relogin => Icons.login,
        CrashFix.movePath => Icons.drive_file_move_outline,
        CrashFix.openMods => Icons.folder_open,
      };

  Widget _finding(CrashFinding f, {required bool primary}) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final label = switch (f.confidence) {
      CrashConfidence.certain => trGlobal('确定'),
      CrashConfidence.likely => trGlobal('很可能'),
      CrashConfidence.possible => trGlobal('可能'),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary ? cs.errorContainer : cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(primary ? Icons.report_rounded : Icons.help_outline, size: 20, color: primary ? cs.onErrorContainer : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(trCore(f.title), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: primary ? cs.onErrorContainer : null))),
          Pill(label, color: f.confidence == CrashConfidence.certain ? cs.error : cs.outline),
        ]),
        const SizedBox(height: 6),
        SelectableText(trCore(f.detail), style: TextStyle(color: primary ? cs.onErrorContainer : null, height: 1.45)),
        if (f.evidence.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(f.evidence, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Consolas', fontSize: 11, color: (primary ? cs.onErrorContainer : cs.onSurfaceVariant).withValues(alpha: 0.8))),
        ],
        if (f.fixes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in f.fixes)
              (primary ? FilledButton.icon : OutlinedButton.icon)(onPressed: () => _fix(x, f), icon: Icon(_fixIcon(x), size: 18), label: Text(_fixLabel(x))),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = widget.report;
    final all = [...r.findings];
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(trGlobal('游戏崩溃了'))),
        if (r.exitCode != null) Pill(trGlobal('退出码 {0}', [r.exitCode]), color: t.hintColor),
      ]),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (all.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                child: Text(trGlobal('没能自动判断原因。可以把下面的日志或崩溃报告发给 Mod 作者或在社区求助。')),
              )
            else ...[
              _finding(all.first, primary: true),
              if (all.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(trGlobal('其他可能的原因'), style: t.textTheme.labelLarge?.copyWith(color: t.hintColor)),
                ),
                for (final f in all.skip(1)) _finding(f, primary: false),
              ],
            ],
            if (r.description != null)
              Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(trGlobal('崩溃报告描述：{0}', [r.description]), style: t.textTheme.bodySmall)),
            InkWell(
              onTap: () => setState(() => showLog = !showLog),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(showLog ? Icons.expand_less : Icons.expand_more, size: 20),
                  const SizedBox(width: 4),
                  Text(trGlobal('关键日志（{0} 行）', [r.excerpt.length])),
                ]),
              ),
            ),
            if (showLog)
              Container(
                height: 220,
                decoration: BoxDecoration(color: const Color(0xFF14161B), borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: SelectableText(r.excerpt.isEmpty ? trGlobal('（没有异常信息）') : r.excerpt.join('\n'),
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 11, color: Color(0xFFCFD6E0), height: 1.35)),
                ),
              ),
            if (r.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in r.sources)
                  ActionChip(avatar: const Icon(Icons.description_outlined, size: 16), label: Text(p.basename(s)), onPressed: () => revealInExplorer(s)),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            final text = [
              for (final f in r.findings) '${f.title}：${f.detail}',
              if (r.description != null) 'Description: ${r.description}',
              ...r.excerpt,
            ].join('\n');
            Clipboard.setData(ClipboardData(text: text));
            toast(context, trGlobal('已复制'));
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(trGlobal('复制分析结果')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('关闭'))),
      ],
    );
  }
}
