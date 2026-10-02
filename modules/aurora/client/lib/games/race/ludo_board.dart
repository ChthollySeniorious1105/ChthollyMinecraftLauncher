import 'dart:math';

import 'package:aurora_shared/games/race/ludo.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'race_common.dart';

const _ludoColors = [Color(0xFFE53935), Color(0xFFFDD835), Color(0xFF1E88E5), Color(0xFF43A047)];
const _ludoNames = ['红', '黄', '蓝', '绿'];

class LudoBoard extends StatefulWidget {
  final GameContext g;
  const LudoBoard(this.g, {super.key});
  @override
  State<LudoBoard> createState() => _LudoBoardState();
}

class _LudoBoardState extends State<LudoBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _roll =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  int _seenRolls = -1;
  final _rand = Random();

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LudoBoard old) {
    super.didUpdateWidget(old);
    final r = (widget.g.view['rolls'] as num?)?.toInt() ?? 0;
    if (_seenRolls >= 0 && r != _seenRolls) _roll.forward(from: 0);
    _seenRolls = r;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    _seenRolls = _seenRolls < 0 ? ((v['rolls'] as num?)?.toInt() ?? 0) : _seenRolls;
    final colors = (v['colors'] as List).cast<int>();
    final pos = [for (final p in v['pos'] as List) (p as List).cast<int>()];
    final turn = v['turn'] as int;
    final phase = v['phase'] as String;
    final die = v['die'] as int;
    final movable = (v['movable'] as List).cast<int>();
    final winner = v['winner'] as int;
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final myTurn = !g.over && winner < 0 && turn == g.seat;

    String status;
    if (winner >= 0) {
      status = '${g.name(winner)} 获胜！';
    } else if (myTurn) {
      status = phase == 'roll' ? (die == 6 && last?['seat'] == g.seat && last?['stops'] != null ? '掷出 6，再掷一次！' : '轮到你掷骰子') : '掷出 $die 点，选择要移动的飞机';
    } else {
      status = '等待 ${g.name(turn)}${phase == 'move' ? ' 选择飞机' : ' 掷骰子'}';
    }

    String lastText = '';
    if (last != null) {
      final who = g.name(last['seat'] as int);
      if (last['void'] == true) {
        lastText = '$who 连掷三个 6，本轮作废';
      } else if (last['none'] == true) {
        lastText = '$who 掷出 ${last['roll']}，无飞机可动';
      } else if (last['stops'] != null) {
        final cap = (last['captured'] as List).length;
        lastText = '$who 掷 ${last['die']} 移动飞机${cap > 0 ? '，击落 $cap 架！' : ''}';
      } else if (last['roll'] != null) {
        lastText = '$who 掷出 ${last['roll']}';
      }
    }

    final tags = [
      for (var s = 0; s < g.players; s++)
        g.tag(s,
            active: winner < 0 && turn == s,
            sub: '${_ludoNames[colors[s]]}方 · 到达 ${pos[s].where((p) => p >= LudoGeo.finish).length}/4',
            trailing: Icon(Icons.flight, color: _ludoColors[colors[s]], size: 20)),
    ];

    final dieWidget = AnimatedBuilder(
      animation: _roll,
      builder: (context, _) {
        final t = _roll.value;
        final spinning = _roll.isAnimating;
        final face = spinning ? _rand.nextInt(6) + 1 : (die == 0 ? 1 : die);
        return Transform.rotate(
          angle: spinning ? t * pi * 4 : 0,
          child: Transform.scale(scale: spinning ? 1 + 0.25 * sin(t * pi) : 1, child: DieFace(face, size: 52)),
        );
      },
    );

    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        dieWidget,
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: myTurn && phase == 'roll' ? () => g.act({'t': 'roll'}) : null,
          icon: const Icon(Icons.casino),
          label: const Text('掷骰子'),
        ),
      ]),
      if (lastText.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(lastText, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
      ],
      const SizedBox(height: 4),
      Text('${v['launch'] == 5 ? '5或6' : '6'} 点起飞 · 同色格跳 4 格 · 虚线处飞越',
          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
    ]);

    return RaceScaffold(
      tags: tags,
      status: status,
      highlight: myTurn,
      controls: controls,
      overlay: winner >= 0 ? DismissibleResult('${g.name(winner)} 的四架飞机全部到达终点！') : null,
      board: LayoutBuilder(builder: (context, c) {
        final size = min(c.maxWidth, c.maxHeight);
        final u = size / 15;
        final planes = <Widget>[];
        for (var s = 0; s < pos.length; s++) {
          final color = colors[s];
          // group planes by position to offset stacked planes
          final groups = <int, List<int>>{};
          for (var i = 0; i < 4; i++) {
            if (pos[s][i] >= 0) (groups[pos[s][i]] ??= []).add(i);
          }
          for (var i = 0; i < 4; i++) {
            final p = pos[s][i];
            double x, y;
            if (p < 0) {
              final (hr, hc) = LudoGeo.hangarCorner(color);
              x = hc + 1.5 + (i % 2) * 2.0;
              y = hr + 1.5 + (i ~/ 2) * 2.0;
            } else {
              final (r, cc) = LudoGeo.cell(color, p);
              final grp = groups[p]!;
              final k = grp.indexOf(i);
              final off = grp.length > 1 ? (k - (grp.length - 1) / 2) * 0.22 : 0.0;
              x = cc + 0.5 + off;
              y = r + 0.5 + off;
            }
            final canMove = myTurn && phase == 'move' && movable.contains(i) && s == g.seat;
            final justMoved = last != null && last['seat'] == s && last['plane'] == i;
            planes.add(AnimatedPositioned(
              key: ValueKey('p$s-$i'),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOut,
              left: x * u - u * 0.48,
              top: y * u - u * 0.48,
              width: u * 0.96,
              height: u * 0.96,
              child: _Plane(
                color: _ludoColors[color],
                angle: pi / 2 * ((color + 1) % 4),
                highlight: canMove,
                recent: justMoved,
                finished: p >= LudoGeo.finish,
                onTap: canMove ? () => g.act({'t': 'move', 'plane': i}) : null,
              ),
            ));
          }
        }
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _LudoPainter(Theme.of(context).colorScheme, turnColor: colors[turn]))),
              ...planes,
            ]),
          ),
        );
      }),
    );
  }
}

class _Plane extends StatelessWidget {
  final Color color;
  final double angle;
  final bool highlight;
  final bool recent;
  final bool finished;
  final VoidCallback? onTap;
  const _Plane({required this.color, required this.angle, this.highlight = false, this.recent = false, this.finished = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final s = c.maxWidth;
      Widget w = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.9),
          border: Border.all(color: highlight ? Colors.amber : (recent ? Colors.white : color), width: highlight ? 3 : 1.5),
          boxShadow: [
            if (highlight) const BoxShadow(color: Colors.amber, blurRadius: 10, spreadRadius: 1),
            const BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 1.5)),
          ],
        ),
        child: Transform.rotate(angle: angle, child: Icon(Icons.flight, color: color, size: s * 0.72)),
      );
      if (finished) w = Opacity(opacity: 0.85, child: w);
      if (onTap == null) return w;
      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
    });
  }
}

class _LudoPainter extends CustomPainter {
  final ColorScheme cs;
  final int turnColor;
  _LudoPainter(this.cs, {required this.turnColor});

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 15;
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(u * 0.6));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFFFFF8E1));
    canvas.drawRRect(bg, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * 0.12
      ..color = const Color(0xFF8D6E63));

    Rect cellRect(int r, int c, [double inset = 0.06]) =>
        Rect.fromLTWH(c * u + u * inset, r * u + u * inset, u * (1 - 2 * inset), u * (1 - 2 * inset));

    // hangars
    for (var col = 0; col < 4; col++) {
      final (hr, hc) = LudoGeo.hangarCorner(col);
      final rect = Rect.fromLTWH(hc * u + u * 0.3, hr * u + u * 0.3, u * 5.4, u * 5.4);
      final color = _ludoColors[col];
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(u * 0.6)),
          Paint()..color = color.withValues(alpha: col == turnColor ? 0.55 : 0.3));
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(u * 0.6)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = col == turnColor ? u * 0.14 : u * 0.06
            ..color = color);
      for (var i = 0; i < 4; i++) {
        final center = Offset((hc + 1.5 + (i % 2) * 2.0) * u, (hr + 1.5 + (i ~/ 2) * 2.0) * u);
        canvas.drawCircle(center, u * 0.62, Paint()..color = Colors.white.withValues(alpha: 0.85));
        canvas.drawCircle(center, u * 0.62, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.05
          ..color = color);
      }
    }

    // track squares
    for (var gsq = 0; gsq < LudoGeo.track; gsq++) {
      final (r, c) = LudoGeo.trackCell(gsq);
      final color = _ludoColors[LudoGeo.squareColor(gsq)];
      final rr = RRect.fromRectAndRadius(cellRect(r, c), Radius.circular(u * 0.2));
      canvas.drawRRect(rr.shift(Offset(u * 0.03, u * 0.05)), Paint()..color = Colors.black26);
      canvas.drawRRect(rr, Paint()..color = color);
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.04
        ..color = Colors.white70);
    }

    // start squares: arrow marks
    for (var col = 0; col < 4; col++) {
      final (r, c) = LudoGeo.startCell(col);
      final center = Offset((c + 0.5) * u, (r + 0.5) * u);
      canvas.drawCircle(center, u * 0.22, Paint()..color = Colors.white);
      // flying shortcut dashed line
      final (fr, fc) = LudoGeo.trackCell(LudoGeo.global(col, LudoGeo.flyFrom));
      final (tr, tc) = LudoGeo.trackCell(LudoGeo.global(col, LudoGeo.flyTo));
      final a = Offset((fc + 0.5) * u, (fr + 0.5) * u), b = Offset((tc + 0.5) * u, (tr + 0.5) * u);
      final paint = Paint()
        ..color = _ludoColors[col]
        ..strokeWidth = u * 0.1
        ..strokeCap = StrokeCap.round;
      const n = 9;
      for (var k = 0; k < n; k += 2) {
        canvas.drawLine(Offset.lerp(a, b, k / n)!, Offset.lerp(a, b, (k + 1) / n)!, paint);
      }
      _drawPlaneMark(canvas, a, u * 0.35, Colors.white);
    }

    // home columns
    for (var col = 0; col < 4; col++) {
      final color = _ludoColors[col];
      for (final (r, c) in LudoGeo.homeColumn(col)) {
        final rr = RRect.fromRectAndRadius(cellRect(r, c), Radius.circular(u * 0.2));
        canvas.drawRRect(rr, Paint()..color = Color.lerp(color, Colors.white, 0.35)!);
        canvas.drawRRect(rr, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.05
          ..color = color);
      }
    }

    // centre: 4 triangles
    final center = Offset(7.5 * u, 7.5 * u);
    final corners = [Offset(6 * u, 6 * u), Offset(9 * u, 6 * u), Offset(9 * u, 9 * u), Offset(6 * u, 9 * u)];
    // colour c's home column enters from rot(c) side: c0 from the left, c1 top, c2 right, c3 bottom
    const sideFor = [3, 0, 1, 2]; // index of corner pair start (left side = corners 3->0)
    for (var col = 0; col < 4; col++) {
      final i = sideFor[col];
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(corners[i].dx, corners[i].dy)
        ..lineTo(corners[(i + 1) % 4].dx, corners[(i + 1) % 4].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = _ludoColors[col]);
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u * 0.05
        ..color = Colors.white);
    }
    canvas.drawCircle(center, u * 0.45, Paint()..color = Colors.white);
    _drawPlaneMark(canvas, center, u * 0.35, const Color(0xFF8D6E63));
  }

  void _drawPlaneMark(Canvas canvas, Offset c, double r, Color color) {
    final p = Paint()..color = color;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + r * 0.25, c.dy - r * 0.2)
      ..lineTo(c.dx + r, c.dy + r * 0.2)
      ..lineTo(c.dx + r * 0.2, c.dy + r * 0.1)
      ..lineTo(c.dx + r * 0.15, c.dy + r * 0.7)
      ..lineTo(c.dx + r * 0.45, c.dy + r)
      ..lineTo(c.dx - r * 0.45, c.dy + r)
      ..lineTo(c.dx - r * 0.15, c.dy + r * 0.7)
      ..lineTo(c.dx - r * 0.2, c.dy + r * 0.1)
      ..lineTo(c.dx - r, c.dy + r * 0.2)
      ..lineTo(c.dx - r * 0.25, c.dy - r * 0.2)
      ..close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _LudoPainter old) => old.turnColor != turnColor || old.cs != cs;
}
