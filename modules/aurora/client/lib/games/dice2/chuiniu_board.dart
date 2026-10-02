import 'dart:math';

import 'package:aurora_shared/games/dice2/chuiniu.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'd2_common.dart';

class ChuiNiuBoard extends StatefulWidget {
  final GameContext g;
  const ChuiNiuBoard(this.g, {super.key});
  @override
  State<ChuiNiuBoard> createState() => _ChuiNiuBoardState();
}

class _ChuiNiuBoardState extends State<ChuiNiuBoard> {
  int qty = 3;
  int face = 2;
  bool zhai = false;
  bool peek = true;
  String key = '';

  static const _cupColors = [
    Color(0xFF8D1E1E), Color(0xFF1E4E8D), Color(0xFF2E7D32), Color(0xFF6A1B9A), Color(0xFFE65100), Color(0xFF37474F),
  ];

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = d2Str(v['phase'], 'bid');
    final round = d2Int(v['round']);
    final turn = d2Int(v['turn']);
    final lives = d2List<int>(v['lives']);
    final maxLives = d2Int(v['maxLives'], 3);
    final allowPi = v['allowPi'] == true;
    final myDice = d2List<int>(v['dice']);
    final bidQty = d2Int(v['bidQty']);
    final bidFace = d2Int(v['bidFace']);
    final bidder = d2Int(v['bidder'], -1);
    final curZhai = v['zhai'] == true;
    final stake = d2Int(v['stake'], 1);
    final challenger = d2Int(v['challenger'], -1);
    final total = d2Int(v['totalDice'], 10);
    final minFly = d2Int(v['minFly'], 3);
    final minZhai = d2Int(v['minZhai'], 2);
    final reveal = v['reveal'] == null ? null : d2Map(v['reveal']);
    final history = d2List<dynamic>(v['history']).map(d2Map).toList();
    final winner = d2Int(v['winner'], -1);
    final n = lives.length;
    final me = g.seat;
    final inGame = me >= 0 && me < n;
    final myTurn = phase == 'bid' && turn == me;
    final mustAnswerPi = phase == 'pi' && bidder == me;

    final k = '$round/$bidder/$bidQty/$bidFace/$curZhai';
    if (k != key) {
      key = k;
      if (bidder < 0) {
        qty = minFly;
        face = 2;
        zhai = false;
      } else {
        zhai = curZhai;
        face = bidFace;
        qty = min(total, bidQty + 1);
      }
    }
    final effZhai = zhai || face == 1;
    final err = cnBidError(qty, face, effZhai, bidder < 0 ? 0 : bidQty, bidFace, curZhai,
        minFly: minFly, minZhai: minZhai, total: total);

    String bidText(int q, int f, bool z) => '$q 个 $f${z || f == 1 ? '（斋）' : ''}';

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'reveal') {
      status = '开盅！';
    } else if (phase == 'pi') {
      status = mustAnswerPi ? '${g.name(challenger)} 劈你！接受还是反劈？' : '${g.name(challenger)} 劈 ${g.name(bidder)}，等待回应';
    } else if (myTurn) {
      status = bidder < 0 ? '轮到你：先叫（至少 $minFly 个，斋至少 $minZhai 个）' : '轮到你：加叫，或者开！';
    } else {
      status = '等待 ${g.name(turn)} 叫';
    }

    Widget seatBox(int s, double cup) {
      final dead = lives[s] <= 0;
      final rd = reveal == null ? null : d2List<dynamic>(reveal['dice']).elementAtOrNull(s);
      final isLoser = reveal != null && d2Int(reveal['loser'], -1) == s;
      final active = (phase == 'bid' && s == turn) || (phase == 'pi' && s == bidder);
      return Opacity(
        opacity: dead && !isLoser ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isLoser ? Colors.red.withValues(alpha: 0.25) : Colors.black26,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? Colors.amberAccent : Colors.transparent, width: 2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            g.tag(s, active: active, size: 26, trailing: D2Lives(lives[s], maxLives, size: 11)),
            const SizedBox(height: 4),
            if (rd is List && rd.isNotEmpty)
              Wrap(spacing: 2, children: [
                for (final d in d2List<int>(rd))
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: d == bidFace || (d == 1 && !curZhai && bidFace != 1)
                          ? const [BoxShadow(color: Colors.amberAccent, blurRadius: 5, spreadRadius: 1)]
                          : null,
                    ),
                    child: DieFace(d, size: cup * 0.36),
                  ),
              ])
            else if (!dead)
              DiceCup(size: cup, color: _cupColors[s % _cupColors.length], lifted: false)
            else
              Text('出局', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          ]),
        ),
      );
    }

    Widget center() {
      final ch = <Widget>[
        Text('第 $round 轮 · 场上 $total 颗骰子${curZhai ? ' · 斋' : ' · 1 点万能'}',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
      ];
      if (bidder >= 0) {
        ch.add(Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text('${g.name(bidder)} 叫：$bidQty 个 ',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          DieFace(bidFace, size: 30),
          if (curZhai || bidFace == 1)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.deepOrange, borderRadius: BorderRadius.circular(8)),
              child: const Text('斋', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          if (stake > 1)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.red.shade800, borderRadius: BorderRadius.circular(8)),
              child: Text('劈 ×$stake', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ]));
      } else {
        ch.add(const Text('等待首叫…', style: TextStyle(color: Colors.white, fontSize: 16)));
      }
      if (history.length > 1) {
        ch.add(const SizedBox(height: 4));
        ch.add(Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
          for (final h in history.sublist(0, history.length - 1))
            Text('${g.name(d2Int(h['seat']))} ${bidText(d2Int(h['qty']), d2Int(h['face']), h['zhai'] == true)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]));
      }
      if (reveal != null) {
        ch.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(d2Str(reveal['why']),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: ch);
    }

    Widget myArea(double w) {
      if (!inGame) return const SizedBox.shrink();
      if (lives[me] <= 0) return const Text('你已出局，观战中', style: TextStyle(color: Colors.white70));
      final dsize = (w / 9).clamp(34.0, 54.0);
      final children = <Widget>[
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('我的骰盅', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          IconButton(
            tooltip: peek ? '盖上' : '偷看',
            iconSize: 18,
            color: Colors.white70,
            onPressed: () => setState(() => peek = !peek),
            icon: Icon(peek ? Icons.visibility : Icons.visibility_off),
          ),
        ]),
        if (peek || reveal != null)
          Wrap(spacing: 8, children: [for (final d in myDice) RollingDie(d, size: dsize, rollKey: round)])
        else
          DiceCup(size: dsize * 1.6, color: _cupColors[me % _cupColors.length], label: '盅'),
        const SizedBox(height: 8),
      ];
      if (mustAnswerPi) {
        children.add(Wrap(spacing: 10, children: [
          FilledButton(onPressed: () => g.act({'type': 'accept'}), child: Text('接受（输赢 ×$stake）')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade800),
            onPressed: () => g.act({'type': 'repi'}),
            child: Text('反劈（×${stake * 2}）'),
          ),
        ]));
      }
      if (myTurn) {
        children.add(D2Panel(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: qty > 1 ? () => setState(() => qty--) : null, icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(
                width: 64,
                child: Text('$qty 个', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              IconButton(onPressed: qty < total ? () => setState(() => qty++) : null, icon: const Icon(Icons.add_circle_outline)),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('斋'),
                selected: effZhai,
                onSelected: face == 1 ? null : (b) => setState(() => zhai = b),
              ),
            ]),
            Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (var f = 1; f <= 6; f++)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: face == f ? cs.primary : Colors.transparent, width: 3),
                  ),
                  child: DieFace(f, size: 32, onTap: () => setState(() => face = f)),
                ),
            ]),
            const SizedBox(height: 4),
            if (err != null) Text(err, style: TextStyle(color: cs.error, fontSize: 12)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
              FilledButton(
                onPressed: err == null ? () => g.act({'type': 'bid', 'qty': qty, 'face': face, 'zhai': effZhai}) : null,
                child: Text('叫 ${bidText(qty, face, effZhai)}'),
              ),
              if (bidder >= 0)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: () => g.act({'type': 'open'}),
                  child: const Text('开！'),
                ),
              if (bidder >= 0 && allowPi)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
                  onPressed: () => g.act({'type': 'pi'}),
                  child: const Text('劈（×2）'),
                ),
            ]),
          ]),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    final others = [for (final s in g.seatsFromMe()) if (s != me) s];

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
      final cup = (c.maxWidth / (wide ? 16 : 9)).clamp(34.0, 60.0);
      final felt = D2Felt(
        color: const Color(0xFF4A2C2A),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [for (final s in others) seatBox(s, cup)]),
          const SizedBox(height: 10),
          center(),
          const SizedBox(height: 10),
          if (inGame) seatBox(me, cup),
          const SizedBox(height: 6),
          myArea(min(c.maxWidth, 620)),
        ]),
      );
      final logP = D2Panel(child: SizedBox(width: double.infinity, child: D2Log(d2List<String>(v['log']), max: wide ? 10 : 4)));
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          StatusBar(status, highlight: myTurn || mustAnswerPi),
          if (phase == 'over') ResultBanner(winner >= 0 ? '${g.name(winner)} 吹牛吹赢了！' : '无人获胜'),
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
