import 'dart:math';

import 'package:aurora_shared/games/abstract2/onitama.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _red = Color(0xFFD0443E);
const _blue = Color(0xFF2E6FD1);
Color _colorOf(int c) => c == 0 ? _red : _blue;

/// Board painter. [flip] = viewer plays blue (board rotated 180°).
class _OniPainter extends CustomPainter {
  final List<int> board;
  final bool flip;
  final int sel;
  final Set<int> targets;
  final int hover;
  final int lastFrom, lastTo;
  final Color accent;
  _OniPainter(this.board, this.flip, this.sel, this.targets, this.hover, this.lastFrom, this.lastTo, this.accent);

  static Rect cellRect(Size s, int p, bool flip) {
    final cell = s.width / 5;
    final x = p % 5, y = p ~/ 5;
    final sx = flip ? 4 - x : x, sy = flip ? y : 4 - y;
    return Rect.fromLTWH(sx * cell, sy * cell, cell, cell);
  }

  static int hit(Size s, Offset o, bool flip) {
    final cell = s.width / 5;
    final sx = (o.dx / cell).floor(), sy = (o.dy / cell).floor();
    if (sx < 0 || sy < 0 || sx > 4 || sy > 4) return -1;
    final x = flip ? 4 - sx : sx, y = flip ? sy : 4 - sy;
    return y * 5 + x;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.18));
    canvas.drawRRect(rr.shift(Offset(0, cell * 0.06)), a2Shadow(cell * 0.12, alpha: 0.5));
    canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAD7B0), Color(0xFFD9BF8C), Color(0xFFE6D2A6)],
          ).createShader(Offset.zero & size));
    canvas.save();
    canvas.clipRRect(rr);
    for (var p = 0; p < 25; p++) {
      final r = cellRect(size, p, flip).deflate(cell * 0.04);
      final isTemple = p == 2 || p == 22;
      var fill = ((p % 5) + (p ~/ 5)) % 2 == 0 ? const Color(0x22000000) : const Color(0x10000000);
      if (isTemple) fill = (p == 2 ? _red : _blue).withValues(alpha: 0.22);
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cell * 0.1)), Paint()..color = fill);
      if (isTemple) {
        // temple arch glyph
        final c = r.center;
        final path = Path()
          ..moveTo(c.dx - cell * 0.28, c.dy + cell * 0.3)
          ..lineTo(c.dx - cell * 0.28, c.dy - cell * 0.12)
          ..moveTo(c.dx + cell * 0.28, c.dy + cell * 0.3)
          ..lineTo(c.dx + cell * 0.28, c.dy - cell * 0.12)
          ..moveTo(c.dx - cell * 0.38, c.dy - cell * 0.2)
          ..quadraticBezierTo(c.dx, c.dy - cell * 0.34, c.dx + cell * 0.38, c.dy - cell * 0.2)
          ..moveTo(c.dx - cell * 0.32, c.dy - cell * 0.05)
          ..lineTo(c.dx + cell * 0.32, c.dy - cell * 0.05);
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.05
              ..strokeCap = StrokeCap.round
              ..color = (p == 2 ? _red : _blue).withValues(alpha: 0.45));
      }
      if (p == lastFrom || p == lastTo) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(cell * 0.1)),
            Paint()..color = const Color(0x44FFD54F));
      }
    }
    canvas.restore();
    // grid lines
    final line = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = max(1, cell * 0.015);
    for (var i = 1; i < 5; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), line);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), line);
    }
    if (sel >= 0) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(cellRect(size, sel, flip).deflate(cell * 0.04), Radius.circular(cell * 0.1)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.06
            ..color = accent);
    }
    for (var p = 0; p < 25; p++) {
      final v = board[p];
      if (v == 0) continue;
      final c = cellRect(size, p, flip).center;
      final color = OniState.colorAt(v);
      final master = OniState.isMaster(v);
      _paintPawn(canvas, c, cell, _colorOf(color), master);
    }
    for (final t in targets) {
      final r = cellRect(size, t, flip);
      final cap = board[t] != 0;
      if (cap) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r.deflate(cell * 0.06), Radius.circular(cell * 0.12)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.07
              ..color = const Color(0xCCE53935));
      } else {
        canvas.drawCircle(r.center, cell * (t == hover ? 0.2 : 0.13), Paint()..color = const Color(0xCC43A047));
      }
    }
  }

  void _paintPawn(Canvas canvas, Offset c, double cell, Color color, bool master) {
    final r = cell * (master ? 0.36 : 0.28);
    canvas.drawCircle(c + Offset(r * 0.1, r * 0.2), r, a2Shadow(r * 0.18, alpha: 0.45));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.45),
            colors: [Color.lerp(color, Colors.white, 0.45)!, color, Color.lerp(color, Colors.black, 0.4)!],
            stops: const [0, 0.6, 1],
          ).createShader(rect));
    canvas.drawCircle(
        c,
        r * 0.72,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, r * 0.08)
          ..color = Colors.white.withValues(alpha: 0.55));
    a2PaintTextCentered(canvas, master ? '师' : '徒', c, r * (master ? 0.95 : 0.9), Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

/// Mini 5×5 pattern of a card. [flip] shows it from the other side.
class _PatternPainter extends CustomPainter {
  final List<(int, int)> moves;
  final bool flip;
  final Color color;
  _PatternPainter(this.moves, this.flip, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = min(size.width, size.height) / 5;
    final ox = (size.width - s * 5) / 2, oy = (size.height - s * 5) / 2;
    Rect r(int gx, int gy) => Rect.fromLTWH(ox + gx * s, oy + gy * s, s, s).deflate(max(0.5, s * 0.06));
    for (var gy = 0; gy < 5; gy++) {
      for (var gx = 0; gx < 5; gx++) {
        canvas.drawRect(r(gx, gy), Paint()..color = const Color(0x1F000000));
      }
    }
    canvas.drawRect(r(2, 2), Paint()..color = const Color(0xFF333333));
    for (final (dx, dy) in moves) {
      final gx = flip ? 2 - dx : 2 + dx, gy = flip ? 2 + dy : 2 - dy;
      if (gx < 0 || gy < 0 || gx > 4 || gy > 4) continue;
      canvas.drawRect(r(gx, gy), Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter o) => o.flip != flip || o.color != color || o.moves != moves;
}

class _CardView extends StatelessWidget {
  final String id;
  final bool flip;
  final bool selected;
  final bool dim;
  final bool justUsed;
  final VoidCallback? onTap;
  const _CardView(this.id, {this.flip = false, this.selected = false, this.dim = false, this.justUsed = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = oniCards[oniCardIndex(id)];
    final stamp = _colorOf(card.stamp);
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: EdgeInsets.all(h * 0.04),
          padding: EdgeInsets.all(h * 0.06),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFBF3E0), Color(0xFFEBDDBE)],
            ),
            borderRadius: BorderRadius.circular(h * 0.1),
            border: Border.all(
                color: selected ? cs.primary : (justUsed ? const Color(0xFFFFB300) : const Color(0xFFB89A62)),
                width: selected ? 3 : 1.5),
            boxShadow: [
              BoxShadow(
                  color: selected ? cs.primary.withValues(alpha: 0.5) : Colors.black38,
                  blurRadius: selected ? 10 : 4,
                  offset: const Offset(0, 2)),
            ],
          ),
          foregroundDecoration: dim
              ? BoxDecoration(color: Colors.black.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(h * 0.1))
              : null,
          child: Row(children: [
            Expanded(
              flex: 5,
              child: RotatedBox(
                quarterTurns: flip ? 2 : 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: h * 0.14,
                      height: h * 0.14,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: stamp),
                    ),
                    SizedBox(height: h * 0.04),
                    Text(card.name,
                        style: TextStyle(fontSize: h * 0.24, fontWeight: FontWeight.w800, color: const Color(0xFF4E342E))),
                  ]),
                ),
              ),
            ),
            Expanded(
              flex: 6,
              child: CustomPaint(painter: _PatternPainter(card.moves, flip, stamp.withValues(alpha: 0.85)), child: const SizedBox.expand()),
            ),
          ]),
        ),
      );
    });
  }
}

class OnitamaBoardView extends StatefulWidget {
  final GameContext g;
  const OnitamaBoardView(this.g, {super.key});
  @override
  State<OnitamaBoardView> createState() => _OnitamaBoardViewState();
}

class _OnitamaBoardViewState extends State<OnitamaBoardView> {
  String? card;
  int sel = -1;
  int hover = -1;
  int pendingTo = -1;
  Object? _lastView;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = g.view;
    if (!identical(v, _lastView)) {
      if (_lastView != null && (v['plies'] != (_lastView as Map)['plies'] || v['turn'] != (_lastView as Map)['turn'])) {
        card = null;
        sel = -1;
        pendingTo = -1;
      }
      _lastView = v;
    }
    final board = (v['board'] as List).cast<int>();
    final hands = [for (final h in v['hands'] as List) (h as List).cast<String>()];
    final side = v['side'] as String;
    final redSeat = v['redSeat'] as int;
    final toMove = v['toMove'] as int;
    final turn = v['turn'] as int;
    final moves = [for (final m in v['moves'] as List) (m[0] as String, m[1] as int, m[2] as int)];
    final stuck = v['stuck'] == true;
    final last = v['last'] as Map?;
    final note = v['note'] as String;
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final over = v['over'] == true;
    final me = g.seat;
    final myColor = me == redSeat ? 0 : (me == 1 - redSeat ? 1 : -1);
    final viewColor = myColor < 0 ? 0 : myColor;
    final flip = viewColor == 1;
    final myTurn = !over && turn == me && !g.replay;
    final lastCard = last?['card'] as String?;
    final lastFrom = (last?['from'] as int?) ?? -1, lastTo = (last?['to'] as int?) ?? -1;

    final usable = myTurn ? moves.where((m) => (card == null || m.$1 == card) && (sel < 0 || m.$2 == sel)).toList() : const <(String, int, int)>[];
    final targets = sel >= 0 ? {for (final m in usable) m.$3} : <int>{};

    void tapCell(int p) {
      if (!myTurn || p < 0) return;
      if (sel >= 0 && targets.contains(p)) {
        final opts = usable.where((m) => m.$2 == sel && m.$3 == p).map((m) => m.$1).toSet();
        if (opts.length == 1) {
          g.act({'type': 'move', 'card': opts.first, 'from': sel, 'to': p});
          setState(() {
            sel = -1;
            card = null;
            pendingTo = -1;
          });
        } else {
          setState(() => pendingTo = p);
        }
        return;
      }
      final isMine = OniState.colorAt(board[p]) == toMove;
      setState(() {
        pendingTo = -1;
        sel = isMine && sel != p ? p : -1;
      });
    }

    void tapCard(String id) {
      if (!myTurn || !hands[toMove].contains(id)) return;
      if (stuck) {
        g.act({'type': 'pass', 'card': id});
        return;
      }
      if (pendingTo >= 0 && sel >= 0 && moves.contains((id, sel, pendingTo))) {
        g.act({'type': 'move', 'card': id, 'from': sel, 'to': pendingTo});
        setState(() {
          sel = -1;
          card = null;
          pendingTo = -1;
        });
        return;
      }
      setState(() {
        card = card == id ? null : id;
        pendingTo = -1;
      });
    }

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      if (stuck) {
        status = '无棋可走：点一张卡交给对手';
      } else if (pendingTo >= 0) {
        status = '两张卡都能走到这里，请点选使用哪张卡';
      } else if (sel < 0) {
        status = '轮到你：${card == null ? '选择卡片或' : ''}点选一枚棋子';
      } else {
        status = '点绿色格移动（红框为吃子）';
      }
    } else {
      status = '等待 ${g.name(turn)}（${toMove == 0 ? '红' : '蓝'}）';
    }

    final topColor = 1 - viewColor, botColor = viewColor;
    final boardWidget = LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final bSize = min(w / 1.3, h / 1.62);
      final rowH = bSize * 0.31;
      final sideW = bSize * 0.3;
      Widget cardRow(int color) => SizedBox(
            height: rowH,
            width: bSize,
            child: Row(children: [
              for (final id in hands[color])
                Expanded(
                  child: _CardView(
                    id,
                    flip: color != viewColor,
                    selected: myTurn && color == toMove && (card == id || (pendingTo >= 0 && moves.contains((id, sel, pendingTo)))),
                    dim: myTurn && color == toMove && card != null && card != id,
                    justUsed: false,
                    onTap: myTurn && color == toMove ? () => tapCard(id) : null,
                  ),
                ),
            ]),
          );
      final boardSize = Size(bSize, bSize);
      return Center(
        child: SizedBox(
          width: bSize + sideW,
          height: bSize + rowH * 2,
          child: Row(children: [
            SizedBox(
              width: bSize,
              child: Column(children: [
                cardRow(topColor),
                MouseRegion(
                  onHover: (e) {
                    final p = _OniPainter.hit(boardSize, e.localPosition, flip);
                    if (p != hover) setState(() => hover = p);
                  },
                  onExit: (_) => setState(() => hover = -1),
                  child: GestureDetector(
                    onTapUp: (d) => tapCell(_OniPainter.hit(boardSize, d.localPosition, flip)),
                    child: CustomPaint(
                      size: boardSize,
                      painter: _OniPainter(board, flip, sel, targets, hover, lastFrom, lastTo, cs.primary),
                    ),
                  ),
                ),
                cardRow(botColor),
              ]),
            ),
            SizedBox(
              width: sideW,
              child: Column(
                // the waiting card sits next to whoever will receive it next (the side to move)
                mainAxisAlignment: toMove == botColor ? MainAxisAlignment.end : MainAxisAlignment.start,
                children: [
                  SizedBox(height: rowH * 0.2),
                  Text('侧卡', style: TextStyle(fontSize: max(9, rowH * 0.14), color: cs.onSurface.withValues(alpha: 0.7))),
                  SizedBox(
                    width: sideW,
                    height: rowH,
                    child: RotatedBox(
                      quarterTurns: 0,
                      child: _CardView(side, flip: toMove != viewColor, justUsed: side == lastCard),
                    ),
                  ),
                  SizedBox(height: rowH * 0.2),
                ],
              ),
            ),
          ]),
        ),
      );
    });

    Widget tagFor(int s) {
      final c = s == redSeat ? 0 : 1;
      return g.tag(s,
          active: !over && turn == s,
          sub: '${c == 0 ? '红' : '蓝'}方${over ? (winner == s ? ' · 胜' : (winner == 2 ? ' · 和' : ' · 负')) : ''}',
          trailing: Container(width: 14, height: 14, decoration: BoxDecoration(color: _colorOf(c), shape: BoxShape.circle)));
    }

    final bottomSeat = viewColor == 0 ? redSeat : 1 - redSeat;
    return A2Shell(
      tags: [tagFor(1 - bottomSeat), tagFor(bottomSeat)],
      status: status,
      statusHighlight: myTurn,
      aspect: 1.3 / 1.62,
      board: boardWidget,
      info: [
        if (note.isNotEmpty) '上一步：$note',
        '吃掉对方师父，或让师父走进对方神殿（底线中间）即胜',
      ],
      result: a2Banner(g, over, winner),
      resultSub: over ? result : null,
    );
  }
}
