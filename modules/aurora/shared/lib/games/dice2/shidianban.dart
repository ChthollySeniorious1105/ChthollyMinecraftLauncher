import '../../src/engine.dart';
import 'util.dart';

/// 十点半 hand kinds, ordered by strength.
enum SdbKind { bust, normal, tenHalf, fiveSmall, tianWang, renWuXiao }

const sdbKindNames = {
  SdbKind.bust: '爆牌',
  SdbKind.normal: '平牌',
  SdbKind.tenHalf: '十点半',
  SdbKind.fiveSmall: '五小',
  SdbKind.tianWang: '天王',
  SdbKind.renWuXiao: '人五小',
};

/// Card value in half points: A=2 (1 point), 2..10 face, J/Q/K = 1 (0.5 point).
int sdbHalfValue(String card) {
  if (card.length < 2) return 0;
  switch (card[0]) {
    case 'A':
      return 2;
    case 'T':
      return 20;
    case 'J':
    case 'Q':
    case 'K':
      return 1;
  }
  final n = int.tryParse(card[0]) ?? 0;
  return n * 2;
}

bool sdbIsFace(String card) => card.isNotEmpty && 'JQK'.contains(card[0]);

/// Total in half points.
int sdbTotalHalf(List<String> cards) => cards.fold(0, (a, c) => a + sdbHalfValue(c));

String sdbPointsText(int half) => half.isEven ? '${half ~/ 2}' : '${half ~/ 2}.5';

SdbKind sdbKind(List<String> cards) {
  final t = sdbTotalHalf(cards);
  if (t > 21) return SdbKind.bust;
  if (cards.length >= 5) {
    if (cards.every(sdbIsFace)) return SdbKind.renWuXiao;
    if (t == 21) return SdbKind.tianWang;
    return SdbKind.fiveSmall;
  }
  if (t == 21) return SdbKind.tenHalf;
  return SdbKind.normal;
}

/// Payout multiplier of a winning hand.
int sdbMultiplier(SdbKind k, String payout) {
  if (payout == 'flat') return 1;
  if (payout == 'high') {
    return const {
          SdbKind.normal: 1,
          SdbKind.tenHalf: 3,
          SdbKind.fiveSmall: 5,
          SdbKind.tianWang: 6,
          SdbKind.renWuXiao: 8,
        }[k] ??
        1;
  }
  return const {
        SdbKind.normal: 1,
        SdbKind.tenHalf: 2,
        SdbKind.fiveSmall: 3,
        SdbKind.tianWang: 4,
        SdbKind.renWuXiao: 5,
      }[k] ??
      1;
}

/// Settle one player hand against the banker hand.
/// Returns chips the PLAYER gains (negative = pays banker).
/// Rules: player bust always loses its bet (×1); banker bust pays non-bust players;
/// otherwise higher kind wins, same "平牌" compares points; ties go to the banker.
int sdbSettle(List<String> player, List<String> banker, int bet, String payout) {
  final pk = sdbKind(player), bk = sdbKind(banker);
  if (pk == SdbKind.bust) return -bet;
  if (bk == SdbKind.bust) return bet * sdbMultiplier(pk, payout);
  if (pk.index != bk.index) {
    return pk.index > bk.index ? bet * sdbMultiplier(pk, payout) : -bet * sdbMultiplier(bk, payout);
  }
  if (pk == SdbKind.normal) {
    final pt = sdbTotalHalf(player), bt = sdbTotalHalf(banker);
    if (pt > bt) return bet;
  }
  return -bet * sdbMultiplier(bk, payout);
}

const sdbBets = [10, 20, 50, 100];

class ShiDianBan extends GameEngine {
  ShiDianBan(super.setup);

  late final String bankerMode = setup.opt<String>('banker', 'rotate');
  late final String payout = setup.opt<String>('payout', 'standard');
  late final int rounds = setup.opt<int>('rounds', 10);
  late final D2Log log = D2Log(() => host);

  String phase = 'grab'; // grab / bet / play / result / over
  int round = 0;
  int banker = 0;
  int turn = -1;
  List<int> chips = [];
  List<int> bets = [];
  List<int?> grabs = []; // null undecided, 1 grab, 0 no
  List<List<String>> hands = [];
  List<bool> done = [];
  List<String> deck = [];
  List<int> deltas = [];
  Map<String, dynamic>? result;

  @override
  void start() {
    chips = List.filled(players, 1000);
    banker = rng.nextInt(players);
    _newRound();
  }

  void _newRound() {
    round++;
    result = null;
    bets = List.filled(players, 0);
    grabs = List<int?>.filled(players, null);
    hands = [for (var i = 0; i < players; i++) <String>[]];
    done = List.filled(players, false);
    deltas = List.filled(players, 0);
    deck = shuffled([
      for (final r in 'A23456789TJQK'.split(''))
        for (final s in 'SHDC'.split('')) '$r$s'
    ], rng);
    turn = -1;
    if (bankerMode == 'grab') {
      phase = 'grab';
      log.add('第 $round 局：抢庄');
    } else {
      if (round > 1) banker = (banker + 1) % players;
      _deal();
    }
  }

  void _deal() {
    for (var s = 0; s < players; s++) {
      hands[s].add(deck.removeLast());
    }
    phase = 'bet';
    log.add('第 $round 局：${name(banker)} 坐庄，闲家请下注');
  }

  List<int> _order() => [for (var i = 1; i < players; i++) (banker + i) % players];

  void _nextTurn() {
    for (final s in _order()) {
      if (!done[s]) {
        turn = s;
        return;
      }
    }
    // all players done -> banker, unless every player busted
    if (!done[banker]) {
      final allBust = _order().every((s) => sdbKind(hands[s]) == SdbKind.bust);
      if (!allBust) {
        turn = banker;
        return;
      }
      done[banker] = true;
    }
    _settle();
  }

  void _settle() {
    turn = -1;
    phase = 'result';
    deltas = List.filled(players, 0);
    final lines = <String>[];
    for (final s in _order()) {
      final d = sdbSettle(hands[s], hands[banker], bets[s], payout);
      deltas[s] += d;
      deltas[banker] -= d;
      lines.add('${name(s)} ${d >= 0 ? '+' : ''}$d');
    }
    for (var s = 0; s < players; s++) {
      chips[s] += deltas[s];
    }
    result = {
      'deltas': List.of(deltas),
      'kinds': [for (final h in hands) sdbKindNames[sdbKind(h)]],
    };
    log.add('结算（庄 ${name(banker)} ${sdbKindNames[sdbKind(hands[banker])]} ${sdbPointsText(sdbTotalHalf(hands[banker]))}）：${lines.join('，')}');
    host.schedule(3500, () {
      if (round >= rounds) {
        phase = 'over';
        final best = chips.reduce((a, b) => a > b ? a : b);
        log.add('游戏结束，${[for (var s = 0; s < players; s++) if (chips[s] == best) name(s)].join('、')} 筹码最多');
      } else {
        _newRound();
      }
    });
  }

  void _drawFor(int s) {
    hands[s].add(deck.removeLast());
    final k = sdbKind(hands[s]);
    if (k == SdbKind.bust) {
      done[s] = true;
      log.add('${name(s)} 要牌…爆了！（${sdbPointsText(sdbTotalHalf(hands[s]))} 点）');
    } else if (hands[s].length >= 5 || k == SdbKind.tenHalf) {
      done[s] = true;
      log.add('${name(s)} 要牌，${sdbKindNames[k]}！');
    } else {
      log.add('${name(s)} 要牌', chat: false);
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在游戏中');
    final type = asStr(a['type']);
    switch (phase) {
      case 'grab':
        if (type != 'grab') throw GameError('现在是抢庄阶段');
        if (grabs[seat] != null) throw GameError('你已经选择过了');
        grabs[seat] = asBool(a['grab']) ? 1 : 0;
        log.add('${name(seat)} ${grabs[seat] == 1 ? '抢庄' : '不抢'}', chat: false);
        if (grabs.every((g) => g != null)) {
          final want = [for (var s = 0; s < players; s++) if (grabs[s] == 1) s];
          final pool = want.isEmpty ? [for (var s = 0; s < players; s++) s] : want;
          banker = pool[rng.nextInt(pool.length)];
          _deal();
        }
        return;
      case 'bet':
        if (type != 'bet') throw GameError('现在是下注阶段');
        if (seat == banker) throw GameError('庄家不用下注');
        if (bets[seat] > 0) throw GameError('你已经下注了');
        final amt = asInt(a['amount']);
        if (!sdbBets.contains(amt)) throw GameError('无效的下注额');
        bets[seat] = amt;
        log.add('${name(seat)} 下注 $amt', chat: false);
        if (_order().every((s) => bets[s] > 0)) {
          phase = 'play';
          _nextTurn();
        }
        return;
      case 'play':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'hit') {
          _drawFor(seat);
        } else if (type == 'stand') {
          done[seat] = true;
          log.add('${name(seat)} 停牌', chat: false);
        } else {
          throw GameError('未知操作');
        }
        if (done[seat]) _nextTurn();
        return;
      default:
        throw GameError('请稍候');
    }
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'grab':
        return [for (var s = 0; s < players; s++) if (grabs[s] == null) s];
      case 'bet':
        return [for (final s in _order()) if (bets[s] == 0) s];
      case 'play':
        return turn >= 0 ? [turn] : [];
    }
    return [];
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings => isOver ? rankByScore(chips) : null;

  bool _revealed(int owner, int viewer) =>
      owner == viewer || phase == 'result' || phase == 'over' || sdbKind(hands[owner]) == SdbKind.bust;

  @override
  Map<String, dynamic> view(int seat) {
    final shown = <List<String>>[];
    final pts = <String?>[];
    for (var s = 0; s < players; s++) {
      final open = _revealed(s, seat);
      final h = [for (var i = 0; i < hands[s].length; i++) (i == 0 && !open) ? '' : hands[s][i]];
      shown.add(h);
      final visible = [for (final c in h) if (c.isNotEmpty) c];
      pts.add(open ? sdbPointsText(sdbTotalHalf(hands[s])) : (visible.isEmpty ? null : '? + ${sdbPointsText(sdbTotalHalf(visible))}'));
    }
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'banker': banker,
      'bankerMode': bankerMode,
      'payout': payout,
      'turn': turn,
      'chips': chips,
      'bets': bets,
      'grabs': grabs,
      'hands': shown,
      'points': pts,
      'kinds': [
        for (var s = 0; s < players; s++) _revealed(s, seat) && hands[s].isNotEmpty ? sdbKindNames[sdbKind(hands[s])] : null
      ],
      'done': done,
      'betChoices': sdbBets,
      'result': result,
      'log': log.tail(),
    };
  }

  // ---------------- bot (only uses own cards + face-up cards) ----------------
  List<String> _unseen(int seat) {
    final seen = <String>{...hands[seat]};
    for (var s = 0; s < players; s++) {
      if (s == seat) continue;
      for (var i = 0; i < hands[s].length; i++) {
        if (i > 0 || _revealed(s, seat)) seen.add(hands[s][i]);
      }
    }
    return [
      for (final r in 'A23456789TJQK'.split(''))
        for (final su in 'SHDC'.split(''))
          if (!seen.contains('$r$su')) '$r$su'
    ];
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'grab':
        return {'type': 'grab', 'grab': rng.nextInt(3) == 0};
      case 'bet':
        if (botLevel <= 0) return {'type': 'bet', 'amount': sdbBets[rng.nextInt(sdbBets.length)]};
        final c = hands[seat].isEmpty ? 0 : sdbHalfValue(hands[seat][0]);
        if (botLevel >= 2) {
          // 困难: face cards (can still make 十点半/人五小) and 9/10 are strong starts
          final amt = c == 1 ? 100 : (c >= 18 ? 50 : (c >= 14 ? 20 : 10));
          return {'type': 'bet', 'amount': amt};
        }
        final amt = c == 1 || c >= 16 ? 50 : (c >= 12 ? 20 : 10);
        return {'type': 'bet', 'amount': amt};
      case 'play':
        if (seat != turn) return null;
        final h = hands[seat];
        final t = sdbTotalHalf(h);
        final unseen = _unseen(seat);
        final safe = unseen.where((c) => t + sdbHalfValue(c) <= 21).length / (unseen.isEmpty ? 1 : unseen.length);
        if (botLevel <= 0) {
          // 简单: ignores the deck and others, fixed target with random slips
          if (rng.nextInt(4) == 0) return {'type': rng.nextBool() ? 'hit' : 'stand'};
          return {'type': t < 12 ? 'hit' : 'stand'};
        }
        if (botLevel >= 2) return {'type': _hardHit(seat, t, safe, unseen) ? 'hit' : 'stand'};
        if (h.length == 4) return {'type': safe > 0.55 ? 'hit' : 'stand'};
        if (seat == banker) {
          // banker: look at players still standing and their visible cards
          final live = [for (final s in _order()) if (sdbKind(hands[s]) != SdbKind.bust) s];
          var threat = 0;
          for (final s in live) {
            final vis = sdbTotalHalf(hands[s].sublist(1));
            if (vis >= t) threat++;
          }
          final need = threat * 2 > live.length ? 17 : 14;
          return {'type': t < need && safe > 0.35 ? 'hit' : 'stand'};
        }
        return {'type': t < 12 || (t < 15 && safe > 0.6) ? 'hit' : 'stand'};
    }
    return null;
  }

  /// 困难: one-card lookahead. Compares the estimated win chance of standing
  /// on [t] with the average after one more card (players: against the
  /// banker's likely final total; banker: against the live players' visible
  /// cards). Always tries for 五小 when 4 small cards are safe enough.
  bool _hardHit(int seat, int t, double safe, List<String> unseen) {
    final h = hands[seat];
    if (unseen.isEmpty) return false;
    if (h.length == 4) return safe > 0.5;
    double winStand(int total) {
      if (total > 21) return 0;
      if (seat == banker) {
        final live = [for (final s in _order()) if (sdbKind(hands[s]) != SdbKind.bust) s];
        if (live.isEmpty) return 1;
        var w = 0.0;
        for (final s in live) {
          // hidden card of a player averages ~5 points (10 halves)
          final est = sdbTotalHalf(hands[s].sublist(1)) + 10;
          w += total >= est.clamp(0, 21) ? 1 : (total + 4 >= est ? 0.5 : 0.1);
        }
        return w / live.length;
      }
      // player vs banker: banker usually ends on 7..10.5 (14..21 halves) or busts
      if (total >= 21) return 0.9;
      if (total <= 12) return 0.3;
      return 0.3 + (total - 12) * 0.07;
    }

    final stand = winStand(t);
    var hit = 0.0;
    for (final c in unseen) {
      final nt = t + sdbHalfValue(c);
      hit += nt > 21 ? 0 : (h.length + 1 >= 5 ? 1.0 : winStand(nt));
    }
    hit /= unseen.length;
    return hit > stand;
  }
}
