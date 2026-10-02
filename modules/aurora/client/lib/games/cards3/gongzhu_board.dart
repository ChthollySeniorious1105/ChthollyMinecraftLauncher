import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c3_widgets.dart';

const _exposable = ['QS', 'JD', 'TC', 'AH'];
const _exposeName = {'QS': '猪', 'JD': '羊', 'TC': '变压器', 'AH': '红心A'};

class GongzhuBoard extends StatefulWidget {
  final GameContext g;
  const GongzhuBoard(this.g, {super.key});
  @override
  State<GongzhuBoard> createState() => _GongzhuBoardState();
}

class _GongzhuBoardState extends State<GongzhuBoard> {
  final Set<String> _expose = {};

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final me = g.seat;
    final turn = (v['turn'] as num? ?? -1).toInt();
    final myTurn = me >= 0 && phase == 'play' && turn == me;
    final exposeDone = (v['exposeDone'] as List?)?.map((e) => e == true).toList() ?? const [];
    final needExpose = me >= 0 && phase == 'expose' && me < exposeDone.length && !exposeDone[me];
    final hand = c3Strs(v['hand']);
    final legal = c3Strs(v['legal']).toSet();
    String status;
    switch (phase) {
      case 'expose':
        status = needExpose ? '亮牌阶段：可选择亮出猪/羊/变压器/红心A使其分值加倍' : '等待其他玩家亮牌';
      case 'play':
        status = myTurn ? ((v['tricks'] as num) == 0 && legal.length == 1 ? '你持♣2，请先出' : '轮到你出牌') : '等待 ${g.name(turn)} 出牌';
      case 'roundEnd':
        status = '本局结束';
      default:
        status = '比赛结束';
    }
    final seats = g.seatsFromMe();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 9 : 17)).clamp(30.0, 60.0).toDouble();
        final byH = (c.maxHeight / 7.6).clamp(28.0, 60.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(fit: StackFit.expand, children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              c3Pill('拱猪 第 ${v['round']} 局 · 至 -${v['limit']}', Colors.indigo),
              c3Pill('第 ${((v['tricks'] as num?) ?? 0).toInt() + (phase == 'play' ? 1 : 0)}/13 墩', Colors.teal.shade700),
              ..._exposedPills(),
            ]),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: C3Felt(felt: c3FeltColor(g, const Color(0xFF4A148C)), child: Center(child: _tableArea(seats, w))),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn || needExpose),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              if (needExpose) _exposeBar(hand),
              const SizedBox(height: 4),
              C3Hand(
                cards: hand,
                sel: needExpose ? {for (var i = 0; i < hand.length; i++) if (_expose.contains(hand[i])) i} : const {},
                cw: w,
                maxW: c.maxWidth - 16,
                enabled: myTurn ? (i) => legal.contains(hand[i]) : (needExpose ? (i) => _exposable.contains(hand[i]) : null),
                onToggle: (i) {
                  if (myTurn) {
                    g.act({'type': 'play', 'card': hand[i]});
                  } else if (needExpose) {
                    setState(() {
                      if (!_expose.remove(hand[i])) _expose.add(hand[i]);
                    });
                  }
                },
              ),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase == 'roundEnd' || phase == 'over') Center(child: SingleChildScrollView(child: _result())),
        ]);
      }),
    );
  }

  List<Widget> _exposedPills() {
    final ex = v['exposed'] as List? ?? const [];
    final out = <Widget>[];
    for (var s = 0; s < ex.length; s++) {
      for (final c in c3Strs(ex[s])) {
        out.add(c3Pill('${g.name(s)} 亮${_exposeName[c] ?? c}', Colors.deepOrange, fontSize: 11));
      }
    }
    return out;
  }

  Widget _exposeBar(List<String> hand) {
    final mine = _exposable.where(hand.contains).toList();
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
      if (mine.isEmpty) const Text('你没有可亮的牌', style: TextStyle(color: Colors.white70)),
      for (final c in mine)
        FilterChip(
          label: Text('亮${_exposeName[c]}'),
          selected: _expose.contains(c),
          onSelected: (b) => setState(() => b ? _expose.add(c) : _expose.remove(c)),
        ),
      FilledButton(
        onPressed: () => g.act({'type': 'expose', 'cards': [for (final c in _expose) if (hand.contains(c)) c]}),
        child: Text(_expose.isEmpty ? '不亮' : '确认亮牌'),
      ),
    ]);
  }

  Widget _seatBox(int s, double w) {
    final scores = c3Ints(v['scores']);
    final live = c3Ints(v['live']);
    final counts = c3Ints(v['counts']);
    final taken = v['taken'] as List? ?? const [];
    final turn = (v['turn'] as num? ?? -1).toInt();
    final t = s < taken.length ? c3Strs(taken[s]) : <String>[];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max(120.0, w * 3.2)),
        child: g.tag(s,
          active: turn == s,
          size: 28,
          sub: '总${s < scores.length ? scores[s] : 0} · 本局${s < live.length ? live[s] : 0}',
          trailing: s != g.seat && s < counts.length ? Text('${counts[s]}张', style: const TextStyle(fontSize: 11)) : null),
      ),
      if (t.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: c3Row(t, w * 0.5, gap: 0.42)),
    ]);
  }

  Widget _tableArea(List<int> seats, double hw) {
    return LayoutBuilder(builder: (context, bc) {
      final w = [bc.maxWidth / 9.6, bc.maxHeight / 7.8, 70.0].reduce((a, b) => a < b ? a : b).clamp(20.0, 70.0).toDouble();
      return _tableInner(seats, w);
    });
  }

  Widget _tableInner(List<int> seats, double w) {
    final trick = v['trick'] as List? ?? const [];
    final last = v['lastTrick'] as Map?;
    final leader = (v['leader'] as num? ?? 0).toInt();
    String? cardOf(int s) => s < trick.length ? trick[s] as String? : null;
    // seats: [me, right, across, left]
    Widget slot(int s) {
      final c = cardOf(s);
      if (c == null) return SizedBox(width: w, height: w * 1.4);
      return c3Card(c, w, highlight: s == leader);
    }

    final bottom = seats[0], right = seats[1], top = seats[2], left = seats[3];
    final showLast = last != null && trick.every((x) => x == null);
    final cross = SizedBox(
      width: w * 3.6,
      height: w * 4.4,
      child: Stack(children: [
        Positioned(left: w * 1.3, top: 0, child: slot(top)),
        Positioned(left: 0, top: w * 1.5, child: slot(left)),
        Positioned(left: w * 2.6, top: w * 1.5, child: slot(right)),
        Positioned(left: w * 1.3, top: w * 3.0, child: slot(bottom)),
        if (showLast)
          Positioned.fill(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('上一墩 · ${g.name((last['winner'] as num).toInt())} 收',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                c3Row(c3Strs(last['cards']), w * 0.6, gap: 0.7),
              ]),
            ),
          ),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.all(6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _seatBox(top, w),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: w * 2.9, child: Center(child: _seatBox(left, w))),
            cross,
            SizedBox(width: w * 2.9, child: Center(child: _seatBox(right, w))),
          ]),
          const SizedBox(height: 4),
          _seatBox(bottom, w),
        ]),
      ),
    );
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final scores = c3Ints(v['scores']);
    final over = v['phase'] == 'over';
    final order = List.generate(4, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 夺冠' : '第 ${v['round']} 局结算',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < 4; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 28, child: Text(over ? '#${k + 1}' : '')),
                  SizedBox(width: 84, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                  if (r != null) SizedBox(width: 56, child: c3Delta(((r['delta'] as List)[order[k]] as num).toInt())),
                  SizedBox(width: 64, child: Text('${scores[order[k]]}分', textAlign: TextAlign.right)),
                  if (r != null) ...[
                    const SizedBox(width: 8),
                    c3Row(c3Strs((r['taken'] as List)[order[k]]), 22, gap: 0.45),
                  ],
                ]),
              ),
            ),
          c3Continue(g),
        ]),
      ),
    );
  }
}
