import 'dart:math' as math;

import 'dart:ui' show Picture, PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';
import 'arcade_common.dart';

const snakeColors = [
  Color(0xFF43A047), Color(0xFF1E88E5), Color(0xFFE53935), Color(0xFFFDD835), Color(0xFF8E24AA), Color(0xFFFF7043),
];

class SnakeBoard extends StatefulWidget {
  final GameContext g;
  const SnakeBoard(this.g, {super.key});
  @override
  State<SnakeBoard> createState() => _SnakeBoardState();
}

class _SnakeBoardState extends State<SnakeBoard> with SingleTickerProviderStateMixin {
  GameContext get g => widget.g;

  // Smooth motion: the server moves snakes one cell per tick (~6/s); the
  // painter slides each segment from its previous cell at display frame rate.
  late final Ticker _ticker = createTicker((_) => _anim.value = _progress())..start();
  final _anim = ValueNotifier<double>(1);
  int _tick = -1;
  List<List<int>> _prev = const [], _cur = const [];
  DateTime _tickAt = DateTime.now();

  double _progress() {
    final ms = aInt(g.view['tickMs'], 160);
    return (DateTime.now().difference(_tickAt).inMilliseconds / ms).clamp(0.0, 1.0);
  }

  void _syncTick(List<Map<String, dynamic>> sn) {
    final t = aInt(g.view['tick'], 0);
    if (t == _tick) return;
    final bodies = [for (final s in sn) aInts(s['b'])];
    _prev = t == _tick + 1 ? _cur : bodies;
    _cur = bodies;
    _tick = t;
    _tickAt = DateTime.now();
    _anim.value = 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _anim.dispose();
    super.dispose();
  }
  String? _lastSent;
  int _lastSentTick = -1;
  Offset? _panStart;

  bool get _canPlay {
    final sn = aMaps(g.view['sn']);
    return !g.over && g.seat >= 0 && g.seat < sn.length && sn[g.seat]['al'] == true;
  }

  void _turn(String d) {
    if (!_canPlay) return;
    final tick = aInt(g.view['tick'], 0);
    // skip duplicate sends within the same tick (holding a key)
    if (d == _lastSent && tick == _lastSentTick) return;
    _lastSent = d;
    _lastSentTick = tick;
    g.act({'type': 'turn', 'dir': d});
  }

  bool _onKey(LogicalKeyboardKey k, bool repeat) {
    if (repeat) return true;
    final d = {
      LogicalKeyboardKey.arrowUp: 'up',
      LogicalKeyboardKey.keyW: 'up',
      LogicalKeyboardKey.arrowDown: 'down',
      LogicalKeyboardKey.keyS: 'down',
      LogicalKeyboardKey.arrowLeft: 'left',
      LogicalKeyboardKey.keyA: 'left',
      LogicalKeyboardKey.arrowRight: 'right',
      LogicalKeyboardKey.keyD: 'right',
    }[k];
    if (d == null) return false;
    _turn(d);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final sn = aMaps(v['sn']);
    final phase = aStr(v['phase']);
    final n = aInt(v['n'], 30);
    final left = aInt(v['left'], 0);
    _syncTick(sn);
    final meAlive = g.seat >= 0 && g.seat < sn.length && sn[g.seat]['al'] == true;
    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'countdown') {
      status = '准备… ${(aInt(v['cd'], 0) * aInt(v['tickMs'], 160) / 1000).ceil()}   你是 ${g.seat >= 0 ? '${_colorName(g.seat)}色' : '观众'}';
    } else if (g.seat < 0) {
      status = '观战中 · 剩余 ${mmss(left)}';
    } else if (!meAlive) {
      status = '你已出局 · 剩余 ${mmss(left)}';
    } else {
      status = '方向键 / WASD / 滑动 控制方向 · 剩余 ${mmss(left)}';
    }

    return ArcadeKeys(
      onKey: _onKey,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth > box.maxHeight * 1.2;
        final showPad = g.seat >= 0 && meAlive && phase != 'over';
        final sideW = wide ? math.min(220.0, box.maxWidth * 0.28) : 0.0;
        final padH = !wide && showPad ? 128.0 : 0.0;
        final listH = wide ? 0.0 : 58.0;
        final size = math.max(80.0, math.min(box.maxWidth - sideW - (wide && showPad ? 170 : 16), box.maxHeight - 44 - padH - listH));
        final scores = Wrap(
          direction: wide ? Axis.vertical : Axis.horizontal,
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final s in g.seatsFromMe())
              if (s < sn.length) _ScoreTag(g, s, sn[s]),
          ],
        );
        final arena = GestureDetector(
          onPanStart: (d) => _panStart = d.localPosition,
          onPanUpdate: (d) {
            final st = _panStart;
            if (st == null) return;
            final dv = d.localPosition - st;
            if (dv.distance < 18) return;
            _turn(dv.dx.abs() > dv.dy.abs() ? (dv.dx > 0 ? 'right' : 'left') : (dv.dy > 0 ? 'down' : 'up'));
            _panStart = d.localPosition;
          },
          onPanEnd: (_) => _panStart = null,
          child: SizedBox(
            width: size,
            height: size,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ArenaPainter(n, sn, aInts(v['food']), g.seat, Theme.of(context).colorScheme.primary,
                    prev: _prev, anim: _anim),
              ),
            ),
          ),
        );
        final pad = _DPad(onDir: _turn);
        Widget body;
        if (wide) {
          body = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: sideW, child: SingleChildScrollView(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: scores)))),
            arena,
            if (showPad) SizedBox(width: 160, child: Center(child: pad)),
          ]);
        } else {
          body = Column(children: [
            SizedBox(height: listH, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: scores))),
            Expanded(child: Center(child: arena)),
            if (showPad) SizedBox(height: padH, child: Center(child: pad)),
          ]);
        }
        return Column(children: [
          SizedBox(height: 40, child: aStatus(status, highlight: meAlive && phase == 'play')),
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: body),
              if (phase == 'over')
                Positioned.fill(
                  child: Container(
                    color: Colors.black38,
                    child: aRanking(g, aMaps(v['final']), (r) => '长度 ${r['len']}${r['alive'] == true ? ' · 存活' : ''}'),
                  ),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

String _colorName(int s) => const ['绿', '蓝', '红', '黄', '紫', '橙'][s % 6];

class _ScoreTag extends StatelessWidget {
  final GameContext g;
  final int s;
  final Map<String, dynamic> p;
  const _ScoreTag(this.g, this.s, this.p);
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: p['al'] == true ? 1 : 0.45,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: snakeColors[s % 6], shape: BoxShape.circle)),
          const SizedBox(width: 3),
          g.tag(s, size: 24, active: s == g.seat, sub: p['al'] == true ? '长度 ${p['len']}' : '出局 · ${p['len']}'),
        ]),
      );
}

class _DPad extends StatelessWidget {
  final void Function(String) onDir;
  const _DPad({required this.onDir});
  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 150,
          height: 120,
          child: Stack(children: [
            Positioned(left: 51, top: 0, child: PadButton(icon: Icons.keyboard_arrow_up, size: 46, onTap: () => onDir('up'))),
            Positioned(left: 51, top: 74, child: PadButton(icon: Icons.keyboard_arrow_down, size: 46, onTap: () => onDir('down'))),
            Positioned(left: 4, top: 37, child: PadButton(icon: Icons.keyboard_arrow_left, size: 46, onTap: () => onDir('left'))),
            Positioned(left: 98, top: 37, child: PadButton(icon: Icons.keyboard_arrow_right, size: 46, onTap: () => onDir('right'))),
          ]),
        ),
      );
}

class _ArenaPainter extends CustomPainter {
  final int n;
  final List<Map<String, dynamic>> sn;
  final List<int> food;
  final int me;
  final Color accent;

  /// Bodies at the previous tick, and 0..1 progress towards the current one.
  final List<List<int>> prev;
  final ValueNotifier<double> anim;
  _ArenaPainter(this.n, this.sn, this.food, this.me, this.accent, {required this.prev, required this.anim})
      : super(repaint: anim);

  static final _bgCache = <(int, double), Picture>{};

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / n;
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8));
    final pic = _bgCache.putIfAbsent((n, size.width), () {
      if (_bgCache.length > 8) _bgCache.clear();
      final rec = PictureRecorder();
      final cv = Canvas(rec);
      cv.drawRRect(bg, Paint()..color = const Color(0xFF16261C));
      final alt = Paint()..color = const Color(0xFF1B2E22);
      for (var y = 0; y < n; y++) {
        for (var x = (y % 2); x < n; x += 2) {
          cv.drawRect(Rect.fromLTWH(x * c, y * c, c, c), alt);
        }
      }
      return rec.endRecording();
    });
    canvas.drawPicture(pic);
    final t = Curves.linear.transform(anim.value);
    Offset ctr(int i) => Offset((i % n + 0.5) * c, (i ~/ n + 0.5) * c);
    // Segment k slides from where segment k was last tick (the head from its
    // old cell, every other segment from the cell of the one before it).
    Offset seg(int s, List<int> body, int k) {
      final to = ctr(body[k]);
      if (t >= 1 || s >= prev.length) return to;
      final pb = prev[s];
      if (pb.isEmpty || pb.first == body.first) return to;
      final from = k < pb.length ? ctr(pb[k]) : ctr(pb.last);
      // don't glide across the board (respawn / big jumps)
      if ((from - to).distance > c * 1.5) return to;
      return Offset.lerp(from, to, t)!;
    }
    final fp = Paint()..color = const Color(0xFFFF5252);
    final shine = Paint()..color = Colors.white70;
    for (final f in food) {
      canvas.drawCircle(ctr(f), c * 0.36, fp);
      canvas.drawCircle(ctr(f) + Offset(-c * 0.12, -c * 0.12), c * 0.1, shine);
    }
    for (var s = 0; s < sn.length; s++) {
      final body = aInts(sn[s]['b']);
      if (body.isEmpty) continue;
      final col = snakeColors[s % 6];
      final line = Paint()
        ..color = col
        ..strokeWidth = c * 0.72
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final pts = [for (var k = 0; k < body.length; k++) seg(s, body, k)];
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (s == me) {
        canvas.drawPath(path, Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = c * 0.95
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke);
      }
      if (body.length == 1) {
        canvas.drawCircle(pts.first, c * 0.36, Paint()..color = col);
      } else {
        canvas.drawPath(path, line);
      }
      // head + eyes
      final h = pts.first;
      canvas.drawCircle(h, c * 0.45, Paint()..color = Color.lerp(col, Colors.black, 0.2)!);
      final d = aStr(sn[s]['d']);
      final (dx, dy) = switch (d) { 'up' => (0.0, -1.0), 'down' => (0.0, 1.0), 'left' => (-1.0, 0.0), _ => (1.0, 0.0) };
      final perp = Offset(-dy, dx);
      final eye = Paint()..color = Colors.white;
      final pup = Paint()..color = Colors.black;
      for (final sign in [-1.0, 1.0]) {
        final e = h + Offset(dx, dy) * c * 0.15 + perp * sign * c * 0.2;
        canvas.drawCircle(e, c * 0.12, eye);
        canvas.drawCircle(e + Offset(dx, dy) * c * 0.04, c * 0.06, pup);
      }
    }
    canvas.drawRRect(bg, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = accent.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_ArenaPainter o) => o.sn != sn || o.food != food || o.me != me || o.accent != accent;
}
