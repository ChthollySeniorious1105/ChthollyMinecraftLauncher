import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../i18n/i18n.dart';
import '../state.dart';
import '../widgets/common.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> with SingleTickerProviderStateMixin {
  late final tabs = TabController(length: 7, vsync: this);

  @override
  Widget build(BuildContext context) => Column(children: [
        TabBar(controller: tabs, isScrollable: true, tabAlignment: TabAlignment.start, tabs: const [
          Tab(text: '游戏'),
          Tab(text: 'Mod'),
          Tab(text: '整合包'),
          Tab(text: '光影'),
          Tab(text: '资源包'),
          Tab(text: '数据包'),
          Tab(text: 'Java'),
        ]),
        Expanded(
          child: TabBarView(controller: tabs, children: const [
            _GameTab(),
            _ContentTab(ContentType.mod),
            _ContentTab(ContentType.modpack),
            _ContentTab(ContentType.shader),
            _ContentTab(ContentType.resourcepack),
            _ContentTab(ContentType.datapack),
            _JavaTab(),
          ]),
        ),
      ]);
}

// ============================ game versions ============================

class _GameTab extends StatefulWidget {
  const _GameTab();
  @override
  State<_GameTab> createState() => _GameTabState();
}

class _GameTabState extends State<_GameTab> {
  VersionManifest? manifest;
  String? error;
  String type = 'release';
  String filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool refreshing = false;

  Future<void> _load({bool refresh = false}) async {
    final ins = App.read(context).ctx.installer;
    setState(() {
      error = null;
      refreshing = true;
    });
    // show the cached list immediately, then refresh from the network
    if (manifest == null) {
      final cached = await ins.cachedManifest();
      if (mounted && cached != null) setState(() => manifest = cached);
    }
    try {
      final m = await ins.manifest(refresh: refresh || manifest != null);
      if (mounted) setState(() => manifest = m);
    } catch (e) {
      if (mounted && manifest == null) setState(() => error = errText(e));
    }
    if (mounted) setState(() => refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return EmptyHint(Icons.cloud_off, error!, action: FilledButton(onPressed: () => _load(refresh: true), child: const Text('重试')));
    if (manifest == null) return const Center(child: CircularProgressIndicator());
    final list = manifest!.versions.where((v) => (type == 'all' || v.type == type || (type == 'old' && v.type.startsWith('old'))) && v.id.contains(filter)).toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Row(children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'release', label: Text('正式版')),
              ButtonSegment(value: 'snapshot', label: Text('快照版')),
              ButtonSegment(value: 'old', label: Text('远古版')),
              ButtonSegment(value: 'all', label: Text('全部')),
            ],
            selected: {type},
            onSelectionChanged: (s) => setState(() => type = s.first),
          ),
          const SizedBox(width: 12),
          Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: '搜索版本号'), onChanged: (v) => setState(() => filter = v.trim()))),
          IconButton(
            onPressed: refreshing ? null : () => _load(refresh: true),
            icon: refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(children: [
          Expanded(child: _LatestCard(label: '最新正式版', entry: manifest!.find(manifest!.latestRelease), icon: Icons.grass_rounded, color: Colors.green)),
          const SizedBox(width: 12),
          Expanded(child: _LatestCard(label: '最新快照版', entry: manifest!.find(manifest!.latestSnapshot), icon: Icons.science_rounded, color: Colors.orange)),
        ]),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 300, mainAxisExtent: 64, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: list.length,
          itemBuilder: (_, i) => _VersionTile(entry: list[i]),
        ),
      ),
    ]);
  }
}

Color _typeColor(String type) => switch (type) { 'release' => Colors.green, 'snapshot' => Colors.orange, _ => Colors.brown };
IconData _typeIcon(String type) => switch (type) { 'release' => Icons.grass_rounded, 'snapshot' => Icons.science_rounded, _ => Icons.history_edu_rounded };

class _LatestCard extends StatelessWidget {
  final String label;
  final ManifestEntry? entry;
  final IconData icon;
  final Color color;
  const _LatestCard({required this.label, required this.entry, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: entry == null ? null : () => showDialog(context: context, builder: (_) => _InstallDialog(entry: entry!)),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.14), color.withValues(alpha: 0.02)], begin: Alignment.centerLeft, end: Alignment.centerRight),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                Text(entry?.id ?? '-', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
            Text(fmtDate(entry?.releaseTime).split(' ').first, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('安装'),
              onPressed: entry == null ? null : () => showDialog(context: context, builder: (_) => _InstallDialog(entry: entry!)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  final ManifestEntry entry;
  const _VersionTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = _typeColor(entry.type);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showDialog(context: context, builder: (_) => _InstallDialog(entry: entry)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
              child: Icon(_typeIcon(entry.type), color: c, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.id, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${entry.typeLabel} · ${fmtDate(entry.releaseTime).split(' ').first}', style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
              ]),
            ),
            Icon(Icons.add_circle_outline_rounded, size: 20, color: t.colorScheme.primary),
          ]),
        ),
      ),
    );
  }
}

class _InstallDialog extends StatefulWidget {
  final ManifestEntry entry;
  const _InstallDialog({required this.entry});
  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  ModLoader? loader;
  final versions = <ModLoader, List<LoaderVersion>?>{};
  final errors = <ModLoader, String>{};
  LoaderVersion? picked;
  late final name = TextEditingController(text: widget.entry.id);

  // OptiFine: standalone (loader == optifine) or as an add-on to Forge
  List<OptiFineBuild>? ofBuilds;
  String? ofError;
  OptiFineBuild? ofPicked;
  bool ofWithForge = false;

  static const supported = [ModLoader.fabric, ModLoader.quilt, ModLoader.forge, ModLoader.neoforge];

  @override
  void initState() {
    super.initState();
    final app = App.read(context);
    for (final l in supported) {
      app.ctx.loaders.list(l, widget.entry.id).then((v) {
        if (mounted) setState(() => versions[l] = v);
      }, onError: (e) {
        if (mounted) setState(() => errors[l] = errText(e));
      });
    }
    app.ctx.optifine.list(widget.entry.id).then((v) {
      if (mounted) {
        setState(() {
          ofBuilds = v;
          ofPicked = v.firstOrNull;
        });
      }
    }, onError: (e) {
      if (mounted) setState(() => ofError = errText(e));
    });
  }

  void _updateName() {
    final mc = widget.entry.id;
    if (loader == ModLoader.optifine) {
      name.text = ofPicked == null ? mc : '$mc-OptiFine_${ofPicked!.edition}';
    } else {
      var n = picked == null ? mc : LoaderInstaller.defaultName(picked!);
      if (loader == ModLoader.forge && ofWithForge && ofPicked != null) n = '$n-OptiFine';
      name.text = n;
    }
  }

  Future<void> _install() async {
    final app = App.read(context);
    final id = name.text.trim();
    if (id.isEmpty) return;
    Navigator.pop(context);
    final e = widget.entry;
    final of = ofPicked;
    final standaloneOf = loader == ModLoader.optifine;
    final forgeOf = loader == ModLoader.forge && ofWithForge && of != null;
    await app.runTask(context.tr('安装 {0}', [id]), (t) async {
      final dir = app.ctx.gameDir;
      final ins = app.ctx.installer;
      if (picked == null && !standaloneOf) {
        await ins.installVanillaJson(dir, e, id: id);
      } else {
        if (!await dir.list().then((l) => l.any((x) => x.id == e.id))) await ins.installVanillaJson(dir, e);
        await ins.completeFiles(dir, e.id, task: t);
        final v = await dir.load(e.id);
        final java = await app.ctx.javaFor(v, InstanceSettings(), task: t);
        if (standaloneOf) {
          await app.ctx.optifine.install(dir, of!, javaPath: java.path, id: id, task: t);
        } else {
          await app.ctx.loaders.install(dir, picked!, javaPath: java.path, id: id, task: t);
        }
      }
      await ins.completeFiles(dir, id, task: t);
      if (forgeOf) {
        final modsDir = p.join(dir.gameDirFor(id, isolated: app.settings.isolateVersions), 'mods');
        await app.ctx.optifine.installAsMod(of, modsDir, task: t);
      }
    }, onError: (err) => toast(context, errText(err), error: true));
  }

  bool get _canInstall => loader != ModLoader.optifine || ofPicked != null;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final ofCount = ofBuilds?.length ?? 0;
    return AlertDialog(
      title: Text(context.tr('安装 Minecraft {0}', [widget.entry.id])),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: context.tr('版本名称'))),
            const SizedBox(height: 12),
            RadioGroup<ModLoader?>(
              groupValue: loader,
              onChanged: (v) => setState(() {
                loader = v;
                picked = (v == null || v == ModLoader.optifine) ? null : versions[v]?.where((x) => x.stable).firstOrNull ?? versions[v]?.firstOrNull;
                _updateName();
              }),
              child: Column(children: [
                RadioListTile<ModLoader?>(dense: true, value: null, title: Text(context.tr('原版（不安装加载器）'))),
                for (final l in supported)
                  RadioListTile<ModLoader?>(
                    dense: true,
                    value: l,
                    enabled: versions[l]?.isNotEmpty == true,
                    title: Text(l.label),
                    subtitle: Text(
                        errors[l] ??
                            (versions[l] == null
                                ? context.tr('加载中…')
                                : (versions[l]!.isEmpty
                                    ? context.tr('不支持此版本')
                                    : context.tr('{0} 个版本，最新 {1}', [versions[l]!.length, versions[l]!.first.version]))),
                        style: t.textTheme.bodySmall),
                  ),
                RadioListTile<ModLoader?>(
                  dense: true,
                  value: ModLoader.optifine,
                  enabled: ofCount > 0,
                  title: const Text('OptiFine'),
                  subtitle: Text(
                      ofError ??
                          (ofBuilds == null
                              ? context.tr('加载中…')
                              : ofCount == 0
                                  ? context.tr('不支持此版本')
                                  : context.tr('{0} 个版本，最新 {1}（通过 BMCLAPI 获取）', [ofCount, ofBuilds!.first.label])),
                      style: t.textTheme.bodySmall),
                ),
              ]),
            ),
            if (loader != null && loader != ModLoader.optifine && versions[loader]?.isNotEmpty == true)
              DropdownButtonFormField<LoaderVersion>(
                initialValue: picked,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('{0} 版本', [loader!.label])),
                items: [
                  for (final v in versions[loader]!.take(200))
                    DropdownMenuItem(value: v, child: Text('${v.version}${v.stable ? '' : context.tr('（测试版）')}'))
                ],
                onChanged: (v) => setState(() {
                  picked = v;
                  _updateName();
                }),
              ),
            if (loader == ModLoader.forge && ofCount > 0)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: ofWithForge,
                title: Text(context.tr('同时安装 OptiFine（作为 Mod）')),
                subtitle: ofPicked?.forge == null ? null : Text(context.tr('OptiFine {0} 推荐 {1}', [ofPicked!.label, ofPicked!.forge!]), style: t.textTheme.bodySmall),
                onChanged: (v) => setState(() {
                  ofWithForge = v == true;
                  _updateName();
                }),
              ),
            if ((loader == ModLoader.optifine || (loader == ModLoader.forge && ofWithForge)) && ofCount > 0) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<OptiFineBuild>(
                initialValue: ofPicked,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('OptiFine 版本')),
                items: [
                  for (final b in ofBuilds!)
                    DropdownMenuItem(value: b, child: Text('${b.label}${b.forge == null ? '' : '  ·  ${b.forge}'}'))
                ],
                onChanged: (v) => setState(() {
                  ofPicked = v;
                  _updateName();
                }),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('取消'))),
        FilledButton(onPressed: _canInstall ? _install : null, child: Text(context.tr('安装'))),
      ],
    );
  }
}

// ============================ content (Modrinth / CurseForge) ============================

class _ContentTab extends StatefulWidget {
  final ContentType type;
  const _ContentTab(this.type);
  @override
  State<_ContentTab> createState() => _ContentTabState();
}

class _ContentTabState extends State<_ContentTab> with AutomaticKeepAliveClientMixin {
  ContentPlatform platform = ContentPlatform.modrinth;
  final query = TextEditingController();
  String gameVersion = '';
  String loader = '';
  SortBy sort = SortBy.relevance;
  List<ContentProject> results = [];
  bool loading = false;
  String? error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await App.read(context).ctx.content.search(platform, widget.type,
          query: query.text.trim(), gameVersion: gameVersion, loader: loader, sort: sort);
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = Theme.of(context);
    final showLoader = widget.type == ContentType.mod || widget.type == ContentType.modpack;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(children: [
          SegmentedButton<ContentPlatform>(
            segments: const [ButtonSegment(value: ContentPlatform.modrinth, label: Text('Modrinth')), ButtonSegment(value: ContentPlatform.curseforge, label: Text('CurseForge'))],
            selected: {platform},
            onSelectionChanged: (s) {
              setState(() => platform = s.first);
              _search();
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: query,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: '搜索${widget.type.label}'),
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextField(
              decoration: const InputDecoration(hintText: '游戏版本'),
              onChanged: (v) => gameVersion = v.trim(),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (showLoader) ...[
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: loader,
              items: const [
                DropdownMenuItem(value: '', child: Text('任意加载器')),
                DropdownMenuItem(value: 'fabric', child: Text('Fabric')),
                DropdownMenuItem(value: 'forge', child: Text('Forge')),
                DropdownMenuItem(value: 'neoforge', child: Text('NeoForge')),
                DropdownMenuItem(value: 'quilt', child: Text('Quilt')),
              ],
              onChanged: (v) {
                setState(() => loader = v!);
                _search();
              },
            ),
          ],
          const SizedBox(width: 8),
          DropdownButton<SortBy>(
            value: sort,
            items: const [
              DropdownMenuItem(value: SortBy.relevance, child: Text('相关度')),
              DropdownMenuItem(value: SortBy.downloads, child: Text('下载量')),
              DropdownMenuItem(value: SortBy.updated, child: Text('最近更新')),
              DropdownMenuItem(value: SortBy.newest, child: Text('最新发布')),
            ],
            onChanged: (v) {
              setState(() => sort = v!);
              _search();
            },
          ),
          if (widget.type == ContentType.modpack) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('导入本地整合包'), onPressed: () => importLocalModpack(context)),
          ],
        ]),
      ),
      if (loading) const LinearProgressIndicator(),
      Expanded(
        child: error != null
            ? EmptyHint(Icons.cloud_off, error!, action: FilledButton(onPressed: _search, child: const Text('重试')))
            : results.isEmpty && !loading
                ? const EmptyHint(Icons.search_off, '没有结果')
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final r = results[i];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: r.iconUrl == null
                              ? Container(width: 44, height: 44, color: t.colorScheme.surfaceContainerHighest, child: const Icon(Icons.extension))
                              : Image.network(r.iconUrl!, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44)),
                        ),
                        title: Row(children: [
                          Flexible(child: Text(r.title, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          for (final l in r.loaders.take(3)) Padding(padding: const EdgeInsets.only(right: 4), child: Pill(l)),
                        ]),
                        subtitle: Text('${r.description}\n${r.author.isEmpty ? '' : '${r.author} · '}${fmtCount(r.downloads)} 次下载 · ${fmtDate(r.updated).split(' ').first}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        onTap: () => showDialog(context: context, builder: (_) => ProjectDialog(project: r)),
                      );
                    },
                  ),
      ),
    ]);
  }
}

/// Picks a target folder and installs a version of [project].
class ProjectDialog extends StatefulWidget {
  final ContentProject project;
  const ProjectDialog({super.key, required this.project});
  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  List<ContentVersion>? versions;
  String? error;
  String gameVersion = '';
  String? target; // installed version id
  List<InstalledVersion> installed = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = App.read(context);
    installed = await app.ctx.gameDir.list();
    target ??= app.settings.selectedVersion ?? installed.firstOrNull?.id;
    final tv = installed.where((v) => v.id == target).firstOrNull?.version;
    // pre-filter by the target instance's MC version and loader
    final mc = gameVersion.isNotEmpty ? gameVersion : (tv?.baseVersion ?? '');
    final loader = widget.project.type == ContentType.mod ? tv?.loaders.where((l) => l != ModLoader.optifine).firstOrNull?.slug : null;
    try {
      final v = await app.ctx.content.versions(widget.project, gameVersion: mc.isEmpty || widget.project.type == ContentType.modpack ? null : mc, loader: loader);
      if (mounted) setState(() => versions = v);
    } catch (e) {
      if (mounted) setState(() => error = errText(e));
    }
  }

  String _folderFor(AppState app, String id) {
    final inst = app.ctx.gameDir.gameDirFor(id, isolated: app.settings.isolateVersions);
    return p.join(inst, widget.project.type.folder);
  }

  Future<void> _install(ContentVersion v) async {
    final app = App.read(context);
    final type = widget.project.type;
    if (type == ContentType.modpack) {
      final name = await prompt(context, '整合包实例名称', initial: widget.project.title);
      if (name == null || name.trim().isEmpty || !mounted) return;
      Navigator.pop(context);
      await app.runTask('安装整合包 ${name.trim()}', (t) async {
        final tmp = p.join(Os.cmlHome, 'cache', v.primaryFile.filename);
        await app.ctx.contentInstaller.installFile(v, p.dirname(tmp), task: t);
        final java = app.ctx.java.pick(21) ?? app.ctx.java.pick(17) ?? app.ctx.java.installs.first;
        await app.ctx.contentInstaller.importModpack(app.ctx.gameDir, tmp, name.trim(), javaPath: java.path, task: t);
      }, onError: (e) => toast(context, errText(e), error: true));
      return;
    }
    String? folder;
    if (type == ContentType.datapack) {
      // datapacks go into a world
      final saves = p.join(app.ctx.gameDir.gameDirFor(target!, isolated: app.settings.isolateVersions), 'saves');
      final worlds = await Worlds.listJava(saves);
      if (!mounted) return;
      if (worlds.isEmpty) return toast(context, '版本 $target 没有存档，无法安装数据包', error: true);
      final w = await showDialog<WorldInfo>(
          context: context,
          builder: (c) => SimpleDialog(title: const Text('安装到哪个存档？'), children: [for (final w in worlds) SimpleDialogOption(onPressed: () => Navigator.pop(c, w), child: Text(w.name))]));
      if (w == null) return;
      folder = p.join(w.path, 'datapacks');
    } else {
      folder = _folderFor(app, target!);
    }
    if (!mounted) return;
    Navigator.pop(context);
    final tv = installed.where((x) => x.id == target).firstOrNull?.version;
    await app.runTask('下载 ${widget.project.title}', (t) async {
      final files = type == ContentType.mod
          ? await app.ctx.contentInstaller.installWithDependencies(v, folder!, gameVersion: tv?.baseVersion, loader: tv?.loaders.firstOrNull?.slug, task: t)
          : [await app.ctx.contentInstaller.installFile(v, folder!, task: t)];
      return files;
    }, onError: (e) => toast(context, errText(e), error: true));
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final pr = widget.project;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(pr.title)),
        IconButton(icon: const Icon(Icons.open_in_new, size: 18), tooltip: '打开项目主页', onPressed: () => launchUrl(Uri.parse(pr.pageUrl))),
      ]),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pr.description, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Row(children: [
            if (pr.type != ContentType.modpack)
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '安装到版本'),
                  items: [for (final v in installed) DropdownMenuItem(value: v.id, child: Text(v.id))],
                  onChanged: (v) {
                    setState(() {
                      target = v;
                      versions = null;
                    });
                    _load();
                  },
                ),
              ),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: TextField(
                decoration: const InputDecoration(labelText: '筛选游戏版本'),
                onSubmitted: (v) {
                  gameVersion = v.trim();
                  setState(() => versions = null);
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: error != null
                ? Text(error!)
                : versions == null
                    ? const Center(child: CircularProgressIndicator())
                    : versions!.isEmpty
                        ? const Center(child: Text('没有适用于该版本的文件'))
                        : ListView(children: [
                            for (final v in versions!)
                              ListTile(
                                dense: true,
                                title: Text(v.name),
                                subtitle: Text('${v.gameVersions.take(6).join(', ')}  ·  ${v.loaders.join(', ')}  ·  ${fmtDate(v.published).split(' ').first}'),
                                leading: Pill(switch (v.channel) { 'beta' => 'Beta', 'alpha' => 'Alpha', _ => '正式' },
                                    color: v.channel == 'release' ? Colors.green : Colors.orange),
                                trailing: FilledButton.tonal(
                                  onPressed: target == null && pr.type != ContentType.modpack ? null : () => _install(v),
                                  child: const Text('安装'),
                                ),
                              ),
                          ]),
          ),
          if (app.settings.contentSource == ContentSource.mcim) Text('当前使用 MCIM 镜像源，可在设置中切换。', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  }
}

Future<void> importLocalModpack(BuildContext context) async {
  final app = App.read(context);
  final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '整合包', extensions: ['mrpack', 'zip'])]);
  if (f == null || !context.mounted) return;
  final name = await prompt(context, '实例名称', initial: p.basenameWithoutExtension(f.name));
  if (name == null || name.trim().isEmpty) return;
  final java = app.ctx.java.pick(21) ?? app.ctx.java.pick(17) ?? app.ctx.java.installs.firstOrNull;
  if (java == null) {
    if (context.mounted) toast(context, '请先安装 Java', error: true);
    return;
  }
  await app.runTask('导入整合包 ${name.trim()}', (t) => app.ctx.contentInstaller.importModpack(app.ctx.gameDir, f.path, name.trim(), javaPath: java.path, task: t),
      onError: (e) => toast(context, errText(e), error: true));
}

// ============================ Java ============================

class _JavaTab extends StatelessWidget {
  const _JavaTab();

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    return PageBody(children: [
      Section(
        title: '下载 Java（Eclipse Temurin）',
        icon: Icons.download_for_offline_outlined,
        child: Wrap(spacing: 12, runSpacing: 12, children: [
          for (final m in JavaDownloader.majors)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.download, size: 16),
              label: Text('Java $m'),
              onPressed: () => app.runTask('下载 Java $m', (t) async {
                final pkg = await app.ctx.javaDownloader.latest(m);
                final exe = await app.ctx.javaDownloader.install(pkg, task: t);
                await app.ctx.java.addManual(exe);
                app.changed();
              }, onError: (e) => toast(context, errText(e), error: true)),
            ),
        ]),
      ),
      Section(
        title: '版本对应',
        icon: Icons.info_outline,
        child: Text('Minecraft 1.20.5 及以上需要 Java 21；1.18 – 1.20.4 需要 Java 17；1.17 需要 Java 16；1.16.5 及以下推荐 Java 8。\n'
            '下载源为「BMCLAPI」或「自动」时会优先使用清华大学镜像。'),
      ),
    ]);
  }
}
