part of 'changsha.dart';

/// 长沙 bot: shanten-driven, keeps a 2-5-8 pair for 小胡, goes for 清一色 /
/// 碰碰胡 / 七小对 / 将将胡 when the hand leans that way. Only uses its own
/// hand and public information. botLevel 0 plays loosely (random-ish discards,
/// fewer calls), 2 also avoids discarding tiles that are rarely safe late.
extension _CsBot on ChangshaGame {
  Map<String, dynamic>? botAction(int s) {
    switch (phase) {
      case 'qishou':
        if (!qishouOpts.containsKey(s) || qishouDone.contains(s)) return null;
        return {'type': botLevel == 0 && rng.nextInt(4) == 0 ? 'pass' : 'qishou'};
      case 'act':
        if (s != turn) return null;
        return _botAct(s);
      case 'claim':
        final c = claim!;
        final o = c.opts[s];
        if (o == null || c.resp.containsKey(s)) return null;
        if (o.contains('hu')) return {'type': 'hu'};
        return _botClaim(s, c, o);
      case 'settle':
        return ready.contains(s) ? null : {'type': 'next'};
    }
    return null;
  }

  /// Dominant suit for a 清一色 plan, or -1.
  int _planSuit(int s) {
    final per = [0, 0, 0];
    for (var t = 0; t < 27; t++) {
      per[suitOf(t)] += hands[s][t];
    }
    for (final m in melds[s]) {
      per[suitOf(m.tile)] += 3;
    }
    var best = 0;
    for (var i = 1; i < 3; i++) {
      if (per[i] > per[best]) best = i;
    }
    for (final m in melds[s]) {
      if (suitOf(m.tile) != best) return -1;
    }
    return per[best] >= 10 ? best : -1;
  }

  /// Discard score (lower = better to throw).
  int _score(int s, List<int> c, int t, int plan) {
    c[t]--;
    var sh = shanten(c, melds[s].length);
    if (sh == 0 && csWaits(c, melds[s]).isEmpty) sh = 1; // tenpai without a legal win
    c[t]++;
    var v = sh * 100 + tileValue(c, t) * 2;
    if (plan >= 0) v += suitOf(t) == plan ? 12 : -12;
    // keep 2-5-8 pairs for 小胡
    if (is258(t) && c[t] == 2) v += 6;
    if (is258(t)) v += 1;
    if (botLevel >= 2) {
      // late game: prefer tiles already seen on the table (safer)
      if (wall.length < 30) {
        var seen = 0;
        for (var o = 0; o < players; o++) {
          for (final d in discards[o]) {
            if (d.tile == t) seen++;
          }
        }
        v -= seen * 3;
      }
    }
    return v;
  }

  Map<String, dynamic> _botAct(int s) {
    if (canSelfHu) return {'type': 'hu'};
    final c = hands[s];
    final m = melds[s].length;
    final legal = legalDiscards(s);
    if (locked[s]) return {'type': 'discard', 'tile': tileCode(legal.first)};
    final base = shanten(c, m);
    for (final (t, bu) in selfKongs()) {
      final h = List.of(c);
      h[t] -= bu ? 1 : 4;
      final after = shanten(h, bu ? m : m + 1);
      if (after <= base) {
        final kai = botLevel >= 1 && kaiOk(s, t, bu ? 1 : 4, fromPeng: bu) && wall.length > 8;
        return {'type': 'gang', 'tile': tileCode(t), 'mode': kai ? 'kai' : 'bu'};
      }
    }
    if (botLevel == 0 && rng.nextInt(3) == 0) {
      // 简单: sometimes a plain "least connected" discard
      final sorted = List.of(legal)..sort((a, b) => tileValue(c, a).compareTo(tileValue(c, b)));
      return {'type': 'discard', 'tile': tileCode(sorted[rng.nextInt(sorted.length < 3 ? sorted.length : 3)])};
    }
    final plan = _planSuit(s);
    var bestT = legal.first, best = 1 << 30;
    for (final t in legal) {
      final v = _score(s, c, t, plan);
      if (v < best) {
        best = v;
        bestT = t;
      }
    }
    return {'type': 'discard', 'tile': tileCode(bestT)};
  }

  int _bestAfterDiscard(List<int> h, int m) {
    var best = 99;
    for (var t = 0; t < 27; t++) {
      if (h[t] == 0) continue;
      h[t]--;
      final sh = shanten(h, m);
      h[t]++;
      if (sh < best) best = sh;
    }
    return best;
  }

  Map<String, dynamic> _botClaim(int s, _Claim c, Set<String> o) {
    if (botLevel == 0 && rng.nextInt(2) == 0) return {'type': 'pass'};
    final h = hands[s];
    final m = melds[s].length;
    final base = shanten(h, m);
    final t = c.tile;
    final plan = _planSuit(s);
    final fits = plan < 0 || suitOf(t) == plan;
    if (o.contains('gang')) {
      final x = List.of(h)..[t] -= 3;
      if (shanten(x, m + 1) <= base) {
        final kai = botLevel >= 1 && kaiOk(s, t, 3) && wall.length > 8;
        return {'type': 'gang', 'mode': kai ? 'kai' : 'bu'};
      }
    }
    if (o.contains('peng') && fits) {
      final x = List.of(h)..[t] -= 2;
      if (_bestAfterDiscard(x, m + 1) < base) return {'type': 'peng'};
    }
    if (o.contains('chi') && fits) {
      for (final lo in c.chis[s] ?? const <int>[]) {
        final x = List.of(h);
        for (var k = lo; k < lo + 3; k++) {
          if (k != t) x[k]--;
        }
        if (_bestAfterDiscard(x, m + 1) < base) return {'type': 'chi', 'tile': tileCode(lo)};
      }
    }
    return {'type': 'pass'};
  }
}
