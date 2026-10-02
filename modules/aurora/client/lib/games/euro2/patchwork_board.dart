import 'dart:math';

import 'package:aurora_shared/games/euro2/patchwork.dart' show pwOrient;
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'x_common.dart';

/// Fabric colour per patch id.
Color pwColor(int id) {
  if (id >= 100) return const Color(0xFF8B5A2B);
  const pal = [
    Color(0xFFE57373), Color(0xFF64B5F6), Color(0xFF81C784), Color(0xFFFFB74D), Color(0xFFBA68C8), Color(0xFF4DB6AC),
    Color(0xFFF06292), Color(0xFF9575CD), Color(0xFFAED581), Color(0xFFFF8A65), Color(0xFF4FC3F7), Color(0xFFDCE775),
  ];
  return pal[id % pal.length];
}

void _paintFabric(Canvas canvas, Rect r, int id, {bool ghost = false}) {
  final base = pwColor(id);
  final p = Paint()..color = ghost ? base.withValues(alpha: 0.55) : base;
  canvas.drawRect(r, p);
  final w = r.width;
  final pat = Paint()
    ..color = Colors.white.withValues(alpha: ghost ? 0.2 : 0.35)
    ..strokeWidth = max(0.6, w * 0.06);
  switch (id % 4) {
    case 0:
      canvas.drawLine(r.topLeft + Offset(w * 0.2, w * 0.2), r.bottomRight - Offset(w * 0.2, w * 0.2), pat);
    case 1:
      canvas.drawCircle(r.center, w * 0.16, pat);
    case 2:
      canvas.drawLine(Offset(r.left + w * 0.5, r.top + w * 0.15), Offset(r.left + w * 0.5, r.bottom - w * 0.15), pat);
    default:
      canvas.drawLine(Offset(r.left + w * 0.15, r.top + w * 0.5), Offset(r.right - w * 0.15, r.top + w * 0.5), pat);
  }
}

/// A patch shape preview with cost/time/income labels.
class PwPatchCard extends StatelessWidget {
  final int id;
  final Map<String, dynamic> info;
  final double cell;
  final bool selected, buyable, affordable;
  final VoidCallback? onTap;
  const PwPatchCard(this.id, this.info, {super.key, this.cell = 10, this.selected = false, this.buyable = false, this.affordable = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final rows = xList<String>(info['rows']);
    final h = rows.length, w = rows.fold(0, (m, r) => max(m, r.length));
    final side = max(h, w) * cell;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF3C4) : const Color(0xFFF7F0E1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? const Color(0xFFE0A100) : (buyable ? const Color(0xFF6D8B3A) : Colors.black12), width: selected || buyable ? 2 : 1),
          boxShadow: [BoxShadow(blurRadius: selected ? 6 : 2, color: Colors.black26, offset: const Offset(0.5, 1))],
        ),
        child: Opacity(
          opacity: buyable && !affordable ? 0.5 : 1,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: max(side, cell * 3),
              height: side,
              child: CustomPaint(painter: _ShapePainter(rows, id, cell)),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _chip('●${xInt(info['cost'])}', const Color(0xFF2F6BD8)),
                _chip('⌛${xInt(info['time'])}', const Color(0xFF8D6E63)),
                if (xInt(info['income']) > 0) _chip('+${xInt(info['income'])}', const Color(0xFF3DA84A)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
      );
}

class _ShapePainter extends CustomPainter {
  final List<String> rows;
  final int id;
  final double cell;
  _ShapePainter(this.rows, this.id, this.cell);
  @override
  void paint(Canvas canvas, Size s) {
    final w = rows.fold(0, (m, r) => max(m, r.length));
    final ox = (s.width - w * cell) / 2, oy = (s.height - rows.length * cell) / 2;
    final border = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] != 'X') continue;
        final r = Rect.fromLTWH(ox + x * cell, oy + y * cell, cell, cell);
        _paintFabric(canvas, r, id);
        canvas.drawRect(r, border);
      }
    }
  }

  @override
  bool shouldRepaint(_ShapePainter o) => o.id != id || o.cell != cell;
}

class _QuiltPainter extends CustomPainter {
  final List<int> b;
  final List<(int, int)>? preview;
  final int previewId;
  final bool previewOk;
  final Set<int> lastCells;
  _QuiltPainter(this.b, this.preview, this.previewId, this.previewOk, this.lastCells);

  @override
  void paint(Canvas canvas, Size s) {
    final cell = s.width / 9;
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(cell * 0.3)), Paint()..color = const Color(0xFFE9DFC8));
    final grid = Paint()
      ..color = const Color(0xFFB8A57E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 9; x++) {
        final r = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        final v = b[y * 9 + x];
        if (v != 0) {
          _paintFabric(canvas, r, v >= 100 ? 100 : v - 1);
          if (v >= 100) {
            canvas.drawCircle(r.center, cell * 0.12, Paint()..color = const Color(0xFFD7B98E));
          }
        }
        canvas.drawRect(r, grid);
      }
    }
    // patch boundaries: stronger line between different ids
    final edge = Paint()
      ..color = Colors.black54
      ..strokeWidth = max(1, cell * 0.06);
    for (var y = 0; y < 9; y++) {
      for (var x = 0; x < 9; x++) {
        final v = b[y * 9 + x];
        if (v == 0) continue;
        if (x == 8 || b[y * 9 + x + 1] != v || v >= 100) canvas.drawLine(Offset((x + 1) * cell, y * cell), Offset((x + 1) * cell, (y + 1) * cell), edge);
        if (x == 0 || b[y * 9 + x - 1] != v || v >= 100) canvas.drawLine(Offset(x * cell, y * cell), Offset(x * cell, (y + 1) * cell), edge);
        if (y == 8 || b[(y + 1) * 9 + x] != v || v >= 100) canvas.drawLine(Offset(x * cell, (y + 1) * cell), Offset((x + 1) * cell, (y + 1) * cell), edge);
        if (y == 0 || b[(y - 1) * 9 + x] != v || v >= 100) canvas.drawLine(Offset(x * cell, y * cell), Offset((x + 1) * cell, y * cell), edge);
      }
    }
    for (final i in lastCells) {
      final r = Rect.fromLTWH((i % 9) * cell, (i ~/ 9) * cell, cell, cell).deflate(cell * 0.08);
      canvas.drawRect(
          r,
          Paint()
            ..color = const Color(0xFFFFE066)
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.2, cell * 0.08));
    }
    if (preview != null) {
      for (final (x, y) in preview!) {
        if (x < 0 || y < 0 || x > 8 || y > 8) continue;
        final r = Rect.fromLTWH(x * cell, y * cell, cell, cell);
        _paintFabric(canvas, r, previewId, ghost: true);
        canvas.drawRect(
            r.deflate(1),
            Paint()
              ..color = previewOk ? Colors.white : Colors.redAccent
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1.5, cell * 0.08));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _TrackPainter extends CustomPainter {
  final List<int> pos, leather, income;
  final int end;
  final Color c0, c1;
  _TrackPainter(this.pos, this.leather, this.income, this.end, this.c0, this.c1);

  @override
  void paint(Canvas canvas, Size s) {
    // snake: rows of 9 cells, 6 rows (54 cells: 0..53)
    const perRow = 9;
    final rowsN = (end + 1 + perRow - 1) ~/ perRow;
    final cw = s.width / perRow, ch = s.height / rowsN;
    Offset centerOf(int i) {
      final r = i ~/ perRow, k = i % perRow;
      final x = r.isEven ? k : perRow - 1 - k;
      return Offset((x + 0.5) * cw, (r + 0.5) * ch);
    }

    final path = Path()..moveTo(centerOf(0).dx, centerOf(0).dy);
    for (var i = 1; i <= end; i++) {
      final c = centerOf(i);
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFB8A57E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = min(cw, ch) * 0.55
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    final rad = min(cw, ch) * 0.3;
    for (var i = 0; i <= end; i++) {
      final c = centerOf(i);
      canvas.drawCircle(c, rad, Paint()..color = i == end ? const Color(0xFF6D4C41) : const Color(0xFFF3EAD5));
      if (income.contains(i)) {
        canvas.drawCircle(c, rad * 0.75, Paint()..color = const Color(0xFF2F6BD8));
        canvas.drawCircle(c, rad * 0.18, Paint()..color = Colors.white);
      }
      if (leather.contains(i)) {
        canvas.drawRect(Rect.fromCenter(center: c, width: rad * 1.3, height: rad * 1.3), Paint()..color = const Color(0xFF8B5A2B));
      }
    }
    for (var s2 = 0; s2 < 2; s2++) {
      final c = centerOf(pos[s2].clamp(0, end)) + Offset(s2 == 0 ? -rad * 0.5 : rad * 0.5, -rad * 0.3);
      final col = s2 == 0 ? c0 : c1;
      canvas.drawCircle(c, rad * 0.7, Paint()..color = Colors.black38);
      canvas.drawCircle(c - const Offset(0.5, 0.5), rad * 0.66, Paint()..color = col);
      canvas.drawCircle(
          c - const Offset(0.5, 0.5),
          rad * 0.66,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class PatchworkBoard extends StatefulWidget {
  final GameContext g;
  const PatchworkBoard(this.g, {super.key});
  @override
  State<PatchworkBoard> createState() => _PatchworkBoardState();
}

class _PatchworkBoardState extends State<PatchworkBoard> {
  int? sel; // index 0..2 into available
  int rot = 0;
  bool flip = false;
  (int, int)? at;
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = xInt(v['turn']);
    final me = g.seat;
    final myTurn = !over && turn == me && me >= 0 && !g.replay;
    final ring = xInts(v['ring']);
    final np = xInt(v['np']);
    final avail = xInts(v['available']);
    final patches = xList<dynamic>(v['patches']).map(xMap).toList();
    final pos = xInts(v['pos']);
    final buttons = xInts(v['buttons']);
    final income = xInts(v['income']);
    final boards = xList<dynamic>(v['boards']).map(xInts).toList();
    final scores = xInts(v['scores']);
    final bonus7 = xInt(v['bonus7'], -1);
    final last = xMap(v['last']);
    final k = '$phase/$turn/${pos.join(',')}/${ring.length}';
    if (k != key) {
      key = k;
      sel = null;
      at = null;
      rot = 0;
      flip = false;
    }
    final leatherMode = myTurn && phase == 'leather';

    List<(int, int)>? previewCells;
    var previewOk = false;
    var previewId = 0;
    if (me >= 0 && at != null) {
      if (leatherMode) {
        previewCells = [at!];
        previewId = 100;
        previewOk = boards[me][at!.$2 * 9 + at!.$1] == 0;
      } else if (sel != null && sel! < avail.length) {
        previewId = avail[sel!];
        final cells = pwOrient(previewId, rot, flip);
        previewCells = [for (final (x, y) in cells) (at!.$1 + x, at!.$2 + y)];
        previewOk = previewCells.every((c) => c.$1 >= 0 && c.$2 >= 0 && c.$1 < 9 && c.$2 < 9 && boards[me][c.$2 * 9 + c.$1] == 0);
      }
    }

    String status;
    if (over) {
      status = '游戏结束';
    } else if (phase == 'leather') {
      status = myTurn ? '放置皮革补丁：点被子上任意空格' : '等待 ${g.name(turn)} 放置皮革补丁';
    } else if (myTurn) {
      status = sel == null ? '轮到你：选一块布片购买，或前进拿纽扣' : '点被子格子放置（左上角），可旋转/翻转';
    } else {
      status = '等待 ${g.name(turn)} 行动';
    }

    Widget quilt(int s, double px, {bool mine = false}) {
      final lastCells = <int>{};
      if (xInt(last['seat'], -1) == s) {
        if (last['type'] == 'buy') {
          for (final (x, y) in pwOrient(xInt(last['patch']), xInt(last['rot']), last['flip'] == true)) {
            lastCells.add((xInt(last['y']) + y) * 9 + xInt(last['x']) + x);
          }
        } else if (last['type'] == 'leather') {
          lastCells.add(xInt(last['y']) * 9 + xInt(last['x']));
        }
      }
      final active = !over && turn == s;
      return XPanel(
        highlight: active,
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          g.tag(s,
              active: active,
              size: mine ? 26 : 22,
              sub: '纽扣 ${buttons[s]} · 收入 ${income[s]} · 位置 ${pos[s]}${bonus7 == s ? ' · 7×7✓' : ''}',
              trailing: Container(width: 10, height: 10, decoration: BoxDecoration(color: seatColor(s), shape: BoxShape.circle))),
          const SizedBox(height: 3),
          GestureDetector(
            onTapUp: mine && (leatherMode || (myTurn && sel != null))
                ? (d) {
                    final cell = px / 9;
                    final x = (d.localPosition.dx / cell).floor().clamp(0, 8), y = (d.localPosition.dy / cell).floor().clamp(0, 8);
                    setState(() => at = (x, y));
                  }
                : null,
            child: CustomPaint(
              size: Size(px, px),
              painter: _QuiltPainter(boards[s], mine ? previewCells : null, previewId, previewOk, lastCells),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('当前得分 ${scores[s]}（纽扣 − 2×空格${bonus7 == s ? ' + 7' : ''}）', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.75))),
          ),
        ]),
      );
    }

    Widget market(double cell, double maxW) {
      final upcoming = [for (var i = 0; i < ring.length; i++) ring[(np + i) % ring.length]];
      return XPanel(
        padding: const EdgeInsets.all(5),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('可购买（中立标记前方 3 块）', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < avail.length; i++)
              PwPatchCard(avail[i], patches[avail[i]],
                  cell: cell,
                  buyable: true,
                  selected: sel == i,
                  affordable: me < 0 || xInt(patches[avail[i]]['cost']) <= (me >= 0 ? buttons[me] : 0),
                  onTap: myTurn && phase == 'turn'
                      ? () => setState(() {
                            sel = sel == i ? null : i;
                            at = null;
                            rot = 0;
                            flip = false;
                          })
                      : null),
          ]),
          const SizedBox(height: 4),
          Text('之后的布片', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.7))),
          SizedBox(
            width: maxW,
            height: cell * 0.6 * 5 + 24,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final id in upcoming.skip(3))
                Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: PwPatchCard(id, patches[id], cell: cell * 0.6)),
            ]),
          ),
        ]),
      );
    }

    Widget actions() {
      if (!myTurn) return const SizedBox.shrink();
      if (leatherMode) {
        return Wrap(spacing: 6, children: [
          XButton('放置皮革', icon: Icons.check, onTap: at != null && previewOk ? () => g.act({'type': 'leather', 'x': at!.$1, 'y': at!.$2}) : null),
        ]);
      }
      final gain = min(pos[1 - me] + 1, xInt(v['end'], 53)) - pos[me];
      final cost = sel != null && sel! < avail.length ? xInt(patches[avail[sel!]]['cost']) : 0;
      return Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
        if (sel != null) ...[
          XButton('旋转', icon: Icons.rotate_right, primary: false, onTap: () => setState(() => rot = (rot + 1) % 4)),
          XButton('翻转', icon: Icons.flip, primary: false, onTap: () => setState(() => flip = !flip)),
          XButton('购买放置 (●$cost)',
              icon: Icons.check,
              onTap: at != null && previewOk && cost <= buttons[me]
                  ? () => g.act({'type': 'buy', 'k': sel, 'x': at!.$1, 'y': at!.$2, 'rot': rot, 'flip': flip})
                  : null),
        ],
        XButton('前进 $gain 格 (+$gain●)', icon: Icons.fast_forward, primary: sel == null, onTap: () => g.act({'type': 'advance'})),
      ]);
    }

    Widget track(double w) => XPanel(
          padding: const EdgeInsets.all(4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('时间轨（蓝点=收入，棕块=皮革补丁）', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.75))),
            CustomPaint(
              size: Size(w, w * 6 / 9 * 0.7),
              painter: _TrackPainter(pos, xInts(v['leather']), xInts(v['incomeMarks']), xInt(v['end'], 53), seatColor(0), seatColor(1)),
            ),
          ]),
        );

    final result = xMap(v['result']);
    final pl = xInts(v['placings']);
    Widget? banner;
    if (over) {
      final w = pl.isNotEmpty && pl[0] == 1 ? 0 : 1;
      final rows = xList<dynamic>(result['rows']).map(xMap).toList();
      final title = xInt(v['resigned'], -1) >= 0 ? '${g.name(xInt(v['resigned']))} 认输，${g.name(w)} 获胜' : '${g.name(w)} 获胜！';
      banner = ResultBanner(title,
          child: rows.isEmpty
              ? null
              : scoreTable(context, const ['玩家', '纽扣', '空格', '7×7', '总分'], [
                  for (final r in rows)
                    [g.name(xInt(r['seat'])), '${xInt(r['buttons'])}', '-${xInt(r['empty']) * 2}', '+${xInt(r['bonus'])}', '${xInt(r['score'])}']
                ], bold: [w]));
    }

    final meS = me >= 0 ? me : 0;
    final oppS = 1 - meS;
    final log = XPanel(child: XLog(xList<String>(v['recent']), max: 4));

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.1;
      if (wide) {
        final qPx = min(c.maxHeight - 90, c.maxWidth * 0.3);
        final midW = c.maxWidth - qPx - 40 - qPx * 0.62;
        return Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(children: [quilt(meS, qPx, mine: me >= 0), const SizedBox(height: 4), actions()]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  StatusBar(status, highlight: myTurn),
                  const SizedBox(height: 4),
                  market(min(12.0, midW / 16), midW - 20),
                  const SizedBox(height: 4),
                  track(min(midW - 20, 360)),
                  const SizedBox(height: 4),
                  log,
                ]),
              ),
            ),
            SingleChildScrollView(padding: const EdgeInsets.all(6), child: quilt(oppS, qPx * 0.62)),
          ]),
          if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
        ]);
      }
      final qPx = min(c.maxWidth - 24, 340.0);
      return Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              quilt(oppS, min(130, c.maxWidth * 0.36)),
              const SizedBox(width: 4),
              Expanded(child: track(c.maxWidth * 0.55)),
            ]),
            const SizedBox(height: 4),
            market(min(11.0, c.maxWidth / 34), c.maxWidth - 24),
            const SizedBox(height: 4),
            actions(),
            const SizedBox(height: 4),
            quilt(meS, qPx, mine: me >= 0),
            const SizedBox(height: 4),
            log,
          ]),
        ),
        if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
      ]);
    });
  }
}
