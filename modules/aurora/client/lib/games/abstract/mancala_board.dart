import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const double _mW = 8.6, _mH = 3.4;

class _MGeo {
  final double u;
  final int bottom; // 下方座位
  _MGeo(this.u, this.bottom);

  /// 坑位中心与半径。
  (Offset, double, bool) pit(int i) {
    final low = bottom == 0 ? i <= 6 : i >= 7;
    if (i == 6 || i == 13) {
      // 仓：下方座位的仓在右侧
      final right = low;
      return (Offset(right ? (_mW - 0.62) * u : 0.62 * u, _mH / 2 * u), 0.45 * u, true);
    }
    final k = i % 7; // 0..5
    final col = low ? k : 5 - k;
    return (Offset((1.675 + col * 1.05) * u, (low ? _mH - 0.95 : 0.95) * u), 0.45 * u, false);
  }

  int hit(Offset o) {
    for (var i = 0; i < 14; i++) {
      if (i == 6 || i == 13) continue;
      final (c, r, _) = pit(i);
      if ((o - c).distance <= r * 1.1) return i;
    }
    return -1;
  }
}

const _gemColors = [
  Color(0xFFE57373),
  Color(0xFF64B5F6),
  Color(0xFF81C784),
  Color(0xFFFFD54F),
  Color(0xFFBA68C8),
  Color(0xFF4DD0E1),
  Color(0xFFFF8A65),
];

class _MancalaPainter extends CustomPainter {
  final _MGeo geo;
  final List<int> pits;
  final Set<int> legal;
  final int last, lastPit, hover;
  final bool captured;

  _MancalaPainter(this.geo, this.pits, this.legal, this.last, this.lastPit, this.hover, this.captured);

  @override
  void paint(Canvas canvas, Size size) {
    final u = geo.u;
    final full = Offset.zero & size;
    canvas.drawRRect(
        RRect.fromRectAndRadius(full.deflate(u * 0.05), Radius.circular(u * 0.6)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF9C6134), Color(0xFF7A4520), Color(0xFF8E552B)],
          ).createShader(full));
    // 木纹
    final grain = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.03;
    for (var k = 1; k < 9; k++) {
      final y = size.height * k / 9;
      canvas.drawPath(
          Path()
            ..moveTo(u * 0.4, y)
            ..cubicTo(size.width * 0.3, y - u * 0.12, size.width * 0.6, y + u * 0.12, size.width - u * 0.4, y),
          grain);
    }
    for (var i = 0; i < 14; i++) {
      final (c, r, store) = geo.pit(i);
      final rect = store
          ? Rect.fromCenter(center: c, width: r * 2, height: (_mH - 0.7) * u)
          : Rect.fromCircle(center: c, radius: r);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(r));
      canvas.drawRRect(
          rr,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0.2, 0.35),
              colors: const [Color(0xFF6B3A17), Color(0xFF3E200B)],
            ).createShader(rect));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.04
            ..color = Colors.black45);
      if (legal.contains(i)) {
        canvas.drawRRect(
            rr.inflate(u * 0.03),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * (hover == i ? 0.1 : 0.06)
              ..color = const Color(0xFFFFD54F).withValues(alpha: hover == i ? 1 : 0.75));
      }
      if (i == last) {
        canvas.drawRRect(
            rr.deflate(u * 0.03),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.05
              ..color = captured ? const Color(0xFFEF5350) : const Color(0xFF42A5F5));
      }
      if (i == lastPit) {
        canvas.drawCircle(rect.topLeft + Offset(r * 0.25, r * 0.25), u * 0.07, Paint()..color = const Color(0xFF42A5F5));
      }
      // 石子
      final n = pits[i];
      final rnd = Random(i * 7919 + 13);
      final shown = min(n, store ? 40 : 18);
      final gr = u * 0.1;
      for (var k = 0; k < shown; k++) {
        final ang = rnd.nextDouble() * pi * 2;
        final dist = sqrt(rnd.nextDouble());
        final w = rect.width / 2 - gr * 1.5, h = rect.height / 2 - gr * 1.5;
        final p = c + Offset(cos(ang) * w * dist, sin(ang) * h * dist);
        absStone(canvas, p, gr, _gemColors[(i * 3 + k) % _gemColors.length], shadow: false);
      }
      // 数字
      final ty = store ? c.dy : (c.dy < size.height / 2 ? c.dy - r - u * 0.2 : c.dy + r + u * 0.2);
      final tx = store ? c.dx : c.dx;
      if (store) {
        final tp = absText('$n', u * 0.42, Colors.white, weight: FontWeight.w800);
        final bg = Rect.fromCenter(center: Offset(tx, ty), width: tp.width + u * 0.3, height: tp.height + u * 0.05);
        canvas.drawRRect(RRect.fromRectAndRadius(bg, Radius.circular(u * 0.2)), Paint()..color = Colors.black54);
        tp.paint(canvas, Offset(tx - tp.width / 2, ty - tp.height / 2));
      } else {
        absTextAt(canvas, '$n', Offset(tx, ty), u * 0.3, const Color(0xFFFFF3E0), weight: FontWeight.w800);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MancalaPainter o) => true;
}

class MancalaBoardView extends StatefulWidget {
  final GameContext g;
  const MancalaBoardView(this.g, {super.key});
  @override
  State<MancalaBoardView> createState() => _MancalaBoardViewState();
}

class _MancalaBoardViewState extends State<MancalaBoardView> {
  int hover = -1;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final pits = (v['pits'] as List).cast<int>();
    final turn = v['turn'] as int;
    final over = v['over'] as bool;
    final legal = (v['legal'] as List).cast<int>().toSet();
    final lastSeat = v['lastSeat'] as int;
    final lastCaptured = v['lastCaptured'] as int;
    final lastAgain = v['lastAgain'] as bool;
    final me = g.seat;
    final player = me == 0 || me == 1;
    final bottom = player ? me : 0;
    final myTurn = !over && turn == me;

    String status;
    if (over) {
      status = v['result'] as String? ?? '对局结束';
    } else if (myTurn) {
      status = lastAgain && lastSeat == me ? '最后一颗落入己仓，再走一次！' : '轮到你：选择己方一侧的一个坑播种';
    } else {
      status = '等待 ${g.name(turn)} 播种';
    }

    Widget tagFor(int s) => g.tag(s, active: !over && turn == s, sub: '仓中 ${pits[s == 0 ? 6 : 13]} 颗');

    final boardWidget = LayoutBuilder(builder: (context, c) {
      final u = c.maxWidth / _mW;
      final geo = _MGeo(u, bottom);
      final myLegal = myTurn ? legal : const <int>{};
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
            if (p >= 0 && myLegal.contains(p)) g.act({'type': 'play', 'pit': p});
          },
          child: CustomPaint(
            size: Size(c.maxWidth, u * _mH),
            painter: _MancalaPainter(geo, pits, myLegal, v['last'] as int, v['lastPit'] as int, hover, lastCaptured > 0),
          ),
        ),
      );
    });

    final lastLine = lastSeat < 0
        ? '逆时针播种，跳过对方的仓'
        : '${g.name(lastSeat)} 上一步${lastCaptured > 0 ? '吃掉对面 ${lastCaptured - 1} 颗' : ''}'
            '${lastAgain ? '，落入己仓再走一次' : ''}${lastCaptured == 0 && !lastAgain ? '：普通播种' : ''}';
    return AbsShell(
      tags: [tagFor(1 - bottom), tagFor(bottom)],
      status: status,
      statusHighlight: myTurn,
      aspect: _mW / _mH,
      board: boardWidget,
      actions: [?absResign(context, g)],
      info: [
        '每坑 ${v['seeds']} 颗 · ${v['capture'] == true ? '可吃子' : '无吃子'} · 第 ${v['moves']} 步 · 你的仓在右侧',
        lastLine,
      ],
      result: absBanner(g, v),
      resultSub: over ? '仓中石子 ${pits[6]} : ${pits[13]}' : null,
    );
  }
}
