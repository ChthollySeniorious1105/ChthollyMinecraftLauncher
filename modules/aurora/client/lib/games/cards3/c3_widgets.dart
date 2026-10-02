import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Small helpers shared by the cards3 boards (干瞪眼/五十K/争上游/拱猪/百家乐).

List<int> c3Ints(Object? l) => [for (final x in (l as List? ?? const [])) (x as num).toInt()];
List<String> c3Strs(Object? l) => [for (final x in (l as List? ?? const [])) '$x'];

/// A card rendered at a legible base size and scaled to [w].
Widget c3Card(String code, double w, {bool dim = false, bool highlight = false}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back', dim: dim)),
  );
  if (highlight) {
    c = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        boxShadow: const [BoxShadow(color: Colors.amberAccent, blurRadius: 6, spreadRadius: 1.5)],
      ),
      child: c,
    );
  }
  return c;
}

Widget c3Pill(String t, Color c, {double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
    );

Widget c3Delta(int d, {double fontSize = 14}) => Text(d > 0 ? '+$d' : '$d',
    style: TextStyle(
        color: d > 0 ? Colors.green : (d < 0 ? Colors.redAccent : Colors.grey),
        fontWeight: FontWeight.bold,
        fontSize: fontSize));

/// A row of overlapped cards.
Widget c3Row(List<String> cards, double w, {double gap = 0.5, bool dim = false, Set<String> hi = const {}}) {
  if (cards.isEmpty) return SizedBox(height: w * 1.4);
  return SizedBox(
    width: w + (cards.length - 1) * w * gap,
    height: w * 1.4,
    child: Stack(children: [
      for (var i = 0; i < cards.length; i++)
        Positioned(left: i * w * gap, child: c3Card(cards[i], w, dim: dim, highlight: hi.contains(cards[i]))),
    ]),
  );
}

/// Small stack of face-down cards showing a hand size.
Widget c3Backs(int n, double w) {
  if (n <= 0) return SizedBox(width: w * 0.6, height: w * 0.84);
  final k = n.clamp(1, 12);
  return SizedBox(
    width: w * 0.6 + (k - 1) * 3.0,
    height: w * 0.84,
    child: Stack(children: [
      for (var i = 0; i < k; i++) Positioned(left: i * 3.0, child: c3Card('back', w * 0.6)),
    ]),
  );
}

/// Wooden rim + felt rounded table.
class C3Felt extends StatelessWidget {
  final Color felt;
  final Widget? child;
  const C3Felt({super.key, required this.felt, this.child});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final rr = (c.maxHeight < c.maxWidth ? c.maxHeight : c.maxWidth) * 0.3;
      final r = BorderRadius.circular(rr.clamp(12, 200).toDouble());
      final hsl = HSLColor.fromColor(felt);
      final hi = hsl.withLightness((hsl.lightness + 0.1).clamp(0, 1)).toColor();
      return Container(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8D6E63), Color(0xFF4E342E)]),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(6),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: RadialGradient(colors: [hi, felt], radius: 0.95),
            border: Border.all(color: Colors.black26, width: 2),
          ),
          child: child,
        ),
      );
    });
  }
}

Color c3FeltColor(GameContext g, [Color tint = const Color(0xFF0B6B3A)]) => Color.lerp(g.table, tint, 0.45)!;

/// Opponent panels in one or two rows, each scaled down to fit.
Widget c3Opponents(List<int> others, Widget Function(int s) panel, double width) {
  if (others.isEmpty) return const SizedBox();
  final perRow = width < 600 ? 3 : 6;
  final rows = <List<int>>[];
  if (others.length <= perRow) {
    rows.add(others);
  } else {
    final half = (others.length + 1) ~/ 2;
    rows
      ..add(others.sublist(0, half))
      ..add(others.sublist(half));
  }
  return Column(mainAxisSize: MainAxisSize.min, children: [
    for (final r in rows)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in r) Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: panel(s))),
        ]),
      ),
  ]);
}

/// "继续下一局" button for round-end banners.
Widget c3Continue(GameContext g) {
  final ready = (g.view['ready'] as List?)?.map((e) => e == true).toList();
  final me = g.seat;
  if (ready == null || me < 0 || me >= ready.length || g.view['phase'] == 'over') return const SizedBox();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton(
      onPressed: ready[me] ? null : () => g.act({'type': 'continue'}),
      child: Text(ready[me] ? '等待其他玩家…' : '继续下一局'),
    ),
  );
}

void c3Toast(BuildContext context, String t) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 1)));

/// Selectable fanned hand. [sel] holds indices; [enabled] limits tappable cards.
class C3Hand extends StatelessWidget {
  final List<String> cards;
  final Set<int> sel;
  final double cw;
  final double maxW;
  final void Function(int i) onToggle;
  final bool Function(int i)? enabled;
  final String? label;
  const C3Hand(
      {super.key,
      required this.cards,
      required this.sel,
      required this.cw,
      required this.maxW,
      required this.onToggle,
      this.enabled,
      this.label});

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    if (n == 0) return SizedBox(height: cw * 1.7);
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.2, cw * 0.66).toDouble();
    final total = cw + step * (n - 1);
    int idx(double x) => (x / step).floor().clamp(0, n - 1);
    return SizedBox(
      width: total,
      height: cw * 1.4 + cw * 0.3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final i = idx(d.localPosition.dx);
          if (enabled == null || enabled!(i)) onToggle(i);
        },
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: step * i,
              bottom: 0,
              child: PlayingCard(cards[i],
                  width: cw, selected: sel.contains(i), dim: enabled != null && !enabled!(i)),
            ),
          if (label != null) Positioned(right: 0, top: 0, child: c3Pill(label!, Colors.deepPurple, fontSize: 11)),
        ]),
      ),
    );
  }
}
