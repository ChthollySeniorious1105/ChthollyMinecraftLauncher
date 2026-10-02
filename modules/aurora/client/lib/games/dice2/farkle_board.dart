import 'package:aurora_shared/games/dice2/farkle.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'd2_common.dart';

class FarkleBoard extends StatefulWidget {
  final GameContext g;
  const FarkleBoard(this.g, {super.key});
  @override
  State<FarkleBoard> createState() => _FarkleBoardState();
}

class _FarkleBoardState extends State<FarkleBoard> {
  Set<int> sel = {};
  int lastRoll = -1;

  static const _help = [
    ('1', '100'),
    ('5', '50'),
    ('三条', '点数×100（1 为 1000）'),
    ('四/五/六条', '三条 ×2 / ×4 / ×8'),
    ('顺子 1-6', '1500'),
    ('三对', '750'),
  ];

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = d2Str(v['phase'], 'play');
    final turn = d2Int(v['turn']);
    final target = d2Int(v['target'], 10000);
    final scores = d2List<int>(v['scores']);
    final tp = d2Int(v['turnPoints']);
    final roll = d2List<int>(v['roll']);
    final aside = d2List<int>(v['setAside']);
    final farkled = d2List<int>(v['lastFarkle']);
    final rollCount = d2Int(v['rollCount']);
    final finalRound = v['finalRound'] == true;
    final winners = d2List<int>(v['winners']);
    final over = phase == 'over';
    final myTurn = !over && turn == g.seat;
    final n = scores.length;
    if (rollCount != lastRoll) {
      lastRoll = rollCount;
      sel = {};
    }
    sel.removeWhere((i) => i >= roll.length);
    final selDice = [for (final i in sel) roll[i]];
    final selPts = farkleScore(selDice);
    final best = roll.isEmpty ? 0 : farkleBest(roll).$1;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn) {
      status = roll.isEmpty
          ? (tp == 0 ? '轮到你：掷 6 颗骰子' : '请掷骰')
          : '选出计分骰（本次最多 $best 分），然后继续掷或存分';
    } else {
      status = '等待 ${g.name(turn)}（本回合 $tp 分）';
    }
    if (finalRound && !over) status = '最后一轮！$status';

    Widget diceZone(double size) {
      final showFarkle = roll.isEmpty && farkled.isNotEmpty;
      final shown = showFarkle ? farkled : roll;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (aside.isNotEmpty) ...[
          const Text('已留下', style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 2),
          Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (final d in aside) DieFace(d, size: size * 0.55),
          ]),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: size * 1.45,
          child: Center(
            child: shown.isEmpty
                ? Wrap(spacing: size * 0.16, alignment: WrapAlignment.center, children: [
                    for (var i = 0; i < (aside.length >= 6 || aside.isEmpty ? 6 : 6 - aside.length); i++)
                      RollingDie(i + 1, size: size, dim: true),
                  ])
                : Wrap(spacing: size * 0.16, alignment: WrapAlignment.center, children: [
                    for (var i = 0; i < shown.length; i++)
                      RollingDie(shown[i],
                          size: size,
                          rollKey: rollCount,
                          dim: showFarkle,
                          ring: showFarkle ? Colors.redAccent : null,
                          held: myTurn && !showFarkle && sel.contains(i),
                          onTap: myTurn && !showFarkle
                              ? () => setState(() {
                                    if (!sel.remove(i)) sel.add(i);
                                  })
                              : null),
                  ]),
          ),
        ),
        if (showFarkle)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('FARKLE！', style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.w900)),
          ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(18)),
          child: Text(
            myTurn && sel.isNotEmpty ? '本回合 $tp  + 选中 ${selPts > 0 ? selPts : '无效'}' : '本回合 $tp 分',
            style: TextStyle(
                color: myTurn && sel.isNotEmpty && selPts == 0 ? Colors.orangeAccent : Colors.amberAccent,
                fontSize: 17,
                fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 8),
        if (myTurn)
          Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
            if (roll.isEmpty)
              FilledButton.icon(
                onPressed: () => g.act({'type': 'roll'}),
                icon: const Icon(Icons.casino),
                label: const Text('掷骰'),
              )
            else ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => setState(() => sel = farkleBest(roll).$2.toSet()),
                child: const Text('自动选择'),
              ),
              FilledButton.icon(
                onPressed: selPts > 0 ? () => g.act({'type': 'keep', 'dice': sel.toList(), 'then': 'roll'}) : null,
                icon: const Icon(Icons.casino),
                label: Text(sel.length == roll.length && selPts > 0 ? '满堂骰！继续掷' : '留下并继续掷'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                onPressed: selPts > 0 ? () => g.act({'type': 'keep', 'dice': sel.toList(), 'then': 'bank'}) : null,
                icon: const Icon(Icons.savings),
                label: Text('存分 ${selPts > 0 ? tp + selPts : ''}'),
              ),
            ],
          ]),
        const SizedBox(height: 4),
        Text(d2Str(v['lastEvent']),
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);
    }

    Widget scoreList() => D2Panel(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('目标 $target 分${finalRound ? ' · 最后一轮' : ''}',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
            for (var s = 0; s < n; s++)
              d2ScoreRow(g, s,
                  size: 28,
                  active: s == turn && !over,
                  sub: '${scores[s]} 分${s == turn && tp > 0 && !over ? '  (+$tp)' : ''}',
                  extra: D2Progress(scores[s], target, pending: s == turn && !over ? tp : 0)),
          ]),
        );

    Widget helpTable() => D2Panel(
          child: Wrap(spacing: 10, runSpacing: 2, children: [
            for (final (a, b) in _help)
              Text.rich(TextSpan(children: [
                TextSpan(text: '$a ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                TextSpan(text: b, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.75))),
              ])),
          ]),
        );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
      final size = ((wide ? c.maxWidth * 0.55 : c.maxWidth) / 8.4).clamp(34.0, 64.0);
      final felt = D2Felt(color: g.table, child: diceZone(size));
      final top = Column(mainAxisSize: MainAxisSize.min, children: [
        StatusBar(status, highlight: myTurn),
        if (over)
          ResultBanner('${winners.map(g.name).join('、')} 获胜！',
              child: Text(winners.isEmpty ? '' : '${scores[winners.first]} 分')),
        const SizedBox(height: 8),
      ]);
      final logP = D2Panel(child: SizedBox(width: double.infinity, child: D2Log(d2List<String>(v['log']), max: wide ? 6 : 3)));
      if (wide) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            top,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 11, child: Column(children: [felt, const SizedBox(height: 8), helpTable()])),
              const SizedBox(width: 8),
              Expanded(flex: 8, child: Column(children: [scoreList(), const SizedBox(height: 8), logP])),
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
          scoreList(),
          const SizedBox(height: 8),
          helpTable(),
          const SizedBox(height: 8),
          logP,
        ]),
      );
    });
  }
}
