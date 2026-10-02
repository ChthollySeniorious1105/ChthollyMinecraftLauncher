import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Shared widgets for the 4-player partnership card tables (掼蛋 / 升级).

String tcTeamName(int team) => team == 0 ? '南北队' : '东西队';

Widget tcChip(String t, Color c, {double font = 13}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
      child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: font)),
    );

Widget tcBadge(String t, Color c) => Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
    );

/// Small card rendered at a legible base size and scaled down.
Widget tcMini(String code, double w, {bool mark = false, Color markColor = Colors.amber}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back')),
  );
  if (mark) {
    c = Stack(children: [
      c,
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.1),
              border: Border.all(color: markColor, width: 2),
            ),
          ),
        ),
      ),
    ]);
  }
  return c;
}

/// Overlapping row of small cards.
Widget tcCards(List<String> cards, double w, {double maxW = 400, bool Function(String)? mark, Color markColor = Colors.amber}) {
  if (cards.isEmpty) return const SizedBox();
  return ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxW),
    child: OverlapRow(
      itemWidth: w,
      maxSpacing: 0.45,
      minSpacing: 0.16,
      children: [for (final c in cards) tcMini(c, w, mark: mark?.call(c) ?? false, markColor: markColor)],
    ),
  );
}

/// Four-seat table: partner on top, opponents left/right, [center] in the middle, me at the bottom.
class TcTable extends StatelessWidget {
  final GameContext g;
  final Widget Function(int seat, double cardW, double maxW) panel;
  final Widget center;
  final Widget info;
  final Widget bottom;
  final Widget? overlay;
  const TcTable({super.key, required this.g, required this.panel, required this.center, required this.info, required this.bottom, this.overlay});

  @override
  Widget build(BuildContext context) {
    final order = g.seatsFromMe();
    final right = order[1], top = order[2], left = order[3];
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final byW = c.maxWidth / 20, byH = c.maxHeight / 12;
        final small = (byW < byH ? byW : byH).clamp(26.0, 54.0).toDouble();
        final sideW = (c.maxWidth * 0.26).clamp(96.0, 300.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            info,
            const SizedBox(height: 4),
            Expanded(
              child: Column(children: [
                Flexible(
                  flex: 2,
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: panel(top, small, c.maxWidth * 0.6)),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Row(children: [
                    SizedBox(
                      width: sideW,
                      child: FittedBox(fit: BoxFit.scaleDown, child: panel(left, small, sideW - 4)),
                    ),
                    Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: center)),
                    SizedBox(
                      width: sideW,
                      child: FittedBox(fit: BoxFit.scaleDown, child: panel(right, small, sideW - 4)),
                    ),
                  ]),
                ),
              ]),
            ),
            bottom,
            const SizedBox(height: 6),
          ]),
          if (overlay != null) Positioned.fill(child: Center(child: SingleChildScrollView(child: overlay!))),
        ]);
      }),
    );
  }
}

/// Card in my hand with selection lift and an optional corner mark (主 / 配).
class TcHandCard extends StatelessWidget {
  final String code;
  final double width;
  final bool selected;
  final String? mark;
  final Color markColor;
  const TcHandCard(this.code, {super.key, required this.width, this.selected = false, this.mark, this.markColor = Colors.deepOrange});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      transform: Matrix4.translationValues(0, selected ? -width * 0.3 : 0, 0),
      child: Stack(children: [
        PlayingCard(code, width: width),
        if (mark != null)
          Positioned(
            left: width * 0.04,
            top: width * 0.58,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: width * 0.06),
              decoration: BoxDecoration(color: markColor, borderRadius: BorderRadius.circular(width * 0.08)),
              child: Text(mark!, style: TextStyle(fontSize: width * 0.22, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.1),
                  border: Border.all(color: Colors.amber, width: 2.5),
                  color: Colors.amber.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// My fanned hand with tap / drag selection. Splits into two rows when too crowded.
class TcHand extends StatefulWidget {
  final List<String> cards;
  final Set<int> selected;
  final double cardW;
  final double maxW;
  final bool interactive;
  final String? Function(String code)? mark;
  final Color Function(String code)? markColor;
  final void Function(Set<int> sel) onChanged;
  const TcHand({
    super.key,
    required this.cards,
    required this.selected,
    required this.cardW,
    required this.maxW,
    required this.onChanged,
    this.interactive = true,
    this.mark,
    this.markColor,
  });

  @override
  State<TcHand> createState() => _TcHandState();
}

class _TcHandState extends State<TcHand> {
  final Set<int> _dragSeen = {};
  bool _dragAdd = true;

  void _set(int i, bool add) {
    final s = Set<int>.of(widget.selected);
    add ? s.add(i) : s.remove(i);
    widget.onChanged(s);
  }

  Widget _row(int from, int to, double cw) {
    final n = to - from;
    var step = n <= 1 ? cw : (widget.maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.2, cw * 0.62).toDouble();
    final total = cw + step * (n - 1);
    int idx(double x) => from + (x / step).floor().clamp(0, n - 1);
    final cards = widget.cards;
    Widget stack = SizedBox(
      width: total,
      height: cw * 1.4 + cw * 0.3,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = from; i < to; i++)
          Positioned(
            left: step * (i - from),
            bottom: 0,
            child: TcHandCard(cards[i],
                width: cw,
                selected: widget.selected.contains(i),
                mark: widget.mark?.call(cards[i]),
                markColor: widget.markColor?.call(cards[i]) ?? Colors.deepOrange),
          ),
      ]),
    );
    if (!widget.interactive) return stack;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final i = idx(d.localPosition.dx);
        _set(i, !widget.selected.contains(i));
      },
      onHorizontalDragStart: (d) {
        final i = idx(d.localPosition.dx);
        _dragSeen
          ..clear()
          ..add(i);
        _dragAdd = !widget.selected.contains(i);
        _set(i, _dragAdd);
      },
      onHorizontalDragUpdate: (d) {
        final i = idx(d.localPosition.dx);
        if (_dragSeen.add(i)) _set(i, _dragAdd);
      },
      child: stack,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cards.length;
    var cw = widget.cardW;
    if (n == 0) return SizedBox(height: cw * 1.7);
    final step = n <= 1 ? cw : (widget.maxW - cw) / (n - 1);
    if (step >= cw * 0.6 || n < 14) return _row(0, n, cw);
    // two rows with bigger cards (phones in portrait)
    final half = (n + 1) ~/ 2;
    final fit = widget.maxW / (1 + 0.42 * (half - 1));
    cw = cw * 1.3 < fit ? cw * 1.3 : fit;
    final rowH = cw * 1.7;
    final offset = cw * 0.9;
    return SizedBox(
      height: rowH + offset,
      width: widget.maxW,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(top: 0, left: 0, right: 0, child: Center(child: _row(0, half, cw))),
        Positioned(top: offset, left: 0, right: 0, child: Center(child: _row(half, n, cw))),
      ]),
    );
  }
}

/// Compact pill describing a seat's last action / state.
Widget tcNote(String t, {Color color = Colors.black54}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
