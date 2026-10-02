import 'package:flutter/material.dart';

/// Small helpers shared by the tabletop boards.

List<T> ttList<T>(Object? v) => v is List ? v.cast<T>() : <T>[];

Map<String, dynamic> ttMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int ttInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

/// Semi-transparent rounded panel.
class TTPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool highlight;
  const TTPanel({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.color, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? cs.primary : cs.outline.withValues(alpha: 0.25), width: highlight ? 2 : 1),
      ),
      child: child,
    );
  }
}

/// Recent log lines, newest at the bottom.
class TTLog extends StatelessWidget {
  final List<String> lines;
  final int max;
  final double fontSize;
  const TTLog(this.lines, {super.key, this.max = 6, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        Text(shown[i],
            style: TextStyle(
                fontSize: fontSize,
                color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 1 : 0.7),
                fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
    ]);
  }
}
