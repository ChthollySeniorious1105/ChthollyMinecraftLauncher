part of 'sichuan.dart';

extension _SichuanBot on SichuanGame {
  Map<String, dynamic>? botAction(int s) {
    switch (phase) {
      case 'swap':
        if (swapPick[s] != null) return null;
        return {'type': 'swap', 'tiles': [for (final t in _botSwap(s)) tileCode(t)]};
      case 'que':
        if (quePick[s] != null) return null;
        return {'type': 'que', 'suit': _fewestSuit(hands[s])};
      case 'act':
        if (s != turn) return null;
        return _botAct(s);
      case 'claim':
        final c = claim!;
        final o = c.opts[s];
        if (o == null || c.resp.containsKey(s)) return null;
        if (o.contains('hu')) return {'type': 'hu'};
        final base = shanten(hands[s], melds[s].length, que: que[s]);
        if (o.contains('gang')) {
          final h = List.of(hands[s]);
          h[c.tile] -= 3;
          if (shanten(h, melds[s].length + 1, que: que[s]) <= base) return {'type': 'gang'};
        }
        if (o.contains('peng')) {
          final h = List.of(hands[s]);
          h[c.tile] -= 2;
          // best shanten after the discard that follows
          var best = 99;
          for (var t = 0; t < 27; t++) {
            if (h[t] == 0) continue;
            h[t]--;
            final sh = shanten(h, melds[s].length + 1, que: que[s]);
            h[t]++;
            if (sh < best) best = sh;
          }
          if (best < base) return {'type': 'peng'};
        }
        return {'type': 'pass'};
      case 'settle':
        return ready.contains(s) ? null : {'type': 'next'};
    }
    return null;
  }

  /// Copies of [t] visible to [s] (own hand, all discards, all melds).
  int _seen(int s, int t) {
    var n = hands[s][t];
    for (var o = 0; o < players; o++) {
      for (final d in discards[o]) {
        if (d.tile == t && !d.taken) n++;
      }
      for (final m in melds[o]) {
        if (m.kind == 'agang' && o != s) continue;
        if (m.tile == t) n += m.size;
      }
      if (o != s && winTile[o] == t) n++;
    }
    return n > 4 ? 4 : n;
  }

  /// Unseen copies of the tiles that lower the shanten of [c] (3n+1 hand).
  int _liveOuts(int s, List<int> c, int q) {
    final base = shanten(c, melds[s].length, que: q);
    var n = 0;
    for (var t = 0; t < 27; t++) {
      if (suitOf(t) == q || c[t] >= 4) continue;
      c[t]++;
      final sh = shanten(c, melds[s].length, que: q);
      c[t]--;
      if (sh < base) n += 4 - _seen(s, t);
    }
    return n;
  }

  int _fewestSuit(List<int> c) {
    var best = 0, bestN = 99;
    for (var su = 0; su < 3; su++) {
      var n = 0;
      for (var r = 0; r < 9; r++) {
        n += c[su * 9 + r];
      }
      if (n < bestN) {
        bestN = n;
        best = su;
      }
    }
    return best;
  }

  List<int> _botSwap(int s) {
    final c = hands[s];
    var best = -1, bestN = 99;
    for (var su = 0; su < 3; su++) {
      var n = 0;
      for (var r = 0; r < 9; r++) {
        n += c[su * 9 + r];
      }
      if (n >= 3 && n < bestN) {
        bestN = n;
        best = su;
      }
    }
    final tiles = <int>[
      for (var r = 0; r < 9; r++)
        for (var k = 0; k < c[best * 9 + r]; k++) best * 9 + r
    ];
    tiles.sort((a, b) => tileValue(c, a).compareTo(tileValue(c, b)));
    return tiles.take(3).toList();
  }

  Map<String, dynamic> _botAct(int s) {
    if (canSelfHu) return {'type': 'hu'};
    final c = hands[s];
    final q = que[s];
    final base = shanten(c, melds[s].length, que: q);
    for (final (t, bu) in selfKongs()) {
      final h = List.of(c);
      if (bu) {
        h[t] -= 1;
        if (shanten(h, melds[s].length, que: q) <= base) return {'type': 'gang', 'tile': tileCode(t)};
      } else {
        h[t] -= 4;
        if (shanten(h, melds[s].length + 1, que: q) <= base) return {'type': 'gang', 'tile': tileCode(t)};
      }
    }
    final legal = legalDiscards();
    if (legal.isEmpty) return {'type': 'discard', 'tile': tileCode(_anyTile(s))};
    if (suitOf(legal.first) == q && _hasQue(s)) {
      legal.sort((a, b) => tileValue(c, a).compareTo(tileValue(c, b)));
      return {'type': 'discard', 'tile': tileCode(legal.first)};
    }
    if (botLevel <= 0) {
      // 简单: any tile that doesn't worsen shanten, sometimes a random one.
      final sh0 = <int, int>{};
      for (final t in legal) {
        c[t]--;
        sh0[t] = shanten(c, melds[s].length, que: q);
        c[t]++;
      }
      final best = sh0.values.reduce((a, b) => a < b ? a : b);
      final keep = [for (final t in legal) if (sh0[t] == best) t];
      final pool = rng.nextInt(10) < 3 ? legal : keep;
      return {'type': 'discard', 'tile': tileCode(pool[rng.nextInt(pool.length)])};
    }
    var bestT = legal.first, bestSh = 99, bestV = 1 << 30;
    for (final t in legal) {
      c[t]--;
      final sh = shanten(c, melds[s].length, que: q);
      final live = botLevel >= 2 && sh <= 1 ? _liveOuts(s, c, q) : 0;
      c[t]++;
      // 困难: among equal shanten prefer more live outs, then already-seen (safer) tiles
      final v = tileValue(c, t) - live * 2 - (botLevel >= 2 ? _seen(s, t) : 0);
      if (sh < bestSh || (sh == bestSh && v < bestV)) {
        bestSh = sh;
        bestV = v;
        bestT = t;
      }
    }
    return {'type': 'discard', 'tile': tileCode(bestT)};
  }
}
