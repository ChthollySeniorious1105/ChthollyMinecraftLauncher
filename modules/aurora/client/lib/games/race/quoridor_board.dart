import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'race_common.dart';

const _pawnColors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFFB300)];
const _sideNames = ['上方', '右侧', '下方', '左侧']; // goal side for start side 0..3

class QuoridorBoard extends StatefulWidget {
  final GameContext g;
  const QuoridorBoard(this.g, {super.key});
  @override
  State<QuoridorBoard> createState() => _QuoridorBoardState();
}

class _QuoridorBoardState extends State<QuoridorBoard> {
  bool wallMode = false;
  String orient = 'h';
  (int, int)? preview; // wall anchor under the pointer / last tap

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final pawns = [for (final p in v['pawns'] as List) (p as List).cast<int>()];
    final sides = (v['sides'] as List).cast<int>();
    final walls = [for (final w in v['walls'] as List) w as List];
    final wallsLeft = (v['wallsLeft'] as List).cast<int>();
    final turn = v['turn'] as int;
    final winner = v['winner'] as int;
    final moves = [for (final m in v['moves'] as List) (m as List).cast<int>()];
    final dist = (v['dist'] as List).cast<int>();
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final myTurn = !g.over && winner < 0 && turn == g.seat;
    final cs = Theme.of(context).colorScheme;
    if (!myTurn || wallsLeft[max(0, g.seat)] <= 0) {
      if (wallMode) wallMode = false;
    }

    // Rotate the board so that my pawn starts at the bottom.
    final rot = g.seat >= 0 ? sides[g.seat] : 0; // quarter turns to undo
    (int, int) toScreen(int r, int c) {
      var (rr, cc) = (r, c);
      for (var i = 0; i < rot; i++) {
        (rr, cc) = (8 - cc, rr); // rotate counter-clockwise
      }
      return (rr, cc);
    }

    (int, int) fromScreen(int r, int c) {
      var (rr, cc) = (r, c);
      for (var i = 0; i < rot; i++) {
        (rr, cc) = (cc, 8 - rr);
      }
      return (rr, cc);
    }

    // wall anchors (r,c in 0..7) under rotation: anchor is the corner between cells
    // (r,c),(r+1,c+1). Rotating maps it to the corner between the rotated cells.
    (int, int, String) wallToScreen(int r, int c, String o) {
      final (a1, b1) = toScreen(r, c);
      final (a2, b2) = toScreen(r + 1, c + 1);
      final o2 = rot.isOdd ? (o == 'h' ? 'v' : 'h') : o;
      return (min(a1, a2), min(b1, b2), o2);
    }

    (int, int, String) wallFromScreen(int r, int c, String o) {
      final (a1, b1) = fromScreen(r, c);
      final (a2, b2) = fromScreen(r + 1, c + 1);
      final o2 = rot.isOdd ? (o == 'h' ? 'v' : 'h') : o;
      return (min(a1, a2), min(b1, b2), o2);
    }

    String status;
    if (v['drawn'] == true) {
      status = '和棋';
    } else if (winner >= 0) {
      status = '${g.name(winner)} 获胜！';
    } else if (myTurn) {
      status = wallMode ? '放墙：点击格线交点放置${orient == 'h' ? '横' : '竖'}墙' : '轮到你：移动棋子或放墙';
    } else {
      status = '等待 ${g.name(turn)}';
    }

    final tags = [
      for (var s = 0; s < g.players; s++)
        g.tag(s,
            active: winner < 0 && turn == s,
            sub: '墙 ${wallsLeft[s]} · 距终点 ${dist[s]}',
            trailing: colorDot(_pawnColors[s])),
    ];

    final canWall = myTurn && wallsLeft[g.seat] > 0;
    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('走棋'), icon: Icon(Icons.directions_walk)),
            ButtonSegment(value: true, label: Text('放墙'), icon: Icon(Icons.horizontal_rule)),
          ],
          selected: {wallMode},
          onSelectionChanged: canWall ? (s) => setState(() => wallMode = s.first) : null,
        ),
        if (wallMode)
          OutlinedButton.icon(
            onPressed: () => setState(() => orient = orient == 'h' ? 'v' : 'h'),
            icon: const Icon(Icons.rotate_90_degrees_ccw),
            label: Text(orient == 'h' ? '横墙' : '竖墙'),
          ),
        if (myTurn && moves.isEmpty && !canWall)
          FilledButton(onPressed: () => g.act({'t': 'pass'}), child: const Text('无路可走，跳过')),
      ]),
      const SizedBox(height: 4),
      Text(
        g.seat >= 0 ? '目标：到达${_sideNames[0]}（第 ${v['turns']}/${v['cap']} 步）' : '第 ${v['turns']}/${v['cap']} 步',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.65)),
      ),
    ]);

    return RaceScaffold(
      tags: tags,
      status: status,
      highlight: myTurn,
      controls: controls,
      overlay: winner >= 0 ? DismissibleResult(v['capped'] == true ? '达到步数上限，${g.name(winner)} 离终点最近获胜' : '${g.name(winner)} 到达终点！') : null,
      board: LayoutBuilder(builder: (context, c) {
        final size = min(c.maxWidth, c.maxHeight);
        final pad = size * 0.03;
        final cell = (size - 2 * pad) / 9;
        final gap = cell * 0.14;

        (int, int)? anchorAt(Offset p) {
          final x = (p.dx - pad) / cell, y = (p.dy - pad) / cell;
          final c = (x - 1).round(), r = (y - 1).round();
          if (r < 0 || r > 7 || c < 0 || c > 7) {
            final cr = (y - 1).clamp(0, 7).round(), cc = (x - 1).clamp(0, 7).round();
            return (cr, cc);
          }
          return (r, c);
        }

        void onTap(Offset p) {
          if (!myTurn) return;
          if (wallMode) {
            final a = anchorAt(p);
            if (a == null) return;
            final (r, cc, o) = wallFromScreen(a.$1, a.$2, orient);
            setState(() => preview = null);
            g.act({'t': 'wall', 'r': r, 'c': cc, 'o': o});
            return;
          }
          final sc = ((p.dx - pad) / cell).floor(), sr = ((p.dy - pad) / cell).floor();
          if (sr < 0 || sr > 8 || sc < 0 || sc > 8) return;
          final (r, cc) = fromScreen(sr, sc);
          if (moves.any((m) => m[0] == r && m[1] == cc)) g.act({'t': 'move', 'r': r, 'c': cc});
        }

        final screenWalls = [
          for (final w in walls) (wallToScreen(w[0] as int, w[1] as int, w[2] as String), w[3] as int),
        ];
        final lastWall = last?['t'] == 'wall' ? (last!['wall'] as List) : null;
        final screenLast = lastWall == null ? null : wallToScreen(lastWall[0] as int, lastWall[1] as int, lastWall[2] as String);

        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: MouseRegion(
              onHover: wallMode ? (e) => setState(() => preview = anchorAt(e.localPosition)) : null,
              onExit: (_) => setState(() => preview = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => onTap(d.localPosition),
                child: CustomPaint(
                  painter: _QPainter(
                    pad: pad,
                    cell: cell,
                    gap: gap,
                    pawns: [for (final p in pawns) toScreen(p[0], p[1])],
                    moves: wallMode || !myTurn ? const [] : [for (final m in moves) toScreen(m[0], m[1])],
                    walls: screenWalls,
                    lastWall: screenLast,
                    preview: wallMode && preview != null ? (preview!.$1, preview!.$2, orient) : null,
                    goalSides: [for (final s in sides) ((s - rot) % 4 + 4) % 4],
                    turn: winner < 0 ? turn : -1,
                    lastMoveTo: last?['t'] == 'move' ? toScreen((last!['to'] as List)[0] as int, (last['to'] as List)[1] as int) : null,
                    cs: cs,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _QPainter extends CustomPainter {
  final double pad, cell, gap;
  final List<(int, int)> pawns;
  final List<(int, int)> moves;
  final List<((int, int, String), int)> walls;
  final (int, int, String)? lastWall;
  final (int, int, String)? preview;
  final List<int> goalSides; // screen side each pawn is heading to: 0 top,1 right,2 bottom,3 left
  final int turn;
  final (int, int)? lastMoveTo;
  final ColorScheme cs;
  _QPainter({
    required this.pad,
    required this.cell,
    required this.gap,
    required this.pawns,
    required this.moves,
    required this.walls,
    required this.lastWall,
    required this.preview,
    required this.goalSides,
    required this.turn,
    required this.lastMoveTo,
    required this.cs,
  });

  Rect _cell(int r, int c) =>
      Rect.fromLTWH(pad + c * cell + gap / 2, pad + r * cell + gap / 2, cell - gap, cell - gap);

  Rect _wall(int r, int c, String o) {
    final x = pad + (c + 1) * cell, y = pad + (r + 1) * cell;
    final t = gap * 0.9;
    return o == 'h'
        ? Rect.fromLTRB(x - cell + gap / 2, y - t / 2, x + cell - gap / 2, y + t / 2)
        : Rect.fromLTRB(x - t / 2, y - cell + gap / 2, x + t / 2, y + cell - gap / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.3));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF5D4037));
    // goal edges
    for (var s = 0; s < pawns.length; s++) {
      final col = _pawnColors[s].withValues(alpha: 0.8);
      final p = Paint()..color = col;
      final e = pad * 0.8;
      switch (goalSides[s]) {
        case 0:
          canvas.drawRect(Rect.fromLTWH(pad, 0, size.width - 2 * pad, e), p);
        case 1:
          canvas.drawRect(Rect.fromLTWH(size.width - e, pad, e, size.height - 2 * pad), p);
        case 2:
          canvas.drawRect(Rect.fromLTWH(pad, size.height - e, size.width - 2 * pad, e), p);
        default:
          canvas.drawRect(Rect.fromLTWH(0, pad, e, size.height - 2 * pad), p);
      }
    }
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        final rr = RRect.fromRectAndRadius(_cell(r, c), Radius.circular(cell * 0.12));
        canvas.drawRRect(rr, Paint()..color = const Color(0xFFD7B98E));
        canvas.drawRRect(rr.deflate(cell * 0.04), Paint()..color = const Color(0xFFE8CFA5));
      }
    }
    if (lastMoveTo != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(_cell(lastMoveTo!.$1, lastMoveTo!.$2), Radius.circular(cell * 0.12)),
          Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    for (final (r, c) in moves) {
      final rect = _cell(r, c);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.12)),
          Paint()..color = Colors.amber.withValues(alpha: 0.45));
      canvas.drawCircle(rect.center, cell * 0.12, Paint()..color = Colors.amber.shade800);
    }
    for (final ((r, c, o), s) in walls) {
      final rect = _wall(r, c, o);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(gap * 0.4));
      canvas.drawRRect(rr.shift(const Offset(1, 2)), Paint()..color = Colors.black45);
      canvas.drawRRect(rr, Paint()..color = Color.lerp(_pawnColors[s], Colors.black, 0.25)!);
      if (lastWall == (r, c, o)) {
        canvas.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
      }
    }
    if (preview != null) {
      final (r, c, o) = preview!;
      canvas.drawRRect(RRect.fromRectAndRadius(_wall(r, c, o), Radius.circular(gap * 0.4)),
          Paint()..color = Colors.amber.withValues(alpha: 0.7));
    }
    for (var s = 0; s < pawns.length; s++) {
      final (r, c) = pawns[s];
      final center = _cell(r, c).center;
      final rad = cell * 0.33;
      final col = _pawnColors[s];
      canvas.drawCircle(center + Offset(rad * 0.1, rad * 0.18), rad, Paint()..color = Colors.black45);
      canvas.drawCircle(
          center,
          rad,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.35, -0.4),
              colors: [Color.lerp(col, Colors.white, 0.55)!, col, Color.lerp(col, Colors.black, 0.4)!],
              stops: const [0, 0.55, 1],
            ).createShader(Rect.fromCircle(center: center, radius: rad)));
      if (s == turn) {
        canvas.drawCircle(center, rad + 3, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QPainter old) => true;
}
