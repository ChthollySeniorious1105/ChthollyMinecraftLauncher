import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'sg_shell.dart';

const _redChars = ['', '帥', '仕', '相', '傌', '俥', '炮', '兵', ''];
const _blackChars = ['', '將', '士', '象', '馬', '車', '砲', '卒', ''];
const _hidden = 8;

/// Round xiangqi piece; |piece| == 8 is drawn face-down.
class JqPiece extends StatelessWidget {
  final int piece;
  final double size;
  final bool selected;
  const JqPiece(this.piece, {super.key, required this.size, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final red = piece > 0;
    final down = piece.abs() == _hidden;
    final ink = red ? const Color(0xFFC62828) : const Color(0xFF1B1B1B);
    final face = down
        ? (red
            ? const [Color(0xFFE57373), Color(0xFFB71C1C), Color(0xFF7F1010)]
            : const [Color(0xFF78909C), Color(0xFF37474F), Color(0xFF1C262B)])
        : const [Color(0xFFFBE7C2), Color(0xFFE2BB7E), Color(0xFFB88A4A)];
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      scale: selected ? 1.08 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: const Alignment(-0.3, -0.35), radius: 0.95, colors: face, stops: const [0, 0.7, 1]),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: selected ? 0.55 : 0.4), blurRadius: selected ? 8 : 3, offset: Offset(0, selected ? 4 : 2)),
          ],
          border: Border.all(color: selected ? const Color(0xFF2E7D32) : const Color(0xFF6A4A22), width: max(1.0, size * (selected ? 0.07 : 0.03))),
        ),
        child: Container(
          margin: EdgeInsets.all(size * 0.1),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: down ? Colors.white.withValues(alpha: 0.45) : ink.withValues(alpha: 0.75), width: max(0.8, size * 0.03)),
          ),
          alignment: Alignment.center,
          child: down
              ? Icon(Icons.help_outline, size: size * 0.4, color: Colors.white.withValues(alpha: 0.7))
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    (red ? _redChars : _blackChars)[piece.abs()],
                    style: TextStyle(fontSize: size * 0.5, height: 1.0, fontWeight: FontWeight.w900, color: ink),
                  ),
                ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final bool flipped;
  _GridPainter(this.flipped);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 9;
    Offset pt(int col, int row) => Offset((col + 0.5) * cell, (row + 0.5) * cell);
    final line = Paint()
      ..color = const Color(0xFF5B3A1A)
      ..strokeWidth = max(1, cell * 0.03);
    final thick = Paint()
      ..color = const Color(0xFF5B3A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2, cell * 0.06);
    canvas.drawRect(Rect.fromPoints(pt(0, 0) - Offset(cell * 0.12, cell * 0.12), pt(8, 9) + Offset(cell * 0.12, cell * 0.12)), thick);
    for (var r = 0; r < 10; r++) {
      canvas.drawLine(pt(0, r), pt(8, r), line);
    }
    for (var c = 0; c < 9; c++) {
      if (c == 0 || c == 8) {
        canvas.drawLine(pt(c, 0), pt(c, 9), line);
      } else {
        canvas.drawLine(pt(c, 0), pt(c, 4), line);
        canvas.drawLine(pt(c, 5), pt(c, 9), line);
      }
    }
    for (final top in const [0, 7]) {
      canvas.drawLine(pt(3, top), pt(5, top + 2), line);
      canvas.drawLine(pt(5, top), pt(3, top + 2), line);
    }
    void txt(String s, Offset center) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: kFontFallback.first, fontFamilyFallback: kFontFallback, fontSize: cell * 0.5, color: const Color(0xFF6B4524), fontWeight: FontWeight.bold, letterSpacing: cell * 0.3)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }

    txt(flipped ? '漢 界' : '楚 河', Offset(2.5 * cell, 5 * cell));
    txt(flipped ? '楚 河' : '漢 界', Offset(6.5 * cell, 5 * cell));
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.flipped != flipped;
}

class JieqiBoard extends StatefulWidget {
  final GameContext g;
  const JieqiBoard(this.g, {super.key});
  @override
  State<JieqiBoard> createState() => _JieqiBoardState();
}

class _JieqiBoardState extends State<JieqiBoard> {
  int? sel;
  int _plies = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final redSeat = v['redSeat'] as int;
    final turn = v['turn'] as int;
    final moves = (v['moves'] as List).cast<int>();
    final last = (v['last'] as List).cast<int>();
    final check = v['check'] as int?;
    final notation = (v['notation'] as List).cast<String>();
    final captured = (v['captured'] as List).map((e) => (e as List).cast<int>()).toList();
    final winner = v['winner'] as int;
    final reason = v['reason'] as String;
    final plies = v['plies'] as int;
    if (plies != _plies) {
      _plies = plies;
      sel = null;
    }
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = player && me != redSeat ? -1 : 1;
    final flipped = myColor < 0;
    final myTurn = !g.over && player && turn == me;
    final bottomSeat = player ? me : redSeat;
    final topSeat = 1 - bottomSeat;
    String colorName(int s) => s == redSeat ? '红方' : '黑方';
    final hiddenLeft = [board.where((x) => x == _hidden).length, board.where((x) => x == -_hidden).length];

    String status;
    if (winner == -1) {
      status = '和棋：$reason';
    } else if (winner >= 0) {
      status = '${g.name(winner)} 获胜（$reason）';
    } else if (myTurn) {
      status = check != null ? '你被将军了！请应将' : '轮到你走棋（${colorName(me)}）';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）${check != null ? ' · 将军' : ''}';
    }
    final offer = v['drawOffer'] as int? ?? -1;
    if (!g.over && offer >= 0 && offer != me) status = '${g.name(offer)} 提议和棋';

    Widget tagFor(int s) {
      final c = s == redSeat ? 1 : -1;
      final list = List<int>.of(captured[c == 1 ? 0 : 1])..sort();
      return g.tag(s,
          active: !g.over && turn == s,
          sub: '${colorName(s)} · 暗子 ${hiddenLeft[c == 1 ? 0 : 1]}',
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Wrap(spacing: 1, runSpacing: 1, children: [for (final t in list) JqPiece(-c * t, size: 16)]),
          ));
    }

    final targets = <int>{
      if (sel != null)
        for (final m in moves)
          if (m ~/ 90 == sel) m % 90
    };
    final movable = <int>{for (final m in moves) m ~/ 90};

    void tap(int s) {
      if (!myTurn) return;
      final p = board[s];
      final mine = p != 0 && (p > 0) == (myColor > 0);
      if (sel != null && targets.contains(s)) {
        final from = sel!;
        setState(() => sel = null);
        g.act({'type': 'move', 'from': from, 'to': s});
        return;
      }
      setState(() => sel = mine && sel != s && movable.contains(s) ? s : null);
    }

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final cell = c.maxWidth / 9;
      Offset posOf(int s) {
        final r = s ~/ 9, col = s % 9;
        final vr = flipped ? r : 9 - r;
        final vc = flipped ? 8 - col : col;
        return Offset(vc * cell, vr * cell);
      }

      final pieceSize = cell * 0.9;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF1D29A), Color(0xFFE0B46C), Color(0xFFEBC685)],
          ),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter(flipped))),
          for (final s in last)
            Positioned(
              left: posOf(s).dx + cell * 0.04,
              top: posOf(s).dy + cell * 0.04,
              width: cell * 0.92,
              height: cell * 0.92,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: board[s] == 0 ? Colors.blue.withValues(alpha: 0.18) : null,
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.8), width: 2),
                  ),
                ),
              ),
            ),
          for (var s = 0; s < 90; s++)
            Positioned(
              left: posOf(s).dx,
              top: posOf(s).dy,
              width: cell,
              height: cell,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => tap(s),
                child: Center(
                  child: board[s] != 0
                      ? Stack(alignment: Alignment.center, children: [
                          if (check == s)
                            Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.9), blurRadius: cell * 0.3, spreadRadius: cell * 0.05)],
                              ),
                            ),
                          JqPiece(board[s], size: pieceSize, selected: sel == s),
                          if (targets.contains(s))
                            Container(
                              width: pieceSize,
                              height: pieceSize,
                              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.green.shade700, width: cell * 0.07)),
                            ),
                        ])
                      : (targets.contains(s)
                          ? Container(
                              width: cell * 0.28,
                              height: cell * 0.28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green.shade700.withValues(alpha: 0.75),
                                border: Border.all(color: Colors.white70, width: 1.5),
                              ),
                            )
                          : const SizedBox()),
                ),
              ),
            ),
        ]),
      );
    });

    return SgShell(
      topTag: tagFor(topSeat),
      bottomTag: tagFor(bottomSeat),
      status: status,
      statusHighlight: myTurn || (offer >= 0 && offer != me && !g.over),
      aspect: 9 / 10,
      board: boardWidget,
      actions: sgResignDraw(context, g),
      extra: SgMoveList(notation),
      result: g.over ? (winner == -1 ? '和棋 · $reason' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜')) : null,
    );
  }
}
