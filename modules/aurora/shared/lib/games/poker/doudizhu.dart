import '../../src/engine.dart';
import 'ddz_rules.dart';

/// 斗地主（一副牌 3 人 / 两副牌 4 人），多局累计积分。
class Doudizhu extends GameEngine {
  Doudizhu(super.setup);

  late final bool two = setup.opt<int>('decks', 1) == 2;
  late final int rounds = setup.opt<int>('rounds', 3);
  late final bool grabMode = setup.opt<String>('bid', 'score') == 'grab';

  final List<List<String>> hands = [];
  List<String> bottom = [];
  List<int> scores = [];
  int round = 0;
  int dealer = 0; // first bidder this round
  String phase = 'bid'; // bid / play / roundEnd / over
  int turn = 0;
  int landlord = -1;
  int redeals = 0;

  // bidding
  List<Object?> bids = []; // per seat: null = not yet, int (score / 0 pass) or 'call'/'grab'/'pass'
  int bidValue = 0; // score mode: highest bid; grab mode: multiplier
  int bidder = -1; // current highest / candidate
  int bidCount = 0; // number of bid actions this round
  int firstCaller = -1; // grab mode
  final List<int> _grabQueue = [];
  bool anyGrab = false;
  bool callerFinal = false;

  // play
  Combo? tableCombo;
  List<String> tableCards = [];
  int tableSeat = -1;
  List<Map<String, dynamic>?> acts = []; // current-trick action per seat
  int bombs = 0;
  List<int> playCount = [];
  Map<String, dynamic>? result;
  List<bool> ready = [];
  List<String> history = [];

  /// Cards played this round (public information, used by the hard bot).
  List<String> played = [];

  int get _handSize => two ? 25 : 17;

  @override
  void start() {
    scores = List.filled(players, 0);
    dealer = rng.nextInt(players);
    _deal();
  }

  void _deal() {
    final deck = shuffled(ddzDeck(two ? 2 : 1), rng);
    hands
      ..clear()
      ..addAll([
        for (var s = 0; s < players; s++) ddzSort(deck.sublist(s * _handSize, (s + 1) * _handSize)),
      ]);
    bottom = deck.sublist(players * _handSize);
    phase = 'bid';
    landlord = -1;
    bids = List.filled(players, null);
    bidValue = 0;
    bidder = -1;
    bidCount = 0;
    firstCaller = -1;
    _grabQueue.clear();
    anyGrab = false;
    callerFinal = false;
    turn = dealer;
    tableCombo = null;
    tableCards = [];
    tableSeat = -1;
    acts = List.filled(players, null);
    bombs = 0;
    playCount = List.filled(players, 0);
    result = null;
    history = [];
    played = [];
    host.log('第 ${round + 1}/$rounds 局开始，${name(turn)} 先${grabMode ? "叫地主" : "叫分"}');
  }

  @override
  bool get isOver => phase == 'over';

  /// Final ranking by cumulative score (single round: winning side 1st).
  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  @override
  List<int> get waitingFor {
    if (phase == 'bid' || phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  List<String> _takeCards(int seat, List<String> codes) {
    final hand = List.of(hands[seat]);
    for (final c in codes) {
      if (!hand.remove(c)) throw GameError('你没有这张牌');
    }
    return hand;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _nextRound();
      return;
    }
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (phase == 'bid') {
      if (type != 'bid') throw GameError('现在是叫地主阶段');
      _bid(seat, asInt(a['value'], 0));
      return;
    }
    if (type == 'pass') {
      if (tableCombo == null || tableSeat == seat) throw GameError('你必须出牌');
      acts[seat] = {'pass': true};
      history.add('${name(seat)} 不出');
      _advance();
      return;
    }
    if (type != 'play') throw GameError('无效操作');
    final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
    if (cards.isEmpty) throw GameError('请选择要出的牌');
    final rest = _takeCards(seat, cards);
    final lead = tableCombo == null || tableSeat == seat;
    final combo = ddzPick([for (final c in cards) ddzRank(c)], lead ? null : tableCombo, two);
    if (combo == null) {
      throw GameError(ddzAnalyze([for (final c in cards) ddzRank(c)], two).isEmpty ? '不是有效的牌型' : '管不上上家的牌');
    }
    if (lead) acts = List.filled(players, null);
    hands[seat] = rest;
    tableCombo = combo;
    tableCards = ddzSort(cards);
    tableSeat = seat;
    playCount[seat]++;
    played.addAll(cards);
    acts[seat] = {'cards': tableCards, 'label': combo.label};
    if (combo.isBomb) {
      bombs++;
      host.log('${name(seat)} 打出${combo.label}！倍数翻倍');
    }
    history.add('${name(seat)} ${combo.label}');
    if (rest.isEmpty) {
      _finishRound(seat);
      return;
    }
    if (rest.length <= 2) host.log('${name(seat)} 只剩 ${rest.length} 张牌了！');
    _advance();
  }

  void _advance() {
    turn = (turn + 1) % players;
    if (turn == tableSeat) {
      // everyone passed: new trick
      tableCombo = null;
      tableCards = [];
      acts = List.filled(players, null);
    }
  }

  void _bid(int seat, int v) {
    if (!grabMode && v != 0 && (v <= bidValue || v > 3)) throw GameError('叫分必须大于当前分数');
    bidCount++;
    if (!grabMode) {
      bids[seat] = v;
      if (v > 0) {
        bidValue = v;
        bidder = seat;
        host.log('${name(seat)} 叫 $v 分');
      } else {
        host.log('${name(seat)} 不叫');
      }
      if (bidValue == 3 || bidCount >= players) {
        if (bidder < 0) {
          _redeal();
        } else {
          _setLandlord(bidder);
        }
        return;
      }
      turn = (turn + 1) % players;
      return;
    }
    // 抢地主
    if (firstCaller < 0) {
      bids[seat] = v > 0 ? 'call' : 'pass';
      if (v > 0) {
        firstCaller = seat;
        bidder = seat;
        bidValue = 1;
        host.log('${name(seat)} 叫地主');
        // everyone after caller who hasn't passed gets a grab chance, then caller
        for (var i = 1; i < players; i++) {
          final s = (seat + i) % players;
          if (bids[s] != 'pass') _grabQueue.add(s);
        }
        if (_grabQueue.isEmpty) {
          _setLandlord(seat);
          return;
        }
        turn = _grabQueue.removeAt(0);
        return;
      }
      host.log('${name(seat)} 不叫');
      if (bidCount >= players) {
        _redeal();
        return;
      }
      turn = (turn + 1) % players;
      return;
    }
    if (v > 0) {
      bids[seat] = 'grab';
      bidder = seat;
      bidValue *= 2;
      anyGrab = true;
      host.log('${name(seat)} 抢地主（×$bidValue）');
    } else {
      if (seat != firstCaller) bids[seat] = 'nograb';
      host.log('${name(seat)} 不抢');
    }
    if (_grabQueue.isEmpty) {
      if (anyGrab && !callerFinal && seat != firstCaller) {
        callerFinal = true;
        turn = firstCaller;
      } else {
        _setLandlord(bidder);
      }
    } else {
      turn = _grabQueue.removeAt(0);
    }
  }

  void _redeal() {
    redeals++;
    if (redeals >= 3) {
      // avoid endless redeal: first bidder becomes landlord with 1
      host.log('连续无人叫地主，${name(dealer)} 强制成为地主');
      bidValue = 1;
      _setLandlord(dealer);
      return;
    }
    host.log('无人叫地主，重新发牌');
    dealer = (dealer + 1) % players;
    _deal();
  }

  void _setLandlord(int seat) {
    redeals = 0;
    landlord = seat;
    if (bidValue <= 0) bidValue = 1;
    hands[seat] = ddzSort([...hands[seat], ...bottom]);
    phase = 'play';
    turn = seat;
    host.log('${name(seat)} 成为地主，底牌：${bottom.map(_cardName).join(' ')}');
  }

  static String _cardName(String c) => ddzRankName(ddzRank(c));

  void _finishRound(int winner) {
    final landlordWin = winner == landlord;
    var spring = false;
    if (landlordWin) {
      spring = [for (var s = 0; s < players; s++) if (s != landlord) playCount[s]].every((c) => c == 0);
    } else {
      spring = playCount[landlord] <= 1;
    }
    final mult = bidValue * (1 << bombs) * (spring ? 2 : 1);
    final delta = List.filled(players, 0);
    for (var s = 0; s < players; s++) {
      if (s == landlord) continue;
      delta[s] = landlordWin ? -mult : mult;
      delta[landlord] += landlordWin ? mult : -mult;
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    result = {
      'winner': winner,
      'landlordWin': landlordWin,
      'spring': spring ? (landlordWin ? '春天' : '反春') : null,
      'bid': bidValue,
      'bombs': bombs,
      'mult': mult,
      'delta': delta,
      'hands': [for (final h in hands) h],
    };
    host.log('${landlordWin ? "地主" : "农民"}获胜！${spring ? (landlordWin ? "春天！" : "反春！") : ""}倍数 $mult');
    round++;
    if (round >= rounds) {
      phase = 'over';
      final order = List.generate(players, (i) => i)..sort((a, b) => scores[b] - scores[a]);
      host.log('比赛结束：${order.map((s) => '${name(s)} ${scores[s]}').join('，')}');
    } else {
      phase = 'roundEnd';
      ready = [for (var s = 0; s < players; s++) false];
    }
  }

  void _nextRound() {
    dealer = (dealer + 1) % players;
    _deal();
  }

  @override
  Map<String, dynamic> view(int seat) {
    final showAll = phase == 'roundEnd' || phase == 'over';
    return {
      'phase': phase,
      'two': two,
      'round': round,
      'rounds': rounds,
      'grab': grabMode,
      'turn': turn,
      'landlord': landlord,
      'hand': seat >= 0 && seat < players ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'hands': showAll ? [for (final h in hands) h] : null,
      'bottom': landlord >= 0 ? bottom : null,
      'bottomCount': bottom.length,
      'bids': bids,
      'bidValue': bidValue,
      'bidder': bidder,
      'table': tableCombo?.toJson(),
      'tableCards': tableCards,
      'tableSeat': tableSeat,
      'lead': phase == 'play' && (tableCombo == null || tableSeat == turn),
      'acts': acts,
      'bombs': bombs,
      'mult': bidValue * (1 << bombs),
      'scores': scores,
      'result': result,
      'ready': phase == 'roundEnd' ? ready : null,
      'history': history.length > 12 ? history.sublist(history.length - 12) : history,
      'over': isOver,
    };
  }

  // ---------------- bot ----------------

  double _strength(List<String> hand) {
    final r = [for (final c in hand) ddzRank(c)];
    final cnt = <int, int>{};
    for (final x in r) {
      cnt[x] = (cnt[x] ?? 0) + 1;
    }
    var s = 0.0;
    s += (cnt[17] ?? 0) * 2.0 + (cnt[16] ?? 0) * 1.5 + (cnt[15] ?? 0) * 1.0 + (cnt[14] ?? 0) * 0.4;
    for (final e in cnt.entries) {
      if (e.key <= 15 && e.value >= 4) s += 2.0 + (e.value - 4);
    }
    if (two) s *= 0.6;
    return s;
  }

  List<String> _cardsFor(List<String> hand, List<int> ranks) {
    final pool = List.of(hand);
    final out = <String>[];
    for (final r in ranks) {
      final i = pool.lastIndexWhere((c) => ddzRank(c) == r);
      out.add(pool.removeAt(i));
    }
    return out;
  }

  double _cost(List<int> play, Map<int, int> cnt, Combo c) {
    final used = <int, int>{};
    for (final r in play) {
      used[r] = (used[r] ?? 0) + 1;
    }
    var cost = c.key * 10.0 - play.length * 4.0;
    for (final e in used.entries) {
      final have = cnt[e.key]!;
      if (e.value < have) {
        cost += have >= 4 ? 300 : 40;
      }
      if (e.key >= 15) cost += 30;
    }
    if (c.isBomb) cost += 500;
    return cost;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return {'type': 'continue'};
    if (phase == 'over' || seat != turn) return null;
    final hand = hands[seat];
    if (phase == 'bid') {
      if (botLevel == 0 && rng.nextDouble() < 0.45) {
        // 简单：随手叫
        final v = rng.nextInt(4);
        if (grabMode) return {'type': 'bid', 'value': v >= 2 ? 1 : 0};
        return {'type': 'bid', 'value': v > bidValue ? v : 0};
      }
      final st = _strength(hand) - (botLevel >= 2 ? _looseness(hand) : 0);
      if (!grabMode) {
        final want = st >= 6.5 ? 3 : (st >= 4.5 ? 2 : (st >= 3 ? 1 : 0));
        return {'type': 'bid', 'value': want > bidValue ? want : 0};
      }
      final th = firstCaller < 0 ? 3.0 : 5.5;
      return {'type': 'bid', 'value': st >= th ? 1 : 0};
    }
    final ranks = [for (final c in hand) ddzRank(c)];
    final cnt = <int, int>{};
    for (final x in ranks) {
      cnt[x] = (cnt[x] ?? 0) + 1;
    }
    final lead = tableCombo == null || tableSeat == seat;
    final table = lead ? null : tableCombo;
    final cands = ddzCandidates(ranks, table, two);
    if (cands.isEmpty) return {'type': 'pass'};
    // finish immediately if possible
    for (final c in cands) {
      if (c.length == ranks.length) return {'type': 'play', 'cards': _cardsFor(hand, c)};
    }
    if (botLevel == 0) {
      // 简单：经常随手出牌 / 随便不出，不做配合与优化
      if (!lead && rng.nextDouble() < 0.25) return {'type': 'pass'};
      if (rng.nextDouble() < 0.45) {
        final plain = cands.where((c) => !ddzPick(List.of(c)..sort(), table, two)!.isBomb).toList();
        final pool = plain.isNotEmpty ? plain : cands;
        return {'type': 'play', 'cards': _cardsFor(hand, pool[rng.nextInt(pool.length)])};
      }
    }
    if (botLevel >= 2) {
      final h = _hardPlay(seat, hand, ranks, cnt, cands, table, lead);
      if (h != null) return h;
    }
    final scored = [
      for (final c in cands) (c, _cost(c, cnt, ddzPick(List.of(c)..sort(), table, two)!)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    if (lead) {
      return {'type': 'play', 'cards': _cardsFor(hand, scored.first.$1)};
    }
    final teammate = landlord >= 0 && seat != landlord && tableSeat != landlord;
    if (teammate) {
      // don't overtake a teammate unless it's cheap and small
      final best = scored.first;
      final combo = ddzPick(List.of(best.$1)..sort(), table, two)!;
      if (!combo.isBomb && best.$2 < 60 && tableCombo!.key < 11 && hands[tableSeat].length > 3) {
        return {'type': 'play', 'cards': _cardsFor(hand, best.$1)};
      }
      return {'type': 'pass'};
    }
    final best = scored.first;
    final combo = ddzPick(List.of(best.$1)..sort(), table, two)!;
    if (combo.isBomb) {
      final danger = hands[tableSeat].length <= 6 || hand.length - best.$1.length <= 4;
      if (!danger) return {'type': 'pass'};
    } else if (best.$2 > 250 && hands[tableSeat].length > 5) {
      return {'type': 'pass'};
    }
    return {'type': 'play', 'cards': _cardsFor(hand, best.$1)};
  }

  /// 困难叫牌：散牌（孤立的小单张）越多越弱。
  double _looseness(List<String> hand) {
    final cnt = <int, int>{};
    for (final c in hand) {
      final r = ddzRank(c);
      cnt[r] = (cnt[r] ?? 0) + 1;
    }
    var loose = 0;
    for (var r = 3; r <= 12; r++) {
      if (cnt[r] == 1 && (cnt[r - 1] ?? 0) == 0 && (cnt[r + 1] ?? 0) == 0) loose++;
    }
    return loose * 0.35;
  }

  /// Ranks this seat cannot see (other hands), from public info only:
  /// full deck - own hand - played cards - bottom cards still held by the landlord.
  Map<int, int> _unseen(int seat) {
    final m = <String, int>{};
    for (final c in ddzDeck(two ? 2 : 1)) {
      m[c] = (m[c] ?? 0) + 1;
    }
    void take(String c) {
      final v = m[c] ?? 0;
      if (v > 0) m[c] = v - 1;
    }
    hands[seat].forEach(take);
    played.forEach(take);
    if (landlord >= 0 && seat != landlord) {
      final rest = List.of(bottom);
      for (final c in played) {
        rest.remove(c);
      }
      rest.forEach(take);
    }
    final out = <int, int>{};
    m.forEach((c, n) {
      if (n > 0) out[ddzRank(c)] = (out[ddzRank(c)] ?? 0) + n;
    });
    return out;
  }

  /// True when no unseen cards can beat [c] (counting-based; bombs considered).
  bool _isBoss(Combo c, Map<int, int> unseen) {
    if (c.type == 'rocket') return true;
    final jokers = two ? ((unseen[16] ?? 0) >= 2 && (unseen[17] ?? 0) >= 2) : ((unseen[16] ?? 0) >= 1 && (unseen[17] ?? 0) >= 1);
    if (jokers) return false;
    final bombRanks = [for (final e in unseen.entries) if (e.key <= 15 && e.value >= 4) e];
    if (c.type == 'bomb') {
      return !bombRanks.any((e) => two ? (e.value > c.len || (e.value == c.len && e.key > c.key)) : e.key > c.key);
    }
    if (bombRanks.isNotEmpty) return false;
    final need = {'single': 1, 'pair': 2, 'triple': 3}[c.type];
    if (need == null) return false;
    for (final e in unseen.entries) {
      if (e.key > c.key && e.value >= need) return false;
    }
    return true;
  }

  /// 困难：记牌 + 残局意识。Returns null to fall back to the normal logic.
  Map<String, dynamic>? _hardPlay(
      int seat, List<String> hand, List<int> ranks, Map<int, int> cnt, List<List<int>> cands, Combo? table, bool lead) {
    final unseen = _unseen(seat);
    final enemies = [
      for (var s = 0; s < players; s++)
        if (s != seat && (seat == landlord || s == landlord)) s,
    ];
    final minEnemy = enemies.map((s) => hands[s].length).fold(99, (a, b) => a < b ? a : b);
    Combo pick(List<int> c) => ddzPick(List.of(c)..sort(), table, two)!;
    final enemyTable = !lead && enemies.contains(tableSeat);
    if (!lead && !enemyTable && landlord >= 0 && hands[landlord].length > 2) {
      // 队友的牌且地主没到残局：不压队友
      return {'type': 'pass'};
    }
    // Play a boss combo if what remains is a single playable combo (win next lead).
    for (final c in cands) {
      final rest = List.of(ranks);
      for (final r in c) {
        rest.remove(r);
      }
      if (_isBoss(pick(c), unseen) && ddzAnalyze(rest, two).isNotEmpty) {
        return {'type': 'play', 'cards': _cardsFor(hand, c)};
      }
    }
    if (lead && minEnemy <= 2) {
      // 敌方快出完：避免出对方能接走的小单张/小对子
      final scored = [
        for (final c in cands)
          (c, _cost(c, cnt, pick(c)) + ((c.length <= minEnemy && !_isBoss(pick(c), unseen)) ? 400 - c.first * 10 : 0)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      return {'type': 'play', 'cards': _cardsFor(hand, scored.first.$1)};
    }
    if (!lead && table != null) {
      if (enemyTable && hands[tableSeat].length <= 2) {
        // 必须顶住：用最大的非炸牌，不行就炸
        final plain = cands.where((c) => !pick(c).isBomb).toList();
        final use = plain.isNotEmpty ? plain.last : cands.last;
        return {'type': 'play', 'cards': _cardsFor(hand, use)};
      }
    }
    return null;
  }

  @override
  int get botDelayMs => 900;
}
