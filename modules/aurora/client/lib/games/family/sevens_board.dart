import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'fm_widgets.dart';

/// 牌七 / 接龙
class SevensBoard extends StatefulWidget {
  final GameContext g;
  const SevensBoard(this.g, {super.key});
  @override
  State<SevensBoard> createState() => _SevensBoardState();
}

class _SevensBoardState extends State<SevensBoard> {
  int _sel = -1;
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  static const _ranks = 'A23456789TJQK';
  static const _suits = 'SHCD';
  static const _sym = ['♠', '♥', '♣', '♦'];

  int _val(String c) => _ranks.indexOf(c[0]) + 1;

  @override
  Widget build(BuildContext context) {
    final hand = fmStrs(v['hand']);
    final k = '${hand.join(',')}|${v['turn']}';
    if (k != _key) {
      _key = k;
      _sel = -1;
    }
    final over = v['phase'] == 'over';
    final turn = (v['turn'] as num).toInt();
    final me = g.seat;
    final myTurn = !over && me >= 0 && turn == me;
    final legal = fmStrs(v['legal']).toSet();
    final cover = v['mode'] == 'cover';
    final counts = fmInts(v['counts']);
    final coverCounts = fmInts(v['coverCounts']);
    final myCovered = fmStrs(v['myCovered']);
    final stuck = myTurn && legal.isEmpty;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn) {
      if (v['first'] == true) {
        status = '你持有♥7，请先打出♥7';
      } else if (!stuck) {
        status = '轮到你：点击发光的牌出牌';
      } else {
        status = cover ? '没有牌能接！选一张牌扣下（点数计入罚分）' : '没有牌能接，只能过';
      }
    } else {
      status = '等待 ${g.name(turn)} 出牌';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    final acts = v['acts'] as List;

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        final cw = (c.maxWidth / (narrow ? 9 : 18)).clamp(30.0, 60.0).toDouble();
        final byH = (c.maxHeight / 8.0).clamp(28.0, 60.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              fmChip(cover ? '扣牌计分 · 少者胜' : '过牌 · 先出完者胜', Colors.deepPurple),
              fmChip('♥7 先出', Colors.red.shade700),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in others)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _panel(s, w * 0.8, counts[s], coverCounts[s], !over && s == turn, acts[s] as Map?, cover),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 6 : c.maxWidth * 0.06, vertical: 2),
                child: FmFelt(felt: fmFelt(g), child: _table(legal, myTurn)),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                g.tag(me,
                    active: myTurn,
                    size: 30,
                    sub: cover
                        ? '手牌 ${counts[me]} · 扣 ${myCovered.length} 张 ${myCovered.fold<int>(0, (a, c) => a + _val(c))} 分'
                        : '手牌 ${counts[me]}'),
                if (myCovered.isNotEmpty) _coveredRow(myCovered, w * 0.42),
                if (stuck && cover)
                  FilledButton.icon(
                    onPressed: _sel >= 0 && _sel < hand.length ? () => g.act({'type': 'cover', 'card': hand[_sel]}) : null,
                    icon: const Icon(Icons.flip_to_back, size: 18),
                    label: Text(_sel >= 0 && _sel < hand.length ? '扣下 ${_name(hand[_sel])}' : '选一张扣牌'),
                  ),
                if (stuck && !cover) FilledButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('过')),
              ]),
              const SizedBox(height: 4),
              FmHand(hand,
                  cardW: w,
                  maxW: c.maxWidth - 16,
                  selected: {if (_sel >= 0) _sel},
                  glow: myTurn ? {for (var i = 0; i < hand.length; i++) if (legal.contains(hand[i])) i} : const {},
                  dim: myTurn && !stuck ? {for (var i = 0; i < hand.length; i++) if (!legal.contains(hand[i])) i} : const {},
                  onTap: myTurn
                      ? (i) {
                          if (legal.contains(hand[i])) {
                            g.act({'type': 'play', 'card': hand[i]});
                          } else if (stuck && cover) {
                            setState(() => _sel = _sel == i ? -1 : i);
                          }
                        }
                      : null),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (over) Center(child: _result(cover)),
        ]);
      }),
    );
  }

  String _name(String c) => '${_sym[_suits.indexOf(c[1])]}${fmRankLabel(c[0])}';

  Widget _coveredRow(List<String> cs, double w) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in cs) Padding(padding: const EdgeInsets.only(right: 1), child: fmCard(c, w, dim: true)),
      ]);

  Widget _panel(int s, double w, int count, int covered, bool active, Map? act, bool cover) {
    Widget? actChip;
    if (act != null) {
      switch (act['type']) {
        case 'play':
          actChip = fmChip('出 ${_name('${act['card']}')}', Colors.teal, fontSize: 11);
        case 'cover':
          actChip = fmChip('扣牌', Colors.deepOrange, fontSize: 11);
        case 'pass':
          actChip = fmChip('过', Colors.blueGrey, fontSize: 11);
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s, active: active, size: 32, sub: cover ? '$count张 · 扣$covered' : '$count张'),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          fmBacks(count, w),
          if (actChip != null) ...[const SizedBox(width: 4), actChip],
        ]),
      ]),
    );
  }

  /// The four suit rows A..K.
  Widget _table(Set<String> legal, bool myTurn) {
    final lo = fmInts(v['lo']), hi = fmInts(v['hi']);
    final last = v['last'] as Map?;
    final lastCard = last != null && last['type'] == 'play' ? '${last['card']}' : '';
    return LayoutBuilder(builder: (context, fc) {
      const padH = 22.0, padV = 10.0;
      const labelW = 22.0;
      final availW = fc.maxWidth - padH * 2 - labelW;
      final availH = fc.maxHeight - padV * 2;
      // cards overlap (corner index stays visible) so they can be larger on phones
      var cw = availW / (1 + 12 * 0.5);
      final byH = availH / (4 * 1.4 + 3 * 0.12);
      if (byH < cw) cw = byH;
      cw = cw.clamp(12.0, 76.0).toDouble();
      final step = ((availW - cw) / 12).clamp(cw * 0.5, cw * 1.08).toDouble();
      final hasRow = [for (var si = 0; si < 4; si++) lo[si] > 0];
      Widget cell(int si, int r) {
        final code = '${_ranks[r - 1]}${_suits[si]}';
        if (hasRow[si] && r >= lo[si] && r <= hi[si]) {
          return fmCard(code, cw, highlight: code == lastCard);
        }
        final sw = r == 13 || step >= cw ? cw : step * 0.92;
        if (myTurn && legal.contains(code)) {
          return Container(
            width: sw,
            height: cw * 1.4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cw * 0.1),
              border: Border.all(color: Colors.amberAccent, width: 1.5),
              color: Colors.amber.withValues(alpha: 0.18),
            ),
          );
        }
        return SizedBox(
          width: sw,
          height: cw * 1.4,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cw * 0.1),
              border: Border.all(color: Colors.white24, width: 1.2),
              color: Colors.black.withValues(alpha: 0.10),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(fmRankLabel(_ranks[r - 1]),
                  style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold, fontSize: cw * 0.34)),
            ),
          ),
        );
      }

      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var si = 0; si < 4; si++) ...[
              if (si > 0) SizedBox(height: cw * 0.12),
              Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: labelW,
                  child: Text(_sym[si],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: (cw * 0.5).clamp(12, 22).toDouble(),
                          color: si == 1 || si == 3 ? Colors.redAccent.shade100 : Colors.white,
                          fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: cw + step * 12,
                  height: cw * 1.4,
                  child: Stack(children: [
                    // empty slots first, then laid cards on top (low to high)
                    for (var r = 1; r <= 13; r++)
                      if (!(hasRow[si] && r >= lo[si] && r <= hi[si])) Positioned(left: step * (r - 1), child: cell(si, r)),
                    for (var r = 1; r <= 13; r++)
                      if (hasRow[si] && r >= lo[si] && r <= hi[si]) Positioned(left: step * (r - 1), child: cell(si, r)),
                  ]),
                ),
              ]),
            ],
          ]),
        ),
      );
    });
  }

  Widget _result(bool cover) {
    final r = v['result'] as Map?;
    final pl = fmInts(r?['placings']);
    if (pl.length != g.players) return const SizedBox();
    final scores = fmInts(v['scores']);
    final covered = v['covered'] as List?;
    final winner = (v['winner'] as num).toInt();
    final win = [for (var s = 0; s < g.players; s++) if (pl[s] == 1) g.name(s)];
    return fmResult(g, '${win.join('、')} 获胜！', pl, (s) {
      if (cover) {
        final n = covered == null ? 0 : (covered[s] as List).length;
        return '扣 $n 张 · ${scores.length > s ? scores[s] : 0} 分';
      }
      if (s == winner) return '最先出完';
      return '剩 ${scores.length > s ? scores[s] : 0} 点';
    });
  }
}
