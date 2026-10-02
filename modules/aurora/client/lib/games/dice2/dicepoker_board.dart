import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'd2_common.dart';

class DicePokerBoard extends StatefulWidget {
  final GameContext g;
  const DicePokerBoard(this.g, {super.key});
  @override
  State<DicePokerBoard> createState() => _DicePokerBoardState();
}

class _DicePokerBoardState extends State<DicePokerBoard> {
  List<bool> hold = List.filled(5, false);
  String key = '';

  static const _rankTable = ['五条', '四条', '葫芦', '大顺 2-6', '小顺 1-5', '三条', '两对', '一对', '散牌'];

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = d2Str(v['phase'], 'play');
    final turn = d2Int(v['turn']);
    final dice = d2List<int>(v['dice']);
    final rollsUsed = d2Int(v['rollsUsed']);
    final round = d2Int(v['round']);
    final rounds = d2Int(v['rounds'], 5);
    final points = d2List<int>(v['points']);
    final finals = d2List<dynamic>(v['finals']);
    final finalRanks = d2List<dynamic>(v['finalRanks']);
    final roundWinners = d2List<int>(v['roundWinners']);
    final winners = d2List<int>(v['winners']);
    final over = phase == 'over';
    final myTurn = phase == 'play' && turn == g.seat;
    final n = points.length;
    final k = '$turn/$rollsUsed/$round';
    if (k != key) {
      key = k;
      hold = List.filled(5, false);
    }
    final rolled = rollsUsed > 0;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (phase == 'result') {
      status = '第 $round 局：${roundWinners.map(g.name).join('、')} 获胜';
    } else if (myTurn) {
      status = !rolled ? '轮到你：掷骰！' : '点骰子保留，再掷（剩 ${3 - rollsUsed} 次）或停手';
    } else {
      status = '等待 ${g.name(turn)} 掷骰（第 $rollsUsed/3 次）';
    }

    Widget diceZone(double size) => Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: size * 0.18, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < 5; i++)
              RollingDie(rolled && dice.length > i ? dice[i] : i + 1,
                  size: size,
                  dim: !rolled,
                  rollKey: '$turn/$rollsUsed/$round',
                  held: myTurn && rolled && hold[i],
                  onTap: myTurn && rolled ? () => setState(() => hold[i] = !hold[i]) : null),
          ]),
          const SizedBox(height: 8),
          if (rolled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(16)),
              child: Text('${g.name(turn)}：${d2Str(v['current'])}',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          const SizedBox(height: 8),
          if (myTurn)
            Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton.icon(
                onPressed: !(rolled && hold.every((h) => h)) ? () => g.act({'type': 'roll', 'hold': hold}) : null,
                icon: const Icon(Icons.casino),
                label: Text(rolled ? '再掷（剩 ${3 - rollsUsed}）' : '掷骰子'),
              ),
              if (rolled)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  onPressed: () => g.act({'type': 'stand'}),
                  icon: const Icon(Icons.check),
                  label: const Text('停手'),
                ),
            ]),
        ]);

    Widget results() => D2Panel(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('第 $round / $rounds 局 · 得分', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 4),
            for (var s = 0; s < n; s++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Flexible(
                    flex: 3,
                    child: g.tag(s,
                        active: s == turn && phase == 'play',
                        size: 28,
                        sub: '${points.elementAtOrNull(s) ?? 0} 分${roundWinners.contains(s) ? ' ★' : ''}'),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: finals.elementAtOrNull(s) is List
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            for (final d in d2List<int>(finals[s]))
                              Padding(padding: const EdgeInsets.only(right: 2), child: DieFace(d, size: 18)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(d2Str(finalRanks.elementAtOrNull(s)),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: roundWinners.contains(s) ? cs.primary : null)),
                            ),
                          ])
                        : Text(s == turn && phase == 'play' ? '掷骰中…' : '—',
                            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
                  ),
                ]),
              ),
          ]),
        );

    Widget rankHelp() => D2Panel(
          child: Wrap(spacing: 6, runSpacing: 2, children: [
            for (var i = 0; i < _rankTable.length; i++)
              Text('${_rankTable[i]}${i < _rankTable.length - 1 ? ' >' : ''}',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.75))),
          ]),
        );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
      final size = ((wide ? c.maxWidth * 0.55 : c.maxWidth) / 7.2).clamp(38.0, 72.0);
      final felt = D2Felt(color: g.table, child: diceZone(size));
      final top = Column(mainAxisSize: MainAxisSize.min, children: [
        StatusBar(status, highlight: myTurn),
        if (over)
          ResultBanner('${winners.map(g.name).join('、')} 获胜！',
              child: Text(winners.isEmpty ? '' : '赢得 ${points[winners.first]} 局')),
        const SizedBox(height: 8),
      ]);
      final logP = D2Panel(child: SizedBox(width: double.infinity, child: D2Log(d2List<String>(v['log']), max: wide ? 6 : 3)));
      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            top,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 11, child: Column(children: [felt, const SizedBox(height: 8), rankHelp()])),
              const SizedBox(width: 8),
              Expanded(flex: 9, child: Column(children: [results(), const SizedBox(height: 8), logP])),
            ]),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          top,
          felt,
          const SizedBox(height: 8),
          results(),
          const SizedBox(height: 8),
          rankHelp(),
          const SizedBox(height: 8),
          logP,
        ]),
      );
    });
  }
}
