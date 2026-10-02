import 'package:flutter/material.dart';

/// Small helpers shared by the euro boards (卡卡颂 / 花火).

List<T> eList<T>(Object? v) => v is List ? v.cast<T>() : <T>[];

Map<String, dynamic> eMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int eInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

/// Semi-transparent rounded panel.
class EPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  const EPanel({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? cs.primary : cs.outline.withValues(alpha: 0.25), width: highlight ? 2 : 1),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Recent log lines, newest at the bottom.
class ELog extends StatelessWidget {
  final List<String> lines;
  final int max;
  final double fontSize;
  const ELog(this.lines, {super.key, this.max = 6, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text(shown[i],
              style: TextStyle(
                  fontSize: fontSize,
                  color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 0.95 : 0.65),
                  fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
        ),
    ]);
  }
}

/// Meeple colours per seat (红/蓝/黄/绿/黑).
const List<Color> meepleColors = [
  Color(0xFFD83A34),
  Color(0xFF2F6BD8),
  Color(0xFFF2C230),
  Color(0xFF3DA84A),
  Color(0xFF3A3A44),
];
const List<String> meepleColorNames = ['红', '蓝', '黄', '绿', '黑'];

Color meepleColor(int seat) => meepleColors[seat % meepleColors.length];

/// Meeple silhouette centred at [c] with total height [h].
Path meeplePath(Offset c, double h) {
  const pts = [
    (-0.12, -0.2), (0.12, -0.2), (0.44, -0.06), (0.4, 0.08), (0.16, 0.02), (0.3, 0.46), //
    (0.07, 0.46), (0.0, 0.26), (-0.07, 0.46), (-0.3, 0.46), (-0.16, 0.02), (-0.4, 0.08), (-0.44, -0.06),
  ];
  final p = Path()..moveTo(c.dx + pts[0].$1 * h, c.dy + pts[0].$2 * h);
  for (final (x, y) in pts.skip(1)) {
    p.lineTo(c.dx + x * h, c.dy + y * h);
  }
  p.close();
  p.addOval(Rect.fromCircle(center: Offset(c.dx, c.dy - 0.32 * h), radius: 0.155 * h));
  return p;
}

/// Paints a meeple; [lying] draws a farmer (rotated 90°).
void paintMeeple(Canvas canvas, Offset c, double h, Color color, {bool lying = false}) {
  canvas.save();
  if (lying) {
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-1.5708);
    canvas.translate(-c.dx, -c.dy);
  }
  final p = meeplePath(c, h);
  canvas.drawShadow(p, Colors.black, 2, false);
  canvas.drawPath(p, Paint()..color = color);
  final light = color.computeLuminance() < 0.25;
  canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.05
        ..color = light ? Colors.white70 : Colors.black54);
  canvas.restore();
}

/// A meeple icon widget.
class MeepleIcon extends StatelessWidget {
  final Color color;
  final double size;
  final bool dim;
  const MeepleIcon(this.color, {super.key, this.size = 16, this.dim = false});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: dim ? 0.25 : 1,
        child: CustomPaint(size: Size(size, size), painter: _MeeplePainter(color)),
      );
}

class _MeeplePainter extends CustomPainter {
  final Color color;
  _MeeplePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) =>
      paintMeeple(canvas, Offset(size.width / 2, size.height * 0.54), size.height * 0.95, color);
  @override
  bool shouldRepaint(_MeeplePainter old) => old.color != color;
}
