part of 'engine.dart';

extension RiichiBot on RiichiGame {
  Map<String, dynamic>? botAction(int s) {
    if (_over) return null;
    switch (phase) {
      case 'exchange':
        return {'t': 'exchange', 'tiles': _botExchange(s)};
      case 'turn':
        if (s != turn) return null;
        return _botTurn(s);
      case 'call':
      case 'chankan':
        final op = opts[s];
        if (op == null) return null;
        if (op['ron'] == true) return {'t': 'ron'};
        final pons = (op['pon'] as List?)?.cast<List<int>>();
        if (pons != null && pons.isNotEmpty) {
          final k = kindOf(respTile);
          if (_isYakuhaiFor(s, k) && ps[s].score > 0) return {'t': 'pon', 'tiles': pons.first};
        }
        return {'t': 'skip'};
      case 'anyeOpen':
        if (!opts.containsKey(s)) return null;
        // Open only when the dark tile would be our winning tile is unknown; rarely open.
        return {'t': ps[s].riichi && ps[s].score >= 12000 && rng.nextInt(4) == 0 ? 'open' : 'skip'};
      case 'anyeLock':
        return {'t': ps[s].score >= 20000 && rng.nextInt(3) == 0 ? 'lock' : 'nolock'};
      case 'result':
        return {'t': 'ok'};
    }
    return null;
  }

  bool _isYakuhaiFor(int s, int k) => isDragon(k) || k == seatWindKind(s) || k == roundWindKind;

  List<int> _botExchange(int s) {
    final p = ps[s];
    // any 3 tiles (no suit restriction): give away the 3 most isolated
    final ids = [for (final id in p.hand) if (!isWild(id)) id]
      ..sort((a, b) => _isolation(p.hand, b) - _isolation(p.hand, a));
    return ids.take(3).toList();
  }

  /// Higher = more isolated.
  int _isolation(List<int> hand, int id) {
    final k = kindOf(id);
    var score = 10;
    for (final o in hand) {
      if (o == id || isWild(o)) continue;
      final ko = kindOf(o);
      if (ko == k) score -= 4;
      if (k < 27 && ko < 27 && ko ~/ 9 == k ~/ 9 && (ko - k).abs() <= 2) score -= (ko - k).abs() == 1 ? 3 : 2;
    }
    if (isYaochu(k)) score += 1;
    return score;
  }

  Map<String, dynamic> _botTurn(int s) {
    final p = ps[s];
    final ta = turnActions(s);
    if (ta['tsumo'] == true) return {'t': 'tsumo'};
    if (ta['kita'] == true) return {'t': 'kita'};
    if (p.riichi) {
      if ((ta['ankan'] as List).isNotEmpty) return {'t': 'ankan', 'kind': (ta['ankan'] as List).first};
      return {'t': 'discard', 'tile': drawnId};
    }
    final allowed = [
      for (final id in p.hand)
        if (!isWild(id) && !p.forbidden.contains(kindOf(id))) id
    ];
    final visible = _visibleCounts(s);
    final melds = p.melds.length;
    // evaluate each distinct kind
    int bestShan = 99, bestUke = -1;
    var cands = <int>[];
    final seen = <int>{};
    final shanOf = <int, int>{};
    for (final id in allowed) {
      final k = kindOf(id);
      if (!seen.add(k)) continue;
      final rest = List<int>.of(p.hand)..remove(id);
      final c = realCounts(rest);
      final w = wildCount(rest);
      final sh = shanten(c, melds) - w;
      shanOf[k] = sh;
      final uke = w > 0 ? 0 : ukeire(c, melds, visible, allowed: ts.kindInGame);
      if (sh < bestShan || (sh == bestShan && uke > bestUke)) {
        bestShan = sh;
        bestUke = uke;
        cands = [id];
      } else if (sh == bestShan && uke == bestUke) {
        cands.add(id);
      }
    }
    // defence
    final threat = [for (var o = 0; o < n; o++) if (o != s && active(o) && ps[o].riichi) o];
    if (botLevel <= 0) {
      // 简单: no defence, sloppy efficiency — any tile that keeps the shanten
      // (ignoring ukeire), and sometimes one that goes back a step.
      final keep = [for (final id in allowed) if (shanOf[kindOf(id)] == bestShan) id];
      final loose = [for (final id in allowed) if ((shanOf[kindOf(id)] ?? 99) <= bestShan + 1) id];
      final pool = rng.nextInt(10) < 3 && loose.isNotEmpty ? loose : (keep.isNotEmpty ? keep : allowed);
      final pick = pool[rng.nextInt(pool.length)];
      final riichiIds = (ta['riichi'] as List).cast<int>();
      return {'t': 'discard', 'tile': pick, 'riichi': riichiIds.contains(pick) && shanOf[kindOf(pick)] == 0};
    }
    if (botLevel >= 2) {
      final fold = _hardDefence(s, allowed, shanOf, bestShan, visible);
      if (fold != null) {
        final riichiIds = (ta['riichi'] as List).cast<int>();
        return {'t': 'discard', 'tile': fold, 'riichi': riichiIds.contains(fold) && shanOf[kindOf(fold)] == 0};
      }
    }
    if (botLevel == 1 && threat.isNotEmpty && bestShan >= 2) {
      int? safest;
      var safeScore = -1;
      for (final id in allowed) {
        var sc = 0;
        for (final o in threat) {
          if (ps[o].river.any((d) => kindOf(d.id) == kindOf(id) && !d.dark)) {
            sc += 10;
          } else if (isHonor(kindOf(id)) && visible[kindOf(id)] >= 3) {
            sc += 8;
          } else if (isHonor(kindOf(id))) {
            sc += 4;
          } else if (isTerminal(kindOf(id))) {
            sc += 2;
          }
        }
        if (sc > safeScore) {
          safeScore = sc;
          safest = id;
        }
      }
      if (safest != null) return {'t': 'discard', 'tile': safest};
    }
    if ((ta['ankan'] as List).isNotEmpty && bestShan >= 1) {
      final k = (ta['ankan'] as List).first as int;
      // only kan when it does not hurt shanten
      final rest = [for (final id in p.hand) if (kindOf(id) != k || isWild(id)) id];
      if (rest.length % 3 == 2 && shanten(realCounts(rest), melds + 1) - wildCount(rest) <= bestShan) {
        return {'t': 'ankan', 'kind': k};
      }
    }
    // among candidates prefer isolated honours / terminals; prefer non-red, non-dora
    cands.sort((a, b) {
      final ra = ts.isRed(a) ? 1 : 0, rb = ts.isRed(b) ? 1 : 0;
      if (ra != rb) return ra - rb;
      return _isolation(p.hand, b) - _isolation(p.hand, a);
    });
    final pick = cands.isNotEmpty ? cands.first : allowed.first;
    final riichiIds = (ta['riichi'] as List).cast<int>();
    final riichi = riichiIds.contains(pick) && bestShan == 0;
    // 暗夜之战: hide a dangerous tile when someone is in riichi.
    var dark = false;
    if (ta['dark'] == true && threat.isNotEmpty && p.score >= (riichi ? 12000 : 10000)) {
      final k = kindOf(pick);
      final genbutsu = threat.every((o) => ps[o].river.any((d) => kindOf(d.id) == k && !d.dark));
      dark = !genbutsu && !isHonor(k) && rng.nextInt(2) == 0;
    }
    return {'t': 'discard', 'tile': pick, 'riichi': riichi, if (dark) 'dark': true};
  }

  /// 困难 push/fold: against a riichi (or a 3+-meld open hand) fold with the
  /// safest tile unless we are tenpai (or 1-shanten early with no riichi).
  /// Returns null to keep attacking.
  int? _hardDefence(int s, List<int> allowed, Map<int, int> shanOf, int bestShan, List<int> visible) {
    final riichiThreats = [for (var o = 0; o < n; o++) if (o != s && active(o) && ps[o].riichi) o];
    final openThreats = [
      for (var o = 0; o < n; o++)
        if (o != s && active(o) && !ps[o].riichi && ps[o].melds.where((m) => m.open).length >= 3) o
    ];
    final threats = [...riichiThreats, ...openThreats];
    if (threats.isEmpty || allowed.isEmpty) return null;
    final fold = riichiThreats.isNotEmpty ? bestShan >= 1 : bestShan >= 2 && live.length < 40;
    if (!fold) {
      // tenpai / close: still avoid a clearly dangerous tile if an equally good safe one exists
      int? best;
      var bestD = 1 << 30;
      for (final id in allowed) {
        if (shanOf[kindOf(id)] != bestShan) continue;
        final d = _danger(id, threats, visible);
        if (d < bestD) {
          bestD = d;
          best = id;
        }
      }
      return bestD <= 2 ? best : null;
    }
    int? safest;
    var bestD = 1 << 30;
    for (final id in allowed) {
      // prefer safety, then keeping the hand together
      final d = _danger(id, threats, visible) * 10 + ((shanOf[kindOf(id)] ?? 9) - bestShan);
      if (d < bestD) {
        bestD = d;
        safest = id;
      }
    }
    return safest;
  }

  /// Rough deal-in danger of discarding [id] against [threats] (0 = 现物),
  /// from public information only: 现物, 字牌 visible count, 筋.
  int _danger(int id, List<int> threats, List<int> visible) {
    final k = kindOf(id);
    var total = 0;
    for (final o in threats) {
      final river = {for (final d in ps[o].river) if (!d.dark) kindOf(d.id)};
      if (river.contains(k)) continue;
      if (isHonor(k)) {
        total += visible[k] >= 3 ? 1 : (visible[k] == 2 ? 3 : 6);
        continue;
      }
      final num = k % 9 + 1;
      final lo = num - 3 >= 1 && river.contains(k - 3);
      final hi = num + 3 <= 9 && river.contains(k + 3);
      final suji = num <= 3 ? hi : (num >= 7 ? lo : lo && hi);
      if (suji) {
        total += isTerminal(k) ? 2 : 4;
      } else {
        total += isTerminal(k) ? 7 : (num == 2 || num == 8 ? 9 : 12);
      }
      if (visible[k] >= 3) total -= 2;
    }
    return total;
  }

  List<int> _visibleCounts(int s) {
    final v = List<int>.filled(34, 0);
    for (final id in ps[s].hand) {
      if (!isWild(id)) v[kindOf(id)]++;
    }
    for (var o = 0; o < n; o++) {
      for (final d in ps[o].river) {
        if (!d.dark || o == s) v[kindOf(d.id)]++;
      }
      for (final m in ps[o].melds) {
        for (final id in m.tiles) {
          v[kindOf(id)]++;
        }
      }
      for (final id in ps[o].kita) {
        v[kindOf(id)]++;
      }
    }
    for (var i = 0; i < doraShown; i++) {
      v[kindOf(indicators[i])]++;
    }
    for (var k = 0; k < 34; k++) {
      if (v[k] > 4) v[k] = 4;
    }
    return v;
  }
}
