import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'bridge_panels.dart';
import 'tr_common.dart';

/// 桥牌 牌桌
class BridgeBoard extends StatefulWidget {
  final GameContext g;
  const BridgeBoard(this.g, {super.key});
  @override
  State<BridgeBoard> createState() => _BridgeBoardState();
}

class _BridgeBoardState extends State<BridgeBoard> {
  bool _sheet = false;
  bool _showAuction = false;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<int> _ints(Object? x) => x is List ? [for (final e in x) (e as num).toInt()] : <int>[];

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final me = g.seat;
    final hand = trList(v['hand']);
    final counts = _ints(v['counts']);
    final turn = (v['turn'] as num?)?.toInt() ?? 0;
    final dealer = (v['dealer'] as num?)?.toInt() ?? 0;
    final declarer = (v['declarer'] as num?)?.toInt() ?? -1;
    final dummy = (v['dummy'] as num?)?.toInt() ?? -1;
    final dummyHand = v['dummyHand'] == null ? null : trList(v['dummyHand']);
    final contract = v['contract'] as Map?;
    final tricks = _ints(v['tricks']);
    final vul = (v['vul'] as List?)?.cast<bool>() ?? const [false, false];
    final calls = (v['calls'] as List?) ?? const [];
    final trick = (v['trick'] as List?) ?? const [];
    final lastWinner = (v['lastWinner'] as num?)?.toInt() ?? -1;
    final legal = trList(v['legal']).toSet();
    final inPlay = phase == 'play' || phase == 'trickEnd';
    final actor = (v['actor'] as num?)?.toInt() ?? -1;
    final iPlayDummy = phase == 'play' && me >= 0 && me == declarer && turn == dummy;

    String lastCall(int s) {
      for (var i = calls.length - 1; i >= 0; i--) {
        if ((calls[i] as Map)['seat'] == s) return '${calls[i]['call']}';
      }
      return '';
    }

    Widget panel(int s, double w) {
      final active = (phase == 'auction' && turn == s) || (phase == 'play' && turn == s);
      final role = s == declarer && inPlay ? '庄家' : (s == dummy && inPlay ? '明手' : '');
      final sub = '${brSeatNames[s]} · ${brSide(s % 2)}${vul[s % 2] ? '（有局）' : ''}';
      final children = <Widget>[
        Row(mainAxisSize: MainAxisSize.min, children: [
          g.tag(s, active: active, sub: sub, size: 30),
          if (role.isNotEmpty) trBadge(role, s == declarer ? Colors.deepOrange : Colors.teal),
          if (s == dealer && phase == 'auction') trBadge('发牌', Colors.brown),
        ]),
        const SizedBox(height: 4),
      ];
      if (s == dummy && dummyHand != null && s != me) {
        children.add(trSuitRows(dummyHand, w * 0.85,
            playable: iPlayDummy ? legal : const {}, onPlay: iPlayDummy ? (c) => g.act({'type': 'play', 'card': c}) : null));
      } else {
        children.add(Row(mainAxisSize: MainAxisSize.min, children: [
          trBacks(counts[s], w * 0.8),
          if (phase == 'auction' && lastCall(s).isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFFDF7), borderRadius: BorderRadius.circular(8)),
              child: brCallText(lastCall(s), size: 15),
            ),
          ],
        ]));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    // ---- status ----
    String status;
    var hi = false;
    switch (phase) {
      case 'auction':
        hi = turn == me;
        status = hi ? '轮到你叫牌' : '等待 ${g.name(turn)}（${brSeatNames[turn]}）叫牌';
      case 'play':
        hi = actor == me;
        if (iPlayDummy) {
          status = '轮到明手出牌（由你代打）';
        } else if (hi) {
          status = trick.isEmpty && tricks[0] + tricks[1] == 0 ? '请首攻' : '轮到你出牌';
        } else {
          status = turn == dummy ? '等待庄家 ${g.name(declarer)} 打明手的牌' : '等待 ${g.name(turn)} 出牌';
        }
        if (me == dummy && me >= 0) status = '你是明手 · $status';
      case 'trickEnd':
        status = '${g.name(lastWinner)}（${brSeatNames[lastWinner]}）赢得这一墩';
      case 'dealEnd':
        status = '本副结束';
      default:
        status = '比赛结束';
    }

    final mode = '${v['mode']}';
    final dealNo = (v['dealNo'] as num?)?.toInt() ?? 0;
    final gamesWon = _ints(v['gamesWon']);
    final belowCur = _ints(v['belowCur']);
    final info = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        StatusBar(status, highlight: hi || iPlayDummy),
        trChip(mode == 'chicago' ? '芝加哥 第 ${(v['chicagoIndex'] as num? ?? 0).toInt() + 1}/4 副' : '盘式 第 ${dealNo + 1} 副', Colors.indigo),
        brVulChip(vul),
        if (contract != null) brContractChip(contract),
        if (inPlay) trChip('墩数 南北 ${tricks[0]} : 东西 ${tricks[1]}', Colors.teal.shade700),
        if (mode != 'chicago')
          trChip('局 ${gamesWon[0]}:${gamesWon[1]} · 线下 ${belowCur[0]}:${belowCur[1]}', Colors.brown),
        if (inPlay) trChip('叫牌', Colors.blueGrey, onTap: () => setState(() => _showAuction = !_showAuction)),
        trChip('记分表', Colors.blueGrey, onTap: () => setState(() => _sheet = !_sheet)),
      ],
    );

    Widget center;
    if (phase == 'auction' || (_showAuction && inPlay)) {
      center = BrAuctionTable(calls: calls, dealer: dealer, turn: phase == 'auction' ? turn : -1, vul: vul);
    } else {
      final need = contract == null ? 0 : (contract['level'] as num).toInt() + 6;
      final declSide = declarer < 0 ? 0 : declarer % 2;
      center = TrTrick(
        g: g,
        trick: trick,
        winner: phase == 'trickEnd' ? lastWinner : -1,
        w: 52,
        middle: trick.isEmpty && contract != null
            ? trNote('庄家 ${tricks[declSide]}/$need 墩', color: Colors.black45)
            : null,
      );
    }

    Widget bottom(double cw, double maxW) {
      final myTurnPlay = phase == 'play' && turn == me && me != dummy;
      final bidding = phase == 'auction' && turn == me;
      final tagRow = me >= 0
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              g.tag(me, active: hi, sub: '${brSeatNames[me]} · ${brSide(me % 2)}${vul[me % 2] ? '（有局）' : ''}', size: 28),
              if (me == declarer && inPlay) trBadge('庄家', Colors.deepOrange),
              if (me == dummy && inPlay) trBadge('明手', Colors.teal),
            ])
          : const SizedBox();
      final handW = TrHand(
        cards: hand,
        cardW: cw,
        legal: myTurnPlay ? legal : const {},
        dimIllegal: myTurnPlay,
        onTap: myTurnPlay ? (c) => g.act({'type': 'play', 'card': c}) : null,
      );
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (bidding)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              width: maxW,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: BrBiddingBox(legal: trList(v['legalCalls']), onCall: (c) => g.act({'type': 'call', 'call': c})),
                ),
              ),
            ),
          ),
        tagRow,
        SizedBox(width: maxW, child: Center(child: handW)),
      ]);
    }

    Widget? overlay;
    if (phase == 'dealEnd' || phase == 'over') {
      overlay = _resultPanel(phase == 'over');
    } else if (_sheet) {
      overlay = _card(Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(fit: BoxFit.scaleDown, child: brScoreSheet(context, v, g.name)),
        TextButton(onPressed: () => setState(() => _sheet = false), child: const Text('关闭')),
      ]));
    }
    return TrTable(g: g, panel: panel, center: center, info: info, bottom: bottom, overlay: overlay);
  }

  Widget _card(Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: cs.onSurface), child: child),
    );
  }

  Widget _allHands(List hands) {
    final cs = Theme.of(context).colorScheme;
    Widget h(int s) => Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: const Color(0xFFFFFDF7), borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(brSeatLabel(g, s), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            DefaultTextStyle.merge(style: const TextStyle(color: Colors.black87), child: brHandText(trList(hands[s]), size: 12)),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      h(0),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        h(3),
        SizedBox(
          width: 70,
          child: Center(child: Icon(Icons.explore, color: cs.primary, size: 36)),
        ),
        h(1),
      ]),
      const SizedBox(height: 4),
      h(2),
    ]);
  }

  Widget _resultPanel(bool over) {
    final r = (v['result'] as Map?) ?? const {};
    final hands = v['allHands'] as List?;
    final lines = <Widget>[];
    if (r['passedOut'] == true) {
      lines.add(const Text('四家都不叫，本副作废，重新发牌', style: TextStyle(fontWeight: FontWeight.bold)));
    } else if (r.isNotEmpty) {
      final diff = (r['diff'] as num).toInt();
      final decl = (r['declarer'] as num).toInt();
      final how = diff >= 0 ? (diff == 0 ? '刚好完成' : '超 $diff 墩完成') : '宕 ${-diff} 墩';
      lines.add(Text('${brSeatNames[decl]}（${g.name(decl)}）主打 ${r['contract']}，拿到 ${r['tricks']} 墩，$how',
          style: TextStyle(fontWeight: FontWeight.bold, color: diff >= 0 ? Colors.green.shade700 : Colors.red.shade700)));
      lines.add(Text('本副得分：南北 +${r['ns']}，东西 +${r['ew']}'));
      for (final n in trList(r['notes'])) {
        lines.add(Text(n, style: const TextStyle(fontSize: 13)));
      }
    }
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      ...lines,
      const SizedBox(height: 8),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (hands != null) FittedBox(fit: BoxFit.scaleDown, child: _allHands(hands)),
          FittedBox(fit: BoxFit.scaleDown, child: brScoreSheet(context, v, g.name)),
        ],
      ),
      if (!over) trContinue(g, (v['ready'] as List?)?.cast<bool>()),
    ]);
    if (over) {
      final w = (v['winner'] as num?)?.toInt() ?? -1;
      final t = _ints(v['totals']);
      return ResultBanner(w == 2 ? '平局 ${t[0]} : ${t[1]}' : '${brSide(w)} 获胜！${t[0]} : ${t[1]}', child: body);
    }
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _card(body));
  }
}
