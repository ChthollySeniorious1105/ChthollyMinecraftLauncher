import 'dart:math';

import '../../src/engine.dart';
import 'pdk_rules.dart';

/// 跑得快（三人）。
class Paodekuai extends GameEngine {
  Paodekuai(super.setup);

  late int perHand;
  late bool mustBeat;
  late int rounds;
  int round = 0;
  late List<int> scores;

  late List<List<String>> hands;
  late List<int> playedCount; // cards played this round (关门 check)
  late List<Map<String, dynamic>?> acts; // last action per seat in the current trick
  PdkCombo? table;
  List<String> tableCards = [];
  int tableSeat = -1;
  int turn = 0;
  bool firstPlay = true;
  int bombsThisRound = 0;
  String phase = 'play'; // play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  late List<int> bombScore;

  /// Cards played by anyone this round (public information, for card counting).
  List<String> playedCards = [];

  @override
  bool get isOver => phase == 'over';

  /// Ranking by total score after the last round (ties share).
  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  void start() {
    perHand = setup.opt<int>('cards', 16);
    mustBeat = setup.opt<bool>('must', true);
    rounds = setup.opt<int>('rounds', 5);
    scores = List.filled(players, 0);
    host.log('跑得快开始：每人 $perHand 张，${mustBeat ? "有牌必须管" : "可以不管"}，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = shuffled(pdkDeck(perHand), rng);
    hands = [
      for (var s = 0; s < players; s++) (deck.sublist(s * perHand, (s + 1) * perHand)..sort((a, b) => pdkSortKey(a) - pdkSortKey(b)))
    ];
    playedCount = List.filled(players, 0);
    playedCards = [];
    acts = List.filled(players, null);
    bombScore = List.filled(players, 0);
    table = null;
    tableCards = [];
    tableSeat = -1;
    bombsThisRound = 0;
    firstPlay = true;
    result = null;
    phase = 'play';
    ready = List.filled(players, false);
    turn = hands.indexWhere((h) => h.contains('3S'));
    if (turn < 0) {
      // 15张模式♠3一定存在；保险起见由最小牌的人先出
      turn = 0;
      firstPlay = false;
    }
    host.log('第 $round 局：${name(turn)} 持有♠3，先出');
  }

  int _next(int s) => (s + 1) % players;

  bool get leading => table == null;

  /// 报单：下家只剩一张时，出单张必须出最大的。
  bool _singleMax(int seat) => hands[_next(seat)].length == 1;

  List<List<int>> candidates(int seat) {
    final ranks = [for (final c in hands[seat]) pdkRank(c)];
    var cands = pdkCandidates(ranks, table, singleMax: _singleMax(seat));
    if (firstPlay && leading) cands = [for (final c in cands) if (c.contains(3)) c];
    return cands;
  }

  bool canPass(int seat) => !leading && (!mustBeat || candidates(seat).isEmpty);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'roundEnd') {
      if (asStr(a['type']) != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _afterRound();
      return;
    }
    if (phase != 'play') throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'pass') {
      if (leading) throw GameError('你是首家，必须出牌');
      if (!canPass(seat)) throw GameError('有牌能管上，必须出牌');
      acts[seat] = {'pass': true};
      host.log('${name(seat)} 不要');
      turn = _next(seat);
      if (turn == tableSeat) {
        table = null;
        tableCards = [];
        acts = List.filled(players, null);
      }
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
    if (cards.isEmpty) throw GameError('请选择要出的牌');
    final hand = List<String>.of(hands[seat]);
    for (final c in cards) {
      if (!hand.remove(c)) throw GameError('你没有这张牌');
    }
    if (firstPlay && !cards.contains('3S')) throw GameError('首轮出牌必须包含♠3');
    final isAll = cards.length == hands[seat].length;
    final ranks = [for (final c in cards) pdkRank(c)];
    final combo = pdkParse(ranks, isAll: isAll, table: table);
    if (combo == null) {
      throw GameError(pdkParse(ranks, isAll: isAll) == null ? '不是合法牌型' : '管不上');
    }
    if (combo.type == 'single' && _singleMax(seat)) {
      final top = hands[seat].map(pdkRank).reduce((x, y) => x > y ? x : y);
      if (ranks[0] != top) throw GameError('下家报单，单张必须出最大的');
    }
    hands[seat] = hand;
    playedCount[seat] += cards.length;
    playedCards.addAll(cards);
    firstPlay = false;
    table = combo;
    tableCards = cards;
    tableSeat = seat;
    acts = List.filled(players, null);
    acts[seat] = {'cards': cards, 'label': combo.label};
    host.log('${name(seat)} 出 ${combo.label}');
    if (combo.type == 'bomb') {
      bombsThisRound++;
      for (var s = 0; s < players; s++) {
        bombScore[s] += s == seat ? 10 * (players - 1) : -10;
      }
      host.log('${name(seat)} 炸弹！每家付 10 分');
    }
    if (hand.length == 1) host.log('${name(seat)} 报单！');
    if (hand.isEmpty) {
      _roundOver(seat);
      return;
    }
    turn = _next(seat);
  }

  void _roundOver(int winner) {
    final delta = List<int>.filled(players, 0);
    final closed = List<bool>.filled(players, false);
    for (var s = 0; s < players; s++) {
      if (s == winner) continue;
      final left = hands[s].length;
      var pay = left == 1 ? 0 : left;
      if (playedCount[s] == 0) {
        closed[s] = true;
        pay *= 2;
      }
      delta[s] -= pay;
      delta[winner] += pay;
    }
    for (var s = 0; s < players; s++) {
      delta[s] += bombScore[s];
      scores[s] += delta[s];
    }
    result = {
      'winner': winner,
      'delta': delta,
      'closed': closed,
      'left': [for (final h in hands) h.length],
      'bombs': bombsThisRound,
    };
    host.log('${name(winner)} 出完了！${[for (var s = 0; s < players; s++) if (closed[s]) name(s)].map((n) => "$n 被关门").join("，")}');
    phase = 'roundEnd';
    turn = -1;
    if (round >= rounds) {
      phase = 'over';
      final best = List.generate(players, (i) => i)..sort((a, b) => scores[b] - scores[a]);
      host.log('比赛结束，${name(best.first)} 夺冠（${scores[best.first]} 分）');
    }
  }

  void _afterRound() {
    if (phase == 'roundEnd') _deal();
  }

  @override
  Map<String, dynamic> view(int seat) {
    final showAll = phase != 'play';
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'perHand': perHand,
      'must': mustBeat,
      'scores': scores,
      'turn': turn,
      'counts': [for (final h in hands) h.length],
      'hand': seat >= 0 ? hands[seat] : const <String>[],
      'hands': showAll ? hands : null,
      'acts': acts,
      'table': table?.toJson(),
      'tableCards': tableCards,
      'tableSeat': tableSeat,
      'lead': leading,
      'first': firstPlay,
      'canPass': seat >= 0 && phase == 'play' && seat == turn && canPass(seat),
      'singleMax': seat >= 0 && phase == 'play' && _singleMax(seat),
      'result': result,
      'ready': phase == 'roundEnd' ? ready : null,
    };
  }

  // ---------------------------------------------------------------------------
  // Bot (uses only own hand + public counts / table).
  // ---------------------------------------------------------------------------
  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.45) return _botRandom(seat);
    if (botLevel >= 2) return _botHard(seat);
    final hand = hands[seat];
    final cands = candidates(seat);
    List<String> pick(List<int> ranks) {
      final h = firstPlay ? (['3S', ...hand.where((c) => c != '3S')]) : hand;
      return pdkPick(h, ranks);
    }

    // finish immediately if possible
    for (final c in cands) {
      if (c.length == hand.length) return {'type': 'play', 'cards': pick(c)};
    }
    final ranks = [for (final c in hand) pdkRank(c)];
    final cnt = <int, int>{};
    for (final r in ranks) {
      cnt[r] = (cnt[r] ?? 0) + 1;
    }
    bool isBomb(List<int> c) => c.length == 4 && c.toSet().length == 1;
    int broken(List<int> c) {
      // penalty for breaking bombs / triples / pairs
      var p = 0;
      final used = <int, int>{};
      for (final r in c) {
        used[r] = (used[r] ?? 0) + 1;
      }
      used.forEach((r, u) {
        final have = cnt[r]!;
        if (have == 4 && u < 4) p += 8;
        if (have == 3 && u < 3) p += 3;
        if (have == 2 && u == 1) p += 2;
      });
      return p;
    }

    final minOpp = [for (var s = 0; s < players; s++) if (s != seat) hands[s].length].reduce((a, b) => a < b ? a : b);
    final danger = minOpp <= 3;
    if (leading) {
      final nonBomb = [for (final c in cands) if (!isBomb(c)) c];
      final pool = nonBomb.isEmpty ? cands : nonBomb;
      List<int>? best;
      var bestScore = -1e9;
      for (final c in pool) {
        final key = c.reduce((a, b) => a > b ? a : b);
        var sc = c.length * 2.0 - key * 0.6 - broken(c) * 1.5;
        if (c.length == 1 && _singleMax(seat)) sc -= 6;
        if (danger && c.length == 1) sc -= 4;
        if (sc > bestScore) {
          bestScore = sc;
          best = c;
        }
      }
      if (best != null) return {'type': 'play', 'cards': pick(best)};
      // fallback: must play something containing lowest card
      return {'type': 'play', 'cards': [hand.first]};
    }
    if (cands.isEmpty) return {'type': 'pass'};
    final fromTeamless = tableSeat;
    final tableKey = table!.key;
    final options = [for (final c in cands) if (!isBomb(c)) c];
    options.sort((a, b) => (broken(a) * 3 + a.reduce((x, y) => x > y ? x : y)) - (broken(b) * 3 + b.reduce((x, y) => x > y ? x : y)));
    if (options.isNotEmpty) {
      final c = options.first;
      final expensive = broken(c) >= 3 || c.reduce((x, y) => x > y ? x : y) >= 14;
      // be lazy when nobody is close to finishing and play would waste strength
      if (!mustBeat && expensive && !danger && hands[fromTeamless].length > 5 && tableKey >= 11 && rng.nextDouble() < 0.6) {
        return {'type': 'pass'};
      }
      return {'type': 'play', 'cards': pick(c)};
    }
    // only bombs beat
    if (mustBeat || danger || hand.length <= 6 || rng.nextDouble() < 0.5) {
      return {'type': 'play', 'cards': pick(cands.first)};
    }
    return {'type': 'pass'};
  }

  List<String> _pickFor(int seat, List<int> ranks) {
    final hand = hands[seat];
    final h = firstPlay ? (['3S', ...hand.where((c) => c != '3S')]) : hand;
    return pdkPick(h, ranks);
  }

  /// 简单: a uniformly random legal play (or pass when allowed).
  Map<String, dynamic> _botRandom(int seat) {
    final cands = candidates(seat);
    final opts = cands.length + (canPass(seat) ? 1 : 0);
    if (opts == 0) return {'type': 'pass'};
    final i = rng.nextInt(opts);
    if (i >= cands.length) return {'type': 'pass'};
    return {'type': 'play', 'cards': _pickFor(seat, cands[i])};
  }

  /// 困难: minimises the number of plays needed to empty the hand, keeps
  /// control cards, counts the cards still unseen (only own hand + cards
  /// played this round) to know which plays can't be beaten, and blocks
  /// opponents who are about to finish.
  Map<String, dynamic> _botHard(int seat) {
    final hand = hands[seat];
    final cands = candidates(seat);
    if (cands.isEmpty) return {'type': 'pass'};
    for (final c in cands) {
      if (c.length == hand.length) return {'type': 'play', 'cards': _pickFor(seat, c)};
    }
    final myRanks = [for (final c in hand) pdkRank(c)];
    // unseen = full deck minus own hand minus played cards
    final unseen = <int, int>{};
    for (final c in pdkDeck(perHand)) {
      final r = pdkRank(c);
      unseen[r] = (unseen[r] ?? 0) + 1;
    }
    for (final c in [...hand, ...playedCards]) {
      final r = pdkRank(c);
      unseen[r] = (unseen[r] ?? 0) - 1;
    }
    final bombRanks = [for (final e in unseen.entries) if (e.value >= 4) e.key];
    final next = _next(seat);
    final minOpp = [for (var s = 0; s < players; s++) if (s != seat) hands[s].length].reduce(min);
    final danger = minOpp <= 2;
    final nextLeft = hands[next].length;

    bool unbeatable(List<int> c) {
      final combo = pdkParse(c, isAll: c.length == hand.length);
      if (combo == null) return false;
      if (combo.type == 'bomb') return bombRanks.every((r) => r <= combo.key);
      if (bombRanks.isNotEmpty) return false;
      final need = switch (combo.type) { 'pair' || 'pairs' => 2, 'triple' || 'plane' => 3, _ => 1 };
      if (combo.type == 'single' || combo.type == 'pair' || combo.type == 'triple') {
        return !unseen.entries.any((e) => e.key > combo.key && e.value >= need);
      }
      // sequences: could an opponent form a higher sequence of the same length?
      for (var top = combo.key + 1; top <= 14; top++) {
        final lo = top - combo.len + 1;
        if (lo < 3) continue;
        if (List.generate(combo.len, (i) => lo + i).every((r) => (unseen[r] ?? 0) >= need)) return false;
      }
      return true;
    }

    double score(List<int> c) {
      final rest = List<int>.of(myRanks);
      for (final r in c) {
        rest.remove(r);
      }
      final isBomb = c.length == 4 && c.toSet().length == 1;
      final top = c.reduce(max);
      final sure = unbeatable(c);
      var sc = -pdkTurns(rest) * 10.0;
      // keep strong cards for later unless they matter now
      sc -= top * (danger ? 0.1 : 0.5);
      if (sure) sc += rest.length <= 6 || danger ? 12 : 4;
      if (isBomb && !danger && rest.length > 4) sc -= 25;
      if (leading) {
        sc += c.length * 0.8;
        // a beatable single when the next player is on one card hands them the game
        if (c.length == 1 && nextLeft == 1 && !sure) sc -= 40;
        if (c.length == 1 && minOpp == 1 && !sure) sc -= 15;
        if (c.length == 2 && minOpp == 2 && !sure) sc -= 10;
      } else if (danger) {
        sc += 8 + top * 0.8; // beat hard to stop them
      }
      return sc;
    }

    var best = cands.first;
    var bestScore = -1e18;
    for (final c in cands) {
      final sc = score(c);
      if (sc > bestScore) {
        bestScore = sc;
        best = c;
      }
    }
    if (!leading && canPass(seat)) {
      // passing keeps the hand intact; worth it when the play is expensive
      // and nobody is close to finishing
      final passScore = -pdkTurns(myRanks) * 10.0 + 6 - (danger ? 30 : 0) - (hands[tableSeat].length <= 4 ? 10 : 0);
      if (passScore > bestScore) return {'type': 'pass'};
    }
    return {'type': 'play', 'cards': _pickFor(seat, best)};
  }
}
