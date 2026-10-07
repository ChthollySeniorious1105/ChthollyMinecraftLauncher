import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'fm_widgets.dart';

/// 抽乌龟
class OldMaidBoard extends StatelessWidget {
  final GameContext g;
  const OldMaidBoard(this.g, {super.key});

  Map<String, dynamic> get v => g.view;

  String _cardName(String c) {
    if (c == 'RJ') return '大王';
    const sym = {'S': '♠', 'H': '♥', 'C': '♣', 'D': '♦'};
    return '${sym[c[c.length - 1]] ?? ''}${fmRankLabel(c[0])}';
  }

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = (v['turn'] as num).toInt();
    final target = (v['target'] as num).toInt();
    final me = g.seat;
    final myTurn = !over && me >= 0 && turn == me;
    final counts = fmInts(v['counts']);
    final pairs = fmInts(v['pairs']);
    final finish = fmInts(v['finish']);
    final hand = fmStrs(v['hand']);
    final last = v['last'] as Map?;
    final lastCard = v['lastCard'] as String?;
    final joker = v['mode'] == 'joker';

    String status;
    if (over) {
      final l = (v['loser'] as num).toInt();
      status = l >= 0 ? '${g.name(l)} 是乌龟！' : '游戏结束';
    } else if (myTurn) {
      status = '轮到你：抽 ${g.name(target)} 一张牌';
    } else if (me >= 0 && target == me) {
      status = '${g.name(turn)} 正在抽你的牌…';
    } else {
      status = '${g.name(turn)} 正在抽 ${g.name(target)} 的牌';
    }

    String? lastText;
    if (last != null) {
      final f = (last['from'] as num).toInt(), t = (last['to'] as num).toInt();
      final pair = last['pair'] as List?;
      final who = f == me ? '你' : g.name(f);
      final whom = t == me ? '你' : g.name(t);
      if (pair != null) {
        lastText = '$who 抽了 $whom 的${lastCard != null ? ' ${_cardName(lastCard)}' : '一张牌'}，配成一对';
      } else {
        lastText = '$who 抽了 $whom 的${lastCard != null ? ' ${_cardName(lastCard)}' : '一张牌'}，没配上';
      }
    }

    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        final cw = (c.maxWidth / (narrow ? 8.5 : 16)).clamp(34.0, 64.0).toDouble();
        final byH = (c.maxHeight / 7.0).clamp(30.0, 64.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              fmChip(joker ? '大王是乌龟' : '暗牌乌龟', Colors.deepPurple),
              fmChip('已打出 ${v['discardCount']} 对', Colors.teal),
              if (finish.isNotEmpty) fmChip('已上岸 ${finish.length} 人', Colors.green),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in others)
                  Expanded(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _panel(s, w * 0.8, counts[s], pairs[s], finish.indexOf(s), !over && s == turn, !over && s == target))),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : c.maxWidth * 0.08, vertical: 2),
                child: FmFelt(
                  felt: fmFelt(g),
                  child: LayoutBuilder(builder: (context, fc) => _center(fc, w, over, myTurn, turn, target, counts, lastText)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                g.tag(me, active: myTurn || (!over && target == me), size: 30, sub: '手牌 ${counts[me]} · 配对 ${pairs[me]}'),
                if (finish.contains(me)) fmChip('第 ${finish.indexOf(me) + 1} 个上岸', Colors.green),
                if (!over && me == target) fmChip('被抽中', Colors.deepOrange),
              ]),
              const SizedBox(height: 4),
              FmHand(hand,
                  cardW: w,
                  maxW: c.maxWidth - 16,
                  glow: {
                    for (var i = 0; i < hand.length; i++)
                      if (hand[i] == lastCard && last != null && (last['from'] as num).toInt() == me) i
                  }),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (over) Center(child: _result()),
        ]);
      }),
    );
  }

  Widget _panel(int s, double w, int count, int pairs, int fin, bool drawing, bool target) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s, active: drawing, size: 32, sub: fin >= 0 ? '已上岸 · 第${fin + 1}' : '$count张 · $pairs对'),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          fmBacks(count, w),
          if (target) ...[const SizedBox(width: 4), fmChip('被抽', Colors.deepOrange, fontSize: 11)],
          if (drawing) ...[const SizedBox(width: 4), fmChip('抽牌中', Colors.indigo, fontSize: 11)],
        ]),
      ]),
    );
  }

  Widget _center(BoxConstraints fc, double w, bool over, bool myTurn, int turn, int target, List<int> counts, String? lastText) {
    final discards = [for (final p in (v['discards'] as List? ?? const [])) fmStrs(p)];
    final children = <Widget>[];
    if (!over && target >= 0) {
      final n = counts[target];
      final tw = (w * 1.15).clamp(30.0, 74.0).toDouble();
      final maxW = fc.maxWidth - 40;
      children.add(Text(myTurn ? '${g.name(target)} 的手牌 · 点一张抽走' : '${g.name(turn)} 抽 ${g.name(target)} 的牌',
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)));
      children.add(const SizedBox(height: 6));
      children.add(target == g.seat
          ? Text('（你的牌在下方）', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12))
          : FmHand(List.filled(n, 'back'),
              cardW: tw,
              maxW: maxW,
              maxStep: 1.12,
              glow: myTurn ? {for (var i = 0; i < n; i++) i} : const {},
              onTap: myTurn ? (i) => g.act({'type': 'draw', 'index': i}) : null));
    }
    if (lastText != null) {
      children.add(const SizedBox(height: 8));
      children.add(fmChip(lastText, Colors.black54, fontSize: 12));
    }
    if (discards.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final p in discards.length > 6 ? discards.sublist(discards.length - 6) : discards)
          SizedBox(
            width: w * 0.75 + w * 0.35,
            height: w * 0.75 * 1.4,
            child: Stack(children: [
              Positioned(left: 0, child: fmCard(p[0], w * 0.75)),
              Positioned(left: w * 0.35, child: fmCard(p[1], w * 0.75)),
            ]),
          ),
      ]));
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: fc.maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ),
      ),
    );
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final pl = fmInts(r?['placings']);
    if (pl.length != g.players) return const SizedBox();
    final loser = (v['loser'] as num).toInt();
    final hands = v['hands'] as List?;
    final removed = v['removed'] as String?;
    final finish = fmInts(v['finish']);
    return fmResult(
      g,
      loser >= 0 ? '${g.name(loser)} 是乌龟！' : '游戏结束',
      pl,
      (s) {
        if (finish.contains(s)) return '第 ${finish.indexOf(s) + 1} 个上岸';
        final h = hands == null ? const [] : (hands[s] as List);
        return h.isEmpty ? '' : '剩 ${h.map((c) => _cardName('$c')).join(' ')}';
      },
      extra: removed != null && removed.isNotEmpty
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('被抽掉的暗牌：', style: TextStyle(fontSize: 13)),
              fmCard(removed, 30),
            ])
          : null,
    );
  }
}
