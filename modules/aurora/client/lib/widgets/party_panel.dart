import '../i18n/aurora_i18n.dart';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

import '../state/app_state.dart';

class PartyPanel extends StatelessWidget {
  final AppState app;
  const PartyPanel({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    final party = app.room?['party'] as Map?;
    if (party == null) {
      return app.isHost
          ? OutlinedButton.icon(
              onPressed: () => _configure(context),
              icon: const Icon(Icons.celebration),
              label: const AuroraText('创建派对之夜'),
            )
          : const SizedBox.shrink();
    }
    final q = (party['queue'] as List).cast<String>(),
        index = party['index'] as int;
    final finished = party['finished'] == true,
        complete = party['roundComplete'] == true;
    final rows = (party['scores'] as List).cast<Map>();
    final top = rows.isEmpty ? 0 : rows.first['points'];
    final winners = rows
        .where((r) => r['points'] == top)
        .map((r) => '${r['name']}')
        .join('、');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              finished
                  ? '派对结束！${winners.isEmpty ? '' : '获胜：$winners'}'
                  : '派对之夜 · 第 ${index + 1}/${q.length} 局',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              q.map((id) => '${app.gameInfo(id)?['name'] ?? id}').join(' → '),
            ),
            const SizedBox(height: 8),
            const Text(
              '每局第一名 100 分，其他名次按人数折算；跨游戏累计。',
              style: TextStyle(fontSize: 12),
            ),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('${r['name']}　${r['points']} 分 · ${r['wins']} 胜'),
              ),
            if (complete && !finished) ...[
              const Divider(),
              const AuroraText('投票选择下一款游戏（同票按队列顺序）'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final id in q.skip(index + 1))
                    ChoiceChip(
                      label: Text(
                        '${app.gameInfo(id)?['name'] ?? id} · ${(party['votes'] as Map).values.where((v) => v == id).length} 票',
                      ),
                      selected: (party['votes'] as Map)['${app.myId}'] == id,
                      onSelected: app.mySeat >= 0
                          ? (_) => app.send({'t': Msg.partyVote, 'game': id})
                          : null,
                    ),
                ],
              ),
              if (app.isHost)
                FilledButton(
                  onPressed: () => app.send({'t': Msg.partyNext}),
                  child: const AuroraText('按投票进入下一局'),
                ),
            ],
            if (app.isHost && app.room?['playing'] != true)
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    useRootNavigator: false,
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const AuroraText('结束当前派对？'),
                      content: const AuroraText('本次派对累计积分将清空。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const AuroraText('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const AuroraText('结束'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) app.send({'t': Msg.partyConfig, 'queue': []});
                },
                child: const AuroraText('结束派对'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _configure(BuildContext context) async {
    final selected = <String>[];
    final count = app.seats
        .where((s) => s['client'] != null || s['bot'] == true)
        .length;
    final available = app.games
        .where((g) => matchesGame(g, players: count))
        .toList();
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const AuroraText('派对之夜'),
          content: SizedBox(
            width: 520,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '当前 $count 人，选择 2~8 款游戏。点击顺序就是初始队列。已选 ${selected.length}/8。',
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final g in available)
                        CheckboxListTile(
                          title: Text('${g['name']}'),
                          subtitle: Text('约 ${g['minutes']} 分钟'),
                          value: selected.contains(g['id']),
                          onChanged: (v) => set(() {
                            final id = '${g['id']}';
                            if (v == false) {
                              selected.remove(id);
                            } else if (selected.length < 8) {
                              selected.add(id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const AuroraText('取消'),
            ),
            FilledButton(
              onPressed: selected.length < 2
                  ? null
                  : () {
                      app.send({
                        't': Msg.partyConfig,
                        'queue': List.of(selected),
                      });
                      Navigator.pop(c);
                    },
              child: const AuroraText('创建派对'),
            ),
          ],
        ),
      ),
    );
  }
}
