import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'sg_shell.dart';

// piece codes follow the engine: 1 步 2 香 3 桂 4 银 5 金 6 角 7 飞 8 玉; +8 = promoted
const _kanji = ['', '歩', '香', '桂', '銀', '金', '角', '飛', '玉', 'と', '杏', '圭', '全', '', '馬', '龍'];
const _scale = [0.0, 0.84, 0.88, 0.9, 0.94, 0.94, 0.98, 0.98, 1.0, 0.84, 0.88, 0.9, 0.94, 0, 0.98, 0.98];
const _cnNames = ['', '步', '香车', '桂马', '银将', '金将', '角行', '飞车', '玉将', 'と金', '成香', '成桂', '成银', '', '龙马', '龙王'];

/// Pentagon shogi piece (koma). [up] = points towards the top of the screen.
class KomaPainter extends CustomPainter {
  final int type; // unsigned 1..15
  final bool up;
  final bool gote; // 王 instead of 玉
  final bool selected;
  KomaPainter(this.type, {required this.up, this.gote = false, this.selected = false});

  @override
  void paint(Canvas canvas, Size size) {
    final s = _scale[type];
    final w = size.width * s, h = size.height * s;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    if (!up) canvas.rotate(pi);
    // unit pentagon, centred
    Offset p(double x, double y) => Offset((x - 0.5) * w, (y - 0.5) * h);
    final path = Path()
      ..moveTo(p(0.5, 0.0).dx, p(0.5, 0.0).dy)
      ..lineTo(p(0.86, 0.17).dx, p(0.86, 0.17).dy)
      ..lineTo(p(0.97, 1.0).dx, p(0.97, 1.0).dy)
      ..lineTo(p(0.03, 1.0).dx, p(0.03, 1.0).dy)
      ..lineTo(p(0.14, 0.17).dx, p(0.14, 0.17).dy)
      ..close();
    canvas.drawShadow(path, Colors.black, selected ? 5 : 2, false);
    final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFCE9BE), Color(0xFFEBC98A), Color(0xFFD9AE68)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? max(2.0, w * 0.07) : max(0.8, w * 0.025)
        ..color = selected ? const Color(0xFF2E7D32) : const Color(0xFF7A5428),
    );
    final promoted = type > 8;
    final label = type == 8 && gote ? '王' : _kanji[type];
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: kFontFallback.first,
          fontFamilyFallback: kFontFallback,
          fontSize: w * 0.56,
          height: 1.0,
          fontWeight: FontWeight.w900,
          color: promoted ? const Color(0xFFC62828) : const Color(0xFF1B1B1B),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, h * 0.08 - tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant KomaPainter o) => o.type != type || o.up != up || o.selected != selected || o.gote != gote;
}

class Koma extends StatelessWidget {
  final int type;
  final bool up;
  final bool gote;
  final bool selected;
  final double size;
  const Koma(this.type, {super.key, required this.up, this.gote = false, this.selected = false, required this.size});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: KomaPainter(type, up: up, gote: gote, selected: selected)),
      );
}

class _GridPainter extends CustomPainter {
  final double cell;
  final Offset origin;
  final bool flipped;
  _GridPainter(this.cell, this.origin, this.flipped);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF4A3218)
      ..strokeWidth = max(1.0, cell * 0.025);
    for (var i = 0; i <= 9; i++) {
      canvas.drawLine(origin + Offset(0, i * cell), origin + Offset(9 * cell, i * cell), line);
      canvas.drawLine(origin + Offset(i * cell, 0), origin + Offset(i * cell, 9 * cell), line);
    }
    canvas.drawRect(
      Rect.fromLTWH(origin.dx, origin.dy, 9 * cell, 9 * cell),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xFF4A3218)
        ..strokeWidth = max(2.0, cell * 0.05),
    );
    final dot = Paint()..color = const Color(0xFF4A3218);
    for (final x in const [3, 6]) {
      for (final y in const [3, 6]) {
        canvas.drawCircle(origin + Offset(x * cell, y * cell), max(2.0, cell * 0.06), dot);
      }
    }
    void txt(String s, Offset c) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: kFontFallback.first, fontFamilyFallback: kFontFallback, fontSize: cell * 0.28, color: const Color(0xFF5B3A1A), fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }

    const ranks = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
    for (var i = 0; i < 9; i++) {
      final file = flipped ? i + 1 : 9 - i;
      txt('$file', origin + Offset((i + 0.5) * cell, -cell * 0.22));
      txt(ranks[flipped ? 8 - i : i], origin + Offset(9 * cell + cell * 0.25, (i + 0.5) * cell));
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter o) => o.cell != cell || o.flipped != flipped || o.origin != origin;
}

class ShogiBoard extends StatefulWidget {
  final GameContext g;
  const ShogiBoard(this.g, {super.key});
  @override
  State<ShogiBoard> createState() => _ShogiBoardState();
}

class _ShogiBoardState extends State<ShogiBoard> {
  int? sel; // board square 0..80, or 81 + piece type for a hand piece
  int _plies = -1;
  GameContext get g => widget.g;

  Future<void> _promoteDialog(int from, int to, int type, bool up) async {
    final r = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('是否升变？'),
        content: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final pr in const [true, false])
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(ctx, pr),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Koma(pr ? type + 8 : type, up: true, size: 56),
                  const SizedBox(height: 4),
                  Text(pr ? '升变（${_cnNames[type + 8]}）' : '不升变'),
                ]),
              ),
            ),
        ]),
      ),
    );
    if (r == null || !mounted) return;
    g.act({'type': 'move', 'from': from, 'to': to, 'promote': r});
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final board = (v['board'] as List).cast<int>();
    final hands = (v['hands'] as List).map((e) => (e as List).cast<int>()).toList();
    final senteSeat = v['senteSeat'] as int;
    final turn = v['turn'] as int;
    final moves = (v['moves'] as List).cast<int>();
    final last = (v['last'] as List).cast<int>();
    final check = v['check'] as int?;
    final notation = (v['notation'] as List).cast<String>();
    final winner = v['winner'] as int;
    final reason = v['reason'] as String;
    final plies = v['plies'] as int;
    final handicap = v['handicap'] as int? ?? 0;
    if (plies != _plies) {
      _plies = plies;
      sel = null;
    }
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = player && me != senteSeat ? -1 : 1;
    final flipped = myColor < 0;
    final myTurn = !g.over && player && turn == me;
    final bottomSeat = player ? me : senteSeat;
    final topSeat = 1 - bottomSeat;
    String colorName(int s) {
      if (handicap > 0) return s == senteSeat ? '下手 ☗' : '上手 ☖';
      return s == senteSeat ? '先手 ☗' : '后手 ☖';
    }

    String status;
    if (winner == -1) {
      status = '和棋：$reason';
    } else if (winner >= 0) {
      status = '${g.name(winner)} 获胜（$reason）';
    } else if (myTurn) {
      status = check != null ? '王手！请应将' : '轮到你走棋（${colorName(me)}）';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）${check != null ? ' · 王手' : ''}';
    }
    final offer = v['drawOffer'] as int? ?? -1;
    if (!g.over && offer >= 0 && offer != me) status = '${g.name(offer)} 提议和棋';

    // targets: to -> flag (0 不成, 1 必成, 2 可选)
    final targets = <int, int>{};
    if (sel != null) {
      for (final m in moves) {
        if (m ~/ 1000 == sel) targets[(m % 1000) ~/ 10] = m % 10;
      }
    }
    final movable = <int>{for (final m in moves) m ~/ 1000};

    void tapSquare(int s) {
      if (!myTurn) return;
      final p = board[s];
      if (sel != null && targets.containsKey(s)) {
        final from = sel!;
        final flag = targets[s]!;
        setState(() => sel = null);
        if (from >= 81) {
          g.act({'type': 'drop', 'piece': from - 81, 'to': s});
        } else if (flag == 2) {
          _promoteDialog(from, s, board[from].abs(), true);
        } else {
          g.act({'type': 'move', 'from': from, 'to': s, 'promote': flag == 1});
        }
        return;
      }
      final mine = p != 0 && (p > 0) == (myColor > 0);
      setState(() => sel = mine && sel != s && movable.contains(s) ? s : null);
    }

    void tapHand(int type) {
      if (!myTurn) return;
      setState(() => sel = sel == 81 + type || !movable.contains(81 + type) ? null : 81 + type);
    }

    Widget tagFor(int s) => g.tag(s, active: !g.over && turn == s, sub: colorName(s));

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final cell = c.maxWidth / 9.7;
      final standH = cell * 1.35;
      final origin = Offset(cell * 0.15, standH + cell * 0.55);
      Offset posOf(int s) {
        final r = s ~/ 9, col = s % 9;
        final vr = flipped ? 8 - r : r, vc = flipped ? 8 - col : col;
        return origin + Offset(vc * cell, vr * cell);
      }

      Widget stand(int color, bool bottom) {
        final hand = hands[color > 0 ? 0 : 1];
        final mineStand = player && color == myColor;
        final items = <Widget>[];
        for (var t = 7; t >= 1; t--) {
          final n = hand[t];
          if (n == 0) continue;
          final selected = mineStand && sel == 81 + t;
          items.add(GestureDetector(
            onTap: mineStand ? () => tapHand(t) : null,
            child: SizedBox(
              width: cell * 1.1,
              height: cell * 1.1,
              child: Stack(clipBehavior: Clip.none, children: [
                Center(child: Koma(t, up: bottom, selected: selected, size: cell * 0.95)),
                if (n > 1)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: cell * 0.08),
                      decoration: BoxDecoration(color: const Color(0xFF8E1B1B), borderRadius: BorderRadius.circular(cell)),
                      child: Text('$n', style: TextStyle(color: Colors.white, fontSize: cell * 0.3, fontWeight: FontWeight.bold, height: 1.2)),
                    ),
                  ),
              ]),
            ),
          ));
        }
        return Container(
          height: standH,
          padding: EdgeInsets.symmetric(horizontal: cell * 0.2),
          decoration: BoxDecoration(
            color: const Color(0xFFB98A4E),
            borderRadius: BorderRadius.circular(cell * 0.2),
            border: Border.all(color: const Color(0xFF6E4B22), width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Row(
            mainAxisAlignment: bottom ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: items.isEmpty
                ? [Expanded(child: Center(child: Text('驹台', style: TextStyle(color: const Color(0xFF6E4B22), fontSize: cell * 0.32))))]
                : items,
          ),
        );
      }

      final boardH = cell * 9.9;
      return Stack(children: [
        Positioned(left: 0, right: 0, top: 0, child: stand(-myColor, false)),
        Positioned(left: 0, right: 0, bottom: 0, child: stand(myColor, true)),
        Positioned(
          left: 0,
          right: 0,
          top: standH + cell * 0.1,
          height: boardH,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF3D69C), Color(0xFFE4BA72), Color(0xFFEFCB88)],
              ),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))],
            ),
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GridPainter(cell, origin, flipped)))),
        for (final s in last)
          Positioned(
            left: posOf(s).dx,
            top: posOf(s).dy,
            width: cell,
            height: cell,
            child: IgnorePointer(child: ColoredBox(color: Colors.orange.withValues(alpha: 0.3))),
          ),
        if (sel != null && sel! < 81)
          Positioned(
            left: posOf(sel!).dx,
            top: posOf(sel!).dy,
            width: cell,
            height: cell,
            child: IgnorePointer(child: ColoredBox(color: Colors.green.withValues(alpha: 0.25))),
          ),
        for (var s = 0; s < 81; s++)
          Positioned(
            left: posOf(s).dx,
            top: posOf(s).dy,
            width: cell,
            height: cell,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapSquare(s),
              child: Stack(alignment: Alignment.center, children: [
                if (check == s)
                  Container(
                    decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.85), blurRadius: cell * 0.3, spreadRadius: -cell * 0.05)]),
                  ),
                if (board[s] != 0)
                  Koma(board[s].abs(),
                      up: (board[s] > 0) != flipped, gote: board[s] < 0, selected: sel == s, size: cell * 0.92),
                if (targets.containsKey(s))
                  board[s] == 0
                      ? Container(
                          width: cell * 0.26,
                          height: cell * 0.26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.green.shade700.withValues(alpha: 0.75),
                            border: Border.all(color: Colors.white70, width: 1.5),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.green.shade700, width: max(2.0, cell * 0.07))),
                        ),
              ]),
            ),
          ),
      ]);
    });

    return SgShell(
      topTag: tagFor(topSeat),
      bottomTag: tagFor(bottomSeat),
      status: status,
      statusHighlight: myTurn || (offer >= 0 && offer != me && !g.over),
      aspect: 9.7 / (9.9 + 2 * 1.35 + 0.2),
      board: boardWidget,
      actions: sgResignDraw(context, g),
      extra: SgMoveList(notation),
      result: g.over ? (winner == -1 ? '和棋 · $reason' : (winner == me ? '你赢了！' : '${g.name(winner)} 获胜')) : null,
    );
  }
}
