import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'x_common.dart';

const _tileCols = [Color(0xFF2D6CC0), Color(0xFFF2C12E), Color(0xFFD9453B), Color(0xFF2B2B33), Color(0xFFEDEBE3)];
const _tileNames = ['蓝', '黄', '红', '黑', '白'];

/// One Azul tile (colour 0..4, 5 = first player token). [ghost] draws the
/// faint wall print.
class AzulTile extends StatelessWidget {
  final int c;
  final double size;
  final bool ghost, selected, glow, dim;
  const AzulTile(this.c, {super.key, this.size = 24, this.ghost = false, this.selected = false, this.glow = false, this.dim = false});

  @override
  Widget build(BuildContext context) {
    if (c == 5) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF4D6),
          borderRadius: BorderRadius.circular(size * 0.18),
          border: Border.all(color: const Color(0xFF9C7A2B), width: 1.2),
          boxShadow: const [BoxShadow(blurRadius: 2, color: Colors.black38, offset: Offset(0.5, 1))],
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('1', style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w900, color: const Color(0xFF7A5A12))),
        ),
      );
    }
    final base = c >= 0 && c < 5 ? _tileCols[c] : Colors.grey;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: size,
      height: size,
      transform: Matrix4.translationValues(0, selected ? -size * 0.12 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.16),
        border: Border.all(
            color: selected ? Colors.white : (glow ? const Color(0xFFFFE066) : Colors.black.withValues(alpha: ghost ? 0.1 : 0.35)),
            width: selected || glow ? 2 : 0.8),
        boxShadow: ghost ? null : [BoxShadow(blurRadius: selected || glow ? 6 : 2, color: glow ? const Color(0xAAFFE066) : Colors.black38, offset: const Offset(0.5, 1))],
      ),
      child: Opacity(
        opacity: ghost ? 0.28 : (dim ? 0.45 : 1),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.14),
          child: CustomPaint(painter: _TilePainter(c, base)),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  final int c;
  final Color base;
  _TilePainter(this.c, this.base);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
            Color.lerp(base, Colors.white, 0.25)!,
            base,
            Color.lerp(base, Colors.black, 0.25)!,
          ]).createShader(r));
    final accent = switch (c) {
      0 => Colors.white.withValues(alpha: 0.55),
      1 => const Color(0xFFB0441E).withValues(alpha: 0.6),
      2 => const Color(0xFFFFD58A).withValues(alpha: 0.65),
      3 => const Color(0xFF7DC7E8).withValues(alpha: 0.6),
      _ => const Color(0xFF2D6CC0).withValues(alpha: 0.6),
    };
    final p = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, s.width * 0.06);
    final cx = s.width / 2, cy = s.height / 2, w = s.width;
    switch (c) {
      case 0: // blue: 4-petal flower
        for (var k = 0; k < 4; k++) {
          final a = k * pi / 2;
          canvas.drawCircle(Offset(cx + cos(a) * w * 0.18, cy + sin(a) * w * 0.18), w * 0.14, p);
        }
      case 1: // yellow: diamond with dot
        final d = Path()
          ..moveTo(cx, cy - w * 0.32)
          ..lineTo(cx + w * 0.32, cy)
          ..lineTo(cx, cy + w * 0.32)
          ..lineTo(cx - w * 0.32, cy)
          ..close();
        canvas.drawPath(d, p);
        canvas.drawCircle(Offset(cx, cy), w * 0.07, Paint()..color = accent);
      case 2: // red: star
        final st = Path();
        for (var k = 0; k < 8; k++) {
          final rr = k.isEven ? w * 0.34 : w * 0.14;
          final a = k * pi / 4 - pi / 2;
          final pt = Offset(cx + cos(a) * rr, cy + sin(a) * rr);
          k == 0 ? st.moveTo(pt.dx, pt.dy) : st.lineTo(pt.dx, pt.dy);
        }
        st.close();
        canvas.drawPath(st, p);
      case 3: // black: nested squares
        canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: w * 0.56, height: w * 0.56), p);
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(pi / 4);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w * 0.36, height: w * 0.36), p);
        canvas.restore();
      default: // white: blue ring + cross
        canvas.drawCircle(Offset(cx, cy), w * 0.28, p);
        canvas.drawLine(Offset(cx - w * 0.2, cy), Offset(cx + w * 0.2, cy), p);
        canvas.drawLine(Offset(cx, cy - w * 0.2), Offset(cx, cy + w * 0.2), p);
    }
  }

  @override
  bool shouldRepaint(_TilePainter o) => o.c != c;
}

class AzulBoard extends StatefulWidget {
  final GameContext g;
  const AzulBoard(this.g, {super.key});
  @override
  State<AzulBoard> createState() => _AzulBoardState();
}

class _AzulBoardState extends State<AzulBoard> {
  int? selSrc; // -1 centre
  int? selColor;
  String key = '';

  static const _floorPen = [-1, -1, -2, -2, -2, -3, -3];

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = xInt(v['turn']);
    final grey = v['grey'] == true;
    final factories = xList<dynamic>(v['factories']).map(xInts).toList();
    final center = xInts(v['center']);
    final tokenIn = v['token'] == true;
    final ps = xList<dynamic>(v['players']).map(xMap).toList();
    final me = g.seat;
    final myDraft = !over && phase == 'draft' && turn == me && !g.replay;
    final myPending = me >= 0 && me < ps.length ? xInt(ps[me]['pending'], -1) : -1;
    final myTile = !over && phase == 'tile' && myPending >= 0 && !g.replay;
    final k = '$phase/${xInt(v['round'])}/$turn/${center.length}/${factories.map((f) => f.length).join()}';
    if (k != key) {
      key = k;
      selSrc = null;
      selColor = null;
    }

    String status;
    if (over) {
      status = '游戏结束';
    } else if (phase == 'tile') {
      status = myTile ? '铺砖：为第 ${myPending + 1} 行选择墙上的列' : '等待其他玩家铺砖';
    } else if (myDraft) {
      status = selColor == null ? '轮到你：点工厂或中央的一种颜色' : '把 ${_tileNames[selColor!]} 砖放到哪一行？（或放地板）';
    } else {
      status = '等待 ${g.name(turn)} 选砖';
    }
    status = '第 ${xInt(v['round'])} 轮 · $status';

    bool lineOk(Map<String, dynamic> p, int r, int c) {
      final lc = xInts(p['lineColor']), ln = xInts(p['lineCount']);
      final wall = xList<dynamic>(p['wall']).map(xInts).toList();
      if (ln[r] >= r + 1) return false;
      if (lc[r] != -1 && lc[r] != c) return false;
      if (r < wall.length && wall[r].contains(c)) return false;
      return true;
    }

    void pick(int src, int c) {
      if (!myDraft) return;
      setState(() {
        if (selSrc == src && selColor == c) {
          selSrc = null;
          selColor = null;
        } else {
          selSrc = src;
          selColor = c;
        }
      });
    }

    void place(int line) {
      if (!myDraft || selColor == null) return;
      g.act({'type': 'take', 'src': selSrc, 'color': selColor, 'line': line});
      setState(() {
        selSrc = null;
        selColor = null;
      });
    }

    Widget factory(int f, double t) {
      final tiles = factories[f];
      final active = myDraft && tiles.isNotEmpty;
      final d = t * 2.9;
      return Container(
        width: d,
        height: d,
        margin: EdgeInsets.all(t * 0.12),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFF8F1E4), Color(0xFFD9C9AA)]),
          border: Border.all(color: selSrc == f ? cs.primary : const Color(0xFF9C8660), width: selSrc == f ? 2.5 : 1.5),
          boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black38, offset: Offset(1, 2))],
        ),
        child: Center(
          child: tiles.isEmpty
              ? Text('${f + 1}', style: TextStyle(fontSize: t * 0.6, color: Colors.brown.withValues(alpha: 0.4), fontWeight: FontWeight.bold))
              : SizedBox(
                  width: t * 2.1,
                  child: Wrap(spacing: t * 0.1, runSpacing: t * 0.1, children: [
                    for (final c in tiles)
                      GestureDetector(
                        onTap: active ? () => pick(f, c) : null,
                        child: AzulTile(c, size: t, selected: selSrc == f && selColor == c),
                      ),
                  ]),
                ),
        ),
      );
    }

    Widget centerPool(double t) {
      final counts = <int, int>{};
      for (final c in center) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
      return XPanel(
        highlight: selSrc == -1,
        color: const Color(0xFFEFE4CC).withValues(alpha: 0.85),
        padding: EdgeInsets.all(t * 0.25),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('中央', style: TextStyle(fontSize: 11, color: Colors.brown.shade700, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Wrap(spacing: t * 0.3, runSpacing: t * 0.2, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (tokenIn) AzulTile(5, size: t),
            for (final e in counts.entries)
              GestureDetector(
                onTap: myDraft ? () => pick(-1, e.key) : null,
                child: Stack(clipBehavior: Clip.none, children: [
                  AzulTile(e.key, size: t, selected: selSrc == -1 && selColor == e.key),
                  if (e.value > 1)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                        child: Text('×${e.value}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ]),
              ),
            if (counts.isEmpty && !tokenIn) Text('（空）', style: TextStyle(fontSize: 11, color: Colors.brown.shade400)),
          ]),
        ]),
      );
    }

    Widget market(double t, double maxW) => Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: maxW,
            child: Wrap(alignment: WrapAlignment.center, children: [for (var f = 0; f < factories.length; f++) factory(f, t)]),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(constraints: BoxConstraints(maxWidth: maxW), child: centerPool(t)),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('袋中 ${xInt(v['bag'])} · 弃砖盒 ${xInt(v['lid'])}', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
        ]);

    Widget playerBoard(int s, double t, {bool mine = false}) {
      final p = ps[s];
      final wall = xList<dynamic>(p['wall']).map(xInts).toList();
      final lc = xInts(p['lineColor']), ln = xInts(p['lineCount']);
      final floor = xInts(p['floor']);
      final tiled = xList<dynamic>(p['tiled']).map(xMap).map((m) => xInt(m['r']) * 5 + xInt(m['c'])).toSet();
      final pending = xInt(p['pending'], -1);
      final greyCols = xInts(p['greyCols']).toSet();
      final canPlace = mine && myDraft && selColor != null;
      final gap = t * 0.1;
      Widget cellBox(Widget? child, {bool hl = false, bool on = false, VoidCallback? onTap}) => GestureDetector(
            onTap: onTap,
            child: Container(
              width: t,
              height: t,
              margin: EdgeInsets.all(gap / 2),
              decoration: BoxDecoration(
                color: on ? cs.primary.withValues(alpha: 0.28) : Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(t * 0.16),
                border: Border.all(color: hl ? cs.primary : Colors.black.withValues(alpha: 0.15), width: hl ? 2 : 0.8),
              ),
              child: child,
            ),
          );
      final lines = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var r = 0; r < 5; r++)
          Builder(builder: (_) {
            final ok = canPlace && lineOk(p, r, selColor!);
            return GestureDetector(
              onTap: ok ? () => place(r) : null,
              child: Container(
                decoration: BoxDecoration(
                  color: ok ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
                  borderRadius: BorderRadius.circular(t * 0.2),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = r; i >= 0; i--)
                    cellBox(i < ln[r] ? AzulTile(lc[r], size: t) : null, hl: ok || (pending == r && mine)),
                ]),
              ),
            );
          }),
      ]);
      final wallW = Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < 5; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var c = 0; c < 5; c++)
              Builder(builder: (_) {
                final placed = wall[r][c];
                final tgt = mine && myTile && pending == r && greyCols.contains(c);
                return cellBox(
                  placed >= 0
                      ? AzulTile(placed, size: t, glow: tiled.contains(r * 5 + c))
                      : (grey ? null : AzulTile((c - r + 5) % 5, size: t, ghost: true)),
                  hl: tgt,
                  on: tgt,
                  onTap: tgt ? () => g.act({'type': 'tile', 'col': c}) : null,
                );
              }),
          ]),
      ]);
      final floorOk = canPlace;
      final floorRow = GestureDetector(
        onTap: floorOk ? () => place(-1) : null,
        child: Container(
          decoration: BoxDecoration(
            color: floorOk ? Colors.redAccent.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(t * 0.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 7; i++)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${_floorPen[i]}', style: TextStyle(fontSize: max(8, t * 0.34), color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                cellBox(i < floor.length ? AzulTile(floor[i], size: t) : null, hl: floorOk),
              ]),
            if (floorOk)
              Padding(padding: const EdgeInsets.only(left: 4), child: Text('放地板', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.bold))),
          ]),
        ),
      );
      final active = !over && ((phase == 'draft' && turn == s) || (phase == 'tile' && pending >= 0));
      final sub = '${xInt(p['score'])} 分${xInt(v['firstNext']) == s && !tokenIn ? ' · 先手' : ''}';
      return XPanel(
        highlight: active,
        color: const Color(0xFFF3E9D6).withValues(alpha: 0.92),
        padding: EdgeInsets.all(max(3, t * 0.2)),
        child: Theme(
          data: Theme.of(context).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: cs.primary)),
          child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.black87), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            g.tag(s, active: active, size: max(18, min(30, t * 1.1)), sub: sub),
            SizedBox(height: gap),
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              lines,
              Container(width: 2, height: 5 * (t + gap), margin: EdgeInsets.symmetric(horizontal: t * 0.15), color: Colors.brown.withValues(alpha: 0.35)),
              wallW,
            ]),
            SizedBox(height: gap),
            floorRow,
          ])),
        ),
      );
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
              : scoreTable(context, const ['玩家', '横行', '竖列', '同色', '奖励', '总分'], [
                  for (final r in result)
                    [g.name(xInt(r['seat'])), '${xInt(r['rows'])}', '${xInt(r['cols'])}', '${xInt(r['colors'])}', '+${xInt(r['bonus'])}', '${xInt(r['score'])}']
                ], bold: [for (var i = 0; i < result.length; i++) if (pl.elementAtOrNull(xInt(result[i]['seat'])) == 1) i]));
    }

    final order = g.seatsFromMe();
    final others = me >= 0 ? order.skip(1).toList() : order;
    final log = XPanel(child: XLog(xList<String>(v['recent']), max: 4));

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.1;
      if (wide) {
        final leftW = c.maxWidth * 0.42;
        final ft = min(30.0, min(leftW / (min(factories.length, 5) * 3.3), c.maxHeight / 11));
        final rightW = c.maxWidth - leftW - 16;
        final myT = min(34.0, min(rightW / 11.8, (c.maxHeight - 40) / (others.isEmpty ? 8.6 : 12.5)));
        final otherT = min(18.0, (rightW / max(1, others.length)) / 12.5);
        return Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: leftW,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [StatusBar(status, highlight: myDraft || myTile), const SizedBox(height: 6), market(ft, leftW - 12), const SizedBox(height: 6), log]),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  if (me >= 0) FittedBox(fit: BoxFit.scaleDown, child: playerBoard(me, myT, mine: true)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final s in others) playerBoard(s, me >= 0 ? otherT : myT * 0.6)]),
                ]),
              ),
            ),
          ]),
          if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
        ]);
      }
      final ft = min(26.0, c.maxWidth / (min(factories.length, 5) * 3.3));
      final myT = min(32.0, (c.maxWidth - 30) / 11.8);
      final otherT = min(14.0, (c.maxWidth - 20) / (min(3, max(1, others.length)) * 12.6));
      return Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            StatusBar(status, highlight: myDraft || myTile),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [for (final s in others) playerBoard(s, me >= 0 ? otherT : myT * 0.8)]),
            const SizedBox(height: 4),
            market(ft, c.maxWidth - 8),
            const SizedBox(height: 4),
            if (me >= 0) FittedBox(fit: BoxFit.scaleDown, child: playerBoard(me, myT, mine: true)),
            const SizedBox(height: 4),
            log,
          ]),
        ),
        if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
      ]);
    });
  }
}
