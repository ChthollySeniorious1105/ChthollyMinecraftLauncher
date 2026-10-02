part of 'taiwan_game.dart';

extension _TaiwanView on TaiwanGame {
  List<String> _handCodes(int s) => [
        for (var t = 0; t < kKinds; t++)
          for (var k = 0; k < hands[s][t]; k++) tileCode(t)
      ];

  Map<String, dynamic> buildView(int me) {
    final reveal = phase == 'settle' || phase == 'over';
    // during settlement show the winds/dealer of the finished hand
    final shownDealer = reveal && settle != null ? settle!['dealer'] as int : dealer;
    final seats = <Map<String, dynamic>>[];
    for (var s = 0; s < players; s++) {
      final n = countTotal(hands[s]);
      final hasDrawn = phase == 'act' && turn == s && drawn[s] >= 0 && hands[s][drawn[s]] > 0;
      seats.add({
        'count': n,
        'drawn': hasDrawn,
        'hand': s == me || reveal ? _handCodes(s) : null,
        // concealed kongs are face down: only the owner (or the settle screen) sees the tiles
        'melds': [
          for (final m in melds[s])
            m.kind == 'agang' && s != me && !reveal
                ? {...m.toJson(), 'tiles': const ['back', 'back', 'back', 'back']}
                : m.toJson()
        ],
        'flowers': [for (final f in flowers[s]) tileCode(f)],
        'discards': [
          for (final d in discards[s]) {'t': tileCode(d.tile), 'taken': d.taken, 'tg': d.tsumogiri}
        ],
        'wind': (s - shownDealer + players) % players,
        'score': scores[s],
        'delta': handDelta[s],
      });
    }
    final v = <String, dynamic>{
      // The claim-cover pause looks exactly like a claim window nobody (visible) can use.
      'phase': (phase == 'pause' ? 'claim' : phase),
      'hand': handNo,
      'rounds': totalRounds,
      'dealer': shownDealer,
      'lian': reveal && settle != null ? settle!['lian'] as int : lian,
      'roundWind': reveal && settle != null ? settle!['roundWind'] as int : roundWind,
      'dealerNo': dealerPasses % players,
      'turn': turn,
      'wall': drawable < 0 ? 0 : drawable,
      'di': di,
      'perTai': perTai,
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
      v['claimRob'] = claim!.rob;
    }
    if (phase == 'pause' && lastDiscardSeat >= 0 && discards[lastDiscardSeat].isNotEmpty) {
      v['claimTile'] = tileCode(discards[lastDiscardSeat].last.tile);
      v['claimFrom'] = lastDiscardSeat;
      v['claimRob'] = false;
    }
    if (over) v['ranking'] = ranking();
    if (me >= 0 && me < players) {
      final my = <String, dynamic>{
        'drawn': phase == 'act' && turn == me && drawn[me] >= 0 && hands[me][drawn[me]] > 0 ? tileCode(drawn[me]) : null,
      };
      if (phase == 'act' && turn == me) {
        my['canHu'] = canSelfWin;
        my['kongs'] = [for (final (t, _) in selfKongs()) tileCode(t)];
      }
      if (phase == 'claim' && claim!.opts.containsKey(me) && !claim!.resp.containsKey(me)) {
        my['claim'] = claim!.opts[me]!.toList();
        my['chis'] = [
          for (final lo in claim!.chis[me] ?? const <int>[]) [for (var k = lo; k < lo + 3; k++) tileCode(k)]
        ];
      }
      final n = countTotal(hands[me]);
      if (n % 3 == 1 && (phase == 'act' || phase == 'claim')) {
        my['waits'] = [for (final t in waitsOf(hands[me])) tileCode(t)];
      }
      v['me'] = my;
    }
    return v;
  }
}
