part of 'mcr_game.dart';

/// Bot: shanten-driven with a simple fan plan (清一色/混一色 when one suit dominates,
/// 碰碰和 when many pairs/pungs) and, when tenpai, preference for waits that reach 起和番.
/// Uses only the seat's own hand and public information.
extension _McrBot on McrGame {
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

  /// Dominant suit for a flush plan, or -1.
  int _planSuit(int s) {
    final all = List.of(hands[s]);
    for (final m in melds[s]) {
      for (final t in m.tiles) {
        all[t]++;
      }
    }
    final per = [0, 0, 0];
    var honors = 0;
    for (var t = 0; t < kKinds; t++) {
      if (t < 27) {
        per[suitOf(t)] += all[t];
      } else {
        honors += all[t];
      }
    }
    var best = 0;
    for (var i = 1; i < 3; i++) {
      if (per[i] > per[best]) best = i;
    }
    // melds of other suits make a flush impossible
    for (final m in melds[s]) {
      if (m.tile < 27 && suitOf(m.tile) != best) return -1;
    }
    return per[best] + honors >= 10 ? best : -1;
  }

  bool _fitsPlan(int plan, int t) => plan < 0 || t >= 27 || suitOf(t) == plan;

  /// Penalty for keeping tiles that don't fit the plan (lower is better when discarding [t]).
  int _planScore(int s, int plan, int t) {
    if (plan < 0) return 0;
    return _fitsPlan(plan, t) ? 6 : -6;
  }

  int _tileValue(List<int> c, int t) {
    var v = c[t] * 4;
    if (t < 27) {
      final r = rankOf(t);
      for (var d = -2; d <= 2; d++) {
        if (d == 0) continue;
        final rr = r + d;
        if (rr < 1 || rr > 9) continue;
        final k = t + d;
        if (c[k] > 0) v += d.abs() == 1 ? 3 : 2;
      }
      if (r == 1 || r == 9) v -= 1;
    } else {
      v -= 1;
      if (isDragon(t) || t - 27 == seatWind(turn) || t - 27 == roundWind) v += 1;
    }
    return v;
  }

  /// Best fan reachable over the waits of a tenpai (3n+1) hand, assuming a discard win.
  int _waitQuality(int s, List<int> c) {
    final waits = waitsOf(c, melds[s].length);
    var good = 0;
    for (final t in waits) {
      final cc = List.of(c);
      cc[t]++;
      if (isMcr) {
        final r = evaluateMcr(cc, melds[s], WinCtx(t, seatWind: seatWind(s), roundWind: roundWind));
        if (r != null && r.base >= minFan) good++;
      } else {
        final r = evaluateGd(cc, melds[s], GdCtx(sevenPairs: gdSevenPairs));
        if (r != null && r.fan >= minFan) good++;
      }
    }
    return good;
  }

  Map<String, dynamic> _botAct(int s) {
    if (canSelfWin) return {'type': 'hu'};
    final c = hands[s];
    final m = melds[s].length;
    final base = shanten(c, m);
    for (final (t, bu) in selfKongs()) {
      final h = List.of(c);
      if (bu) {
        h[t] -= 1;
        if (shanten(h, m) <= base) return {'type': 'gang', 'tile': tileCode(t)};
      } else {
        h[t] -= 4;
        if (shanten(h, m + 1) <= base) return {'type': 'gang', 'tile': tileCode(t)};
      }
    }
    if (botLevel <= 0) return {'type': 'discard', 'tile': tileCode(_easyDiscard(c, m))};
    final plan = _planSuit(s);
    final hard = botLevel >= 2;
    final late = wall.length < 24;
    var bestT = -1;
    var bestScore = 1 << 30;
    for (var t = 0; t < kKinds; t++) {
      if (c[t] == 0) continue;
      c[t]--;
      var sh = shanten(c, m);
      if (sh == 0 && _waitQuality(s, c) == 0) sh = 1; // tenpai but can't reach 起和番
      final live = hard && sh == 0 ? _liveWaits(s, c) : 0;
      c[t]++;
      var score = sh * 100 + _tileValue(c, t) + _planScore(s, plan, t);
      if (hard) {
        // 困难: prefer waits with more live tiles; far from winning late in the
        // hand, fold toward tiles that are already on the table (fewer outs for others).
        score -= live * 3;
        final seen = _visibleCopies(t) + c[t];
        score -= late && base >= 2 ? seen * 40 : seen;
      }
      if (score < bestScore) {
        bestScore = score;
        bestT = t;
      }
    }
    if (bestT < 0) bestT = drawn[s];
    return {'type': 'discard', 'tile': tileCode(bestT)};
  }

  /// 简单: a random tile among those that keep the best shanten (no fan plan,
  /// no wait quality, no safety), and 30% of the time any tile at all.
  int _easyDiscard(List<int> c, int m) {
    final sh = <int, int>{};
    for (var t = 0; t < kKinds; t++) {
      if (c[t] == 0) continue;
      c[t]--;
      sh[t] = shanten(c, m);
      c[t]++;
    }
    final best = sh.values.reduce((a, b) => a < b ? a : b);
    final pool = rng.nextInt(10) < 3 ? sh.keys.toList() : [for (final e in sh.entries) if (e.value == best) e.key];
    return pool[rng.nextInt(pool.length)];
  }

  /// Live (unseen) copies of the waits of a tenpai 3n+1 hand.
  int _liveWaits(int s, List<int> c) {
    var n = 0;
    for (final t in waitsOf(c, melds[s].length)) {
      final left = 4 - _visibleCopies(t) - c[t];
      if (left > 0) n += left;
    }
    return n;
  }

  int _bestAfterDiscard(List<int> h, int m) {
    var best = 99;
    for (var t = 0; t < kKinds; t++) {
      if (h[t] == 0) continue;
      h[t]--;
      final sh = shanten(h, m);
      h[t]++;
      if (sh < best) best = sh;
    }
    return best;
  }

  Map<String, dynamic> _botClaim(int s, _Claim c, Set<String> o) {
    // 简单: calls only now and then, without any plan
    if (botLevel <= 0 && rng.nextInt(3) != 0) return {'type': 'pass'};
    final h = hands[s];
    final m = melds[s].length;
    final base = shanten(h, m);
    final plan = _planSuit(s);
    final t = c.tile;
    // MCR: calling destroys 门前清; only call along a plan (flush / honours pungs)
    final planOk = _fitsPlan(plan, t) && (plan >= 0 || !isMcr || isDragon(t));
    if (o.contains('gang') && planOk) {
      final x = List.of(h)..[t] -= 3;
      if (shanten(x, m + 1) <= base) return {'type': 'gang'};
    }
    if (o.contains('peng') && planOk) {
      final x = List.of(h)..[t] -= 2;
      if (_bestAfterDiscard(x, m + 1) < base) return {'type': 'peng'};
    }
    if (o.contains('chi') && planOk && plan >= 0) {
      for (final lo in c.chis[s] ?? const <int>[]) {
        final x = List.of(h);
        for (var k = lo; k < lo + 3; k++) {
          if (k != t) x[k]--;
        }
        if (_bestAfterDiscard(x, m + 1) < base) return {'type': 'chi', 'tile': tileCode(lo)};
      }
    }
    if (o.contains('chi') && !isMcr && plan < 0 && minFan == 0) {
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
