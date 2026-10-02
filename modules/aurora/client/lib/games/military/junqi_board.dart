import 'dart:math' as math;

import 'package:aurora_shared/games/military/junqi.dart';
import 'package:aurora_shared/games/military/junqi_geo.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _seatColors = [Color(0xFFD32F2F), Color(0xFF1565C0), Color(0xFFEF6C00), Color(0xFF2E7D32)];

class JunqiBoard extends StatefulWidget {
  final GameContext g;
  const JunqiBoard(this.g, {super.key});
  @override
  State<JunqiBoard> createState() => _JunqiBoardState();
}

class _JunqiBoardState extends State<JunqiBoard> {
  int sel = -1;

  GameContext get g => widget.g;

  @override
  void didUpdateWidget(covariant JunqiBoard old) {
    super.didUpdateWidget(old);
    final v = g.view;
    final board = v['board'] as List;
    if (sel >= board.length) sel = -1;
    if ((v['phase'] as int) == 1) {
      final moves = (v['moves'] as Map);
      if (!moves.containsKey('$sel')) sel = -1;
    }
  }

  Color _pieceColor(int owner, String mode) {
    if (owner < 0) return const Color(0xFF6D4C41);
    if (mode == 'flip') return _seatColors[owner];
    return _seatColors[owner % 4];
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final mode = v['mode'] as String;
    final four = mode == 'four';
    final flip = mode == 'flip';
    final geo = JunqiGeo.of(four);
    final phase = v['phase'] as int;
    final turn = v['turn'] as int;
    final board = (v['board'] as List).cast<Map?>();
    final moves = (v['moves'] as Map).map((k, e) => MapEntry(int.parse(k as String), (e as List).cast<int>()));
    final ready = (v['ready'] as List).cast<bool>();
    final alive = (v['alive'] as List).cast<bool>();
    final colors = (v['colors'] as List).cast<int>();
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final me = g.seat;
    final myTurn = phase == 1 && turn == me && me >= 0;
    final deploying = phase == 0 && me >= 0 && !ready[me];
    final canFlip = v['canFlip'] == true;

    // --- status text
    String status;
    if (phase == 0) {
      status = me < 0
          ? '布阵中…'
          : deploying
              ? '布阵：先后点两枚己方棋子交换位置，完成后点“准备”'
              : '已准备，等待其他玩家布阵';
    } else if (phase == 1) {
      if (myTurn) {
        status = flip ? '轮到你：翻开一枚棋子，或移动己方棋子' : '轮到你：选择棋子，再点目标位置';
      } else {
        status = '等待 ${g.name(turn)} 行棋';
      }
    } else {
      status = v['result'] as String;
    }

    String? lastText;
    if (last != null) {
      final who = g.name(last['seat'] as int);
      lastText = switch (last['res']) {
        'flip' => '$who 翻开了一枚棋子',
        'move' => '$who 移动了棋子',
        'win' => '$who 发起进攻：胜利，吃掉对方棋子',
        'lose' => '$who 发起进攻：失败，己方棋子阵亡',
        'tie' => '$who 发起进攻：同归于尽',
        'flag' => '$who 夺取了军旗！',
        _ => null,
      };
    }

    // --- rotation so that my arm is at the bottom
    final rot = me < 0 ? 0 : (flip ? me : me % (four ? 4 : 2));
    Offset pos(int id) {
      final n = geo.nodes[id];
      var r = n.r.toDouble(), c = n.c.toDouble();
      if (four) {
        for (var i = 0; i < rot; i++) {
          final nr = c, nc = 16 - r;
          r = nr;
          c = nc;
        }
        return Offset(c, r);
      }
      if (rot == 1) {
        r = 11 - r;
        c = 4 - c;
      }
      return Offset(c, r + (r >= 6 ? 1 : 0));
    }

    Offset rotPt(double r, double c) {
      if (four) {
        for (var i = 0; i < rot; i++) {
          final nr = c, nc = 16 - r;
          r = nr;
          c = nc;
        }
      }
      return Offset(c, r);
    }

    void tap(int id) {
      final cell = board[id];
      if (deploying) {
        final mine = cell != null && cell['o'] == me;
        if (!mine) return;
        if (sel < 0) {
          setState(() => sel = id);
        } else if (sel == id) {
          setState(() => sel = -1);
        } else {
          g.act({'type': 'swap', 'a': sel, 'b': id});
          setState(() => sel = -1);
        }
        return;
      }
      if (!myTurn) return;
      if (sel >= 0 && (moves[sel]?.contains(id) ?? false)) {
        g.act({'type': 'move', 'from': sel, 'to': id});
        setState(() => sel = -1);
        return;
      }
      if (moves.containsKey(id)) {
        setState(() => sel = sel == id ? -1 : id);
        return;
      }
      if (canFlip && cell != null && cell['u'] != true) {
        g.act({'type': 'flip', 'node': id});
        setState(() => sel = -1);
        return;
      }
      setState(() => sel = -1);
    }

    final dests = sel >= 0 ? (moves[sel] ?? const <int>[]) : const <int>[];

    String sub(int s) {
      if (phase == 0) return ready[s] ? '已准备' : '布阵中';
      if (!alive[s]) return '已出局';
      if (flip) {
        final c = colors[s];
        return c < 0 ? '未定色' : (c == 0 ? '红方' : '蓝方');
      }
      if (four) return s % 2 == 0 ? '甲队' : '乙队';
      return '';
    }

    Color tagColor(int s) {
      if (flip) return colors[s] < 0 ? Colors.grey : _seatColors[colors[s]];
      return _seatColors[s % 4];
    }

    final lostRanks = (v['lost'] as List).cast<int>();

    return Column(children: [
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: [
        for (final s in g.seatsFromMe())
          g.tag(s,
              size: 30,
              active: phase == 1 && turn == s,
              sub: sub(s),
              trailing: Container(
                  width: 12, height: 12, decoration: BoxDecoration(color: tagColor(s), shape: BoxShape.circle))),
      ]),
      const SizedBox(height: 6),
      StatusBar(status, highlight: myTurn || deploying),
      if (lastText != null && phase != 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(lastText, style: const TextStyle(fontSize: 12)),
        ),
      if (phase == 0 && me >= 0 && v['error'] != null)
        Text(v['error'] as String, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
      const SizedBox(height: 4),
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          final gw = four ? 17.0 : 5.0 * 1.5;
          final gh = four ? 17.0 : 13.0;
          final u = math.min(box.maxWidth / gw, box.maxHeight / gh);
          final sx = four ? u : u * 1.5, sy = u;
          final bw = four ? 17 * u : 5 * sx, bh = gh * u;
          final pw = four ? u * 0.9 : u * 1.25, ph = four ? u * 0.64 : u * 0.72;
          Offset px(Offset gp) => Offset((gp.dx + 0.5) * sx, (gp.dy + 0.5) * sy);
          final lastFrom = last == null ? -1 : last['from'] as int;
          final lastTo = last == null ? -1 : last['to'] as int;
          return Center(
            child: SizedBox(
              width: bw,
              height: bh,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _JunqiPainter(
                      geo: geo,
                      pos: (id) => px(pos(id)),
                      arcCorner: (r, c) => px(rotPt(r, c)),
                      pw: pw,
                      ph: ph,
                      four: four,
                      label: !four,
                    ),
                  ),
                ),
                for (var id = 0; id < geo.nodes.length; id++)
                  Positioned(
                    left: px(pos(id)).dx - pw / 2,
                    top: px(pos(id)).dy - ph / 2,
                    width: pw,
                    height: ph,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tap(id),
                      child: _cell(board[id], mode, id == sel, dests.contains(id), id == lastFrom || id == lastTo,
                          pw, ph, geo.nodes[id].kind),
                    ),
                  ),
              ]),
            ),
          );
        }),
      ),
      Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (deploying) ...[
            OutlinedButton.icon(
                onPressed: () {
                  setState(() => sel = -1);
                  g.act({'type': 'random'});
                },
                icon: const Icon(Icons.shuffle, size: 18),
                label: const Text('随机布阵')),
            FilledButton.icon(
                onPressed: () {
                  setState(() => sel = -1);
                  g.act({'type': 'ready'});
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('准备')),
          ],
          if (phase == 1) Text('步数 ${v['plies']}/${v['cap']}', style: const TextStyle(fontSize: 12)),
          if (lostRanks.isNotEmpty)
            Text('我方阵亡：${lostRanks.map((r) => junqiRankNames[r]).join(' ')}', style: const TextStyle(fontSize: 12)),
        ]),
      ),
      if (g.over) ResultBanner(v['result'] as String),
    ]);
  }

  Widget _cell(Map? cell, String mode, bool selected, bool dest, bool lastMove, double w, double h, JKind kind) {
    if (cell == null) {
      if (!dest) {
        return lastMove
            ? DecoratedBox(
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber, width: 2), borderRadius: BorderRadius.circular(4)))
            : const SizedBox();
      }
      return Center(
        child: Container(
          width: h * 0.45,
          height: h * 0.45,
          decoration: BoxDecoration(
              color: Colors.greenAccent.shade400.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)]),
        ),
      );
    }
    final owner = cell['o'] as int;
    final rank = cell['k'] as int;
    final faceDown = mode == 'flip' && cell['u'] != true;
    final color = _pieceColor(faceDown ? -1 : owner, mode);
    final text = rank >= 0 ? junqiRankNames[rank]! : (faceDown ? '' : '');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, selected ? -h * 0.15 : 0, 0),
      decoration: BoxDecoration(
        gradient: faceDown
            ? const LinearGradient(colors: [Color(0xFF8D6E63), Color(0xFF5D4037)])
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.lerp(color, Colors.white, 0.18)!, color]),
        borderRadius: BorderRadius.circular(h * 0.14),
        border: Border.all(
          color: selected
              ? Colors.amber
              : dest
                  ? Colors.greenAccent
                  : lastMove
                      ? Colors.amberAccent
                      : Colors.black38,
          width: selected || dest || lastMove ? 2.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: selected ? 6 : 2, offset: const Offset(1, 1.5))
        ],
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: text.isEmpty
                ? Icon(faceDown ? Icons.help_outline : Icons.shield_outlined, color: Colors.white70, size: h * 0.6)
                : Text(text,
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: h * 0.52,
                        height: 1.1,
                        shadows: const [Shadow(blurRadius: 2, color: Colors.black54)])),
          ),
        ),
      ),
    );
  }
}

class _JunqiPainter extends CustomPainter {
  final JunqiGeo geo;
  final Offset Function(int) pos;
  final Offset Function(double r, double c) arcCorner;
  final double pw, ph;
  final bool four;
  final bool label;
  _JunqiPainter(
      {required this.geo,
      required this.pos,
      required this.arcCorner,
      required this.pw,
      required this.ph,
      required this.four,
      required this.label});

  @override
  void paint(Canvas canvas, Size size) {
    const ink = Color(0xFF5D4037);
    // background panels
    final bg = Paint()..color = const Color(0xFFEFE3C2);
    final shadow = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final rects = <RRect>[];
    if (four) {
      final u = size.width / 17;
      Rect g(double c0, double r0, double c1, double r1) => Rect.fromLTRB(c0 * u, r0 * u, c1 * u, r1 * u);
      for (final r in [g(5.6, 0, 11.4, 17), g(0, 5.6, 17, 11.4)]) {
        rects.add(RRect.fromRectAndRadius(r, Radius.circular(u * 0.4)));
      }
    } else {
      rects.add(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.03)));
    }
    for (final r in rects) {
      canvas.drawRRect(r.shift(const Offset(2, 3)), shadow);
    }
    for (final r in rects) {
      canvas.drawRRect(r, bg);
    }

    final road = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = 1.2;
    final railOuter = Paint()
      ..color = ink
      ..strokeWidth = ph * 0.28
      ..style = PaintingStyle.stroke;
    final railInner = Paint()
      ..color = const Color(0xFFEFE3C2)
      ..strokeWidth = ph * 0.13
      ..style = PaintingStyle.stroke;
    for (final (a, b, rail) in geo.edges) {
      if (!rail) canvas.drawLine(pos(a), pos(b), road);
    }
    final railPath = Path();
    for (final (a, b, rail) in geo.edges) {
      if (!rail) continue;
      railPath
        ..moveTo(pos(a).dx, pos(a).dy)
        ..lineTo(pos(b).dx, pos(b).dy);
    }
    for (final (a, b, cr, cc) in geo.arcs) {
      final na = geo.nodes[a], nb = geo.nodes[b];
      // control point = the corner opposite to the arc center
      var ctrl = (na.r.toDouble(), nb.c.toDouble());
      if (ctrl.$1 == cr && ctrl.$2 == cc) ctrl = (nb.r.toDouble(), na.c.toDouble());
      final cp = arcCorner(ctrl.$1, ctrl.$2);
      railPath
        ..moveTo(pos(a).dx, pos(a).dy)
        ..quadraticBezierTo(cp.dx, cp.dy, pos(b).dx, pos(b).dy);
    }
    canvas.drawPath(railPath, railOuter);
    canvas.drawPath(railPath, railInner);

    final fill = Paint()..color = const Color(0xFFF8F1DC);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final campFill = Paint()..color = const Color(0xFFD7E8C8);
    final hqFill = Paint()..color = const Color(0xFFF2C9B5);
    for (final n in geo.nodes) {
      final p = pos(n.id);
      switch (n.kind) {
        case JKind.camp:
          final r = ph * 0.62;
          canvas.drawCircle(p, r, campFill);
          canvas.drawCircle(p, r, stroke);
        case JKind.hq:
          final rr = RRect.fromRectAndRadius(
              Rect.fromCenter(center: p, width: pw * 0.95, height: ph * 1.05), Radius.circular(ph * 0.4));
          canvas.drawRRect(rr, hqFill);
          canvas.drawRRect(rr, stroke);
          _text(canvas, '营', p, ph * 0.4, ink.withValues(alpha: 0.5));
        case JKind.station:
          final rr = RRect.fromRectAndRadius(
              Rect.fromCenter(center: p, width: pw * 0.8, height: ph * 0.78), Radius.circular(ph * 0.12));
          canvas.drawRRect(rr, fill);
          canvas.drawRRect(rr, stroke);
      }
    }
    if (label) {
      // front line label between the two halves
      final y = size.height / 2;
      for (final x in [0.3, 0.7]) {
        _text(canvas, '山 界', Offset(size.width * x, y), ph * 0.42, ink.withValues(alpha: 0.6));
      }
    }
  }

  void _text(Canvas canvas, String s, Offset c, double fs, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontFamilyFallback: kFontFallback, fontSize: fs, color: color, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _JunqiPainter old) => true;
}
