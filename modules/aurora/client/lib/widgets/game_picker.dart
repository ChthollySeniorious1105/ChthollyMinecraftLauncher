import 'dart:math';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../state/app_state.dart';

class CreateRoomResult {
  final String name;
  final String game;
  final Map<String, dynamic> options;
  final String password;
  final bool private;
  CreateRoomResult(this.name, this.game, this.options, this.password, this.private);
}

/// Games grouped by category with a search box; returns a game id.
class GamePickerGrid extends StatefulWidget {
  final List<Map<String, dynamic>> games;
  final String? selected;
  final ValueChanged<String> onPick;
  const GamePickerGrid({super.key, required this.games, required this.onPick, this.selected});

  static const categoryIcons = {
    '麻将': Icons.grid_view_rounded,
    '棋类': Icons.extension,
    '牌类': Icons.style,
    '桌游': Icons.casino,
    '派对': Icons.celebration,
  };

  @override
  State<GamePickerGrid> createState() => _GamePickerGridState();
}

class _GamePickerGridState extends State<GamePickerGrid> {
  String _q = '';
  String? _cat;
  int _playersFilter = 0, _minutes = 0, _difficulty = 0;
  String _mode = '';

  static String _players(Map<String, dynamic> g) {
    final p = (g['players'] as List?)?.cast<int>();
    if (p == null || p.length != 2) return '';
    return p[0] == p[1] ? '${p[0]}人' : '${p[0]}-${p[1]}人';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    final cats = <String, List<Map<String, dynamic>>>{};
    for (final g in widget.games) {
      cats.putIfAbsent('${g['category']}', () => []);
      if (_cat != null && g['category'] != _cat) continue;
      if (!matchesGame(g, players: _playersFilter, minutes: _minutes, difficulty: _difficulty, mode: _mode)) continue;
      if (q.isNotEmpty &&
          !'${g['name']}'.toLowerCase().contains(q) &&
          !'${g['id']}'.contains(q) &&
          !'${g['description']}'.toLowerCase().contains(q)) {
        continue;
      }
      cats['${g['category']}']!.add(g);
    }
    final shown = cats.entries.where((e) => e.value.isNotEmpty).toList();
    final app = context.getInheritedWidgetOfExactType<AppScope>()?.notifier;
    Map<String, dynamic>? byId(String id) {
      for (final g in widget.games) {
        if (g['id'] == id) return g;
      }
      return null;
    }

    final showQuick = app != null && q.isEmpty && _cat == null && _playersFilter == 0 && _minutes == 0 && _difficulty == 0 && _mode.isEmpty;
    final favs = showQuick ? [for (final id in app.favoriteGames) ?byId(id)] : const <Map<String, dynamic>>[];
    final recents = showQuick
        ? [for (final id in app.recentGames) if (!app.favoriteGames.contains(id)) ?byId(id)]
        : const <Map<String, dynamic>>[];
    final sel = widget.selected;
    Widget section(IconData icon, String title, List<Map<String, dynamic>> gs) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
              child: Row(children: [
                Icon(icon, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
              ]),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final g in gs) _chip(context, g, app)]),
          ],
        );
    return Column(children: [
      SizedBox(height: 46, child: ListView(scrollDirection: Axis.horizontal, children: [
        _filter<int>('人数', _playersFilter, {0: '不限', for (var i = 1; i <= 12; i++) i: '$i 人'}, (v) => _playersFilter = v),
        _filter<int>('时长', _minutes, {0: '不限', 5: '约 5 分钟', 15: '约 15 分钟', 30: '30 分钟内', 60: '约 1 小时'}, (v) => _minutes = v),
        _filter<int>('难度', _difficulty, {0: '不限', 1: '入门', 2: '中等及以下', 3: '含进阶'}, (v) => _difficulty = v),
        _filter<String>('玩法', _mode, {'': '不限', 'coop': '合作', 'competitive': '对战'}, (v) => _mode = v),
        TextButton.icon(onPressed: shown.isEmpty ? null : () { final choices = shown.expand((e) => e.value).toList(); widget.onPick('${choices[Random().nextInt(choices.length)]['id']}'); }, icon: const Icon(Icons.shuffle, size: 18), label: const Text('帮我选')),
      ])),
      Row(children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索游戏（名称/简介）'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        if (app != null && sel != null)
          IconButton(
            tooltip: app.isFavorite(sel) ? '取消收藏当前游戏' : '收藏当前游戏（也可长按游戏）',
            onPressed: () => setState(() => app.toggleFavorite(sel)),
            icon: Icon(app.isFavorite(sel) ? Icons.star : Icons.star_border, color: app.isFavorite(sel) ? Colors.amber : null),
          ),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text('全部 ${widget.games.length}'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
          ),
          for (final c in cats.keys)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                avatar: Icon(GamePickerGrid.categoryIcons[c] ?? Icons.games, size: 16),
                label: Text(c),
                selected: _cat == c,
                onSelected: (_) => setState(() => _cat = _cat == c ? null : c),
              ),
            ),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? const Center(child: Text('没有匹配的游戏'))
            : ListView(children: [
                if (favs.isNotEmpty) section(Icons.star, '收藏', favs),
                if (recents.isNotEmpty) section(Icons.history, '最近玩过', recents),
                for (final e in shown) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Row(children: [
                      Icon(GamePickerGrid.categoryIcons[e.key] ?? Icons.games, size: 18, color: cs.primary),
                      const SizedBox(width: 6),
                      Text('${e.key}（${e.value.length}）', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
                    ]),
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final g in e.value) _chip(context, g, app),
                  ]),
                ],
              ]),
      ),
    ]);
  }

  Widget _filter<T>(String label, T value, Map<T, String> choices, void Function(T) changed) => Padding(
    padding: const EdgeInsets.only(right: 8), child: PopupMenuButton<T>(initialValue: value,
      onSelected: (v) => setState(() => changed(v)), itemBuilder: (_) => [for (final e in choices.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
      child: Chip(label: Text('$label：${choices[value]}'), avatar: const Icon(Icons.filter_list, size: 16))));

  Widget _chip(BuildContext context, Map<String, dynamic> g, AppState? app) {
    final cs = Theme.of(context).colorScheme;
    final id = '${g['id']}';
    final fav = app?.isFavorite(id) ?? false;
    void toggle() {
      if (app == null) return;
      setState(() => app.toggleFavorite(id));
    }

    return Tooltip(
      message: '${g['description']}${app == null ? '' : '\n（长按 / 右键：${fav ? '取消收藏' : '收藏'}）'}',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        onLongPress: toggle,
        onSecondaryTap: toggle,
        child: ChoiceChip(
          avatar: fav ? const Icon(Icons.star, size: 14, color: Colors.amber) : null,
          label: Text.rich(TextSpan(children: [
            TextSpan(text: '${g['name']}'),
            if (_players(g).isNotEmpty)
              TextSpan(text: ' ${_players(g)}', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
          ])),
          selected: id == widget.selected,
          onSelected: (_) => widget.onPick(id),
        ),
      ),
    );
  }
}

/// Renders option dropdowns for a game definition.
class GameOptionsForm extends StatelessWidget {
  final Map<String, dynamic> game;
  final Map<String, dynamic> values;
  final void Function(String key, Object value)? onChanged;
  const GameOptionsForm({super.key, required this.game, required this.values, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final opts = (game['options'] as List? ?? []).cast<Map>();
    if (opts.isEmpty) return const Text('该游戏没有可调整的选项');
    return Wrap(spacing: 12, runSpacing: 10, children: [
      for (final o in opts)
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<Object>(
            initialValue: values[o['key']] ?? o['default'],
            isExpanded: true,
            decoration: InputDecoration(labelText: '${o['label']}'),
            items: [
              for (final c in (o['choices'] as List).cast<Map>())
                DropdownMenuItem(value: c['value'] as Object, child: Text('${c['label']}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged == null ? null : (v) => onChanged!('${o['key']}', v!),
          ),
        ),
    ]);
  }
}

class CreateRoomDialog extends StatefulWidget {
  final AppState app;
  const CreateRoomDialog({super.key, required this.app});
  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  late final TextEditingController _name = TextEditingController(text: '${widget.app.name}的房间');
  final _pwd = TextEditingController();
  bool _private = false;
  late String _game = widget.app.prefs.getString('lastGame') ?? '${widget.app.games.first['id']}';
  final Map<String, dynamic> _opts = {};

  @override
  Widget build(BuildContext context) {
    final g = widget.app.gameInfo(_game) ?? widget.app.games.first;
    _game = '${g['id']}';
    return AlertDialog(
      title: const Text('创建房间'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: TextField(controller: _name, decoration: const InputDecoration(labelText: '房间名'))),
            const SizedBox(width: 12),
            SizedBox(
                width: 160,
                child: TextField(controller: _pwd, decoration: const InputDecoration(labelText: '密码（可选）'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.public, size: 16), label: Text('公开')),
                ButtonSegment(value: true, icon: Icon(Icons.lock_outline, size: 16), label: Text('私密')),
              ],
              selected: {_private},
              onSelectionChanged: (v) => setState(() => _private = v.first),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_private ? '不在大厅显示，仅凭 5 位房间号进入' : '所有人都能在大厅看到并加入',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: GamePickerGrid(
              games: widget.app.games,
              selected: _game,
              onPick: (id) => setState(() {
                _game = id;
                _opts.clear();
              }),
            ),
          ),
          const Divider(),
          Text('${g['name']}：${g['description']}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          GameOptionsForm(game: g, values: _opts, onChanged: (k, v) => setState(() => _opts[k] = v)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            widget.app.prefs.setString('lastGame', _game);
            Navigator.pop(context, CreateRoomResult(_name.text.trim(), _game, Map.of(_opts), _pwd.text, _private));
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}
