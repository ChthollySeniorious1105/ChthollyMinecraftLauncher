import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Shared helpers for the party2 boards.

int p2Int(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> p2Ints(Object? o) => o is List ? [for (final e in o) p2Int(e)] : <int>[];
List<bool> p2Bools(Object? o) => o is List ? [for (final e in o) e == true] : <bool>[];
Map<String, dynamic>? p2Map(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
List<Map<String, dynamic>> p2Maps(Object? o) =>
    o is List ? [for (final e in o) if (e is Map) e.cast<String, dynamic>()] : <Map<String, dynamic>>[];

/// A rounded translucent panel on the table.
class P2Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;
  const P2Panel({super.key, required this.child, this.padding = const EdgeInsets.all(10), this.color, this.border});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(14),
        border: border == null ? null : Border.all(color: border!, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Small colored pill label.
class P2Chip extends StatelessWidget {
  final String text;
  final Color color;
  final Color? fg;
  final double size;
  const P2Chip(this.text, this.color, {super.key, this.fg, this.size = 11});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: size, color: fg ?? Colors.white, fontWeight: FontWeight.bold)),
      );
}

/// Top status line, scaled down when narrow.
Widget p2Status(String text, {bool highlight = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(text, highlight: highlight)),
    );

/// Final ranking banner (rows of {'s', 'rank', ...}).
Widget p2Ranking(GameContext g, String title, List<Map<String, dynamic>> rows, String Function(Map<String, dynamic>) sub) {
  return ResultBanner(
    title,
    child: Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final r in rows)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('#${r['rank']} ', style: const TextStyle(fontWeight: FontWeight.bold)),
            g.tag(p2Int(r['s']), size: 26, sub: sub(r), active: r['rank'] == 1),
          ]),
      ],
    ),
  );
}

/// Single-line text input with a send button.
class P2Input extends StatefulWidget {
  final String hint;
  final String button;
  final int maxLength;
  final bool enabled;
  final void Function(String) onSubmit;
  final TextInputType? keyboard;
  const P2Input({super.key, required this.hint, required this.button, required this.onSubmit, this.maxLength = 60, this.enabled = true, this.keyboard});
  @override
  State<P2Input> createState() => _P2InputState();
}

class _P2InputState extends State<P2Input> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _send() {
    final t = _c.text.trim();
    if (t.isEmpty || !widget.enabled) return;
    widget.onSubmit(t);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: TextField(
            controller: _c,
            enabled: widget.enabled,
            maxLength: widget.maxLength,
            keyboardType: widget.keyboard,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              counterText: '',
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(onPressed: widget.enabled ? _send : null, child: Text(widget.button)),
      ]);
}
