import 'dart:math';

import 'package:aurora_shared/games/euro/carc_tiles.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'carc_painter.dart';
import 'euro_common.dart';

const double _cell = 60;

class CarcassonneBoard extends StatefulWidget {
  final GameContext g;
  const CarcassonneBoard(this.g, {super.key});
  @override
  State<CarcassonneBoard> createState() => _CarcassonneBoardState();
}

class _CarcassonneBoardState extends State<CarcassonneBoard> {
  (int, int)? sel;
  int rot = 0;
  String turnKey = '';
  final TransformationController ctrl = TransformationController();
  Size? _centeredFor;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  Map<(int, int), List<int>> _legal(Map<String, dynamic> v) => {
        for (final l in eList<dynamic>(v['legal']).map(eMap)) (eInt(l['x']), eInt(l['y'])): eList<int>(l['r']),
      };

  void _tapCell(int x, int y, Map<(int, int), List<int>> legal) {
    final rs = legal[(x, y)];
    if (rs == null || rs.isEmpty) return;
    setState(() {
      if (sel == (x, y)) {
        final i = rs.indexOf(rot);
        rot = rs[(i + 1) % rs.length];
      } else {
        sel = (x, y);
        if (!rs.contains(rot)) rot = rs.first;
      }
    });
  }

  void _rotate(Map<(int, int), List<int>> legal) {
    setState(() {
      final rs = sel == null ? null : legal[sel!];
      if (rs == null || rs.isEmpty) {
        rot = (rot + 1) % 4;
      } else {
        final i = rs.indexOf(rot);
        rot = rs[(i + 1) % rs.length];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = v['phase'] as String? ?? 'place';
    final turn = eInt(v['turn']);
    final over = phase == 'over';
    final myTurn = !over && turn == g.seat;
    final cur = v['cur'] as String?;
    final tiles = eList<dynamic>(v['tiles']).map(eMap).toList();
    final legal = _legal(v);
    final key = '$turn/${tiles.length}/$phase';
    if (key != turnKey) {
      turnKey = key;
      sel = null;
    }
    if (sel != null && !(legal[sel!]?.contains(rot) ?? false)) {
      final rs = legal[sel!];
      if (rs == null || rs.isEmpty) {
        sel = null;
      } else {
        rot = rs.first;
      }
    }
    final scores = eList<int>(v['scores']);
    final left = eList<int>(v['meeplesLeft']);
    final fin = v['final'] is List ? eList<dynamic>(v['final']).map(eMap).toList() : null;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn && phase == 'place') {
      status = sel == null ? '轮到你：点击绿色格子放置板块' : '点击同一格或“旋转”换方向，然后确认放置';
    } else if (myTurn) {
      status = '可点击板块上的圆点派出跟随者（剩 ${left.elementAtOrNull(g.seat) ?? 0} 个），或跳过';
    } else {
      status = '等待 ${g.name(turn)}${phase == 'meeple' ? ' 放置跟随者' : ' 放置板块'}';
    }

    final board = _boardView(v, tiles, legal, myTurn, phase, cur, cs);

    Widget scoresPanel(bool compact) => EPanel(
          padding: const EdgeInsets.all(6),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (var s = 0; s < g.players; s++)
              g.tag(s,
                  active: !over && s == turn,
                  size: compact ? 26 : 30,
                  sub: '${scores.elementAtOrNull(s) ?? 0} 分',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    MeepleIcon(meepleColor(s), size: compact ? 14 : 16),
                    Text('×${left.elementAtOrNull(s) ?? 0}', style: const TextStyle(fontSize: 12)),
                  ])),
          ]),
        );

    Widget tilePanel(double size) => EPanel(
          highlight: myTurn,
          padding: const EdgeInsets.all(6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (cur != null && phase == 'place') CarcTileView(cur, rot: rot, size: size) else SizedBox(width: size, height: size, child: Icon(Icons.layers, size: size * 0.5, color: cs.outline)),
              const SizedBox(height: 2),
              Text('牌堆 ${eInt(v['deck'])}', style: const TextStyle(fontSize: 11)),
            ]),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, children: [
              if (myTurn && phase == 'place') ...[
                OutlinedButton.icon(onPressed: () => _rotate(legal), icon: const Icon(Icons.rotate_right, size: 18), label: const Text('旋转')),
                const SizedBox(height: 4),
                FilledButton.icon(
                  onPressed: sel == null ? null : () => g.act({'type': 'place', 'x': sel!.$1, 'y': sel!.$2, 'rot': rot}),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('确认放置'),
                ),
              ],
              if (myTurn && phase == 'meeple')
                FilledButton.tonalIcon(
                  onPressed: () => g.act({'type': 'meeple', 'f': -1}),
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('不放跟随者'),
                ),
              if (!myTurn) Text(over ? '终局' : '${g.name(turn)} 行动中', style: const TextStyle(fontSize: 12)),
            ]),
          ]),
        );

    final log = ELog(eList<String>(v['recent']), max: 4, fontSize: 11);
    final result = fin == null
        ? null
        : ResultBanner(
            '${[for (final f in fin) if (f['win'] == true) g.name(eInt(f['seat']))].join('、')} 获胜！',
            child: Wrap(spacing: 10, runSpacing: 2, alignment: WrapAlignment.center, children: [
              for (final f in fin)
                Text('${g.name(eInt(f['seat']))} ${eInt(f['score'])} 分（终局 +${eInt(f['end'])}）', style: const TextStyle(fontSize: 12)),
            ]),
          );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 700 && c.maxWidth > c.maxHeight;
      if (wide) {
        final sideW = min(300.0, c.maxWidth * 0.32);
        return Row(children: [
          Expanded(child: Stack(children: [board, if (result != null) Align(alignment: Alignment.topCenter, child: result)])),
          SizedBox(
            width: sideW,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                StatusBar(status, highlight: myTurn),
                const SizedBox(height: 6),
                Center(child: tilePanel(c.maxHeight < 450 ? 52 : 72)),
                const SizedBox(height: 6),
                scoresPanel(c.maxHeight < 450),
                const SizedBox(height: 6),
                EPanel(child: log),
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        StatusBar(status, highlight: myTurn),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: scoresPanel(true)),
        Expanded(child: Stack(children: [board, if (result != null) Align(alignment: Alignment.topCenter, child: SingleChildScrollView(child: result))])),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            tilePanel(56),
            const SizedBox(width: 6),
            Expanded(child: EPanel(padding: const EdgeInsets.all(6), child: SizedBox(height: 74, child: ClipRect(child: OverflowBox(alignment: Alignment.bottomLeft, maxHeight: double.infinity, child: log))))),
          ]),
        ),
      ]);
    });
  }

  Widget _boardView(Map<String, dynamic> v, List<Map<String, dynamic>> tiles, Map<(int, int), List<int>> legal, bool myTurn,
      String phase, String? cur, ColorScheme cs) {
    var minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (final t in tiles) {
      minX = min(minX, eInt(t['x']));
      maxX = max(maxX, eInt(t['x']));
      minY = min(minY, eInt(t['y']));
      maxY = max(maxY, eInt(t['y']));
    }
    minX -= 2;
    minY -= 2;
    maxX += 2;
    maxY += 2;
    final cw = (maxX - minX + 1) * _cell, ch = (maxY - minY + 1) * _cell;
    final last = eInt(v['last'], -1);
    final meeples = eList<dynamic>(v['meeples']).map(eMap).toList();
    final opts = phase == 'meeple' ? eList<int>(v['meepleOpts']) : const <int>[];
    final lastTile = last >= 0 && last < tiles.length ? tiles[last] : null;

    // meeple spots of the just-placed tile
    final spots = <(int, Offset, FeatureKind)>[];
    if (lastTile != null && opts.isNotEmpty && myTurn) {
      final t = carcType(lastTile['t'] as String?);
      if (t != null) {
        final fs = t.featuresAt(eInt(lastTile['r']));
        for (final f in opts) {
          if (f < 0 || f >= fs.length) continue;
          spots.add((f, Offset((eInt(lastTile['x']) - minX + fs[f].ax) * _cell, (eInt(lastTile['y']) - minY + fs[f].ay) * _cell), fs[f].kind));
        }
      }
    }

    return LayoutBuilder(builder: (context, c) {
      final w = max(c.maxWidth, cw), h = max(c.maxHeight, ch);
      final ox = (w - cw) / 2, oy = (h - ch) / 2;
      final vp = Size(c.maxWidth, c.maxHeight);
      if (_centeredFor != vp) {
        _centeredFor = vp;
        // centre on the start tile
        final sx = ox + (0 - minX + 0.5) * _cell, sy = oy + (0 - minY + 0.5) * _cell;
        final tx = (c.maxWidth / 2 - sx).clamp(c.maxWidth - w, 0.0), ty = (c.maxHeight / 2 - sy).clamp(c.maxHeight - h, 0.0);
        ctrl.value = Matrix4.identity()..translateByDouble(tx, ty, 0, 1);
      }
      final painter = _BoardPainter(
        tiles: tiles,
        minX: minX,
        minY: minY,
        legal: myTurn && phase == 'place' ? legal.keys.toList() : const [],
        sel: sel,
        cur: cur,
        rot: rot,
        last: last,
        meeples: meeples,
        spots: spots,
        accent: cs.primary,
      );
      return ClipRect(
        child: InteractiveViewer(
          transformationController: ctrl,
          constrained: false,
          minScale: 0.3,
          maxScale: 2.5,
          boundaryMargin: const EdgeInsets.all(200),
          child: GestureDetector(
            onTapUp: (d) {
              final p = d.localPosition - Offset(ox, oy);
              if (spots.isNotEmpty) {
                for (final s in spots) {
                  if ((s.$2 - p).distance < _cell * 0.2) {
                    widget.g.act({'type': 'meeple', 'f': s.$1});
                    return;
                  }
                }
              }
              if (myTurn && phase == 'place') {
                _tapCell((p.dx / _cell).floor() + minX, (p.dy / _cell).floor() + minY, legal);
              }
            },
            child: SizedBox(
              width: w,
              height: h,
              child: CustomPaint(painter: painter.withOffset(Offset(ox, oy))),
            ),
          ),
        ),
      );
    });
  }
}

class _BoardPainter extends CustomPainter {
  final List<Map<String, dynamic>> tiles;
  final int minX, minY;
  final List<(int, int)> legal;
  final (int, int)? sel;
  final String? cur;
  final int rot, last;
  final List<Map<String, dynamic>> meeples;
  final List<(int, Offset, FeatureKind)> spots;
  final Color accent;
  final Offset origin;
  _BoardPainter({
    required this.tiles,
    required this.minX,
    required this.minY,
    required this.legal,
    required this.sel,
    required this.cur,
    required this.rot,
    required this.last,
    required this.meeples,
    required this.spots,
    required this.accent,
    this.origin = Offset.zero,
  });

  _BoardPainter withOffset(Offset o) => _BoardPainter(
      tiles: tiles, minX: minX, minY: minY, legal: legal, sel: sel, cur: cur, rot: rot, last: last, meeples: meeples, spots: spots, accent: accent, origin: o);

  Rect _cellRect(int x, int y) => Rect.fromLTWH(origin.dx + (x - minX) * _cell, origin.dy + (y - minY) * _cell, _cell, _cell);

  @override
  void paint(Canvas canvas, Size size) {
    // subtle grid
    final grid = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    for (var x = origin.dx % _cell; x < size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = origin.dy % _cell; y < size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    // shadows then tiles
    for (final t in tiles) {
      final r = _cellRect(eInt(t['x']), eInt(t['y']));
      canvas.drawRect(r.shift(const Offset(2, 3)), Paint()..color = const Color(0x44000000));
    }
    for (final t in tiles) {
      final tt = carcType(t['t'] as String?);
      if (tt == null) continue;
      paintCarcTile(canvas, _cellRect(eInt(t['x']), eInt(t['y'])), tt, eInt(t['r']));
    }
    // last placed
    if (last >= 0 && last < tiles.length) {
      final r = _cellRect(eInt(tiles[last]['x']), eInt(tiles[last]['y']));
      canvas.drawRect(
          r.deflate(1.5),
          Paint()
            ..color = const Color(0xFFFFE066)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    // legal cells
    for (final (x, y) in legal) {
      final r = _cellRect(x, y).deflate(4);
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(6)), Paint()..color = const Color(0x4432D26A));
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(6)),
          Paint()
            ..color = const Color(0xCC32D26A)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    // preview
    final ct = carcType(cur);
    if (sel != null && ct != null) {
      final r = _cellRect(sel!.$1, sel!.$2);
      paintCarcTile(canvas, r, ct, rot, opacity: 0.88);
      canvas.drawRect(
          r.deflate(1),
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    // meeples
    for (final m in meeples) {
      final ti = eInt(m['tile'], -1);
      if (ti < 0 || ti >= tiles.length) continue;
      final t = tiles[ti];
      final tt = carcType(t['t'] as String?);
      if (tt == null) continue;
      final fs = tt.featuresAt(eInt(t['r']));
      final f = eInt(m['f']);
      if (f < 0 || f >= fs.length) continue;
      final r = _cellRect(eInt(t['x']), eInt(t['y']));
      final c = Offset(r.left + fs[f].ax * _cell, r.top + fs[f].ay * _cell);
      paintMeeple(canvas, c, _cell * 0.3, meepleColor(eInt(m['s'])), lying: m['k'] == 'field');
    }
    // meeple spots
    for (final (_, o, k) in spots) {
      final c = origin + o;
      canvas.drawCircle(c, _cell * 0.13, Paint()..color = Colors.white.withValues(alpha: 0.85));
      canvas.drawCircle(
          c,
          _cell * 0.13,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5);
      final label = switch (k) { FeatureKind.city => '城', FeatureKind.road => '路', FeatureKind.field => '田', FeatureKind.cloister => '寺' };
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: _cell * 0.15, color: Colors.black87, fontWeight: FontWeight.bold, fontFamilyFallback: kFontFallback)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
