import 'dart:async';

import 'package:flutter/material.dart';

import 'package:aurora_shared/aurora_shared.dart';

import '../games/boards.dart';
import '../main.dart';
import '../platform/game_ui.dart';
import '../state/app_state.dart';
import '../widgets/chat_panel.dart';
import '../widgets/common.dart';
import '../widgets/game_picker.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final room = app.room!;
    final wide = MediaQuery.of(context).size.width > 1000;
    final gameName = app.gameInfo('${room['game']}')?['name'] ?? room['game'];
    final showBoard = app.game != null;
    final main = showBoard ? _GameArea(app: app) : _SeatsArea(app: app);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        leading: IconButton(
          tooltip: '离开房间',
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (app.room?['playing'] == true && app.mySeat >= 0) {
              final ok = await showDialog<bool>(useRootNavigator: false, 
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('离开房间？'),
                  content: const Text('对局进行中，离开后将由电脑托管你的座位。'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('离开')),
                  ],
                ),
              );
              if (ok != true) return;
            }
            app.send({'t': 'leave_room'});
          },
        ),
        title: LayoutBuilder(builder: (context, c) {
          final narrow = c.maxWidth < 260;
          final chip = ActionChip(
            avatar: const Icon(Icons.copy, size: 14),
            visualDensity: narrow ? VisualDensity.compact : null,
            label: Text(narrow ? '${room['id']}' : '房间号 ${room['id']}',
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            onPressed: () => copyText(context, '${room['id']}'),
          );
          if (c.maxWidth < 150) return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: chip);
          return Row(children: [
            if (room['private'] == true) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.lock_outline, size: 18)),
            Flexible(child: Text(narrow ? '$gameName' : '${room['name']} · $gameName', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            chip,
          ]);
        }),
        actions: [
          if (showBoard)
            GameActionsBar(_actionsModel(context, app))
          else
            IconButton(
              tooltip: '规则说明',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.menu_book),
              onPressed: () => showRulesDialog(context, app.gameInfo('${room['game']}')),
            ),
          const VoiceControls(),
          if (app.isHost && showBoard)
            IconButton(
              tooltip: app.game!.over ? '返回房间' : '结束对局',
              icon: Icon(app.game!.over ? Icons.meeting_room : Icons.stop_circle_outlined),
              onPressed: () async {
                if (!app.game!.over) {
                  final ok = await showDialog<bool>(useRootNavigator: false, 
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('结束对局？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('结束')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  app.send({'t': 'abort'});
                  return;
                }
                app.leaveFinishedGame();
              },
            ),
          if (!app.isHost && showBoard && app.game!.over)
            IconButton(
              tooltip: '返回房间',
              icon: const Icon(Icons.meeting_room),
              onPressed: app.leaveFinishedGame,
            ),
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: '聊天',
                icon: Badge(
                  isLabelVisible: app.unreadChat > 0,
                  label: Text('${app.unreadChat > 99 ? 99 : app.unreadChat}'),
                  child: const Icon(Icons.chat),
                ),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
        ],
      ),
      endDrawer: wide ? null : const Drawer(width: 340, child: SafeArea(child: ChatPanel(voice: false))),
      body: SafeArea(
        child: wide
            ? Row(children: [
                Expanded(child: main),
                SizedBox(
                  width: 320,
                  child: Card(margin: const EdgeInsets.fromLTRB(0, 8, 8, 8), child: const ChatPanel(voice: false)),
                ),
              ])
            : main,
      ),
    );
  }
}

GameActionsModel _actionsModel(BuildContext context, AppState app) {
  final caps = app.caps;
  final g = app.game;
  final playing = g != null && !g.over && g.seat >= 0 && app.mySeat >= 0;
  return GameActionsModel(
    canPlay: playing,
    auto: app.myAuto,
    canResign: caps['resign'] == true,
    canDraw: caps['draw'] == true,
    canUndo: caps['undo'] == true,
    requestPending: app.pendingRequest != null,
    onEmote: () async {
      final e = await pickEmote(context);
      if (e != null) app.sendEmote(e);
    },
    onAuto: (on) => app.send({'t': Msg.autoPlay, 'on': on}),
    onResign: () => app.send({'t': Msg.resign}),
    onDraw: () => app.send({'t': Msg.request, 'kind': 'draw'}),
    onUndo: () => app.send({'t': Msg.request, 'kind': 'undo'}),
    onRules: () => showRulesDialog(context, app.gameInfo('${app.room?['game']}')),
  );
}

class _GameArea extends StatelessWidget {
  final AppState app;
  const _GameArea({required this.app});

  /// Seats that resigned, from the engine's optional `resigned` view field
  /// (a bool list per seat or a list of seat numbers).
  static List<int> _resigned(GameContext g) {
    final r = g.view['resigned'];
    if (r is int) return r >= 0 && r < g.players ? [r] : const [];
    if (r is! List) return const [];
    if (r.isNotEmpty && r.first is bool) return [for (var i = 0; i < r.length; i++) if (r[i] == true) i];
    return [for (final x in r) if (x is int && x >= 0 && x < g.players) x];
  }

  @override
  Widget build(BuildContext context) {
    final g = GameContext(app, app.game!);
    final mine = g.state.deadlines[g.seat];
    final req = app.pendingRequest;
    return Stack(children: [
      Positioned.fill(child: buildBoard(g)),
      if (app.myAuto && !g.over)
        Positioned(
          bottom: 8,
          left: 8,
          child: AutoPlayChip(onCancel: () => app.send({'t': Msg.autoPlay, 'on': false})),
        ),
      Positioned.fill(child: EmoteOverlay(events: app.emotes)),
      if (_resigned(g).isNotEmpty)
        Positioned(
          bottom: 44,
          left: 8,
          child: Chip(
            avatar: const Icon(Icons.flag, size: 16),
            label: Text('已认输：${_resigned(g).map(g.name).join('、')}', style: const TextStyle(fontSize: 12)),
          ),
        ),
      if (req != null && !g.over)
        Positioned.fill(
          child: RequestOverlay(
            request: req,
            myId: app.myId,
            onRespond: (yes) => app.send({'t': Msg.respond, 'id': req['id'], 'yes': yes}),
          ),
        ),
      if (mine != null && !g.over)
        Positioned(top: 4, right: 8, child: TurnClock(g.state.received.add(Duration(milliseconds: mine)))),
      if (app.autoLeaveAt != null)
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: Center(child: _AutoLeaveChip(app: app, at: app.autoLeaveAt!)),
        ),
      if (g.spectator)
        const Positioned(top: 4, left: 4, child: Chip(label: Text('观战中'), avatar: Icon(Icons.visibility, size: 16))),
    ]);
  }
}

/// "3 秒后返回房间" countdown shown over the final result.
class _AutoLeaveChip extends StatefulWidget {
  final AppState app;
  final DateTime at;
  const _AutoLeaveChip({required this.app, required this.at});
  @override
  State<_AutoLeaveChip> createState() => _AutoLeaveChipState();
}

class _AutoLeaveChipState extends State<_AutoLeaveChip> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = (widget.at.difference(DateTime.now()).inMilliseconds / 1000).ceil().clamp(0, 99);
    return ActionChip(
      avatar: const Icon(Icons.meeting_room, size: 16),
      label: Text('$left 秒后返回房间 · 点击立即返回'),
      onPressed: widget.app.leaveFinishedGame,
    );
  }
}

class _SeatsArea extends StatelessWidget {
  final AppState app;
  const _SeatsArea({required this.app});

  @override
  Widget build(BuildContext context) {
    final room = app.room!;
    final cs = Theme.of(context).colorScheme;
    final seats = app.seats;
    final range = (room['range'] as List).cast<int>();
    final gameId = '${room['game']}';
    final info = app.gameInfo(gameId);
    final options = (room['options'] as Map).cast<String, dynamic>();
    final mySeat = app.mySeat;
    final myReady = mySeat >= 0 && seats[mySeat]['ready'] == true;
    final filled = seats.where((s) => s['client'] != null || s['bot'] == true).length;
    final talking = app.voice.talking;

    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.sports_esports, color: cs.primary),
                const SizedBox(width: 8),
                Text('${info?['name'] ?? gameId}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                Text(range[0] == range[1] ? '${range[0]} 人' : '${range[0]}~${range[1]} 人',
                    style: TextStyle(color: cs.secondary)),
              ]),
              if (app.isHost)
                OutlinedButton.icon(
                  onPressed: () => _changeGame(context),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('更换游戏'),
                ),
              if (app.isHost)
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.public, size: 16), label: Text('公开')),
                    ButtonSegment(value: true, icon: Icon(Icons.lock_outline, size: 16), label: Text('私密')),
                  ],
                  selected: {room['private'] == true},
                  onSelectionChanged: (v) => app.send({'t': 'set_private', 'private': v.first}),
                )
              else
                Chip(
                  avatar: Icon(room['private'] == true ? Icons.lock_outline : Icons.public, size: 16),
                  label: Text(room['private'] == true ? '私密房间' : '公开房间'),
                ),
            ]),
            if (room['private'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('私密房间不会出现在大厅列表中，好友需在大厅输入房间号 ${room['id']} 进入',
                    style: TextStyle(fontSize: 12, color: cs.secondary)),
              ),
            const SizedBox(height: 6),
            Text('${info?['description'] ?? ''}'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              OutlinedButton.icon(
                onPressed: () => showRulesDialog(context, info),
                icon: const Icon(Icons.menu_book, size: 18),
                label: const Text('规则'),
              ),
              OutlinedButton.icon(
                onPressed: () => copyText(context, inviteText(app)),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('复制邀请'),
              ),
            ]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: 200,
                child: DropdownButtonFormField<int>(
                  initialValue: (room['turnTimeout'] as int?) ?? 0,
                  decoration: const InputDecoration(labelText: '思考时间（超时电脑代打）'),
                  items: [
                    for (final t in const [0, 15, 30, 60, 90, 120, 300])
                      DropdownMenuItem(value: t, child: Text(t == 0 ? '不限' : '$t 秒')),
                  ],
                  onChanged: app.isHost ? (v) => app.send({'t': 'set_timeout', 'sec': v}) : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: 200,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('botLevel${app.botLevel}'),
                  initialValue: app.botLevel,
                  decoration: const InputDecoration(labelText: '电脑难度'),
                  items: [
                    for (var i = 0; i < kBotLevels.length; i++) DropdownMenuItem(value: i, child: Text(kBotLevels[i])),
                  ],
                  onChanged: app.isHost && room['playing'] != true
                      ? (v) => app.send({'t': Msg.setRoomOpts, 'botLevel': v})
                      : null,
                ),
              ),
            ),
            if (info != null && _hasAiOption(info) && !app.serverAi)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16, color: cs.secondary),
                  const SizedBox(width: 6),
                  Flexible(child: Text('服务器未配置 AI，将使用普通电脑', style: TextStyle(fontSize: 12, color: cs.secondary))),
                ]),
              )
            else if (info != null && _hasAiOption(info) && app.aiLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('AI 电脑：${app.aiLabel}', style: TextStyle(fontSize: 12, color: cs.secondary)),
              ),
            if (info != null)
              GameOptionsForm(
                game: info,
                values: options,
                onChanged: app.isHost
                    ? (k, v) => app.send({'t': 'set_game', 'game': gameId, 'options': {...options, k: v}})
                    : null,
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (var i = 0; i < seats.length; i++) _seatCard(context, i, seats[i], talking),
      ]),
      const SizedBox(height: 20),
      Center(
        child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
          if (mySeat < 0)
            FilledButton.tonalIcon(
              onPressed: () {
                final free = seats.indexWhere((s) => s['client'] == null && s['bot'] != true);
                if (free >= 0) app.send({'t': 'sit', 'seat': free});
              },
              icon: const Icon(Icons.event_seat),
              label: const Text('入座'),
            )
          else ...[
            OutlinedButton.icon(
                onPressed: () => app.send({'t': 'stand'}), icon: const Icon(Icons.visibility), label: const Text('观战')),
            if (!app.isHost)
              FilledButton.icon(
                onPressed: () => app.send({'t': 'ready', 'ready': !myReady}),
                icon: Icon(myReady ? Icons.close : Icons.check),
                label: Text(myReady ? '取消准备' : '准备'),
              ),
          ],
          if (app.isHost)
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
              onPressed: room['canStart'] == true ? () => app.send({'t': 'start'}) : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(room['canStart'] == true
                  ? '开始游戏（$filled 人）'
                  : '人数不足：$filled/${range[0] == range[1] ? range[0] : '${range[0]}~${range[1]}'}'),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      if (app.tally.isNotEmpty) ...[_TallyCard(app: app), const SizedBox(height: 12)],
      _Members(app: app),
    ]);
  }

  static bool _hasAiOption(Map<String, dynamic> info) =>
      (info['options'] as List? ?? const []).any((o) => o is Map && o['key'] == 'ai');

  Widget _seatCard(BuildContext context, int i, Map<String, dynamic> s, Set<int> talking) {
    final cs = Theme.of(context).colorScheme;
    final client = (s['client'] as Map?)?.cast<String, dynamic>();
    final bot = s['bot'] == true;
    final empty = client == null && !bot;
    final isHostSeat = client != null && client['id'] == app.room!['host'];
    final isMe = client != null && client['id'] == app.myId;
    return SizedBox(
      width: 170,
      height: 150,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: isMe ? cs.primary : cs.outline.withValues(alpha: 0.3), width: isMe ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: empty ? () => app.send({'t': 'sit', 'seat': i}) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Row(children: [
                Text('${i + 1}号位', style: TextStyle(fontSize: 12, color: cs.secondary)),
                const Spacer(),
                if (isHostSeat) const Icon(Icons.star, size: 16, color: Colors.amber),
                if (app.isHost && !empty && !isMe)
                  InkWell(
                    onTap: () => app.send({'t': 'remove_seat', 'seat': i}),
                    child: const Icon(Icons.close, size: 16),
                  ),
              ]),
              const Spacer(),
              if (empty) ...[
                Icon(Icons.add_circle_outline, size: 40, color: cs.onSurface.withValues(alpha: 0.4)),
                const SizedBox(height: 4),
                if (app.isHost)
                  TextButton(onPressed: () => app.send({'t': 'add_bot', 'seat': i}), child: const Text('添加电脑'))
                else
                  const Text('空位'),
              ] else ...[
                Avatar(bot ? 0 : asAvatar(client), size: 54, bot: bot, speaking: client != null && talking.contains(client['id']),
                    dim: client != null && client['online'] == false),
                const SizedBox(height: 6),
                Text(bot ? '${s['botName']}' : '${client!['name']}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  bot
                      ? '电脑'
                      : client!['online'] == false
                          ? '离线'
                          : isHostSeat
                              ? '房主'
                              : (s['ready'] == true ? '已准备' : '未准备'),
                  style: TextStyle(
                      fontSize: 12,
                      color: s['ready'] == true || bot || isHostSeat ? Colors.green : cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
              const Spacer(),
            ]),
          ),
        ),
      ),
    );
  }

  int asAvatar(Map<String, dynamic>? c) => (c?['avatar'] as int?) ?? 0;

  Future<void> _changeGame(BuildContext context) async {
    String? picked;
    await showDialog<void>(useRootNavigator: false, 
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('更换游戏'),
        content: SizedBox(
          width: 600,
          height: 460,
          child: GamePickerGrid(
            games: app.games,
            selected: '${app.room!['game']}',
            onPick: (id) {
              picked = id;
              Navigator.pop(c);
            },
          ),
        ),
      ),
    );
    if (picked != null) app.send({'t': 'set_game', 'game': picked, 'options': {}});
  }
}

class _Members extends StatelessWidget {
  final AppState app;
  const _Members({required this.app});
  @override
  Widget build(BuildContext context) {
    final members = (app.room!['members'] as List).cast<Map>();
    return ListenableBuilder(
      listenable: app.voice,
      builder: (context, _) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in members) _chip(context, m),
      ]),
    );
  }

  Widget _chip(BuildContext context, Map m) {
    final chip = Chip(
      avatar: Avatar(m['avatar'] as int, size: 24, speaking: app.voice.talking.contains(m['id']) || (m['id'] == app.myId && app.voice.speaking)),
      label: Text('${m['name']}${m['online'] == false ? '（离线）' : ''}${m['id'] == app.room!['host'] ? ' · 房主' : ''}'),
    );
    if (!app.isHost || m['id'] == app.myId) return chip;
    return PopupMenuButton<String>(
      tooltip: '管理成员',
      onSelected: (v) async {
        if (v != 'kick') return;
        if (await confirmDialog(context, '踢出 ${m['name']}？', '被踢出的玩家 5 分钟内不能再进入本房间。', '踢出')) {
          app.send({'t': Msg.kick, 'id': m['id']});
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'kick', child: ListTile(dense: true, leading: Icon(Icons.person_remove), title: Text('踢出房间'))),
      ],
      child: chip,
    );
  }
}


/// Countdown chip for my own turn clock.
class TurnClock extends StatefulWidget {
  final DateTime deadline;
  const TurnClock(this.deadline, {super.key});
  @override
  State<TurnClock> createState() => _TurnClockState();
}

class _TurnClockState extends State<TurnClock> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 250), (_) => setState(() {}));

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now()).inSeconds.clamp(0, 9999);
    final urgent = left <= 10;
    return Chip(
      avatar: Icon(Icons.timer, size: 16, color: urgent ? Colors.white : null),
      backgroundColor: urgent ? Colors.redAccent : null,
      label: Text('$left 秒', style: TextStyle(color: urgent ? Colors.white : null, fontWeight: FontWeight.bold)),
    );
  }
}
/// "Aurora 房间邀请" text: server address + room code.
String inviteText(AppState app) {
  final game = app.gameInfo('${app.room?['game']}')?['name'] ?? '';
  return '来 Aurora 一起玩$game！服务器地址：${app.address}  房间号：${app.room?['id']}';
}

/// 积分榜: this room's running tally of consecutive games.
class _TallyCard extends StatelessWidget {
  final AppState app;
  const _TallyCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = [...app.tally]..sort((a, b) => asInt(b['points'], 0).compareTo(asInt(a['points'], 0)));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.leaderboard, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            const Text('积分榜', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('换游戏后清零', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(
                    width: 22,
                    child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: i == 0 ? Colors.amber : null))),
                Avatar(asInt(rows[i]['avatar'], 0), size: 24),
                const SizedBox(width: 6),
                Expanded(child: Text(asStr(rows[i]['name']), overflow: TextOverflow.ellipsis)),
                Text('${asInt(rows[i]['wins'], 0)} 胜 / ${asInt(rows[i]['games'], 0)} 局', style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 52,
                  child: Text('${asInt(rows[i]['points'], 0)} 分',
                      textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
