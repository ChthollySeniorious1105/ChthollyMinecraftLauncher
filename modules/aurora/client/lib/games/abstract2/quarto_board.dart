import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _dark = Color(0xFF7A4A26);
const _light = Color(0xFFF1D9A8);

/// Paints a Quarto piece seen from above at a slight angle.
/// bit0 tall, bit1 dark, bit2 square, bit3 hollow.
void paintQuartoPiece(Canvas canvas, Offset c, double cell, int p, {double opacity = 1, bool glow = false}) {
  final tall = p & 1 != 0, dark = p & 2 != 0, square = p & 4 != 0, hollow = p & 8 != 0;
  final r = cell * (tall ? 0.36 : 0.27);
  final h = cell * (tall ? 0.14 : 0.06);
  final base = dark ? _dark : _light;
  final side = Color.lerp(base, Colors.black, 0.35)!;
  final top = c - Offset(0, h / 2);
  final bottom = c + Offset(0, h / 2);
  Path shape(Offset o, double rr) => square
      ? (Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: rr * 2, height: rr * 2), Radius.circular(rr * 0.22))))
      : (Path()..addOval(Rect.fromCircle(center: o, radius: rr)));
  canvas.drawPath(shape(bottom + Offset(r * 0.12, r * 0.18), r), a2Shadow(r * 0.2, alpha: 0.4 * opacity));
  if (glow) {
    canvas.drawPath(
        shape(top, r * 1.18),
        Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.75 * opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25));
  }
  // side extrusion
  final steps = max(1, (h / 1.5).round());
  for (var i = steps; i >= 0; i--) {
    canvas.drawPath(shape(top + Offset(0, h * i / steps), r), Paint()..color = side.withValues(alpha: opacity));
  }
  final rect = Rect.fromCircle(center: top, radius: r);
  canvas.drawPath(
      shape(top, r),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: [
            Color.lerp(base, Colors.white, dark ? 0.3 : 0.55)!.withValues(alpha: opacity),
            base.withValues(alpha: opacity),
            Color.lerp(base, Colors.black, 0.18)!.withValues(alpha: opacity),
          ],
          stops: const [0, 0.6, 1],
        ).createShader(rect));
  canvas.drawPath(
      shape(top, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, r * 0.05)
        ..color = Colors.black.withValues(alpha: 0.35 * opacity));
  if (hollow) {
    final hr = r * 0.42;
    canvas.drawCircle(top, hr, Paint()..color = Color.lerp(base, Colors.black, 0.55)!.withValues(alpha: opacity));
    canvas.drawCircle(
        top + Offset(0, hr * 0.12),
        hr * 0.8,
        Paint()..color = Color.lerp(base, Colors.black, 0.7)!.withValues(alpha: opacity));
  }
}

class _QuartoPainter extends CustomPainter {
  final List<int> board;
  final int last, hover, hand;
  final Set<int> winLine;
  final bool placing;
  final Color accent;
  _QuartoPainter(this.board, this.last, this.hover, this.hand, this.winLine, this.placing, this.accent);

  static Offset cellCenter(Size size, int i) {
    final m = size.width * 0.1;
    final cell = (size.width - 2 * m) / 4;
    return Offset(m + (i % 4 + 0.5) * cell, m + (i ~/ 4 + 0.5) * cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final m = w * 0.1;
    final cell = (w - 2 * m) / 4;
    // round wooden board (Quarto's board is a rounded square with circular slots)
    final bRect = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.02, w * 0.02, w * 0.96, w * 0.96), Radius.circular(w * 0.2));
    canvas.drawRRect(bRect.shift(Offset(0, w * 0.012)), a2Shadow(w * 0.02, alpha: 0.5));
    canvas.drawRRect(
        bRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5B3B22), Color(0xFF3E2716), Color(0xFF5A3A20)],
          ).createShader(bRect.outerRect));
    canvas.drawRRect(
        bRect.deflate(w * 0.015),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.006
          ..color = const Color(0x55FFE0B2));
    for (var i = 0; i < 16; i++) {
      final c = cellCenter(size, i);
      final slot = Rect.fromCircle(center: c, radius: cell * 0.42);
      canvas.drawCircle(
          c,
          cell * 0.42,
          Paint()
            ..shader = const RadialGradient(
              center: Alignment(0.2, 0.3),
              colors: [Color(0xFF2E1B0E), Color(0xFF4A2F1B)],
            ).createShader(slot));
      if (winLine.contains(i)) {
        canvas.drawCircle(
            c,
            cell * 0.46,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, cell * 0.06)
              ..color = const Color(0xFFFFD54F));
      } else if (i == last) {
        canvas.drawCircle(
            c,
            cell * 0.45,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1.5, cell * 0.035)
              ..color = accent.withValues(alpha: 0.9));
      }
      if (placing && board[i] < 0) {
        canvas.drawCircle(c, cell * 0.08, Paint()..color = const Color(0x8866BB6A));
      }
    }
    for (var i = 0; i < 16; i++) {
      if (board[i] >= 0) paintQuartoPiece(canvas, cellCenter(size, i), cell, board[i], glow: winLine.contains(i));
    }
    if (placing && hover >= 0 && hover < 16 && board[hover] < 0 && hand >= 0) {
      canvas.drawCircle(cellCenter(size, hover), cell * 0.44, Paint()..color = const Color(0x3366BB6A));
      paintQuartoPiece(canvas, cellCenter(size, hover), cell, hand, opacity: 0.55);
    }
    // coordinates
    for (var i = 0; i < 4; i++) {
      final col = String.fromCharCode(65 + i);
      a2PaintTextCentered(canvas, col, Offset(m + (i + 0.5) * cell, m * 0.5), m * 0.32, const Color(0x99FFE0B2));
      a2PaintTextCentered(canvas, '${i + 1}', Offset(m * 0.5, m + (i + 0.5) * cell), m * 0.32, const Color(0x99FFE0B2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class _PiecePainter extends CustomPainter {
  final int p;
  final bool glow;
  _PiecePainter(this.p, {this.glow = false});
  @override
  void paint(Canvas canvas, Size size) =>
      paintQuartoPiece(canvas, Offset(size.width / 2, size.height / 2 + size.height * 0.04), size.width, p, glow: glow);
  @override
  bool shouldRepaint(covariant _PiecePainter o) => o.p != p || o.glow != glow;
}

String quartoPieceName(int p) =>
    '${p & 1 != 0 ? '高' : '矮'}·${p & 2 != 0 ? '深' : '浅'}·${p & 4 != 0 ? '方' : '圆'}·${p & 8 != 0 ? '空心' : '实心'}';

class QuartoBoardView extends StatefulWidget {
  final GameContext g;
  const QuartoBoardView(this.g, {super.key});
  @override
  State<QuartoBoardView> createState() => _QuartoBoardViewState();
}

class _QuartoBoardViewState extends State<QuartoBoardView> {
  int hover = -1;
  int hoverPool = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final avail = (v['avail'] as List).cast<int>().toSet();
    final hand = v['hand'] as int;
    final phase = v['phase'] as String;
    final turn = v['turn'] as int;
    final last = v['last'] as int;
    final winLine = (v['winLine'] as List).cast<int>().toSet();
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final lastText = v['lastText'] as String;
    final squares = v['squares'] == true;
    final over = v['over'] == true;
    final me = g.seat;
    final myTurn = !over && turn == me && !g.replay;
    final placing = myTurn && phase == 'place';
    final giving = myTurn && phase == 'give';

    String status;
    if (over) {
      status = result;
    } else if (giving) {
      status = '轮到你：为 ${g.name(1 - me)} 挑一枚棋子';
    } else if (placing) {
      status = '轮到你：把「${quartoPieceName(hand)}」放到棋盘上';
    } else {
      status = phase == 'give' ? '等待 ${g.name(turn)} 挑选棋子' : '等待 ${g.name(turn)} 放置棋子';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: over ? (winner == s ? '胜' : (winner == 2 ? '和' : '负')) : (turn == s ? (phase == 'give' ? '挑选中' : '放置中') : '等待'));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxWidth);
      int at(Offset o) {
        final m = size.width * 0.1;
        final cell = (size.width - 2 * m) / 4;
        final x = ((o.dx - m) / cell).floor(), y = ((o.dy - m) / cell).floor();
        if (x < 0 || y < 0 || x > 3 || y > 3) return -1;
        return y * 4 + x;
      }

      return MouseRegion(
        onHover: (e) {
          final p = placing ? at(e.localPosition) : -1;
          if (p != hover) setState(() => hover = p);
        },
        onExit: (_) => setState(() => hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final p = at(d.localPosition);
            if (placing && p >= 0 && board[p] < 0) {
              g.act({'type': 'place', 'cell': p});
              setState(() => hover = -1);
            }
          },
          child: CustomPaint(size: size, painter: _QuartoPainter(board, last, placing ? hover : -1, hand, winLine, placing, cs.primary)),
        ),
      );
    });

    // Tray: hand piece + pool of available pieces.
    final tray = A2Panel(
      highlight: giving,
      child: LayoutBuilder(builder: (context, c) {
        final handBox = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(phase == 'place' && !over ? '${g.name(turn)} 手中' : '待放', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          SizedBox(
            width: 44,
            height: 44,
            child: hand >= 0
                ? CustomPaint(painter: _PiecePainter(hand, glow: true))
                : Icon(Icons.help_outline, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          ),
        ]);
        final pool = LayoutBuilder(builder: (context, pc) {
          // 16 slots arranged 8×2 (wide) or 4×4 (narrow/tall)
          var cols = 4;
          var s = 0.0;
          for (final c in const [2, 4, 8, 16]) {
            final t = min(pc.maxWidth / c, pc.maxHeight / (16 / c).ceil());
            if (t > s) {
              s = t;
              cols = c;
            }
          }
          s = s.floorToDouble().clamp(10.0, 72.0);
          final rows = (16 / cols).ceil();
          return Center(
            child: SizedBox(
              width: s * cols,
              height: s * rows,
              child: Wrap(children: [
                for (var p = 0; p < 16; p++)
                  MouseRegion(
                    onEnter: (_) => setState(() => hoverPool = p),
                    onExit: (_) => setState(() => hoverPool = -1),
                    child: GestureDetector(
                      onTap: giving && avail.contains(p) ? () => g.act({'type': 'give', 'piece': p}) : null,
                      child: Tooltip(
                        message: quartoPieceName(p),
                        child: Container(
                          width: s,
                          height: s,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(s * 0.2),
                            color: giving && hoverPool == p && avail.contains(p) ? cs.primary.withValues(alpha: 0.22) : null,
                          ),
                          child: avail.contains(p) ? CustomPaint(painter: _PiecePainter(p)) : null,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          );
        });
        return Row(children: [handBox, const SizedBox(width: 6), Expanded(child: pool)]);
      }),
    );

    return A2Shell(
      tags: [tagFor(me == 1 ? 0 : 1), tagFor(me == 1 ? 1 : 0)],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      tray: tray,
      trayFraction: 0.16,
      info: [
        if (lastText.isNotEmpty) '上一步：$lastText',
        '四枚连成一线且共享任一属性（高/矮、深/浅、方/圆、空心/实心）即胜${squares ? '；2×2 方块也算' : ''}',
      ],
      result: a2Banner(g, over, winner),
      resultSub: over ? result : null,
    );
  }
}
