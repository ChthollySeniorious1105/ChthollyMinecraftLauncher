import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'pp_widgets.dart';

class BlackjackBoard extends StatefulWidget {
  final GameContext g;
  const BlackjackBoard(this.g, {super.key});
  @override
  State<BlackjackBoard> createState() => _BlackjackBoardState();
}

class _BlackjackBoardState extends State<BlackjackBoard> {
  int _bet = 50;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<int> _ints(String k) => [for (final x in (v[k] as List? ?? const [])) (x as num).toInt()];

  static const _acts = {'hit': '要牌', 'stand': '停牌', 'double': '加倍', 'split': '分牌'};
  static const _outcome = {'bj': '黑杰克!', 'win': '赢', 'lose': '输', 'push': '平', 'bust': '爆牌'};

  String _total(num t, bool soft) => soft && t < 21 ? '${t - 10}/$t' : '$t';

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final me = g.seat;
    final chips = _ints('chips'), bets = _ints('bets');
    final broke = [for (final b in v['broke'] as List) b == true];
    final turn = (v['turn'] as num).toInt();
    final ins = _ints('insurance');
    String status;
    var mine = false;
    switch (phase) {
      case 'bet':
        mine = me >= 0 && !broke[me] && bets[me] == 0;
        status = mine ? '请下注' : '等待其他玩家下注';
      case 'insurance':
        mine = me >= 0 && bets[me] > 0 && ins[me] < 0;
        status = mine ? '庄家明牌 A，是否购买保险？' : '等待其他玩家决定保险';
      case 'play':
        mine = turn == me && me >= 0;
        status = mine ? '轮到你：要牌 / 停牌 / 加倍 / 分牌' : '等待 ${g.name(turn)} 行动';
      case 'result':
        status = '本局结算';
      default:
        status = '游戏结束';
    }
    final rounds = (v['rounds'] as num).toInt();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (min(c.maxWidth / (c.maxWidth < 600 ? 9 : 16), c.maxHeight / 11)).clamp(26.0, 58.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ppChip('第 ${v['round']}${rounds > 0 ? "/$rounds" : "/${v['cap']}"} 局', Colors.indigo),
              ppChip('软17${v['h17'] == true ? "要牌" : "停牌"}', Colors.brown),
              ppChip('牌靴 ${v['shoe']}', Colors.blueGrey),
              StatusBar(status, highlight: mine),
            ]),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: FeltTable(
                  felt: Color.lerp(g.table, const Color(0xFF0B5E3A), 0.5)!,
                  semicircle: true,
                  child: Column(children: [
                    const SizedBox(height: 6),
                    _dealer(cw),
                    Text('黑杰克 3:2 · 保险 2:1 · 庄家软17${v['h17'] == true ? "要牌" : "停牌"}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    Expanded(child: _seats(cw, chips, bets, broke, turn)),
                  ]),
                ),
              ),
            ),
            if (mine) _actionBar(phase, chips[me]) else const SizedBox(height: 6),
          ]),
          if (phase == 'over') Center(child: _final(chips)),
        ]);
      }),
    );
  }

  Widget _dealer(double cw) {
    final cards = [for (final c in v['dealer'] as List) '$c'];
    final t = (v['dealerTotal'] as num).toInt();
    final bust = t > 21;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.person, color: Colors.white70, size: 18),
          const Text(' 庄家 ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          if (cards.isNotEmpty)
            ppChip(v['dealerBj'] == true ? '黑杰克' : (bust ? '$t 爆' : _total(t, v['dealerSoft'] == true)),
                bust ? Colors.redAccent : Colors.black54),
        ]),
        const SizedBox(height: 3),
        SizedBox(
          height: cw * 1.4,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (cards.isEmpty) ...[ppSlot(cw), const SizedBox(width: 4), ppSlot(cw)],
            for (final c in cards) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: ppCard(c, cw)),
          ]),
        ),
      ]),
    );
  }

  Widget _seats(double cw, List<int> chips, List<int> bets, List<bool> broke, int turn) {
    final n = g.players;
    final hands = v['hands'] as List;
    final result = v['result'] as List?;
    final active = _ints('active');
    final ins = _ints('insurance');
    Widget seat(int s, double scale) => _seat(s, cw * scale, hands[s] as List, chips[s], bets[s], broke[s],
        turn == s ? active[s] : -1, result == null ? null : (result[s] as num).toInt(), ins[s]);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 600) {
        // narrow: grid of seats, two per row
        final colW = c.maxWidth / 2 - 8;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: c.maxWidth,
            child: Wrap(alignment: WrapAlignment.center, runSpacing: 8, children: [
              for (var s = 0; s < n; s++) SizedBox(width: colW, child: Center(child: seat(s, n > 4 ? 0.75 : 0.9))),
            ]),
          ),
        );
      }
      final seatW = min(220.0, c.maxWidth / max(n, 2) - 6);
      final widgets = <Widget>[];
      for (var k = 0; k < n; k++) {
        final frac = n == 1 ? 0.5 : k / (n - 1);
        final ang = pi * (0.12 + 0.76 * (1 - frac));
        final x = c.maxWidth / 2 + (c.maxWidth / 2 - seatW / 2 - 6) * cos(ang);
        final y = c.maxHeight * 0.12 + (c.maxHeight * 0.3) * sin(ang);
        widgets.add(Positioned(
          left: x - seatW / 2,
          top: y,
          width: seatW,
          height: c.maxHeight - y - 2,
          child: Align(
            alignment: Alignment.topCenter,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topCenter,
              child: SizedBox(width: seatW, child: seat(k, n > 4 ? 0.8 : 1)),
            ),
          ),
        ));
      }
      return Stack(children: widgets);
    });
  }

  Widget _seat(int s, double cw, List hs, int chips, int bet, bool broke, int activeHand, int? delta, int ins) {
    final cs = Theme.of(context).colorScheme;
    final isTurn = activeHand >= 0;
    return Opacity(
      opacity: broke && hs.isEmpty ? 0.45 : 1,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 2, children: [
          for (var i = 0; i < hs.length; i++) _hand(hs[i] as Map, cw, isTurn && i == activeHand),
        ]),
        const SizedBox(height: 4),
        g.tag(s,
            active: isTurn,
            size: 28,
            sub: broke ? '已破产' : '筹码 $chips${ins > 0 ? " · 保险" : ""}',
            trailing: delta == null
                ? null
                : Text(delta > 0 ? '+$delta' : '$delta',
                    style: TextStyle(
                        color: delta > 0 ? Colors.lightGreenAccent : (delta < 0 ? Colors.redAccent : cs.onSurface),
                        fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _hand(Map h, double cw, bool active) {
    final cards = [for (final c in h['cards'] as List) '$c'];
    final t = (h['total'] as num).toInt();
    final soft = h['soft'] == true;
    final outcome = '${h['outcome']}';
    final bust = t > 21;
    Color tagColor = Colors.black54;
    if (outcome == 'win' || outcome == 'bj') tagColor = Colors.green.shade700;
    if (outcome == 'lose' || outcome == 'bust' || bust) tagColor = Colors.red.shade700;
    if (outcome == 'push') tagColor = Colors.blueGrey;
    final step = cw * 0.45;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? Colors.amberAccent : Colors.transparent, width: 2),
        color: active ? Colors.amber.withValues(alpha: 0.15) : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: cw + step * max(0, cards.length - 1),
          height: cw * 1.4,
          child: Stack(children: [
            for (var i = 0; i < cards.length; i++) Positioned(left: step * i, child: ppCard(cards[i], cw)),
          ]),
        ),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          ppChip(bust ? '$t 爆' : _total(t, soft), tagColor, fontSize: 11),
          const SizedBox(width: 3),
          ChipStack((h['bet'] as num).toInt(), size: 13),
          if (h['doubled'] == true) const Text(' ×2', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
          if (outcome.isNotEmpty && outcome != 'bust')
            Padding(padding: const EdgeInsets.only(left: 3), child: ppChip(_outcome[outcome] ?? '', tagColor, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _actionBar(String phase, int chips) {
    final bar = <Widget>[];
    if (phase == 'bet') {
      final choices = _ints('betChoices');
      if (_bet > chips) _bet = choices.lastWhere((b) => b <= chips, orElse: () => chips);
      bar.addAll([
        for (final b in choices)
          ChoiceChip(
            label: Text('$b'),
            selected: _bet == b,
            onSelected: b <= chips ? (_) => setState(() => _bet = b) : null,
          ),
        ChoiceChip(label: Text('全部 $chips'), selected: _bet == chips, onSelected: (_) => setState(() => _bet = chips)),
        FilledButton(onPressed: _bet >= 10 ? () => g.act({'type': 'bet', 'amount': _bet}) : null, child: Text('下注 $_bet')),
      ]);
    } else if (phase == 'insurance') {
      bar.addAll([
        FilledButton(onPressed: () => g.act({'type': 'insurance', 'take': true}), child: const Text('购买保险')),
        OutlinedButton(onPressed: () => g.act({'type': 'insurance', 'take': false}), child: const Text('不买')),
      ]);
    } else {
      final legal = [for (final x in v['legal'] as List) '$x'];
      for (final a in ['hit', 'stand', 'double', 'split']) {
        final ok = legal.contains(a);
        bar.add(a == 'hit' || a == 'stand'
            ? FilledButton(onPressed: ok ? () => g.act({'type': a}) : null, child: Text(_acts[a]!))
            : FilledButton.tonal(onPressed: ok ? () => g.act({'type': a}) : null, child: Text(_acts[a]!)));
      }
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: bar),
    );
  }

  Widget _final(List<int> chips) {
    final order = List.generate(g.players, (i) => i)..sort((a, b) => chips[b] - chips[a]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: ResultBanner(
        '${g.name(order.first)} 筹码最多！',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < order.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 30, child: Text('#${i + 1}')),
              SizedBox(width: 120, child: Text(g.name(order[i]), overflow: TextOverflow.ellipsis)),
              SizedBox(
                width: 80,
                child: Text('${chips[order[i]]} (${chips[order[i]] - 1000 >= 0 ? "+" : ""}${chips[order[i]] - 1000})',
                    textAlign: TextAlign.right),
              ),
            ]),
        ]),
      ),
    );
  }
}
