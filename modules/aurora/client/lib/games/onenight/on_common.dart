import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';

List<int> onInts(Object? o) => o is List ? [for (final e in o) (e as num).toInt()] : <int>[];
int onInt(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<bool> onBools(Object? o) => o is List ? [for (final e in o) e == true] : <bool>[];

/// Rounded translucent panel used by all three boards.
class OnPanel extends StatelessWidget {
  final Widget child;
  final Color? border;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  const OnPanel({super.key, required this.child, this.border, this.title, this.icon, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? cs.outline.withValues(alpha: 0.3), width: border == null ? 1 : 2),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: cs.primary), const SizedBox(width: 6)],
              Expanded(
                child: Text(title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cs.onSurface)),
              ),
              ?trailing,
            ]),
          ),
        child,
      ]),
    );
  }
}

Widget onBadge(String t, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.75)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 11, color: c),
        Text(t, style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.bold)),
      ]),
    );

/// Grid of player seat tiles. [badges] returns extra badges per seat.
class OnSeatGrid extends StatelessWidget {
  final GameContext g;
  final Set<int> selectable;
  final Set<int> selected;
  final Set<int> active;
  final void Function(int)? onTap;
  final List<Widget> Function(int seat) badges;
  const OnSeatGrid({
    super.key,
    required this.g,
    this.selectable = const {},
    this.selected = const {},
    this.active = const {},
    this.onTap,
    required this.badges,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final n = g.players;
      final cols = c.maxWidth < 420 ? 3 : (c.maxWidth < 640 ? 4 : (n <= 8 ? 4 : 5));
      final w = ((c.maxWidth - (cols - 1) * 8) / cols).floorToDouble();
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (var s = 0; s < n; s++)
          SizedBox(
            width: w,
            child: GestureDetector(
              onTap: selectable.contains(s) && onTap != null ? () => onTap!(s) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: selected.contains(s)
                      ? Color.alphaBlend(cs.primary.withValues(alpha: 0.22), cs.surface)
                      : cs.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected.contains(s)
                        ? cs.primary
                        : active.contains(s)
                            ? Colors.greenAccent.shade700
                            : selectable.contains(s)
                                ? cs.primary.withValues(alpha: 0.6)
                                : cs.outline.withValues(alpha: 0.3),
                    width: selected.contains(s) || active.contains(s) ? 2.5 : (selectable.contains(s) ? 1.8 : 1),
                  ),
                  boxShadow: [
                    if (active.contains(s)) BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.7), blurRadius: 8),
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Stack(clipBehavior: Clip.none, children: [
                      Avatar(g.avatar(s), size: 32, bot: g.bot(s), speaking: active.contains(s)),
                      Positioned(
                        left: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: g.seat == s ? cs.primary : Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${s + 1}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: g.seat == s ? cs.onPrimary : Colors.white)),
                        ),
                      ),
                    ]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${g.name(s)}${g.seat == s ? '（我）' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cs.onSurface)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 16),
                    child: Wrap(spacing: 3, runSpacing: 3, children: badges(s)),
                  ),
                ]),
              ),
            ),
          ),
      ]);
    });
  }
}

/// Countdown text computed from `endsAt`/`now` epoch values in a view.
class OnCountdown extends StatefulWidget {
  final int endsAt;
  final int serverNow;
  final TextStyle? style;
  final String prefix;
  const OnCountdown({super.key, required this.endsAt, required this.serverNow, this.style, this.prefix = ''});
  @override
  State<OnCountdown> createState() => _OnCountdownState();
}

class _OnCountdownState extends State<OnCountdown> {
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
  void didUpdateWidget(OnCountdown old) {
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
    final ms = widget.endsAt - (DateTime.now().millisecondsSinceEpoch + _skew);
    final sec = ms <= 0 ? 0 : (ms / 1000).ceil();
    final txt = '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
    return Text('${widget.prefix}$txt',
        style: widget.style ??
            TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: sec <= 30 ? Colors.redAccent : null));
  }
}

/// Phase banner with gradient.
class OnBanner extends StatelessWidget {
  final String title;
  final String sub;
  final IconData icon;
  final List<Color> colors;
  final Color fg;
  final bool myTurn;
  final Widget? trailing;
  const OnBanner({
    super.key,
    required this.title,
    required this.sub,
    required this.icon,
    required this.colors,
    this.fg = Colors.white,
    this.myTurn = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(16),
        border: myTurn ? Border.all(color: Colors.greenAccent, width: 2.5) : null,
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Row(children: [
        Icon(icon, color: fg, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.88))),
          ]),
        ),
        ?trailing,
        if (myTurn)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(10)),
            child: const Text('轮到你', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
      ]),
    );
  }
}

/// Two-column (wide) / single-column (narrow) scrolling layout.
Widget onLayout({required List<Widget> main, required List<Widget> side, Decoration? bg}) {
  return LayoutBuilder(builder: (context, c) {
    final wide = c.maxWidth >= 760;
    Widget body;
    if (wide) {
      body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(10), child: Column(children: main))),
        SizedBox(
          width: c.maxWidth >= 1100 ? 400 : 340,
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 10), child: Column(children: side)),
        ),
      ]);
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [...main.take(1), ...side, ...main.skip(1)]),
      );
    }
    return Container(decoration: bg, child: body);
  });
}
