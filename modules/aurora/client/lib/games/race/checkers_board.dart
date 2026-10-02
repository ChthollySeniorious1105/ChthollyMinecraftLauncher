import 'dart:math';

import 'package:aurora_shared/games/race/checkers.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'race_common.dart';

/// Colours per corner (not per seat) so each camp keeps its colour.
const _cornerColors = [
  Color(0xFFE53935),
  Color(0xFFFFB300),
  Color(0xFF43A047),
  Color(0xFF1E88E5),
  Color(0xFF8E24AA),
  Color(0xFFFF7043),
];
const _cornerNames = ['红', '黄', '绿', '蓝', '紫', '橙'];

class CheckersBoard extends StatefulWidget {
  final GameContext g;
  const CheckersBoard(this.g, {super.key});
  @override
  State<CheckersBoard> createState() => _CheckersBoardState();
}

class _CheckersBoardState extends State<CheckersBoard> {
  int? sel;

  // board extents in unit coordinates
  static final double _minX = List.generate(CCGeo.cells.length, (i) => CCGeo.xy(i).$1).reduce(min);
  static final double _maxX = List.generate(CCGeo.cells.length, (i) => CCGeo.xy(i).$1).reduce(max);
  static final double _minY = List.generate(CCGeo.cells.length, (i) => CCGeo.xy(i).$2).reduce(min);
  static final double _maxY = List.generate(CCGeo.cells.length, (i) => CCGeo.xy(i).$2).reduce(max);

  /// Client-side reachability (mirrors the engine; server re-validates).
  Set<int> _reach(List<int> board, int from) {
    final out = <int>{};
    final (q, r) = CCGeo.cells[from];
    for (final (dq, dr) in CCGeo.dirs) {
      final n = CCGeo.at(q + dq, r + dr);
      if (n != null && board[n] < 0) out.add(n);
    }
    final seen = <int>{from};
    final stack = [from];
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      final (cq, cr) = CCGeo.cells[c];
      for (final (dq, dr) in CCGeo.dirs) {
        final over = CCGeo.at(cq + dq, cr + dr);
        final land = CCGeo.at(cq + 2 * dq, cr + 2 * dr);
        if (over == null || land == null || board[over] < 0 || board[land] >= 0) continue;
        if (seen.add(land)) {
          out.add(land);
          stack.add(land);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final home = (v['home'] as List).cast<int>();
    final target = (v['target'] as List).cast<int>();
    final turn = v['turn'] as int;
    final winner = v['winner'] as int;
    final last = (v['last'] as List).cast<int>();
    final lastSeat = v['lastSeat'] as int;
    final inTarget = (v['inTarget'] as List).cast<int>();
    final myTurn = !g.over && winner < 0 && turn == g.seat;
    if (!myTurn || (sel != null && board[sel!] != g.seat)) sel = null;
    final reach = sel == null ? <int>{} : _reach(board, sel!);
    final cs = Theme.of(context).colorScheme;

    Color seatColor(int s) => _cornerColors[home[s]];
    final status = v['drawn'] == true
        ? '和棋'
        : winner >= 0
        ? '${g.name(winner)} 获胜！'
        : myTurn
            ? (sel == null ? '轮到你：点选一颗${_cornerNames[home[g.seat]]}色棋子' : '点击高亮位置移动（可连跳）')
            : '等待 ${g.name(turn)}';

    final tags = [
      for (var s = 0; s < g.players; s++)
        g.tag(s, active: winner < 0 && turn == s, sub: '进营 ${inTarget[s]}/10', trailing: colorDot(seatColor(s))),
    ];

    final controls = Text(
      '第 ${v['turns']} 步 / 上限 ${v['cap']} 步（到达上限时进营最多者胜）',
      style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.65)),
      textAlign: TextAlign.center,
    );

    final w = _maxX - _minX + 2, h = _maxY - _minY + 2;
    return RaceScaffold(
      tags: tags,
      status: status,
      highlight: myTurn,
      controls: controls,
      boardAspect: w / h,
      overlay: winner >= 0
          ? DismissibleResult(v['capped'] == true ? '达到步数上限，${g.name(winner)} 胜' : '${g.name(winner)} 全部棋子进入对面营地！')
          : null,
      board: LayoutBuilder(builder: (context, c) {
        final u = min(c.maxWidth / w, c.maxHeight / h);
        final ox = (c.maxWidth - w * u) / 2 + (1 - _minX) * u;
        final oy = (c.maxHeight - h * u) / 2 + (1 - _minY) * u;
        Offset pt(int i) {
          final (x, y) = CCGeo.xy(i);
          return Offset(ox + x * u, oy + y * u);
        }

        void tapAt(Offset p) {
          if (!myTurn) return;
          int? best;
          var bd = double.infinity;
          for (var i = 0; i < board.length; i++) {
            final d = (pt(i) - p).distance;
            if (d < bd) {
              bd = d;
              best = i;
            }
          }
          if (best == null || bd > u * 0.6) return;
          if (board[best] == g.seat) {
            setState(() => sel = sel == best ? null : best);
          } else if (sel != null && reach.contains(best)) {
            final from = sel!;
            setState(() => sel = null);
            g.act({'from': from, 'to': best});
          } else {
            setState(() => sel = null);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => tapAt(d.localPosition),
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _StarPainter(
              board: board,
              pt: pt,
              u: u,
              seatColors: [for (var s = 0; s < home.length; s++) seatColor(s)],
              targetCorners: {for (var s = 0; s < target.length; s++) target[s]: seatColor(s)},
              sel: sel,
              reach: reach,
              last: last,
              lastColor: lastSeat >= 0 ? seatColor(lastSeat) : Colors.white,
              cs: cs,
            ),
          ),
        );
      }),
    );
  }
}

class _StarPainter extends CustomPainter {
  final List<int> board;
  final Offset Function(int) pt;
  final double u;
  final List<Color> seatColors;
  final Map<int, Color> targetCorners;
  final int? sel;
  final Set<int> reach;
  final List<int> last;
  final Color lastColor;
  final ColorScheme cs;
  _StarPainter({
    required this.board,
    required this.pt,
    required this.u,
    required this.seatColors,
    required this.targetCorners,
    required this.sel,
    required this.reach,
    required this.last,
    required this.lastColor,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // star background: two big triangles
    final top = CCGeo.tip(0), bl = CCGeo.tip(4), br = CCGeo.tip(2);
    final bottom = CCGeo.tip(3), tl = CCGeo.tip(5), tr = CCGeo.tip(1);
    Path tri(int a, int b, int c) {
      Offset grow(Offset p) {
        final center = (pt(a) + pt(b) + pt(c)) / 3;
        return center + (p - center) * 1.12;
      }

      return Path()
        ..moveTo(grow(pt(a)).dx, grow(pt(a)).dy)
        ..lineTo(grow(pt(b)).dx, grow(pt(b)).dy)
        ..lineTo(grow(pt(c)).dx, grow(pt(c)).dy)
        ..close();
    }

    final star = Path.combine(PathOperation.union, tri(top, bl, br), tri(bottom, tl, tr));
    canvas.drawShadow(star, Colors.black, 6, false);
    canvas.drawPath(
        star,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF5E6C8), Color(0xFFD7B98E)],
          ).createShader(Offset.zero & size));
    canvas.drawPath(star, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.08
      ..color = const Color(0xFF8D6E63));

    // corner tints for target camps
    for (var k = 0; k < 6; k++) {
      final c = targetCorners[k];
      if (c == null) continue;
      for (final i in CCGeo.corners[k]) {
        canvas.drawCircle(pt(i), u * 0.46, Paint()..color = c.withValues(alpha: 0.18));
      }
    }

    // last move path
    if (last.length >= 2) {
      final p = Paint()
        ..color = lastColor.withValues(alpha: 0.7)
        ..strokeWidth = u * 0.12
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(pt(last.first).dx, pt(last.first).dy);
      for (final i in last.skip(1)) {
        path.lineTo(pt(i).dx, pt(i).dy);
      }
      canvas.drawPath(path, p);
      canvas.drawCircle(pt(last.first), u * 0.18, Paint()..color = lastColor.withValues(alpha: 0.6));
    }

    for (var i = 0; i < board.length; i++) {
      final c = pt(i);
      // hole
      canvas.drawCircle(c, u * 0.3, Paint()..color = const Color(0xFF6D4C41).withValues(alpha: 0.55));
      canvas.drawCircle(c + Offset(0, u * 0.03), u * 0.26, Paint()..color = const Color(0xFF3E2723).withValues(alpha: 0.35));
      final s = board[i];
      if (s >= 0) {
        final col = seatColors[s];
        final r = u * 0.4;
        canvas.drawCircle(c + Offset(u * 0.04, u * 0.07), r, Paint()..color = Colors.black38);
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..shader = RadialGradient(
                center: const Alignment(-0.35, -0.4),
                radius: 0.9,
                colors: [Color.lerp(col, Colors.white, 0.6)!, col, Color.lerp(col, Colors.black, 0.4)!],
                stops: const [0, 0.5, 1],
              ).createShader(Rect.fromCircle(center: c, radius: r)));
        canvas.drawCircle(c + Offset(-r * 0.35, -r * 0.4), r * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.7));
      }
      if (i == sel) {
        canvas.drawCircle(c, u * 0.48, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.1
          ..color = Colors.amber);
      }
      if (reach.contains(i)) {
        canvas.drawCircle(c, u * 0.22, Paint()..color = Colors.amber.withValues(alpha: 0.9));
        canvas.drawCircle(c, u * 0.36, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.05
          ..color = Colors.amber);
      }
      if (last.isNotEmpty && i == last.last && s >= 0) {
        canvas.drawCircle(c, u * 0.45, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.05
          ..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => true;
}
