import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets/account.dart';
import '../widgets/common.dart';
import '../widgets/favorites.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<InstalledVersion> versions = [];
  bool loading = true;
  bool launching = false;

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
    });
  }

  String? get selected {
    final app = App.read(context);
    final s = app.settings.selectedVersion;
    if (s != null && versions.any((v) => v.id == s)) return s;
    return versions.where((v) => !v.broken).firstOrNull?.id;
  }

  /// Launches a favourite: switches game directory if needed, then launches.
  Future<void> _launchFavorite(String gameDir, String id) async {
    final app = App.read(context);
    if (!p.equals(app.settings.gameDir, gameDir)) {
      final match = app.settings.gameDirs.firstWhere((d) => p.equals(d, gameDir), orElse: () => '');
      if (match.isEmpty) return toast(context, '找不到游戏目录 $gameDir', error: true);
      app.settings.gameDir = match;
    }
    app.settings.selectedVersion = id;
    await app.saveSettings();
    await _load();
    if (mounted) await _launch();
  }

  Future<void> _launch() async {
    final app = App.read(context);
    final id = selected;
    if (id == null) return;
    if (app.ctx.accounts.selected == null) {
      final a = await showLoginDialog(context);
      if (a == null) return;
    }
    setState(() => launching = true);
    app.gameLog.clear();
    final gp = await app.runTask('启动 $id', (t) => app.ctx.launch(id, task: t, onLog: app.addLog), onError: (e) {
      if (mounted) toast(context, errText(e), error: true);
    });
    if (!mounted) return;
    setState(() => launching = false);
    if (gp == null) return;
    app.running = gp;
    app.changed();
    await gp.ready;
    if (app.settings.afterLaunch == 1) await windowManager.minimize();
    if (app.settings.afterLaunch == 2) await windowManager.close();
    final code = await gp.exitCode;
    app.running = null;
    app.changed();
    if (code != 0 && mounted) {
      final reason = gp.diagnose();
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('游戏崩溃了'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('退出码 $code'),
              const SizedBox(height: 8),
              Text(reason ?? '未能自动判断原因，请查看日志。', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: SingleChildScrollView(child: SelectableText(gp.tail.skip(gp.tail.length > 60 ? gp.tail.length - 60 : 0).join('\n'), style: const TextStyle(fontFamily: 'Consolas', fontSize: 11))),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final cml = CmlColors.of(context);
    final acc = app.ctx.accounts.selected;
    final mem = Memory.info();
    final sel = versions.where((v) => v.id == selected).firstOrNull;
    final running = app.running != null;
    return PageBody(children: [
      // ---------------- hero launch banner ----------------
      Container(
        decoration: BoxDecoration(
          gradient: cml.hero,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: cs.primary.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Positioned(right: -40, top: -50, child: Opacity(opacity: 0.18, child: Image.asset('assets/logo.png', width: 260, height: 260))),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SkinHead(acc?.activeSkin?.url, size: 44),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(acc == null ? '欢迎使用 CML' : '欢迎回来，${acc.name}',
                      style: t.textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  Text(acc == null ? '登录 Microsoft 账号后即可开始游戏' : (running ? '游戏正在运行' : '准备好开始冒险了吗？'),
                      style: t.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                ]),
              ]),
              const SizedBox(height: 26),
              if (loading)
                const LinearProgressIndicator(color: Colors.white)
              else if (versions.isEmpty)
                Text('当前游戏目录还没有安装任何版本，请前往「下载」页安装。', style: TextStyle(color: Colors.white.withValues(alpha: 0.9)))
              else
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withValues(alpha: 0.3))),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selected,
                          isExpanded: true,
                          dropdownColor: cs.surface,
                          borderRadius: BorderRadius.circular(12),
                          iconEnabledColor: Colors.white,
                          selectedItemBuilder: (_) => [
                            for (final v in versions)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Row(children: [
                                  const Icon(Icons.layers, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Flexible(child: Text(v.id, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                                  const SizedBox(width: 8),
                                  for (final l in v.version?.loaders ?? <ModLoader>{})
                                    Padding(padding: const EdgeInsets.only(right: 4), child: Pill(l.label, color: Colors.white)),
                                ]),
                              ),
                          ],
                          items: [
                            for (final v in versions)
                              DropdownMenuItem(
                                value: v.id,
                                enabled: !v.broken,
                                child: Row(children: [
                                  Text(v.id),
                                  const SizedBox(width: 8),
                                  if (v.broken) const Pill('已损坏', color: Colors.red),
                                  for (final l in v.version?.loaders ?? <ModLoader>{}) Padding(padding: const EdgeInsets.only(right: 4), child: Pill(l.label)),
                                  if (v.version != null && v.version!.baseVersion != v.id) Text(v.version!.baseVersion, style: t.textTheme.bodySmall),
                                ]),
                              )
                          ],
                          onChanged: (v) {
                            app.settings.selectedVersion = v;
                            app.saveSettings();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    height: 56,
                    width: 210,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: cs.primary,
                        disabledBackgroundColor: Colors.white.withValues(alpha: 0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: launching || running
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary))
                          : const Icon(Icons.play_arrow_rounded, size: 30),
                      label: Text(running ? '游戏运行中' : (launching ? '启动中…' : '启动游戏'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      onPressed: launching || running || selected == null ? null : _launch,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (selected != null) FavoriteStar(gameDir: app.settings.gameDir, versionId: selected!, size: 24, color: Colors.white),
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh, color: Colors.white), tooltip: '刷新版本列表'),
                ]),
              if (sel?.version != null) ...[
                const SizedBox(height: 12),
                Text('Minecraft ${sel!.version!.baseVersion}  ·  需要 Java ${sel.version!.requiredJava}+  ·  ${sel.version!.libraries.length} 个依赖库',
                    style: t.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ]),
          ),
        ]),
      ),
      // ---------------- favourites ----------------
      _FavoritesStrip(versions: versions, running: running || launching, onLaunch: _launchFavorite, onSelect: (id) {
        app.settings.selectedVersion = id;
        app.saveSettings();
      }),
      // ---------------- stats ----------------
      Row(children: [
        Expanded(
          child: StatTile(
            icon: Icons.memory_rounded,
            value: '${(mem.usedMb / 1024).toStringAsFixed(1)} / ${(mem.totalMb / 1024).toStringAsFixed(0)} GB',
            label: '内存占用 ${mem.loadPercent}%',
            progress: mem.loadPercent / 100,
            color: mem.loadPercent > 85 ? Colors.red : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: StatTile(icon: Icons.coffee_rounded, value: '${app.ctx.java.installs.length} 个', label: 'Java 运行时', color: Colors.orange)),
        const SizedBox(width: 14),
        Expanded(child: StatTile(icon: Icons.layers_rounded, value: '${versions.length} 个', label: '已安装版本', color: Colors.teal)),
        const SizedBox(width: 14),
        Expanded(
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final r = await app.runTask('内存优化', (t) => Memory.optimize(pids: [?app.running?.pid], purgeStandby: app.settings.purgeStandbyMemory));
                if (r != null && context.mounted) {
                  toast(context, '已整理 CML${app.running != null ? ' 与游戏' : ''} 的内存，可用内存增加约 ${r.freedMb} MB${r.standbyCleared ? '（含系统缓存）' : ''}');
                  setState(() {});
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.purple),
                  SizedBox(width: 12),
                  Expanded(child: Text('一键内存优化', style: TextStyle(fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right),
                ]),
              ),
            ),
          ),
        ),
      ]),
      // ---------------- accounts ----------------
      Section(
        title: '账号',
        icon: Icons.account_circle_outlined,
        subtitle: 'CML 仅支持 Microsoft 正版账号',
        actions: [
          FilledButton.tonalIcon(icon: const Icon(Icons.add, size: 18), label: const Text('添加账号'), onPressed: () => showLoginDialog(context)),
        ],
        child: app.ctx.accounts.accounts.isEmpty
            ? Row(children: [
                Icon(Icons.info_outline, size: 18, color: t.hintColor),
                const SizedBox(width: 8),
                const Expanded(child: Text('还没有登录账号。点击「添加账号」，在 microsoft.com/link 输入代码即可登录。')),
              ])
            : Wrap(spacing: 12, runSpacing: 12, children: [
                for (final a in app.ctx.accounts.accounts) _accountCard(context, app, a, a.uuid == acc?.uuid),
              ]),
      ),
      if (running || app.gameLog.isNotEmpty)
        Section(
          title: '游戏日志',
          icon: Icons.terminal_rounded,
          actions: [
            if (running)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cs.error),
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('结束游戏'),
                onPressed: () async {
                  if (await confirm(context, '结束游戏', '强制结束游戏进程？未保存的进度会丢失。', danger: true)) app.running?.kill();
                },
              ),
          ],
          child: Container(
            height: 240,
            decoration: BoxDecoration(color: const Color(0xFF14161B), borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.all(10),
            child: ListView.builder(
              reverse: true,
              itemCount: app.gameLog.length,
              itemBuilder: (_, i) {
                final l = app.gameLog[app.gameLog.length - 1 - i];
                final color = l.contains('ERROR') || l.contains('Exception')
                    ? const Color(0xFFFF7B7B)
                    : l.contains('WARN')
                        ? const Color(0xFFFFD27B)
                        : l.startsWith('[CML]')
                            ? const Color(0xFF8FD3FF)
                            : const Color(0xFFCFD6E0);
                return Text(l, style: TextStyle(fontFamily: 'Consolas', fontSize: 11.5, color: color, height: 1.35));
              },
            ),
          ),
        ),
    ]);
  }

  Widget _accountCard(BuildContext context, AppState app, MsAccount a, bool active) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        app.ctx.accounts.selectedUuid = a.uuid;
        await app.ctx.accounts.save();
        app.changed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? cs.primary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? cs.primary : CmlColors.of(context).cardBorder, width: active ? 2 : 1),
        ),
        child: Row(children: [
          SkinHead(a.activeSkin?.url, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Pill(a.tokenValid ? '已登录' : '待刷新', color: a.tokenValid ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                if (active) const Pill('当前'),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            tooltip: '',
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (v) async {
              if (v == 'remove' && await confirm(context, '移除账号', '确定移除 ${a.name}？', danger: true)) {
                app.ctx.accounts.remove(a.uuid);
                await app.ctx.accounts.save();
                app.changed();
              } else if (v == 'refresh') {
                await app.runTask('刷新账号 ${a.name}', (t) async {
                  final n = await app.ctx.auth.refresh(a);
                  app.ctx.accounts.upsert(n);
                  await app.ctx.accounts.save();
                }, onError: (e) => toast(context, errText(e), error: true));
              }
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'refresh', child: Text('刷新登录')), PopupMenuItem(value: 'remove', child: Text('移除'))],
          ),
        ]),
      ),
    );
  }
}


/// Horizontal list of favourited versions with one-click launch.
class _FavoritesStrip extends StatefulWidget {
  final List<InstalledVersion> versions;
  final bool running;
  final Future<void> Function(String gameDir, String id) onLaunch;
  final ValueChanged<String> onSelect;
  const _FavoritesStrip({required this.versions, required this.running, required this.onLaunch, required this.onSelect});
  @override
  State<_FavoritesStrip> createState() => _FavoritesStripState();
}

class _FavoritesStripState extends State<_FavoritesStrip> {
  int folderIndex = 0;

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final t = Theme.of(context);
    final fav = app.ctx.favorites;
    if (fav.folders.every((f) => f.entries.isEmpty)) return const SizedBox.shrink();
    final folders = [for (final f in fav.folders) if (f.entries.isNotEmpty) f];
    final folder = folders[folderIndex.clamp(0, folders.length - 1)];
    final local = {for (final v in widget.versions) Favorites.key(app.settings.gameDir, v.id): v};
    return Section(
      title: '收藏',
      icon: Icons.star_rounded,
      subtitle: '点击直接启动 · 右键版本可调整收藏夹',
      actions: [
        if (folders.length > 1)
          for (var i = 0; i < folders.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                avatar: Icon(favoriteIcon(folders[i]), size: 16, color: Color(folders[i].color)),
                label: Text(folders[i].name),
                selected: i == folderIndex.clamp(0, folders.length - 1),
                onSelected: (_) => setState(() => folderIndex = i),
              ),
            ),
      ],
      child: SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: folder.entries.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final key = folder.entries[i];
            final (dir, id) = Favorites.parse(key);
            final v = local[key];
            final other = !p.equals(dir, app.settings.gameDir);
            final c = Color(folder.color);
            return GestureDetector(
              onSecondaryTap: () => showFavoriteFolders(context, dir, id),
              child: Material(
                color: t.cardTheme.color,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: widget.running ? null : () => widget.onLaunch(dir, id),
                  child: Container(
                    width: 230,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.withValues(alpha: 0.35)),
                      gradient: LinearGradient(colors: [c.withValues(alpha: 0.12), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                        child: Icon(v?.version?.loaders.isNotEmpty == true ? Icons.extension_rounded : Icons.grass_rounded, color: c),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            other ? '其他目录 · ${p.basename(p.dirname(dir))}' : (v?.version == null ? '未找到' : [v!.version!.baseVersion, ...v.version!.loaders.map((l) => l.label)].join(' · ')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
                          ),
                        ]),
                      ),
                      Icon(Icons.play_circle_fill_rounded, color: widget.running ? t.disabledColor : c, size: 30),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
