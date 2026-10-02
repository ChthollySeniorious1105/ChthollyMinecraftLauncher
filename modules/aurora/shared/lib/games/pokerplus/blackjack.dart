import 'dart:math';

import '../../src/engine.dart';
import 'cards.dart';

/// Best blackjack total of [cards] and whether it is soft (an ace counted as 11).
(int, bool) bjTotal(List<String> cards) {
  var t = 0, aces = 0;
  for (final c in cards) {
    final r = cardRank(c);
    if (r == 14) {
      aces++;
      t += 1;
    } else {
      t += r >= 10 ? 10 : r;
    }
  }
  if (aces > 0 && t + 10 <= 21) return (t + 10, true);
  return (t, false);
}

bool isBlackjack(List<String> cards) => cards.length == 2 && bjTotal(cards).$1 == 21;

/// Blackjack card value 2..11 (ace = 11) for strategy lookups.
int bjValue(String c) {
  final r = cardRank(c);
  return r == 14 ? 11 : (r >= 10 ? 10 : r);
}

class BjHand {
  final List<String> cards;
  int bet;
  bool done = false;
  bool doubled = false;
  final bool fromSplit;
  final bool splitAces;
  String outcome = ''; // win / lose / push / bj / bust
  int payout = 0; // chips returned (incl. stake)
  BjHand(this.cards, this.bet, {this.fromSplit = false, this.splitAces = false});

  int get total => bjTotal(cards).$1;
  bool get soft => bjTotal(cards).$2;
  bool get bust => total > 21;
  bool get natural => !fromSplit && isBlackjack(cards);

  Map<String, dynamic> toJson() => {
        'cards': cards,
        'bet': bet,
        'total': total,
        'soft': soft,
        'done': done,
        'doubled': doubled,
        'outcome': outcome,
        'payout': payout,
      };
}

/// Payout (chips returned incl. stake) of a finished player hand vs the dealer.
/// Returns (outcome, payout).
(String, int) settleHand(BjHand h, List<String> dealer) {
  final dealerBj = isBlackjack(dealer);
  if (h.bust) return ('bust', 0);
  if (h.natural && !dealerBj) return ('bj', h.bet + h.bet * 3 ~/ 2);
  if (dealerBj) return h.natural ? ('push', h.bet) : ('lose', 0);
  final d = bjTotal(dealer).$1;
  if (d > 21 || h.total > d) return ('win', h.bet * 2);
  if (h.total == d) return ('push', h.bet);
  return ('lose', 0);
}

/// 21点：多名玩家对抗电脑庄家。
class Blackjack extends GameEngine {
  Blackjack(super.setup);

  static const int startChips = 1000;
  static const List<int> betChoices = [10, 25, 50, 100, 200, 500];

  late bool hitSoft17;
  late int roundsLimit; // 0 = until broke (cap 50)
  int round = 0;
  late List<int> chips;
  late List<bool> broke;

  List<String> shoe = [];
  int shoeSize = 0;
  List<String> dealer = [];
  bool dealerHidden = true;
  List<List<BjHand>> hands = [];
  late List<int> betOf; // this round's base bet, 0 = not yet
  late List<int> insurance; // -1 undecided, 0 declined, >0 amount
  late List<int> active; // index of hand being played
  String phase = 'bet'; // bet | insurance | play | result | over
  int turn = -1;
  List<int> results = [];

  int get cap => roundsLimit == 0 ? 50 : roundsLimit;

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 700;

  /// Final ranking by chips (ties share).
  @override
  List<int>? get placings => isOver ? rankByScore(chips) : null;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'bet':
        return [for (var s = 0; s < players; s++) if (!broke[s] && betOf[s] == 0) s];
      case 'insurance':
        return [for (var s = 0; s < players; s++) if (_seated(s) && insurance[s] < 0) s];
      case 'play':
        return turn >= 0 ? [turn] : const [];
      default:
        return const [];
    }
  }

  bool _seated(int s) => !broke[s] && betOf[s] > 0;

  @override
  void start() {
    hitSoft17 = setup.opt<bool>('h17', false);
    roundsLimit = setup.opt<int>('rounds', 10);
    chips = List.filled(players, startChips);
    broke = List.filled(players, false);
    _reshuffle();
    host.log('21点开始：每人 $startChips 筹码，${roundsLimit == 0 ? "直到破产" : "共 $roundsLimit 局"}，庄家软17${hitSoft17 ? "要牌" : "停牌"}');
    _newRound();
  }

  /// Public cards of finished rounds since the last shuffle (for card counting).
  final List<String> _seen = [];

  void _reshuffle() {
    _seen.clear();
    shoe = shuffled([for (var d = 0; d < 6; d++) ...fullDeck()], rng);
    shoeSize = shoe.length;
    host.log('重新洗牌（6副牌）');
  }

  String _draw() {
    if (shoe.isEmpty) _reshuffle();
    return shoe.removeLast();
  }

  void _newRound() {
    round++;
    _seen
      ..addAll(dealer)
      ..addAll([for (final hs in hands) for (final h in hs) ...h.cards]);
    if (shoe.length < shoeSize * 0.25) _reshuffle();
    phase = 'bet';
    dealer = [];
    dealerHidden = true;
    hands = [for (var s = 0; s < players; s++) <BjHand>[]];
    betOf = List.filled(players, 0);
    insurance = List.filled(players, -1);
    active = List.filled(players, 0);
    turn = -1;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'bet':
        if (type != 'bet') throw GameError('现在是下注阶段');
        if (broke[seat]) throw GameError('你已经没有筹码了');
        if (betOf[seat] > 0) throw GameError('你已经下注');
        final amt = asInt(a['amount']);
        if (amt < 10) throw GameError('最低下注 10');
        if (amt > chips[seat]) throw GameError('筹码不足');
        betOf[seat] = amt;
        chips[seat] -= amt;
        if (waitingFor.isEmpty) _deal();
      case 'insurance':
        if (type != 'insurance') throw GameError('请选择是否购买保险');
        if (!_seated(seat) || insurance[seat] >= 0) throw GameError('无需操作');
        if (asBool(a['take'])) {
          final amt = betOf[seat] ~/ 2;
          if (amt > chips[seat] || amt <= 0) throw GameError('筹码不足以购买保险');
          chips[seat] -= amt;
          insurance[seat] = amt;
          host.log('${name(seat)} 购买保险 $amt');
        } else {
          insurance[seat] = 0;
        }
        if (waitingFor.isEmpty) _resolveInsurance();
      case 'play':
        if (seat != turn) throw GameError('还没轮到你');
        _play(seat, type);
      default:
        throw GameError('现在不能操作');
    }
  }

  void _deal() {
    for (var s = 0; s < players; s++) {
      if (_seated(s)) hands[s] = [BjHand([], betOf[s])];
    }
    for (var r = 0; r < 2; r++) {
      for (var s = 0; s < players; s++) {
        if (_seated(s)) hands[s][0].cards.add(_draw());
      }
      dealer.add(_draw());
    }
    if (cardRank(dealer[0]) == 14) {
      phase = 'insurance';
      host.log('庄家明牌为 A，可购买保险');
      return;
    }
    _afterPeek();
  }

  void _resolveInsurance() {
    final dbj = isBlackjack(dealer);
    for (var s = 0; s < players; s++) {
      if (insurance[s] > 0 && dbj) chips[s] += insurance[s] * 3;
    }
    if (dbj) host.log('庄家黑杰克！保险赔付 2:1');
    _afterPeek();
  }

  void _afterPeek() {
    // dealer peeks with a ten or ace up
    if (bjValue(dealer[0]) >= 10 && isBlackjack(dealer)) {
      if (cardRank(dealer[0]) != 14) host.log('庄家黑杰克！');
      _settle();
      return;
    }
    for (var s = 0; s < players; s++) {
      if (!_seated(s)) continue;
      if (hands[s][0].natural) {
        hands[s][0].done = true;
        host.log('${name(s)} 黑杰克！');
      }
    }
    phase = 'play';
    turn = -1;
    _nextTurn(-1);
  }

  void _nextTurn(int from) {
    for (var s = max(from, 0); s < players; s++) {
      if (!_seated(s)) continue;
      final hs = hands[s];
      for (var i = 0; i < hs.length; i++) {
        if (!hs[i].done) {
          turn = s;
          active[s] = i;
          return;
        }
      }
    }
    turn = -1;
    _dealerPlay();
  }

  List<String> legal(int seat) {
    if (phase != 'play' || seat != turn) return const [];
    final h = hands[seat][active[seat]];
    final out = <String>['hit', 'stand'];
    if (h.cards.length == 2 && chips[seat] >= h.bet) {
      out.add('double');
      if (bjValue(h.cards[0]) == bjValue(h.cards[1]) && hands[seat].length < 4) out.add('split');
    }
    return out;
  }

  void _play(int seat, String type) {
    if (!legal(seat).contains(type)) throw GameError('不能这样操作');
    final hs = hands[seat];
    final h = hs[active[seat]];
    switch (type) {
      case 'hit':
        h.cards.add(_draw());
        if (h.total >= 21) h.done = true;
        if (h.bust) host.log('${name(seat)} 爆牌（${h.total}）');
      case 'stand':
        h.done = true;
      case 'double':
        chips[seat] -= h.bet;
        h.bet *= 2;
        h.doubled = true;
        h.cards.add(_draw());
        h.done = true;
        host.log('${name(seat)} 加倍，得到 ${h.total} 点');
      case 'split':
        chips[seat] -= h.bet;
        final aces = cardRank(h.cards[0]) == 14;
        final second = h.cards.removeLast();
        final a = BjHand([h.cards[0], _draw()], h.bet, fromSplit: true, splitAces: aces);
        final b = BjHand([second, _draw()], h.bet, fromSplit: true, splitAces: aces);
        hs
          ..removeAt(active[seat])
          ..insertAll(active[seat], [a, b]);
        for (final x in [a, b]) {
          if (aces || x.total == 21) x.done = true;
        }
        host.log('${name(seat)} 分牌');
    }
    _nextTurn(seat);
  }

  bool _dealerMustHit() {
    final (t, soft) = bjTotal(dealer);
    return t < 17 || (t == 17 && soft && hitSoft17);
  }

  void _dealerPlay() {
    dealerHidden = false;
    final anyLive = [
      for (var s = 0; s < players; s++)
        if (_seated(s)) ...hands[s].where((h) => !h.bust && !h.natural)
    ].isNotEmpty;
    if (anyLive) {
      while (_dealerMustHit()) {
        dealer.add(_draw());
      }
    }
    _settle();
  }

  void _settle() {
    dealerHidden = false;
    phase = 'result';
    turn = -1;
    results = List.filled(players, 0);
    for (var s = 0; s < players; s++) {
      if (!_seated(s)) continue;
      var staked = 0, back = 0;
      for (final h in hands[s]) {
        final (o, p) = settleHand(h, dealer);
        h.outcome = o;
        h.payout = p;
        staked += h.bet;
        back += p;
      }
      chips[s] += back;
      results[s] = back - staked;
      if (insurance[s] > 0) results[s] += isBlackjack(dealer) ? insurance[s] * 2 : -insurance[s];
    }
    final (dt, _) = bjTotal(dealer);
    host.log('庄家 ${isBlackjack(dealer) ? "黑杰克" : (dt > 21 ? "爆牌" : "$dt 点")}');
    for (var s = 0; s < players; s++) {
      if (!broke[s] && chips[s] < 10) {
        broke[s] = true;
        host.log('${name(s)} 破产出局');
      }
    }
    if (round >= cap || broke.every((b) => b)) {
      phase = 'over';
      final best = List.generate(players, (i) => i)..sort((a, b) => chips[b] - chips[a]);
      host.log('游戏结束，${name(best.first)} 筹码最多（${chips[best.first]}）');
      return;
    }
    host.schedule(4000, () {
      if (phase == 'result') _newRound();
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final hidden = dealerHidden && dealer.length >= 2;
    final dcards = [for (var i = 0; i < dealer.length; i++) hidden && i == 1 ? 'back' : dealer[i]];
    final (dt, ds) = bjTotal(hidden ? [dealer[0]] : dealer);
    return {
      'phase': phase,
      'round': round,
      'rounds': roundsLimit,
      'cap': cap,
      'h17': hitSoft17,
      'chips': chips,
      'broke': broke,
      'bets': betOf,
      'insurance': insurance,
      'turn': turn,
      'active': active,
      'dealer': dcards,
      'dealerTotal': dealer.isEmpty ? 0 : dt,
      'dealerSoft': ds,
      'dealerBj': !hidden && isBlackjack(dealer),
      'hands': [for (final hs in hands) [for (final h in hs) h.toJson()]],
      'legal': seat >= 0 ? legal(seat) : const <String>[],
      'shoe': shoe.length,
      'shoeSize': shoeSize,
      'result': phase == 'result' || phase == 'over' ? results : null,
      'betChoices': betChoices,
    };
  }

  // Bot: only uses own cards, the dealer upcard and public information.
  // 0 简单: random bet sizes, sloppy "never bust"-style play half the time.
  // 1 普通: basic strategy, flat 5% bets.
  // 2 困难: full basic strategy (H17/S17 deviations) + Hi-Lo count from the
  //         public cards seen since the last shuffle for bet sizing and insurance.
  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'bet':
        if (broke[seat] || betOf[seat] > 0) return null;
        int amt;
        if (botLevel == 0) {
          amt = betChoices[rng.nextInt(betChoices.length)];
        } else {
          var frac = 0.05;
          if (botLevel >= 2) {
            final tc = _trueCount();
            frac = tc >= 2 ? min(0.2, 0.05 * (tc - 0.5)) : 0.03;
          }
          final base = (chips[seat] * frac).round();
          amt = betChoices.lastWhere((b) => b <= max(10, base), orElse: () => 10);
        }
        if (amt > chips[seat]) amt = chips[seat];
        return {'type': 'bet', 'amount': amt};
      case 'insurance':
        if (botLevel == 0) return {'type': 'insurance', 'take': rng.nextDouble() < 0.3 && chips[seat] >= betOf[seat] ~/ 2 && betOf[seat] ~/ 2 > 0};
        final take = botLevel >= 2 && _trueCount() >= 3 && chips[seat] >= betOf[seat] ~/ 2 && betOf[seat] ~/ 2 > 0;
        return {'type': 'insurance', 'take': take};
      case 'play':
        if (seat != turn) return null;
        final lg = legal(seat);
        final cards = hands[seat][active[seat]].cards;
        if (botLevel == 0 && rng.nextDouble() < 0.5) {
          // novice: stand on 12+, otherwise hit; never doubles/splits
          return {'type': bjTotal(cards).$1 >= 12 ? 'stand' : 'hit'};
        }
        if (botLevel >= 2) return {'type': fullBasicStrategy(cards, dealer[0], lg, hitSoft17: hitSoft17)};
        return {'type': basicStrategy(cards, dealer[0], lg)};
    }
    return null;
  }

  /// Hi-Lo true count from cards dealt out of the current shoe that are
  /// visible to everyone (dealer hole card only once revealed).
  double _trueCount() {
    final dealt = shoeSize - shoe.length;
    if (dealt <= 0) return 0;
    // Cards still in play this round are counted from the table; cards of
    // finished rounds were all shown at settlement.
    var rc = 0;
    final onTable = <String>[
      for (var i = 0; i < dealer.length; i++)
        if (!(dealerHidden && i == 1)) dealer[i],
      for (final hs in hands)
        for (final h in hs) ...h.cards,
    ];
    for (final c in [..._seen, ...onTable]) {
      final v = bjValue(c);
      if (v <= 6) {
        rc++;
      } else if (v >= 10) {
        rc--;
      }
    }
    final decksLeft = max(0.5, shoe.length / 52);
    return rc / decksLeft;
  }
}

/// Classic basic strategy. [legal] restricts double/split availability.
String basicStrategy(List<String> cards, String up, List<String> legal) {
  final d = bjValue(up);
  final (t, soft) = bjTotal(cards);
  final canD = legal.contains('double');
  if (legal.contains('split')) {
    final p = bjValue(cards[0]);
    final split = switch (p) {
      11 || 8 => true,
      10 || 5 => false,
      9 => d != 7 && d < 10,
      7 => d <= 7,
      6 => d <= 6,
      4 => d == 5 || d == 6,
      _ => d <= 7, // 2,3
    };
    if (split) return 'split';
  }
  if (soft && cards.length >= 2) {
    if (t >= 20) return 'stand';
    if (t == 19) return canD && d == 6 ? 'double' : 'stand';
    if (t == 18) {
      if (d >= 2 && d <= 6) return canD ? 'double' : 'stand';
      if (d <= 8) return 'stand';
      return 'hit';
    }
    final lo = switch (t) { 17 => 3, 15 || 16 => 4, _ => 5 };
    if (canD && d >= lo && d <= 6) return 'double';
    return 'hit';
  }
  if (t >= 17) return 'stand';
  if (t >= 13) return d <= 6 ? 'stand' : 'hit';
  if (t == 12) return d >= 4 && d <= 6 ? 'stand' : 'hit';
  if (t == 11) return canD ? 'double' : 'hit';
  if (t == 10) return canD && d <= 9 ? 'double' : 'hit';
  if (t == 9) return canD && d >= 3 && d <= 6 ? 'double' : 'hit';
  return 'hit';
}

/// Complete multi-deck basic strategy (doubles after split allowed, no
/// surrender) including the H17 deviations. [legal] restricts double/split.
String fullBasicStrategy(List<String> cards, String up, List<String> legal, {bool hitSoft17 = false}) {
  final d = bjValue(up);
  final (t, soft) = bjTotal(cards);
  final canD = legal.contains('double');
  if (legal.contains('split')) {
    final p = bjValue(cards[0]);
    final split = switch (p) {
      11 || 8 => true,
      10 || 5 => false,
      9 => d != 7 && d < 10,
      7 => d <= 7,
      6 => d <= 6,
      4 => d == 5 || d == 6,
      _ => d <= 7, // 2,3
    };
    if (split) return 'split';
  }
  if (soft) {
    if (t >= 20) return 'stand';
    if (t == 19) return canD && d == 6 && hitSoft17 ? 'double' : 'stand';
    if (t == 18) {
      if (d <= 6) return canD && (d >= 3 || (hitSoft17 && d == 2)) ? 'double' : 'stand';
      if (d <= 8) return 'stand';
      return 'hit';
    }
    final lo = switch (t) { 17 => 3, 15 || 16 => 4, _ => 5 };
    if (canD && d >= lo && d <= 6) return 'double';
    return 'hit';
  }
  if (t >= 17) return 'stand';
  if (t >= 13) return d <= 6 ? 'stand' : 'hit';
  if (t == 12) return d >= 4 && d <= 6 ? 'stand' : 'hit';
  if (t == 11) return canD && (d <= 10 || hitSoft17) ? 'double' : 'hit';
  if (t == 10) return canD && d <= 9 ? 'double' : 'hit';
  if (t == 9) return canD && d >= 3 && d <= 6 ? 'double' : 'hit';
  return 'hit';
}
