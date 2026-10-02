import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'd2_common.dart';

class PigBoard extends StatelessWidget {
  final GameContext g;
  const PigBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = d2Str(v['phase'], 'play');
    final turn = d2Int(v['turn']);
    final target = d2Int(v['target'], 100);
    final two = v['two'] == true;
    final scores = d2List<int>(v['scores']);
    final tp = d2Int(v['turnPoints']);
    final turnRolls = d2Int(v['turnRolls']);
    final last = d2List<int>(v['lastRoll']);
    final rollCount = d2Int(v['rollCount']);
    final winner = d2Int(v['winner'], -1);
    final over = phase == 'over';
    final myTurn = !over && turn == g.seat;
    final n = scores.length;

    final status = over
        ? '游戏结束'
        : myTurn
            ? (turnRolls == 0 ? '轮到你：掷骰！' : '本回合 $tp 分 —— 继续掷还是存分？')
            : '等待 ${g.name(turn)}（本回合 $tp 分）';

    Widget diceZone(double size) {
      final busted = last.contains(1);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: size * 1.5,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (last.isEmpty)
              for (var i = 0; i < (two ? 2 : 1); i++)
                Padding(padding: const EdgeInsets.all(6), child: RollingDie(1, size: size, dim: true))
            else
              for (var i = 0; i < last.length; i++)
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: RollingDie(last[i],
                      size: size, rollKey: rollCount, ring: last[i] == 1 ? Colors.redAccent : null),
                ),
          ]),
        ),
        const SizedBox(height: 4),
        Text(d2Str(v['lastEvent'], '准备开始'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: busted && turnRolls == 0 ? Colors.orangeAccent : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
          child: Text('本回合 $tp 分', style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 10),
        if (myTurn)
          Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              onPressed: () => g.act({'type': 'roll'}),
              icon: const Icon(Icons.casino),
              label: Text(two ? '掷两颗' : '掷骰'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
              onPressed: turnRolls > 0 ? () => g.act({'type': 'hold'}) : null,
              icon: const Icon(Icons.savings),
              label: Text('存分 +$tp'),
            ),
          ]),
        const SizedBox(height: 6),
        Text(two ? '规则：掷出一个 1 本回合清零；双 1（蛇眼）总分清零' : '规则：掷出 1 本回合分数作废',
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]);
    }

    Widget scoreList() => D2Panel(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('目标 $target 分', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
            for (var s = 0; s < n; s++)
              d2ScoreRow(g, s,
                  active: s == turn && !over,
                  sub: '${scores[s]} 分${s == turn && tp > 0 && !over ? '  (+$tp)' : ''}',
                  extra: D2Progress(scores[s], target, pending: s == turn && !over ? tp : 0)),
          ]),
        );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
      final size = (c.maxWidth / (wide ? 12 : 6)).clamp(44.0, 84.0);
      final felt = D2Felt(
        color: g.table,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.savings_outlined, color: Colors.pinkAccent, size: 20),
            const SizedBox(width: 6),
            Text(two ? '双骰猪' : '猪骰', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          diceZone(size),
        ]),
      );
      final top = Column(mainAxisSize: MainAxisSize.min, children: [
        StatusBar(status, highlight: myTurn),
        if (over) ResultBanner(winner >= 0 ? '${g.name(winner)} 获胜！' : '游戏结束', child: Text('${winner >= 0 ? scores[winner] : 0} 分')),
        const SizedBox(height: 8),
      ]);
      final logP = D2Panel(child: SizedBox(width: double.infinity, child: D2Log(d2List<String>(v['log']), max: wide ? 8 : 4)));
      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            top,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 6, child: felt),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: Column(children: [scoreList(), const SizedBox(height: 8), logP])),
            ]),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [top, felt, const SizedBox(height: 8), scoreList(), const SizedBox(height: 8), logP]),
      );
    });
  }
}
