import 'package:flutter/material.dart';

import '../../widgets/common.dart';

class TicTacToeBoard extends StatelessWidget {
  final GameContext g;
  const TicTacToeBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cells = (v['cells'] as List).cast<int>();
    final turn = v['turn'] as int;
    final winner = v['winner'] as int;
    final line = (v['line'] as List).cast<int>();
    final cs = Theme.of(context).colorScheme;
    final myTurn = !g.over && turn == g.seat;
    String status;
    if (winner == 2) {
      status = '平局';
    } else if (winner >= 0) {
      status = '${g.name(winner)} 获胜！';
    } else {
      status = myTurn ? '轮到你了' : '等待 ${g.name(turn)}';
    }
    Widget mark(int s, double size) => s < 0
        ? const SizedBox()
        : Icon(s == 0 ? Icons.close : Icons.circle_outlined,
            size: size, color: s == 0 ? Colors.redAccent : Colors.lightBlueAccent);
    return Column(children: [
      const SizedBox(height: 8),
      Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
        for (var s = 0; s < 2; s++) g.tag(s, active: !g.over && turn == s, trailing: mark(s, 20)),
      ]),
      const SizedBox(height: 8),
      StatusBar(status, highlight: myTurn),
      const SizedBox(height: 8),
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(builder: (context, c) {
              final cell = c.maxWidth / 3;
              return GridView.count(
                crossAxisCount: 3,
                padding: EdgeInsets.all(cell * 0.05),
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (var i = 0; i < 9; i++)
                    Material(
                      color: line.contains(i) ? cs.primary.withValues(alpha: 0.4) : cs.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: myTurn && cells[i] < 0 ? () => g.act({'cell': i}) : null,
                        child: Center(child: mark(cells[i], cell * 0.6)),
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    ]);
  }
}
