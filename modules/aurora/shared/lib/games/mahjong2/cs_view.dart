part of 'changsha.dart';

extension _CsView on ChangshaGame {
  Map<String, dynamic> buildView(int me) {
    final reveal = phase == 'settle' || phase == 'over';
    final seats = <Map<String, dynamic>>[];
    for (var s = 0; s < players; s++) {
      final n = countTotal(hands[s]);
      final hasDrawn = phase == 'act' && turn == s && drawn[s] >= 0 && hands[s][drawn[s]] > 0;
      seats.add({
        'count': n,
        'drawn': hasDrawn,
        'hand': s == me || reveal ? codesOfCounts(hands[s]) : null,
        'melds': [for (final m in melds[s]) m.toJson(hide: m.kind == 'agang' && s != me && !reveal)],
        'discards': [
          for (final d in discards[s]) {'t': tileCode(d.tile), 'taken': d.taken, 'tg': d.tsumogiri, 'flip': d.flip}
        ],
        'wind': seatWind(s),
        'score': scores[s],
        'delta': handDelta[s],
        'locked': locked[s],
        'qishou': qishouShown[s],
      });
    }
    final v = <String, dynamic>{
      'rule': 'changsha',
      'phase': (phase == 'pause' ? 'claim' : phase),
      'hand': handNo,
      'hands': totalHands,
      'dealer': dealer,
      'turn': turn,
      'wall': wall.length,
      'birds': birdN,
      'pao': allowPao,
      'seats': seats,
      'last': lastAction,
      'lastDiscard': lastDiscardSeat,
      'event': lastEvent == null ? null : {...lastEvent!, 'seq': eventSeq},
      // claim windows (and 起手胡 decisions) only reveal whether *I* am being waited on
      'waiting': phase == 'claim' || phase == 'qishou' ? [for (final s in waitingFor) if (s == me) s] : waitingFor,
      'over': over,
      'settle': settle,
      'history': history,
    };
    if (claim != null) {
      v['claimTile'] = tileCode(claim!.tile);
      v['claimTiles'] = [for (final t in claim!.tiles) tileCode(t)];
      v['claimFrom'] = claim!.from;
      v['claimKind'] = claim!.kind;
    } else if (phase == 'pause' && lastDiscardSeat >= 0 && discards[lastDiscardSeat].isNotEmpty) {
      v['claimTile'] = tileCode(discards[lastDiscardSeat].last.tile);
      v['claimTiles'] = [v['claimTile']];
      v['claimFrom'] = lastDiscardSeat;
      v['claimKind'] = 'discard';
    }
    if (over) v['ranking'] = ranking();
    if (me >= 0 && me < players) {
      final my = <String, dynamic>{
        'drawn': phase == 'act' && turn == me && drawn[me] >= 0 && hands[me][drawn[me]] > 0 ? tileCode(drawn[me]) : null,
      };
      if (phase == 'qishou' && qishouOpts.containsKey(me) && !qishouDone.contains(me)) {
        my['qishou'] = [for (final (n, k) in qishouOpts[me]!) k > 1 ? '$n×$k' : n];
      }
      if (phase == 'act' && turn == me) {
        my['canHu'] = canSelfHu;
        my['kongs'] = [
          for (final (t, bu) in selfKongs()) {'tile': tileCode(t), 'kai': kaiOk(me, t, bu ? 1 : 4, fromPeng: bu)}
        ];
        my['discardable'] = [for (final t in legalDiscards(me)) tileCode(t)];
      }
      if (phase == 'claim' && claim!.opts.containsKey(me) && !claim!.resp.containsKey(me)) {
        final c = claim!;
        my['claim'] = c.opts[me]!.toList();
        if (c.hu.containsKey(me)) my['huTile'] = tileCode(c.hu[me]!.$1);
        my['chis'] = [
          for (final lo in c.chis[me] ?? const <int>[]) [for (var k = lo; k < lo + 3; k++) tileCode(k)]
        ];
        if (c.opts[me]!.contains('gang')) my['kaiOk'] = kaiOk(me, c.tile, 3);
      }
      final n = countTotal(hands[me]);
      if (n % 3 == 1 && (phase == 'act' || phase == 'claim' || phase == 'pause')) {
        my['waits'] = [for (final t in csWaits(hands[me], melds[me])) tileCode(t)];
      }
      v['me'] = my;
    }
    return v;
  }
}
