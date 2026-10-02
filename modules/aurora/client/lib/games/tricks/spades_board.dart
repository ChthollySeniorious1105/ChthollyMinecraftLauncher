import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tr_common.dart';

/// 黑桃王 牌桌
class SpadesBoard extends StatefulWidget {
  final GameContext g;
  const SpadesBoard(this.g, {super.key});
  @override
  State<SpadesBoard> createState() => _SpadesBoardState();
}

class _SpadesBoardState extends State<SpadesBoard> {
  bool _sheet = false;
  int _bid = 3;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<int> _ints(Object? x) => x is List ? [for (final e in x) (e as num).toInt()] : <int>[];
  String _team(int t) => t == 0 ? '南北队' : '东西队';
  String _signed(int n) => n >= 0 ? '+$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final handNo = (v['handNo'] as num?)?.toInt() ?? 0;
    final hand = trList(v['hand']);
    final bids = [for (final b in (v['bids'] as List? ?? const [])) (b as num?)?.toInt()];
    final blind = (v['blind'] as List?)?.cast<bool>() ?? const [false, false, false, false];
    final won = _ints(v['won']);
    final counts = _ints(v['counts']);
    final scores = _ints(v['scores']);
    final bags = _ints(v['bags']);
    final turn = (v['turn'] as num?)?.toInt() ?? 0;
    final dealer = (v['dealer'] as num?)?.toInt() ?? 0;
    final trick = (v['trick'] as List?) ?? const [];
    final lastWinner = (v['lastWinner'] as num?)?.toInt() ?? -1;
    final me = g.seat;

    String bidText(int s) {
      final b = bids[s];
      if (b == null) return phase == 'bid' ? '叫墩中' : '—';
      if (b == 0) return blind[s] ? '盲零' : '零墩';
      return '叫 $b';
    }

    Widget panel(int s, double w) {
      final active = (phase == 'bid' || phase == 'play') && turn == s;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s, active: active, sub: '${_team(s % 2)}${s == dealer ? ' · 发牌' : ''}', size: 32),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          trBacks(counts[s], w * 0.8),
          const SizedBox(width: 8),
          trBadge(bidText(s), bids[s] == 0 ? Colors.purple : Colors.indigo),
          if (phase != 'bid') trBadge('得 ${won[s]}', Colors.teal),
        ]),
      ]);
    }

    String status;
    var hi = false;
    if (phase == 'bid') {
      hi = turn == me;
      status = hi ? '轮到你叫墩' : '等待 ${g.name(turn)} 叫墩';
    } else if (phase == 'play') {
      hi = turn == me;
      status = hi ? '轮到你出牌' : '等待 ${g.name(turn)} 出牌';
    } else if (phase == 'trickEnd') {
      status = '${g.name(lastWinner)} 赢得这一墩';
    } else if (phase == 'handEnd') {
      status = '本局结束';
    } else {
      status = '比赛结束';
    }

    int teamBid(int t) => [t, t + 2].fold(0, (a, s) => a + (bids[s] ?? 0));
    int teamWon(int t) => won[t] + won[t + 2];

    final info = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        StatusBar(status, highlight: hi),
        trChip('第 ${handNo + 1} 局', Colors.indigo),
        for (var t = 0; t < 2; t++)
          trChip('${_team(t)} ${scores[t]} 分 · 袋 ${bags[t]}${phase != 'bid' ? ' · ${teamWon(t)}/${teamBid(t)}' : ''}',
              t == 0 ? Colors.blue.shade700 : Colors.deepOrange.shade700),
        trChip(v['broken'] == true ? '♠ 已破' : '♠ 未破', v['broken'] == true ? Colors.black87 : Colors.grey.shade700),
        trChip('目标 ${v['target']}', Colors.brown),
        trChip('记分表', Colors.blueGrey, onTap: () => setState(() => _sheet = !_sheet)),
      ],
    );

    final center = TrTrick(g: g, trick: trick, winner: phase == 'trickEnd' ? lastWinner : -1, w: 52);

    Widget bottom(double cw, double maxW) {
      final legal = trList(v['legal']).toSet();
      final myTurnPlay = phase == 'play' && turn == me;
      final myTurnBid = phase == 'bid' && turn == me;
      final hidden = v['hidden'] == true;
      Widget controls = const SizedBox();
      if (myTurnBid && hidden) {
        controls = Wrap(spacing: 8, children: [
          if (v['canBlind'] == true)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.purple),
              onPressed: () => g.act({'type': 'blindnil'}),
              child: const Text('盲零（不看牌，±200）'),
            ),
          FilledButton(onPressed: () => g.act({'type': 'look'}), child: const Text('看牌')),
        ]);
      } else if (myTurnBid) {
        controls = Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
          IconButton.filledTonal(
              onPressed: _bid > 1 ? () => setState(() => _bid--) : null, icon: const Icon(Icons.remove), iconSize: 18),
          Container(
            width: 44,
            alignment: Alignment.center,
            child: Text('$_bid', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          IconButton.filledTonal(
              onPressed: _bid < 13 ? () => setState(() => _bid++) : null, icon: const Icon(Icons.add), iconSize: 18),
          FilledButton(onPressed: () => g.act({'type': 'bid', 'n': _bid}), child: Text('叫 $_bid 墩')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () => g.act({'type': 'bid', 'n': 0}),
            child: const Text('零墩'),
          ),
        ]);
      }
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (me >= 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
              g.tag(me, active: hi, sub: '${bidText(me)}${phase != 'bid' ? ' · 得 ${won[me]}' : ''}', size: 28),
              controls,
            ]),
          ),
        SizedBox(
          width: maxW,
          child: Center(
            child: hidden
                ? Row(mainAxisSize: MainAxisSize.min, children: [trBacks(13, cw), const SizedBox(width: 10), trNote('手牌未看')])
                : TrHand(
                    cards: hand,
                    cardW: cw,
                    legal: legal,
                    dimIllegal: myTurnPlay,
                    onTap: myTurnPlay ? (c) => g.act({'type': 'play', 'card': c}) : null,
                  ),
          ),
        ),
      ]);
    }

    Widget? overlay;
    if (phase == 'handEnd' || phase == 'over') {
      overlay = _resultPanel(phase == 'over');
    } else if (_sheet) {
      overlay = _card(Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetGrid(),
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

  Widget _sheetGrid() {
    final hist = (v['history'] as List?) ?? const [];
    final rows = <List<String>>[];
    for (final h in hist) {
      final m = h as Map;
      final b = [for (final x in m['bids'] as List) (x as num).toInt()];
      final w = _ints(m['won']);
      final sc = _ints(m['scores']);
      final bg = _ints(m['bags']);
      String tb(int t) => '${b[t] == 0 ? 'N' : b[t]}+${b[t + 2] == 0 ? 'N' : b[t + 2]} / ${w[t] + w[t + 2]}';
      rows.add(['${m['no']}', tb(0), '${sc[0]}(${bg[0]})', tb(1), '${sc[1]}(${bg[1]})']);
    }
    if (rows.isEmpty) rows.add(['—', '', '', '', '']);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: trGrid(['局', '南北 叫/得', '南北分(袋)', '东西 叫/得', '东西分(袋)'], rows.length > 12 ? rows.sublist(rows.length - 12) : rows,
          colW: 86),
    );
  }

  Widget _resultPanel(bool over) {
    final r = (v['result'] as Map?) ?? const {};
    final teams = (r['teams'] as List?) ?? const [];
    final scores = _ints(v['scores']);
    final winner = (v['winner'] as num?)?.toInt() ?? -1;
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      for (var t = 0; t < teams.length; t++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${_team(t)}（${g.name(t)}、${g.name(t + 2)}）：${_signed(((teams[t] as Map)['delta'] as num).toInt())}，总分 ${scores[t]}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(trList((teams[t] as Map)['notes']).join('；'), style: const TextStyle(fontSize: 12)),
          ]),
        ),
      const SizedBox(height: 6),
      _sheetGrid(),
      if (!over) trContinue(g, (v['ready'] as List?)?.cast<bool>()),
    ]);
    if (over) {
      return ResultBanner(winner == 2 ? '平局' : '${_team(winner)} 获胜！', child: body);
    }
    return _card(body);
  }
}
