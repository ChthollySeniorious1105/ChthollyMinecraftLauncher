import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';

final Map<String, BoardBuilder> party4Boards = {
  'memorypairs': (g) => MemoryBoard(g),
  'lightsout': (g) => LightsBoard(g),
  'wordtiles': (g) => WordBoard(g),
};

class PartyBoardPage extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  const PartyBoardPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget scoreList(GameContext g) {
  final scores = (g.view['scores'] as List?) ?? [];
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var s = 0; s < scores.length; s++)
        Chip(
          label: Text(
            '${g.name(s)}：${scores[s]} 分${g.view['teamMode'] == true ? ' · ${s % 2 + 1} 队' : ''}',
          ),
        ),
    ],
  );
}

Widget nextRound(GameContext g) => FilledButton.icon(
  onPressed: !g.over && g.view['canAct'] == true
      ? () => g.act({'continue': true})
      : null,
  icon: const Icon(Icons.arrow_forward),
  label: Text(
    g.over
        ? '本场结束'
        : g.view['canAct'] == true
        ? '继续下一题'
        : '等待其他玩家',
  ),
);

const pairSymbols = [
  '日',
  '月',
  '星',
  '云',
  '山',
  '海',
  '花',
  '叶',
  '火',
  '水',
  '风',
  '雪',
];

class MemoryBoard extends StatelessWidget {
  final GameContext g;
  const MemoryBoard(this.g, {super.key});
  @override
  Widget build(BuildContext context) {
    final v = g.view, cards = v['cards'] as List, owners = v['owners'] as List;
    final mine = !g.over && v['turn'] == g.seat;
    return PartyBoardPage(
      title: '记忆翻翻乐',
      subtitle: g.over
          ? '所有卡片已配对，得分最多者获胜'
          : '轮到 ${g.name(v['turn'] as int)} · 翻开两张相同图案',
      children: [
        scoreList(g),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) => GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: c.maxWidth < 500 ? 4 : 6,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemBuilder: (context, i) => Semantics(
              label:
                  '第 ${i + 1} 张${cards[i] < 0 ? '未翻开的牌' : '，${pairSymbols[cards[i] as int]}'}',
              child: FilledButton.tonal(
                onPressed:
                    mine && v['reveal'] != true && owners[i] < 0 && cards[i] < 0
                    ? () => g.act({'cell': i})
                    : null,
                child: Text(
                  cards[i] < 0 ? '?' : pairSymbols[cards[i] as int],
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (v['reveal'] == true && !g.over)
          FilledButton(
            onPressed: mine ? () => g.act({'continue': true}) : null,
            child: const Text('记住了，继续'),
          ),
      ],
    );
  }
}

class LightsBoard extends StatelessWidget {
  final GameContext g;
  const LightsBoard(this.g, {super.key});
  @override
  Widget build(BuildContext context) {
    final v = g.view, b = v['board'] as List, n = v['size'] as int;
    return LayoutBuilder(
      builder: (context, bounds) {
        final side = min(
          480.0,
          min(
            bounds.maxWidth - 32,
            max(n * 52.0 + (n - 1) * 8, bounds.maxHeight - 180),
          ),
        );
        return PartyBoardPage(
          title: '熄灯挑战',
          subtitle: g.over
              ? '${g.name(v['winner'] as int)} 已熄灭全部灯！'
              : '点击一格，切换自己与上下左右的灯。目标：全部熄灭。',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < g.players; i++)
                  Chip(
                    label: Text(
                      '${g.name(i)}：${(v['remaining'] as List)[i]} 盏亮灯',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: side,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: b.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: n,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemBuilder: (context, i) => FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(2),
                      backgroundColor: b[i] == 1
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                    ),
                    onPressed: !g.spectator && !g.over
                        ? () => g.act({'cell': i})
                        : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          b[i] == 1 ? Icons.lightbulb : Icons.lightbulb_outline,
                        ),
                        Text(b[i] == 1 ? '亮' : '灭'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class WordBoard extends StatefulWidget {
  final GameContext g;
  const WordBoard(this.g, {super.key});
  @override
  State<WordBoard> createState() => _WordBoardState();
}

class _WordBoardState extends State<WordBoard> {
  final List<int> selected = [];
  @override
  void didUpdateWidget(WordBoard old) {
    super.didUpdateWidget(old);
    if (old.g.view['round'] != widget.g.view['round']) selected.clear();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g, v = g.view, tiles = v['tiles'] as List;
    final can = v['canAct'] == true && v['reveal'] != true && !g.over;
    return PartyBoardPage(
      title:
          '字词拼图 · 第 ${min(v['round'] as int, v['rounds'] as int)}/${v['rounds']} 题',
      subtitle: '${v['hint']}',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              selected.isEmpty
                  ? '依次点击下方字块'
                  : selected.map((i) => tiles[i]).join(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < tiles.length; i++)
              FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(64, 64)),
                onPressed: can
                    ? () => setState(() {
                        if (selected.contains(i)) {
                          selected.removeRange(
                            selected.indexOf(i),
                            selected.length,
                          );
                        } else {
                          selected.add(i);
                        }
                      })
                    : null,
                child: Text(
                  '${tiles[i]}${selected.contains(i) ? ' ${selected.indexOf(i) + 1}' : ''}',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: can ? () => setState(selected.clear) : null,
              child: const Text('清空'),
            ),
            FilledButton(
              onPressed: can && selected.length == tiles.length
                  ? () => g.act({'order': List.of(selected)})
                  : null,
              child: const Text('提交'),
            ),
            TextButton(
              onPressed: can ? () => g.act({'skip': true}) : null,
              child: const Text('跳过本题'),
            ),
          ],
        ),
        if ('${v['note'] ?? ''}'.isNotEmpty)
          Text('${v['note']}', textAlign: TextAlign.center),
        if (v['reveal'] == true || g.over) ...[
          Text('正确答案：${v['answer']}', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          nextRound(g),
        ],
        const SizedBox(height: 16),
        scoreList(g),
      ],
    );
  }
}
