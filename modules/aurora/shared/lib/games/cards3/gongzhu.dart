import '../../src/engine.dart';
import 'cards.dart';
import 'gz_rules.dart';

/// 拱猪：4 人，52 张，每人 13 张，须跟花色，没有才可垫牌。
/// 猪(♠Q)-100，羊(♦J)+100，变压器(♣10)使总分翻倍，红心 A-50 K-40 Q-30 J-20 5~10各-10，
/// 全红 +200。可亮牌（猪/羊/变压器/红心A）使其分值加倍。有人累计达到 -1000 时比赛结束。
class Gongzhu extends GameEngine {
  Gongzhu(super.setup);

  late int limit;
  late bool allowExpose;
  int round = 0;
  late List<int> scores;
  late List<List<String>> hands;
  late List<List<String>> taken; // scoring cards captured this round
  late List<List<String>> exposed;
  late List<bool> exposeDone;
  Set<String> playedSuits = {}; // suits already led (for 亮牌 first-round rule)
  List<String?> trick = [null, null, null, null];
  int leader = 0;
  int turn = 0;
  int tricks = 0;
  String phase = 'expose'; // expose | play | roundEnd | over
  Map<String, dynamic>? lastTrick; // {'cards': [...], 'winner': s}
  Map<String, dynamic>? result;
  late List<bool> ready;
  List<String> played = []; // all cards played this round (public)

  @override
  bool get isOver => phase == 'over';

  /// 累计分越高名次越好（拱猪负分是坏的）。
  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'expose':
        return [for (var s = 0; s < 4; s++) if (!exposeDone[s]) s];
      case 'play':
        return [turn];
      case 'roundEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  @override
  void start() {
    limit = setup.opt<int>('limit', 1000);
    allowExpose = setup.opt<bool>('expose', true);
    scores = List.filled(4, 0);
    host.log('拱猪开始：任意玩家累计 -$limit 分时结束');
    _deal();
  }

  void _deal() {
    round++;
    final deck = c3Shuffled(c3Deck(jokers: false), rng);
    hands = [for (var s = 0; s < 4; s++) deck.sublist(s * 13, s * 13 + 13)];
    for (final h in hands) {
      gzSortHand(h);
    }
    taken = List.generate(4, (_) => <String>[]);
    exposed = List.generate(4, (_) => <String>[]);
    exposeDone = List.filled(4, !allowExpose);
    playedSuits = {};
    trick = [null, null, null, null];
    tricks = 0;
    lastTrick = null;
    result = null;
    played = [];
    ready = List.filled(4, false);
    leader = hands.indexWhere((h) => h.contains('2C'));
    turn = leader;
    phase = allowExpose ? 'expose' : 'play';
    host.log('第 $round 局：${name(leader)} 持♣2 先出');
  }

  static void gzSortHand(List<String> h) {
    const order = {'S': 0, 'H': 1, 'C': 2, 'D': 3};
    h.sort((a, b) {
      final d = order[c3Suit(a)]! - order[c3Suit(b)]!;
      return d != 0 ? d : c3Trick(a) - c3Trick(b);
    });
  }

  String? get ledSuit => trick[leader] == null ? null : c3Suit(trick[leader]!);

  /// Legal cards for [seat] right now.
  List<String> legal(int seat) {
    final h = hands[seat];
    final led = ledSuit;
    List<String> base;
    if (led == null) {
      base = List.of(h);
      if (tricks == 0 && h.contains('2C')) return ['2C'];
    } else {
      final follow = h.where((c) => c3Suit(c) == led).toList();
      base = follow.isNotEmpty ? follow : List.of(h);
    }
    // 亮过的牌在该花色第一轮不能出（除非别无选择）
    final ex = exposed[seat];
    if (ex.isNotEmpty) {
      final suitNew = led == null ? null : !playedSuits.contains(led);
      final filtered = base.where((c) {
        if (!ex.contains(c)) return true;
        final s = c3Suit(c);
        if (led == null) return playedSuits.contains(s);
        return !(s == led && suitNew == true);
      }).toList();
      if (filtered.isNotEmpty) return filtered;
    }
    return base;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= 4) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    switch (phase) {
      case 'expose':
        if (type != 'expose') throw GameError('请选择要亮的牌（可不亮）');
        if (exposeDone[seat]) throw GameError('你已经决定过了');
        final raw = a['cards'];
        if (raw != null && raw is! List) throw GameError('无效的牌');
        final list = raw is List ? raw : const [];
        if (list.length > 4) throw GameError('无效的牌');
        final pick = <String>{};
        for (final c in list) {
          if (c is! String || !gzExposable.contains(c)) throw GameError('只能亮猪、羊、变压器或红心A');
          if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
          pick.add(c);
        }
        exposed[seat] = pick.toList();
        exposeDone[seat] = true;
        if (pick.isNotEmpty) host.log('${name(seat)} 亮牌：${pick.map(c3CardName).join(' ')}');
        if (exposeDone.every((d) => d)) phase = 'play';
        return;
      case 'play':
        if (seat != turn) throw GameError('还没轮到你');
        if (type != 'play') throw GameError('请出一张牌');
        final c = a['card'];
        if (c is! String || !hands[seat].contains(c)) throw GameError('你没有这张牌');
        if (!legal(seat).contains(c)) {
          if (tricks == 0 && ledSuit == null) throw GameError('首墩必须出♣2');
          if (ledSuit != null && hands[seat].any((x) => c3Suit(x) == ledSuit)) {
            throw GameError('必须跟出${c3SuitSym[ledSuit]}');
          }
          throw GameError('亮过的牌在该花色第一轮不能出');
        }
        _play(seat, c);
        return;
      case 'roundEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) _deal();
        return;
    }
    throw GameError('游戏已结束');
  }

  void _play(int seat, String c) {
    hands[seat].remove(c);
    trick[seat] = c;
    played.add(c);
    turn = (seat + 1) % 4;
    if (trick.every((x) => x != null)) _finishTrick();
  }

  void _finishTrick() {
    final led = ledSuit!;
    var win = leader;
    for (var s = 0; s < 4; s++) {
      final c = trick[s]!;
      if (c3Suit(c) == led && c3Trick(c) > c3Trick(trick[win]!)) win = s;
    }
    final cards = [for (final c in trick) c!];
    final pts = cards.where(gzIsScoring).toList();
    taken[win].addAll(pts);
    gzSortHand(taken[win]);
    playedSuits.add(led);
    lastTrick = {'cards': cards, 'winner': win, 'leader': leader};
    trick = [null, null, null, null];
    tricks++;
    leader = win;
    turn = win;
    if (pts.contains(gzPig)) host.log('${name(win)} 收到了猪！');
    if (tricks == 13) _endRound();
  }

  /// Cards [seat] has not seen yet (still in other hands) — public info only.
  List<String> _unseen(int seat) {
    final u = c3Deck(jokers: false);
    for (final c in [...hands[seat], ...played]) {
      u.remove(c);
    }
    return u;
  }

  /// 困难领出：记牌，选别人更可能有更大牌的小牌领出，没有猪大牌时逼猪。
  String _hardLead(int seat, List<String> opts) {
    final unseen = _unseen(seat);
    final h = hands[seat];
    final pigOut = !unseen.contains(gzPig);
    final holdPig = h.contains(gzPig);
    int score(String c) {
      final s = c3Suit(c);
      final v = c3Trick(c);
      final higher = unseen.where((x) => c3Suit(x) == s && c3Trick(x) > v).length;
      final lower = unseen.where((x) => c3Suit(x) == s && c3Trick(x) < v).length;
      final others = higher + lower;
      var sc = lower * 3 - higher;
      if (others == 0) sc += 60; // 必赢这一墩，别人会往里垫猪/红心
      if (higher == 0) sc += 40;
      if (c == gzPig) sc += 200;
      if (c == gzTrans) sc += 50;
      if (c == gzSheep) sc += higher == 0 ? -30 : 80;
      if (s == 'H') sc += v >= 11 ? 30 : 5;
      if (s == 'S' && !pigOut) {
        if (holdPig) {
          if (v > 12) sc += 100; // 拿着猪还出♠A/K：自己吃猪
        } else if (v < 12 && !h.contains('AS') && !h.contains('KS')) {
          sc -= 15; // 逼猪
        } else if (v > 12) {
          sc += 60;
        }
      }
      return sc;
    }

    final pool = List.of(opts)..sort((a, b) => score(a) - score(b));
    return pool.first;
  }

  Set<String> get _allExposed => {for (final e in exposed) ...e};

  void _endRound() {
    final ex = _allExposed;
    final delta = [for (var s = 0; s < 4; s++) gzScore(taken[s], exposed: ex)];
    for (var s = 0; s < 4; s++) {
      scores[s] += delta[s];
    }
    result = {'delta': delta, 'taken': [for (final t in taken) List.of(t)], 'exposed': ex.toList()};
    host.log('第 $round 局结束：${[for (var s = 0; s < 4; s++) '${name(s)} ${delta[s] >= 0 ? '+' : ''}${delta[s]}'].join('，')}');
    final end = scores.any((x) => x <= -limit) || round >= 60;
    phase = end ? 'over' : 'roundEnd';
    ready = List.filled(4, false);
    if (end) host.log(scores.any((x) => x <= -limit) ? '有玩家达到 -$limit，比赛结束' : '已达局数上限，比赛结束');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < 4;
    return {
      'phase': phase,
      'round': round,
      'limit': limit,
      'turn': phase == 'play' ? turn : -1,
      'leader': leader,
      'tricks': tricks,
      'hand': me ? hands[seat] : <String>[],
      'legal': me && phase == 'play' && seat == turn ? legal(seat) : <String>[],
      'counts': [for (final h in hands) h.length],
      'trick': trick,
      'lastTrick': lastTrick,
      'taken': taken,
      'exposed': phase == 'expose' ? [for (var s = 0; s < 4; s++) s == seat ? exposed[s] : <String>[]] : exposed,
      'exposeDone': exposeDone,
      'scores': scores,
      'live': [for (var s = 0; s < 4; s++) gzScore(taken[s], exposed: phase == 'expose' ? const {} : _allExposed)],
      'result': phase == 'roundEnd' || phase == 'over' ? result : null,
      'ready': phase == 'roundEnd' ? ready : null,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'expose') {
      if (exposeDone[seat]) return null;
      final h = hands[seat];
      final pick = <String>[];
      if (botLevel == 0) return {'type': 'expose', 'cards': pick};
      final diamonds = h.where((c) => c3Suit(c) == 'D' && c3Trick(c) > 11).length;
      if (h.contains(gzSheep) && diamonds >= 2) pick.add(gzSheep);
      final spades = h.where((c) => c3Suit(c) == 'S').length;
      if (h.contains(gzPig) && spades >= 5 && !h.contains('AS') && !h.contains('KS')) pick.add(gzPig);
      return {'type': 'expose', 'cards': pick};
    }
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'play' || seat != turn) return null;
    return {'type': 'play', 'card': _botCard(seat)};
  }

  String _botCard(int seat) {
    final opts = legal(seat);
    if (opts.length == 1) return opts.first;
    if (botLevel == 0 && rng.nextDouble() < 0.45) return opts[rng.nextInt(opts.length)];
    final led = ledSuit;
    if (led == null && botLevel >= 2) return _hardLead(seat, opts);
    int badness(String c) => c == gzSheep ? 1000 : gzScore([c]);
    if (led == null) {
      // 领出：出小牌，避免红心大牌和黑桃大牌（除非猪已出）
      final pigOut = played.contains(gzPig) || hands[seat].contains(gzPig);
      final safe = opts.where((c) {
        if (c == gzPig || c == gzTrans) return false;
        if (c3Suit(c) == 'S' && !pigOut && c3Trick(c) > 12) return false;
        return true;
      }).toList();
      final pool = safe.isNotEmpty ? safe : opts;
      pool.sort((a, b) => c3Trick(a) - c3Trick(b));
      return pool.first;
    }
    final cur = [for (final c in trick) if (c != null) c];
    final high = cur.where((c) => c3Suit(c) == led).map(c3Trick).fold(0, (a, b) => a > b ? a : b);
    final following = opts.any((c) => c3Suit(c) == led);
    final trickPts = cur.where(gzIsScoring).fold(0, (a, c) => a + gzScore([c]));
    final last = cur.length == 3;
    if (!following) {
      // 垫牌：先垫猪，再垫红心大牌，再垫大牌；有羊的墩不垫负分
      final byBad = List.of(opts)
        ..sort((a, b) {
          if (a == gzPig) return -1;
          if (b == gzPig) return 1;
          final d = badness(a) - badness(b);
          return d != 0 ? d : c3Trick(b) - c3Trick(a);
        });
      if (byBad.contains(gzSheep) && trickPts >= 0) return byBad.firstWhere((c) => c != gzSheep, orElse: () => byBad.first);
      return byBad.first;
    }
    final under = opts.where((c) => c3Trick(c) < high).toList()..sort((a, b) => c3Trick(b) - c3Trick(a));
    if (botLevel >= 2 && !last && under.isEmpty) {
      // 困难（记牌）：躲不开时，若连最小的牌都没人能压（必赢此墩），就趁机出掉最大的牌
      final unseen = _unseen(seat);
      final nonPig = opts.where((c) => c != gzPig).toList()..sort((a, b) => c3Trick(a) - c3Trick(b));
      if (nonPig.isNotEmpty) {
        final small = nonPig.first;
        final beaten = unseen.any((c) => c3Suit(c) == led && c3Trick(c) > c3Trick(small));
        return beaten ? small : nonPig.last;
      }
    }
    if (last && trickPts > 0) {
      // 有羊可以收
      final over = opts.where((c) => c3Trick(c) > high && c != gzPig).toList();
      if (over.isNotEmpty) return over.first;
    }
    if (under.isNotEmpty) {
      // 能躲就躲，出最大的躲牌；有猪就趁机扔
      if (under.contains(gzPig)) return gzPig;
      return under.first;
    }
    // 只能压：最后一手出最大（不含猪），否则出最小
    final nonPig = opts.where((c) => c != gzPig).toList();
    final pool = nonPig.isNotEmpty ? nonPig : opts;
    pool.sort((a, b) => c3Trick(a) - c3Trick(b));
    return last ? pool.last : pool.first;
  }
}
