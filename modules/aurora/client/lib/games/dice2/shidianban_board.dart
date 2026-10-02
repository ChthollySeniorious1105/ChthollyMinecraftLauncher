import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'd2_common.dart';

class ShiDianBanBoard extends StatelessWidget {
  final GameContext g;
  const ShiDianBanBoard(this.g, {super.key});

  static const _payoutText = {
    'standard': '十点半×2 · 五小×3 · 天王×4 · 人五小×5',
    'high': '十点半×3 · 五小×5 · 天王×6 · 人五小×8',
    'flat': '所有牌型一律 ×1',
  };

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = d2Str(v['phase'], 'bet');
    final round = d2Int(v['round']);
    final rounds = d2Int(v['rounds'], 10);
    final banker = d2Int(v['banker']);
    final turn = d2Int(v['turn'], -1);
    final chips = d2List<int>(v['chips']);
    final bets = d2List<int>(v['bets']);
    final grabs = d2List<dynamic>(v['grabs']);
    final hands = d2List<dynamic>(v['hands']);
    final points = d2List<dynamic>(v['points']);
    final kinds = d2List<dynamic>(v['kinds']);
    final done = d2List<bool>(v['done']);
    final betChoices = d2List<int>(v['betChoices']);
    final result = v['result'] == null ? null : d2Map(v['result']);
    final deltas = d2List<int>(result?['deltas']);
    final n = chips.length;
    final me = g.seat;
    final inGame = me >= 0 && me < n;
    final over = phase == 'over';

    final needGrab = phase == 'grab' && inGame && grabs.elementAtOrNull(me) == null;
    final needBet = phase == 'bet' && inGame && me != banker && (bets.elementAtOrNull(me) ?? 0) == 0;
    final myTurn = phase == 'play' && turn == me;

    String status;
    switch (phase) {
      case 'grab':
        status = needGrab ? '抢庄吗？' : '等待其他玩家抢庄';
      case 'bet':
        status = needBet ? '请下注（庄家：${g.name(banker)}）' : '等待闲家下注';
      case 'play':
        status = myTurn ? '轮到你：要牌还是停牌？' : '等待 ${g.name(turn)} ${turn == banker ? '（庄家）' : ''}';
      case 'result':
        status = '第 $round 局结算';
      default:
        status = '游戏结束';
    }

    Widget handView(int s, double cw) {
      final h = d2List<String>(hands.elementAtOrNull(s));
      if (h.isEmpty) return SizedBox(height: cw * 1.4);
      return SizedBox(
        height: cw * 1.4,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < h.length; i++)
            Positioned(
              left: i * cw * 0.55,
              child: PlayingCard(h[i], width: cw, faceDown: h[i].isEmpty),
            ),
          SizedBox(width: cw + (h.length - 1) * cw * 0.55),
        ]),
      );
    }

    Widget seat(int s, double cw) {
      final isBanker = s == banker;
      final active = (phase == 'play' && s == turn) ||
          (phase == 'bet' && s != banker && (bets.elementAtOrNull(s) ?? 0) == 0) ||
          (phase == 'grab' && grabs.elementAtOrNull(s) == null);
      final kind = d2Str(kinds.elementAtOrNull(s));
      final pt = points.elementAtOrNull(s);
      final d = deltas.elementAtOrNull(s);
      String sub = '筹码 ${chips[s]}';
      if (!isBanker && (bets.elementAtOrNull(s) ?? 0) > 0) sub += ' · 注 ${bets[s]}';
      if (phase == 'grab' && grabs.elementAtOrNull(s) != null) sub += grabs[s] == 1 ? ' · 抢' : ' · 不抢';
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? Colors.amberAccent : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (isBanker)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(6)),
                child: const Text('庄', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            Flexible(child: g.tag(s, active: active, size: 26, sub: sub)),
          ]),
          const SizedBox(height: 4),
          handView(s, cw),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (pt != null)
              Text('$pt 点', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            if (kind.isNotEmpty && kind != '平牌') ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: kind == '爆牌' ? Colors.red.shade700 : Colors.deepOrange,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(kind, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
            if (done.elementAtOrNull(s) == true && phase == 'play' && kind != '爆牌')
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text('停', style: TextStyle(color: Colors.white60, fontSize: 11)),
              ),
            if (d != null && (phase == 'result' || over)) ...[
              const SizedBox(width: 6),
              Text('${d >= 0 ? '+' : ''}$d',
                  style: TextStyle(
                      color: d > 0 ? Colors.greenAccent : (d < 0 ? Colors.redAccent : Colors.white70),
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
            ],
          ]),
        ]),
      );
    }

    Widget actions() {
      if (needGrab) {
        return Wrap(spacing: 10, children: [
          FilledButton(onPressed: () => g.act({'type': 'grab', 'grab': true}), child: const Text('抢庄')),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => g.act({'type': 'grab', 'grab': false}),
            child: const Text('不抢'),
          ),
        ]);
      }
      if (needBet) {
        return Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final b in betChoices)
            FilledButton.tonal(
              onPressed: () => g.act({'type': 'bet', 'amount': b}),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.toll, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text('$b'),
              ]),
            ),
        ]);
      }
      if (myTurn) {
        return Wrap(spacing: 12, children: [
          FilledButton.icon(onPressed: () => g.act({'type': 'hit'}), icon: const Icon(Icons.add), label: const Text('要牌')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            onPressed: () => g.act({'type': 'stand'}),
            icon: const Icon(Icons.pan_tool),
            label: const Text('停牌'),
          ),
        ]);
      }
      return const SizedBox.shrink();
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
      final cw = (min(c.maxWidth, 1000) / (wide ? 22 : 11)).clamp(28.0, 50.0);
      final others = [for (final s in g.seatsFromMe()) if (s != me) s];
      final felt = D2Felt(
        color: g.table,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('第 $round / $rounds 局 · ${v['bankerMode'] == 'grab' ? '抢庄' : '轮庄'}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text(_payoutText[d2Str(v['payout'])] ?? '', style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [for (final s in others) seat(s, cw)]),
          const SizedBox(height: 12),
          if (inGame) seat(me, cw * 1.35),
          const SizedBox(height: 8),
          actions(),
        ]),
      );
      final ranking = [for (var s = 0; s < n; s++) s]..sort((a, b) => chips[b] - chips[a]);
      final logP = D2Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('规则：A=1，2~10 按点数，JQK=半点；超过 10.5 爆牌；5 张不爆为五小/天王，5 张全人头为人五小；同点庄赢。',
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
          const Divider(height: 10),
          D2Log(d2List<String>(v['log']), max: wide ? 8 : 4),
        ]),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          StatusBar(status, highlight: needGrab || needBet || myTurn),
          if (over)
            ResultBanner('${g.name(ranking.first)} 筹码最多！',
                child: Wrap(spacing: 10, children: [
                  for (final s in ranking) Text('${g.name(s)} ${chips[s]}', style: const TextStyle(fontSize: 13)),
                ])),
          const SizedBox(height: 8),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: felt),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: logP),
            ])
          else ...[
            felt,
            const SizedBox(height: 8),
            logP,
          ],
        ]),
      );
    });
  }
}
