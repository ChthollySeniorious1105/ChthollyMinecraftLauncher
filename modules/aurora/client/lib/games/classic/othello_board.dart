import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

class _OthelloPainter extends CustomPainter {
  final List<int> board;
  final Set<int> legal;
  final bool showLegal;
  final int last;
  final Set<int> flips;
  final int hover;

  _OthelloPainter(this.board, this.legal, this.showLegal, this.last, this.flips, this.hover);

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * 0.03;
    final cell = (size.width - 2 * m) / 8;
    // felt
    final rect = Rect.fromLTWH(m, m, cell * 8, cell * 8);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xFF2E9E5B), Color(0xFF1B6E3C)], radius: 0.9).createShader(rect));
    final line = Paint()
      ..color = const Color(0xFF0E3F22)
      ..strokeWidth = max(1, cell * 0.03);
    for (var i = 0; i <= 8; i++) {
      canvas.drawLine(Offset(m + i * cell, m), Offset(m + i * cell, m + 8 * cell), line);
      canvas.drawLine(Offset(m, m + i * cell), Offset(m + 8 * cell, m + i * cell), line);
    }
    for (final (x, y) in const [(2, 2), (6, 2), (2, 6), (6, 6)]) {
      canvas.drawCircle(Offset(m + x * cell, m + y * cell), max(2, cell * 0.07), Paint()..color = const Color(0xFF0E3F22));
    }
    Offset ctr(int p) => Offset(m + (p % 8 + 0.5) * cell, m + (p ~/ 8 + 0.5) * cell);
    if (hover >= 0 && legal.contains(hover)) {
      canvas.drawRect(
          Rect.fromLTWH(m + (hover % 8) * cell, m + (hover ~/ 8) * cell, cell, cell), Paint()..color = Colors.white24);
    }
    if (last >= 0) {
      canvas.drawRect(
          Rect.fromLTWH(m + (last % 8) * cell, m + (last ~/ 8) * cell, cell, cell).deflate(cell * 0.03),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, cell * 0.05)
            ..color = const Color(0xFFFFD54F));
    }
    final r = cell * 0.42;
    for (var p = 0; p < 64; p++) {
      final v = board[p];
      if (v == 0) continue;
      paintStone(canvas, ctr(p), r, v == 1 ? kBlackStone : kWhiteStone);
      if (flips.contains(p)) {
        canvas.drawCircle(ctr(p), r * 0.18, Paint()..color = const Color(0xAAFFB300));
      }
    }
    if (showLegal) {
      for (final p in legal) {
        canvas.drawCircle(ctr(p), cell * 0.12, Paint()..color = const Color(0x99FFFFFF));
        canvas.drawCircle(
            ctr(p),
            cell * 0.12,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = const Color(0x55000000));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _OthelloPainter o) => true;
}

class OthelloBoardView extends StatefulWidget {
  final GameContext g;
  const OthelloBoardView(this.g, {super.key});
  @override
  State<OthelloBoardView> createState() => _OthelloBoardViewState();
}

class _OthelloBoardViewState extends State<OthelloBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final blackSeat = v['blackSeat'] as int;
    final turn = v['turn'] as int;
    final last = v['last'] as int;
    final flips = (v['flips'] as List).cast<int>().toSet();
    final legal = (v['legal'] as List).cast<int>().toSet();
    final counts = (v['counts'] as List).cast<int>();
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final note = v['note'] as String;
    final over = v['over'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myTurn = !over && turn == me;
    String colorName(int s) => s == blackSeat ? '黑' : '白';

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      status = '${note.isNotEmpty ? '$note · ' : ''}轮到你（${colorName(me)}），可落 ${legal.length} 处';
    } else {
      status = '${note.isNotEmpty ? '$note · ' : ''}等待 ${g.name(turn)}（${colorName(turn)}）';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: '${colorName(s)} · ${counts[s == blackSeat ? 0 : 1]} 子',
        trailing: StoneDot(s == blackSeat ? kBlackStone : kWhiteStone));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final m = side * 0.03;
      final cell = (side - 2 * m) / 8;
      int at(Offset o) {
        final x = ((o.dx - m) / cell).floor(), y = ((o.dy - m) / cell).floor();
        if (x < 0 || y < 0 || x >= 8 || y >= 8) return -1;
        return y * 8 + x;
      }

      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF5D3A1A),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: MouseRegion(
          onHover: (e) {
            final p = myTurn ? at(e.localPosition) : -1;
            if (p != hover) setState(() => hover = p);
          },
          onExit: (_) => setState(() => hover = -1),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final p = at(d.localPosition);
              if (p >= 0 && myTurn && legal.contains(p)) g.act({'type': 'play', 'point': p});
            },
            child: CustomPaint(
              size: Size(side, side),
              painter: _OthelloPainter(board, legal, myTurn, last, flips, myTurn ? hover : -1),
            ),
          ),
        ),
      );
    });

    String? banner;
    if (over) {
      banner = winner == 2 ? '和棋' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜');
    }
    final bottom = player ? me : blackSeat;
    return ClassicShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      actions: [?resignButton(context, g)],
      info: InfoPanel([
        '黑 ${counts[0]} : 白 ${counts[1]} · 空 ${64 - counts[0] - counts[1]}',
        '白点为可落子位置，黄框为上一手',
      ]),
      result: banner,
    );
  }
}
