import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Small helpers shared by the euro2 boards.

List<T> xList<T>(Object? v) => v is List ? v.cast<T>() : <T>[];
Map<String, dynamic> xMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
int xInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
List<int> xInts(Object? v) => v is List ? [for (final e in v) xInt(e)] : <int>[];

/// Seat colours (红/蓝/黄/绿).
const List<Color> seatColors = [Color(0xFFD83A34), Color(0xFF2F6BD8), Color(0xFFF2B630), Color(0xFF3DA84A)];
Color seatColor(int s) => seatColors[s % seatColors.length];

/// Semi-transparent rounded panel.
class XPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;
  const XPanel({super.key, required this.child, this.padding = const EdgeInsets.all(6), this.highlight = false, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? cs.primary : cs.outline.withValues(alpha: 0.25), width: highlight ? 2 : 1),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Recent log lines, newest at the bottom.
class XLog extends StatelessWidget {
  final List<String> lines;
  final int max;
  final double fontSize;
  const XLog(this.lines, {super.key, this.max = 5, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        Text(shown[i],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: fontSize,
                color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 0.95 : 0.65),
                fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
    ]);
  }
}

/// Final score table for a result banner.
Widget scoreTable(BuildContext context, List<String> header, List<List<String>> rows, {List<int> bold = const []}) {
  final cs = Theme.of(context).colorScheme;
  TextStyle st(bool h, bool b) => TextStyle(fontSize: 12, fontWeight: h || b ? FontWeight.bold : FontWeight.normal, color: h ? cs.primary : cs.onSurface);
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(children: [for (final h in header) Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Text(h, style: st(true, false)))]),
        for (var r = 0; r < rows.length; r++)
          TableRow(children: [
            for (final c in rows[r]) Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: Text(c, style: st(false, bold.contains(r))))
          ]),
      ],
    ),
  );
}

/// Text style for CustomPainters.
TextStyle paintText(double size, Color color, {FontWeight weight = FontWeight.bold}) =>
    TextStyle(fontSize: size, color: color, fontWeight: weight, fontFamilyFallback: kFontFallback);

void paintLabel(Canvas canvas, String text, Offset center, TextStyle style) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Compact pill button for action bars.
class XButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  const XButton(this.label, {super.key, this.icon, this.onTap, this.primary = true});
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = icon == null ? Text(label) : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)]);
    return primary ? FilledButton(style: style, onPressed: onTap, child: child) : OutlinedButton(style: style, onPressed: onTap, child: child);
  }
}
