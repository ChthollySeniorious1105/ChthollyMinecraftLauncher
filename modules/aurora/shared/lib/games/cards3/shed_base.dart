import '../../src/engine.dart';
import 'cards.dart';
import 'shed_rules.dart';

/// Trick-flow core shared by 五十K and 争上游: play / pass, trick won when
/// every other active player passes, finishers leave the table and the lead
/// passes on (接风).
abstract class ShedBase extends GameEngine {
  ShedBase(super.setup);

  ShedRules get rules;

  late List<List<String>> hands;
  late List<Map<String, dynamic>?> acts;
  ShedCombo? table;
  List<String> tableCards = [];
  int tableSeat = -1;
  int turn = 0;
  int passes = 0;
  List<int> finish = []; // seats in finishing order
  List<String> trickCards = []; // every card played in the current trick
  List<String> seen = []; // every card played this round (public; reset on deal)
  late List<int> scores; // match totals

  /// Final ranking by match score (higher is better). Subclasses may refine.
  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  bool active(int s) => hands[s].isNotEmpty;
  int get activeCount => hands.where((h) => h.isNotEmpty).length;
  bool get leading => table == null;

  int nextActive(int s) {
    for (var i = 1; i <= players; i++) {
      final t = (s + i) % players;
      if (active(t)) return t;
    }
    return s;
  }

  /// Whether the round has ended after the last play.
  bool get roundDone;
  void endRound();

  /// Called when a trick is won (everyone else passed, or the round ended).
  void onTrickWon(int seat, List<String> cards) {}

  /// Who leads after [winner] took a trick (winner may have gone out).
  int leaderAfter(int winner) => active(winner) ? winner : nextActive(winner);

  void resetTrickState() {
    acts = List.filled(players, null);
    table = null;
    tableCards = [];
    tableSeat = -1;
    passes = 0;
    trickCards = [];
  }

  /// Handles 'play' / 'pass' in the play phase. Validates before mutating.
  void handlePlay(int seat, Map<String, dynamic> a) {
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'pass') {
      if (leading) throw GameError('你是首家，必须出牌');
      acts[seat] = {'pass': true};
      passes++;
      final need = activeCount - (active(tableSeat) ? 1 : 0);
      if (passes >= need) {
        final w = tableSeat;
        onTrickWon(w, trickCards);
        final lead = leaderAfter(w);
        resetTrickState();
        turn = lead;
      } else {
        turn = nextActive(turn);
      }
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final hand = hands[seat];
    final cards = c3TakeCards(a['cards'], hand, max: 40);
    final combo = shedClassify(cards, rules);
    if (combo == null) throw GameError('不是合法牌型');
    if (!leading && !combo.beats(table!)) {
      throw GameError(table!.isBomb ? '管不上：需要更大的炸弹' : '管不上：需出同型更大的牌（${table!.label}）或炸弹');
    }
    c3Remove(hand, cards);
    c3Sort(cards);
    table = combo;
    tableCards = cards;
    tableSeat = seat;
    trickCards.addAll(cards);
    seen.addAll(cards);
    passes = 0;
    acts[seat] = {'cards': cards, 'label': combo.label};
    if (combo.isBomb) host.log('${name(seat)} 打出${combo.label}！');
    if (hand.isEmpty) {
      finish.add(seat);
      host.log('${name(seat)} 出完了（第${finish.length}名）');
      if (roundDone) {
        onTrickWon(seat, trickCards);
        trickCards = [];
        endRound();
        return;
      }
    }
    turn = nextActive(seat);
  }

  /// 简单电脑：约 45% 的概率随便出一手合法牌（或不要）。null = 按正常策略。
  Map<String, dynamic>? easyMove(int seat) {
    if (botLevel != 0 || rng.nextDouble() >= 0.45) return null;
    final hand = hands[seat];
    final cands = shedCandidates(hand, table, rules);
    if (!leading && (cands.isEmpty || rng.nextDouble() < 0.35)) return {'type': 'pass'};
    if (cands.isEmpty) return {'type': 'play', 'cards': [hand.first]};
    return {'type': 'play', 'cards': cands[rng.nextInt(cands.length)]};
  }

  /// Cards [seat] cannot see (other hands), derived from public info only:
  /// full deck minus own hand minus everything played this round.
  List<String> unseenBy(int seat, List<String> fullDeck) {
    final pool = List.of(fullDeck);
    for (final c in hands[seat]) {
      pool.remove(c);
    }
    for (final c in seen) {
      pool.remove(c);
    }
    return pool;
  }

  /// 困难电脑的选牌：记牌（只用公开信息）、尽量不拆牌/炸弹、
  /// 对手快出完时封牌。[oppMin] = 在场对手最少手牌数，[valuable] = 本墩值得抢。
  /// Rough number of plays needed to empty [hand] (straights of 5+ are taken
  /// greedily, bombs count as free).
  static int handsNeeded(List<String> hand) {
    final cnt = <int, int>{};
    for (final c in hand) {
      final v = c3Val(c);
      cnt[v] = (cnt[v] ?? 0) + 1;
    }
    var n = 0;
    // straights from values that are single
    var run = <int>[];
    void flush() {
      if (run.length >= 5) {
        n++;
        for (final v in run) {
          cnt[v] = cnt[v]! - 1;
        }
      }
      run = [];
    }

    for (var v = 3; v <= 14; v++) {
      if (cnt[v] == 1) {
        run.add(v);
      } else {
        flush();
      }
    }
    flush();
    for (final e in cnt.entries) {
      if (e.value <= 0) continue;
      if (e.value >= 4 && e.key < 16) continue; // bomb
      n++;
    }
    return n;
  }

  List<String>? hardPick(int seat, List<String> unseen,
      {required int oppMin, bool valuable = false, int Function(String)? cardPts}) {
    final hand = hands[seat];
    final cands = shedCandidates(hand, table, rules);
    if (cands.isEmpty) return null;
    final whole = cands.where((c) => c.length == hand.length);
    if (whole.isNotEmpty) return whole.first;
    final g = c3Groups(hand);
    final combos = {for (final c in cands) c: shedClassify(c, rules)!};
    final urgent = oppMin <= 2 || valuable;
    // Two-step finish: play something and the rest is one combo.
    for (final c in cands) {
      final rest = List.of(hand);
      c3Remove(rest, c);
      final rc = shedClassify(rest, rules);
      if (rc == null) continue;
      if (!combos[c]!.isBomb || urgent || rc.isBomb) return c;
    }
    int breaks(List<String> c) {
      final x = combos[c]!;
      if (x.isBomb) return 0;
      var b = 0;
      final used = c3Groups(c);
      for (final e in used.entries) {
        final have = g[e.key]?.length ?? 0;
        if (have >= 4) b += 30; // 拆炸弹
        if (have > e.value.length && have < 4) b += 6; // 拆对子/三张
      }
      return b;
    }

    // Is [c] the top of its type among cards still hidden? (single/pair/triple)
    bool boss(List<String> c) {
      final x = combos[c]!;
      final need = {'single': 1, 'pair': 2, 'triple': 3}[x.type];
      if (need == null) return false;
      final ug = c3Groups(unseen);
      for (final e in ug.entries) {
        if (e.key > x.key && e.value.length >= need) return false;
      }
      return true;
    }

    int low(List<String> c) => c.map(c3Val).reduce((a, b) => a < b ? a : b);
    if (leading) {
      final nb = cands.where((c) => !combos[c]!.isBomb).toList();
      if (nb.isEmpty) return cands.first;
      int score(List<String> c) {
        final x = combos[c]!;
        final rest = List.of(hand);
        c3Remove(rest, c);
        var sc = handsNeeded(rest) * 12 + low(c) * 3 + breaks(c);
        if (cardPts != null) sc += c.fold(0, (a, card) => a + cardPts(card)) * 2; // 别把分牌送出去
        if (c.any((card) => c3Val(card) >= 15)) sc += 25; // 保留 2/王
        // 对手只剩 1~2 张：别出他可能接得住的单张/对子，除非是最大的
        if (oppMin <= 2) {
          final n = {'single': 1, 'pair': 2}[x.type];
          if (n != null && n <= oppMin) sc += boss(c) ? -40 : 80;
        }
        return sc;
      }

      nb.sort((a, b) => score(a) - score(b));
      return nb.first;
    }
    int followCost(List<String> c) {
      final rest = List.of(hand);
      c3Remove(rest, c);
      var sc = breaks(c) + handsNeeded(rest) * 4 + combos[c]!.key;
      if (cardPts != null && !valuable) sc += c.fold(0, (a, card) => a + cardPts(card));
      return sc;
    }

    final plain = cands.where((c) => !combos[c]!.isBomb).toList()..sort((a, b) => followCost(a) - followCost(b));
    if (plain.isNotEmpty) {
      final p = plain.first;
      final big = p.any((c) => c3Val(c) >= 15);
      if (breaks(p) >= 30 && !urgent) return null;
      if (big && !urgent && hand.length > 4 && table!.key < 12) return null;
      return p;
    }
    // Only bombs left: keep them unless it matters.
    if (urgent) return cands.firstWhere((c) => combos[c]!.isBomb, orElse: () => cands.first);
    return null;
  }

  Map<String, dynamic> baseView(int seat) => {
        'turn': turn,
        'lead': leading,
        'hand': seat >= 0 && seat < players ? hands[seat] : <String>[],
        'counts': [for (final h in hands) h.length],
        'acts': acts,
        'table': table?.toJson(),
        'tableCards': tableCards,
        'tableSeat': tableSeat,
        'finish': finish,
      };
}
