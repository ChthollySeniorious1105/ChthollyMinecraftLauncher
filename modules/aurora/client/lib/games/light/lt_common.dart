import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Small helpers shared by the light party-card boards.

List<T> lList<T>(Object? v) => v is List ? v.whereType<T>().toList() : <T>[];

Map<String, dynamic> lMap(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

int lInt(Object? v, [int d = 0]) => v is num ? v.toInt() : d;

List<int> lInts(Object? v) => v is List ? [for (final e in v) lInt(e)] : <int>[];

List<bool> lBools(Object? v) => v is List ? [for (final e in v) e == true] : <bool>[];

/// Rounded translucent panel with an optional highlight ring.
class LPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool highlight;
  final Color? color;
  const LPanel({super.key, required this.child, this.padding = const EdgeInsets.all(8), this.highlight = false, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? cs.primary : cs.outline.withValues(alpha: 0.25), width: highlight ? 2 : 1),
        boxShadow: [
          BoxShadow(color: highlight ? cs.primary.withValues(alpha: 0.35) : Colors.black26, blurRadius: highlight ? 10 : 4, offset: const Offset(0, 2)),
        ],
      ),
      child: child,
    );
  }
}

/// Recent log lines (newest last, emphasised).
class LLog extends StatelessWidget {
  final List<String> lines;
  final int max;
  const LLog(this.lines, {super.key, this.max = 5});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > max ? lines.sublist(lines.length - max) : lines;
    if (shown.isEmpty) return const SizedBox();
    return LPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < shown.length; i++)
          Text(shown[i],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: i == shown.length - 1 ? 1 : 0.65),
                  fontWeight: i == shown.length - 1 ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }
}

/// Small pill with an icon and text.
class LChip extends StatelessWidget {
  final IconData? icon;
  final String text;
  final Color? color;
  const LChip(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 3)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
      ]),
    );
  }
}

/// Standard scaffold for these boards: status, optional result, body, log.
class LFrame extends StatelessWidget {
  final String status;
  final bool highlight;
  final Widget? result;
  final List<Widget> children;
  final List<String> log;
  final double maxWidth;
  const LFrame({super.key, required this.status, this.highlight = false, this.result, required this.children, this.log = const [], this.maxWidth = 980});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(6),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            StatusBar(status, highlight: highlight),
            ?result,
            const SizedBox(height: 6),
            ...children,
            if (log.isNotEmpty) ...[const SizedBox(height: 6), LLog(log)],
          ]),
        ),
      ),
    );
  }
}

/// Seats in "me first" order when seated, excluding me.
List<int> lOthers(GameContext g, int n) {
  final base = g.seat >= 0 && g.seat < n ? g.seat : 0;
  return [for (var i = 0; i < n; i++) (base + i) % n].where((s) => s != g.seat).toList();
}

bool lMe(GameContext g, int n) => g.seat >= 0 && g.seat < n;
