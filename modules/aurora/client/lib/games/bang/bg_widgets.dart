import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Small helpers shared by the bang package boards (蟑螂扑克 / 西部无间道).

List<int> bgInts(Object? l) => [for (final x in (l as List? ?? const [])) (x as num).toInt()];
int bgInt(Object? v, [int d = -1]) => v is num ? v.toInt() : d;

Widget bgChip(String t, Color c, {double fontSize = 12, IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: fontSize + 2, color: Colors.white), const SizedBox(width: 3)],
        Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize, fontFamilyFallback: kFontFallback)),
      ]),
    );

/// Emoji text that renders with colour-emoji fallbacks.
Text bgEmoji(String e, double size) => Text(e, style: TextStyle(fontSize: size, height: 1.1, fontFamilyFallback: kFontFallback));

/// Rounded felt panel used as the table centre.
class BgFelt extends StatelessWidget {
  final Color felt;
  final Widget child;
  const BgFelt({super.key, required this.felt, required this.child});
  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(felt);
    final hi = hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8D6E63), Color(0xFF4E342E)]),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: RadialGradient(colors: [hi, felt], radius: 1.1),
        ),
        child: child,
      ),
    );
  }
}

/// Panel frame for a player seat.
Widget bgPanel(BuildContext context, {required Widget child, bool active = false, bool picked = false, bool pickable = false, bool dead = false, VoidCallback? onTap}) {
  final cs = Theme.of(context).colorScheme;
  final border = picked ? Colors.amberAccent : (active ? cs.primary : (pickable ? Colors.lightGreenAccent.withValues(alpha: 0.8) : Colors.white24));
  return GestureDetector(
    onTap: onTap,
    child: Opacity(
      opacity: dead ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: (picked ? Colors.amber.withValues(alpha: 0.22) : cs.surface.withValues(alpha: 0.72)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: picked || active || pickable ? 2.2 : 1),
          boxShadow: [if (active) BoxShadow(color: cs.primary.withValues(alpha: 0.4), blurRadius: 8)],
        ),
        child: child,
      ),
    ),
  );
}

/// Lays [panels] out in [rows] rows of equal-width cells, each scaled down to fit.
Widget bgPanelGrid(List<Widget> panels, int rows, double height) {
  if (panels.isEmpty) return const SizedBox();
  final per = (panels.length / rows).ceil();
  return SizedBox(
    height: height,
    child: Column(children: [
      for (var r = 0; r < rows; r++)
        if (r * per < panels.length)
          Expanded(
            child: Row(children: [
              for (var i = r * per; i < (r + 1) * per; i++)
                Expanded(
                  child: i < panels.length
                      ? Padding(
                          padding: const EdgeInsets.all(2),
                          child: FittedBox(fit: BoxFit.scaleDown, child: panels[i]),
                        )
                      : const SizedBox(),
                ),
            ]),
          ),
    ]),
  );
}

/// Last few log lines.
Widget bgLog(List<String> lines, {int max = 5, double fontSize = 12}) {
  final l = lines.length > max ? lines.sublist(lines.length - max) : lines;
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (var i = 0; i < l.length; i++)
      Text(l[i],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: fontSize,
            fontFamilyFallback: kFontFallback,
            color: i == l.length - 1 ? Colors.white : Colors.white70,
            fontWeight: i == l.length - 1 ? FontWeight.bold : FontWeight.normal,
          )),
  ]);
}

/// Final ranking banner.
Widget bgResult(GameContext g, String title, List<int> placings, String Function(int s) detail) {
  final order = List.generate(g.players, (i) => i)..sort((a, b) => placings[a] - placings[b]);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: ResultBanner(
      title,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final s in order)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                  width: 34,
                  child: Text('#${placings[s]}', style: TextStyle(fontWeight: FontWeight.bold, color: placings[s] == 1 ? Colors.amber.shade700 : null))),
              SizedBox(width: 100, child: Text(g.name(s), overflow: TextOverflow.ellipsis)),
              SizedBox(
                  width: 150,
                  child: Text(detail(s),
                      textAlign: TextAlign.right, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontFamilyFallback: kFontFallback))),
            ]),
          ),
      ]),
    ),
  );
}
