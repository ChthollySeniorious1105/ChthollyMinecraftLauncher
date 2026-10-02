import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../games/boards.dart';
import '../main.dart';
import '../net/connection.dart';
import '../platform/game_ui.dart';
import '../platform/replay_store.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Opens a replay file saved on this device.
Future<void> openLocalReplayFile(BuildContext context, String path) async {
  try {
    final r = await ReplayStore.load(File(path));
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReplayPlayerScreen(replay: r, savedPath: path)));
  } catch (e) {
    if (context.mounted) AppScope.read(context).toast('无法打开回放：$e');
  }
}

/// 回放列表: server replays (全部 / 我的) and replays saved on this device.
class ReplaysScreen extends StatefulWidget {
  const ReplaysScreen({super.key});
  @override
  State<ReplaysScreen> createState() => _ReplaysScreenState();
}

class _ReplaysScreenState extends State<ReplaysScreen> with SingleTickerProviderStateMixin {
  late final bool _online = AppScope.read(context).state == ConnState.connected;
  late final TabController _tabs = TabController(length: _online ? 3 : 1, vsync: this);
  List<LocalReplay>? _local;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    if (_online) AppScope.read(context).requestReplays();
    _loadLocal();
  }

  void _onTab() {
    if (_tabs.indexIsChanging || !_online) return;
    if (_tabs.index < 2) AppScope.read(context).requestReplays(mine: _tabs.index == 1);
    if (_tabs.index == 2) _loadLocal();
  }

  Future<void> _loadLocal() async {
    final l = await ReplayStore.list();
    if (mounted) setState(() => _local = l);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openServer(ReplayMeta m) async {
    final app = AppScope.read(context);
    var cancelled = false;
    showDialog<void>(useRootNavigator: false, 
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        content: const Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('正在下载回放…')]),
        actions: [
          TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.pop(c);
              },
              child: const Text('取消')),
        ],
      ),
    );
    try {
      final gz = await app.fetchReplayGz(m.id);
      final r = decodeReplayGz(gz);
      if (!mounted || cancelled) return;
      Navigator.pop(context);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReplayPlayerScreen(replay: r, gz: gz)));
      _loadLocal();
    } catch (e) {
      if (!mounted || cancelled) return;
      Navigator.pop(context);
      app.toast('获取回放失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget serverList() {
      final l = app.replayList;
      if (l == null) return const Center(child: CircularProgressIndicator());
      if (l.isEmpty) return const Center(child: Text('还没有回放'));
      return ListView.builder(itemCount: l.length, itemBuilder: (c, i) => _tile(l[i], () => _openServer(l[i])));
    }

    Widget localList() {
      final l = _local;
      if (l == null) return const Center(child: CircularProgressIndicator());
      if (l.isEmpty) return const Center(child: Text('本机还没有保存的回放\n（单机对局结束后自动保存；联机回放可在播放时保存）', textAlign: TextAlign.center));
      return ListView.builder(
        itemCount: l.length,
        itemBuilder: (c, i) => _tile(l[i].meta, () => openLocalReplayFile(context, l[i].file.path), onDelete: () async {
          await ReplayStore.delete(l[i]);
          _loadLocal();
        }),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('对局回放'),
        bottom: TabBar(controller: _tabs, tabs: [
          if (_online) const Tab(text: '全部'),
          if (_online) const Tab(text: '我的'),
          const Tab(text: '本机'),
        ]),
      ),
      body: TabBarView(controller: _tabs, children: [
        if (_online) serverList(),
        if (_online) serverList(),
        localList(),
      ]),
    );
  }

  Widget _tile(ReplayMeta m, VoidCallback onTap, {VoidCallback? onDelete}) {
    final cs = Theme.of(context).colorScheme;
    final rank = m.ranking;
    final players = [
      for (var i = 0; i < m.names.length; i++)
        '${m.names[i]}${rank != null && i < rank.length && rank[i] == 1 ? '🏆' : ''}'
    ].join('、');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: cs.primaryContainer, child: Icon(Icons.slideshow, color: cs.onPrimaryContainer)),
        title: Text(m.gameName, overflow: TextOverflow.ellipsis),
        subtitle: Text('$players\n${formatDate(m.startedAt)} · 时长 ${formatDuration(m.durationMs)}${m.room.isEmpty ? '' : ' · ${m.room}'}',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: true,
        trailing: onDelete == null
            ? const Icon(Icons.play_arrow)
            : IconButton(tooltip: '删除', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      ),
    );
  }
}

/// Plays a [Replay]: board, timeline, speed, perspective, log.
class ReplayPlayerScreen extends StatefulWidget {
  final Replay replay;

  /// Raw gzip bytes (server replay) so it can be saved to this device.
  final Uint8List? gz;
  final String? savedPath;
  final int initialSeat;
  const ReplayPlayerScreen({super.key, required this.replay, this.gz, this.savedPath, this.initialSeat = -1});
  @override
  State<ReplayPlayerScreen> createState() => _ReplayPlayerScreenState();
}

class _ReplayPlayerScreenState extends State<ReplayPlayerScreen> {
  late int _seat = widget.initialSeat;
  int _i = 0;
  bool _playing = false;
  double _speed = 1;
  Timer? _timer;
  String? _saved;

  Replay get r => widget.replay;
  List<(int, Map<String, dynamic>)> get _frames => r.frames(_seat);

  @override
  void initState() {
    super.initState();
    _saved = widget.savedPath;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  int get _t => _frames.isEmpty ? 0 : _frames[_i.clamp(0, _frames.length - 1)].$1;

  void _setSeat(int s) {
    final t = _t;
    setState(() {
      _seat = s;
      _i = _frames.isEmpty ? 0 : Replay.frameAt(_frames, t);
    });
  }

  void _go(int i) {
    final n = _frames.length;
    setState(() => _i = n == 0 ? 0 : i.clamp(0, n - 1));
    if (_i >= n - 1) _pause();
  }

  void _play() {
    if (_frames.length < 2) return;
    if (_i >= _frames.length - 1) _i = 0;
    setState(() => _playing = true);
    _scheduleNext();
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (_playing && mounted) setState(() => _playing = false);
  }

  void _scheduleNext() {
    _timer?.cancel();
    final f = _frames;
    if (!_playing || _i >= f.length - 1) {
      _pause();
      return;
    }
    // real gaps, but long thinking pauses are compressed to 1.5 s
    final gap = (f[_i + 1].$1 - f[_i].$1).clamp(120, 1500);
    _timer = Timer(Duration(milliseconds: (gap / _speed).round()), () {
      if (!mounted) return;
      setState(() => _i++);
      _scheduleNext();
    });
  }

  Future<void> _save() async {
    final gz = widget.gz;
    if (gz == null) return;
    try {
      final f = await ReplayStore.saveGz(r.meta, gz);
      setState(() => _saved = f.path);
      if (mounted) AppScope.read(context).toast('已保存到本机：${f.path}');
    } catch (e) {
      if (mounted) AppScope.read(context).toast('保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final f = _frames;
    final n = f.length;
    final i = n == 0 ? 0 : _i.clamp(0, n - 1);
    final m = r.meta;
    final wide = MediaQuery.of(context).size.width > 1000;
    final short = MediaQuery.of(context).size.height < 500;

    Widget board;
    if (n == 0) {
      board = const Center(child: Text('该视角没有记录'));
    } else {
      final gs = GameState(m.game, _seat, m.names, m.bots, m.avatars, f[i].$2, i == n - 1);
      board = KeyedSubtree(
        key: ValueKey('seat$_seat'),
        child: buildBoard(GameContext(app, gs, replay: true, optionsOverride: m.options)),
      );
    }

    final t = n == 0 ? 0 : f[i].$1;
    final logs = [for (final l in r.logs) if (l.isNotEmpty && l[0] is num && (l[0] as num) <= t) l];
    final logPanel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(children: [
          Icon(Icons.receipt_long, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          const Text('对局记录', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(8),
          itemCount: logs.length,
          itemBuilder: (c, k) {
            final l = logs[logs.length - 1 - k];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${formatDuration((l[0] as num).toInt())}  ${l.length > 1 ? l[1] : ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.85))),
            );
          },
        ),
      ),
    ]);

    final controls = Material(
      color: cs.surface.withValues(alpha: 0.92),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 8, 2),
        child: Row(children: [
          IconButton(tooltip: '上一步', visualDensity: VisualDensity.compact, onPressed: i > 0 ? () => _go(i - 1) : null, icon: const Icon(Icons.skip_previous)),
          IconButton(
            tooltip: _playing ? '暂停' : '播放',
            visualDensity: VisualDensity.compact,
            onPressed: _playing ? _pause : _play,
            icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, size: 30, color: cs.primary),
          ),
          IconButton(tooltip: '下一步', visualDensity: VisualDensity.compact, onPressed: i < n - 1 ? () => _go(i + 1) : null, icon: const Icon(Icons.skip_next)),
          Expanded(
            child: Slider(
              value: n <= 1 ? 0 : i.toDouble(),
              min: 0,
              max: n <= 1 ? 1 : (n - 1).toDouble(),
              onChanged: n <= 1 ? null : (v) => _go(v.round()),
            ),
          ),
          Text('${formatDuration(t)} / ${formatDuration(m.durationMs)}', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          PopupMenuButton<double>(
            tooltip: '播放速度',
            initialValue: _speed,
            onSelected: (v) {
              setState(() => _speed = v);
              if (_playing) _scheduleNext();
            },
            itemBuilder: (_) => [for (final s in const [0.5, 1.0, 2.0, 4.0]) PopupMenuItem(value: s, child: Text('${_fmtSpeed(s)}x'))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text('${_fmtSpeed(_speed)}x', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
            ),
          ),
        ]),
      ),
    );

    final seatPicker = DropdownButton<int>(
      value: _seat,
      underline: const SizedBox(),
      isDense: true,
      items: [
        const DropdownMenuItem(value: -1, child: Text('观众视角')),
        for (var s = 0; s < m.names.length; s++)
          DropdownMenuItem(value: s, child: Text('${m.names[s]} 视角', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => _setSeat(v ?? -1),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        title: Text('回放 · ${m.gameName}', overflow: TextOverflow.ellipsis),
        actions: [
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: seatPicker),
          if (widget.gz != null && _saved == null)
            IconButton(tooltip: '保存到本机', onPressed: _save, icon: const Icon(Icons.download)),
          if (_saved != null)
            IconButton(
              tooltip: '复制文件路径',
              onPressed: () => copyText(context, _saved!),
              icon: const Icon(Icons.folder_open),
            ),
          IconButton(
            tooltip: '规则说明',
            onPressed: () => showRulesDialog(context, app.gameInfo(m.game) ?? findGame(m.game)?.toJson()),
            icon: const Icon(Icons.menu_book),
          ),
          if (!wide)
            Builder(
              builder: (c) => IconButton(tooltip: '对局记录', onPressed: () => Scaffold.of(c).openEndDrawer(), icon: const Icon(Icons.receipt_long)),
            ),
        ],
      ),
      endDrawer: wide ? null : Drawer(width: 320, child: SafeArea(child: logPanel)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: wide
                ? Row(children: [
                    Expanded(child: board),
                    SizedBox(width: 300, child: Card(margin: const EdgeInsets.fromLTRB(0, 8, 8, 8), child: logPanel)),
                  ])
                : board,
          ),
          SizedBox(height: short ? 44 : 52, child: controls),
        ]),
      ),
    );
  }

  static String _fmtSpeed(double s) => s == s.roundToDouble() ? '${s.toInt()}' : '$s';
}
