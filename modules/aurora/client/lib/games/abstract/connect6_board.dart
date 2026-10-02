import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

class _C6Painter extends CustomPainter {
  final int n;
  final List<int> board;
  final Set<int> lastTurn, thisTurn, winLine;
  final int hover, hoverColor;

  _C6Painter(this.n, this.board, this.lastTurn, this.thisTurn, this.winLine, this.hover, this.hoverColor);

  static const _ink = Color(0xFF3B2A14);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / (n + 1);
    Offset pt(int p) => Offset((p % n + 1) * cell, (p ~/ n + 1) * cell);
    final line = Paint()
      ..color = _ink
      ..strokeWidth = max(0.6, cell * 0.035);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(cell, (i + 1) * cell), Offset(n * cell, (i + 1) * cell), line);
      canvas.drawLine(Offset((i + 1) * cell, cell), Offset((i + 1) * cell, n * cell), line);
    }
    canvas.drawRect(
        Rect.fromLTRB(cell, cell, n * cell, n * cell),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.2, cell * 0.07));
    for (final x in [3, 9, 15]) {
      for (final y in [3, 9, 15]) {
        canvas.drawCircle(pt(y * n + x), max(1.8, cell * 0.11), Paint()..color = _ink);
      }
    }
    final r = cell * 0.46;
    for (var p = 0; p < n * n; p++) {
      final c = board[p];
      if (c == 0) continue;
      absStone(canvas, pt(p), r, c == 1 ? kAbsBlack : kAbsWhite, shadow: cell > 10);
    }
    if (hover >= 0 && hover < board.length && board[hover] == 0 && hoverColor > 0) {
      absStone(canvas, pt(hover), r, hoverColor == 1 ? kAbsBlack : kAbsWhite, opacity: 0.45, shadow: false);
    }
    if (winLine.isEmpty) {
      for (final p in lastTurn) {
        if (board[p] == 0) continue;
        canvas.drawCircle(pt(p), r * 0.3, Paint()..color = const Color(0xFFE53935));
      }
      for (final p in thisTurn) {
        if (board[p] == 0) continue;
        canvas.drawCircle(
            pt(p),
            r * 0.35,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1.2, r * 0.18)
              ..color = const Color(0xFF42A5F5));
      }
    } else {
      final pts = winLine.toList()..sort();
      canvas.drawLine(
          pt(pts.first),
          pt(pts.last),
          Paint()
            ..color = const Color(0xCCE53935)
            ..strokeWidth = max(2, cell * 0.14)
            ..strokeCap = StrokeCap.round);
      for (final p in pts) {
        canvas.drawCircle(pt(p), r * 0.25, Paint()..color = const Color(0xFFFFD54F));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _C6Painter o) => true;
}

class Connect6BoardView extends StatefulWidget {
  final GameContext g;
  const Connect6BoardView(this.g, {super.key});
  @override
  State<Connect6BoardView> createState() => _Connect6BoardViewState();
}

class _Connect6BoardViewState extends State<Connect6BoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final board = (v['board'] as List).cast<int>();
    final blackSeat = v['blackSeat'] as int;
    final turn = v['turn'] as int;
    final stonesLeft = v['stonesLeft'] as int;
    final over = v['over'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = !player ? 0 : (me == blackSeat ? 1 : 2);
    final myTurn = !over && turn == me;
    String colorName(int s) => s == blackSeat ? '黑' : '白';
    final first = v['moves'] == 0;

    String status;
    if (over) {
      status = v['result'] as String? ?? '对局结束';
    } else if (myTurn) {
      status = first ? '轮到你：首手只下 1 子' : '轮到你：本回合还需下 $stonesLeft 子';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）落子，还剩 $stonesLeft 子';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: s == blackSeat ? '执黑先行' : '执白',
        trailing: AbsDot(s == blackSeat ? kAbsBlack : kAbsWhite));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / (n + 1);
      int pointAt(Offset o) {
        final x = (o.dx / cell - 1).round(), y = (o.dy / cell - 1).round();
        if (x < 0 || y < 0 || x >= n || y >= n) return -1;
        return y * n + x;
      }

      return Container(
        decoration: absWood(radius: 6),
        child: MouseRegion(
          onHover: (e) {
            final p = myTurn ? pointAt(e.localPosition) : -1;
            if (p != hover) setState(() => hover = p);
          },
          onExit: (_) => setState(() => hover = -1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = pointAt(d.localPosition);
              if (p < 0 || !myTurn || board[p] != 0) return;
              g.act({'type': 'play', 'point': p});
            },
            child: CustomPaint(
              size: Size(side, side),
              painter: _C6Painter(
                n,
                board,
                (v['lastTurn'] as List).cast<int>().toSet(),
                (v['thisTurn'] as List).cast<int>().toSet(),
                (v['winLine'] as List).cast<int>().toSet(),
                myTurn ? hover : -1,
                myColor,
              ),
            ),
          ),
        ),
      );
    });

    final bottom = player ? me : blackSeat;
    return AbsShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      actions: [?absResign(context, g)],
      info: [
        '19 路 · 黑方首手 1 子，此后每回合 2 子 · 连成六子获胜 · 第 ${v['moves']} 子',
        '红点：对手上一回合 · 蓝圈：本回合已下',
      ],
      result: absBanner(g, v),
    );
  }
}
