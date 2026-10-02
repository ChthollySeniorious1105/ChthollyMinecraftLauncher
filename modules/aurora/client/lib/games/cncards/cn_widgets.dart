import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Small helpers shared by the 锄大地 / 炸金花 / 斗牛 / 十三水 boards.

List<int> cnInts(Map<String, dynamic> v, String k) => [for (final x in (v[k] as List? ?? const [])) (x as num).toInt()];
List<String> cnStrs(Object? l) => [for (final x in (l as List? ?? const [])) '$x'];

/// A card rendered at a legible base size and scaled down to [w].
Widget cnCard(String code, double w, {bool dim = false, bool highlight = false, bool selected = false}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back', dim: dim)),
  );
  if (highlight || selected) {
    c = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        boxShadow: [
          BoxShadow(color: selected ? Colors.lightBlueAccent : Colors.amberAccent, blurRadius: 6, spreadRadius: 1.5),
        ],
      ),
      child: c,
    );
  }
  return c;
}

/// Dashed-ish empty slot.
Widget cnSlot(double w, {Color? color}) => Container(
      width: w,
      height: w * 1.4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        border: Border.all(color: color ?? Colors.white30, width: 1.2),
        color: Colors.black.withValues(alpha: 0.10),
      ),
    );

/// Colored pill.
Widget cnPill(String t, Color c, {double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
    );

/// Round badge (庄 etc).
Widget cnDisc(String t, Color bg, {double size = 20}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70, width: 1.2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: size * 0.55)),
        ),
      ),
    );

/// Signed number text in green/red.
Widget cnDelta(int d, {double fontSize = 14}) => Text(d > 0 ? '+$d' : '$d',
    style: TextStyle(
        color: d > 0 ? Colors.green : (d < 0 ? Colors.redAccent : Colors.grey),
        fontWeight: FontWeight.bold,
        fontSize: fontSize));

/// A row of cards, overlapped when narrow.
Widget cnRow(List<String> cards, double w, {double gap = 0.55, Set<int> hi = const {}, bool dim = false}) {
  if (cards.isEmpty) return SizedBox(height: w * 1.4);
  return SizedBox(
    width: w + (cards.length - 1) * w * gap,
    height: w * 1.4,
    child: Stack(children: [
      for (var i = 0; i < cards.length; i++)
        Positioned(left: i * w * gap, child: cnCard(cards[i], w, highlight: hi.contains(i), dim: dim)),
    ]),
  );
}

/// Wooden rim + felt rounded table.
class CnFelt extends StatelessWidget {
  final Color felt;
  final Widget? child;
  const CnFelt({super.key, required this.felt, this.child});
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
        padding: const EdgeInsets.all(7),
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

Color cnFeltColor(GameContext g, [Color tint = const Color(0xFF0B6B3A)]) => Color.lerp(g.table, tint, 0.45)!;

/// Lays out opponent panels in one or two rows, each panel scaled down to fit.
Widget cnOpponents(List<int> others, Widget Function(int s) panel, double width) {
  if (others.isEmpty) return const SizedBox();
  final perRow = width < 600 ? 4 : 8;
  final rows = <List<int>>[];
  for (var i = 0; i < others.length; i += perRow) {
    rows.add(others.sublist(i, (i + perRow).clamp(0, others.length)));
  }
  if (rows.length == 2 && rows[1].length < rows[0].length - 1) {
    // balance the two rows
    final half = (others.length + 1) ~/ 2;
    rows
      ..clear()
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

/// The "continue" button used in round-end banners.
Widget cnContinue(GameContext g) {
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
