import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

List<int> _stars(int n) {
  final d = 3, lo = d, hi = n - 1 - d, mid = n ~/ 2;
  final pts = <int>[lo * n + lo, lo * n + hi, hi * n + lo, hi * n + hi, mid * n + mid];
  if (n == 19) pts.addAll([lo * n + mid, hi * n + mid, mid * n + lo, mid * n + hi]);
  return pts;
}

class _GomokuPainter extends CustomPainter {
  final int n;
  final List<int> board;
  final int last;
  final int hover;
  final int hoverColor;
  final Set<int> winLine;
  final Set<int> forbidden;
  final int forbiddenAt;
  final bool showForbidden;

  _GomokuPainter({
    required this.n,
    required this.board,
    required this.last,
    required this.hover,
    required this.hoverColor,
    required this.winLine,
    required this.forbidden,
    required this.forbiddenAt,
    required this.showForbidden,
  });

  static const _ink = Color(0xFF3B2A14);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / (n + 1);
    Offset pt(int p) => Offset((p % n + 1) * cell, (p ~/ n + 1) * cell);
    final line = Paint()
      ..color = _ink
      ..strokeWidth = max(0.7, cell * 0.035);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(cell, (i + 1) * cell), Offset(n * cell, (i + 1) * cell), line);
      canvas.drawLine(Offset((i + 1) * cell, cell), Offset((i + 1) * cell, n * cell), line);
    }
    canvas.drawRect(
        Rect.fromLTRB(cell, cell, n * cell, n * cell),
        Paint()
          ..color = _ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.4, cell * 0.07));
    final star = Paint()..color = _ink;
    for (final s in _stars(n)) {
      canvas.drawCircle(pt(s), max(2, cell * 0.11), star);
    }
    // coordinates
    final fs = cell * 0.34;
    const letters = 'ABCDEFGHJKLMNOPQRST';
    for (var i = 0; i < n; i++) {
      void t(String s, Offset c) {
        final tp = classicText(s, fs, const Color(0xFF5A4020));
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }

      t(letters[i], Offset((i + 1) * cell, cell * 0.45));
      t('${n - i}', Offset(cell * 0.42, (i + 1) * cell));
    }
    final r = cell * 0.46;
    for (var p = 0; p < n * n; p++) {
      final c = board[p];
      if (c == 0) continue;
      paintStone(canvas, pt(p), r, c == 1 ? kBlackStone : kWhiteStone);
    }
    if (hover >= 0 && hover < board.length && board[hover] == 0 && hoverColor > 0) {
      paintStone(canvas, pt(hover), r, hoverColor == 1 ? kBlackStone : kWhiteStone, opacity: 0.45, shadow: false);
    }
    // forbidden points for black
    if (showForbidden) {
      final xp = Paint()
        ..color = const Color(0xFFD32F2F)
        ..strokeWidth = max(1.5, cell * 0.08)
        ..strokeCap = StrokeCap.round;
      final h = cell * 0.2;
      for (final p in forbidden) {
        if (board[p] != 0) continue;
        final c = pt(p);
        canvas.drawLine(c + Offset(-h, -h), c + Offset(h, h), xp);
        canvas.drawLine(c + Offset(-h, h), c + Offset(h, -h), xp);
      }
    }
    // win line
    if (winLine.length >= 2) {
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
    if (forbiddenAt >= 0) {
      canvas.drawCircle(
          pt(forbiddenAt),
          r * 1.05,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2, cell * 0.1)
            ..color = const Color(0xFFE53935));
    }
    if (last >= 0 && last < board.length && board[last] != 0 && winLine.isEmpty) {
      canvas.drawCircle(pt(last), r * 0.28, Paint()..color = const Color(0xFFE53935));
    }
  }

  @override
  bool shouldRepaint(covariant _GomokuPainter o) => true;
}

class GomokuBoardView extends StatefulWidget {
  final GameContext g;
  const GomokuBoardView(this.g, {super.key});
  @override
  State<GomokuBoardView> createState() => _GomokuBoardViewState();
}

class _GomokuBoardViewState extends State<GomokuBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final board = (v['board'] as List).cast<int>();
    final blackSeat = v['blackSeat'] as int;
    final turn = v['turn'] as int;
    final last = v['last'] as int;
    final moves = v['moves'] as int;
    final winner = v['winner'] as int;
    final rule = v['rule'] as String;
    final forbidden = (v['forbidden'] as List).cast<int>().toSet();
    final forbiddenAt = v['forbiddenAt'] as int;
    final winLine = (v['winLine'] as List).cast<int>().toSet();
    final result = v['result'] as String;
    final over = v['over'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = !player ? 0 : (me == blackSeat ? 1 : 2);
    final myTurn = !over && turn == me;
    String colorName(int s) => s == blackSeat ? '黑' : '白';
    const ruleName = {'free': '自由规则', 'standard': '标准规则（恰好五连）', 'renju': '连珠禁手'};

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      status = '轮到你落子（${colorName(me)}）${forbidden.isNotEmpty && myColor == 1 ? ' · 红叉为禁手点' : ''}';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: s == blackSeat ? '执黑先行' : '执白',
        trailing: StoneDot(s == blackSeat ? kBlackStone : kWhiteStone));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / (n + 1);
      int pointAt(Offset o) {
        final x = (o.dx / cell - 1).round(), y = (o.dy / cell - 1).round();
        if (x < 0 || y < 0 || x >= n || y >= n) return -1;
        return y * n + x;
      }

      return Container(
        decoration: woodDecoration(radius: 6),
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
              if (myColor == 1 && forbidden.contains(p)) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
                    content: Text('这是禁手点，落子即判负'), duration: Duration(seconds: 2)));
              }
              g.act({'type': 'play', 'point': p});
            },
            child: CustomPaint(
              size: Size(side, side),
              painter: _GomokuPainter(
                n: n,
                board: board,
                last: last,
                hover: myTurn ? hover : -1,
                hoverColor: myColor,
                winLine: winLine,
                forbidden: forbidden,
                forbiddenAt: forbiddenAt,
                showForbidden: !over && rule == 'renju' && turn == blackSeat,
              ),
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
        '$n 路 · ${ruleName[rule]} · 第 $moves 手',
        if (rule == 'renju') '黑棋禁手：三三、四四、长连（落子即负）',
      ]),
      result: banner,
    );
  }
}
