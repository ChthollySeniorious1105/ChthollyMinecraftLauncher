import '../../src/engine.dart';

/// Common engine for "everybody races on the same hidden word" guessing games
/// (English Wordle, 汉兜). Each round every player guesses independently and
/// simultaneously; others only see the colour feedback of your guesses.
abstract class WordRace extends GameEngine {
  WordRace(super.setup);

  static const int maxGuesses = 6;

  int get rounds => setup.opt<int>('rounds', 3);

  // ---- per-game hooks -------------------------------------------------------

  /// Answers are drawn from this list.
  List<String> get answerPool;

  /// Validates and canonicalises raw input; throws [GameError] if invalid.
  String normalize(Object? raw);

  /// Feedback string for [guess] against [answer] (public: shown to everyone).
  String mark(String guess, String answer);

  /// True if [mark] means "solved".
  bool isSolved(String guess, String answer) => guess == answer;

  /// Extra per-word info for the guesser's own board (e.g. pinyin).
  Map<String, dynamic> wordInfo(String word) => {'w': word};

  /// Text used in chat logs.
  String display(String word) => word;

  /// Best opener for strong bots (null = random candidate).
  String? get strongOpener => null;

  /// Words a strong bot may use as non-candidate probe guesses.
  List<String> get probePool => answerPool;

  // ---- state ----------------------------------------------------------------

  int round = 0;
  String phase = 'play'; // play | reveal | over
  String answer = '';
  final Set<String> _used = {};
  late List<List<String>> guesses;
  late List<List<String>> marks;
  late List<int> solvedIn; // 0 = not solved (yet)
  late List<bool> done;
  late List<int> score;
  late List<int> roundPts;
  final List<int> solveOrder = [];
  final List<Map<String, dynamic>> history = [];
  bool _over = false;

  @override
  void start() {
    score = List.filled(players, 0);
    _newRound();
  }

  void _newRound() {
    round++;
    final pool = answerPool;
    var tries = 0;
    do {
      answer = pool[rng.nextInt(pool.length)];
    } while (_used.contains(answer) && ++tries < 200);
    _used.add(answer);
    guesses = [for (var i = 0; i < players; i++) <String>[]];
    marks = [for (var i = 0; i < players; i++) <String>[]];
    solvedIn = List.filled(players, 0);
    done = List.filled(players, false);
    roundPts = List.filled(players, 0);
    solveOrder.clear();
    phase = 'play';
    host.log('第 $round/$rounds 轮开始，所有人猜同一个答案！');
  }

  /// Points for solving in [n] guesses (+1 for the first solver in multiplayer).
  int pointsFor(int n, bool first) => (maxGuesses + 1 - n) + (first && players > 1 ? 1 : 0);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    if (phase != 'play') throw GameError('本轮已结束，请稍候');
    if (done[seat]) throw GameError(solvedIn[seat] > 0 ? '你已经猜中了，等待其他玩家' : '你本轮的机会已用完，等待其他玩家');
    switch (a['type']) {
      case 'guess':
        final w = normalize(a['word']);
        guesses[seat].add(w);
        marks[seat].add(mark(w, answer));
        final n = guesses[seat].length;
        if (isSolved(w, answer)) {
          solvedIn[seat] = n;
          done[seat] = true;
          final first = solveOrder.isEmpty;
          solveOrder.add(seat);
          final p = pointsFor(n, first);
          roundPts[seat] = p;
          score[seat] += p;
          host.log('${name(seat)} 第 $n 次猜中！+$p 分${first && players > 1 ? '（最快 +1）' : ''}');
        } else if (n >= maxGuesses) {
          done[seat] = true;
          host.log('${name(seat)} 用完了 $maxGuesses 次机会');
        }
      case 'giveup':
        done[seat] = true;
        host.log('${name(seat)} 放弃了本轮');
      default:
        throw GameError('未知操作');
    }
    if (done.every((d) => d)) _endRound();
  }

  void _endRound() {
    history.add({
      'answer': answer,
      'info': wordInfo(answer),
      'pts': List.of(roundPts),
      'solved': List.of(solvedIn),
    });
    host.log('第 $round 轮答案：${display(answer)}');
    if (round >= rounds) {
      phase = 'over';
      _over = true;
    } else {
      phase = 'reveal';
      host.schedule(6000, () {
        if (phase == 'reveal') _newRound();
      });
    }
  }

  @override
  List<int> get waitingFor => phase == 'play' ? [for (var s = 0; s < players; s++) if (!done[s]) s] : const [];

  @override
  bool get isOver => _over;

  @override
  List<int>? get placings => _over ? rankByScore(score) : null;

  @override
  Map<String, dynamic> view(int seat) {
    final open = phase != 'play';
    final me = seat >= 0 && seat < players;
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'max': maxGuesses,
      'score': score,
      'roundPts': roundPts,
      'solved': solvedIn,
      'done': done,
      'first': solveOrder.isEmpty ? -1 : solveOrder.first,
      // colour feedback of everyone is public; the words are not (until the round ends)
      'marks': marks,
      'mine': me ? [for (final w in guesses[seat]) wordInfo(w)] : null,
      'words': open ? guesses : null,
      'answer': open ? wordInfo(answer) : null,
      'history': history,
      'placings': placings,
    };
  }

  // ---- bots -----------------------------------------------------------------

  /// Memo of candidate answers consistent with a guess history (pure cache,
  /// not game state: the same history always yields the same list).
  final Map<String, List<String>> _cand = {};

  List<String> candidatesFor(List<String> gs, List<String> ms) {
    if (gs.isEmpty) return answerPool;
    final key = '$round|${gs.join(',')}|${ms.join(',')}';
    final hit = _cand[key];
    if (hit != null) return hit;
    final prev = candidatesFor(gs.sublist(0, gs.length - 1), ms.sublist(0, ms.length - 1));
    final g = gs.last, m = ms.last;
    final out = [for (final c in prev) if (mark(g, c) == m) c];
    if (_cand.length > 4000) _cand.clear();
    _cand[key] = out;
    return out;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || seat < 0 || seat >= players || done[seat]) return null;
    // only this seat's own guesses + feedback are used
    final gs = guesses[seat], ms = marks[seat];
    var cands = candidatesFor(gs, ms);
    if (cands.isEmpty) cands = answerPool; // cannot happen, but never get stuck
    final pool = answerPool;
    String pick;
    switch (botLevel) {
      case 0:
        if (rng.nextDouble() < 0.55) {
          pick = cands[rng.nextInt(cands.length)];
        } else {
          pick = pool[rng.nextInt(pool.length)];
        }
      case 2:
        pick = _strongPick(gs, cands);
      default:
        pick = cands[rng.nextInt(cands.length)];
    }
    return {'type': 'guess', 'word': pick};
  }

  String _strongPick(List<String> gs, List<String> cands) {
    if (gs.isEmpty) return strongOpener ?? cands[rng.nextInt(cands.length)];
    if (cands.length <= 2) return cands[rng.nextInt(cands.length)];
    // sample the candidate set and score probes by how finely they split it
    final sample = cands.length <= 150 ? cands : [for (var i = 0; i < 150; i++) cands[rng.nextInt(cands.length)]];
    final probes = <String>{
      ...(cands.length <= 60 ? cands : [for (var i = 0; i < 60; i++) cands[rng.nextInt(cands.length)]]),
      if (gs.length < maxGuesses - 1)
        for (var i = 0; i < 40; i++) probePool[rng.nextInt(probePool.length)],
    }.toList();
    final candSet = cands.toSet();
    String best = cands.first;
    var bestScore = -1.0;
    for (final p in probes) {
      final buckets = <String, int>{};
      for (final c in sample) {
        final k = mark(p, c);
        buckets[k] = (buckets[k] ?? 0) + 1;
      }
      // expected remaining size (lower is better) -> score; candidates get a small bonus
      var sumSq = 0;
      for (final b in buckets.values) {
        sumSq += b * b;
      }
      final s = sample.length / (sumSq / sample.length) + (candSet.contains(p) ? 0.5 : 0);
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return best;
  }
}
