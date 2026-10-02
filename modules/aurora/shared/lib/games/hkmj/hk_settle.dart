part of 'hk_game.dart';

extension _HkSettle on HkGame {
  void _win(int s, int from, int tile, {bool rob = false}) {
    final tsumo = from < 0;
    final w = evalWin(s, tile, tsumo: tsumo, rob: rob);
    if (w == null) throw GameError('不能食糊');
    if (rob) {
      hands[from][tile]--;
    } else if (!tsumo) {
      discards[from].last.taken = true;
    }
    if (tsumo) hands[s][tile]--;
    drawn[s] = -1;
    final fan = w.fan;
    final full = hkPoints(fan);
    final pay = <String, int>{};
    var bao = -1;
    if (tsumo) {
      final big = w.has('大三元') || w.has('大四喜');
      if (big && baoBy[s] >= 0) bao = baoBy[s];
      for (var o = 0; o < players; o++) {
        if (o == s) continue;
        final payer = bao >= 0 ? bao : o;
        pay['$payer'] = (pay['$payer'] ?? 0) + full ~/ 2;
        _pay(payer, s, full ~/ 2);
      }
    } else {
      pay['$from'] = full;
      _pay(from, s, full);
    }
    final fanText = [for (final (n, f) in w.items) '$n${f == hkLimit ? '(满贯)' : f}'].join(' ');
    host.log(tsumo
        ? '${name(s)} 自摸 ${tileName(tile)}！$fanText，共 $fan 番${bao >= 0 ? '（${name(bao)} 包自摸）' : ''}'
        : '${name(s)} 食糊 ${name(from)} 的 ${tileName(tile)}${rob ? '（抢杠）' : ''}！$fanText，共 $fan 番');
    lastAction = tsumo ? '${name(s)} 自摸' : '${name(s)} 食糊（${name(from)} 出铳）';
    _event(tsumo ? 'zimo' : 'hu', s, tile);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': from,
      'tile': tileCode(tile),
      'tsumo': tsumo,
      'rob': rob,
      'fan': fan,
      'limit': fan >= maxFan,
      'points': full,
      'items': [
        for (final (n, f) in w.items) [n, f == hkLimit ? '满贯' : f]
      ],
      'pay': pay,
      'bao': bao,
    }, dealerWon: s == dealer);
  }

  /// 八仙过海 (all 8 flowers): immediate 满贯 self-drawn win.
  void _flowerWin(int s) {
    drawn[s] = -1;
    final full = hkPoints(maxFan);
    final pay = <String, int>{};
    for (var o = 0; o < players; o++) {
      if (o == s) continue;
      pay['$o'] = full ~/ 2;
      _pay(o, s, full ~/ 2);
    }
    host.log('${name(s)} 集齐八张花牌，八仙过海（花糊）！');
    lastAction = '${name(s)} 花糊';
    _event('zimo', s);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': -1,
      'tile': null,
      'tsumo': true,
      'rob': false,
      'fan': maxFan,
      'limit': true,
      'points': full,
      'items': [
        ['八仙过海', '满贯']
      ],
      'pay': pay,
      'bao': -1,
    }, dealerWon: s == dealer);
  }

  void _drawnGame() {
    host.log('流局（荒庄）');
    lastAction = '流局';
    _endHand({'kind': 'draw'}, dealerWon: true);
  }

  void _endHand(Map<String, dynamic> result, {required bool dealerWon}) {
    claim = null;
    result['hand'] = handNo;
    result['delta'] = List.of(handDelta);
    result['dealer'] = dealer;
    result['roundWind'] = roundWind;
    settle = result;
    history.add({'hand': handNo, 'delta': List.of(handDelta)});
    ready = {};
    nextDealerKeep = dealerWon;
    // match ends when the last dealer of the last 圈 loses the deal (or safety cap)
    final lastSeatOfRound = (dealer + 1) % players == firstDealer;
    final finished = (!dealerWon && lastSeatOfRound && roundWind + 1 >= rounds) || handNo >= handCap;
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

  void _nextHand() {
    if (nextDealerKeep) {
      dealerStreak++;
    } else {
      dealerStreak = 0;
      dealer = (dealer + 1) % players;
      if (dealer == firstDealer) roundWind = (roundWind + 1) % 4;
    }
    _startHand();
  }
}
