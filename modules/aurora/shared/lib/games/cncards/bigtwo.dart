import '../../src/engine.dart';
import 'bigtwo_rules.dart';
import 'cards.dart';

/// 锄大地（Big Two）。2-4 人，♦3 先出。
class BigTwo extends GameEngine {
  BigTwo(super.setup);

  late int rounds;
  late bool doubling;
  int round = 0;
  late List<int> scores;
  late List<List<String>> hands;
  late List<Map<String, dynamic>?> acts;
  B2Combo? table;
  List<String> tableCards = [];
  int tableSeat = -1;
  int turn = 0;
  String? mustInclude; // first play of the round must include this card
  String phase = 'play'; // play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  List<Map<String, dynamic>> history = [];

  /// Every card played this round (public information, used by 困难 bots).
  List<String> played = [];
  int resigned = -1;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(scores);
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
    host.log('游戏结束！${name(1 - seat)} 获胜');
  }

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [turn];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 4);
    doubling = setup.opt<bool>('double', true);
    scores = List.filled(players, 0);
    host.log('锄大地开始：$players 人，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = shuffled(cnDeck(), rng);
    final per = players == 3 ? 17 : 13;
    hands = [for (var s = 0; s < players; s++) deck.sublist(s * per, (s + 1) * per)];
    if (players == 3) {
      // 第 52 张给持有♦3的玩家
      final extra = deck[51];
      final holder = hands.indexWhere((h) => h.contains('3D'));
      (holder >= 0 ? hands[holder] : hands[0]).add(extra);
    }
    for (final h in hands) {
      b2Sort(h);
    }
    // 持有最小牌的人先出（通常是♦3）
    var best = 99;
    for (var s = 0; s < players; s++) {
      final v = b2Value(hands[s].first);
      if (v < best) {
        best = v;
        turn = s;
      }
    }
    mustInclude = hands[turn].first;
    acts = List.filled(players, null);
    table = null;
    tableCards = [];
    tableSeat = -1;
    result = null;
    phase = 'play';
    ready = List.filled(players, false);
    history = [];
    played = [];
    host.log('第 $round 局：${name(turn)} 持有${cnCardName(mustInclude!)}，先出');
  }

  int _next(int s) => (s + 1) % players;
  bool get leading => table == null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (ready.every((r) => r)) _afterRound();
      return;
    }
    if (phase != 'play') throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'pass') {
      if (leading) throw GameError('你是首家，必须出牌');
      acts[seat] = {'pass': true};
      _advance();
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final raw = a['cards'];
    final cards = raw is List ? [for (final c in raw) '$c'] : <String>[];
    if (cards.isEmpty) throw GameError('请选择要出的牌');
    final hand = hands[seat];
    final pool = List.of(hand);
    for (final c in cards) {
      if (!pool.remove(c)) throw GameError('你没有这张牌');
    }
    final combo = b2Classify(cards);
    if (combo == null) throw GameError('不是合法牌型（单张、对子、三条或五张牌型）');
    if (mustInclude != null && !cards.contains(mustInclude)) {
      throw GameError('首轮出牌必须包含${cnCardName(mustInclude!)}');
    }
    if (!leading) {
      if (combo.len != table!.len) throw GameError('必须出相同张数的牌（${table!.len}张）');
      if (!combo.beats(table!)) throw GameError('管不上');
    }
    for (final c in cards) {
      hand.remove(c);
    }
    played.addAll(cards);
    b2Sort(cards);
    mustInclude = null;
    table = combo;
    tableCards = cards;
    tableSeat = seat;
    // clear other seats' old actions at the start of a new trick
    acts[seat] = {'cards': cards, 'label': combo.label};
    history.add({'seat': seat, 'cards': cards, 'label': combo.label});
    if (history.length > 20) history.removeAt(0);
    if (hand.isEmpty) {
      _endRound(seat);
      return;
    }
    if (hand.length == 1) host.log('${name(seat)} 只剩一张牌！');
    _advance();
  }

  void _advance() {
    turn = _next(turn);
    if (turn == tableSeat) {
      // 其他人都不要，重新领出
      table = null;
      tableCards = [];
      acts = List.filled(players, null);
    }
  }

  static int mult(int left, bool doubling) {
    if (!doubling) return 1;
    if (left >= 13) return 3;
    if (left >= 10) return 2;
    return 1;
  }

  void _endRound(int winner) {
    final delta = List.filled(players, 0);
    final left = [for (final h in hands) h.length];
    for (var s = 0; s < players; s++) {
      if (s == winner) continue;
      final lose = left[s] * mult(left[s], doubling);
      delta[s] -= lose;
      delta[winner] += lose;
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    result = {
      'winner': winner,
      'delta': delta,
      'left': left,
      'hands': [for (final h in hands) List.of(h)],
    };
    host.log('第 $round 局 ${name(winner)} 出完获胜');
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  void _afterRound() => _deal();

  @override
  Map<String, dynamic> view(int seat) {
    final ended = phase != 'play';
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'turn': phase == 'play' ? turn : -1,
      'lead': leading,
      'hand': seat >= 0 ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'scores': scores,
      'acts': acts,
      'table': table?.toJson(),
      'tableCards': tableCards,
      'tableSeat': tableSeat,
      'mustInclude': mustInclude,
      'result': ended ? result : null,
      'ready': phase == 'roundEnd' ? ready : null,
      'history': history,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    if (botLevel <= 0 && rng.nextDouble() < 0.45) return _botRandom(seat);
    if (botLevel >= 2) return _botHard(seat);
    return _botNormal(seat);
  }

  /// 简单：随便出一手合法牌（跟牌时也常常直接不要）。
  Map<String, dynamic> _botRandom(int seat) {
    final hand = hands[seat];
    if (!leading && rng.nextDouble() < 0.35) return {'type': 'pass'};
    final c = b2Candidates(hand, leading ? null : table, mustInclude: mustInclude);
    if (c.isEmpty) return leading ? {'type': 'play', 'cards': [mustInclude ?? hand.first]} : {'type': 'pass'};
    return {'type': 'play', 'cards': c[rng.nextInt(c.length)]};
  }

  /// Rough number of plays needed to empty [hand] (fewer = better structure).
  static int handMoves(List<String> hand) {
    final cnt = <int, int>{};
    for (final c in hand) {
      cnt[b2RankIdx(c)] = (cnt[b2RankIdx(c)] ?? 0) + 1;
    }
    var moves = cnt.length;
    // straights made of single cards (natural ranks, A2345 .. TJQKA)
    final singles = {for (final e in cnt.entries) if (e.value == 1) e.key};
    int nat(int idx) => idx == 12 ? 2 : idx + 3; // b2 index -> natural rank (2 → 2, A → 14)
    final natSingles = {for (final i in singles) nat(i)};
    if (natSingles.contains(14)) natSingles.add(1);
    for (var top = 14; top >= 5; top--) {
      final run = [for (var r = top - 4; r <= top; r++) r];
      if (run.every(natSingles.contains)) {
        natSingles.removeAll(run);
        if (run.contains(1)) natSingles.remove(14);
        if (run.contains(14)) natSingles.remove(1);
        moves -= 4;
      }
    }
    // full houses: a triple takes a pair along
    final triples = cnt.values.where((v) => v == 3).length;
    final pairs = cnt.values.where((v) => v == 2).length;
    moves -= triples < pairs ? triples : pairs;
    // quads need a kicker: one single gets absorbed
    final quads = cnt.values.where((v) => v == 4).length;
    final singleLeft = cnt.values.where((v) => v == 1).length;
    moves -= quads < singleLeft ? quads : singleLeft;
    return moves;
  }

  /// Strongest combo key of length [len] that the unseen cards could form
  /// (public-info card counting). -1 = none; a huge value = too many to count (assume it can be beaten).
  int _maxUnseen(int len, List<String> unseen, int maxOpp) {
    if (maxOpp < len) return -1;
    if (len == 5 && unseen.length > 16) return 0x3fffffff;
    var best = -1;
    for (final idx in cnCombos(unseen.length, len)) {
      final c = b2Classify([for (final i in idx) unseen[i]]);
      if (c != null && c.key > best) best = c.key;
    }
    return best;
  }

  /// 困难：记牌（已出的牌 + 自己的手牌）+ 手牌结构评估。
  Map<String, dynamic> _botHard(int seat) {
    final hand = hands[seat];
    final gone = {...hand, ...played};
    final unseen = [for (final c in cnDeck()) if (!gone.contains(c)) c];
    final opp = [for (var s = 0; s < players; s++) if (s != seat) hands[s].length];
    final oppMin = opp.fold(99, (a, b) => a < b ? a : b);
    final nextLeft = hands[_next(seat)].length;
    final cands = b2Candidates(hand, leading ? null : table, mustInclude: mustInclude);
    if (cands.isEmpty) {
      return leading ? {'type': 'play', 'cards': [mustInclude ?? hand.first]} : {'type': 'pass'};
    }
    for (final c in cands) {
      if (c.length == hand.length) return {'type': 'play', 'cards': c};
    }
    final baseMoves = handMoves(hand);
    final maxOpp = opp.fold(0, (a, b) => a > b ? a : b);
    final maxKey = <int, int>{};
    final danger = oppMin <= 3;
    double score(List<String> c) {
      final rest = [for (final x in hand) if (!c.contains(x)) x];
      final k = b2Classify(c)!;
      final restMoves = handMoves(rest);
      final top = c.map(b2Value).reduce((a, b) => a > b ? a : b) / 51.0;
      var v = -restMoves * 10.0 - top * 6;
      if (leading) v += c.length * 1.5;
      final safe = k.key > maxKey.putIfAbsent(c.length, () => _maxUnseen(c.length, unseen, maxOpp));
      if (safe) v += restMoves <= 1 ? 40 : 2;
      if (danger) {
        // 对手快出完：出张数多的牌型、出大牌顶住
        v += top * 14 + (c.length > 1 ? 6 : 0);
        if (c.length == 1 && nextLeft == 1 && !safe) v -= 12;
        if (c.length > oppMin) v += 8;
      }
      return v;
    }

    var best = cands.first;
    var bestV = -1e9;
    for (final c in cands) {
      final v = score(c);
      if (v > bestV) {
        bestV = v;
        best = c;
      }
    }
    if (!leading && !danger) {
      // 不值得拆牌/交大牌时就不要
      final passV = -baseMoves * 10.0 - 4;
      if (bestV < passV) return {'type': 'pass'};
    }
    return {'type': 'play', 'cards': best};
  }

  Map<String, dynamic> _botNormal(int seat) {
    final hand = hands[seat];
    final nextLeft = hands[_next(seat)].length;
    if (leading) {
      final c = b2Candidates(hand, null, mustInclude: mustInclude);
      // prefer plays that dump the lowest card with the most cards
      final low = mustInclude ?? hand.first;
      final withLow = c.where((x) => x.contains(low)).toList();
      final pool = withLow.isNotEmpty ? withLow : c;
      pool.sort((a, b) {
        if (a.length != b.length) return b.length - a.length;
        return b2Classify(a)!.key - b2Classify(b)!.key;
      });
      var pick = pool.first;
      if (nextLeft == 1 && pick.length == 1 && mustInclude == null) {
        // 下家报单：尽量不出小单张
        final multi = c.where((x) => x.length > 1).toList();
        if (multi.isNotEmpty) {
          pick = multi.first;
        } else {
          pick = [hand.last];
        }
      }
      return {'type': 'play', 'cards': pick};
    }
    final c = b2Hints(hand, table);
    if (c.isEmpty) return {'type': 'pass'};
    final danger = hands.any((h) => h.length <= 2 && !identical(h, hand));
    // avoid spending 2s / big hands early unless someone is about to go out
    final pick = danger ? c.last : c.first;
    final usesTwo = pick.any((x) => x[0] == '2');
    if (!danger && usesTwo && hand.length > 6 && rng.nextInt(3) == 0) return {'type': 'pass'};
    return {'type': 'play', 'cards': pick};
  }
}
