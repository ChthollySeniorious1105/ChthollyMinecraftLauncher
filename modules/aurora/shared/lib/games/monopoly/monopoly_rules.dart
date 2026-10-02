part of 'monopoly.dart';

extension MonopolyRules on MonopolyGame {
  // ------------------------------------------------------------ rent
  bool hasMonopoly(int s, int group) => s >= 0 && mGroups[group].every((i) => owner[i] == s);

  int stationsOwned(int s) => mStations.where((i) => owner[i] == s).length;

  int rentFor(int sq, {int diceSum = 7, int stationMult = 1, int utilMult = 0}) {
    final o = owner[sq];
    if (o < 0 || mortgaged[sq]) return 0;
    final d = mBoard[sq];
    switch (d.type) {
      case SqType.street:
        final h = houses[sq];
        if (h > 0) return d.rents[h];
        return d.rents[0] * (hasMonopoly(o, d.group) ? 2 : 1);
      case SqType.station:
        final n = stationsOwned(o);
        return (25 << (n - 1)) * stationMult;
      case SqType.utility:
        final n = mUtilities.where((i) => owner[i] == o).length;
        final m = utilMult > 0 ? utilMult : (n >= 2 ? 10 : 4);
        return diceSum * m;
      default:
        return 0;
    }
  }

  // ------------------------------------------------------------ management
  bool canManage(int seat) {
    if (over || bankrupt[seat]) return false;
    if (phase == 'debt') return curDebt?.from == seat;
    return seat == turn && (phase == 'roll' || phase == 'end' || phase == 'buy');
  }

  bool groupHasHouses(int group) => group >= 0 && mGroups[group].any((i) => houses[i] > 0);

  String? manageError(int seat, String kind, int sq) {
    if (!canManage(seat)) return '现在不能管理地产';
    final d = mBoard[sq];
    if (!d.ownable || owner[sq] != seat) return '这不是你的地产';
    switch (kind) {
      case 'build':
        if (phase == 'debt') return '还债期间不能建房';
        if (d.type != SqType.street) return '只能在街道上建房';
        if (!hasMonopoly(seat, d.group)) return '需要拥有整组同色地产才能建房';
        final grp = mGroups[d.group];
        if (grp.any((i) => mortgaged[i])) return '同组有地产被抵押，不能建房';
        final h = houses[sq];
        if (h >= 5) return '已建酒店';
        final minH = grp.map((i) => houses[i]).reduce((a, b) => a < b ? a : b);
        if (h > minH) return '必须平均建房：请先在同组其他地产上建房';
        if (h == 4 ? hotelsLeft <= 0 : housesLeft <= 0) return h == 4 ? '银行酒店已用完' : '银行房屋已用完';
        if (cash[seat] < d.houseCost) return '资金不足（需要 ¥${d.houseCost}）';
        return null;
      case 'sell':
        final h = houses[sq];
        if (h <= 0) return '这里没有房屋';
        final grp = mGroups[d.group];
        final maxH = grp.map((i) => houses[i]).reduce((a, b) => a > b ? a : b);
        if (h < maxH) return '必须平均拆房：请先拆同组房屋更多的地产';
        if (h == 5 && housesLeft < 4) return '银行房屋不足，无法把酒店拆回 4 栋房屋';
        return null;
      case 'mortgage':
        if (mortgaged[sq]) return '已经抵押';
        if (groupHasHouses(d.group)) return '同组有房屋，需先拆除';
        return null;
      case 'unmortgage':
        if (phase == 'debt') return '还债期间不能赎回';
        if (!mortgaged[sq]) return '没有抵押';
        if (cash[seat] < d.unmortgageCost) return '资金不足（需要 ¥${d.unmortgageCost}）';
        return null;
    }
    return '未知操作';
  }

  void _manage(int seat, String kind, int sq) {
    final d = mBoard[sq];
    switch (kind) {
      case 'build':
        if (houses[sq] == 4) {
          hotelsLeft--;
          housesLeft += 4;
        } else {
          housesLeft--;
        }
        houses[sq]++;
        cash[seat] -= d.houseCost;
        _ev('${name(seat)} 在 ${d.name} ${houses[sq] == 5 ? '建造酒店' : '建造第 ${houses[sq]} 栋房屋'}');
      case 'sell':
        if (houses[sq] == 5) {
          hotelsLeft++;
          housesLeft -= 4;
        } else {
          housesLeft++;
        }
        houses[sq]--;
        cash[seat] += d.houseCost ~/ 2;
        _ev('${name(seat)} 拆除 ${d.name} 的建筑，回收 ¥${d.houseCost ~/ 2}');
      case 'mortgage':
        mortgaged[sq] = true;
        cash[seat] += d.mortgage;
        _ev('${name(seat)} 抵押 ${d.name}，获得 ¥${d.mortgage}');
      case 'unmortgage':
        mortgaged[sq] = false;
        cash[seat] -= d.unmortgageCost;
        _ev('${name(seat)} 赎回 ${d.name}，支付 ¥${d.unmortgageCost}');
    }
  }

  /// Squares on which [seat] may currently perform [kind].
  List<int> legalFor(int seat, String kind) =>
      [for (var i = 0; i < 40; i++) if (owner[i] == seat && manageError(seat, kind, i) == null) i];

  /// Cash [s] could raise by selling all buildings and mortgaging everything.
  int liquidValue(int s) {
    var v = 0;
    for (var i = 0; i < 40; i++) {
      if (owner[i] != s) continue;
      final d = mBoard[i];
      v += houses[i] * (d.houseCost ~/ 2);
      if (!mortgaged[i]) v += d.mortgage;
    }
    return v;
  }

  // ------------------------------------------------------------ auction
  List<int> get aucWaiting => phase != 'auction'
      ? const []
      : [
          for (final s in aucActive)
            if (s != aucLeader && !aucBids.containsKey(s) && cash[s] >= aucHigh + 10) s
        ];

  void _startAuction(int sq) {
    aucSq = sq;
    aucHigh = 0;
    aucLeader = -1;
    aucRound = 1;
    aucBids = {};
    aucLast = {};
    aucActive = [for (final s in active) if (cash[s] >= 10) s];
    phase = 'auction';
    _ev('${mBoard[sq].name} 开始拍卖', log: true);
    if (aucWaiting.isEmpty) _aucResolve();
  }

  void _aucResolve() {
    // one sealed round complete
    var best = aucHigh, bestSeat = -1;
    final stay = <int>[];
    aucLast = {};
    // iterate in turn order starting from the current player so ties favour earlier seats
    for (var k = 0; k < players; k++) {
      final s = (turn + k) % players;
      if (!aucActive.contains(s) || s == aucLeader) continue;
      final b = aucBids[s] ?? 0;
      aucLast['$s'] = b;
      if (b > aucHigh) {
        stay.add(s);
        if (b > best) {
          best = b;
          bestSeat = s;
        }
      }
    }
    aucBids = {};
    if (bestSeat >= 0) {
      if (aucLeader >= 0) stay.add(aucLeader);
      aucHigh = best;
      aucLeader = bestSeat;
      aucActive = stay;
      aucRound++;
      if (aucWaiting.isNotEmpty) return;
    }
    // nobody outbid the leader: auction over
    final sq = aucSq;
    if (aucLeader >= 0) {
      cash[aucLeader] -= aucHigh;
      owner[sq] = aucLeader;
      _ev('${name(aucLeader)} 以 ¥$aucHigh 拍得 ${mBoard[sq].name}', log: true);
    } else {
      _ev('${mBoard[sq].name} 无人出价，流拍');
    }
    aucSq = -1;
    aucLeader = -1;
    aucHigh = 0;
    aucActive = [];
    phase = 'roll'; // placeholder; _resume/_finishStep sets the proper phase
    _resume();
  }

  // ------------------------------------------------------------ trade
  String _tradeKey(Map<String, dynamic> o) =>
      '${o['from']}>${o['to']}:${o['give']}/${o['get']}/${o['giveCash']}/${o['getCash']}';

  String? tradeError(Map<String, dynamic> o) {
    final from = o['from'] as int, to = o['to'] as int;
    final give = (o['give'] as List).cast<int>(), get = (o['get'] as List).cast<int>();
    final giveCash = o['giveCash'] as int, getCash = o['getCash'] as int;
    if (to < 0 || to >= players || to == from || bankrupt[to]) return '无效的交易对象';
    if (giveCash < 0 || getCash < 0) return '金额无效';
    if (give.isEmpty && get.isEmpty && giveCash == 0 && getCash == 0) return '交易内容为空';
    if (give.isEmpty && get.isEmpty) return '交易至少要包含一处地产';
    if (give.toSet().length != give.length || get.toSet().length != get.length) return '地产重复';
    for (final i in give) {
      if (i < 0 || i >= 40 || owner[i] != from) return '你并不拥有所列地产';
      if (groupHasHouses(mBoard[i].group)) return '${mBoard[i].name} 所在色组有房屋，需先拆除';
    }
    for (final i in get) {
      if (i < 0 || i >= 40 || owner[i] != to) return '对方并不拥有所列地产';
      if (groupHasHouses(mBoard[i].group)) return '${mBoard[i].name} 所在色组有房屋，需先拆除';
    }
    if (cash[from] < giveCash) return '你的现金不足';
    if (cash[to] < getCash) return '对方现金不足';
    return null;
  }

  void _applyTrade(Map<String, dynamic> o) {
    final from = o['from'] as int, to = o['to'] as int;
    for (final i in (o['give'] as List).cast<int>()) {
      owner[i] = to;
    }
    for (final i in (o['get'] as List).cast<int>()) {
      owner[i] = from;
    }
    final gc = o['giveCash'] as int, tc = o['getCash'] as int;
    cash[from] += tc - gc;
    cash[to] += gc - tc;
  }

  // ------------------------------------------------------------ bankruptcy
  void _declareBankrupt(int s, int creditor) {
    _liquidate(s, creditor);
    if (trade != null && (trade!['from'] == s || trade!['to'] == s)) trade = null;
    if (active.length <= 1) {
      _finishGame();
      return;
    }
    _resume();
  }

  /// Hands all of [s]'s assets to [creditor] (or the bank when < 0) and marks
  /// the seat bankrupt. Does not advance the game.
  void _liquidate(int s, int creditor, {bool resigned = false}) {
    final toPlayer = creditor >= 0 && !bankrupt[creditor];
    var raised = 0;
    for (var i = 0; i < 40; i++) {
      if (owner[i] != s) continue;
      final d = mBoard[i];
      if (houses[i] > 0) {
        raised += (houses[i] * d.houseCost) ~/ 2;
        if (houses[i] == 5) {
          hotelsLeft++;
        } else {
          housesLeft += houses[i];
        }
        houses[i] = 0;
      }
      if (toPlayer) {
        owner[i] = creditor;
      } else {
        owner[i] = -1;
        mortgaged[i] = false;
      }
    }
    final total = cash[s] + raised;
    cash[s] = 0;
    if (toPlayer) {
      cash[creditor] += total;
      jailCards[creditor].addAll(jailCards[s]);
    } else {
      for (final c in jailCards[s]) {
        _returnJailCard(c);
      }
    }
    jailCards[s] = [];
    bankrupt[s] = true;
    inJail[s] = false;
    (resigned ? resignOrder : bankruptOrder).add(s);
    debts.removeWhere((d) => d.from == s);
    _ev(resigned ? '${name(s)} 认输退出，资产归还银行' : '${name(s)} 宣告破产！资产${toPlayer ? '归 ${name(creditor)} 所有' : '归还银行'}',
        log: !resigned);
  }

  /// 认输: the seat goes bankrupt to the bank and is ranked last.
  void _resignImpl(int seat) {
    if (over) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || bankrupt[seat]) throw GameError('你已出局');
    host.log('${name(seat)} 认输');
    final ph = phase;
    final wasTurn = seat == turn;
    _liquidate(seat, -1, resigned: true);
    if (active.length <= 1) {
      _finishGame();
      return;
    }
    switch (ph) {
      case 'debt':
        _resume();
      case 'auction':
        aucActive.remove(seat);
        aucBids.remove(seat);
        if (aucLeader == seat) {
          // the leading bid is void: restart the auction for the others
          aucLeader = -1;
          aucHigh = 0;
          aucBids = {};
          aucLast = {};
          aucRound = 1;
          aucActive = [for (final s in active) if (cash[s] >= 10) s];
        }
        if (aucWaiting.isEmpty) _aucResolve();
      case 'trade':
        final o = trade;
        if (o != null && (o['from'] == seat || o['to'] == seat)) {
          trade = null;
          phase = tradeReturn;
        }
        if (wasTurn) _nextTurn();
      case 'buy':
        if (wasTurn) {
          buySq = -1;
          _cont = null;
          _nextTurn();
        }
      default:
        if (wasTurn) {
          _cont = null;
          _nextTurn();
        }
    }
  }

  /// Final order: survivors by net worth, then bankrupt players (later
  /// bankruptcy ranks better), then resigned players (later resign better).
  List<int> get finalOrder {
    final alive = active..sort((a, b) => worth(b).compareTo(worth(a)));
    return [...alive, ...bankruptOrder.reversed, ...resignOrder.reversed];
  }

  List<int> get placingsImpl {
    final order = finalOrder;
    final r = List.filled(players, players);
    for (var k = 0; k < order.length; k++) {
      final s = order[k];
      if (!bankrupt[s]) {
        r[s] = 1 + [for (final o in active) if (worth(o) > worth(s)) o].length;
      } else {
        r[s] = k + 1;
      }
    }
    return r;
  }

  // ------------------------------------------------------------ view
  Map<String, dynamic> _viewImpl(int seat) {
    final me = seat >= 0 && seat < players ? seat : -1;
    final d = curDebt;
    return {
      'phase': phase,
      'turn': turn,
      'round': round,
      'roundLimit': roundLimit,
      'timed': endRounds > 0,
      'dice': dice,
      'rolls': rolls,
      'doubles': doubles,
      'again': again,
      'buySq': buySq,
      'owner': owner,
      'houses': houses,
      'mortgaged': mortgaged,
      'housesLeft': housesLeft,
      'hotelsLeft': hotelsLeft,
      'potOn': potOn,
      'pot': pot,
      'auctionOn': auctionOn,
      'players': [
        for (var s = 0; s < players; s++)
          {
            'cash': cash[s],
            'pos': pos[s],
            'jail': inJail[s],
            'jailTurns': jailTurns[s],
            'cards': jailCards[s].length,
            'bankrupt': bankrupt[s],
            'worth': worth(s),
          }
      ],
      'auction': phase == 'auction'
          ? {
              'sq': aucSq,
              'high': aucHigh,
              'leader': aucLeader,
              'round': aucRound,
              'active': aucActive,
              'waiting': aucWaiting,
              'done': [for (final s in aucBids.keys) s],
              'last': aucLast,
              if (me >= 0 && aucBids.containsKey(me)) 'myBid': aucBids[me],
            }
          : null,
      'debt': d == null
          ? null
          : {'from': d.from, 'to': d.to, 'amount': d.amount, 'why': d.why, 'liquid': liquidValue(d.from)},
      'trade': trade,
      'tradesLeft': 5 - tradesThisTurn,
      'card': lastCard,
      'events': events,
      'winner': winner,
      'result': result,
      'legal': me < 0
          ? null
          : {
              'build': legalFor(me, 'build'),
              'sell': legalFor(me, 'sell'),
              'mortgage': legalFor(me, 'mortgage'),
              'unmortgage': legalFor(me, 'unmortgage'),
            },
    };
  }
}
