part of 'mcr_game.dart';

extension _McrSettle on McrGame {
  void _win(int s, int from, int tile, {bool rob = false}) {
    final tsumo = from < 0;
    final w = evalWin(s, tile, tsumo: tsumo, rob: rob);
    if (w == null) throw GameError('不能和牌');
    if (rob) {
      hands[from][tile]--;
    } else if (!tsumo) {
      discards[from].last.taken = true;
    }
    // winning tile shown separately
    if (tsumo) hands[s][tile]--;
    drawn[s] = -1;
    winner = s;
    final pay = <String, int>{};
    final horseTiles = <int>[];
    final horseHit = <bool>[];
    var pts = 0;
    if (isMcr) {
      for (var o = 0; o < players; o++) {
        if (o == s) continue;
        final amt = tsumo || o == from ? 8 + w.fan : 8;
        pay['$o'] = amt;
        _pay(o, s, amt);
      }
      pts = w.fan;
    } else {
      pts = gdPoints(w.fan, gdCap);
      for (var i = 0; i < horses && wall.isNotEmpty; i++) {
        final t = wall.removeLast();
        horseTiles.add(t);
        horseHit.add(horseTarget(t) == seatWind(s));
      }
      final hits = horseHit.where((x) => x).length;
      final payers = tsumo || rob ? [for (var o = 0; o < players; o++) if (o != s) o] : [from];
      final d = gdSettle(players, s, payers, pts, hits, robbedFrom: rob ? from : -1);
      for (var o = 0; o < players; o++) {
        if (o != s && d[o] != 0) {
          pay['$o'] = -d[o];
          _pay(o, s, -d[o]);
        }
      }
    }
    final fanText = [
      for (final it in w.items) '${it[0]}${it[1] is int ? it[1] : ''}${(it[2] as int) > 1 ? '×${it[2]}' : ''}'
    ].join(' ');
    final hu = isMcr ? '和' : '胡';
    host.log(tsumo
        ? '${name(s)} 自摸 ${tileName(tile)}！$fanText'
        : '${name(s)} $hu ${name(from)} 的 ${tileName(tile)}${rob ? '（抢杠）' : ''}！$fanText');
    lastAction = tsumo ? '${name(s)} 自摸' : '${name(s)} $hu牌（${name(from)} 放铳）';
    _event(tsumo ? 'zimo' : 'hu', s, tile);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': from,
      'tile': tileCode(tile),
      'tsumo': tsumo,
      'rob': rob,
      'fan': w.fan >= gdLimit && !isMcr ? -1 : w.fan,
      'points': pts,
      'items': w.items,
      'pay': pay,
      'horses': [for (final t in horseTiles) tileCode(t)],
      'horseHit': horseHit,
    }, dealerWon: s == dealer);
  }

  void _drawnGame() {
    host.log('荒庄（流局）');
    lastAction = '荒庄';
    _endHand({'kind': 'draw'}, dealerWon: true);
  }

  void _endHand(Map<String, dynamic> result, {required bool dealerWon}) {
    claim = null;
    result['hand'] = handNo;
    result['delta'] = List.of(handDelta);
    result['gen'] = genPaid;
    result['dealer'] = dealer;
    settle = result;
    history.add({'hand': handNo, 'delta': List.of(handDelta)});
    ready = {};
    // dealer: MCR rotates every hand; GD keeps the deal when the dealer wins or on a draw
    nextDealerKeep = !isMcr && dealerWon;
    if (handNo >= totalHands) {
      phase = 'over';
      over = true;
      final order = ranking();
      host.log('全部 $totalHands 局结束！${[
        for (var i = 0; i < order.length; i++) '第${i + 1} ${name(order[i])} ${scores[order[i]]}'
      ].join('，')}');
    } else {
      phase = 'settle';
    }
  }

  List<int> ranking() => List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));

  void _nextHand() {
    if (!nextDealerKeep) dealer = (dealer + 1) % players;
    _startHand();
  }
}
