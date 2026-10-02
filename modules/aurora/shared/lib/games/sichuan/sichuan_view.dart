part of 'sichuan.dart';

extension _SichuanView on SichuanGame {
  List<String> _handCodes(int s) => [
        for (var t = 0; t < 27; t++)
          for (var k = 0; k < hands[s][t]; k++) tileCode(t)
      ];

  Map<String, dynamic> buildView(int me) {
    final reveal = phase == 'settle' || phase == 'over';
    final seats = <Map<String, dynamic>>[];
    for (var s = 0; s < players; s++) {
      // 血战: a seat that already won keeps its hand face down until the
      // settlement; only the winning tile (winTile) is public.
      final showHand = s == me || reveal;
      var n = 0;
      for (final x in hands[s]) {
        n += x;
      }
      final hasDrawn = phase == 'act' && turn == s && drawn[s] >= 0 && hands[s][drawn[s]] > 0;
      seats.add({
        'count': n,
        'drawn': hasDrawn,
        'hand': showHand ? _handCodes(s) : null,
        'melds': [
          // concealed kongs are face down: only the owner (or the settle screen) sees the tile
          for (final m in melds[s])
            {'kind': m.kind, 'tile': m.kind == 'agang' && !showHand ? 'back' : tileCode(m.tile), 'from': m.from}
        ],
        'discards': [
          for (final d in discards[s]) {'t': tileCode(d.tile), 'taken': d.taken, 'tg': d.tsumogiri}
        ],
        'que': phase == 'que' ? -1 : que[s],
        'queDone': quePick.length > s && quePick[s] != null,
        'swapDone': swapPick.length > s && swapPick[s] != null,
        'won': wonOrder[s],
        'winTile': winTile[s] >= 0 ? tileCode(winTile[s]) : null,
        'score': scores[s],
        'delta': handDelta[s],
      });
    }
    final v = <String, dynamic>{
      // The claim-cover pause looks exactly like a claim window nobody (visible) can use.
      'phase': (phase == 'pause' ? 'claim' : phase),
      'hand': handNo,
      'hands': totalHands,
      'dealer': dealer,
      'turn': turn,
      'wall': wall.length,
      'cap': cap,
      'zimoFan': zimoFan,
      'swapOn': swapOn,
      'swapDir': phase == 'swap' ? 0 : swapDir,
      'seats': seats,
      'last': lastAction,
      'lastDiscard': lastDiscardSeat,
      'event': lastEvent == null ? null : {...lastEvent!, 'seq': eventSeq},
      // During claim windows only seats with a legal claim are waited on; publishing
      // that list would reveal who can pon/chi/win. Each seat only learns about itself.
      'waiting': phase == 'claim' ? [for (final s in waitingFor) if (s == me) s] : waitingFor,
      'over': over,
      'settle': settle,
      'history': history,
    };
    if (claim != null) {
      v['claimTile'] = tileCode(claim!.tile);
      v['claimFrom'] = claim!.from;
      v['claimQiang'] = claim!.qiang;
    }
    if (phase == 'pause' && lastDiscardSeat >= 0 && discards[lastDiscardSeat].isNotEmpty) {
      v['claimTile'] = tileCode(discards[lastDiscardSeat].last.tile);
      v['claimFrom'] = lastDiscardSeat;
      v['claimQiang'] = false;
    }
    if (over) {
      final order = List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
      v['ranking'] = order;
    }
    if (me >= 0 && me < players) {
      final my = <String, dynamic>{
        'drawn': phase == 'act' && turn == me && drawn[me] >= 0 && hands[me][drawn[me]] > 0 ? tileCode(drawn[me]) : null,
        'swapGot': [for (final t in swapGot[me]) tileCode(t)],
        'swapPick': swapPick[me] == null ? null : [for (final t in swapPick[me]!) tileCode(t)],
        'quePick': quePick[me],
      };
      if (phase == 'que' && quePick[me] == null) my['queHint'] = _fewestSuit(hands[me]);
      if (phase == 'swap' && swapPick[me] == null) my['swapHint'] = [for (final t in _botSwap(me)) tileCode(t)];
      if (phase == 'act' && turn == me) {
        my['canHu'] = canSelfHu;
        my['kongs'] = [for (final (t, _) in selfKongs()) tileCode(t)];
        my['discardable'] = [for (final t in legalDiscards()) tileCode(t)];
      }
      if (phase == 'claim' && claim!.opts.containsKey(me) && !claim!.resp.containsKey(me)) {
        my['claim'] = claim!.opts[me]!.toList();
      }
      if (_active(me) && que[me] >= 0 && phase != 'que' && phase != 'swap' && !_hasQue(me)) {
        var n = 0;
        for (final x in hands[me]) {
          n += x;
        }
        if (n % 3 == 1) {
          my['waits'] = [for (final t in waitingTiles(hands[me], melds[me], que: que[me])) tileCode(t)];
        }
      }
      v['me'] = my;
    }
    return v;
  }
}
