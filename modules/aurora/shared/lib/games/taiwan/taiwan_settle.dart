part of 'taiwan_game.dart';

extension _TaiwanSettle on TaiwanGame {
  /// 庄家 / 连庄拉庄 台 applied between the winner and one payer.
  int get dealerTai => 1 + 2 * lian;

  List<List<Object>> _dealerItems(String suffix) => [
        ['庄家$suffix', 1],
        if (lian > 0) ['连$lian拉$lian$suffix', 2 * lian],
      ];

  /// Pays winner [s] from every seat in [payers]; returns seat -> amount.
  Map<String, int> _collect(int s, List<int> payers, int tai) {
    final pay = <String, int>{};
    for (final o in payers) {
      final t = tai + (s == dealer || o == dealer ? dealerTai : 0);
      final amt = di + t * perTai;
      pay['$o'] = amt;
      _pay(o, s, amt);
    }
    return pay;
  }

  void _win(int s, int from, int tile, {bool rob = false}) {
    final tsumo = from < 0;
    final w = evalWin(s, tile, tsumo: tsumo, rob: rob);
    if (w == null) throw GameError('不能胡牌');
    if (rob) {
      hands[from][tile]--;
    } else if (!tsumo) {
      discards[from].last.taken = true;
    }
    if (tsumo) hands[s][tile]--;
    drawn[s] = -1;
    final payers = tsumo ? [for (var o = 0; o < players; o++) if (o != s) o] : [from];
    final pay = _collect(s, payers, w.total);
    final items = <List<Object>>[for (final (n, v) in w.items) [n, v]];
    if (s == dealer) {
      items.addAll(_dealerItems(''));
    } else if (payers.contains(dealer)) {
      items.addAll(_dealerItems('（庄家付）'));
    }
    final text = items.map((e) => '${e[0]}${e[1]}').join(' ');
    host.log(tsumo
        ? '${name(s)} 自摸 ${tileName(tile)}！$text'
        : '${name(s)} 胡 ${name(from)} 的 ${tileName(tile)}${rob ? '（抢杠）' : ''}！$text');
    lastAction = tsumo ? '${name(s)} 自摸' : '${name(s)} 胡牌（${name(from)} 放枪）';
    _event(tsumo ? 'zimo' : 'hu', s, tile);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': from,
      'tile': tileCode(tile),
      'tsumo': tsumo,
      'rob': rob,
      'tai': w.total,
      'items': items,
      'pay': pay,
    }, dealerKeeps: s == dealer);
  }

  /// 八仙过海 (from < 0: all pay) or 七抢一 (from = the seat holding the eighth flower pays).
  void _flowerWin(int s, int from) {
    final tsumo = from < 0;
    drawn[s] = -1;
    final name0 = tsumo ? '八仙过海' : '七抢一';
    final payers = tsumo ? [for (var o = 0; o < players; o++) if (o != s) o] : [from];
    if (!tsumo) {
      // the robbed flower moves over
      final f = flowers[from].removeLast();
      flowers[s].add(f);
    }
    final pay = _collect(s, payers, 8);
    final items = <List<Object>>[
      [name0, 8]
    ];
    if (s == dealer) {
      items.addAll(_dealerItems(''));
    } else if (payers.contains(dealer)) {
      items.addAll(_dealerItems('（庄家付）'));
    }
    host.log(tsumo ? '${name(s)} 八仙过海！集齐八张花牌' : '${name(s)} 七抢一！抢走 ${name(from)} 的花牌');
    lastAction = '${name(s)} $name0';
    _event(tsumo ? 'zimo' : 'hu', s);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': from,
      'tile': tileCode(flowers[s].last),
      'tsumo': tsumo,
      'rob': false,
      'flowerWin': name0,
      'tai': 8,
      'items': items,
      'pay': pay,
    }, dealerKeeps: s == dealer);
  }

  void _drawnGame() {
    host.log('流局（荒庄），${name(dealer)} 连庄');
    lastAction = '流局';
    _endHand({'kind': 'draw'}, dealerKeeps: true);
  }

  void _endHand(Map<String, dynamic> result, {required bool dealerKeeps}) {
    handEnded = true;
    claim = null;
    result['hand'] = handNo;
    result['delta'] = List.of(handDelta);
    result['dealer'] = dealer;
    result['lian'] = lian;
    result['roundWind'] = roundWind;
    settle = result;
    history.add({'hand': handNo, 'delta': List.of(handDelta)});
    ready = {};
    if (dealerKeeps) {
      lian++;
    } else {
      lian = 0;
      dealerPasses++;
      dealer = (dealer + 1) % players;
    }
    final finished = dealerPasses >= totalRounds * players || handNo >= totalRounds * players * 5;
    if (finished) {
      phase = 'over';
      over = true;
      final order = ranking();
      host.log('对局结束！${[
        for (var i = 0; i < order.length; i++) '第${i + 1} ${name(order[i])} ${scores[order[i]]}'
      ].join('，')}');
    } else {
      phase = 'settle';
    }
  }

  List<int> ranking() => List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));

  void _nextHand() => _startHand();
}
