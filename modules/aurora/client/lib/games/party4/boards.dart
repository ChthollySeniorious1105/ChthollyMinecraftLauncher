import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';

final Map<String, BoardBuilder> party4Boards = {
  'quizparty': (g) => QuizBoard(g),
  'memorypairs': (g) => MemoryBoard(g),
  'escapehouse': (g) => EscapeBoard(g),
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

class QuizBoard extends StatelessWidget {
  final GameContext g;
  const QuizBoard(this.g, {super.key});
  @override
  Widget build(BuildContext context) {
    final v = g.view, choices = v['choices'] as List;
    final reveal = v['reveal'] == true || g.over;
    return PartyBoardPage(
      title:
          '知识派对 · 第 ${min(v['round'] as int, v['rounds'] as int)}/${v['rounds']} 题',
      subtitle: g.over
          ? '本场结束，按正确率计分'
          : reveal
          ? '${v['explanation']}'
          : '45 秒内选择答案，提交后统一揭晓。已提交 ${(v['submitted'] as List).length}/${g.players}',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '${v['question']}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        for (var i = 0; i < choices.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 54),
                alignment: Alignment.centerLeft,
              ),
              onPressed: v['canAct'] == true && !reveal
                  ? () => g.act({'answer': i})
                  : null,
              icon: Icon(
                reveal && v['answer'] == i
                    ? Icons.check_circle
                    : v['mine'] == i
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              label: Text(
                '${String.fromCharCode(65 + i)}. ${choices[i]}${reveal && v['answer'] == i ? ' ✓ 正确答案' : ''}',
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (reveal) ...[scoreList(g), const SizedBox(height: 12), nextRound(g)],
      ],
    );
  }
}

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

class EscapeBoard extends StatelessWidget {
  final GameContext g;
  const EscapeBoard(this.g, {super.key});
  @override
  Widget build(BuildContext context) {
    final v = g.view,
        clues = v['clues'] as List,
        inspected = v['inspected'] as List;
    final cs = Theme.of(context).colorScheme;
    return PartyBoardPage(
      title: '极光密室 · ${v['title']}',
      subtitle: g.over
          ? (v['won'] == true ? '全员成功逃出密室！' : '错误达到上限，挑战失败。')
          : '第 ${v['stage']}/${v['rooms']} 间 · 全员共享线索 · 错误 ${v['mistakes']}/6',
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primaryContainer, cs.tertiaryContainer],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(Icons.nightlight_round, size: 64, color: cs.primary),
              const SizedBox(height: 8),
              const Text('一道锁住的门。墙上的星图、桌上的笔记与角落的锁盒，似乎藏着出口。'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 3; i++)
                    FilledButton.tonalIcon(
                      onPressed:
                          !g.spectator && !g.over && !inspected.contains(i)
                          ? () => g.act({'type': 'inspect', 'item': i})
                          : null,
                      icon: Icon([Icons.stars, Icons.menu_book, Icons.lock][i]),
                      label: Text(['调查壁画', '打开笔记', '检查锁盒'][i]),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < clues.length; i++)
          Card(
            child: ListTile(
              leading: Icon(
                inspected.contains(i) ? Icons.check_circle : Icons.help_outline,
              ),
              title: Text('${clues[i]}'),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (var i = 0; i < (v['choices'] as List).length; i++)
              FilledButton(
                onPressed: !g.spectator && !g.over
                    ? () => g.act({'type': 'solve', 'choice': i})
                    : null,
                child: Text('密码 ${(v['choices'] as List)[i]}'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '共享背包：${(v['inventory'] as List).isEmpty ? '暂无线索钥匙' : (v['inventory'] as List).join('、')}',
        ),
      ],
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
