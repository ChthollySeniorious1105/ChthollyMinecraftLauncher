import '../i18n/aurora_i18n.dart';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/common.dart';

/// 我的战绩 + 排行榜.
class StatsScreen extends StatefulWidget {
  final int initialTab;
  const StatsScreen({super.key, this.initialTab = 0});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  String? _game;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    app.myStats = null;
    app.requestStats();
    _game =
        app.recentGames.isNotEmpty &&
            app.gameInfo(app.recentGames.first) != null
        ? app.recentGames.first
        : (app.games.isNotEmpty ? '${app.games.first['id']}' : null);
    if (_game != null) app.requestLeaderboard(_game!);
  }

  String _gameName(String id) => '${AppScope.read(context).gameInfo(id)?['name'] ?? auroraGameText(id)}';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const AuroraText('战绩与排行'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '我的战绩'),
              Tab(text: '排行榜'),
            ],
          ),
        ),
        body: TabBarView(children: [_mine(context), _board(context)]),
      ),
    );
  }

  Widget _mine(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final s = app.myStats;
    if (s == null) return const Center(child: CircularProgressIndicator());
    final games = asInt(s['games'], 0), wins = asInt(s['wins'], 0);
    final per = ((s['per'] as Map?) ?? const {}).cast<String, dynamic>();
    final rows =
        per.entries
            .where((e) => e.value is Map)
            .map((e) => (e.key, (e.value as Map).cast<String, dynamic>()))
            .toList()
          ..sort((a, b) => asInt(b.$2['p'], 0).compareTo(asInt(a.$2['p'], 0)));
    Widget stat(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: cs.primary,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Row(
              children: [
                Avatar(app.avatar, size: 48),
                const SizedBox(width: 8),
                stat('总局数', '$games'),
                stat('胜局', '$wins'),
                stat(
                  '胜率',
                  games == 0 ? '-' : '${(wins * 100 / games).round()}%',
                ),
              ],
            ),
          ),
        ),
        if (app.pid.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: AuroraText('服务器未返回玩家身份，暂不记录战绩'),
          ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: AuroraText('还没有对局记录（与电脑或好友完成一局后显示）')),
          ),
        for (final (id, r) in rows)
          Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              title: Text(_gameName(id), overflow: TextOverflow.ellipsis),
              subtitle: Text('${asInt(r['p'], 0)} 局 · ${asInt(r['w'], 0)} 胜'),
              trailing: Text(
                '${asInt(r['elo'], 1500)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  fontSize: 16,
                ),
              ),
              onTap: () {
                setState(() => _game = id);
                app.requestLeaderboard(id);
                DefaultTabController.of(context).animateTo(1);
              },
            ),
          ),
      ],
    );
  }

  Widget _board(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final g = _game;
    final rows = g == null ? null : app.leaderboards[g];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: DropdownButtonFormField<String>(
            key: ValueKey(g),
            initialValue: g,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: auroraT('游戏'),
              prefixIcon: Icon(Icons.sports_esports),
            ),
            items: [
              for (final x in app.games)
                DropdownMenuItem(
                  value: '${x['id']}',
                  child: Text('${x['name']}', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _game = v);
              app.requestLeaderboard(v);
            },
          ),
        ),
        Expanded(
          child: rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
              ? const Center(child: AuroraText('暂无上榜玩家（至少完成 3 局才上榜）'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (c, i) {
                    final r = rows[i];
                    final medal = i < 3
                        ? [
                            Colors.amber,
                            Colors.blueGrey.shade300,
                            Colors.brown.shade300,
                          ][i]
                        : null;
                    return ListTile(
                      leading: SizedBox(
                        width: 64,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: medal ?? cs.onSurface,
                                ),
                              ),
                            ),
                            Avatar(asInt(r['avatar'], 0), size: 34),
                          ],
                        ),
                      ),
                      title: Text(
                        asStr(r['name']),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${asInt(r['p'], 0)} 局 · ${asInt(r['w'], 0)} 胜',
                      ),
                      trailing: Text(
                        '${asInt(r['elo'], 1500)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                          fontSize: 16,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
