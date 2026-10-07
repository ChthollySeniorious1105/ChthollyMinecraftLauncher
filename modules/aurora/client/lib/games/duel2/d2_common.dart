import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Small helpers shared by the duel2 boards.

List<T> dList<T>(Object? v) => v is List ? v.cast<T>() : <T>[];
Map<String, dynamic> dMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
int dInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;
List<int> dInts(Object? v) => v is List ? [for (final e in v) dInt(e)] : <int>[];

/// Semi-transparent rounded panel.
class DPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  const DPanel({super.key, required this.child, this.padding = const EdgeInsets.all(6), this.highlight = false});

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
class DLog extends StatelessWidget {
  final List<String> lines;
  final int max;
  const DLog(this.lines, {super.key, this.max = 4});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    // Lines may wrap, so the column can be taller than the box it is given:
    // scroll (non-interactive, pinned to the bottom) so older lines clip off
    // the top instead of overflowing.
    return SingleChildScrollView(
      reverse: true,
      physics: const NeverScrollableScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < shown.length; i++)
        Text(shown[i],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 0.95 : 0.65),
                fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
    ]),
    );
  }
}

/// Compact pill button.
class DButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  const DButton(this.label, {super.key, this.icon, this.onTap, this.primary = true});
  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 4)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final child = icon == null
        ? Text(label)
        : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)]);
    return primary ? FilledButton(style: style, onPressed: onTap, child: child) : FilledButton.tonal(style: style, onPressed: onTap, child: child);
  }
}

/// Simple score table for result banners.
Widget dTable(BuildContext context, List<String> header, List<List<String>> rows, {List<int> bold = const []}) {
  final cs = Theme.of(context).colorScheme;
  TextStyle st(bool h, bool b) =>
      TextStyle(fontSize: 13, fontWeight: h || b ? FontWeight.bold : FontWeight.normal, color: h ? cs.primary : cs.onSurface);
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      children: [
        TableRow(children: [
          for (final h in header) Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), child: Text(h, style: st(true, false)))
        ]),
        for (var r = 0; r < rows.length; r++)
          TableRow(children: [
            for (final c in rows[r])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), child: Text(c, style: st(false, bold.contains(r))))
          ]),
      ],
    ),
  );
}

/// Text that scales down instead of overflowing.
Widget dFit(String text, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: style.copyWith(fontFamilyFallback: kFontFallback), maxLines: 1),
    );
