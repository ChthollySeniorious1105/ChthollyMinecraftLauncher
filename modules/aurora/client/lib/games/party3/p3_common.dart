import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Shared helpers for the party3 boards.

int p3Int(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> p3Ints(Object? o) => o is List ? [for (final e in o) p3Int(e)] : <int>[];
Map<String, dynamic>? p3Map(Object? o) => o is Map ? o.cast<String, dynamic>() : null;
List<Map<String, dynamic>> p3Maps(Object? o) =>
    o is List ? [for (final e in o) if (e is Map) e.cast<String, dynamic>()] : <Map<String, dynamic>>[];
String p3Str(Object? o, [String d = '']) => o is String ? o : d;

/// Rounded translucent panel.
class P3Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;
  const P3Panel({super.key, required this.child, this.padding = const EdgeInsets.all(10), this.color, this.border});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? cs.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: border == null ? null : Border.all(color: border!, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 2))],
      ),
      child: child,
    );
  }
}

/// Small colored pill label.
class P3Chip extends StatelessWidget {
  final String text;
  final Color color;
  final Color? fg;
  final double size;
  const P3Chip(this.text, this.color, {super.key, this.fg, this.size = 11});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, color: fg ?? Colors.white, fontWeight: FontWeight.bold)),
      );
}

/// Status line with an optional countdown on the right.
class P3Status extends StatelessWidget {
  final String text;
  final bool highlight;
  final Map<String, dynamic> view;
  final bool replay;
  const P3Status(this.text, {super.key, required this.view, this.highlight = false, this.replay = false});
  @override
  Widget build(BuildContext context) {
    final ends = p3Int(view['endsAt'], 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(children: [
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(text, highlight: highlight))),
        if (ends > 0 && !replay) ...[
          const SizedBox(width: 6),
          P3Countdown(endsAt: ends, serverNow: p3Int(view['now'], 0)),
        ],
      ]),
    );
  }
}

/// Countdown pill from `endsAt`/`now` epoch values.
class P3Countdown extends StatefulWidget {
  final int endsAt;
  final int serverNow;
  const P3Countdown({super.key, required this.endsAt, required this.serverNow});
  @override
  State<P3Countdown> createState() => _P3CountdownState();
}

class _P3CountdownState extends State<P3Countdown> {
  Timer? _t;
  int _skew = 0;

  @override
  void initState() {
    super.initState();
    _sync();
    _t = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(P3Countdown old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.serverNow > 0) _skew = widget.serverNow - DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ms = widget.endsAt - (DateTime.now().millisecondsSinceEpoch + _skew);
    final sec = ms <= 0 ? 0 : (ms / 1000).ceil();
    final urgent = sec <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (urgent ? Colors.redAccent : cs.surface).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 15, color: urgent ? Colors.white : cs.onSurface),
        const SizedBox(width: 3),
        Text('$sec',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: urgent ? Colors.white : cs.onSurface)),
      ]),
    );
  }
}

/// Horizontal strip of player tags.
Widget p3Players(GameContext g, {required bool Function(int) active, required String Function(int) sub, bool Function(int)? dim}) => SizedBox(
      height: 46,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final s in g.seatsFromMe())
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Opacity(opacity: dim != null && dim(s) ? 0.4 : 1, child: g.tag(s, size: 26, active: active(s), sub: sub(s))),
          ),
      ]),
    );

/// Final ranking banner.
Widget p3Ranking(GameContext g, String title, List<int> placings, String Function(int) sub) {
  final order = [for (var s = 0; s < placings.length; s++) s]..sort((a, b) => placings[a] - placings[b]);
  return ResultBanner(
    title,
    child: Wrap(
      spacing: 10,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (final s in order)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('#${placings[s]} ', style: const TextStyle(fontWeight: FontWeight.bold)),
            g.tag(s, size: 26, sub: sub(s), active: placings[s] == 1),
          ]),
      ],
    ),
  );
}

/// Single-line text input with a send button.
class P3Input extends StatefulWidget {
  final String hint;
  final String button;
  final int maxLength;
  final bool enabled;
  final void Function(String) onSubmit;
  final Widget? extra;
  const P3Input({super.key, required this.hint, required this.button, required this.onSubmit, this.maxLength = 30, this.enabled = true, this.extra});
  @override
  State<P3Input> createState() => _P3InputState();
}

class _P3InputState extends State<P3Input> {
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
        if (widget.extra != null) ...[const SizedBox(width: 6), widget.extra!],
      ]);
}

/// Lays out a main area and a side feed: side by side when wide, stacked when tall.
Widget p3Layout({
  required Widget status,
  required Widget players,
  required Widget main,
  required Widget feed,
  required Widget controls,
  Widget? banner,
}) =>
    LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.2;
      final ctl = Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 6), child: controls);
      if (wide) {
        return Column(children: [
          status,
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: players),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Column(children: [
                  Expanded(child: Stack(children: [
                    Positioned.fill(child: main),
                    if (banner != null) Align(alignment: Alignment.center, child: FittedBox(fit: BoxFit.scaleDown, child: banner)),
                  ])),
                  ctl,
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(bottom: 6), child: feed)),
              const SizedBox(width: 8),
            ]),
          ),
        ]);
      }
      return Column(children: [
        status,
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: players),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Stack(children: [
              Positioned.fill(child: main),
              if (banner != null) Align(alignment: Alignment.center, child: FittedBox(fit: BoxFit.scaleDown, child: banner)),
            ]),
          ),
        ),
        Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: feed)),
        ctl,
      ]);
    });

/// A scrollable feed panel with a title.
Widget p3Feed(BuildContext context, String title, List<Widget> items, {String empty = '暂无记录'}) {
  final cs = Theme.of(context).colorScheme;
  return P3Panel(
    padding: const EdgeInsets.all(6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
        child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.primary)),
      ),
      Expanded(
        child: items.isEmpty
            ? Center(child: Text(empty, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55))))
            : ListView(children: items),
      ),
    ]),
  );
}

/// One row of a feed.
Widget p3FeedRow(BuildContext context, {required Widget lead, required String text, String? sub, Color? tint}) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 2),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: (tint ?? cs.surfaceContainerHighest).withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(children: [
      lead,
      const SizedBox(width: 6),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.65))),
        ]),
      ),
    ]),
  );
}

/// Lives as hearts.
String p3Hearts(int n, int max) => max > 5 ? '❤×$n' : '${'❤' * n.clamp(0, max)}${'♡' * (max - n).clamp(0, max)}';
