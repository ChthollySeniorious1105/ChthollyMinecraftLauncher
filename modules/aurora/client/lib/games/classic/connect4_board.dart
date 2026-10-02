import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _red = Color(0xFFE53935);
const _yellow = Color(0xFFFDD835);

class _C4Painter extends CustomPainter {
  final List<int> cells;
  final int last;
  final Set<int> win;
  final int hoverCol;
  final int hoverColor;
  final Color frame;

  _C4Painter(this.cells, this.last, this.win, this.hoverCol, this.hoverColor, this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 7;
    final top = cell; // row for the hover preview
    // frame
    final rect = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, cell * 6), Radius.circular(cell * 0.2));
    canvas.drawRRect(rect.shift(const Offset(0, 4)), Paint()..color = Colors.black38..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(frame, Colors.white, 0.15)!, frame, Color.lerp(frame, Colors.black, 0.3)!],
          ).createShader(rect.outerRect));
    final r = cell * 0.38;
    if (hoverCol >= 0) {
      canvas.drawRect(
          Rect.fromLTWH(hoverCol * cell, top, cell, cell * 6), Paint()..color = Colors.white.withValues(alpha: 0.12));
      paintStone(canvas, Offset((hoverCol + 0.5) * cell, cell / 2), r, hoverColor == 1 ? _red : _yellow, opacity: 0.8);
    }
    for (var p = 0; p < 42; p++) {
      final c = Offset((p % 7 + 0.5) * cell, top + (p ~/ 7 + 0.5) * cell);
      final v = cells[p];
      if (v == 0) {
        canvas.drawCircle(c, r, Paint()..color = const Color(0xFF10233F));
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1, cell * 0.03)
              ..color = Colors.black38);
        continue;
      }
      paintStone(canvas, c, r, v == 1 ? _red : _yellow, shadow: false);
      canvas.drawCircle(
          c,
          r * 0.7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1, cell * 0.03)
            ..color = Colors.black.withValues(alpha: 0.18));
      if (win.contains(p)) {
        canvas.drawCircle(
            c,
            r * 1.02,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, cell * 0.08)
              ..color = Colors.white);
      } else if (p == last) {
        canvas.drawCircle(c, r * 0.2, Paint()..color = Colors.white70);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _C4Painter o) => true;
}

class Connect4BoardView extends StatefulWidget {
  final GameContext g;
  const Connect4BoardView(this.g, {super.key});
  @override
  State<Connect4BoardView> createState() => _Connect4BoardViewState();
}

class _Connect4BoardViewState extends State<Connect4BoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cells = (v['cells'] as List).cast<int>();
    final firstSeat = v['firstSeat'] as int;
    final turn = v['turn'] as int;
    final last = v['last'] as int;
    final winner = v['winner'] as int;
    final win = (v['winLine'] as List).cast<int>().toSet();
    final result = v['result'] as String;
    final over = v['over'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myTurn = !over && turn == me;
    final myColor = !player ? 0 : (me == firstSeat ? 1 : 2);
    String colorName(int s) => s == firstSeat ? '红' : '黄';
    bool full(int col) => cells[col] != 0;

    final status = over
        ? result
        : myTurn
            ? '轮到你（${colorName(me)}），点击一列落子'
            : '等待 ${g.name(turn)}（${colorName(turn)}）';

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: s == firstSeat ? '红 · 先手' : '黄 · 后手',
        trailing: StoneDot(s == firstSeat ? _red : _yellow));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cell = w / 7;
      int colAt(Offset o) {
        final col = (o.dx / cell).floor();
        return col < 0 || col >= 7 ? -1 : col;
      }

      return MouseRegion(
        onHover: (e) {
          final col = myTurn ? colAt(e.localPosition) : -1;
          if (col != hover) setState(() => hover = col);
        },
        onExit: (_) => setState(() => hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final col = colAt(d.localPosition);
            if (col >= 0 && myTurn && !full(col)) g.act({'type': 'drop', 'col': col});
          },
          child: CustomPaint(
            size: Size(w, cell * 7),
            painter: _C4Painter(cells, last, win, myTurn && hover >= 0 && !full(hover) ? hover : -1, myColor,
                const Color(0xFF1E5BB8)),
          ),
        ),
      );
    });

    String? banner;
    if (over) {
      banner = winner == 2 ? '和棋' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜');
    }
    final bottom = player ? me : firstSeat;
    final filled = cells.where((x) => x != 0).length;
    return ClassicShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      aspect: 1,
      board: boardWidget,
      actions: [?resignButton(context, g)],
      info: InfoPanel(['已落 $filled / 42 子 · 横竖斜连成四子获胜']),
      result: banner,
    );
  }
}
