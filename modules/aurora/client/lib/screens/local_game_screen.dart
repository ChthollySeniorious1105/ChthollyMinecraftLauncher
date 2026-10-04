import '../i18n/aurora_i18n.dart';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../games/boards.dart';
import '../main.dart';
import '../platform/game_ui.dart';
import '../platform/local_session.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/game_picker.dart';
import 'replay_screen.dart';

/// 单机游戏 setup: game, options, player count, bot level.
class LocalSetupScreen extends StatefulWidget {
  const LocalSetupScreen({super.key});
  @override
  State<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends State<LocalSetupScreen> {
  late final List<Map<String, dynamic>> _games = [
    for (final g in gameRegistry)
      if (g.botSupport) g.toJson(),
  ];
  late String _game;
  final Map<String, dynamic> _opts = {};
  int? _players;
  late int _level;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    final last = app.prefs.getString('localGame');
    _game = _games.any((g) => g['id'] == last)
        ? last!
        : '${_games.first['id']}';
    _level = app.prefs.getInt('localBotLevel') ?? 1;
  }

  GameDef get _def => findGame(_game)!;

  void _start() {
    final app = AppScope.read(context);
    final def = _def;
    final opts = def.normalizeOptions(_opts);
    final (lo, hi) = def.playerRange(opts);
    final players = (_players ?? lo).clamp(lo, hi);
    app.prefs.setString('localGame', _game);
    app.prefs.setInt('localBotLevel', _level);
    final s = LocalSession(
      def: def,
      options: opts,
      players: players,
      botLevel: _level,
      humanName: app.name,
      humanAvatar: app.avatar,
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
    app.startLocal(s);
  }

  @override
  Widget build(BuildContext context) {
    final def = _def;
    final g = def.toJson();
    final (lo, hi) = def.playerRange(def.normalizeOptions(_opts));
    final players = (_players ?? lo).clamp(lo, hi);
    final wide = MediaQuery.of(context).size.width > 760;
    final picker = GamePickerGrid(
      games: _games,
      selected: _game,
      onPick: (id) => setState(() {
        _game = id;
        _opts.clear();
        _players = null;
      }),
    );
    final form = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          auroraGameText('${g['name']}'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(auroraEnglish['${g['description']}'] ?? '${g['description']}'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showRulesDialog(context, g),
            icon: const Icon(Icons.menu_book, size: 18),
            label: const AuroraText('规则说明'),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                key: ValueKey('p$_game$lo$hi'),
                initialValue: players,
                decoration: InputDecoration(labelText: auroraT('人数（你 + 电脑）')),
                items: [
                  for (var p = lo; p <= hi; p++)
                    DropdownMenuItem(value: p, child: AuroraText('$p 人')),
                ],
                onChanged: lo == hi
                    ? null
                    : (v) => setState(() => _players = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                initialValue: _level,
                decoration: InputDecoration(labelText: auroraT('电脑难度')),
                items: [
                  for (var i = 0; i < kBotLevels.length; i++)
                    DropdownMenuItem(value: i, child: Text(kBotLevels[i])),
                ],
                onChanged: (v) => setState(() => _level = v ?? 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GameOptionsForm(
          key: ValueKey(_game),
          game: g,
          values: _opts,
          onChanged: (k, v) => setState(() => _opts[k] = v),
        ),
        if ((g['options'] as List).any((o) => (o as Map)['key'] == 'ai'))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('单机模式没有大模型 AI，将使用普通电脑', style: TextStyle(fontSize: 12)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const AuroraText('开始游戏'),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const AuroraText('单机游戏（与电脑对战）')),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: picker,
                    ),
                  ),
                  SizedBox(
                    width: 380,
                    child: Card(margin: const EdgeInsets.all(12), child: form),
                  ),
                ],
              )
            : Column(
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: picker,
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(flex: 6, child: form),
                ],
              ),
      ),
    );
  }
}

/// A running single-player game (reuses the normal boards).
class LocalGameScreen extends StatelessWidget {
  const LocalGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.local!;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => _build(context, app, s),
    );
  }

  Widget _build(BuildContext context, AppState app, LocalSession s) {
    final wide = MediaQuery.of(context).size.width > 1000;
    final st = s.state;
    final over = s.isOver;
    final model = GameActionsModel(
      canPlay: !over,
      auto: s.auto,
      canResign: s.canResign,
      canDraw: s.canDraw,
      canUndo: s.canUndo,
      onEmote: () async {
        final e = await pickEmote(context);
        if (e != null) app.sendEmote(e);
      },
      onAuto: s.setAuto,
      onResign: s.resign,
      onDraw: s.offerDraw,
      onUndo: s.undo,
      onRules: () => showRulesDialog(context, s.def.toJson()),
    );
    final board = st == null
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              Positioned.fill(child: buildBoard(GameContext(app, st))),
              if (s.auto && !over)
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: AutoPlayChip(onCancel: () => s.setAuto(false)),
                ),
              Positioned.fill(child: EmoteOverlay(events: app.emotes)),
              if (over)
                Positioned(
                  bottom: 8,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: s.begin,
                          icon: const Icon(Icons.replay),
                          label: const AuroraText('再来一局'),
                        ),
                        if (s.replayPath != null)
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                openLocalReplayFile(context, s.replayPath!),
                            icon: const Icon(Icons.slideshow),
                            label: const AuroraText('看回放'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: app.endLocal,
                          icon: const Icon(Icons.exit_to_app),
                          label: const AuroraText('返回'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
    final logPanel = _LogPanel(lines: s.logs);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 46,
        leading: IconButton(
          tooltip: auroraT('退出单机游戏'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (!over &&
                !await confirmDialog(context, '退出本局？', '当前对局不会保存。', '退出'))
              return;
            app.endLocal();
          },
        ),
        title: Text('${auroraT('单机游戏')} · ${auroraGameText(s.def.name)}', overflow: TextOverflow.ellipsis),
        actions: [
          if (s.canUndo)
            IconButton(
              tooltip: auroraT('悔棋'),
              visualDensity: VisualDensity.compact,
              onPressed: s.undo,
              icon: const Icon(Icons.undo),
            ),
          GameActionsBar(model),
          if (!wide)
            Builder(
              builder: (context) => IconButton(
                tooltip: auroraT('对局记录'),
                icon: const Icon(Icons.receipt_long),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
        ],
      ),
      endDrawer: wide
          ? null
          : Drawer(width: 320, child: SafeArea(child: logPanel)),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  Expanded(child: board),
                  SizedBox(
                    width: 300,
                    child: Card(
                      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      child: logPanel,
                    ),
                  ),
                ],
              )
            : board,
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  final List<ChatLine> lines;
  const _LogPanel({required this.lines});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Icon(Icons.receipt_long, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              const Text('对局记录', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: AuroraText('暂无记录'))
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: lines.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '· ${lines[lines.length - 1 - i].text}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
