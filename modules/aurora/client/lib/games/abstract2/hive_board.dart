import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'common.dart';

const _types = ['Q', 'S', 'B', 'G', 'A', 'M', 'L', 'P'];
const _names = {'Q': '蜂后', 'S': '蜘蛛', 'B': '甲虫', 'G': '蚱蜢', 'A': '蚂蚁', 'M': '蚊子', 'L': '瓢虫', 'P': '鼠妇'};
const _glyph = {'Q': '后', 'S': '蛛', 'B': '甲', 'G': '蜢', 'A': '蚁', 'M': '蚊', 'L': '瓢', 'P': '鼠'};
const _bugColor = {
  'Q': Color(0xFFF2B01E),
  'S': Color(0xFF8D5A3B),
  'B': Color(0xFF7E57C2),
  'G': Color(0xFF43A047),
  'A': Color(0xFF1E88E5),
  'M': Color(0xFF78909C),
  'L': Color(0xFFE53935),
  'P': Color(0xFF00897B),
};
const _ivory = Color(0xFFF4EBD6);
const _ebony = Color(0xFF2B2622);

typedef _Hex = (int, int);

Offset _hexCenter(_Hex h, double s) => Offset(sqrt(3) * s * (h.$1 + h.$2 / 2), 1.5 * s * h.$2);

Path _hexPath(Offset c, double r) {
  final p = Path();
  for (var k = 0; k < 6; k++) {
    final a = pi / 180 * (60 * k - 30);
    final o = c + Offset(cos(a) * r, sin(a) * r);
    k == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

/// Draws one hive tile at [c] with radius [r].
void paintHiveTile(Canvas canvas, Offset c, double r, String code, {double opacity = 1, int height = 1, bool dimmed = false}) {
  final white = code[0] == 'w';
  final t = code.substring(1);
  final face = white ? _ivory : _ebony;
  final path = _hexPath(c, r * 0.94);
  canvas.drawPath(path.shift(Offset(r * 0.06, r * 0.12)), a2Shadow(r * 0.12, alpha: 0.45 * opacity));
  // bevel
  canvas.drawPath(path.shift(Offset(0, r * 0.07)), Paint()..color = Color.lerp(face, Colors.black, white ? 0.35 : 0.5)!.withValues(alpha: opacity));
  canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.1,
          colors: [
            Color.lerp(face, Colors.white, white ? 0.5 : 0.18)!.withValues(alpha: opacity),
            face.withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r)));
  final bug = _bugColor[t] ?? Colors.grey;
  canvas.drawCircle(c, r * 0.5, Paint()..color = bug.withValues(alpha: opacity));
  canvas.drawCircle(
      c,
      r * 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, r * 0.05)
        ..color = Colors.white.withValues(alpha: 0.7 * opacity));
  a2PaintTextCentered(canvas, _glyph[t] ?? t, c, r * 0.5, Colors.white.withValues(alpha: opacity));
  if (height > 1) {
    final bc = c + Offset(r * 0.55, -r * 0.55);
    canvas.drawCircle(bc, r * 0.26, Paint()..color = const Color(0xFFD32F2F).withValues(alpha: opacity));
    a2PaintTextCentered(canvas, '$height', bc, r * 0.3, Colors.white.withValues(alpha: opacity));
  }
  if (dimmed) canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.35));
}

class _HivePainter extends CustomPainter {
  final Map<_Hex, List<String>> stacks;
  final double s;
  final Offset origin;
  final _Hex? sel;
  final Set<_Hex> targets;
  final Set<_Hex> throwTargets;
  final _Hex? hover;
  final String? ghost;
  final _Hex? lastFrom, lastTo, frozen;
  final Set<_Hex> selectable;
  final Color accent;
  final Set<_Hex> queenDanger;

  _HivePainter(this.stacks, this.s, this.origin, this.sel, this.targets, this.throwTargets, this.hover, this.ghost, this.lastFrom,
      this.lastTo, this.frozen, this.selectable, this.accent, this.queenDanger);

  Offset ctr(_Hex h) => origin + _hexCenter(h, s);

  @override
  void paint(Canvas canvas, Size size) {
    // subtle hex grid around the hive
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    final near = <_Hex>{};
    for (final h in stacks.keys) {
      for (final (dq, dr) in const [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]) {
        near.add((h.$1 + dq, h.$2 + dr));
      }
    }
    for (final h in near) {
      if (!stacks.containsKey(h)) canvas.drawPath(_hexPath(ctr(h), s * 0.96), gridPaint);
    }
    if (lastFrom != null && !stacks.containsKey(lastFrom)) {
      canvas.drawPath(
          _hexPath(ctr(lastFrom!), s * 0.9),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, s * 0.06)
            ..color = const Color(0x88FFD54F));
    }
    for (final e in stacks.entries) {
      final c = ctr(e.key);
      final st = e.value;
      if (st.length > 1) {
        // hint of the piece underneath
        paintHiveTile(canvas, c + Offset(-s * 0.1, s * 0.12), s, st[st.length - 2], opacity: 0.9);
      }
      paintHiveTile(canvas, c, s, st.last, height: st.length, dimmed: e.key == frozen);
      if (queenDanger.contains(e.key)) {
        canvas.drawPath(
            _hexPath(c, s * 0.98),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, s * 0.08)
              ..color = const Color(0xCCE53935));
      }
      if (e.key == lastTo) {
        canvas.drawPath(
            _hexPath(c, s * 0.98),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(2, s * 0.08)
              ..color = const Color(0xFFFFD54F));
      }
      if (selectable.contains(e.key) && e.key != sel) {
        canvas.drawPath(
            _hexPath(c, s * 0.9),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1, s * 0.04)
              ..color = accent.withValues(alpha: 0.55));
      }
    }
    if (sel != null) {
      canvas.drawPath(
          _hexPath(ctr(sel!), s * 1.0),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(2.5, s * 0.12)
            ..color = accent);
    }
    for (final t in {...targets, ...throwTargets}) {
      final c = ctr(t);
      final occupied = stacks.containsKey(t);
      final isHover = t == hover;
      if (isHover && ghost != null) {
        paintHiveTile(canvas, c, s, ghost!, opacity: 0.55);
      }
      canvas.drawPath(
          _hexPath(c, s * 0.9),
          Paint()
            ..color = (occupied ? const Color(0xFF8E24AA) : const Color(0xFF43A047)).withValues(alpha: isHover ? 0.45 : 0.25));
      canvas.drawPath(
          _hexPath(c, s * 0.9),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.5, s * 0.05)
            ..color = occupied ? const Color(0xFFCE93D8) : const Color(0xFF81C784));
      if (throwTargets.contains(t) && !targets.contains(t)) {
        a2PaintTextCentered(canvas, '搬', c, s * 0.45, Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

class HiveBoardView extends StatefulWidget {
  final GameContext g;
  const HiveBoardView(this.g, {super.key});
  @override
  State<HiveBoardView> createState() => _HiveBoardViewState();
}

class _HiveBoardViewState extends State<HiveBoardView> {
  String? handSel; // piece type selected from hand
  _Hex? sel; // board cell selected
  _Hex? hover;
  Object? _lastPlies;
  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = g.view;
    if (_lastPlies != v['plies']) {
      _lastPlies = v['plies'];
      handSel = null;
      sel = null;
    }
    final stacks = <_Hex, List<String>>{
      for (final e in v['stacks'] as List) ((e['q'] as int), (e['r'] as int)): (e['p'] as List).cast<String>()
    };
    final hands = [for (final h in v['hand'] as List) (h as Map).cast<String, int>()];
    final expansion = v['expansion'] == true;
    final whiteSeat = v['whiteSeat'] as int;
    final toMove = v['toMove'] as int;
    final turn = v['turn'] as int;
    final placed = (v['placed'] as List).cast<int>();
    final queenPlaced = (v['queenPlaced'] as List).cast<bool>();
    final moves = [for (final m in v['moves'] as List) (m as List).cast<int>()];
    final placeCells = {for (final c in v['placeCells'] as List) ((c[0] as int), (c[1] as int))};
    final placeTypes = (v['placeTypes'] as List).cast<String>().toSet();
    final fz = v['frozen'] as List?;
    final frozen = fz == null ? null : ((fz[0] as int), (fz[1] as int));
    final last = v['last'] as Map?;
    final note = v['note'] as String;
    final winner = v['winner'] as int;
    final result = v['result'] as String;
    final over = v['over'] == true;
    final me = g.seat;
    final myColor = me == whiteSeat ? 0 : (me == 1 - whiteSeat ? 1 : -1);
    final myTurn = !over && turn == me && !g.replay;
    final lf = last?['from'] as List?, lt = last?['to'] as List?;
    final lastFrom = lf == null ? null : ((lf[0] as int), (lf[1] as int));
    final lastTo = lt == null ? null : ((lt[0] as int), (lt[1] as int));

    // queens in danger (≥4 neighbours) get a red ring
    final queenDanger = <_Hex>{};
    for (final e in stacks.entries) {
      if (!e.value.any((p) => p.substring(1) == 'Q')) continue;
      var n = 0;
      for (final (dq, dr) in const [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]) {
        if (stacks.containsKey((e.key.$1 + dq, e.key.$2 + dr))) n++;
      }
      if (n >= 4) queenDanger.add(e.key);
    }

    // selectable board cells: pieces with a legal move (or throw) from there
    final moveFrom = <_Hex, Set<_Hex>>{};
    final throwFrom = <_Hex, Set<_Hex>>{};
    for (final m in moves) {
      final f = (m[0], m[1]), t = (m[2], m[3]);
      if (m.length == 4) {
        (moveFrom[f] ??= {}).add(t);
      } else {
        (throwFrom[f] ??= {}).add(t);
      }
    }
    final selectable = myTurn ? {...moveFrom.keys, ...throwFrom.keys} : <_Hex>{};
    var targets = <_Hex>{};
    var throwTargets = <_Hex>{};
    String? ghost;
    if (myTurn && handSel != null && placeTypes.contains(handSel)) {
      targets = placeCells;
      ghost = '${toMove == 0 ? 'w' : 'b'}$handSel';
    } else if (myTurn && sel != null) {
      targets = moveFrom[sel] ?? {};
      throwTargets = (throwFrom[sel] ?? {}).difference(targets);
      ghost = stacks[sel]?.last;
    }

    void tapHex(_Hex h) {
      if (!myTurn) return;
      if (handSel != null && targets.contains(h)) {
        g.act({'type': 'place', 'piece': handSel, 'q': h.$1, 'r': h.$2});
        setState(() => handSel = null);
        return;
      }
      if (sel != null && (targets.contains(h) || throwTargets.contains(h))) {
        final f = sel!;
        if (targets.contains(h)) {
          g.act({
            'type': 'move',
            'from': [f.$1, f.$2],
            'to': [h.$1, h.$2]
          });
        } else {
          final m = moves.firstWhere((m) => m.length == 6 && m[0] == f.$1 && m[1] == f.$2 && m[2] == h.$1 && m[3] == h.$2);
          g.act({
            'type': 'throw',
            'by': [m[4], m[5]],
            'from': [f.$1, f.$2],
            'to': [h.$1, h.$2]
          });
        }
        setState(() => sel = null);
        return;
      }
      setState(() {
        handSel = null;
        sel = selectable.contains(h) && sel != h ? h : null;
      });
    }

    // Board geometry: fit every stack + target + a margin.
    final cells = <_Hex>{...stacks.keys, ...targets, ...throwTargets, ?lastFrom};
    if (cells.isEmpty) cells.add((0, 0));
    final boardWidget = LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      var minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
      for (final x in cells) {
        final o = _hexCenter(x, 1);
        minX = min(minX, o.dx);
        maxX = max(maxX, o.dx);
        minY = min(minY, o.dy);
        maxY = max(maxY, o.dy);
      }
      // units: pad 2.2 hex radii around
      final uw = maxX - minX + 2 * 2.0, uh = maxY - minY + 2 * 2.0;
      final s = min(min(w / uw, h / uh), min(w, h) / 5.5);
      final origin = Offset(w / 2 - (minX + maxX) / 2 * s, h / 2 - (minY + maxY) / 2 * s);
      _Hex? hit(Offset o) {
        final p = (o - origin) / s;
        final qf = (sqrt(3) / 3 * p.dx - p.dy / 3), rf = 2 / 3 * p.dy;
        // cube rounding
        var x = qf, z = rf, y = -x - z;
        var rx = x.roundToDouble(), ry = y.roundToDouble(), rz = z.roundToDouble();
        final dx = (rx - x).abs(), dy = (ry - y).abs(), dz = (rz - z).abs();
        if (dx > dy && dx > dz) {
          rx = -ry - rz;
        } else if (dy > dz) {
          ry = -rx - rz;
        } else {
          rz = -rx - ry;
        }
        return (rx.toInt(), rz.toInt());
      }

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: RadialGradient(colors: [Color.lerp(g.table, Colors.white, 0.08)!, Color.lerp(g.table, Colors.black, 0.25)!], radius: 1.0),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: MouseRegion(
            onHover: (e) {
              final hh = hit(e.localPosition);
              if (hh != hover) setState(() => hover = hh);
            },
            onExit: (_) => setState(() => hover = null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final hh = hit(d.localPosition);
                if (hh != null) tapHex(hh);
              },
              child: CustomPaint(
                size: Size(w, h),
                painter: _HivePainter(stacks, s, origin, myTurn ? sel : null, targets, throwTargets, hover, ghost, lastFrom, lastTo,
                    frozen, selectable, cs.primary, queenDanger),
              ),
            ),
          ),
        ),
      );
    });

    final types = [for (final t in _types) if (expansion || !'MLP'.contains(t)) t];
    Widget handRow(int color, {required bool mine}) {
      final seat = color == 0 ? whiteSeat : 1 - whiteSeat;
      final active = mine && myTurn && toMove == color;
      return LayoutBuilder(builder: (context, c) {
        final chip = min((c.maxWidth - (mine ? 0 : 56)) / types.length, c.maxHeight).clamp(8.0, 58.0);
        return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (final t in types)
            Builder(builder: (context) {
              final n = hands[color][t] ?? 0;
              final allowed = active && placeTypes.contains(t) && n > 0;
              final selected = active && handSel == t;
              return Tooltip(
                message: '${_names[t]} ×$n',
                child: GestureDetector(
                  onTap: allowed
                      ? () => setState(() {
                            handSel = selected ? null : t;
                            sel = null;
                          })
                      : null,
                  child: Container(
                    width: chip,
                    height: chip,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(chip * 0.2),
                      color: selected ? cs.primary.withValues(alpha: 0.35) : (allowed ? cs.primary.withValues(alpha: 0.08) : null),
                      border: selected ? Border.all(color: cs.primary, width: 2) : null,
                    ),
                    child: Opacity(
                      opacity: n == 0 ? 0.18 : (active && !allowed ? 0.45 : 1),
                      child: CustomPaint(
                        painter: _ChipPainter('${color == 0 ? 'w' : 'b'}$t', n),
                      ),
                    ),
                  ),
                ),
              );
            }),
          if (!mine) ...[
            const SizedBox(width: 4),
            SizedBox(
                width: 50,
                child: Text(g.name(seat),
                    overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)))),
          ],
        ]);
      });
    }

    final bottomColor = myColor < 0 ? 0 : myColor;
    final tray = A2Panel(
      highlight: myTurn,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(children: [
        Expanded(child: handRow(1 - bottomColor, mine: false)),
        const Divider(height: 4),
        Expanded(flex: 2, child: handRow(bottomColor, mine: myColor >= 0)),
      ]),
    );

    String status;
    if (over) {
      status = result;
    } else if (myTurn) {
      final mustQueen = placeTypes.length == 1 && placeTypes.contains('Q') && placed[toMove] == 3;
      if (mustQueen) {
        status = '第 4 手：必须放下蜂后';
      } else if (handSel != null) {
        status = '点绿色格打入${_names[handSel]}';
      } else if (sel != null) {
        status = '点高亮格移动${throwTargets.isNotEmpty ? '（“搬”= 鼠妇搬运）' : ''}';
      } else {
        status = queenPlaced[toMove] ? '轮到你：选手中棋子打入，或点己方棋子移动' : '轮到你：从手中选一枚棋子打入';
      }
    } else {
      status = '等待 ${g.name(turn)}（${toMove == 0 ? '白' : '黑'}）';
    }

    Widget tagFor(int s) {
      final c = s == whiteSeat ? 0 : 1;
      final left = hands[c].values.fold(0, (a, b) => a + b);
      return g.tag(s,
          active: !over && turn == s,
          sub: '${c == 0 ? '白' : '黑'} · 手中 $left${over ? (winner == s ? ' · 胜' : (winner == 2 ? ' · 和' : ' · 负')) : ''}',
          trailing: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                  color: c == 0 ? _ivory : _ebony, shape: BoxShape.circle, border: Border.all(color: Colors.black26))));
    }

    final bottomSeat = bottomColor == 0 ? whiteSeat : 1 - whiteSeat;
    return A2Shell(
      tags: [tagFor(1 - bottomSeat), tagFor(bottomSeat)],
      status: status,
      statusHighlight: myTurn,
      aspect: 0,
      board: boardWidget,
      tray: tray,
      trayFraction: 0.17,
      trayLandscapeHeight: 150,
      info: [
        if (note.isNotEmpty) '上一步：$note',
        '围住对方蜂后六面即胜 · 红圈：蜂后已被围 4 面以上',
      ],
      result: a2Banner(g, over, winner),
      resultSub: over ? result : null,
    );
  }
}

class _ChipPainter extends CustomPainter {
  final String code;
  final int n;
  _ChipPainter(this.code, this.n);
  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) * 0.42;
    final c = Offset(size.width / 2, size.height / 2 - r * 0.04);
    paintHiveTile(canvas, c, r, code);
    if (n > 1) {
      final bc = Offset(size.width - r * 0.35, size.height - r * 0.35);
      canvas.drawCircle(bc, r * 0.34, Paint()..color = const Color(0xFF263238));
      a2PaintTextCentered(canvas, '$n', bc, r * 0.4, Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _ChipPainter o) => o.code != code || o.n != n;
}
