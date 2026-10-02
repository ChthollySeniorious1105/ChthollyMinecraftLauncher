import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../state.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';
import '../widgets/favorites.dart';
import '../widgets/instance_tabs.dart';

/// Installed versions + per-instance settings, mods/resource packs/shaders management.
class VersionsPage extends StatefulWidget {
  const VersionsPage({super.key});
  @override
  State<VersionsPage> createState() => _VersionsPageState();
}

class _VersionsPageState extends State<VersionsPage> {
  List<InstalledVersion> versions = [];
  String? current;
  bool loading = true;

  /// null = all versions, otherwise the selected favourites folder.
  FavoriteFolder? folder;
  String filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = App.read(context);
    final v = await app.ctx.gameDir.list();
    if (!mounted) return;
    setState(() {
      versions = v;
      loading = false;
      if (current == null || !v.any((x) => x.id == current)) current = v.firstOrNull?.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    return Row(children: [
      SizedBox(
        width: 280,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: app.settings.gameDir,
                  items: [for (final d in app.settings.gameDirs) DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))],
                  onChanged: (d) async {
                    app.settings.gameDir = d!;
                    await app.saveSettings();
                    current = null;
                    _load();
                  },
                ),
              ),
              IconButton(
                tooltip: '添加游戏目录',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: () async {
                  final d = await getDirectoryPath(confirmButtonText: '选择 .minecraft 文件夹');
                  if (d == null) return;
                  if (!app.settings.gameDirs.contains(d)) app.settings.gameDirs.add(d);
                  app.settings.gameDir = d;
                  await app.saveSettings();
                  current = null;
                  _load();
                },
              ),
              IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: _load),
            ]),
          ),
          _FolderBar(selected: folder, onSelect: (f) => setState(() => folder = f)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: '搜索版本'),
              onChanged: (v) => setState(() => filter = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : Builder(builder: (context) {
                    final fav = app.ctx.favorites;
                    final dir = app.settings.gameDir;
                    var shown = versions.where((v) => filter.isEmpty || v.id.toLowerCase().contains(filter)).toList();
                    if (folder != null) {
                      shown = shown.where((v) => folder!.entries.contains(Favorites.key(dir, v.id))).toList();
                    } else {
                      // favourites first
                      shown.sort((a, b) => (fav.isFavorite(dir, b.id) ? 1 : 0).compareTo(fav.isFavorite(dir, a.id) ? 1 : 0));
                    }
                    if (shown.isEmpty) {
                      return EmptyHint(folder == null ? Icons.layers_clear_outlined : Icons.star_outline_rounded,
                          folder == null ? '没有已安装的版本' : '「${folder!.name}」里还没有当前游戏目录的版本\n点击版本右侧的星标即可收藏');
                    }
                    return ListView(padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                      for (final v in shown)
                        ListTile(
                          selected: v.id == current,
                          selectedTileColor: t.colorScheme.primary.withValues(alpha: 0.08),
                          contentPadding: const EdgeInsets.only(left: 12, right: 2),
                          title: Text(v.id, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            v.broken ? '版本文件损坏' : [v.version!.baseVersion, ...v.version!.loaders.map((l) => l.label)].join(' · '),
                            style: TextStyle(color: v.broken ? t.colorScheme.error : null),
                          ),
                          leading: Icon(v.version?.loaders.isNotEmpty == true ? Icons.extension_outlined : Icons.grass_outlined),
                          trailing: FavoriteStar(gameDir: dir, versionId: v.id),
                          onTap: () => setState(() => current = v.id),
                        ),
                    ]);
                  }),
          ),
        ]),
      ),
      const VerticalDivider(width: 1),
      Expanded(
        child: current == null
            ? const EmptyHint(Icons.layers_outlined, '选择左侧的版本')
            : _VersionDetail(key: ValueKey('${app.settings.gameDir}|$current'), id: current!, onChanged: _load),
      ),
    ]);
  }
}

class _VersionDetail extends StatefulWidget {
  final String id;
  final VoidCallback onChanged;
  const _VersionDetail({super.key, required this.id, required this.onChanged});
  @override
  State<_VersionDetail> createState() => _VersionDetailState();
}

class _VersionDetailState extends State<_VersionDetail> with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 9, vsync: this);
  InstanceSettings? inst;
  GameVersion? version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = App.read(context);
    final dir = app.ctx.gameDir;
    final i = await InstanceSettings.load(dir.instanceConfig(widget.id));
    GameVersion? v;
    try {
      v = await dir.load(widget.id);
    } catch (_) {}
    if (mounted) {
      setState(() {
        inst = i;
        version = v;
      });
    }
  }

  String get gameDir {
    final app = App.read(context);
    return app.ctx.gameDir.gameDirFor(widget.id, isolated: inst?.isolate ?? app.settings.isolateVersions);
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    if (inst == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Expanded(child: Text(widget.id, style: Theme.of(context).textTheme.titleLarge)),
          FavoriteStar(gameDir: app.settings.gameDir, versionId: widget.id, size: 24),
          const SizedBox(width: 6),
          OutlinedButton.icon(icon: const Icon(Icons.folder_open, size: 16), label: const Text('打开文件夹'), onPressed: () => revealInExplorer(gameDir)),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.build_outlined, size: 16),
            label: const Text('补全文件'),
            onPressed: () => app.runTask('补全 ${widget.id}', (t) => app.ctx.installer.completeFiles(app.ctx.gameDir, widget.id, task: t),
                onError: (e) => toast(context, errText(e), error: true)),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final dir = app.ctx.gameDir;
              switch (v) {
                case 'rename':
                  final n = await prompt(context, '重命名版本', initial: widget.id);
                  if (n == null || n.trim().isEmpty || n == widget.id) return;
                  try {
                    await dir.rename(widget.id, n.trim());
                    await app.ctx.favorites.onRenamed(dir.root, widget.id, n.trim());
                    widget.onChanged();
                  } catch (e) {
                    if (context.mounted) toast(context, errText(e), error: true);
                  }
                case 'export':
                  await showExportDialog(context, widget.id, gameDir);
                case 'script':
                  final acc = app.ctx.accounts.selected;
                  if (acc == null) return toast(context, '请先登录账号', error: true);
                  final loc = await getSaveLocation(suggestedName: '启动 ${widget.id}.bat');
                  if (loc == null) return;
                  final v = await dir.load(widget.id);
                  final j = await app.ctx.javaFor(v, inst!);
                  final cmd = await Launcher.build(dir, widget.id, LaunchIdentity(name: acc.name, uuid: acc.uuid, accessToken: acc.mcToken),
                      LaunchOptions(javaPath: j.path, maxMemoryMb: inst!.memoryMb ?? app.settings.memoryMb, isolated: inst!.isolate ?? app.settings.isolateVersions));
                  await File(loc.path).writeAsString(cmd.toBatch());
                  if (context.mounted) toast(context, '已导出（脚本中含登录令牌，请勿分享）');
                case 'delete':
                  if (await confirm(context, '删除版本', '确定删除 ${widget.id}？版本文件夹（包括其中的 Mod 和存档）将被删除。', danger: true, ok: '删除')) {
                    await dir.delete(widget.id);
                    await app.ctx.favorites.onDeleted(dir.root, widget.id);
                    widget.onChanged();
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'export', child: Text('导出为整合包 / 实例')),
              PopupMenuItem(value: 'script', child: Text('导出启动脚本')),
              PopupMenuItem(value: 'delete', child: Text('删除版本')),
            ],
          ),
        ]),
      ),
      TabBar(controller: tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
        Tab(text: '设置'),
        Tab(text: 'Mod'),
        Tab(text: '检查更新'),
        Tab(text: '资源包'),
        Tab(text: '光影'),
        Tab(text: '存档'),
        Tab(text: '服务器'),
        Tab(text: '截图'),
        Tab(text: '日志'),
      ]),
      Expanded(
        child: TabBarView(controller: tabs, children: [
          _InstanceSettingsTab(id: widget.id, inst: inst!, version: version, onSaved: () => setState(() {})),
          _LocalContentTab(folder: p.join(gameDir, 'mods'), kind: 'Mod', exts: const ['.jar'], readMeta: true),
          _UpdatesForAll(gameDir: gameDir, version: version),
          _LocalContentTab(folder: p.join(gameDir, 'resourcepacks'), kind: '资源包', exts: const ['.zip']),
          _LocalContentTab(folder: p.join(gameDir, 'shaderpacks'), kind: '光影', exts: const ['.zip']),
          _InstanceWorldsTab(savesDir: p.join(gameDir, 'saves'), location: widget.id),
          ServersTab(gameDir: gameDir, versionId: widget.id),
          ScreenshotsTab(gameDir: gameDir),
          LogsTab(gameDir: gameDir),
        ]),
      ),
    ]);
  }
}

class _InstanceSettingsTab extends StatefulWidget {
  final String id;
  final InstanceSettings inst;
  final GameVersion? version;
  final VoidCallback onSaved;
  const _InstanceSettingsTab({required this.id, required this.inst, required this.version, required this.onSaved});
  @override
  State<_InstanceSettingsTab> createState() => _InstanceSettingsTabState();
}

class _InstanceSettingsTabState extends State<_InstanceSettingsTab> {
  late final jvm = TextEditingController(text: widget.inst.jvmArgs ?? '');
  late final game = TextEditingController(text: widget.inst.gameArgs ?? '');
  late final server = TextEditingController(text: widget.inst.joinServer ?? '');

  Future<void> _save() async {
    final app = App.read(context);
    widget.inst
      ..jvmArgs = jvm.text.trim().isEmpty ? null : jvm.text.trim()
      ..gameArgs = game.text.trim().isEmpty ? null : game.text.trim()
      ..joinServer = server.text.trim().isEmpty ? null : server.text.trim();
    await widget.inst.save(app.ctx.gameDir.instanceConfig(widget.id));
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final i = widget.inst;
    final need = widget.version?.requiredJava;
    return PageBody(children: [
      Section(
        title: 'Java 与内存',
        icon: Icons.coffee_outlined,
        child: Column(children: [
          FieldRow(
            'Java',
            DropdownButton<String?>(
              isExpanded: true,
              value: i.javaPath,
              items: [
                DropdownMenuItem(value: null, child: Text('跟随全局设置${need == null ? '' : '（本版本需要 Java $need+）'}')),
                for (final j in app.ctx.java.installs) DropdownMenuItem(value: j.path, child: Text('${j.label}  ${j.path}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() => i.javaPath = v);
                _save();
              },
            ),
          ),
          FieldRow(
            '内存',
            Row(children: [
              DropdownButton<bool?>(
                value: i.autoMemory,
                items: const [
                  DropdownMenuItem(value: null, child: Text('跟随全局')),
                  DropdownMenuItem(value: true, child: Text('自动分配')),
                  DropdownMenuItem(value: false, child: Text('手动')),
                ],
                onChanged: (v) {
                  setState(() => i.autoMemory = v);
                  _save();
                },
              ),
              if (i.autoMemory == false) ...[
                Expanded(
                  child: Slider(
                    min: 512,
                    max: (Memory.info().totalMb ~/ 512 * 512).toDouble().clamp(1024, 65536),
                    divisions: (Memory.info().totalMb ~/ 512).clamp(1, 128) - 1,
                    value: (i.memoryMb ?? app.settings.memoryMb).toDouble().clamp(512, (Memory.info().totalMb ~/ 512 * 512).toDouble().clamp(1024, 65536)),
                    label: '${i.memoryMb ?? app.settings.memoryMb} MB',
                    onChanged: (v) => setState(() => i.memoryMb = v.round()),
                    onChangeEnd: (_) => _save(),
                  ),
                ),
                Text('${i.memoryMb ?? app.settings.memoryMb} MB'),
              ],
            ]),
          ),
          FieldRow(
            '版本隔离',
            DropdownButton<bool?>(
              value: i.isolate,
              items: const [
                DropdownMenuItem(value: null, child: Text('跟随全局')),
                DropdownMenuItem(value: true, child: Text('开启（Mod、存档等放在版本文件夹内）')),
                DropdownMenuItem(value: false, child: Text('关闭（共用 .minecraft）')),
              ],
              onChanged: (v) {
                setState(() => i.isolate = v);
                _save();
              },
            ),
          ),
        ]),
      ),
      Section(
        title: '高级',
        icon: Icons.code,
        child: Column(children: [
          FieldRow('附加 JVM 参数', TextField(controller: jvm, onEditingComplete: _save, decoration: const InputDecoration(hintText: '例如 -XX:+UseZGC'))),
          FieldRow('附加游戏参数', TextField(controller: game, onEditingComplete: _save)),
          FieldRow('启动后进入服务器', TextField(controller: server, onEditingComplete: _save, decoration: const InputDecoration(hintText: 'mc.example.com:25565'))),
          Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _save, child: const Text('保存'))),
        ]),
      ),
    ]);
  }
}

class _LocalContentTab extends StatefulWidget {
  final String folder;
  final String kind;
  final List<String> exts;
  final bool readMeta;
  const _LocalContentTab({required this.folder, required this.kind, required this.exts, this.readMeta = false});
  @override
  State<_LocalContentTab> createState() => _LocalContentTabState();
}

class _LocalContentTabState extends State<_LocalContentTab> {
  List<LocalContent> items = [];
  final meta = <String, ModMeta?>{};
  String filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await LocalContent.list(widget.folder, exts: widget.exts);
    if (!mounted) return;
    setState(() => items = l);
    if (widget.readMeta) {
      for (final i in l) {
        meta[i.file.path] = await i.readMeta();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = items.where((i) => filter.isEmpty || i.displayName.toLowerCase().contains(filter) || (meta[i.file.path]?.name.toLowerCase().contains(filter) ?? false)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: '搜索${widget.kind}（共 ${items.length} 个）'),
              onChanged: (v) => setState(() => filter = v.toLowerCase()),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加文件'),
            onPressed: () async {
              final fs = await openFiles(acceptedTypeGroups: [XTypeGroup(label: widget.kind, extensions: [for (final e in widget.exts) e.substring(1)])]);
              await Directory(widget.folder).create(recursive: true);
              for (final f in fs) {
                await File(f.path).copy(p.join(widget.folder, f.name));
              }
              _load();
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('文件夹'),
            onPressed: () async {
              await Directory(widget.folder).create(recursive: true);
              await revealInExplorer(widget.folder);
            },
          ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? EmptyHint(Icons.inventory_2_outlined, '没有${widget.kind}\n可在「下载」页搜索安装')
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final c = shown[i];
                  final m = meta[c.file.path];
                  return ListTile(
                    dense: true,
                    leading: Checkbox(
                      value: c.enabled,
                      onChanged: (v) async {
                        await c.setEnabled(v == true);
                        _load();
                      },
                    ),
                    title: Text(m?.name ?? c.displayName, style: TextStyle(decoration: c.enabled ? null : TextDecoration.lineThrough)),
                    subtitle: Text([if (m != null) m.version, c.displayName, if (m != null && m.description.isNotEmpty) m.description].join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: '删除',
                      onPressed: () async {
                        if (await confirm(context, '删除', '删除 ${c.displayName}？', danger: true, ok: '删除')) {
                          await c.file.delete();
                          _load();
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _InstanceWorldsTab extends StatefulWidget {
  final String savesDir;
  final String location;
  const _InstanceWorldsTab({required this.savesDir, required this.location});
  @override
  State<_InstanceWorldsTab> createState() => _InstanceWorldsTabState();
}

class _InstanceWorldsTabState extends State<_InstanceWorldsTab> {
  List<WorldInfo> worlds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await Worlds.listJava(widget.savesDir, location: widget.location);
    if (mounted) setState(() => worlds = w);
  }

  @override
  Widget build(BuildContext context) => worlds.isEmpty
      ? const EmptyHint(Icons.public_off_outlined, '这个版本还没有存档')
      : ListView(padding: const EdgeInsets.all(12), children: [
          for (final w in worlds)
            ListTile(
              leading: w.icon != null ? Image.file(w.icon!, width: 40, height: 40, filterQuality: FilterQuality.none) : const Icon(Icons.public, size: 40),
              title: Text(w.name),
              subtitle: Text('${w.version ?? '未知版本'} · ${w.gameModeLabel} · ${fmtDate(w.lastPlayed)}'),
              trailing: IconButton(icon: const Icon(Icons.folder_open, size: 18), onPressed: () => revealInExplorer(w.path)),
            ),
          const Padding(padding: EdgeInsets.all(8), child: Text('更多存档操作（备份、转换、导入导出）请到「存档」页。')),
        ]);
}


/// Horizontal folder chips: 全部 · each favourites folder · +.
class _FolderBar extends StatelessWidget {
  final FavoriteFolder? selected;
  final ValueChanged<FavoriteFolder?> onSelect;
  const _FolderBar({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final fav = app.ctx.favorites;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: const Text('全部'), selected: selected == null, onSelected: (_) => onSelect(null)),
          ),
          for (final f in fav.folders)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onSecondaryTapUp: (d) => _menu(context, f, d.globalPosition),
                child: ChoiceChip(
                  avatar: Icon(favoriteIcon(f), size: 16, color: Color(f.color)),
                  label: Text('${f.name} ${f.entries.length}'),
                  selected: identical(selected, f),
                  onSelected: (_) => onSelect(f),
                ),
              ),
            ),
          IconButton(
            tooltip: '新建收藏夹',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 20),
            onPressed: () async {
              final f = await editFavoriteFolder(context);
              if (f != null) onSelect(f);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _menu(BuildContext context, FavoriteFolder f, Offset pos) async {
    final app = App.read(context);
    final isDefault = identical(f, app.ctx.favorites.defaultFolder);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        const PopupMenuItem(value: 'edit', child: Text('重命名 / 图标')),
        if (!isDefault) const PopupMenuItem(value: 'left', child: Text('左移')),
        if (!isDefault) const PopupMenuItem(value: 'right', child: Text('右移')),
        if (!isDefault) const PopupMenuItem(value: 'delete', child: Text('删除收藏夹')),
      ],
    );
    if (!context.mounted || v == null) return;
    final fav = app.ctx.favorites;
    switch (v) {
      case 'edit':
        await editFavoriteFolder(context, folder: f);
      case 'left':
        await fav.move(f, fav.folders.indexOf(f) - 1);
      case 'right':
        await fav.move(f, fav.folders.indexOf(f) + 1);
      case 'delete':
        if (await confirm(context, '删除收藏夹', '删除「${f.name}」？其中的版本不会被删除。', danger: true, ok: '删除')) {
          await fav.removeFolder(f);
          if (identical(selected, f)) onSelect(null);
        }
    }
    app.changed();
  }
}


/// Update checker over mods, resource packs and shader packs (switchable).
class _UpdatesForAll extends StatefulWidget {
  final String gameDir;
  final GameVersion? version;
  const _UpdatesForAll({required this.gameDir, required this.version});
  @override
  State<_UpdatesForAll> createState() => _UpdatesForAllState();
}

class _UpdatesForAllState extends State<_UpdatesForAll> {
  String folder = 'mods';

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'mods', label: Text('Mod')),
              ButtonSegment(value: 'resourcepacks', label: Text('资源包')),
              ButtonSegment(value: 'shaderpacks', label: Text('光影')),
            ],
            selected: {folder},
            onSelectionChanged: (v) => setState(() => folder = v.first),
          ),
        ),
        Expanded(child: ModUpdatesTab(key: ValueKey(folder), folder: p.join(widget.gameDir, folder), version: widget.version)),
      ]);
}
