import 'package:cml_core/cml_core.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../state.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';
import 'saves_page.dart';

class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) => const PageBody(children: [
        _StructureTool(),
        _PackTool(),
        _ChunkerTool(),
        _MemoryTool(),
      ]);
}

// ============================ structure formats ============================

class _StructureTool extends StatefulWidget {
  const _StructureTool();
  @override
  State<_StructureTool> createState() => _StructureToolState();
}

class _StructureToolState extends State<_StructureTool> {
  final files = <String>[];
  StructureFormat target = StructureFormat.mcstructure;
  final results = <String, String>{};
  bool dragging = false;
  Structure? preview;
  String? previewName;

  static const _exts = ['schematic', 'schem', 'litematic', 'nbt', 'mcstructure', 'bdx'];

  void _add(Iterable<String> paths) {
    setState(() {
      for (final f in paths) {
        if (StructureFormat.fromPath(f) != null && !files.contains(f)) files.add(f);
      }
    });
  }

  Future<void> _convert() async {
    final app = App.read(context);
    String? outDir;
    if (files.length > 1) outDir = await getDirectoryPath(confirmButtonText: '输出到此文件夹');
    await app.runTask('转换 ${files.length} 个建筑文件', (t) async {
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        t.update(progress: i / files.length, detail: p.basename(f));
        try {
          final r = await StructureConverter.convertFile(f, target, outDir: outDir);
          results[f] = '✓ ${p.basename(r.output)}  ${r.sx}×${r.sy}×${r.sz}，${r.blocks} 个方块${r.crossEdition ? '（已转换 Java ⇄ 基岩版方块）' : ''}';
        } catch (e) {
          results[f] = '✗ ${errText(e)}';
        }
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Section(
      title: '建筑文件格式转换',
      icon: Icons.view_in_ar_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('支持 .schematic（MCEdit）、.schem（WorldEdit/Sponge）、.litematic（投影）、.nbt（原版结构方块）、.mcstructure（基岩版结构）、.bdx（FastBuilder）互相转换。'
            'Java 与基岩版之间转换时自动映射方块。'),
        const SizedBox(height: 12),
        DropTarget(
          onDragEntered: (_) => setState(() => dragging = true),
          onDragExited: (_) => setState(() => dragging = false),
          onDragDone: (d) {
            setState(() => dragging = false);
            _add(d.files.map((f) => f.path));
          },
          child: Container(
            height: files.isEmpty ? 90 : null,
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: dragging ? t.colorScheme.primary : t.dividerColor, width: dragging ? 2 : 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: files.isEmpty
                ? const Center(child: Text('拖入建筑文件，或点击「添加文件」'))
                : ListView(shrinkWrap: true, children: [
                    for (final f in files)
                      ListTile(
                        dense: true,
                        leading: Pill(p.extension(f).substring(1)),
                        title: Text(p.basename(f)),
                        subtitle: results[f] == null ? null : Text(results[f]!, style: TextStyle(color: results[f]!.startsWith('✗') ? t.colorScheme.error : Colors.green)),
                        trailing: Wrap(children: [
                          IconButton(
                            icon: const Icon(Icons.info_outline, size: 18),
                            tooltip: '查看信息 / 材料清单',
                            onPressed: () {
                              try {
                                final s = StructureConverter.load(f);
                                setState(() {
                                  preview = s;
                                  previewName = p.basename(f);
                                });
                              } catch (e) {
                                toast(context, errText(e), error: true);
                              }
                            },
                          ),
                          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => files.remove(f))),
                        ]),
                      ),
                  ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加文件'),
            onPressed: () async {
              final fs = await openFiles(acceptedTypeGroups: const [XTypeGroup(label: '建筑文件', extensions: _exts)]);
              _add(fs.map((f) => f.path));
            },
          ),
          const SizedBox(width: 16),
          const Text('转换为'),
          const SizedBox(width: 8),
          DropdownButton<StructureFormat>(
            value: target,
            items: [for (final f in StructureFormat.values) DropdownMenuItem(value: f, child: Text('${f.label} (.${f.ext})'))],
            onChanged: (v) => setState(() => target = v!),
          ),
          const Spacer(),
          FilledButton.icon(icon: const Icon(Icons.transform, size: 16), label: const Text('开始转换'), onPressed: files.isEmpty ? null : _convert),
        ]),
        if (preview != null) ...[
          const Divider(height: 24),
          Text('$previewName：${preview!.sx}×${preview!.sy}×${preview!.sz}，${preview!.blockCount} 个方块，${preview!.blockEntities.length} 个方块实体，${preview!.entities.length} 个实体',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in preview!.materials().entries.take(40)) Chip(visualDensity: VisualDensity.compact, label: Text('${e.key.replaceFirst('minecraft:', '')} × ${e.value}')),
          ]),
        ],
      ]),
    );
  }
}

// ============================ resource packs ============================

class _PackTool extends StatefulWidget {
  const _PackTool();
  @override
  State<_PackTool> createState() => _PackToolState();
}

class _PackToolState extends State<_PackTool> {
  String? input;
  String? detected;
  PackTarget target = PackTarget.all[1];
  SkyMode sky = SkyMode.both;
  PackConvertReport? report;
  bool dragging = false;

  Future<void> _pick(String path) async {
    setState(() {
      input = path;
      detected = null;
      report = null;
    });
    try {
      final pack = await ResourcePackConverter.read(path);
      if (mounted) setState(() => detected = ResourcePackConverter.describe(pack));
    } catch (e) {
      if (mounted) setState(() => detected = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    final targets = PackTarget.all;
    return Section(
      title: '资源包转换',
      icon: Icons.palette_outlined,
      subtitle: 'Java 任意版本互转 · Java ⇄ 基岩版 · OptiFine ⇄ Nuit 天空 · 贴图切分/拼合、模型引用、CTM/CIT 一并迁移',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropTarget(
          onDragEntered: (_) => setState(() => dragging = true),
          onDragExited: (_) => setState(() => dragging = false),
          onDragDone: (d) {
            setState(() => dragging = false);
            if (d.files.isNotEmpty) _pick(d.files.first.path);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: dragging ? t.colorScheme.primary : t.dividerColor, width: dragging ? 2 : 1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(input == null ? Icons.upload_file_rounded : Icons.inventory_2_rounded, size: 32, color: t.colorScheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(input == null ? '拖入资源包（.zip / .mcpack / 文件夹），或点击右侧选择' : p.basename(input!), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (detected != null) Text('识别为：$detected', style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                ]),
              ),
              TextButton(
                onPressed: () async {
                  final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '资源包', extensions: ['zip', 'mcpack'])]);
                  if (f != null) _pick(f.path);
                },
                child: const Text('选择文件'),
              ),
              TextButton(
                onPressed: () async {
                  final d = await getDirectoryPath();
                  if (d != null) _pick(d);
                },
                child: const Text('选择文件夹'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Text('转换为'),
          const SizedBox(width: 10),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<PackTarget>(
              initialValue: target,
              isExpanded: true,
              items: [for (final x in targets) DropdownMenuItem(value: x, child: Text(x.label))],
              onChanged: (v) => setState(() => target = v!),
            ),
          ),
          const SizedBox(width: 20),
          if (!target.bedrock) ...[
            const Text('天空'),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<SkyMode>(
                initialValue: sky,
                isExpanded: true,
                items: [for (final s in SkyMode.values) DropdownMenuItem(value: s, child: Text(s.label))],
                onChanged: (v) => setState(() => sky = v!),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 12),
          FilledButton.icon(
            icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
            label: const Text('开始转换'),
            onPressed: input == null
                ? null
                : () async {
                    final r = await app.runTask('转换资源包 → ${target.label}', (_) => ResourcePackConverter.convert(input!, target, sky: sky),
                        onError: (e) => toast(context, errText(e), error: true));
                    if (r != null && mounted) setState(() => report = r);
                  },
          ),
        ]),
        if (report != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('${report!.from} → ${report!.to}', style: const TextStyle(fontWeight: FontWeight.w700))),
                TextButton.icon(icon: const Icon(Icons.folder_open, size: 16), label: const Text('打开所在文件夹'), onPressed: () => revealInExplorer(report!.output)),
              ]),
              Text(report!.output, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in report!.log.counts.entries) Chip(visualDensity: VisualDensity.compact, label: Text('${e.key} ${e.value}')),
                if (report!.log.counts.isEmpty) const Chip(visualDensity: VisualDensity.compact, label: Text('没有需要迁移的内容')),
              ]),
              for (final n in report!.log.notes)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(n.warning ? Icons.warning_amber_rounded : Icons.info_outline_rounded, size: 16, color: n.warning ? Colors.orange : t.hintColor),
                    const SizedBox(width: 6),
                    Expanded(child: Text(n.text, style: t.textTheme.bodySmall)),
                  ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ============================ Chunker ============================

class _ChunkerTool extends StatefulWidget {
  const _ChunkerTool();
  @override
  State<_ChunkerTool> createState() => _ChunkerToolState();
}

class _ChunkerToolState extends State<_ChunkerTool> {
  String? version;

  @override
  void initState() {
    super.initState();
    App.read(context).ctx.chunker.installedVersion().then((v) {
      if (mounted) setState(() => version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final ch = app.ctx.chunker;
    return Section(
      title: 'Chunker 存档转换',
      icon: Icons.swap_horiz_rounded,
      actions: [
        Text(version == null ? '未安装' : '已安装 $version', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () async {
            await app.runTask('更新 Chunker', (t) async {
              final r = await ch.checkUpdate();
              if (r == null) return;
              await ch.update(release: r, task: t);
            }, onError: (e) => toast(context, errText(e), error: true));
            version = await ch.installedVersion();
            if (mounted) setState(() {});
          },
          child: Text(version == null ? '下载' : '检查更新'),
        ),
      ],
      child: Row(children: [
        const Expanded(child: Text('在 Java 版与基岩版之间、或不同游戏版本之间转换整个存档（HiveGamesOSS/Chunker，随 GitHub 版本自动更新）。也可以在「存档」页对某个存档直接转换。')),
        const SizedBox(width: 12),
        FilledButton(onPressed: () => showDialog(context: context, builder: (_) => const ChunkerDialog()), child: const Text('转换存档')),
      ]),
    );
  }
}

// ============================ memory ============================

class _MemoryTool extends StatefulWidget {
  const _MemoryTool();
  @override
  State<_MemoryTool> createState() => _MemoryToolState();
}

class _MemoryToolState extends State<_MemoryTool> {
  OptimizeResult? last;

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final m = Memory.info();
    return Section(
      title: '内存优化',
      icon: Icons.memory_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('已用 ${(m.usedMb / 1024).toStringAsFixed(1)} GB / 共 ${(m.totalMb / 1024).toStringAsFixed(1)} GB，可用 ${(m.availableMb / 1024).toStringAsFixed(1)} GB'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: m.loadPercent / 100, minHeight: 8, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 12),
        Row(children: [
          FilledButton.icon(
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: const Text('立即优化'),
            onPressed: () async {
              final r = await app.runTask('内存优化', (_) => Memory.optimize(pids: [?app.running?.pid], purgeStandby: app.settings.purgeStandbyMemory));
              if (mounted) setState(() => last = r);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              last == null
                  ? '整理 CML 和正在运行的游戏的内存，把暂时不用的部分交还系统。只影响 CML 自己启动的进程。'
                  : '可用内存增加约 ${last!.freedMb} MB${last!.standbyCleared ? '，并清理了系统缓存' : ''}。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
        SwitchRow('同时清理系统待机缓存', app.settings.purgeStandbyMemory, (v) async {
          if (v && !await confirm(context, '清理系统待机缓存', '这会让 Windows 丢弃所有程序的文件缓存（之后会重新读取），需要以管理员身份运行 CML。确定开启？')) return;
          app.settings.purgeStandbyMemory = v;
          app.saveSettings();
        }, help: '默认关闭。仅在以管理员身份运行时生效'),
        SwitchRow('启动游戏前自动优化', app.settings.optimizeMemoryBeforeLaunch, (v) {
          app.settings.optimizeMemoryBeforeLaunch = v;
          app.saveSettings();
        }),
      ]),
    );
  }
}
