import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'x_common.dart';

const kdColors = [
  Color(0xFFE8C547), // 麦田
  Color(0xFF2F7A3A), // 森林
  Color(0xFF3C83C9), // 湖泊
  Color(0xFF8BC85A), // 草地
  Color(0xFF8A7B4F), // 沼泽
  Color(0xFF5E5A5C), // 矿山
  Color(0xFFBFA980), // 城堡
];
const kdNames = ['麦田', '森林', '湖泊', '草地', '沼泽', '矿山', '城堡'];
const _dirs = [(1, 0), (0, 1), (-1, 0), (0, -1)];

void _paintSquare(Canvas canvas, Rect r, int t, int crowns, {bool dim = false}) {
  if (t < 0) return;
  final base = kdColors[t.clamp(0, 6)];
  final rr = RRect.fromRectAndRadius(r.deflate(r.width * 0.03), Radius.circular(r.width * 0.12));
  canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
          Color.lerp(base, Colors.white, 0.18)!,
          Color.lerp(base, Colors.black, 0.18)!,
        ]).createShader(r));
  final w = r.width;
  final deco = Paint()
    ..color = Colors.black.withValues(alpha: 0.18)
    ..strokeWidth = max(0.8, w * 0.04)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  switch (t) {
    case 0: // wheat stalks
      for (var k = 0; k < 3; k++) {
        final x = r.left + w * (0.28 + k * 0.22);
        canvas.drawLine(Offset(x, r.top + w * 0.3), Offset(x, r.bottom - w * 0.18), deco);
        canvas.drawLine(Offset(x, r.top + w * 0.4), Offset(x - w * 0.06, r.top + w * 0.3), deco);
        canvas.drawLine(Offset(x, r.top + w * 0.4), Offset(x + w * 0.06, r.top + w * 0.3), deco);
      }
    case 1: // trees
      final f = Paint()..color = const Color(0xFF1C5424);
      for (final (dx, dy) in const [(0.3, 0.45), (0.68, 0.38), (0.5, 0.7)]) {
        final c = Offset(r.left + w * dx, r.top + w * dy);
        final p = Path()
          ..moveTo(c.dx, c.dy - w * 0.17)
          ..lineTo(c.dx + w * 0.12, c.dy + w * 0.1)
          ..lineTo(c.dx - w * 0.12, c.dy + w * 0.1)
          ..close();
        canvas.drawPath(p, f);
      }
    case 2: // waves
      final wv = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = max(0.8, w * 0.04)
        ..style = PaintingStyle.stroke;
      for (var k = 0; k < 2; k++) {
        final y = r.top + w * (0.45 + k * 0.2);
        final p = Path()..moveTo(r.left + w * 0.2, y);
        p.quadraticBezierTo(r.left + w * 0.35, y - w * 0.08, r.left + w * 0.5, y);
        p.quadraticBezierTo(r.left + w * 0.65, y + w * 0.08, r.left + w * 0.8, y);
        canvas.drawPath(p, wv);
      }
    case 3: // grass tufts
      for (final (dx, dy) in const [(0.3, 0.6), (0.65, 0.5), (0.5, 0.8)]) {
        final c = Offset(r.left + w * dx, r.top + w * dy);
        canvas.drawLine(c, c + Offset(-w * 0.06, -w * 0.12), deco);
        canvas.drawLine(c, c + Offset(0, -w * 0.14), deco);
        canvas.drawLine(c, c + Offset(w * 0.06, -w * 0.12), deco);
      }
    case 4: // swamp reeds / puddles
      canvas.drawOval(Rect.fromCenter(center: Offset(r.left + w * 0.4, r.top + w * 0.68), width: w * 0.36, height: w * 0.14),
          Paint()..color = const Color(0xFF4F6B5E).withValues(alpha: 0.6));
      canvas.drawLine(Offset(r.left + w * 0.7, r.bottom - w * 0.2), Offset(r.left + w * 0.7, r.top + w * 0.35), deco);
      canvas.drawOval(Rect.fromCenter(center: Offset(r.left + w * 0.7, r.top + w * 0.38), width: w * 0.07, height: w * 0.16),
          Paint()..color = const Color(0xFF5B3B1E));
    case 5: // mountains
      final m = Path()
        ..moveTo(r.left + w * 0.12, r.bottom - w * 0.18)
        ..lineTo(r.left + w * 0.42, r.top + w * 0.35)
        ..lineTo(r.left + w * 0.58, r.top + w * 0.55)
        ..lineTo(r.left + w * 0.7, r.top + w * 0.42)
        ..lineTo(r.left + w * 0.9, r.bottom - w * 0.18)
        ..close();
      canvas.drawPath(m, Paint()..color = const Color(0xFF3B3739));
    case 6: // castle
      final cp = Paint()..color = const Color(0xFF8C7A5A);
      final b = Rect.fromLTRB(r.left + w * 0.2, r.top + w * 0.42, r.right - w * 0.2, r.bottom - w * 0.18);
      canvas.drawRect(b, cp);
      for (var k = 0; k < 3; k++) {
        canvas.drawRect(Rect.fromLTWH(b.left + k * b.width * 0.4, r.top + w * 0.28, b.width * 0.2, w * 0.16), cp);
      }
      canvas.drawRect(Rect.fromLTWH(r.left + w * 0.44, r.top + w * 0.6, w * 0.12, w * 0.22), Paint()..color = const Color(0xFF3E2F1E));
  }
  if (crowns > 0) {
    final cw = w * 0.2;
    final total = crowns * cw + (crowns - 1) * w * 0.04;
    for (var k = 0; k < crowns; k++) {
      final x = r.center.dx - total / 2 + k * (cw + w * 0.04);
      final y = r.top + w * 0.08;
      final p = Path()
        ..moveTo(x, y + cw * 0.9)
        ..lineTo(x, y + cw * 0.2)
        ..lineTo(x + cw * 0.25, y + cw * 0.5)
        ..lineTo(x + cw * 0.5, y)
        ..lineTo(x + cw * 0.75, y + cw * 0.5)
        ..lineTo(x + cw, y + cw * 0.2)
        ..lineTo(x + cw, y + cw * 0.9)
        ..close();
      canvas.drawPath(p, Paint()..color = const Color(0xFFFFD84A));
      canvas.drawPath(
          p,
          Paint()
            ..color = const Color(0xFF7A5A00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(0.6, w * 0.02));
    }
  }
  if (dim) canvas.drawRRect(rr, Paint()..color = Colors.black.withValues(alpha: 0.4));
}

/// A domino tile (two squares) with its number on the back corner.
class KdDomino extends StatelessWidget {
  final List<int> d; // [ta, ca, tb, cb]
  final int number;
  final double cell;
  final bool selected, dim;
  final Widget? badge;
  final VoidCallback? onTap;
  const KdDomino(this.d, this.number, {super.key, this.cell = 30, this.selected = false, this.dim = false, this.badge, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE066) : const Color(0xFF4A3B2A),
          borderRadius: BorderRadius.circular(cell * 0.16),
          boxShadow: [BoxShadow(blurRadius: selected ? 8 : 3, color: selected ? const Color(0xAAFFE066) : Colors.black45, offset: const Offset(1, 2))],
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          CustomPaint(size: Size(cell * 2, cell), painter: _DomPainter(d, dim)),
          Positioned(
            left: 1,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
              child: Text('$number', style: TextStyle(fontSize: max(8, cell * 0.28), color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          if (badge != null) Positioned(right: -4, top: -6, child: badge!),
        ]),
      ),
    );
  }
}

class _DomPainter extends CustomPainter {
  final List<int> d;
  final bool dim;
  _DomPainter(this.d, this.dim);
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.height;
    _paintSquare(canvas, Rect.fromLTWH(0, 0, w, w), d[0], d[1], dim: dim);
    _paintSquare(canvas, Rect.fromLTWH(w, 0, w, w), d[2], d[3], dim: dim);
  }

  @override
  bool shouldRepaint(_DomPainter o) => o.d.join() != d.join() || o.dim != dim;
}

/// Kingdom grid painter over a window of the 13×13 grid.
class _KingdomPainter extends CustomPainter {
  final List<List<int>> t, c;
  final int x0, y0, n, size;
  final List<int> box;
  final Set<int> anchors;
  final (int, int, int)? preview;
  final List<int>? previewDom;
  final (int, int, int)? lastPlaced;
  final Color accent;
  _KingdomPainter(this.t, this.c, this.x0, this.y0, this.n, this.size, this.box, this.anchors, this.preview, this.previewDom, this.lastPlaced, this.accent);

  @override
  void paint(Canvas canvas, Size s) {
    final cell = s.width / n;
    // allowed region
    final ax0 = box[2] - size + 1, ax1 = box[0] + size - 1, ay0 = box[3] - size + 1, ay1 = box[1] + size - 1;
    final bg = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(cell * 0.2));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFF6B5638));
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final gx = x0 + i, gy = y0 + j;
        final r = Rect.fromLTWH(i * cell, j * cell, cell, cell);
        final inside = gx >= ax0 && gx <= ax1 && gy >= ay0 && gy <= ay1;
        final tv = gy >= 0 && gy < t.length && gx >= 0 && gx < t[gy].length ? t[gy][gx] : -1;
        if (tv >= 0) {
          _paintSquare(canvas, r, tv, c[gy][gx]);
        } else {
          canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(cell * 0.06), Radius.circular(cell * 0.12)),
              Paint()..color = inside ? const Color(0xFF8E7650) : const Color(0xFF4E3E28));
        }
        if (anchors.contains(gy * 13 + gx)) {
          canvas.drawRRect(
              RRect.fromRectAndRadius(r.deflate(cell * 0.1), Radius.circular(cell * 0.12)),
              Paint()
                ..color = accent.withValues(alpha: 0.85)
                ..style = PaintingStyle.stroke
                ..strokeWidth = max(1.2, cell * 0.06));
        }
      }
    }
    void outline((int, int, int) m, Color col, double wd) {
      final x2 = m.$1 + _dirs[m.$3].$1, y2 = m.$2 + _dirs[m.$3].$2;
      final l = min(m.$1, x2) - x0, tp = min(m.$2, y2) - y0;
      final w = (m.$1 - x2).abs() + 1, h = (m.$2 - y2).abs() + 1;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(l * cell, tp * cell, w * cell, h * cell).deflate(1), Radius.circular(cell * 0.14)),
          Paint()
            ..color = col
            ..style = PaintingStyle.stroke
            ..strokeWidth = wd);
    }

    if (lastPlaced != null) outline(lastPlaced!, const Color(0xFFFFE066), max(1.5, cell * 0.07));
    if (preview != null && previewDom != null) {
      final m = preview!;
      final x2 = m.$1 + _dirs[m.$3].$1, y2 = m.$2 + _dirs[m.$3].$2;
      canvas.saveLayer(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: 0.85));
      _paintSquare(canvas, Rect.fromLTWH((m.$1 - x0) * cell, (m.$2 - y0) * cell, cell, cell), previewDom![0], previewDom![1]);
      _paintSquare(canvas, Rect.fromLTWH((x2 - x0) * cell, (y2 - y0) * cell, cell, cell), previewDom![2], previewDom![3]);
      canvas.restore();
      outline(m, Colors.white, max(2, cell * 0.09));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class KingdominoBoard extends StatefulWidget {
  final GameContext g;
  const KingdominoBoard(this.g, {super.key});
  @override
  State<KingdominoBoard> createState() => _KingdominoBoardState();
}

class _KingdominoBoardState extends State<KingdominoBoard> {
  (int, int)? anchor;
  int dirIdx = 0;
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final actor = xInt(v['actor']);
    final me = g.seat;
    final myTurn = !over && actor == me && me >= 0 && !g.replay;
    final size = xInt(v['size'], 5);
    final doms = xList<dynamic>(v['dominoes']).map(xInts).toList();
    final cur = xList<dynamic>(v['cur']).map(xMap).toList();
    final next = xList<dynamic>(v['next']).map(xMap).toList();
    final ci = xInt(v['ci'], -1);
    final ps = xList<dynamic>(v['players']).map(xMap).toList();
    final legal = [for (final l in xList<dynamic>(v['legal'])) xInts(l)].map((l) => (l[0], l[1], l[2])).toList();
    final last = xMap(v['last']);
    final k = '$phase/$actor/${xInt(v['round'])}/$ci/${next.map((e) => e['king']).join()}';
    if (k != key) {
      key = k;
      anchor = null;
      dirIdx = 0;
    }
    final placing = myTurn && phase == 'place';
    final curDomId = ci >= 0 && ci < cur.length ? xInt(cur[ci]['dom']) : -1;
    final anchorSet = <int>{for (final m in legal) m.$2 * 13 + m.$1};
    final anchorDirs = anchor == null ? const <int>[] : [for (final m in legal) if (m.$1 == anchor!.$1 && m.$2 == anchor!.$2) m.$3];
    final preview = anchor != null && anchorDirs.isNotEmpty ? (anchor!.$1, anchor!.$2, anchorDirs[dirIdx % anchorDirs.length]) : null;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (phase == 'pick') {
      status = myTurn ? '轮到你：在右侧“下一排”选择一块骨牌' : '等待 ${g.name(actor)} 选择骨牌';
    } else {
      status = myTurn
          ? (legal.isEmpty ? '${curDomId + 1} 号骨牌无处可放，只能弃掉' : (preview == null ? '轮到你：点亮框格子放置 ${curDomId + 1} 号骨牌' : '点“旋转”换方向，点“确定”放置'))
          : '等待 ${g.name(actor)} 放置骨牌';
    }

    Widget king(int s, {double sz = 16}) => Container(
          width: sz,
          height: sz,
          decoration: BoxDecoration(
            color: seatColor(s),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black45)],
          ),
          child: Icon(Icons.person, size: sz * 0.75, color: Colors.white),
        );

    Widget rowColumn(String title, List<Map<String, dynamic>> row, double cell, {required bool isNext}) => XPanel(
          padding: const EdgeInsets.all(5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 3),
            if (row.isEmpty) Text('—', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
            for (var i = 0; i < row.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Builder(builder: (_) {
                  final d = xInt(row[i]['dom']);
                  final kg = xInt(row[i]['king'], -1);
                  final canPick = isNext && myTurn && phase == 'pick' && kg == -1;
                  final done = !isNext && row[i]['done'] == true;
                  final active = !isNext && i == ci && phase == 'place';
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: active ? cs.primary : (canPick ? cs.primary.withValues(alpha: 0.6) : Colors.transparent), width: 2),
                    ),
                    child: KdDomino(doms[d], d + 1,
                        cell: cell,
                        dim: done,
                        selected: active,
                        badge: kg >= 0 ? king(kg, sz: cell * 0.55) : null,
                        onTap: canPick ? () => g.act({'type': 'pick', 'i': i}) : null),
                  );
                }),
              ),
          ]),
        );

    Widget kingdom(int s, double px, {bool mine = false}) {
      final p = ps[s];
      final t = xList<dynamic>(p['t']).map(xInts).toList();
      final c = xList<dynamic>(p['c']).map(xInts).toList();
      final box = xInts(p['box']);
      final n = 2 * size - 1;
      final x0 = 6 - (size - 1), y0 = 6 - (size - 1);
      final lp = last['type'] == 'place' && xInt(last['seat']) == s ? (xInt(last['x']), xInt(last['y']), xInt(last['dir'])) : null;
      final cell = px / n;
      final painter = _KingdomPainter(t, c, x0, y0, n, size, box, mine && placing ? anchorSet : const {}, mine ? preview : null,
          mine && curDomId >= 0 ? doms[curDomId] : null, lp, cs.primary);
      final active = !over && actor == s;
      return XPanel(
        highlight: active,
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          g.tag(s, active: active, size: mine ? 26 : 20, sub: '${xInt(p['score'])} 分${xInt(p['discarded']) > 0 ? ' · 弃${xInt(p['discarded'])}' : ''}'),
          const SizedBox(height: 3),
          GestureDetector(
            onTapUp: mine && placing
                ? (d) {
                    final gx = x0 + (d.localPosition.dx / cell).floor(), gy = y0 + (d.localPosition.dy / cell).floor();
                    if (anchorSet.contains(gy * 13 + gx)) {
                      setState(() {
                        if (anchor == (gx, gy)) {
                          dirIdx++;
                        } else {
                          anchor = (gx, gy);
                          dirIdx = 0;
                        }
                      });
                    }
                  }
                : null,
            child: CustomPaint(size: Size(px, px), painter: painter),
          ),
        ]),
      );
    }

    Widget actions() {
      if (!placing) return const SizedBox.shrink();
      return Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
        if (legal.isEmpty) XButton('弃掉骨牌', icon: Icons.delete_outline, onTap: () => g.act({'type': 'discard'})),
        if (preview != null) ...[
          XButton('旋转', icon: Icons.rotate_right, primary: false, onTap: anchorDirs.length > 1 ? () => setState(() => dirIdx++) : null),
          XButton('确定', icon: Icons.check, onTap: () => g.act({'type': 'place', 'x': preview.$1, 'y': preview.$2, 'dir': preview.$3})),
        ],
      ]);
    }

    final result = xList<dynamic>(v['result']).map(xMap).toList();
    final pl = xInts(v['placings']);
    Widget? banner;
    if (over) {
      final winners = [for (var s = 0; s < pl.length; s++) if (pl[s] == 1) g.name(s)];
      final title = xInt(v['resigned'], -1) >= 0 ? '${g.name(xInt(v['resigned']))} 认输，${winners.join('、')} 获胜' : '${winners.join('、')} 获胜！';
      banner = ResultBanner(title,
          child: result.isEmpty
              ? null
              : scoreTable(context, ['玩家', '领地', if (v['middle'] == true) '中央', if (v['harmony'] == true) '和谐', '总分', '最大领地', '皇冠'], [
                  for (final r in result)
                    [
                      g.name(xInt(r['seat'])),
                      '${xInt(r['base'])}',
                      if (v['middle'] == true) '+${xInt(r['middle'])}',
                      if (v['harmony'] == true) '+${xInt(r['harmony'])}',
                      '${xInt(r['score'])}',
                      '${xInt(r['largest'])}',
                      '${xInt(r['crowns'])}',
                    ]
                ], bold: [for (var i = 0; i < result.length; i++) if (pl.elementAtOrNull(xInt(result[i]['seat'])) == 1) i]));
    }

    final order = g.seatsFromMe();
    final others = me >= 0 ? order.skip(1).toList() : order;
    final log = XPanel(child: XLog(xList<String>(v['recent']), max: 4));
    final info = Text('牌堆剩 ${xInt(v['deck'])} 块 · 王国 $size×$size', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.75)));

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.1;
      if (wide) {
        final rowCell = min(30.0, (c.maxHeight - 80) / (next.length.clamp(3, 4) * 1.25 + 1));
        final mainPx = min(c.maxHeight - 90, c.maxWidth * 0.36);
        final sideW = c.maxWidth - mainPx - rowCell * 4.6 * 2 - 50;
        final otherPx = min(mainPx * 0.55, max(90.0, min(sideW - 12, (c.maxHeight - 60) / max(1, others.length) - 40)));
        return Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  StatusBar(status, highlight: myTurn),
                  const SizedBox(height: 6),
                  if (me >= 0) kingdom(me, mainPx, mine: true) else kingdom(others.first, mainPx),
                  const SizedBox(height: 4),
                  actions(),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  rowColumn('当前排', cur, rowCell, isNext: false),
                  const SizedBox(width: 4),
                  rowColumn('下一排', next, rowCell, isNext: true),
                ]),
                const SizedBox(height: 4),
                info,
              ]),
            ),
            SizedBox(
              width: max(100, sideW),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
                    for (final s in (me >= 0 ? others : others.skip(1))) kingdom(s, otherPx),
                  ]),
                  const SizedBox(height: 6),
                  log,
                ]),
              ),
            ),
          ]),
          if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
        ]);
      }
      final mainPx = min(c.maxWidth - 24, 380.0);
      final otherPx = min(150.0, (c.maxWidth - 12) / min(3, max(1, others.length)) - 16);
      final rowCell = min(28.0, (c.maxWidth - 40) / 9.5);
      return Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (final s in (me >= 0 ? others : others.skip(1))) kingdom(s, otherPx),
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              rowColumn('当前排', cur, rowCell, isNext: false),
              const SizedBox(width: 6),
              rowColumn('下一排', next, rowCell, isNext: true),
            ]),
            info,
            const SizedBox(height: 4),
            if (me >= 0) kingdom(me, mainPx, mine: true) else kingdom(others.first, mainPx),
            const SizedBox(height: 4),
            actions(),
            const SizedBox(height: 4),
            log,
          ]),
        ),
        if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
      ]);
    });
  }
}
