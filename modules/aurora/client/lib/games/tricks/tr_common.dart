import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

/// Shared widgets for 4-player trick-taking tables (桥牌 / 红心大战 / 黑桃王).

const Map<String, String> trSym = {'C': '♣', 'D': '♦', 'H': '♥', 'S': '♠'};
const List<String> trDispSuits = ['S', 'H', 'C', 'D'];

List<String> trList(Object? v) => v is List ? [for (final e in v) '$e'] : <String>[];

bool trRed(String suit) => suit == 'H' || suit == 'D';

String trCard(String c) => '${trSym[c[1]]}${c[0] == 'T' ? '10' : c[0]}';

Widget trChip(String t, Color c, {double font = 13, VoidCallback? onTap}) {
  final w = Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(12)),
    child: Text(t, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: font)),
  );
  if (onTap == null) return w;
  return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
}

Widget trBadge(String t, Color c) => Container(
      margin: const EdgeInsets.only(left: 3),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
      child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
    );

Widget trNote(String t, {Color color = Colors.black54}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );

/// Card rendered at a legible base size then scaled to [w].
Widget trMini(String code, double w, {bool mark = false, bool dim = false, VoidCallback? onTap}) {
  Widget c = SizedBox(
    width: w,
    height: w * 1.4,
    child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back', dim: dim)),
  );
  if (mark) {
    c = Stack(children: [
      c,
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.1),
              border: Border.all(color: Colors.amber, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.amber, blurRadius: 6)],
            ),
          ),
        ),
      ),
    ]);
  }
  if (onTap != null) c = MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: c));
  return c;
}

/// A stack of face-down cards with a count, for opponents' hands.
Widget trBacks(int n, double w) {
  if (n <= 0) return SizedBox(width: w, height: w * 1.4);
  return Stack(clipBehavior: Clip.none, children: [
    for (var i = 0; i < (n > 3 ? 3 : n); i++)
      Padding(padding: EdgeInsets.only(left: i * w * 0.18), child: trMini('back', w)),
    Positioned(
      right: -4,
      bottom: -4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    ),
  ]);
}

/// Face-up hand grouped by suit in rows (bridge dummy). Cards in [playable] are tappable.
Widget trSuitRows(List<String> cards, double w, {Set<String> playable = const {}, void Function(String)? onPlay}) {
  final rows = <Widget>[];
  for (final s in trDispSuits) {
    final cs = [for (final c in cards) if (c[1] == s) c];
    rows.add(SizedBox(
      height: w * 1.4 + 2,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: w * 0.55,
          child: Text(trSym[s]!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: w * 0.45, color: trRed(s) ? Colors.red.shade300 : Colors.white, fontWeight: FontWeight.bold)),
        ),
        if (cs.isEmpty) Text('—', style: TextStyle(color: Colors.white54, fontSize: w * 0.35)),
        for (var i = 0; i < cs.length; i++)
          Align(
            alignment: Alignment.centerLeft,
            widthFactor: i == cs.length - 1 ? 1 : 0.5,
            child: trMini(cs[i], w,
                mark: playable.contains(cs[i]),
                dim: playable.isNotEmpty && !playable.contains(cs[i]),
                onTap: playable.contains(cs[i]) && onPlay != null ? () => onPlay(cs[i]) : null),
          ),
      ]),
    ));
  }
  return Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
  );
}

/// The current trick: each seat's card placed toward that seat (me at the bottom).
class TrTrick extends StatelessWidget {
  final GameContext g;
  final List trick; // [{seat, card}]
  final int winner; // seat to highlight, or -1
  final double w;
  final Widget? middle;
  const TrTrick({super.key, required this.g, required this.trick, this.winner = -1, this.w = 48, this.middle});

  @override
  Widget build(BuildContext context) {
    final order = g.seatsFromMe();
    final lead = trick.isEmpty ? -1 : (trick.first as Map)['seat'] as int;
    final pos = <int, Alignment>{
      order[0]: Alignment.bottomCenter,
      order[1]: Alignment.centerRight,
      order[2]: Alignment.topCenter,
      order[3]: Alignment.centerLeft,
    };
    return SizedBox(
      width: w * 3.4,
      height: w * 3.6,
      child: Stack(children: [
        if (middle != null) Center(child: middle),
        for (final t in trick)
          Align(
            alignment: pos[(t as Map)['seat'] as int]!,
            child: Stack(clipBehavior: Clip.none, children: [
              trMini('${t['card']}', w, mark: t['seat'] == winner),
              if (t['seat'] == lead)
                Positioned(
                  top: -6,
                  left: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(6)),
                    child: const Text('首', style: TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// My hand: a fan of cards. [legal] cards are tappable (others dimmed when [dimIllegal]);
/// [selected] cards are lifted.
class TrHand extends StatelessWidget {
  final List<String> cards;
  final double cardW;
  final Set<String> legal;
  final Set<String> selected;
  final Set<String> fresh; // e.g. cards just received
  final bool dimIllegal;
  final void Function(String card)? onTap;
  const TrHand({
    super.key,
    required this.cards,
    required this.cardW,
    this.legal = const {},
    this.selected = const {},
    this.fresh = const {},
    this.dimIllegal = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return SizedBox(height: cardW * 1.7);
    return Padding(
      padding: EdgeInsets.only(top: cardW * 0.32),
      child: OverlapRow(
        itemWidth: cardW,
        maxSpacing: 0.72,
        minSpacing: 0.3,
        children: [
          for (final c in cards)
            Stack(clipBehavior: Clip.none, children: [
              PlayingCard(c,
                  width: cardW,
                  selected: selected.contains(c),
                  dim: dimIllegal && !legal.contains(c),
                  onTap: onTap != null && legal.contains(c) ? () => onTap!(c) : null),
              if (fresh.contains(c))
                Positioned(
                  left: cardW * 0.05,
                  bottom: cardW * 0.08 + (selected.contains(c) ? cardW * 0.3 : 0),
                  child: IgnorePointer(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: cardW * 0.05),
                      decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(4)),
                      child: Text('新', style: TextStyle(fontSize: cardW * 0.22, color: Colors.white)),
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}

/// Four-seat table: partner/opposite on top, others left/right, [center] in the middle,
/// [bottom] (status, controls, my hand) at the bottom.
class TrTable extends StatelessWidget {
  final GameContext g;
  final Widget Function(int seat, double cardW) panel;
  final Widget center;
  final Widget info;
  final Widget Function(double cardW, double maxW) bottom;
  final Widget? overlay;
  final int topFlex;
  const TrTable({
    super.key,
    required this.g,
    required this.panel,
    required this.center,
    required this.info,
    required this.bottom,
    this.overlay,
    this.topFlex = 2,
  });

  @override
  Widget build(BuildContext context) {
    final order = g.seatsFromMe();
    final right = order[1], top = order[2], left = order[3];
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final byW = c.maxWidth / 20, byH = c.maxHeight / 12;
        final small = (byW < byH ? byW : byH).clamp(26.0, 48.0).toDouble();
        final sideW = (c.maxWidth * 0.24).clamp(90.0, 300.0).toDouble();
        final handW = ((c.maxWidth - 16) / 9).clamp(34.0, 64.0).toDouble();
        final handH = (c.maxHeight / 8.5).clamp(30.0, 64.0).toDouble();
        final cw = handW < handH ? handW : handH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: info),
            const SizedBox(height: 4),
            Expanded(
              child: Column(children: [
                Flexible(
                  flex: topFlex,
                  child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: panel(top, small))),
                ),
                Expanded(
                  flex: 3,
                  child: Row(children: [
                    SizedBox(width: sideW, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: panel(left, small)))),
                    Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: center))),
                    SizedBox(width: sideW, child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: panel(right, small)))),
                  ]),
                ),
              ]),
            ),
            bottom(cw, c.maxWidth - 12),
            const SizedBox(height: 6),
          ]),
          if (overlay != null)
            Positioned.fill(
              child: Container(
                color: Colors.black26,
                alignment: Alignment.center,
                child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: overlay!),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Continue button for inter-hand screens.
Widget trContinue(GameContext g, List<bool>? ready) {
  final me = g.seat;
  if (ready == null || me < 0) return const SizedBox();
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton(
      onPressed: ready[me] ? null : () => g.act({'type': 'continue'}),
      child: Text(ready[me] ? '等待其他玩家…（${ready.where((r) => r).length}/4）' : '继续下一局'),
    ),
  );
}

/// Simple table with a header row, used for score sheets.
Widget trGrid(List<String> header, List<List<String>> rows, {double colW = 64, TextStyle? style}) {
  final st = style ?? const TextStyle(fontSize: 13);
  Widget cell(String t, {bool head = false}) => Container(
        width: colW,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        alignment: Alignment.center,
        child: Text(t, overflow: TextOverflow.ellipsis, style: head ? st.copyWith(fontWeight: FontWeight.bold) : st),
      );
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [for (final h in header) cell(h, head: true)]),
    const SizedBox(width: 10, height: 1, child: ColoredBox(color: Colors.transparent)),
    for (final r in rows) Row(mainAxisSize: MainAxisSize.min, children: [for (final t in r) cell(t)]),
  ]);
}
