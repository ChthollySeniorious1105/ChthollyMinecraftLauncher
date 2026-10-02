import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const kDotColors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047), Color(0xFFFB8C00)];

class _DotsPainter extends CustomPainter {
  final int n;
  final List<int> edges;
  final List<int> boxes;
  final Set<int> turnEdges;
  final int lastEdge;
  final int hover;
  final Color hoverColor;
  final Color ink;
  final Color paper;
  final List<String> initials;

  _DotsPainter({
    required this.n,
    required this.edges,
    required this.boxes,
    required this.turnEdges,
    required this.lastEdge,
    required this.hover,
    required this.hoverColor,
    required this.ink,
    required this.paper,
    required this.initials,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final m = size.width * 0.08;
    final cell = (size.width - 2 * m) / n;
    final h = n * (n + 1);
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.03));
    canvas.drawRRect(bg, Paint()..color = paper);
    Offset dot(int r, int c) => Offset(m + c * cell, m + r * cell);
    (Offset, Offset) seg(int e) {
      if (e < h) {
        final r = e ~/ n, c = e % n;
        return (dot(r, c), dot(r, c + 1));
      }
      final k = e - h, r = k ~/ (n + 1), c = k % (n + 1);
      return (dot(r, c), dot(r + 1, c));
    }

    // boxes
    for (var b = 0; b < n * n; b++) {
      final o = boxes[b];
      if (o < 0) continue;
      final r = b ~/ n, c = b % n;
      final rect = Rect.fromLTWH(m + c * cell, m + r * cell, cell, cell).deflate(cell * 0.06);
      final col = kDotColors[o % 4];
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.08)), Paint()..color = col.withValues(alpha: 0.28));
      final tp = classicText(initials[o], cell * 0.38, col, weight: FontWeight.bold);
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
    // empty edges (faint) + hover
    final faint = Paint()
      ..color = ink.withValues(alpha: 0.12)
      ..strokeWidth = max(1, cell * 0.04)
      ..strokeCap = StrokeCap.round;
    for (var e = 0; e < edges.length; e++) {
      if (edges[e] >= 0) continue;
      final (a, b) = seg(e);
      canvas.drawLine(a, b, e == hover ? (Paint()
        ..color = hoverColor.withValues(alpha: 0.55)
        ..strokeWidth = max(3, cell * 0.1)
        ..strokeCap = StrokeCap.round) : faint);
    }
    for (var e = 0; e < edges.length; e++) {
      final s = edges[e];
      if (s < 0) continue;
      final (a, b) = seg(e);
      final col = kDotColors[s % 4];
      final recent = turnEdges.contains(e);
      if (recent) {
        canvas.drawLine(
            a,
            b,
            Paint()
              ..color = col.withValues(alpha: 0.35)
              ..strokeWidth = max(6, cell * 0.2)
              ..strokeCap = StrokeCap.round);
      }
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = col
            ..strokeWidth = max(3, cell * (e == lastEdge ? 0.11 : 0.085))
            ..strokeCap = StrokeCap.round);
    }
    final dp = Paint()..color = ink;
    for (var r = 0; r <= n; r++) {
      for (var c = 0; c <= n; c++) {
        canvas.drawCircle(dot(r, c), max(3, cell * 0.075), dp);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter o) => true;
}

class DotsBoxesBoardView extends StatefulWidget {
  final GameContext g;
  const DotsBoxesBoardView(this.g, {super.key});
  @override
  State<DotsBoxesBoardView> createState() => _DotsBoxesBoardViewState();
}

class _DotsBoxesBoardViewState extends State<DotsBoxesBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final edges = (v['edges'] as List).cast<int>();
    final boxes = (v['boxes'] as List).cast<int>();
    final scores = (v['scores'] as List).cast<int>();
    final turn = v['turn'] as int;
    final lastEdge = v['lastEdge'] as int;
    final turnEdges = (v['turnEdges'] as List).cast<int>().toSet();
    final winners = (v['winners'] as List).cast<int>();
    final result = v['result'] as String;
    final note = v['note'] as String;
    final over = v['over'] as bool;
    final me = g.seat;
    final myTurn = !over && turn == me;
    final players = scores.length;
    final h = n * (n + 1);

    final status = over
        ? result
        : myTurn
            ? (note.isNotEmpty ? '围成格子！再画一条线' : '轮到你，点击两点之间画线')
            : '${note.isNotEmpty ? '$note · ' : ''}等待 ${g.name(turn)}';

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final m = side * 0.08;
      final cell = (side - 2 * m) / n;
      int edgeAt(Offset o) {
        final x = (o.dx - m) / cell, y = (o.dy - m) / cell;
        var best = -1;
        var bd = 0.3;
        // horizontal edges
        final hr = y.round(), hc = x.floor();
        if (hr >= 0 && hr <= n && hc >= 0 && hc < n) {
          final d = (y - hr).abs();
          if (d < bd) {
            bd = d;
            best = hr * n + hc;
          }
        }
        final vc = x.round(), vr = y.floor();
        if (vc >= 0 && vc <= n && vr >= 0 && vr < n) {
          final d = (x - vc).abs();
          if (d < bd) {
            bd = d;
            best = h + vr * (n + 1) + vc;
          }
        }
        return best;
      }

      return MouseRegion(
        onHover: (e) {
          final p = myTurn ? edgeAt(e.localPosition) : -1;
          if (p != hover) setState(() => hover = p);
        },
        onExit: (_) => setState(() => hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final e = edgeAt(d.localPosition);
            if (e >= 0 && myTurn && edges[e] < 0) g.act({'type': 'edge', 'edge': e});
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(side * 0.03),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: CustomPaint(
              size: Size(side, side),
              painter: _DotsPainter(
                n: n,
                edges: edges,
                boxes: boxes,
                turnEdges: turnEdges,
                lastEdge: lastEdge,
                hover: myTurn && hover >= 0 && edges[hover] < 0 ? hover : -1,
                hoverColor: kDotColors[(me < 0 ? 0 : me) % 4],
                ink: const Color(0xFF37474F),
                paper: const Color(0xFFF6F1E4),
                initials: [for (var s = 0; s < players; s++) g.name(s).isEmpty ? '?' : g.name(s).characters.first],
              ),
            ),
          ),
        ),
      );
    });

    String? banner;
    if (over) {
      banner = winners.length > 1
          ? (winners.contains(me) ? '并列第一！' : '平局')
          : (winners.first == me ? '你赢了！' : '${g.name(winners.first)} 获胜');
    }
    final order = g.seatsFromMe();
    final left = boxes.where((b) => b < 0).length;
    return ClassicShell(
      tags: [
        for (final s in order)
          g.tag(s,
              active: !over && turn == s,
              sub: '${scores[s]} 格',
              trailing: Container(
                  width: 14, height: 14, decoration: BoxDecoration(color: kDotColors[s % 4], shape: BoxShape.circle))),
      ],
      status: status,
      statusHighlight: myTurn,
      board: boardWidget,
      info: InfoPanel([
        '$n×$n 格 · 剩余 $left 格 · 围成格子可再走一步',
      ]),
      result: banner,
    );
  }
}
