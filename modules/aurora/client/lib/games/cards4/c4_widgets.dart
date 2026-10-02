import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Helpers shared by the cards4 boards (够级 / 保皇 / 双扣 / Gin Rummy).

List<int> c4Ints(Object? l) => [for (final x in (l as List? ?? const [])) (x as num).toInt()];
List<String> c4Strs(Object? l) => [for (final x in (l as List? ?? const [])) '$x'];
int c4Int(Object? x, [int d = -1]) => x is num ? x.toInt() : d;

/// 保皇 special cards: 'EJ' 皇帝牌, 'GJ' 侍卫牌.
class _SpecialCard extends StatelessWidget {
  final String code;
  final double width;
  final bool selected;
  final bool dim;
  const _SpecialCard(this.code, {required this.width, this.selected = false, this.dim = false});
  @override
  Widget build(BuildContext context) {
    final emperor = code == 'EJ';
    final color = emperor ? const Color(0xFFB8860B) : const Color(0xFFC62828);
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: width * 1.4,
      transform: Matrix4.translationValues(0, selected ? -width * 0.3 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: emperor ? const [Color(0xFFFFF8E1), Color(0xFFFFE082)] : const [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
        ),
        border: selected ? Border.all(color: Colors.amber, width: 2) : Border.all(color: color.withValues(alpha: 0.6)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(1, 2))],
      ),
      child: Padding(
        padding: EdgeInsets.all(width * 0.06),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(emperor ? Icons.workspace_premium : Icons.shield, color: color, size: 30),
            Text(emperor ? '皇帝' : '侍卫',
                style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16, fontFamilyFallback: kFontFallback)),
            if (!emperor) Text('大王', style: TextStyle(color: color, fontSize: 11, fontFamilyFallback: kFontFallback)),
          ]),
        ),
      ),
    );
    if (dim) card = Opacity(opacity: 0.5, child: card);
    return card;
  }
}

/// Any card code (incl. 'back', 'EJ', 'GJ') at width [w].
Widget c4Face(String code, double w, {bool selected = false, bool dim = false}) {
  if (code == 'EJ' || code == 'GJ') return _SpecialCard(code, width: w, selected: selected, dim: dim);
  return PlayingCard(code, width: w, faceDown: code == 'back', selected: selected, dim: dim);
}

/// A card rendered at a legible base size and scaled to [w].
Widget c4Card(String code, double w, {bool dim = false, bool highlight = false}) {
  Widget c = SizedBox(width: w, height: w * 1.4, child: FittedBox(child: c4Face(code, 48, dim: dim)));
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

Widget c4Pill(String t, Color c, {double fontSize = 12}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize)),
    );

Widget c4Delta(int d, {double fontSize = 14}) => Text(d > 0 ? '+$d' : '$d',
    style: TextStyle(
        color: d > 0 ? Colors.green : (d < 0 ? Colors.redAccent : Colors.grey), fontWeight: FontWeight.bold, fontSize: fontSize));

/// A row of overlapped cards.
Widget c4Row(List<String> cards, double w, {double gap = 0.5, bool dim = false, Set<String> hi = const {}}) {
  if (cards.isEmpty) return SizedBox(height: w * 1.4);
  return SizedBox(
    width: w + (cards.length - 1) * w * gap,
    height: w * 1.4,
    child: Stack(children: [
      for (var i = 0; i < cards.length; i++)
        Positioned(left: i * w * gap, child: c4Card(cards[i], w, dim: dim, highlight: hi.contains(cards[i]))),
    ]),
  );
}

/// Overlapped cards wrapped onto several rows (for 30+ card hands in results).
Widget c4Rows(List<String> cards, double w, {int perRow = 18, double gap = 0.4}) {
  if (cards.isEmpty) return const SizedBox();
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    for (var i = 0; i < cards.length; i += perRow)
      c4Row(cards.sublist(i, (i + perRow).clamp(0, cards.length)), w, gap: gap),
  ]);
}

/// Small stack of face-down cards showing a hand size.
Widget c4Backs(int n, double w) {
  if (n <= 0) return SizedBox(width: w * 0.6, height: w * 0.84);
  final k = n.clamp(1, 10);
  return SizedBox(
    width: w * 0.6 + (k - 1) * 3.0,
    height: w * 0.84,
    child: Stack(children: [for (var i = 0; i < k; i++) Positioned(left: i * 3.0, child: c4Card('back', w * 0.6))]),
  );
}

/// Wooden rim + felt rounded table.
class C4Felt extends StatelessWidget {
  final Color felt;
  final Widget? child;
  const C4Felt({super.key, required this.felt, this.child});
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
        padding: const EdgeInsets.all(5),
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

Color c4FeltColor(GameContext g, [Color tint = const Color(0xFF0B6B3A)]) => Color.lerp(g.table, tint, 0.45)!;

/// Opponent panels in one or two rows, each scaled down to fit.
Widget c4Opponents(List<int> others, Widget Function(int s) panel, double width) {
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final s in r) Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: panel(s))),
        ]),
      ),
  ]);
}

/// "继续下一局" button for round-end banners.
Widget c4Continue(GameContext g) {
  final ready = (g.view['ready'] as List?)?.map((e) => e == true).toList();
  final me = g.seat;
  if (ready == null || me < 0 || me >= ready.length || g.view['phase'] == 'over' || g.replay) return const SizedBox();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton(
      onPressed: ready[me] ? null : () => g.act({'type': 'continue'}),
      child: Text(ready[me] ? '等待其他玩家…' : '继续下一局'),
    ),
  );
}

void c4Toast(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 1)));

/// Layout of a big hand wrapped onto up to [maxRows] overlapped rows.
class C4HandLayout {
  final double cw;
  final int perRow;
  final int rows;
  final double step;
  const C4HandLayout(this.cw, this.perRow, this.rows, this.step);
  double get rowGap => cw * 0.62;
  double get height => rows == 0 ? cw * 1.4 : cw * 1.4 + (rows - 1) * rowGap + cw * 0.32;

  static C4HandLayout compute(int n, double maxW, double cw, {int maxRows = 3, double minStep = 0.4}) {
    var w = cw;
    while (true) {
      final per = n <= 1 ? 1 : ((maxW - w) / (w * minStep)).floor() + 1;
      final rows = n == 0 ? 0 : (n / per).ceil();
      if (rows <= maxRows || w < 22) {
        final perRow = n == 0 ? 1 : (n / rows.clamp(1, 99)).ceil();
        var step = perRow <= 1 ? w : (maxW - w) / (perRow - 1);
        step = step.clamp(w * 0.2, w * 0.7).toDouble();
        return C4HandLayout(w, perRow, rows, step);
      }
      w *= 0.9;
    }
  }
}

/// Selectable hand wrapped onto multiple rows. [sel] holds indices.
class C4Hand extends StatelessWidget {
  final List<String> cards;
  final Set<int> sel;
  final C4HandLayout layout;
  final void Function(int i) onToggle;
  final String? label;
  const C4Hand({super.key, required this.cards, required this.sel, required this.layout, required this.onToggle, this.label});

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    final l = layout;
    if (n == 0) return SizedBox(height: l.cw * 1.4);
    final rows = <List<int>>[];
    for (var i = 0; i < n; i += l.perRow) {
      rows.add([for (var k = i; k < n && k < i + l.perRow; k++) k]);
    }
    final width = l.cw + l.step * (l.perRow - 1);
    return SizedBox(
      width: width,
      height: l.height,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var r = 0; r < rows.length; r++)
          Positioned(
            left: 0,
            right: 0,
            top: l.cw * 0.32 + r * l.rowGap,
            height: l.cw * 1.4,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final k = (d.localPosition.dx / l.step).floor().clamp(0, rows[r].length - 1);
                onToggle(rows[r][k]);
              },
              child: Stack(clipBehavior: Clip.none, children: [
                for (var k = 0; k < rows[r].length; k++)
                  Positioned(left: l.step * k, top: 0, child: c4Face(cards[rows[r][k]], l.cw, selected: sel.contains(rows[r][k]))),
              ]),
            ),
          ),
        if (label != null) Positioned(right: 0, top: 0, child: c4Pill(label!, Colors.deepPurple, fontSize: 11)),
      ]),
    );
  }
}

/// Recent log lines (small, translucent).
Widget c4Log(List<String> lines, {int max = 3}) {
  final l = lines.length > max ? lines.sublist(lines.length - max) : lines;
  if (l.isEmpty) return const SizedBox();
  return Column(mainAxisSize: MainAxisSize.min, children: [
    for (final s in l)
      Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11)),
  ]);
}
