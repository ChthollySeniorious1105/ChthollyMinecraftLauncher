import 'dart:async';
import 'dart:math' as math;

import 'package:aurora_shared/games/arcade/tetris.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';
import 'arcade_common.dart';

const _pieceColors = {
  'I': Color(0xFF26C6DA),
  'J': Color(0xFF3F51B5),
  'L': Color(0xFFFF9800),
  'O': Color(0xFFFDD835),
  'S': Color(0xFF66BB6A),
  'T': Color(0xFFAB47BC),
  'Z': Color(0xFFEF5350),
  'G': Color(0xFF78909C),
};

class TetrisBoard extends StatefulWidget {
  final GameContext g;
  const TetrisBoard(this.g, {super.key});
  @override
  State<TetrisBoard> createState() => _TetrisBoardState();
}

class _TetrisBoardState extends State<TetrisBoard> {
  final List<String> _buf = [];
  Timer? _flush;

  GameContext get g => widget.g;

  @override
  void dispose() {
    _flush?.cancel();
    super.dispose();
  }

  bool get _canPlay {
    final ps = aMaps(g.view['p']);
    return !g.over && g.seat >= 0 && g.seat < ps.length && ps[g.seat]['al'] == true && g.view['phase'] == 'play';
  }

  /// Batches key presses (≤ 1 message / 40 ms) to stay well under the
  /// server's rate limit while holding keys down.
  void _press(String k) {
    if (!_canPlay) return;
    if (_buf.length < 12) _buf.add(k);
    _flush ??= Timer(const Duration(milliseconds: 40), () {
      _flush = null;
      if (_buf.isEmpty || !mounted) return;
      final keys = List.of(_buf);
      _buf.clear();
      g.act({'type': 'input', 'keys': keys});
    });
  }

  bool _onKey(LogicalKeyboardKey k, bool repeat) {
    final m = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowLeft: 'left',
      LogicalKeyboardKey.arrowRight: 'right',
      LogicalKeyboardKey.arrowDown: 'soft',
      LogicalKeyboardKey.arrowUp: 'cw',
      LogicalKeyboardKey.keyX: 'cw',
      LogicalKeyboardKey.keyZ: 'ccw',
      LogicalKeyboardKey.controlLeft: 'ccw',
      LogicalKeyboardKey.keyA: 'r180',
      LogicalKeyboardKey.space: 'hard',
      LogicalKeyboardKey.keyC: 'hold',
      LogicalKeyboardKey.shiftLeft: 'hold',
      LogicalKeyboardKey.shiftRight: 'hold',
    };
    final a = m[k];
    if (a == null) return false;
    if (repeat && (a == 'hard' || a == 'hold' || a == 'cw' || a == 'ccw' || a == 'r180')) return true;
    _press(a);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final ps = aMaps(v['p']);
    final phase = aStr(v['phase']);
    final me = g.seat >= 0 && g.seat < ps.length ? g.seat : 0;
    final mine = ps.isEmpty ? null : ps[me];
    final tick = aInt(v['tick'], 0);
    final tps = aInt(v['tps'], 10);
    final alive = mine?['al'] == true;

    String status;
    var hl = false;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'countdown') {
      status = '准备… ${(aInt(v['cd'], 0) / tps).ceil()}';
      hl = true;
    } else {
      final el = aInt(v['el'], 0);
      final mult = (v['mult'] as num?)?.toDouble() ?? 1;
      final clock = '${mmss(el)}${mult > 1 ? ' · 垃圾 ×${mult.toStringAsFixed(2)}' : ''}';
      if (g.seat < 0) {
        status = '观战中 · $clock';
      } else if (!alive) {
        status = '你已出局，观战中 · $clock';
      } else {
        status = '← → 移动  ↑/X 顺转  Z 逆转  A 180°  ↓ 软降  空格 硬降  C 暂存 · $clock';
        hl = true;
      }
    }
    final others = [for (final s in g.seatsFromMe()) if (s != me && s < ps.length) s];

    return ArcadeKeys(
      onKey: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.15;
        final showPad = g.seat >= 0;
        final availH = box.maxHeight - 44 - (wide || !showPad ? 0 : 150);
        final availW = box.maxWidth - (wide && showPad ? 240 : 0);
        // my board: boardW × 2boardW, side panels 0.36 boardW each
        var bw = math.min(availH / 2.05, (availW * (others.isEmpty ? 1 : 0.62)) / 1.8);
        bw = bw.clamp(60.0, 360.0);
        final mini = math.min(availH / (wide ? 1 : 2.2), bw * 1.1).clamp(60.0, 330.0) / 2.2; // mini board width

        Widget myArea = mine == null ? const SizedBox() : _MyField(g, me, mine, tick, tps, bw);
        Widget othersArea = Wrap(
          direction: wide ? Axis.horizontal : Axis.vertical,
          spacing: 6,
          runSpacing: 6,
          children: [for (final s in others) _MiniField(g, s, ps[s], mini)],
        );
        Widget field = FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            myArea,
            if (others.isNotEmpty) const SizedBox(width: 10),
            if (others.isNotEmpty) ConstrainedBox(constraints: BoxConstraints(maxHeight: bw * 2.2, maxWidth: wide ? box.maxWidth * 0.5 : 400), child: othersArea),
          ]),
        );

        final pad = !showPad
            ? null
            : _Pad(onKey: _press, enabled: _canPlay, compact: wide);
        Widget body;
        if (wide && pad != null) {
          body = Row(children: [
            SizedBox(width: 118, child: Center(child: pad.left())),
            Expanded(child: Center(child: field)),
            SizedBox(width: 118, child: Center(child: pad.right())),
          ]);
        } else {
          body = Column(children: [
            Expanded(child: Center(child: field)),
            if (pad != null) SizedBox(height: 146, child: pad.bottom()),
          ]);
        }
        return Column(children: [
          SizedBox(height: 40, child: aStatus(status, highlight: hl)),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: body),
              if (phase == 'over')
                Positioned.fill(
                  child: Container(
                    color: Colors.black38,
                    child: aRanking(g, aMaps(v['final']), (r) => '${r['score']} 分 · ${r['lines']} 行 · 送 ${r['sent']} · KO ${r['kos'] ?? 0}'),
                  ),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

class _Pad {
  final void Function(String) onKey;
  final bool enabled;
  final bool compact;
  _Pad({required this.onKey, required this.enabled, required this.compact});

  VoidCallback? _f(String k) => enabled ? () => onKey(k) : null;

  Widget left() => Column(mainAxisSize: MainAxisSize.min, children: [
        PadButton(label: '暂存', onTap: _f('hold'), size: 46, color: Colors.teal),
        const SizedBox(height: 10),
        Row(mainAxisSize: MainAxisSize.min, children: [
          PadButton(icon: Icons.arrow_back, onTap: _f('left'), size: 52),
          const SizedBox(width: 6),
          PadButton(icon: Icons.arrow_forward, onTap: _f('right'), size: 52),
        ]),
        const SizedBox(height: 10),
        PadButton(icon: Icons.arrow_downward, onTap: _f('soft'), size: 52),
      ]);

  Widget right() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          PadButton(icon: Icons.rotate_left, onTap: _f('ccw'), size: 50),
          const SizedBox(width: 6),
          PadButton(icon: Icons.rotate_right, onTap: _f('cw'), size: 50),
        ]),
        const SizedBox(height: 8),
        PadButton(label: '180°', onTap: _f('r180'), size: 42, color: Colors.indigo),
        const SizedBox(height: 12),
        PadButton(label: '硬降', onTap: _f('hard'), size: 64, color: Colors.deepOrange),
      ]);

  Widget bottom() => FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [left(), const SizedBox(width: 40), right()]),
        ),
      );
}

class _MyField extends StatelessWidget {
  final GameContext g;
  final int seat;
  final Map<String, dynamic> p;
  final int tick, tps;
  final double bw;
  const _MyField(this.g, this.seat, this.p, this.tick, this.tps, this.bw);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final side = bw * 0.38;
    final nx = aStr(p['nx']);
    final ev = p['ev'] is Map ? (p['ev'] as Map).cast<String, dynamic>() : null;
    final recent = ev != null && tick - aInt(ev['k'], -999) < tps * 3 / 2;
    final pd = aInt(p['pd'], 0), ready = aInt(p['pr'], 0);
    TextStyle lbl() => TextStyle(fontSize: math.max(9, side * 0.2), color: cs.onSurface.withValues(alpha: 0.8), fontWeight: FontWeight.bold);
    Widget box(Widget c) => Container(
          width: side,
          padding: EdgeInsets.all(side * 0.06),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
          child: c,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(fit: BoxFit.scaleDown, child: g.tag(seat, size: 26, active: p['al'] == true && seat == g.seat, sub: '${p['sc']} 分')),
      const SizedBox(height: 4),
      Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          box(Column(children: [
            Text('暂存', style: lbl()),
            SizedBox(width: side * 0.8, height: side * 0.5, child: _PiecePreview(p['h'] as String?)),
          ])),
          SizedBox(height: side * 0.15),
          box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (k, val) in [('等级', p['lv']), ('行数', p['ln']), ('连击', p['cb']), ('B2B', p['b2b']), ('送出', p['st']), ('KO', p['ko'])])
              FittedBox(fit: BoxFit.scaleDown, child: Text('$k ${val ?? 0}', style: lbl())),
          ])),
          SizedBox(height: side * 0.15),
          if (recent)
            SizedBox(
              width: side,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: _ClearLabel(ev)),
            ),
        ]),
        SizedBox(width: side * 0.1),
        // pending garbage meter
        Container(
          width: math.max(4, bw * 0.04),
          height: bw * 2,
          alignment: Alignment.bottomCenter,
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
          // queued garbage: orange = still arriving, red = rises on the next placement
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: bw * 2 * (math.min(math.max(0, pd - ready), 20) / 20), color: Colors.orangeAccent),
            Container(height: bw * 2 * (math.min(ready, 20) / 20), color: Colors.redAccent),
          ]),
        ),
        SizedBox(width: side * 0.06),
        SizedBox(width: bw, height: bw * 2, child: _Field(p, big: true)),
        SizedBox(width: side * 0.1),
        box(Column(children: [
          Text('下一个', style: lbl()),
          for (var i = 0; i < nx.length && i < 5; i++)
            SizedBox(width: side * (i == 0 ? 0.8 : 0.6), height: side * (i == 0 ? 0.5 : 0.38), child: _PiecePreview(nx[i])),
        ])),
      ]),
    ]);
  }
}

class _MiniField extends StatelessWidget {
  final GameContext g;
  final int seat;
  final Map<String, dynamic> p;
  final double w;
  const _MiniField(this.g, this.seat, this.p, this.w);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final alive = p['al'] == true;
    final pd = aInt(p['pd'], 0);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: w,
          child: FittedBox(fit: BoxFit.scaleDown, child: g.tag(seat, size: 22, sub: '${p['sc']} 分${pd > 0 ? ' · 待收 $pd' : ''}')),
        ),
        const SizedBox(height: 3),
        SizedBox(
          width: w,
          height: w * 2,
          child: Stack(children: [
            Positioned.fill(child: _Field(p, big: false)),
            if (!alive)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const FittedBox(child: Padding(padding: EdgeInsets.all(4), child: Text('出局', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)))),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final Map<String, dynamic> p;
  final bool big;
  const _Field(this.p, {required this.big});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _FieldPainter(aStr(p['b']), p['t'] as String?, aInts(p['a']), aInts(p['gh']), big, p['al'] == true),
      );
}

void _cell(Canvas c, Rect r, Color col, {bool ghost = false}) {
  if (ghost) {
    c.drawRRect(RRect.fromRectAndRadius(r.deflate(r.width * 0.08), Radius.circular(r.width * 0.12)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, r.width * 0.08)
          ..color = col.withValues(alpha: 0.6));
    return;
  }
  final rr = RRect.fromRectAndRadius(r.deflate(r.width * 0.04), Radius.circular(r.width * 0.12));
  c.drawRRect(rr, Paint()..color = col);
  if (r.width >= 8) {
    c.drawRect(Rect.fromLTWH(r.left + r.width * 0.12, r.top + r.width * 0.12, r.width * 0.76, r.width * 0.16), Paint()..color = Colors.white.withValues(alpha: 0.28));
    c.drawRect(Rect.fromLTWH(r.left + r.width * 0.12, r.bottom - r.width * 0.2, r.width * 0.76, r.width * 0.1), Paint()..color = Colors.black.withValues(alpha: 0.18));
  }
}

class _FieldPainter extends CustomPainter {
  final String b;
  final String? t;
  final List<int> active, ghost;
  final bool big, alive;
  _FieldPainter(this.b, this.t, this.active, this.ghost, this.big, this.alive);

  @override
  void paint(Canvas canvas, Size size) {
    const w = TetrisBattle.w, h = TetrisBattle.h;
    final cw = size.width / w;
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4));
    canvas.drawRRect(bg, Paint()..color = const Color(0xE0101820));
    if (big) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.05)
        ..strokeWidth = 1;
      for (var x = 1; x < w; x++) {
        canvas.drawLine(Offset(x * cw, 0), Offset(x * cw, size.height), grid);
      }
      for (var y = 1; y < h; y++) {
        canvas.drawLine(Offset(0, y * cw), Offset(size.width, y * cw), grid);
      }
    }
    Rect r(int i) => Rect.fromLTWH((i % w) * cw, (i ~/ w) * cw, cw, cw);
    for (var i = 0; i < b.length && i < w * h; i++) {
      final ch = b[i];
      if (ch == '.') continue;
      _cell(canvas, r(i), (_pieceColors[ch] ?? Colors.grey).withValues(alpha: alive ? 1 : 0.55));
    }
    if (t != null && alive) {
      final col = _pieceColors[t] ?? Colors.white;
      for (final i in ghost) {
        if (i >= 0 && i < w * h) _cell(canvas, r(i), col, ghost: true);
      }
      for (final i in active) {
        if (i >= 0 && i < w * h) _cell(canvas, r(i), col);
      }
    }
    canvas.drawRRect(bg, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = big ? 2 : 1
      ..color = Colors.white24);
  }

  @override
  bool shouldRepaint(_FieldPainter o) => o.b != b || o.t != t || '${o.active}' != '$active' || '${o.ghost}' != '$ghost' || o.alive != alive;
}

class _PiecePreview extends StatelessWidget {
  final String? t;
  const _PiecePreview(this.t);
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PreviewPainter(t));
}

class _PreviewPainter extends CustomPainter {
  final String? t;
  _PreviewPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final tt = t;
    if (tt == null || !TetrisBattle.shapes.containsKey(tt)) return;
    final cells = TetrisBattle.cellsOf(tt, 0, 0, 0);
    final minX = cells.map((c) => c[0]).reduce(math.min), maxX = cells.map((c) => c[0]).reduce(math.max);
    final minY = cells.map((c) => c[1]).reduce(math.min), maxY = cells.map((c) => c[1]).reduce(math.max);
    final cols = maxX - minX + 1, rows = maxY - minY + 1;
    final cw = math.min(size.width / 4.2, size.height / 2.2);
    final ox = (size.width - cols * cw) / 2, oy = (size.height - rows * cw) / 2;
    for (final c in cells) {
      _cell(canvas, Rect.fromLTWH(ox + (c[0] - minX) * cw, oy + (c[1] - minY) * cw, cw, cw), _pieceColors[tt]!);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter o) => o.t != t;
}

/// Action text like TETR.IO: "T-SPIN DOUBLE", "B2B ×3", "QUAD", "ALL CLEAR".
class _ClearLabel extends StatelessWidget {
  final Map<String, dynamic> ev;
  const _ClearLabel(this.ev);
  @override
  Widget build(BuildContext context) {
    final n = aInt(ev['n'], 0), sp = aInt(ev['sp'], 0), b2b = aInt(ev['b2b'], 0), cb = aInt(ev['cb'], 0), atk = aInt(ev['a'], 0);
    const names = ['', 'SINGLE', 'DOUBLE', 'TRIPLE', 'QUAD'];
    final line = names[n.clamp(0, 4)];
    final main = sp == 2
        ? 'T-SPIN${n > 0 ? ' $line' : ''}'
        : (sp == 1 ? 'MINI T-SPIN${n > 0 ? ' $line' : ''}' : line);
    final col = sp > 0 ? const Color(0xFFAB47BC) : (n == 4 ? const Color(0xFF26C6DA) : Colors.deepOrange);
    Widget chip(String t, Color c, double size) =>
        Padding(padding: const EdgeInsets.only(bottom: 2), child: AChip(t, c, size: size));
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (ev['pc'] == true) chip('ALL CLEAR', const Color(0xFFFDD835), 12),
      if (b2b > 0) chip('B2B ×$b2b', const Color(0xFFFFB300), 11),
      if (main.isNotEmpty) chip(main, col, 12),
      if (cb > 0) chip('$cb COMBO', Colors.teal, 11),
      if (atk > 0) chip('→ $atk', Colors.redAccent, 11),
    ]);
  }
}
