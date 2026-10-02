import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import 'package:path/path.dart' as p;

import '../state.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';

/// Java + Bedrock world management and Chunker conversion.
class SavesPage extends StatefulWidget {
  const SavesPage({super.key});
  @override
  State<SavesPage> createState() => _SavesPageState();
}

class _SavesPageState extends State<SavesPage> {
  Edition edition = Edition.java;
  List<WorldInfo> worlds = [];
  bool loading = true;
  String filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final app = App.read(context);
    final out = <WorldInfo>[];
    if (edition == Edition.java) {
      final dir = app.ctx.gameDir;
      out.addAll(await Worlds.listJava(p.join(dir.root, 'saves'), location: trGlobal('公共（.minecraft）')));
      for (final v in await dir.list()) {
        final s = p.join(dir.versionDir(v.id), 'saves');
        if (await Directory(s).exists()) out.addAll(await Worlds.listJava(s, location: v.id));
      }
      out.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    } else {
      out.addAll(await Worlds.listBedrock());
    }
    if (mounted) {
      setState(() {
        worlds = out;
        loading = false;
      });
    }
  }

  Future<void> _import() async {
    final app = App.read(context);
    final f = await openFile(acceptedTypeGroups: [XTypeGroup(label: trGlobal('存档'), extensions: ['zip', 'mcworld'])]);
    if (f == null || !mounted) return;
    String dest;
    if (edition == Edition.bedrock) {
      final roots = BedrockPaths.roots();
      if (roots.isEmpty) return toast(context, trGlobal('没有找到基岩版存档目录（请先启动一次基岩版）'), error: true);
      dest = roots.first.worlds;
    } else {
      final versions = await app.ctx.gameDir.list();
      if (!mounted) return;
      final pick = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(title: Text(trGlobal('导入到')), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: Text(trGlobal('公共存档（.minecraft/saves）'))),
          for (final v in versions) SimpleDialogOption(onPressed: () => Navigator.pop(c, v.id), child: Text(v.id)),
        ]),
      );
      if (pick == null) return;
      dest = pick.isEmpty ? p.join(app.ctx.gameDir.root, 'saves') : p.join(app.ctx.gameDir.versionDir(pick), 'saves');
    }
    await app.runTask(trGlobal('导入存档'), (t) => Worlds.import(f.path, dest), onError: (e) => toast(context, errText(e), error: true));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = worlds.where((w) => filter.isEmpty || w.name.toLowerCase().contains(filter)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          SegmentedButton<Edition>(
            segments: [ButtonSegment(value: Edition.java, label: Text(trGlobal('Java 版'))), ButtonSegment(value: Edition.bedrock, label: Text(trGlobal('基岩版')))],
            selected: {edition},
            onSelectionChanged: (s) {
              setState(() => edition = s.first);
              _load();
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: TextField(decoration: InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: trGlobal('搜索存档')), onChanged: (v) => setState(() => filter = v.toLowerCase()))),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.file_download_outlined, size: 16), label: Text(trGlobal('导入')), onPressed: _import),
          const SizedBox(width: 8),
          OutlinedButton.icon(icon: const Icon(Icons.folder_zip_outlined, size: 16), label: Text(trGlobal('备份目录')), onPressed: () async {
            await Directory(Worlds.backupDir).create(recursive: true);
            await revealInExplorer(Worlds.backupDir);
          }),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ]),
      ),
      if (loading) const LinearProgressIndicator(),
      Expanded(
        child: shown.isEmpty && !loading
            ? EmptyHint(Icons.public_off_outlined, edition == Edition.java ? trGlobal('没有找到 Java 版存档') : trGlobal('没有找到基岩版存档\n（基岩版需从 Microsoft Store 安装并至少进入过一次游戏）'))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 420, mainAxisExtent: 112, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: shown.length,
                itemBuilder: (_, i) => _WorldCard(world: shown[i], onChanged: _load),
              ),
      ),
    ]);
  }
}

class _WorldCard extends StatelessWidget {
  final WorldInfo world;
  final VoidCallback onChanged;
  const _WorldCard({required this.world, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final app = App.of(context);
    final w = world;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: w.icon != null
                ? Image.file(w.icon!, width: 88, height: 88, fit: BoxFit.cover, filterQuality: FilterQuality.none, errorBuilder: (_, _, _) => _placeholder(t))
                : _placeholder(t),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(w.name, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 2, children: [
                Pill(w.version ?? trGlobal('未知版本')),
                Pill(trCore(w.gameModeLabel), color: w.hardcore ? Colors.red : Colors.teal),
                if (w.cheats) Pill(trGlobal('作弊'), color: Colors.orange),
              ]),
              const SizedBox(height: 4),
              Text('${trCore(w.location)}  ·  ${fmtDate(w.lastPlayed)}', style: t.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _action(context, app, v),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'open', child: Text(trGlobal('打开文件夹'))),
              PopupMenuItem(value: 'rename', child: Text(trGlobal('重命名'))),
              PopupMenuItem(value: 'mode', child: Text(trGlobal('修改游戏模式 / 作弊'))),
              PopupMenuItem(value: 'backup', child: Text(trGlobal('备份'))),
              PopupMenuItem(value: 'export', child: Text(trGlobal('导出'))),
              PopupMenuItem(value: 'convert', child: Text(trGlobal('转换版本（Chunker）'))),
              if (w.edition == Edition.java) PopupMenuItem(value: 'copy', child: Text(trGlobal('复制到其他版本'))),
              PopupMenuItem(value: 'delete', child: Text(trGlobal('删除'))),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(ThemeData t) => Container(width: 88, height: 88, color: t.colorScheme.surfaceContainerHighest, child: const Icon(Icons.public, size: 36));

  Future<void> _action(BuildContext context, AppState app, String v) async {
    final w = world;
    void fail(Object e) => toast(context, errText(e), error: true);
    switch (v) {
      case 'open':
        await revealInExplorer(w.path);
      case 'rename':
        final n = await prompt(context, trGlobal('存档名称'), initial: w.name);
        if (n == null || n.trim().isEmpty) return;
        await app.runTask(trGlobal('重命名存档'), (_) => Worlds.rename(w, n.trim()), onError: fail);
        onChanged();
      case 'mode':
        if (!context.mounted) return;
        await showDialog(context: context, builder: (_) => _ModeDialog(world: w));
        onChanged();
      case 'backup':
        final out = await app.runTask(trGlobal('备份 {0}', [w.name]), (_) => Worlds.backup(w), onError: fail);
        if (out != null && context.mounted) toast(context, trGlobal('已备份到 {0}', [out]));
      case 'export':
        final d = await getDirectoryPath(confirmButtonText: trGlobal('导出到此处'));
        if (d == null) return;
        final out = await app.runTask(trGlobal('导出 {0}', [w.name]), (_) => Worlds.export(w, d), onError: fail);
        if (out != null) await revealInExplorer(out);
      case 'copy':
        final versions = await app.ctx.gameDir.list();
        if (!context.mounted) return;
        final pick = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(title: Text(trGlobal('复制到')), children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(c, ''), child: Text(trGlobal('公共存档'))),
            for (final v in versions) SimpleDialogOption(onPressed: () => Navigator.pop(c, v.id), child: Text(v.id)),
          ]),
        );
        if (pick == null) return;
        final dest = pick.isEmpty ? p.join(app.ctx.gameDir.root, 'saves') : p.join(app.ctx.gameDir.versionDir(pick), 'saves');
        await app.runTask(trGlobal('复制存档'), (_) => Worlds.copy(w, dest), onError: fail);
        onChanged();
      case 'convert':
        if (!context.mounted) return;
        await showDialog(context: context, builder: (_) => ChunkerDialog(world: w));
        onChanged();
      case 'delete':
        if (!context.mounted) return;
        if (await confirm(context, trGlobal('删除存档'), trGlobal('删除「{0}」？删除前会自动备份到 CML 备份目录。', [w.name]), danger: true, ok: trGlobal('删除'))) {
          await app.runTask(trGlobal('删除 {0}', [w.name]), (_) => Worlds.delete(w), onError: fail);
          onChanged();
        }
    }
  }
}

class _ModeDialog extends StatefulWidget {
  final WorldInfo world;
  const _ModeDialog({required this.world});
  @override
  State<_ModeDialog> createState() => _ModeDialogState();
}

class _ModeDialogState extends State<_ModeDialog> {
  late int mode = widget.world.gameMode;
  late bool cheats = widget.world.cheats;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(trGlobal('游戏模式')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          RadioGroup<int>(
            groupValue: mode,
            onChanged: (v) => setState(() => mode = v!),
            child: Column(children: [
              for (final (v, l) in [(0, trGlobal('生存')), (1, trGlobal('创造')), (2, trGlobal('冒险')), (3, trGlobal('旁观'))]) RadioListTile<int>(dense: true, value: v, title: Text(l)),
            ]),
          ),
          SwitchListTile(value: cheats, title: Text(trGlobal('允许作弊')), onChanged: (v) => setState(() => cheats = v)),
          Text(trGlobal('只修改世界默认设置；玩家自己的模式保存在玩家数据中。修改前会自动备份。'), style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('取消'))),
          FilledButton(
            onPressed: () async {
              try {
                await Worlds.setOptions(widget.world, gameMode: mode, cheats: cheats);
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) toast(context, errText(e), error: true);
              }
            },
            child: Text(trGlobal('保存')),
          ),
        ],
      );
}

/// World conversion via Chunker (Java ⇄ Bedrock, any supported version).
class ChunkerDialog extends StatefulWidget {
  final WorldInfo? world;
  const ChunkerDialog({super.key, this.world});
  @override
  State<ChunkerDialog> createState() => _ChunkerDialogState();
}

class _ChunkerDialogState extends State<ChunkerDialog> {
  List<String>? formats;
  String? format;
  String? input;
  String? outputDir;
  String? error;
  String? version;

  @override
  void initState() {
    super.initState();
    input = widget.world?.path;
    _prepare();
  }

  JavaInstall? get java => App.read(context).ctx.java.pick(21) ?? App.read(context).ctx.java.pick(17);

  Future<void> _prepare() async {
    final app = App.read(context);
    final ch = app.ctx.chunker;
    version = await ch.installedVersion();
    if (!ch.installed) {
      if (mounted) setState(() {});
      return;
    }
    final j = java;
    if (j == null) {
      setState(() => error = trGlobal('Chunker 需要 Java 17 或更高版本，请先在「下载 → Java」中安装'));
      return;
    }
    try {
      final f = await ch.formats(j.path);
      if (!mounted) return;
      setState(() {
        formats = f;
        final want = widget.world?.edition == Edition.java ? 'BEDROCK_' : 'JAVA_';
        format = f.firstWhere((x) => x.startsWith(want), orElse: () => f.first);
      });
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final ch = app.ctx.chunker;
    return AlertDialog(
      title: Text(trGlobal('存档转换（Chunker{0}）', [version == null ? '' : ' $version'])),
      content: SizedBox(
        width: 560,
        child: !ch.installed
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(trGlobal('Chunker 是 Hive Games 开源的 Java ⇄ 基岩版存档转换工具。CML 会从 GitHub 下载其命令行版本（约 30 MB），并在有新版本时自动更新。')),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(trGlobal('下载 Chunker')),
                  onPressed: () async {
                    await app.runTask(trGlobal('下载 Chunker'), (t) => ch.update(task: t), onError: (e) => toast(context, errText(e), error: true));
                    _prepare();
                  },
                ),
              ])
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                FieldRow(
                  trGlobal('输入存档'),
                  Row(children: [
                    Expanded(child: Text(input ?? trGlobal('未选择'), overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () async {
                        final d = await getDirectoryPath(confirmButtonText: trGlobal('选择存档文件夹'));
                        if (d != null) setState(() => input = d);
                      },
                      child: Text(trGlobal('选择')),
                    ),
                  ]),
                ),
                FieldRow(
                  trGlobal('目标格式'),
                  formats == null
                      ? const LinearProgressIndicator()
                      : DropdownButton<String>(
                          isExpanded: true,
                          value: format,
                          items: [for (final f in formats!) DropdownMenuItem(value: f, child: Text(_label(f)))],
                          onChanged: (v) => setState(() => format = v),
                        ),
                ),
                FieldRow(
                  trGlobal('输出到'),
                  Row(children: [
                    Expanded(child: Text(outputDir ?? trGlobal('自动（与原存档同目录）'), overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () async {
                        final d = await getDirectoryPath();
                        if (d != null) setState(() => outputDir = d);
                      },
                      child: Text(trGlobal('选择')),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(trGlobal('转换会生成新的存档文件夹，原存档不会被修改。'), style: TextStyle(fontSize: 12)),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(trGlobal('关闭'))),
        if (ch.installed)
          FilledButton(
            onPressed: input == null || format == null
                ? null
                : () {
                    final out = p.join(outputDir ?? p.dirname(input!), '${p.basename(input!)} (${_label(format!)})');
                    final j = java!;
                    Navigator.pop(context);
                    app.runTask(trGlobal('转换存档 → {0}', [_label(format!)]), (t) async {
                      await ch.convert(java: j, input: input!, output: out, format: format!, task: t);
                      await revealInExplorer(out);
                    }, onError: (e) => toast(context, errText(e), error: true));
                  },
            child: Text(trGlobal('开始转换')),
          ),
      ],
    );
  }

  static String _label(String f) {
    final parts = f.split('_');
    return '${parts.first == 'JAVA' ? 'Java' : '基岩版'} ${parts.skip(1).join('.')}';
  }
}
