import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../widgets/common.dart';
import 'a2_common.dart';

const bomberColors = [Color(0xFFF5F5F5), Color(0xFF263238), Color(0xFFE53935), Color(0xFF1E88E5)];
const _bomberAccents = [Color(0xFF42A5F5), Color(0xFFFFCA28), Color(0xFFFFEB3B), Color(0xFFFF7043)];
const _colorNames = ['白', '黑', '红', '蓝'];

class BombermanBoard extends StatefulWidget {
  final GameContext g;
  const BombermanBoard(this.g, {super.key});
  @override
  State<BombermanBoard> createState() => _BombermanBoardState();
}

class _BombermanBoardState extends State<BombermanBoard> with SingleTickerProviderStateMixin {
  GameContext get g => widget.g;

  // Smooth motion: players step one cell every few server ticks; the painter
  // slides them from their previous cell at display frame rate.
  late final Ticker _ticker = createTicker((_) => _anim.value = _clock())..start();
  final _anim = ValueNotifier<double>(0);
  int _tick = -1;
  DateTime _tickAt = DateTime.now();
  List<int> _cells = const [];
  List<int> _from = const [];
  List<DateTime> _movedAt = const [];
  final _focus = FocusNode(debugLabel: 'bomberman');
  final Set<String> _held = {};
  String? _sentDir;

  /// Fractional ticks elapsed since the last view (drives fuse + motion).
  double _clock() {
    final ms = aInt(g.view['tickMs'], 60);
    return (DateTime.now().difference(_tickAt).inMilliseconds / ms).clamp(0.0, 1.0);
  }

  void _sync(List<Map<String, dynamic>> ps) {
    final t = aInt(g.view['tick'], 0);
    if (t == _tick) return;
    final now = DateTime.now();
    final cells = [for (final p in ps) aInt(p['c'], 0)];
    if (_cells.length != cells.length || t < _tick) {
      _from = List.of(cells);
      _movedAt = List.filled(cells.length, now.subtract(const Duration(seconds: 5)));
    } else {
      _from = [
        for (var i = 0; i < cells.length; i++) cells[i] != _cells[i] ? _cells[i] : _from[i],
      ];
      _movedAt = [
        for (var i = 0; i < cells.length; i++) cells[i] != _cells[i] ? now : _movedAt[i],
      ];
    }
    _cells = cells;
    _tick = t;
    _tickAt = now;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _anim.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canPlay {
    final ps = aMaps(g.view['ps']);
    return !g.over && g.seat >= 0 && g.seat < ps.length && ps[g.seat]['al'] == true;
  }

  void _dir(String? d) {
    if (!_canPlay) return;
    final v = d ?? 'none';
    if (v == _sentDir && v == 'none') return;
    _sentDir = v;
    g.act({'type': 'dir', 'dir': v});
  }

  void _bomb() {
    if (!_canPlay) return;
    g.act({'type': 'bomb'});
  }

  void _press(String d) {
    _held.remove(d);
    _held.add(d); // most recent last
    _dir(d);
  }

  void _release(String d) {
    _held.remove(d);
    _dir(_held.isEmpty ? null : _held.last);
  }

  static final _keys = {
    LogicalKeyboardKey.arrowUp: 'up',
    LogicalKeyboardKey.keyW: 'up',
    LogicalKeyboardKey.arrowDown: 'down',
    LogicalKeyboardKey.keyS: 'down',
    LogicalKeyboardKey.arrowLeft: 'left',
    LogicalKeyboardKey.keyA: 'left',
    LogicalKeyboardKey.arrowRight: 'right',
    LogicalKeyboardKey.keyD: 'right',
  };

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final d = _keys[e.logicalKey];
    if (d != null) {
      if (e is KeyDownEvent) _press(d);
      if (e is KeyUpEvent) _release(d);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.space || e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.keyJ) {
      if (e is KeyDownEvent) _bomb();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final ps = aMaps(v['ps']);
    final phase = aStr(v['phase']);
    final w = aInt(v['w'], 15), h = aInt(v['h'], 13);
    final left = aInt(v['left'], 0);
    _sync(ps);
    final me = g.seat >= 0 && g.seat < ps.length ? ps[g.seat] : null;
    final meAlive = me?['al'] == true;
    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'countdown') {
      status = '准备… ${(aInt(v['cd'], 0) * aInt(v['tickMs'], 60) / 1000).ceil()}   你是 ${g.seat >= 0 ? '${_colorNames[g.seat % 4]}色炸弹人' : '观众'}';
    } else if (g.seat < 0) {
      status = '观战中 · 剩余 ${mmss(left)}';
    } else if (!meAlive) {
      status = '你被炸飞了 · 剩余 ${mmss(left)}';
    } else {
      status = '方向键/WASD 移动 · 空格 放炸弹 · 剩余 ${mmss(left)}';
    }

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > box.maxHeight * 1.15;
          final showPad = me != null && meAlive && phase != 'over';
          final sideW = wide ? math.min(210.0, box.maxWidth * 0.24) : 0.0;
          final padW = wide && showPad ? math.min(190.0, box.maxWidth * 0.24) : 0.0;
          final padH = !wide && showPad ? 150.0 : 0.0;
          final listH = wide ? 0.0 : 54.0;
          final availW = box.maxWidth - sideW - padW - 12;
          final availH = box.maxHeight - 44 - padH - listH;
          final cellSize = math.max(4.0, math.min(availW / w, availH / h));
          final arena = SizedBox(
            width: cellSize * w,
            height: cellSize * h,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _ArenaPainter(
                  w: w,
                  h: h,
                  grid: aStr(v['g']),
                  bombs: aMaps(v['bombs']),
                  flames: v['fl'] is List ? v['fl'] as List : const [],
                  ps: ps,
                  me: g.seat,
                  fuse: aInt(v['fuse'], 42),
                  flameT: aInt(v['flameT'], 8),
                  tickMs: aInt(v['tickMs'], 60),
                  from: _from,
                  movedAt: _movedAt,
                  anim: _anim,
                ),
              ),
            ),
          );
          final tags = Wrap(
            direction: wide ? Axis.vertical : Axis.horizontal,
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final s in g.seatsFromMe())
                if (s < ps.length) _PlayerTag(g, s, ps[s]),
            ],
          );
          final pad = _Controls(onPress: _press, onRelease: _release, onBomb: _bomb, compact: wide);
          Widget body;
          if (wide) {
            body = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: sideW, child: SingleChildScrollView(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: tags)))),
              arena,
              if (showPad) SizedBox(width: padW, child: Center(child: pad)),
            ]);
          } else {
            body = Column(children: [
              SizedBox(height: listH, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: tags))),
              Expanded(child: Center(child: arena)),
              if (showPad) SizedBox(height: padH, child: Center(child: pad)),
            ]);
          }
          return Column(children: [
            SizedBox(height: 40, child: aStatus(status, highlight: meAlive && phase == 'play')),
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: body),
                if (phase == 'countdown')
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Text('${(aInt(v['cd'], 0) * aInt(v['tickMs'], 60) / 1000).ceil()}',
                            style: TextStyle(
                                fontSize: 72,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                shadows: const [Shadow(blurRadius: 12, color: Colors.black)])),
                      ),
                    ),
                  ),
                if (phase == 'over')
                  Positioned.fill(
                    child: Container(
                      color: Colors.black38,
                      child: aRanking(g, aMaps(v['final']), (r) => '击杀 ${r['kills']}${r['alive'] == true ? ' · 存活' : ''}'),
                    ),
                  ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }
}

class _PlayerTag extends StatelessWidget {
  final GameContext g;
  final int s;
  final Map<String, dynamic> p;
  const _PlayerTag(this.g, this.s, this.p);
  @override
  Widget build(BuildContext context) {
    final alive = p['al'] == true;
    return Opacity(
      opacity: alive ? 1 : 0.45,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: bomberColors[s % 4],
            shape: BoxShape.circle,
            border: Border.all(color: _bomberAccents[s % 4], width: 2),
          ),
        ),
        const SizedBox(width: 3),
        g.tag(s,
            size: 24,
            active: s == g.seat,
            sub: alive ? '💣${p['b']} 🔥${p['r']} 👟${p['sp']} · 击杀 ${p['k']}' : '出局 · 击杀 ${p['k']}'),
      ]),
    );
  }
}

/// D-pad (hold to walk) + bomb button.
class _Controls extends StatelessWidget {
  final void Function(String) onPress, onRelease;
  final VoidCallback onBomb;
  final bool compact;
  const _Controls({required this.onPress, required this.onRelease, required this.onBomb, this.compact = false});

  Widget _key(BuildContext context, String d, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => onPress(d),
      onPointerUp: (_) => onRelease(d),
      onPointerCancel: (_) => onRelease(d),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38, offset: Offset(0, 2))],
        ),
        child: Icon(icon, color: cs.onPrimary, size: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dpad = SizedBox(
      width: 150,
      height: 150,
      child: Stack(children: [
        Positioned(left: 51, top: 0, child: _key(context, 'up', Icons.keyboard_arrow_up)),
        Positioned(left: 51, top: 102, child: _key(context, 'down', Icons.keyboard_arrow_down)),
        Positioned(left: 0, top: 51, child: _key(context, 'left', Icons.keyboard_arrow_left)),
        Positioned(left: 102, top: 51, child: _key(context, 'right', Icons.keyboard_arrow_right)),
      ]),
    );
    final bomb = GestureDetector(
      onTapDown: (_) => onBomb(),
      child: Container(
        width: 74,
        height: 74,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFFFF8A65), Color(0xFFD84315)], center: Alignment(-0.3, -0.3)),
          boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black45, offset: Offset(0, 3))],
        ),
        child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('💣', style: TextStyle(fontSize: 24, fontFamilyFallback: kFontFallback)),
          Text('炸弹', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ]),
      ),
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: compact
          ? Column(mainAxisSize: MainAxisSize.min, children: [dpad, const SizedBox(height: 18), bomb])
          : Row(mainAxisSize: MainAxisSize.min, children: [dpad, const SizedBox(width: 48), bomb]),
    );
  }
}

class _ArenaPainter extends CustomPainter {
  final int w, h;
  final String grid;
  final List<Map<String, dynamic>> bombs;
  final List flames;
  final List<Map<String, dynamic>> ps;
  final int me, fuse, flameT, tickMs;
  final List<int> from;
  final List<DateTime> movedAt;
  final ValueNotifier<double> anim;
  _ArenaPainter({
    required this.w,
    required this.h,
    required this.grid,
    required this.bombs,
    required this.flames,
    required this.ps,
    required this.me,
    required this.fuse,
    required this.flameT,
    required this.tickMs,
    required this.from,
    required this.movedAt,
    required this.anim,
  }) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / w;
    Rect rc(int i) => Rect.fromLTWH((i % w) * c, (i ~/ w) * c, c, c);
    Offset ctr(int i) => Offset((i % w + 0.5) * c, (i ~/ w + 0.5) * c);
    final frac = anim.value; // 0..1 of the current tick

    // floor
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.3)), Paint()..color = const Color(0xFF2E7D32));
    final alt = Paint()..color = const Color(0xFF388E3C);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1 + (y % 2); x < w - 1; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c, c), alt);
      }
    }
    // pillars, bricks, items
    final pillarTop = Paint()..color = const Color(0xFF90A4AE);
    final pillarSide = Paint()..color = const Color(0xFF546E7A);
    final pillarHi = Paint()..color = const Color(0xFFCFD8DC);
    final brick = Paint()..color = const Color(0xFFB0643A);
    final brickDark = Paint()
      ..color = const Color(0xFF7A3E1D)
      ..strokeWidth = math.max(1, c * 0.06)
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < grid.length && i < w * h; i++) {
      final ch = grid[i];
      final r = rc(i);
      if (ch == '#') {
        canvas.drawRect(r, pillarSide);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(r.left + c * 0.06, r.top + c * 0.04, c * 0.88, c * 0.78), Radius.circular(c * 0.12)), pillarTop);
        canvas.drawRect(Rect.fromLTWH(r.left + c * 0.16, r.top + c * 0.12, c * 0.3, c * 0.1), pillarHi);
      } else if (ch == '+') {
        final rr = r.deflate(c * 0.03);
        canvas.drawRRect(RRect.fromRectAndRadius(rr, Radius.circular(c * 0.08)), brick);
        // mortar lines
        final p = Path()
          ..moveTo(rr.left, rr.top + rr.height / 3)
          ..lineTo(rr.right, rr.top + rr.height / 3)
          ..moveTo(rr.left, rr.top + rr.height * 2 / 3)
          ..lineTo(rr.right, rr.top + rr.height * 2 / 3)
          ..moveTo(rr.left + rr.width / 2, rr.top)
          ..lineTo(rr.left + rr.width / 2, rr.top + rr.height / 3)
          ..moveTo(rr.left + rr.width / 4, rr.top + rr.height / 3)
          ..lineTo(rr.left + rr.width / 4, rr.top + rr.height * 2 / 3)
          ..moveTo(rr.left + rr.width * 3 / 4, rr.top + rr.height / 3)
          ..lineTo(rr.left + rr.width * 3 / 4, rr.top + rr.height * 2 / 3)
          ..moveTo(rr.left + rr.width / 2, rr.top + rr.height * 2 / 3)
          ..lineTo(rr.left + rr.width / 2, rr.bottom);
        canvas.drawPath(p, brickDark);
      } else if (ch == 'b' || ch == 'r' || ch == 's') {
        final col = switch (ch) { 'b' => const Color(0xFF5C6BC0), 'r' => const Color(0xFFEF6C00), _ => const Color(0xFF00897B) };
        final rr = RRect.fromRectAndRadius(r.deflate(c * 0.1), Radius.circular(c * 0.16));
        canvas.drawRRect(rr.shift(Offset(0, c * 0.05)), Paint()..color = Colors.black26);
        canvas.drawRRect(rr, Paint()..color = col);
        canvas.drawRRect(rr, Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, c * 0.05));
        _emoji(canvas, ch == 'b' ? '💣' : (ch == 'r' ? '🔥' : '👟'), r.center, c * 0.5);
      }
    }
    // flames
    final fl = <int, int>{};
    for (final f in flames) {
      if (f is List && f.length >= 2) fl[aInt(f[0])] = aInt(f[1]);
    }
    for (final e in fl.entries) {
      final i = e.key;
      final life = (e.value - frac) / math.max(1, flameT); // 1 -> 0
      final r = rc(i);
      final horiz = fl.containsKey(i - 1) || fl.containsKey(i + 1);
      final vert = fl.containsKey(i - w) || fl.containsKey(i + w);
      final k = 0.55 + 0.4 * life.clamp(0.0, 1.0);
      final outer = Paint()..color = const Color(0xFFFF6D00).withValues(alpha: 0.9);
      final mid = Paint()..color = const Color(0xFFFFC400);
      final core = Paint()..color = const Color(0xFFFFFDE7);
      for (final (paint, s) in [(outer, 1.0), (mid, 0.68), (core, 0.36)]) {
        final t = c * k * s;
        if (horiz || !vert) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: r.center, width: c * (horiz ? 1.0 : k * s), height: t), Radius.circular(t / 2)), paint);
        }
        if (vert || !horiz) {
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: r.center, width: t, height: c * (vert ? 1.0 : k * s)), Radius.circular(t / 2)), paint);
        }
      }
    }
    // bombs (pulse faster and redden as the fuse burns down)
    for (final b in bombs) {
      final i = aInt(b['c']);
      final left = (aInt(b['f']) - frac) / math.max(1, fuse); // 1 -> 0
      final o = ctr(i);
      final pulse = math.sin((1 - left) * math.pi * (6 + 16 * (1 - left)));
      final r = c * (0.36 + 0.035 * pulse);
      canvas.drawOval(Rect.fromCenter(center: o + Offset(0, c * 0.32), width: c * 0.7, height: c * 0.18), Paint()..color = Colors.black38);
      final body = Color.lerp(const Color(0xFF212121), const Color(0xFFB71C1C), (1 - left).clamp(0.0, 1.0) * 0.8)!;
      canvas.drawCircle(o, r, Paint()..color = body);
      canvas.drawCircle(o + Offset(-r * 0.35, -r * 0.35), r * 0.25, Paint()..color = Colors.white38);
      // fuse cap + spark
      final cap = o + Offset(r * 0.55, -r * 0.75);
      canvas.drawRect(Rect.fromCenter(center: cap, width: c * 0.14, height: c * 0.12), Paint()..color = const Color(0xFF757575));
      final sp = cap + Offset(c * 0.08, -c * 0.1);
      canvas.drawCircle(sp, c * (0.08 + 0.04 * pulse.abs()), Paint()..color = const Color(0xFFFFEB3B));
      canvas.drawCircle(sp, c * 0.04, Paint()..color = Colors.white);
      // owner ring
      final owner = aInt(b['o'], 0);
      canvas.drawCircle(o, r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, c * 0.05)
        ..color = _bomberAccents[owner % 4].withValues(alpha: 0.8));
    }
    // players
    final now = DateTime.now();
    for (var s = 0; s < ps.length; s++) {
      final p = ps[s];
      if (p['al'] != true) continue;
      final cell = aInt(p['c']);
      var pos = ctr(cell);
      if (s < from.length && s < movedAt.length && from[s] != cell) {
        final dur = aInt(p['mt'], 5) * tickMs;
        final t = (now.difference(movedAt[s]).inMilliseconds / math.max(1, dur)).clamp(0.0, 1.0);
        final a = ctr(from[s]);
        if ((a - pos).distance < c * 1.5) pos = Offset.lerp(a, pos, t)!;
      }
      _player(canvas, pos, c, s, aStr(p['d']), s == me);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(c * 0.3)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black54);
  }

  void _player(Canvas canvas, Offset o, double c, int s, String dir, bool mine) {
    final col = bomberColors[s % 4];
    final acc = _bomberAccents[s % 4];
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, c * 0.04)
      ..color = Colors.black87;
    canvas.drawOval(Rect.fromCenter(center: o + Offset(0, c * 0.38), width: c * 0.62, height: c * 0.16), Paint()..color = Colors.black38);
    if (mine) {
      canvas.drawCircle(o, c * 0.5, Paint()..color = Colors.white.withValues(alpha: 0.28));
    }
    // body
    final bodyR = RRect.fromRectAndRadius(Rect.fromCenter(center: o + Offset(0, c * 0.2), width: c * 0.5, height: c * 0.34), Radius.circular(c * 0.12));
    canvas.drawRRect(bodyR, Paint()..color = acc);
    canvas.drawRRect(bodyR, outline);
    // head
    final head = o + Offset(0, -c * 0.1);
    canvas.drawCircle(head, c * 0.27, Paint()..color = col);
    canvas.drawCircle(head, c * 0.27, outline);
    // antenna
    canvas.drawLine(head + Offset(0, -c * 0.27), head + Offset(0, -c * 0.4), outline);
    canvas.drawCircle(head + Offset(0, -c * 0.42), c * 0.07, Paint()..color = acc);
    // face visor
    final (dx, dy) = switch (dir) { 'up' => (0.0, -1.0), 'left' => (-1.0, 0.0), 'right' => (1.0, 0.0), _ => (0.0, 1.0) };
    if (dy >= 0) {
      final visor = RRect.fromRectAndRadius(
          Rect.fromCenter(center: head + Offset(dx * c * 0.07, c * 0.03), width: c * 0.36, height: c * 0.2), Radius.circular(c * 0.08));
      canvas.drawRRect(visor, Paint()..color = const Color(0xFFFFCCBC));
      final eye = Paint()..color = Colors.black;
      for (final sx in [-1.0, 1.0]) {
        canvas.drawOval(
            Rect.fromCenter(center: head + Offset(dx * c * 0.1 + sx * c * 0.07, c * 0.03), width: c * 0.05, height: c * 0.1), eye);
      }
    }
  }

  void _emoji(Canvas canvas, String e, Offset center, double size) {
    final tp = TextPainter(
      text: TextSpan(text: e, style: TextStyle(fontSize: size, fontFamilyFallback: kFontFallback)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_ArenaPainter o) => true;
}
