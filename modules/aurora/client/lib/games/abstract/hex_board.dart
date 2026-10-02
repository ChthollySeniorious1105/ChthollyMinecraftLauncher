import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

/// 菱形六角格布局：格 (r, c) 中心 x = (c + r/2) * w，y = r * 1.5 * s。
class _HGeo {
  final int n;
  final double s; // 六边形外接圆半径
  _HGeo(this.n, this.s);

  double get w => sqrt(3) * s;
  static double widthUnits(int n) => sqrt(3) * (n + (n - 1) / 2) + 2.2;
  static double heightUnits(int n) => 1.5 * (n - 1) + 2 + 2.2;
  Offset get origin => Offset(1.1 * s + w / 2, 1.1 * s + s);

  Offset center(int p) {
    final r = p ~/ n, c = p % n;
    return origin + Offset((c + r / 2) * w, r * 1.5 * s);
  }

  Path hexPath(Offset c, double rad) {
    final p = Path();
    for (var k = 0; k < 6; k++) {
      final a = pi / 180 * (60 * k - 30);
      final o = c + Offset(cos(a) * rad, sin(a) * rad);
      if (k == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }

  int hit(Offset o) {
    var best = -1;
    var bd = double.infinity;
    for (var p = 0; p < n * n; p++) {
      final d = (center(p) - o).distance;
      if (d < bd) {
        bd = d;
        best = p;
      }
    }
    return bd <= w / 2 * 1.05 ? best : -1;
  }
}

class _HexPainter extends CustomPainter {
  final _HGeo geo;
  final List<int> board;
  final int last, hover, hoverColor;
  final Set<int> path;
  final Color bg;

  _HexPainter(this.geo, this.board, this.last, this.hover, this.hoverColor, this.path, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final n = geo.n, s = geo.s;
    // 边框：红方上下，蓝方左右
    final tl = geo.center(0), tr = geo.center(n - 1), bl = geo.center((n - 1) * n), br = geo.center(n * n - 1);
    final m = s * 1.25;
    final cTL = tl + Offset(-geo.w * 0.9, -m), cTR = tr + Offset(geo.w * 0.4, -m);
    final cBL = bl + Offset(-geo.w * 0.4, m), cBR = br + Offset(geo.w * 0.9, m);
    final mid = (cTL + cBR) / 2;
    Path tri(Offset a, Offset b) => Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(mid.dx, mid.dy)
      ..close();
    canvas.drawPath(tri(cTL, cTR), Paint()..color = kAbsRed);
    canvas.drawPath(tri(cBL, cBR), Paint()..color = kAbsRed);
    canvas.drawPath(tri(cTL, cBL), Paint()..color = kAbsBlue);
    canvas.drawPath(tri(cTR, cBR), Paint()..color = kAbsBlue);
    final cellBase = Color.lerp(const Color(0xFFEFE3C8), bg, 0.12)!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, s * 0.07)
      ..color = const Color(0xFF5D4630);
    for (var p = 0; p < n * n; p++) {
      final c = geo.center(p);
      final hp = geo.hexPath(c, s * 0.99);
      canvas.drawPath(hp, Paint()..color = path.contains(p) ? const Color(0xFFFFF59D) : cellBase);
      canvas.drawPath(hp, stroke);
      final v = board[p];
      if (v != 0) {
        absStone(canvas, c, s * 0.68, v == 1 ? kAbsRed : kAbsBlue, shadow: s > 6);
      } else if (p == hover && hoverColor > 0) {
        absStone(canvas, c, s * 0.68, hoverColor == 1 ? kAbsRed : kAbsBlue, opacity: 0.4, shadow: false);
      }
      if (p == last && v != 0) {
        canvas.drawCircle(c, s * 0.22, Paint()..color = Colors.white.withValues(alpha: 0.9));
      }
    }
    // 坐标
    const letters = 'ABCDEFGHIJKLM';
    final fs = s * 0.6;
    for (var i = 0; i < n; i++) {
      absTextAt(canvas, letters[i], geo.center(i) + Offset(0, -s * 1.55), fs, Colors.white);
      absTextAt(canvas, '${i + 1}', geo.center(i * n) + Offset(-geo.w * 0.95, 0), fs, Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _HexPainter o) => true;
}

class HexBoardView extends StatefulWidget {
  final GameContext g;
  const HexBoardView(this.g, {super.key});
  @override
  State<HexBoardView> createState() => _HexBoardViewState();
}

class _HexBoardViewState extends State<HexBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final n = v['size'] as int;
    final board = (v['board'] as List).cast<int>();
    final redSeat = v['redSeat'] as int;
    final turn = v['turn'] as int;
    final over = v['over'] as bool;
    final canSwap = v['canSwap'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final myColor = !player ? 0 : (me == redSeat ? 1 : 2);
    final myTurn = !over && turn == me;
    String colorName(int s) => s == redSeat ? '红' : '蓝';
    String goal(int s) => s == redSeat ? '连接上下' : '连接左右';

    String status;
    if (over) {
      status = v['result'] as String? ?? '对局结束';
    } else if (myTurn) {
      status = canSwap ? '轮到你：落子，或选择“交换”改执红方' : '轮到你（${colorName(me)}，${goal(me)}）';
    } else {
      status = '等待 ${g.name(turn)}（${colorName(turn)}）落子';
    }

    Widget tagFor(int s) => g.tag(s,
        active: !over && turn == s,
        sub: '${colorName(s)}方 · ${goal(s)}${s == redSeat ? ' · 先行' : ''}',
        trailing: AbsDot(s == redSeat ? kAbsRed : kAbsBlue));

    final wU = _HGeo.widthUnits(n), hU = _HGeo.heightUnits(n);
    final boardWidget = LayoutBuilder(builder: (context, c) {
      final s = c.maxWidth / wU;
      final geo = _HGeo(n, s);
      return MouseRegion(
        onHover: (e) {
          final p = myTurn ? geo.hit(e.localPosition) : -1;
          if (p != hover) setState(() => hover = p);
        },
        onExit: (_) => setState(() => hover = -1),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final p = geo.hit(d.localPosition);
            if (p < 0 || !myTurn || board[p] != 0) return;
            g.act({'type': 'play', 'point': p});
          },
          child: CustomPaint(
            size: Size(c.maxWidth, s * hU),
            painter: _HexPainter(geo, board, v['last'] as int, myTurn ? hover : -1, myColor,
                (v['winPath'] as List).cast<int>().toSet(), g.table),
          ),
        ),
      );
    });

    final bottom = player ? me : redSeat;
    return AbsShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      aspect: wU / hU,
      board: boardWidget,
      actions: [
        if (myTurn && canSwap) absButton(context, '交换', Icons.swap_horiz, () => g.act({'type': 'swap'}), primary: true),
        ?absResign(context, g),
      ],
      info: [
        '$n×$n · 红方连接上下两条红边，蓝方连接左右两条蓝边 · 第 ${v['moves']} 手',
        if (v['swapRule'] == true) v['swapped'] == true ? '后手已使用交换规则' : '交换规则：红方第一手后，蓝方可选择交换颜色',
      ],
      result: absBanner(g, v),
    );
  }
}
