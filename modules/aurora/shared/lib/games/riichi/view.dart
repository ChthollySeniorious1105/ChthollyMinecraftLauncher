part of 'engine.dart';

extension RiichiView on RiichiGame {
  Map<String, dynamic> buildView(int me) {
    final showAll = phase == 'result' || _over;
    final reveal = (result?['reveal'] as Map?)?.cast<String, dynamic>() ?? const {};
    final seats = <Map<String, dynamic>>[];
    for (var s = 0; s < n; s++) {
      final p = ps[s];
      final river = <Map<String, dynamic>>[];
      var side = false;
      for (final d in p.river) {
        if (d.riichi) side = true;
        if (d.called) continue;
        final hidden = (d.dark || d.locked) && s != me;
        river.add({
          'c': hidden ? 'back' : tileCode(d.id),
          'side': side,
          'tg': d.tsumogiri,
          'dark': d.dark || d.locked,
          'lock': d.locked,
          'ron': d.ronned,
        });
        side = false;
      }
      List<String> handCodes;
      String? drawn;
      if (p.won && rules.bloodbath && s != me && !(showAll && reveal.containsKey('$s'))) {
        // 血战: a winner who stays at the table shows only the winning tile;
        // the rest of the hand stays face down (a tsumo tile was never public).
        handCodes = [for (final id in p.hand) if (id != p.winTile) 'back'];
        drawn = p.winTile >= 0 ? tileCode(p.winTile) : null;
      } else if (s == me || (showAll && reveal.containsKey('$s'))) {
        handCodes = [for (final id in p.hand) if (!(s == turn && id == drawnId && phase == 'turn')) tileCode(id)];
        if (phase == 'turn' && s == turn && drawnId >= 0 && p.hand.contains(drawnId)) drawn = tileCode(drawnId);
      } else {
        final glass = <String>[];
        var backs = 0;
        String? drawnGlass;
        var drawnBack = false;
        for (final id in p.hand) {
          final isDrawn = phase == 'turn' && s == turn && id == drawnId;
          if (isGlass(id)) {
            if (isDrawn) {
              drawnGlass = 'G${tileCode(id)}';
            } else {
              glass.add('G${tileCode(id)}');
            }
          } else if (isDrawn) {
            drawnBack = true;
          } else {
            backs++;
          }
        }
        handCodes = [...glass, for (var i = 0; i < backs; i++) 'back'];
        drawn = drawnGlass ?? (drawnBack ? 'back' : null);
      }
      seats.add({
        'score': p.score,
        'wind': seatWindIdx(s),
        'riichi': p.riichi || pendingRiichi == s,
        'hand': handCodes,
        'drawn': drawn,
        'melds': [for (final m in p.melds) meldJson(m)],
        'river': river,
        'kita': [for (final id in p.kita) tileCode(id)],
        'won': p.won,
      });
    }
    final v = <String, dynamic>{
      'mode': rules.mode,
      'sanma': rules.sanma,
      'n': n,
      // The claim-cover pause looks exactly like a claim window nobody (visible) can use.
      'phase': _over ? 'over' : (phase == 'pause' ? 'call' : phase),
      'turn': turn,
      'dealer': dealer,
      'roundWind': roundWind,
      'kyoku': kyoku,
      'honba': honba,
      'kyoutaku': kyoutaku,
      'wall': live.length,
      'dora': [for (var i = 0; i < 5; i++) i < doraShown ? tileCode(indicators[i]) : 'back'],
      'seats': seats,
      'last': lastEvent == null ? null : {...lastEvent!, 'seq': eventSeq},
      'discarder': discarder,
      'dark': rules.dark,
      'mirror': rules.mirror,
      'bloodbath': rules.bloodbath,
      // During claim windows only seats with a legal claim are waited on; publishing
      // that list would reveal who can pon/chi/win. Each seat only learns about itself.
      'waiting': const {'call', 'chankan', 'anyeOpen'}.contains(phase)
          ? [for (final s in waitingFor) if (s == me) s]
          : waitingFor,
    };
    if (rules.mirror) {
      v['wallPeek'] = [
        for (var i = 0; i < live.length && i < 8; i++) isGlass(live[i]) ? 'G${tileCode(live[i])}' : 'back'
      ];
    }
    if (phase == 'call' || phase == 'pause' || phase == 'chankan' || phase == 'anyeOpen' || phase == 'anyeLock') {
      final hidden = phase == 'anyeOpen' || phase == 'anyeLock';
      v['respTile'] = hidden && me != discarder ? 'back' : tileCode(respTile);
      v['respKind'] = respKind;
    }
    if (rules.exchange) {
      v['exchDir'] = exchDir;
      v['exchDone'] = [for (var s = 0; s < n; s++) exchSel.containsKey(s)];
      if (me >= 0 && exchGot.containsKey(me)) v['exchGot'] = [for (final id in exchGot[me]!) tileCode(id)];
    }
    if (result != null) v['result'] = result;
    if (finalResult != null) v['final'] = finalResult;
    if (me >= 0 && me < n) v['me'] = _myView(me);
    return v;
  }

  Map<String, dynamic> _myView(int me) {
    final p = ps[me];
    final out = <String, dynamic>{
      'hand': [
        for (final id in p.hand) {'id': id, 'c': tileCode(id), 'glass': isGlass(id)}
      ],
      'drawnId': phase == 'turn' && turn == me ? drawnId : -1,
    };
    if (phase == 'turn' && turn == me) {
      final ta = turnActions(me);
      out['discardable'] = [
        for (final id in p.hand)
          if (!isWild(id) && !p.forbidden.contains(kindOf(id)) && (!p.riichi || id == drawnId)) id
      ];
      out['riichi'] = ta['riichi'];
      out['tsumo'] = ta['tsumo'];
      out['ankan'] = [for (final k in ta['ankan'] as List<int>) {'kind': k, 'c': kindCode(k)}];
      out['kakan'] = [for (final k in ta['kakan'] as List<int>) {'kind': k, 'c': kindCode(k)}];
      out['kita'] = ta['kita'];
      out['kyuushu'] = ta['kyuushu'];
      out['canDark'] = ta['dark'];
    }
    if ((phase == 'call' || phase == 'chankan') && opts.containsKey(me) && !resp.containsKey(me)) {
      final op = opts[me]!;
      out['call'] = {
        'ron': op['ron'] == true,
        'kan': op['kan'] == true,
        'pon': [
          for (final pair in (op['pon'] as List?)?.cast<List<int>>() ?? const <List<int>>[])
            {'ids': pair, 'c': [for (final id in pair) tileCode(id)]}
        ],
        'chi': [
          for (final pair in (op['chi'] as List?)?.cast<List<int>>() ?? const <List<int>>[])
            {'ids': pair, 'c': [for (final id in pair) tileCode(id)]}
        ],
      };
    }
    if (phase == 'anyeOpen' && opts.containsKey(me) && !resp.containsKey(me)) out['canOpen'] = true;
    if (phase == 'anyeLock' && discarder == me) out['canLock'] = true;
    if (phase == 'exchange') out['exchPicked'] = exchSel.containsKey(me);
    if (phase == 'result') out['confirmed'] = confirmed.contains(me);
    // tenpai hint
    if (p.hand.length % 3 == 1 && !p.won) {
      final w = waitsFor(me);
      out['waits'] = [for (final k in w) kindCode(k)];
      out['furiten'] = w.isNotEmpty && isFuriten(me, w);
    }
    return out;
  }
}
