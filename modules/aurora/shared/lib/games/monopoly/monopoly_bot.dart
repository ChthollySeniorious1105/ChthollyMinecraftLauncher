part of 'monopoly.dart';

/// Bot strategy (uses public information only: auction bids of others are
/// never read).
extension MonopolyBot on MonopolyGame {
  static const int _reserve = 150;

  /// Cash to keep in hand. 困难 scales it with the worst rent an opponent can
  /// currently charge; 简单 barely keeps anything.
  int _reserveFor(int seat) {
    if (botLevel <= 0) return 40;
    if (botLevel == 1) return _reserve;
    var danger = 0;
    for (var i = 0; i < 40; i++) {
      final o = owner[i];
      if (o < 0 || o == seat || mortgaged[i]) continue;
      final r = rentFor(i);
      if (r > danger) danger = r;
    }
    return (100 + danger * 0.6).clamp(100, 700).round();
  }

  /// How many squares of [sq]'s group [s] owns (excluding [sq] itself).
  int _ownedInGroup(int s, int sq) {
    final d = mBoard[sq];
    List<int> grp;
    if (d.type == SqType.station) {
      grp = mStations;
    } else if (d.type == SqType.utility) {
      grp = mUtilities;
    } else {
      grp = mGroups[d.group];
    }
    return grp.where((i) => i != sq && owner[i] == s).length;
  }

  int _groupSize(int sq) {
    final d = mBoard[sq];
    if (d.type == SqType.station) return 4;
    if (d.type == SqType.utility) return 2;
    return mGroups[d.group].length;
  }

  bool _completes(int s, int sq) => mBoard[sq].type == SqType.street && _ownedInGroup(s, sq) == _groupSize(sq) - 1;

  /// Subjective value of square [sq] to seat [s].
  double valueTo(int s, int sq) {
    final d = mBoard[sq];
    var v = d.price.toDouble();
    if (mortgaged[sq]) v -= d.mortgage;
    final mine = _ownedInGroup(s, sq);
    if (_completes(s, sq)) {
      v += d.price * 1.0;
    } else {
      v += d.price * 0.25 * mine;
    }
    return v;
  }

  Map<String, dynamic>? botImpl(int seat) {
    if (over || bankrupt[seat]) return null;
    switch (phase) {
      case 'auction':
        return _botAuction(seat);
      case 'debt':
        return _botDebt(seat);
      case 'trade':
        return _botTradeAnswer(seat);
      case 'buy':
        if (seat != turn) return null;
        final d = mBoard[buySq];
        final left = cash[seat] - d.price;
        if (botLevel <= 0) {
          // 简单: coin-flip-ish buyer that ignores colour sets
          return {'t': left >= 0 && rng.nextInt(3) != 0 ? 'buy' : 'decline'};
        }
        final keen = _completes(seat, buySq) || active.any((o) => o != seat && _completes(o, buySq));
        if (botLevel >= 2) {
          // 困难: early on almost everything is worth buying; blocking sets matters
          final unowned = List.generate(40, (i) => i).where((i) => mBoard[i].ownable && owner[i] < 0).length;
          final res = unowned > 14 ? 60 : _reserveFor(seat) ~/ 2;
          if (left >= 0 && (left >= res || (keen && left >= 0) || liquidValue(seat) + left >= _reserveFor(seat))) {
            return {'t': 'buy'};
          }
          return {'t': 'decline'};
        }
        if (left >= 0 && (left >= _reserve || (keen && left >= 20))) return {'t': 'buy'};
        return {'t': 'decline'};
      case 'roll':
        if (seat != turn) return null;
        final m = _botManage(seat);
        if (m != null) return m;
        if (inJail[seat]) {
          if (jailCards[seat].isNotEmpty) return {'t': 'useCard'};
          // early game: get out and buy; late game: staying in jail is safe
          final unowned = List.generate(40, (i) => i).where((i) => mBoard[i].ownable && owner[i] < 0).length;
          if (botLevel <= 0) {
            if (cash[seat] >= 50 && rng.nextBool()) return {'t': 'payJail'};
          } else if (cash[seat] >= 50 + _reserveFor(seat) && unowned > (botLevel >= 2 ? 4 : 6)) {
            return {'t': 'payJail'};
          }
        }
        return {'t': 'roll'};
      case 'end':
        if (seat != turn) return null;
        final m = _botManage(seat);
        if (m != null) return m;
        // one proposal per turn at most (tradesThisTurn is game state set by handle)
        if (tradesThisTurn == 0 && botLevel > 0) {
          final t = _botProposeTrade(seat);
          if (t != null) return t;
        }
        return {'t': 'end'};
    }
    return null;
  }

  Map<String, dynamic>? _botManage(int seat) {
    if (botLevel <= 0) {
      // 简单: builds occasionally on a random legal square, never unmortgages
      final b = legalFor(seat, 'build');
      if (b.isNotEmpty && rng.nextInt(3) == 0) {
        final sq = b[rng.nextInt(b.length)];
        if (cash[seat] - mBoard[sq].houseCost >= 100) return {'t': 'build', 'sq': sq};
      }
      return null;
    }
    if (botLevel >= 2) return _botManageHard(seat);
    // unmortgage (prefer squares in groups where we own a monopoly)
    for (final sq in legalFor(seat, 'unmortgage')) {
      if (cash[seat] - mBoard[sq].unmortgageCost >= 400) return {'t': 'unmortgage', 'sq': sq};
    }
    final builds = legalFor(seat, 'build');
    if (builds.isNotEmpty) {
      // most expensive group first; keep a reserve that scales with the board danger
      builds.sort((a, b) => mBoard[b].houseCost.compareTo(mBoard[a].houseCost));
      for (final sq in builds) {
        if (cash[seat] - mBoard[sq].houseCost >= _reserve + 50) return {'t': 'build', 'sq': sq};
      }
    }
    return null;
  }

  /// 困难 building: evenly up to 3 houses on every monopoly first (best rent
  /// jump), cheapest-per-rent groups first, then hotels; unmortgage monopoly
  /// pieces before anything else.
  Map<String, dynamic>? _botManageHard(int seat) {
    final reserve = _reserveFor(seat);
    final unm = legalFor(seat, 'unmortgage');
    unm.sort((a, b) {
      int sc(int i) => (mBoard[i].type == SqType.street && hasMonopoly(seat, mBoard[i].group)) ? 0 : 1;
      return sc(a).compareTo(sc(b));
    });
    for (final sq in unm) {
      final mono = mBoard[sq].type == SqType.street && hasMonopoly(seat, mBoard[sq].group);
      if (cash[seat] - mBoard[sq].unmortgageCost >= (mono ? reserve : reserve + 250)) return {'t': 'unmortgage', 'sq': sq};
    }
    final builds = legalFor(seat, 'build');
    if (builds.isEmpty) return null;
    double score(int sq) {
      final d = mBoard[sq];
      final h = houses[sq];
      final gain = d.rents[h + 1] - (h == 0 ? d.rents[0] * 2 : d.rents[h]);
      return gain / d.houseCost + (h < 3 ? 2 : 0);
    }

    builds.sort((a, b) => score(b).compareTo(score(a)));
    for (final sq in builds) {
      if (cash[seat] - mBoard[sq].houseCost >= reserve) return {'t': 'build', 'sq': sq};
    }
    return null;
  }

  Map<String, dynamic> _botAuction(int seat) {
    final d = mBoard[aucSq];
    if (botLevel <= 0) {
      final lim = (d.price * (0.5 + rng.nextDouble() * 0.6)).floor();
      final bid = aucHigh + 10;
      return bid <= lim && bid <= cash[seat] - 40 ? {'t': 'bid', 'amount': bid} : {'t': 'pass'};
    }
    final blockMult = botLevel >= 2 ? 1.5 : 1.3;
    final baseMult = botLevel >= 2 ? 1.0 : 0.9;
    final limit = (valueTo(seat, aucSq) * (active.any((o) => o != seat && _completes(o, aucSq)) ? blockMult : baseMult)).floor();
    final step = d.price >= 200 ? 20 : 10;
    final bid = aucHigh + step;
    final cap = cash[seat] - (_completes(seat, aucSq) ? 20 : 80);
    if (bid <= limit && bid <= cap && bid <= cash[seat]) return {'t': 'bid', 'amount': bid};
    if (aucHigh + 10 <= limit && aucHigh + 10 <= cap) return {'t': 'bid', 'amount': aucHigh + 10};
    return {'t': 'pass'};
  }

  Map<String, dynamic> _botDebt(int seat) {
    final d = curDebt!;
    if (cash[seat] >= d.amount) return {'t': 'pay'};
    if (cash[seat] + liquidValue(seat) < d.amount) return {'t': 'bankrupt'};
    // mortgage non-monopoly, cheapest-rent squares first
    final morts = legalFor(seat, 'mortgage');
    morts.sort((a, b) {
      int score(int i) {
        final s = mBoard[i];
        final mono = s.type == SqType.street && hasMonopoly(seat, s.group) ? 1000 : 0;
        return mono + s.price;
      }

      return score(a).compareTo(score(b));
    });
    for (final sq in morts) {
      final s = mBoard[sq];
      if (!(s.type == SqType.street && hasMonopoly(seat, s.group))) return {'t': 'mortgage', 'sq': sq};
    }
    final sells = legalFor(seat, 'sell');
    if (sells.isNotEmpty) {
      sells.sort((a, b) => mBoard[a].houseCost.compareTo(mBoard[b].houseCost));
      return {'t': 'sell', 'sq': sells.first};
    }
    if (morts.isNotEmpty) return {'t': 'mortgage', 'sq': morts.first};
    return {'t': 'bankrupt'};
  }

  Map<String, dynamic> _botTradeAnswer(int seat) {
    final o = trade!;
    final from = o['from'] as int;
    final give = (o['give'] as List).cast<int>(), get = (o['get'] as List).cast<int>();
    var gain = (o['giveCash'] as int) - (o['getCash'] as int) + 0.0;
    for (final i in give) {
      gain += valueTo(seat, i);
    }
    for (final i in get) {
      gain -= valueTo(seat, i);
      // handing over the last piece of someone's set is dangerous
      if (_completes(from, i)) gain -= mBoard[i].price * 0.5;
    }
    if (cash[seat] - (o['getCash'] as int) < 50) gain -= 1000;
    return {'t': gain >= 0 ? 'accept' : 'reject'};
  }

  Map<String, dynamic>? _botProposeTrade(int seat) {
    if (tradesThisTurn >= 5) return null;
    for (var gi = 0; gi < 8; gi++) {
      final grp = mGroups[gi];
      final missing = [for (final i in grp) if (owner[i] != seat) i];
      if (missing.length != 1) continue;
      final sq = missing.first;
      final o = owner[sq];
      if (o < 0 || bankrupt[o] || groupHasHouses(gi)) continue;
      final d = mBoard[sq];
      final targetVal = valueTo(o, sq) + d.price * 0.5;
      final offerCash = ((targetVal + 10) / 10).ceil() * 10;
      if (cash[seat] - offerCash < _reserve) continue;
      final offer = {'from': seat, 'to': o, 'give': <int>[], 'get': [sq], 'giveCash': offerCash, 'getCash': 0};
      if (botDeclined.contains(_tradeKey(offer))) continue;
      if (tradeError(offer) != null) continue;
      return {'t': 'trade', 'to': o, 'give': <int>[], 'get': [sq], 'giveCash': offerCash, 'getCash': 0};
    }
    return null;
  }
}
