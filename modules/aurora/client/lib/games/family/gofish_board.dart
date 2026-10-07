import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'fm_widgets.dart';

/// 钓鱼
class GoFishBoard extends StatefulWidget {
  final GameContext g;
  const GoFishBoard(this.g, {super.key});
  @override
  State<GoFishBoard> createState() => _GoFishBoardState();
}

class _GoFishBoardState extends State<GoFishBoard> {
  String? _rank;
  int _target = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  String _logText(Map e) {
    String n(Object? s) {
      final i = (s as num).toInt();
      return i == g.seat ? '你' : g.name(i);
    }

    final book = e['book'] == null ? '' : '，凑成 ${fmRankLabel('${e['book']}')} 一书！';
    switch (e['type']) {
      case 'ask':
        final r = fmRankLabel('${e['rank']}');
        final head = '${n(e['seat'])} 向 ${n(e['target'])} 要 $r：';
        final got = (e['got'] as num).toInt();
        if (got > 0) return '$head给了 $got 张$book';
        final f = e['fish'];
        if (f == 'empty') return '$head没有（池塘已空）';
        if (f == 'lucky') return '$head去钓鱼，钓到了 $r！$book';
        return '$head去钓鱼$book';
      case 'refill':
        return '${n(e['seat'])} 手牌用完，从池塘摸了一张';
      case 'solo':
        return '${n(e['seat'])} 无人可问，摸了一张$book';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final over = v['phase'] == 'over';
    final turn = (v['turn'] as num).toInt();
    final me = g.seat;
    final myTurn = !over && me >= 0 && turn == me;
    final counts = fmInts(v['counts']);
    final books = [for (final b in (v['books'] as List)) fmStrs(b)];
    final hand = fmStrs(v['hand']);
    final myRanks = hand.map((c) => c[0]).toSet();
    final resigned = (v['resigned'] as num).toInt();
    if (_rank != null && !myRanks.contains(_rank)) _rank = null;
    if (_target >= 0 && (_target >= counts.length || counts[_target] == 0 || _target == me)) _target = -1;
    if (!myTurn) {
      _rank = null;
    }
    final targets = [for (final s in g.seatsFromMe()) if (s != me && s != resigned && counts[s] > 0) s];
    if (myTurn && _target < 0 && targets.length == 1) _target = targets.first;

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn) {
      status = _rank == null
          ? '轮到你：点选手里的一张牌，选择要的点数'
          : (_target < 0 ? '再点选一位玩家，向他要 ${fmRankLabel(_rank!)}' : '向 ${g.name(_target)} 要 ${fmRankLabel(_rank!)}？');
    } else {
      status = '等待 ${g.name(turn)} 问牌';
    }
    final log = [for (final e in (v['log'] as List? ?? const [])) e as Map];
    final others = g.seatsFromMe().where((s) => s != me).toList();

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 600;
        final cw = (c.maxWidth / (narrow ? 8 : 16)).clamp(34.0, 64.0).toDouble();
        final byH = (c.maxHeight / 7.2).clamp(30.0, 64.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              fmChip('池塘 ${v['pond']} 张', Colors.blue.shade700),
              fmChip('已成书 ${books.fold<int>(0, (a, b) => a + b.length)}/13', Colors.teal),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in others)
                  Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: _panel(s, w * 0.8, counts[s], books[s], turn, myTurn, over))),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : c.maxWidth * 0.08, vertical: 2),
                child: FmFelt(felt: fmFelt(g), child: _center(log, w)),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                g.tag(me, active: myTurn, size: 30, sub: '手牌 ${counts[me]} · ${books[me].length} 书'),
                if (books[me].isNotEmpty) _bookRow(books[me], w * 0.45),
                if (myTurn)
                  FilledButton.icon(
                    onPressed: _rank != null && _target >= 0
                        ? () {
                            g.act({'type': 'ask', 'target': _target, 'rank': _rank});
                            setState(() => _rank = null);
                          }
                        : null,
                    icon: const Icon(Icons.record_voice_over, size: 18),
                    label: Text(_rank != null && _target >= 0 ? '要 ${fmRankLabel(_rank!)}' : '问牌'),
                  ),
              ]),
              const SizedBox(height: 4),
              FmHand(hand,
                  cardW: w,
                  maxW: c.maxWidth - 16,
                  selected: {for (var i = 0; i < hand.length; i++) if (hand[i][0] == _rank) i},
                  onTap: myTurn ? (i) => setState(() => _rank = hand[i][0] == _rank ? null : hand[i][0]) : null),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (over) Center(child: _result(books)),
        ]);
      }),
    );
  }

  Widget _bookRow(List<String> b, double w) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final r in b)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: SizedBox(
              width: w + w * 0.2,
              height: w * 1.4,
              child: Stack(children: [
                Positioned(left: 0, child: fmCard('${r}S', w)),
                Positioned(left: w * 0.2, child: fmCard('${r}H', w)),
              ]),
            ),
          ),
      ]);

  Widget _panel(int s, double w, int count, List<String> books, int turn, bool myTurn, bool over) {
    final picked = s == _target && myTurn;
    final canPick = myTurn && count > 0;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: canPick ? () => setState(() => _target = s) : null,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: picked ? Colors.amberAccent : (canPick ? cs.primary.withValues(alpha: 0.35) : Colors.transparent), width: 2),
          color: picked ? Colors.amber.withValues(alpha: 0.15) : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          g.tag(s, active: !over && s == turn, size: 32, sub: '$count张 · ${books.length}书'),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            fmBacks(count, w),
            if (books.isNotEmpty) ...[const SizedBox(width: 6), _bookRow(books, w * 0.5)],
          ]),
          if (picked) ...[const SizedBox(height: 2), fmChip('问他', Colors.amber.shade800, fontSize: 11)],
        ]),
      ),
    );
  }

  Widget _center(List<Map> log, double w) {
    final pond = (v['pond'] as num).toInt();
    final recent = log.length > 6 ? log.sublist(log.length - 6) : log;
    return LayoutBuilder(builder: (context, fc) {
      return Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: w * 0.9 + 12,
              height: w * 1.26 + 8,
              child: pond == 0
                  ? fmSlot(w * 0.9, label: '空')
                  : Stack(children: [
                      for (var i = 0; i < (pond / 6).ceil().clamp(1, 5); i++)
                        Positioned(left: i * 3.0, top: 8 - i * 2.0, child: fmCard('back', w * 0.9)),
                    ]),
            ),
            const SizedBox(height: 4),
            Text('池塘 $pond', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
          ])),
          const SizedBox(width: 12),
          Expanded(
            child: recent.isEmpty
                ? const Center(child: Text('还没有人问牌', style: TextStyle(color: Colors.white54, fontSize: 14)))
                : ClipRect(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (var i = 0; i < recent.length; i++)
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Text(
                              _logText(recent[i]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: i == recent.length - 1 ? Colors.white : Colors.white.withValues(alpha: 0.6),
                                fontWeight: i == recent.length - 1 ? FontWeight.bold : FontWeight.normal,
                                fontSize: fc.maxHeight < 120 ? 11 : 13,
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
          ),
        ]),
      )));
    });
  }

  Widget _result(List<List<String>> books) {
    final r = v['result'] as Map?;
    final pl = fmInts(r?['placings']);
    if (pl.length != g.players) return const SizedBox();
    final win = [for (var s = 0; s < g.players; s++) if (pl[s] == 1) g.name(s)];
    return fmResult(g, '${win.join('、')} 获胜！', pl, (s) => '${books[s].length} 书 ${books[s].map(fmRankLabel).join(' ')}');
  }
}
