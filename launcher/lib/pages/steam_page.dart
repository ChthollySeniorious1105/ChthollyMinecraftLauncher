import 'dart:async';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../state.dart';
import '../widgets/account.dart' show revealInExplorer;
import '../widgets/common.dart';

/// The Steam library of the client logged in on this machine (read-only from local files).
/// Launch / install / uninstall / verify go through the Steam client (`steam://` URLs).
class SteamPage extends StatefulWidget {
  const SteamPage({super.key});
  @override
  State<SteamPage> createState() => _SteamPageState();
}

enum _Sort { name, lastPlayed, playtime }

class _SteamPageState extends State<SteamPage> {
  String? steam;
  List<SteamAccount> accounts = [];
  SteamAccount? account;
  SteamLibrary? lib;
  AppInfo? appInfo;
  String? error;
  bool loading = true;

  bool installedOnly = true;
  bool showHidden = false;
  String query = '';
  _Sort sort = _Sort.lastPlayed;
  String collection = ''; // '' = all, 'favorite', or a user collection id
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // download / update progress lives in the appmanifests; Steam rewrites them while downloading
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refreshInstalled());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reloadInfo = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      steam ??= await Steam.installPath();
      if (steam == null) {
        setState(() {
          loading = false;
          error = trGlobal('没有找到 Steam。安装 Steam 并至少登录一次后再试。');
        });
        return;
      }
      accounts = Steam.accounts(steam!);
      if (accounts.isEmpty) {
        setState(() {
          loading = false;
          error = trGlobal('这台电脑上的 Steam 还没有登录过账号。请先在 Steam 客户端登录。');
        });
        return;
      }
      account = accounts.where((a) => a.accountId == account?.accountId).firstOrNull ?? accounts.first;
      if (reloadInfo || appInfo == null) {
        try {
          appInfo = await AppInfo.load('${steam!}\\appcache\\appinfo.vdf');
        } catch (_) {
          appInfo = null;
        }
      }
      final l = await Steam.library(steam!, account!, appInfo: appInfo);
      if (!mounted) return;
      setState(() {
        lib = l;
        loading = false;
        if (collection.isNotEmpty && collection != 'favorite' && !l.collections.any((c) => c.id == collection)) collection = '';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = errText(e);
        });
      }
    }
  }

  /// Cheap refresh of install / download state only (no library cache or appinfo re-read).
  void _refreshInstalled() {
    final l = lib;
    if (l == null || steam == null || !mounted) return;
    final inst = Steam.installed(steam!);
    var changed = false;
    final games = [
      for (final g in l.games)
        () {
          final now = inst[g.appId]?.install;
          final before = g.install;
          if ((now == null) != (before == null) ||
              (now != null && (now.stateFlags != before!.stateFlags || now.bytesDownloaded != before.bytesDownloaded || now.sizeOnDisk != before.sizeOnDisk))) {
            changed = true;
            return SteamGame(
              appId: g.appId,
              name: g.name,
              install: now,
              lastPlayed: g.lastPlayed,
              playtimeMinutes: g.playtimeMinutes,
              hidden: g.hidden,
              favorite: g.favorite,
              collections: g.collections,
              coverPath: g.coverPath,
              headerPath: g.headerPath,
            );
          }
          return g;
        }(),
    ];
    if (changed) setState(() => lib = SteamLibrary(l.account, games, l.collections, l.warnings, l.familyName));
  }

  List<SteamGame> get _visible {
    final l = lib;
    if (l == null) return const [];
    final q = query.trim().toLowerCase();
    final list = l.games.where((g) {
      if (installedOnly && !g.installed) return false;
      if (!showHidden && g.hidden) return false;
      if (collection == 'favorite' && !g.favorite) return false;
      if (collection.isNotEmpty && collection != 'favorite' && !g.collections.contains(collection)) return false;
      if (q.isNotEmpty && !g.name.toLowerCase().contains(q) && '${g.appId}' != q) return false;
      return true;
    }).toList();
    int byName(SteamGame a, SteamGame b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
    list.sort((a, b) {
      // favourites first, like Steam
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      switch (sort) {
        case _Sort.name:
          return byName(a, b);
        case _Sort.lastPlayed:
          final x = a.lastPlayed?.millisecondsSinceEpoch ?? 0, y = b.lastPlayed?.millisecondsSinceEpoch ?? 0;
          return x != y ? y.compareTo(x) : byName(a, b);
        case _Sort.playtime:
          return a.playtimeMinutes != b.playtimeMinutes ? b.playtimeMinutes.compareTo(a.playtimeMinutes) : byName(a, b);
      }
    });
    return list;
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (loading && lib == null) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return EmptyHint(Icons.videogame_asset_off_outlined, error!, action: FilledButton.tonal(onPressed: _load, child: Text(trGlobal('重新检测'))));
    }
    final l = lib!;
    final games = _visible;
    final hiddenCount = l.games.where((g) => g.hidden && (!installedOnly || g.installed)).length;
    final downloading = l.games.where((g) => g.install?.progress != null).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 10),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (accounts.length > 1)
            DropdownButton<int>(
              value: account!.accountId,
              underline: const SizedBox.shrink(),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.accountId, child: Text(a.mostRecent ? trGlobal('{0}（当前登录）', [a.personaName]) : a.personaName)),
              ],
              onChanged: (v) {
                setState(() => account = accounts.firstWhere((a) => a.accountId == v));
                _load();
              },
            )
          else
            Chip(avatar: const Icon(Icons.person_outline, size: 18), label: Text(account!.personaName)),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(trGlobal('已安装 {0}', [l.games.where((g) => g.installed && (showHidden || !g.hidden)).length]))),
              ButtonSegment(value: false, label: Text(trGlobal('库中全部 {0}', [l.games.where((g) => showHidden || !g.hidden).length]))),
            ],
            selected: {installedOnly},
            onSelectionChanged: (s) => setState(() => installedOnly = s.first),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search, size: 18), hintText: trGlobal('搜索游戏')),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          DropdownButton<_Sort>(
            value: sort,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: _Sort.lastPlayed, child: Text(trGlobal('最近游玩'))),
              DropdownMenuItem(value: _Sort.playtime, child: Text(trGlobal('游玩时长'))),
              DropdownMenuItem(value: _Sort.name, child: Text(trGlobal('名称'))),
            ],
            onChanged: (v) => setState(() => sort = v!),
          ),
          DropdownButton<String>(
            value: collection,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(value: '', child: Text(trGlobal('全部收藏夹'))),
              DropdownMenuItem(value: 'favorite', child: Text(trGlobal('收藏'))),
              for (final c in l.collections) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => collection = v!),
          ),
          FilterChip(
            avatar: Icon(showHidden ? Icons.visibility : Icons.visibility_off_outlined, size: 16),
            label: Text(trGlobal('显示隐藏的游戏（{0}）', [hiddenCount])),
            selected: showHidden,
            onSelected: (v) => setState(() => showHidden = v),
          ),
          IconButton(onPressed: () => _load(reloadInfo: true), icon: const Icon(Icons.refresh), tooltip: trGlobal('刷新')),
          TextButton.icon(onPressed: () => _run(Steam.downloads), icon: const Icon(Icons.download_outlined, size: 18), label: Text(trGlobal('Steam 下载'))),
        ]),
      ),
      if (l.warnings.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: Text(trGlobal('部分数据读取失败（{0}），相关功能已停用。Steam 更新文件格式后可能出现这种情况。', [l.warnings.map(trCore).join('、')]),
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.error)),
        ),
      for (final g in downloading)
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
          child: Row(children: [
            const Icon(Icons.downloading, size: 18),
            const SizedBox(width: 8),
            SizedBox(width: 220, child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Expanded(child: LinearProgressIndicator(value: g.install!.progress)),
            const SizedBox(width: 8),
            Text('${fmtBytes(g.install!.bytesDownloaded)} / ${fmtBytes(g.install!.bytesToDownload)}', style: t.textTheme.bodySmall),
          ]),
        ),
      Expanded(
        child: games.isEmpty
            ? EmptyHint(Icons.search_off, installedOnly ? trGlobal('没有符合条件的已安装游戏。切换到「库中全部」可以安装游戏。') : trGlobal('没有符合条件的游戏'))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.56),
                itemCount: games.length,
                itemBuilder: (_, i) => _GameTile(games[i], onAction: _run),
              ),
      ),
    ]);
  }
}

class _GameTile extends StatefulWidget {
  final SteamGame g;
  final Future<void> Function(Future<void> Function()) onAction;
  const _GameTile(this.g, {required this.onAction});
  @override
  State<_GameTile> createState() => _GameTileState();
}

class _GameTileState extends State<_GameTile> {
  bool hover = false;

  String _playtime(int m) => m < 60 ? trGlobal('{0} 分钟', [m]) : trGlobal('{0} 小时', [(m / 60).toStringAsFixed(m < 600 ? 1 : 0)]);

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final inst = g.install;
    final art = _art(t);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: Opacity(
        opacity: g.hidden ? 0.5 : 1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(fit: StackFit.expand, children: [
                art,
                if (g.favorite) const Positioned(top: 6, left: 6, child: Icon(Icons.star, color: Colors.amber, size: 20)),
                if (g.hidden)
                  Positioned(top: 6, right: 6, child: Pill(trGlobal('已隐藏'), color: Colors.grey)),
                if (inst?.progress != null)
                  Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: inst!.progress, minHeight: 4)),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 140),
                  opacity: hover ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !hover,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      child: Center(
                        child: inst != null
                            ? FilledButton.icon(
                                onPressed: () => widget.onAction(() => Steam.launch(g.appId)),
                                icon: const Icon(Icons.play_arrow),
                                label: Text(trGlobal('启动')),
                              )
                            : FilledButton.tonalIcon(
                                onPressed: () => widget.onAction(() => Steam.install(g.appId)),
                                icon: const Icon(Icons.download),
                                label: Text(trGlobal('安装')),
                              ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (inst != null) fmtBytes(inst.sizeOnDisk) else trGlobal('未安装'),
                    if (g.playtimeMinutes > 0) _playtime(g.playtimeMinutes),
                  ].join(' · '),
                  maxLines: 1,
                  style: t.textTheme.bodySmall?.copyWith(color: t.hintColor),
                ),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
              onSelected: (v) => widget.onAction(() async {
                switch (v) {
                  case 'launch':
                    await Steam.launch(g.appId);
                  case 'install':
                    await Steam.install(g.appId);
                  case 'validate':
                    await Steam.validate(g.appId);
                  case 'uninstall':
                    await Steam.uninstall(g.appId);
                  case 'folder':
                    await revealInExplorer(inst!.path);
                  case 'library':
                    await Steam.libraryPage(g.appId);
                  case 'store':
                    await Steam.storePage(g.appId);
                }
              }),
              itemBuilder: (_) => [
                if (inst != null) ...[
                  PopupMenuItem(value: 'launch', child: Text(trGlobal('启动'))),
                  PopupMenuItem(value: 'folder', child: Text(trGlobal('打开安装目录'))),
                  PopupMenuItem(value: 'validate', child: Text(trGlobal('验证游戏文件'))),
                  PopupMenuItem(value: 'uninstall', child: Text(trGlobal('卸载'))),
                ] else
                  PopupMenuItem(value: 'install', child: Text(trGlobal('安装'))),
                PopupMenuItem(value: 'library', child: Text(trGlobal('在 Steam 库中打开（可设置隐藏 / 收藏）'))),
                PopupMenuItem(value: 'store', child: Text(trGlobal('商店页面'))),
              ],
            ),
          ]),
        ]),
      ),
    );
  }

  /// Portrait cover: local cache → CDN portrait → local / CDN header (landscape, centred) → name.
  Widget _art(ThemeData t) {
    final g = widget.g;
    Widget header() => g.headerPath != null
        ? _framed(Image.file(File(g.headerPath!), fit: BoxFit.contain, errorBuilder: (_, _, _) => _fallback(t)), t)
        : _framed(_net(g.headerUrl, BoxFit.contain, () => _fallback(t), t), t);
    if (g.coverPath != null) return Image.file(File(g.coverPath!), fit: BoxFit.cover, errorBuilder: (_, _, _) => header());
    return _net(g.coverUrl, BoxFit.cover, header, t);
  }

  Widget _net(String url, BoxFit fit, Widget Function() onError, ThemeData t) => Image.network(
        url,
        fit: fit,
        // name placeholder while loading
        frameBuilder: (_, child, frame, sync) => frame == null && !sync ? _fallback(t) : child,
        errorBuilder: (_, _, _) => onError(),
      );

  /// Landscape art centred on a tinted card.
  Widget _framed(Widget img, ThemeData t) => Container(color: t.colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: img);

  Widget _fallback(ThemeData t) => Container(
        color: t.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: Text(widget.g.name, textAlign: TextAlign.center, style: t.textTheme.titleSmall),
      );
}
