part of 'erren.dart';

/// 二人麻将 bot: shanten-driven; when tenpai prefers waits that reach 起和番;
/// only calls when the call keeps a realistic path to 起和番 (箭刻/风刻 pungs,
/// 清一色 without honours, or an already-secured value). Uses only its own hand
/// and public information.
extension _EpBot on ErrenGame {
  Map<String, dynamic>? botAction(int s) {
    switch (phase) {
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

  bool _valuePung(int s, int t) => isDragon(t) || t - 27 == seatWind(s) || t - 27 == roundWind;

  /// Number of waits of a tenpai (3n+1) hand that reach 起和番 on a discard win.
  int _goodWaits(int s, List<int> c) {
    var good = 0;
    for (final t in waits2p(c, melds[s].length, epKinds)) {
      final cc = List.of(c);
      cc[t]++;
      final r = evaluate2p(cc, melds[s], EpCtx(t, seatWind: seatWind(s), roundWind: roundWind, flowers: 0));
      if (r != null && r.base >= minFan) good++;
    }
    return good;
  }

  int _honorCount(int s) {
    var n = 0;
    for (var t = 27; t < 34; t++) {
      n += hands[s][t];
    }
    for (final m in melds[s]) {
      if (m.tile >= 27) n += 3;
    }
    return n;
  }

  Map<String, dynamic> _botAct(int s) {
    if (canSelfWin) return {'type': 'hu'};
    final c = hands[s];
    final m = melds[s].length;
    final base = shanten(c, m);
    for (final (t, bu) in selfKongs()) {
      final h = List.of(c);
      h[t] -= bu ? 1 : 4;
      if (shanten(h, bu ? m : m + 1) <= base) return {'type': 'gang', 'tile': tileCode(t)};
    }
    final kinds = [for (final t in epKinds) if (c[t] > 0) t];
    if (botLevel == 0 && rng.nextInt(3) == 0) {
      final sorted = List.of(kinds)..sort((a, b) => tileValue(c, a).compareTo(tileValue(c, b)));
      return {'type': 'discard', 'tile': tileCode(sorted[rng.nextInt(sorted.length < 3 ? sorted.length : 3)])};
    }
    // 清一色 plan: few honours → throw honours first
    final flush = _honorCount(s) <= 3 && melds[s].every((mm) => mm.tile < 27);
    var bestT = kinds.first, best = 1 << 30;
    for (final t in kinds) {
      c[t]--;
      var sh = shanten(c, m);
      if (sh == 0 && _goodWaits(s, c) == 0) sh = 1;
      c[t]++;
      var v = sh * 100 + tileValue(c, t) * 2;
      if (t >= 27) {
        if (_valuePung(s, t) && c[t] >= 2) v += 10;
        if (flush && c[t] < 2) v -= 8;
      }
      if (botLevel >= 2 && t >= 27 && c[t] == 1 && _visibleCopies(t) >= 2) v -= 6; // dead honour
      if (v < best) {
        best = v;
        bestT = t;
      }
    }
    return {'type': 'discard', 'tile': tileCode(bestT)};
  }

  int _bestAfterDiscard(List<int> h, int m) {
    var best = 99;
    for (final t in epKinds) {
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
    final hasValue = melds[s].any((mm) => mm.tile >= 27 && _valuePung(s, mm.tile));
    final flush = _honorCount(s) == 0;
    if (o.contains('gang')) {
      final x = List.of(h)..[t] -= 3;
      if (shanten(x, m + 1) <= base) return {'type': 'gang'};
    }
    if (o.contains('peng') && (_valuePung(s, t) || hasValue || flush)) {
      final x = List.of(h)..[t] -= 2;
      if (_bestAfterDiscard(x, m + 1) < base) return {'type': 'peng'};
    }
    if (o.contains('chi') && (hasValue || flush) && botLevel >= 1) {
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
