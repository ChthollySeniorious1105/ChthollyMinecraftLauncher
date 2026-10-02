import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'shell.dart';

List<int> _stars(int n) {
  final d = n >= 13 ? 3 : 2;
  final lo = d, hi = n - 1 - d, mid = n ~/ 2;
  final pts = <int>[lo * n + lo, lo * n + hi, hi * n + lo, hi * n + hi, mid * n + mid];
  if (n == 19) pts.addAll([lo * n + mid, hi * n + mid, mid * n + lo, mid * n + hi]);
  return pts;
}

class _GoPainter extends CustomPainter {
  final int n;
  final List<int> board;
  final int last;
  final int hover;
  final int hoverColor;
  final Set<int> dead;
  final List<int> owner;
  final bool showOwner;

  _GoPainter({
    required this.n,
    required this.board,
    required this.last,
    required this.hover,
    required this.hoverColor,
    required this.dead,
    required this.owner,
    required this.showOwner,
  });

  static const letters = 'ABCDEFGHJKLMNOPQRST';

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / (n + 1);
    Offset pt(int p) => Offset((p % n + 1) * cell, (p ~/ n + 1) * cell);
    final line = Paint()
      ..color = const Color(0xFF3B2A14)
      ..strokeWidth = max(0.8, cell * 0.035);
    for (var i = 0; i < n; i++) {
      canvas.drawLine(Offset(cell, (i + 1) * cell), Offset(n * cell, (i + 1) * cell), line);
      canvas.drawLine(Offset((i + 1) * cell, cell), Offset((i + 1) * cell, n * cell), line);
    }
    final border = Paint()
      ..color = const Color(0xFF3B2A14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, cell * 0.07);
    canvas.drawRect(Rect.fromLTRB(cell, cell, n * cell, n * cell), border);
    final star = Paint()..color = const Color(0xFF3B2A14);
    for (final s in _stars(n)) {
      canvas.drawCircle(pt(s), max(2, cell * 0.11), star);
    }
    // coordinates
    final fs = cell * 0.36;
    for (var i = 0; i < n; i++) {
      void t(String s, Offset c) {
        final tp = TextPainter(
          text: TextSpan(text: s, style: TextStyle(fontFamilyFallback: kFontFallback, fontSize: fs, color: const Color(0xFF5A4020), fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }

      t(letters[i], Offset((i + 1) * cell, cell * 0.45));
      t(letters[i], Offset((i + 1) * cell, (n + 0.55) * cell));
      t('${n - i}', Offset(cell * 0.42, (i + 1) * cell));
      t('${n - i}', Offset((n + 0.58) * cell, (i + 1) * cell));
    }
    final r = cell * 0.47;
    // stones
    for (var p = 0; p < n * n; p++) {
      final c = board[p];
      if (c == 0) continue;
      _stone(canvas, pt(p), r, c, dead.contains(p) ? 0.4 : 1.0);
    }
    // hover ghost
    if (hover >= 0 && hover < board.length && board[hover] == 0 && hoverColor > 0) {
      _stone(canvas, pt(hover), r, hoverColor, 0.45, shadow: false);
    }
    // territory
    if (showOwner && owner.length == n * n) {
      for (var p = 0; p < n * n; p++) {
        final o = owner[p];
        if (o == 0) continue;
        if (board[p] != 0 && !dead.contains(p)) continue;
        final paint = Paint()..color = o == 1 ? const Color(0xE0101010) : const Color(0xF0F8F8F8);
        final h = cell * 0.18;
        final rect = Rect.fromCenter(center: pt(p), width: h * 2, height: h * 2);
        canvas.drawRect(rect, paint);
        canvas.drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8
              ..color = o == 1 ? Colors.white54 : Colors.black54);
      }
    }
    // last move marker
    if (last >= 0 && last < board.length && board[last] != 0) {
      canvas.drawCircle(
          pt(last),
          r * 0.42,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, cell * 0.07)
            ..color = board[last] == 1 ? Colors.white : Colors.black);
    }
  }

  void _stone(Canvas canvas, Offset c, double r, int color, double opacity, {bool shadow = true}) {
    if (shadow) {
      canvas.drawCircle(
          c + Offset(r * 0.12, r * 0.18),
          r,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.35 * opacity)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.15));
    }
    final rect = Rect.fromCircle(center: c, radius: r);
    final colors = color == 1
        ? [const Color(0xFF5E5E5E), const Color(0xFF1A1A1A), const Color(0xFF050505)]
        : [const Color(0xFFFFFFFF), const Color(0xFFEDEDE6), const Color(0xFFC4C4BC)];
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 1.0,
        colors: [for (final k in colors) k.withValues(alpha: opacity)],
        stops: const [0, 0.55, 1],
      ).createShader(rect);
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _GoPainter o) => true;
}

class GoBoardView extends StatefulWidget {
  final GameContext g;
  const GoBoardView(this.g, {super.key});
  @override
  State<GoBoardView> createState() => _GoBoardViewState();
}

class _GoBoardViewState extends State<GoBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  static String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final board = (v['board'] as List).cast<int>();
    final blackSeat = v['blackSeat'] as int;
    final turn = v['turn'] as int;
    final phase = v['phase'] as String;
    final last = v['last'] as int;
    final caps = (v['caps'] as List).cast<int>();
    final komi = (v['komi'] as num).toDouble();
    final dead = (v['dead'] as List).cast<int>().toSet();
    final owner = (v['owner'] as List).cast<int>();
    final score = (v['score'] as List).cast<num>();
    final confirmed = (v['confirmed'] as List).cast<bool>();
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final moveCount = v['moveCount'] as int;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = !player ? 0 : (me == blackSeat ? 1 : 2);
    final myTurn = phase == 'play' && turn == me;
    final bottomSeat = player ? me : blackSeat;
    final topSeat = 1 - bottomSeat;
    String colorName(int s) => s == blackSeat ? '黑' : '白';

    String status;
    if (phase == 'over') {
      status = result;
    } else if (phase == 'scoring') {
      status = '数子阶段：黑 ${_fmt(score[0])} · 白 ${_fmt(score[1])}（含贴目）  点击棋子标记/取消死子';
    } else if (myTurn) {
      status = last == -2 ? '对方停了一手，轮到你（${colorName(me)}）' : '轮到你落子（${colorName(me)}）';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）${last == -2 ? ' · 对方已停一手' : ''}';
    }

    Widget tagFor(int s) {
      final c = s == blackSeat ? 1 : 2;
      final stone = Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: c == 1 ? const [Color(0xFF666666), Colors.black] : const [Colors.white, Color(0xFFC8C8C0)],
          ),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1))],
        ),
      );
      final extra = phase == 'scoring' ? (confirmed[s] ? ' · 已确认' : ' · 待确认') : '';
      return g.tag(s,
          active: (phase == 'play' && turn == s) || (phase == 'scoring' && !confirmed[s]),
          sub: '${c == 1 ? '黑' : '白 贴${_fmt(komi)}'} · 提子 ${caps[c - 1]}$extra',
          trailing: stone);
    }

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth;
      final cell = side / (n + 1);
      int pointAt(Offset o) {
        final x = (o.dx / cell - 1).round(), y = (o.dy / cell - 1).round();
        if (x < 0 || y < 0 || x >= n || y >= n) return -1;
        return y * n + x;
      }

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8BF73), Color(0xFFD9A551), Color(0xFFE3B464)],
          ),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
        ),
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
              if (p < 0) return;
              if (myTurn && board[p] == 0) {
                g.act({'type': 'play', 'point': p});
              } else if (phase == 'scoring' && player && board[p] != 0) {
                g.act({'type': 'toggle', 'point': p});
              }
            },
            child: CustomPaint(
              size: Size(side, side),
              painter: _GoPainter(
                n: n,
                board: board,
                last: last,
                hover: myTurn ? hover : -1,
                hoverColor: myColor,
                dead: dead,
                owner: owner,
                showOwner: phase != 'play',
              ),
            ),
          ),
        ),
      );
    });

    final actions = <Widget>[];
    if (player && phase == 'play') {
      actions.add(shellButton(context, '停一手', Icons.pan_tool_alt, myTurn ? () => g.act({'type': 'pass'}) : null));
      actions.add(shellButton(context, '认输', Icons.flag, () async {
        if (await confirmDialog(context, '认输', '确定要认输吗？')) g.act({'type': 'resign'});
      }));
    } else if (player && phase == 'scoring') {
      actions.add(shellButton(context, confirmed[me] ? '已确认' : '确认结果', Icons.check,
          confirmed[me] ? null : () => g.act({'type': 'confirm'}), primary: true));
      actions.add(shellButton(context, '继续对局', Icons.replay, () => g.act({'type': 'resume'})));
    }

    final info = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        child: Text(
          [
            '$n 路 · 贴 ${_fmt(komi)} 目 · 第 $moveCount 手',
            if (phase != 'play') '黑 ${_fmt(score[0])} 子 / 白 ${_fmt(score[1])} 子',
            if (phase == 'scoring') '半透明棋子为死子，方块为目',
          ].join('\n'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );

    String? banner;
    if (phase == 'over') {
      banner = winner == -1 ? '和棋' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜');
    }

    return BoardShell(
      topTag: tagFor(topSeat),
      bottomTag: tagFor(bottomSeat),
      status: status,
      statusHighlight: myTurn || (phase == 'scoring' && player && !confirmed[me]),
      board: boardWidget,
      actions: actions,
      extra: info,
      result: banner,
    );
  }
}
