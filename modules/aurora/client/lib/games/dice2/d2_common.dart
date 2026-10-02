import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Small helpers shared by the dice2 boards.

List<T> d2List<T>(Object? v) => v is List ? [for (final e in v) if (e is T) e] : <T>[];

Map<String, dynamic> d2Map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int d2Int(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

String d2Str(Object? v, [String d = '']) => v is String ? v : d;

/// Semi-transparent rounded panel.
class D2Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  const D2Panel({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? cs.primary : cs.outline.withValues(alpha: 0.25), width: highlight ? 2 : 1),
      ),
      child: child,
    );
  }
}

/// Recent log lines, newest at the bottom.
class D2Log extends StatelessWidget {
  final List<String> lines;
  final int max;
  const D2Log(this.lines, {super.key, this.max = 6});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        Text(shown[i],
            style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 1 : 0.65),
                fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
    ]);
  }
}

/// Felt table area with rounded wooden rim.
class D2Felt extends StatelessWidget {
  final Widget child;
  final Color color;
  final EdgeInsets padding;
  const D2Felt({super.key, required this.child, required this.color, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(color);
    final dark = hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: RadialGradient(colors: [color, dark], radius: 1.2),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF4E342E), width: 6),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// A die that tumbles briefly whenever [rollKey] changes (and it isn't held).
class RollingDie extends StatefulWidget {
  final int value;
  final double size;
  final bool held;
  final bool dim;
  final Object rollKey;
  final VoidCallback? onTap;
  final Color? ring;
  const RollingDie(this.value,
      {super.key, this.size = 48, this.held = false, this.dim = false, this.rollKey = 0, this.onTap, this.ring});

  @override
  State<RollingDie> createState() => _RollingDieState();
}

class _RollingDieState extends State<RollingDie> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  final _r = Random();
  int _face = 1;
  double _spin = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(() {
      if (c.value < 0.85 && _r.nextInt(3) == 0) _face = _r.nextInt(6) + 1;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(RollingDie old) {
    super.didUpdateWidget(old);
    if (old.rollKey != widget.rollKey && !widget.held) {
      _spin = (_r.nextBool() ? 1 : -1) * (1.5 + _r.nextDouble());
      _face = _r.nextInt(6) + 1;
      c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Curves.easeOutCubic.transform(c.value);
    final animating = c.isAnimating;
    final face = animating && c.value < 0.85 ? _face : widget.value;
    final hop = animating ? -sin(t * pi) * widget.size * 0.35 : 0.0;
    final angle = animating ? (1 - t) * _spin * pi : 0.0;
    Widget d = DieFace(face.clamp(1, 6), size: widget.size, held: widget.held);
    if (widget.ring != null) {
      d = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size * 0.22),
          boxShadow: [BoxShadow(color: widget.ring!, blurRadius: 8, spreadRadius: 2)],
        ),
        child: d,
      );
    }
    d = Transform.translate(offset: Offset(0, hop), child: Transform.rotate(angle: angle, child: d));
    if (widget.dim) d = Opacity(opacity: 0.4, child: d);
    if (widget.held) {
      d = Column(mainAxisSize: MainAxisSize.min, children: [
        d,
        SizedBox(
          height: widget.size * 0.3,
          child: FittedBox(
              child: Text('保留', style: TextStyle(color: Colors.amber.shade300, fontWeight: FontWeight.bold))),
        ),
      ]);
    } else if (widget.onTap != null) {
      d = Column(mainAxisSize: MainAxisSize.min, children: [d, SizedBox(height: widget.size * 0.3)]);
    }
    if (widget.onTap == null) return d;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: widget.onTap, child: d));
  }
}

/// A dice cup (骰盅) drawn with a CustomPainter. [lifted] tilts it up.
class DiceCup extends StatelessWidget {
  final double size;
  final Color color;
  final bool lifted;
  final String? label;
  const DiceCup({super.key, this.size = 48, this.color = const Color(0xFF8D1E1E), this.lifted = false, this.label});

  @override
  Widget build(BuildContext context) {
    Widget cup = CustomPaint(size: Size(size, size * 0.95), painter: _CupPainter(color, label));
    if (lifted) cup = Transform.rotate(angle: -0.35, alignment: Alignment.bottomLeft, child: cup);
    return cup;
  }
}

class _CupPainter extends CustomPainter {
  final Color color;
  final String? label;
  _CupPainter(this.color, this.label);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final body = Path()
      ..moveTo(w * 0.22, h * 0.08)
      ..lineTo(w * 0.78, h * 0.08)
      ..quadraticBezierTo(w * 0.84, h * 0.08, w * 0.86, h * 0.16)
      ..lineTo(w * 0.98, h * 0.86)
      ..lineTo(w * 0.02, h * 0.86)
      ..lineTo(w * 0.14, h * 0.16)
      ..quadraticBezierTo(w * 0.16, h * 0.08, w * 0.22, h * 0.08)
      ..close();
    canvas.drawShadow(body, Colors.black, 4, false);
    final hsl = HSLColor.fromColor(color);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(colors: [
          hsl.withLightness((hsl.lightness + 0.2).clamp(0.0, 1.0)).toColor(),
          color,
          hsl.withLightness((hsl.lightness * 0.55).clamp(0.0, 1.0)).toColor(),
        ], stops: const [0, 0.45, 1]).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // rim
    final rim = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * 0.8, w, h * 0.16), Radius.circular(h * 0.06));
    canvas.drawRRect(rim, Paint()..color = const Color(0xFFFFC107));
    canvas.drawRRect(rim, Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
    // bands
    final band = Paint()
      ..color = const Color(0xFFFFD54F).withValues(alpha: 0.8)
      ..strokeWidth = max(1.0, h * 0.03);
    canvas.drawLine(Offset(w * 0.12, h * 0.28), Offset(w * 0.88, h * 0.28), band);
    // highlight
    canvas.drawLine(Offset(w * 0.28, h * 0.18), Offset(w * 0.2, h * 0.7), Paint()
      ..color = Colors.white30
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round);
    if (label != null && label!.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: const Color(0xFFFFE082),
                fontSize: h * 0.28,
                fontWeight: FontWeight.w900,
                fontFamilyFallback: kFontFallback)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      tp.paint(canvas, Offset((w - tp.width) / 2, h * 0.36));
    }
  }

  @override
  bool shouldRepaint(_CupPainter o) => o.color != color || o.label != label;
}

/// Row of little hearts for lives.
class D2Lives extends StatelessWidget {
  final int lives;
  final int max;
  final double size;
  const D2Lives(this.lives, this.max, {super.key, this.size = 12});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < max; i++)
          Icon(i < lives ? Icons.favorite : Icons.favorite_border,
              size: size, color: i < lives ? Colors.redAccent : Colors.white38),
      ]);
}

/// Horizontal progress bar toward a target score.
class D2Progress extends StatelessWidget {
  final int value;
  final int pending;
  final int target;
  const D2Progress(this.value, this.target, {super.key, this.pending = 0});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = (value / max(1, target)).clamp(0.0, 1.0);
    final b = ((value + pending) / max(1, target)).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 120.0;
      return Container(
        height: 8,
        width: w,
        decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
        child: Stack(children: [
          Container(
              width: w * b,
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4))),
          Container(width: w * a, decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(4))),
        ]),
      );
    });
  }
}

/// Player row used in score lists: tag + trailing text.
Widget d2ScoreRow(GameContext g, int s,
    {required bool active, required String sub, Widget? extra, double size = 30}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Align(alignment: Alignment.centerLeft, child: g.tag(s, active: active, sub: sub, size: size)),
      if (extra != null) Padding(padding: const EdgeInsets.only(top: 3, left: 4, right: 4), child: extra),
    ]),
  );
}
