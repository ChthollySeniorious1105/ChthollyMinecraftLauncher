import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p2_common.dart';

const _fruitNames = ['草莓', '香蕉', '青柠', '李子'];
const _fruitColors = [Color(0xFFE53935), Color(0xFFFDD835), Color(0xFF7CB342), Color(0xFF8E24AA)];

/// A Halli Galli fruit card (code = fruit*10 + count), drawn by hand.
class HgCard extends StatelessWidget {
  final int? code;
  final double width;
  final bool hot;
  const HgCard(this.code, {super.key, this.width = 70, this.hot = false});
  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    if (code == null) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: Colors.white38, width: 1.5),
          color: Colors.black12,
        ),
      );
    }
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(width * 0.12),
        border: Border.all(color: hot ? Colors.orangeAccent : const Color(0xFFBDB39A), width: hot ? 3 : 1.5),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38, offset: Offset(1, 2))],
      ),
      child: CustomPaint(painter: _FruitPainter(code! ~/ 10, code! % 10)),
    );
  }
}

class _FruitPainter extends CustomPainter {
  final int fruit, count;
  _FruitPainter(this.fruit, this.count);

  static const _layouts = <List<Offset>>[
    [Offset(0.5, 0.5)],
    [Offset(0.5, 0.28), Offset(0.5, 0.72)],
    [Offset(0.5, 0.2), Offset(0.5, 0.5), Offset(0.5, 0.8)],
    [Offset(0.3, 0.28), Offset(0.7, 0.28), Offset(0.3, 0.72), Offset(0.7, 0.72)],
    [Offset(0.3, 0.22), Offset(0.7, 0.22), Offset(0.5, 0.5), Offset(0.3, 0.78), Offset(0.7, 0.78)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * (count >= 4 ? 0.15 : 0.18);
    for (final o in _layouts[(count - 1).clamp(0, 4)]) {
      _fruit(canvas, Offset(o.dx * size.width, o.dy * size.height), r);
    }
  }

  void _fruit(Canvas c, Offset p, double r) {
    final col = _fruitColors[fruit];
    final paint = Paint()..color = col;
    final dark = Paint()..color = Color.lerp(col, Colors.black, 0.35)!;
    final leaf = Paint()..color = const Color(0xFF2E7D32);
    switch (fruit) {
      case 0: // strawberry
        final path = Path()
          ..moveTo(p.dx - r, p.dy - r * 0.4)
          ..quadraticBezierTo(p.dx, p.dy - r * 1.1, p.dx + r, p.dy - r * 0.4)
          ..quadraticBezierTo(p.dx + r * 0.8, p.dy + r * 0.6, p.dx, p.dy + r * 1.1)
          ..quadraticBezierTo(p.dx - r * 0.8, p.dy + r * 0.6, p.dx - r, p.dy - r * 0.4);
        c.drawPath(path, paint);
        final seed = Paint()..color = const Color(0xFFFFF59D);
        for (final d in const [Offset(-0.4, -0.1), Offset(0.35, -0.05), Offset(0, 0.35), Offset(-0.15, 0.7), Offset(0.2, 0.7), Offset(0, -0.35)]) {
          c.drawCircle(p + Offset(d.dx * r, d.dy * r), r * 0.08, seed);
        }
        c.drawOval(Rect.fromCenter(center: p + Offset(0, -r * 0.75), width: r * 1.2, height: r * 0.4), leaf);
      case 1: // banana
        final path = Path()
          ..moveTo(p.dx - r, p.dy - r * 0.6)
          ..quadraticBezierTo(p.dx - r * 0.2, p.dy + r * 1.3, p.dx + r, p.dy - r * 0.3)
          ..quadraticBezierTo(p.dx - r * 0.1, p.dy + r * 0.5, p.dx - r, p.dy - r * 0.6);
        c.drawPath(path, paint);
        c.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08
          ..color = const Color(0xFFB08C00));
        c.drawCircle(p + Offset(-r, -r * 0.6), r * 0.1, dark);
      case 2: // lime
        c.drawCircle(p, r, paint);
        c.drawCircle(p, r * 0.8, Paint()..color = const Color(0xFFDCEDC8));
        final seg = Paint()
          ..color = const Color(0xFF9CCC65)
          ..strokeWidth = r * 0.08;
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          c.drawLine(p, p + Offset(math.cos(a) * r * 0.8, math.sin(a) * r * 0.8), seg);
        }
      default: // plum
        c.drawCircle(p, r, paint);
        c.drawCircle(p + Offset(-r * 0.35, -r * 0.35), r * 0.22, Paint()..color = Colors.white30);
        c.drawLine(p + Offset(0, -r), p + Offset(r * 0.2, -r * 1.35), Paint()
          ..color = const Color(0xFF5D4037)
          ..strokeWidth = r * 0.12);
        c.drawOval(Rect.fromCenter(center: p + Offset(r * 0.5, -r * 1.2), width: r * 0.6, height: r * 0.3), leaf);
    }
  }

  @override
  bool shouldRepaint(_FruitPainter old) => old.fruit != fruit || old.count != count;
}

class HalliGalliBoard extends StatelessWidget {
  final GameContext g;
  const HalliGalliBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final over = v['phase'] == 'over';
    final turn = p2Int(v['turn']);
    final down = p2Ints(v['down']);
    final upN = p2Ints(v['upCount']);
    final top = (v['top'] as List? ?? const []);
    final alive = p2Bools(v['alive']);
    final me = g.seat;
    final meAlive = me >= 0 && me < alive.length && alive[me];
    final last = p2Map(v['last']);
    final totals = [0, 0, 0, 0];
    for (final c in top) {
      if (c is num) totals[c.toInt() ~/ 10] += c.toInt() % 10;
    }

    String status;
    if (over) {
      status = '游戏结束';
    } else if (turn == me) {
      status = '轮到你翻牌！看到某种水果恰好 5 个就拍铃';
    } else {
      status = '${g.name(turn)} 翻牌中…  （翻牌 ${v['flips']}/${v['maxFlips']}）';
    }
    String? lastText;
    if (last != null) {
      final s = p2Int(last['s']);
      lastText = switch (last['k']) {
        'win' => '${g.name(s)} 拍铃成功！${_fruitNames[p2Int(last['f'], 0)]}恰好 5 个，收走 ${last['n']} 张',
        'wrong' => '${g.name(s)} 拍错了铃，罚给每人 1 张',
        _ => null,
      };
    }

    return LayoutBuilder(builder: (context, box) {
      final n = g.players;
      final narrow = box.maxWidth < 600;
      final cols = narrow ? (n <= 4 ? 2 : 3) : (n <= 3 ? n : (n <= 4 ? 4 : 3));
      final rows = (n / cols).ceil();
      final bellH = math.min(box.maxHeight * 0.26, 150.0);
      final gridH = box.maxHeight - bellH - 90;
      final cellW = (box.maxWidth - 16) / cols - 10;
      final cellH = gridH / rows - 10;
      final cardW = math.max(26.0, math.min(cellW * 0.42, (cellH - 40) / 1.4)).clamp(26.0, 90.0);

      Widget seatCell(int s) {
        final c = s < top.length && top[s] is num ? (top[s] as num).toInt() : null;
        final hot = c != null && totals[c ~/ 10] == 5;
        final isTurn = s == turn && !over;
        return Container(
          width: cellW,
          height: math.max(cellH, 10),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isTurn ? cs.primary.withValues(alpha: 0.22) : Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isTurn ? cs.primary : Colors.transparent, width: 2),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Opacity(
                opacity: s < alive.length && !alive[s] ? 0.4 : 1,
                child: g.tag(s, active: isTurn, size: 26, sub: '共 ${(s < down.length ? down[s] : 0) + (s < upN.length ? upN[s] : 0)} 张'),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _Pile(s < down.length ? down[s] : 0, cardW * 0.8),
                const SizedBox(width: 6),
                HgCard(c, width: cardW, hot: hot),
              ]),
            ]),
          ),
        );
      }

      final myTurn = !over && turn == me && me >= 0 && me < down.length && down[me] > 0;
      return Column(children: [
        p2Status(status, highlight: myTurn),
        if (lastText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: P2Chip(lastText, last!['k'] == 'win' ? Colors.green.shade700 : Colors.red.shade700, size: 12),
            ),
          ),
        Expanded(
          child: Center(
            child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (final s in g.seatsFromMe()) seatCell(s),
            ]),
          ),
        ),
        SizedBox(
          height: bellH,
          child: over
              ? SingleChildScrollView(
                  child: p2Ranking(g, '游戏结束', p2Maps(v['final']), (r) => '${r['cards']} 张'),
                )
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (me >= 0)
                    FilledButton.icon(
                      onPressed: myTurn ? () => g.act({'type': 'flip'}) : null,
                      icon: const Icon(Icons.flip),
                      label: const Text('翻牌'),
                    ),
                  const SizedBox(width: 20),
                  _Bell(size: bellH * 0.85, enabled: meAlive, onTap: () => g.act({'type': 'ring', 'ver': v['ver']})),
                ]),
        ),
        const SizedBox(height: 6),
      ]);
    });
  }
}

class _Pile extends StatelessWidget {
  final int n;
  final double w;
  const _Pile(this.n, this.w);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: w + 6,
      height: w * 1.4 + 6,
      child: Stack(children: [
        for (var i = 0; i < math.min(3, n); i++)
          Positioned(
            left: i * 2.0,
            top: i * 2.0,
            child: Container(
              width: w,
              height: w * 1.4,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.4)!]),
                borderRadius: BorderRadius.circular(w * 0.12),
                border: Border.all(color: Colors.white70, width: 1.2),
              ),
            ),
          ),
        Positioned.fill(
          child: Center(
            child: Text('$n', style: TextStyle(color: n == 0 ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold, fontSize: w * 0.32)),
          ),
        ),
      ]),
    );
  }
}

class _Bell extends StatelessWidget {
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  const _Bell({required this.size, required this.enabled, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: enabled ? (_) => onTap() : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: enabled ? const [Color(0xFFFFF59D), Color(0xFFFFC107), Color(0xFFB8860B)] : const [Colors.white54, Colors.grey, Colors.black45],
          ),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black45, offset: Offset(0, 4))],
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.notifications_active, size: size * 0.4, color: const Color(0xFF5D4037)),
                const Text('拍铃！', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
