import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Small helpers shared by the family boards (抽乌龟/钓鱼/牌七).

List<int> fmInts(Object? l) => [for (final x in (l as List? ?? const [])) (x as num).toInt()];
List<String> fmStrs(Object? l) => [for (final x in (l as List? ?? const [])) '$x'];
String fmRankLabel(String r) => r == 'T' ? '10' : r;

/// A card rendered at a legible base size and scaled to [w].
Widget fmCard(String code, double w, {bool dim = false, bool highlight = false, bool selected = false}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back', dim: dim, selected: selected)),
  );
  if (highlight) {
    c = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        boxShadow: const [BoxShadow(color: Colors.amberAccent, blurRadius: 7, spreadRadius: 1.5)],
      ),
      child: c,
    );
  }
  return c;
}

/// Dashed-ish empty slot.
Widget fmSlot(double w, {String? label}) => Container(
      width: w,
      height: w * 1.4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        border: Border.all(color: Colors.white24, width: 1.2),
        color: Colors.black.withValues(alpha: 0.10),
      ),
      child: label == null
          ? null
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Text(label, style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold, fontSize: w * 0.4)),
              ),
            ),
    );

Widget fmChip(String t, Color c, {double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
    );

/// Small fan of face-down cards showing a hand size.
Widget fmBacks(int n, double w, {int maxShown = 10}) {
  if (n <= 0) return SizedBox(width: w * 0.6, height: w * 0.84);
  final k = n.clamp(1, maxShown);
  return SizedBox(
    width: w * 0.6 + (k - 1) * 3.0,
    height: w * 0.84,
    child: Stack(children: [
      for (var i = 0; i < k; i++) Positioned(left: i * 3.0, child: fmCard('back', w * 0.6)),
    ]),
  );
}

/// Felt table with a wooden rim.
class FmFelt extends StatelessWidget {
  final Color felt;
  final Widget? child;
  const FmFelt({super.key, required this.felt, this.child});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final rr = (c.maxHeight < c.maxWidth ? c.maxHeight : c.maxWidth) * 0.18;
      final r = BorderRadius.circular(rr.clamp(10, 80).toDouble());
      final hsl = HSLColor.fromColor(felt);
      final hi = hsl.withLightness((hsl.lightness + 0.1).clamp(0, 1)).toColor();
      return Container(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8D6E63), Color(0xFF4E342E)]),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(7),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: RadialGradient(colors: [hi, felt], radius: 1.0),
            border: Border.all(color: Colors.black26, width: 2),
          ),
          child: child,
        ),
      );
    });
  }
}

Color fmFelt(GameContext g) => Color.lerp(g.table, const Color(0xFF0B6B3A), 0.45)!;

/// The player's own hand: overlapped cards fitted to [maxW]; tap callback per index.
class FmHand extends StatelessWidget {
  final List<String> cards;
  final double cardW;
  final double maxW;
  final Set<int> selected;
  final Set<int> dim;
  final Set<int> glow;
  final void Function(int i)? onTap;
  final double maxStep;
  const FmHand(this.cards,
      {super.key,
      required this.cardW,
      required this.maxW,
      this.selected = const {},
      this.dim = const {},
      this.glow = const {},
      this.onTap,
      this.maxStep = 0.7});

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    if (n == 0) return SizedBox(height: cardW * 1.4 + cardW * 0.25);
    var step = n <= 1 ? cardW : (maxW - cardW) / (n - 1);
    step = step.clamp(cardW * 0.18, cardW * maxStep).toDouble();
    final total = cardW + step * (n - 1);
    final w = total > maxW ? maxW : total;
    if (total > maxW) step = n <= 1 ? 0 : (maxW - cardW) / (n - 1);
    int idx(double x) => (x / step).floor().clamp(0, n - 1);
    return SizedBox(
      width: w,
      height: cardW * 1.4 + cardW * 0.25,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTap == null ? null : (d) => onTap!(idx(d.localPosition.dx)),
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: step * i,
              bottom: selected.contains(i) ? cardW * 0.25 : 0,
              child: fmCard(cards[i], cardW, dim: dim.contains(i), highlight: glow.contains(i)),
            ),
        ]),
      ),
    );
  }
}

/// Final ranking banner.
Widget fmResult(GameContext g, String title, List<int> placings, String Function(int s) detail, {Widget? extra}) {
  final order = List.generate(g.players, (i) => i)..sort((a, b) => placings[a] - placings[b]);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 380),
    child: ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (extra != null) ...[extra, const SizedBox(height: 6)],
        for (final s in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 34,
                  child: Text('#${placings[s]}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: placings[s] == 1 ? Colors.amber.shade700 : null))),
              SizedBox(width: 110, child: Text(g.name(s), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 120, child: Text(detail(s), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ]),
    ),
  );
}
