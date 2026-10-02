import 'package:flutter/material.dart';

import '../../widgets/pieces.dart';

/// Small helpers shared by the pokerplus boards.

/// A card rendered at a legible base size and scaled down to [w] (avoids face overflow).
Widget ppCard(String code, double w, {bool dim = false, bool highlight = false}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back', dim: dim)),
  );
  if (highlight) {
    c = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        boxShadow: const [BoxShadow(color: Colors.amberAccent, blurRadius: 6, spreadRadius: 1)],
      ),
      child: c,
    );
  }
  return c;
}

/// A dashed placeholder for an empty card slot.
Widget ppSlot(double w) => Container(
      width: w,
      height: w * 1.4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        border: Border.all(color: Colors.white24, width: 1.2),
        color: Colors.black.withValues(alpha: 0.08),
      ),
    );

/// Colored pill with white bold text.
Widget ppChip(String t, Color c, {double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
    );

/// Round badge like the dealer button.
Widget ppDisc(String t, Color bg, Color fg, {double size = 20}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(t, style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: size * 0.55)),
        ),
      ),
    );

Color chipColor(int amount) {
  if (amount >= 1000) return const Color(0xFF212121);
  if (amount >= 500) return const Color(0xFF6A1B9A);
  if (amount >= 100) return const Color(0xFF1565C0);
  if (amount >= 25) return const Color(0xFF2E7D32);
  return const Color(0xFFC62828);
}

/// A stack of casino chips with the amount next to it.
class ChipStack extends StatelessWidget {
  final int amount;
  final double size;
  const ChipStack(this.amount, {super.key, this.size = 18});
  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox();
    final n = amount >= 500 ? 3 : (amount >= 50 ? 2 : 1);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        height: size + (n - 1) * 3,
        child: Stack(children: [
          for (var i = 0; i < n; i++)
            Positioned(
              bottom: i * 3.0,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chipColor(amount),
                  border: Border.all(color: Colors.white, width: size * 0.14),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1))],
                ),
              ),
            ),
        ]),
      ),
      const SizedBox(width: 3),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text('$amount', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: size * 0.7)),
      ),
    ]);
  }
}

/// Wooden rim + felt oval table.
class FeltTable extends StatelessWidget {
  final Color felt;
  final Widget? child;
  final bool semicircle;
  const FeltTable({super.key, required this.felt, this.child, this.semicircle = false});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final r = semicircle
          ? BorderRadius.only(
              bottomLeft: Radius.circular(c.maxWidth / 2),
              bottomRight: Radius.circular(c.maxWidth / 2),
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18))
          : BorderRadius.circular(c.maxHeight < c.maxWidth ? c.maxHeight / 2 : c.maxWidth / 2);
      final light = HSLColor.fromColor(felt);
      final hi = light.withLightness((light.lightness + 0.1).clamp(0, 1)).toColor();
      return Container(
        decoration: BoxDecoration(
          borderRadius: r,
          color: const Color(0xFF5D4037),
          gradient: const LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8D6E63), Color(0xFF4E342E)]),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 14, offset: Offset(0, 5))],
        ),
        padding: const EdgeInsets.all(9),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: RadialGradient(colors: [hi, felt], radius: 0.9),
            border: Border.all(color: Colors.black26, width: 2),
          ),
          child: child,
        ),
      );
    });
  }
}
