import '../../src/engine.dart';

/// 猜数字 1A2B.
///
/// Phases: setup (everyone picks a secret simultaneously) → play → over.
/// Every player guesses their "target" (the next alive player; in 2p the
/// opponent). Mode 'race': first to crack their target wins. Mode 'elim':
/// cracking a number eliminates that player and you take over their target;
/// last player standing wins.
class BullsCows extends GameEngine {
  BullsCows(super.setup);

  static const maxRounds = 40;
  static const maxHistory = 400;

  late int digits;
  late bool repeat;
  late bool elimination;
  String phase = 'setup';
  late List<String?> secret;
  late List<bool> alive;
  late List<int> target;
  int turn = 0;
  int round = 1;
  int winner = -1;
  String reason = '';

  /// {'s': guesser, 't': target, 'g': guess, 'a': bulls, 'b': cows}
  final List<Map<String, dynamic>> history = [];

  // bot bookkeeping: candidate list per (guesser -> target), rebuilt from history
  final Map<int, List<String>> _cand = {};
  final Map<int, int> _candTarget = {};

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings => isOver ? rankWinners(players, [if (winner >= 0) winner]) : null;

  @override
  int get botDelayMs => phase == 'setup' ? 600 : 1200;

  @override
  void start() {
    digits = setup.opt<int>('digits', 4);
    repeat = setup.opt<bool>('repeat', false);
    elimination = setup.opt<String>('mode', 'race') == 'elim';
    secret = List.filled(players, null);
    alive = List.filled(players, true);
    target = [for (var s = 0; s < players; s++) (s + 1) % players];
    host.log('猜数字开始！每人设定一个 $digits 位${repeat ? '（数字可重复）' : '、数字互不相同'}的密码。'
        '${elimination ? '猜中目标即淘汰对方并接手其目标，最后存活者获胜。' : '率先猜中目标密码者获胜。'}');
  }

  /// xAyB feedback (works with repeated digits too).
  static (int, int) score(String secret, String guess) {
    var a = 0;
    final cs = List.filled(10, 0), cg = List.filled(10, 0);
    for (var i = 0; i < guess.length; i++) {
      if (secret[i] == guess[i]) a++;
      cs[secret.codeUnitAt(i) - 48]++;
      cg[guess.codeUnitAt(i) - 48]++;
    }
    var common = 0;
    for (var d = 0; d < 10; d++) {
      common += cs[d] < cg[d] ? cs[d] : cg[d];
    }
    return (a, common - a);
  }

  static String? validate(String s, int digits, {bool repeat = false}) {
    if (s.length != digits) return '请输入 $digits 位数字';
    if (!RegExp(r'^[0-9]+$').hasMatch(s)) return '只能包含数字';
    if (!repeat && s.split('').toSet().length != digits) return '各位数字不能重复';
    return null;
  }

  static List<String> allCodes(int digits, {bool repeat = false}) {
    final out = <String>[];
    void rec(String cur) {
      if (cur.length == digits) {
        out.add(cur);
        return;
      }
      for (var d = 0; d < 10; d++) {
        final c = '$d';
        if (repeat || !cur.contains(c)) rec(cur + c);
      }
    }

    rec('');
    return out;
  }

  /// Candidates consistent with all (guess, a, b) observations.
  static List<String> consistent(List<String> pool, List<(String, int, int)> obs) => [
        for (final c in pool)
          if (obs.every((o) {
            final (x, y) = score(c, o.$1);
            return x == o.$2 && y == o.$3;
          }))
            c,
      ];

  @override
  List<int> get waitingFor {
    if (phase == 'setup') return [for (var s = 0; s < players; s++) if (secret[s] == null) s];
    if (phase == 'play') return [turn];
    return const [];
  }

  List<int> get alivePlayers => [for (var s = 0; s < players; s++) if (alive[s]) s];

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (phase == 'setup') {
      if (type != 'secret') throw GameError('请先设定你的密码');
      if (secret[seat] != null) throw GameError('你已设定密码');
      final s = asStr(a['code']).trim();
      final p = validate(s, digits, repeat: repeat);
      if (p != null) throw GameError(p);
      secret[seat] = s;
      host.log('${name(seat)} 设定好了密码');
      if (secret.every((x) => x != null)) {
        phase = 'play';
        turn = 0;
        host.log('所有人已设定密码，${name(turn)} 先猜');
      }
      return;
    }
    if (type != 'guess') throw GameError('未知操作');
    if (seat != turn) throw GameError('还没轮到你');
    final g = asStr(a['code']).trim();
    final p = validate(g, digits, repeat: repeat);
    if (p != null) throw GameError(p);
    final t = target[seat];
    final (x, y) = score(secret[t]!, g);
    history.add({'s': seat, 't': t, 'g': g, 'a': x, 'b': y, 'r': round});
    if (history.length > maxHistory) history.removeAt(0);
    host.log('${name(seat)} 猜 ${name(t)}：$g → ${x}A${y}B');
    if (x == digits) {
      if (!elimination || alivePlayers.length <= 2) {
        _finish(seat, '${name(seat)} 破解了 ${name(t)} 的密码 ${secret[t]}');
        return;
      }
      alive[t] = false;
      host.log('${name(t)} 的密码被破解，出局！${name(seat)} 接手其目标');
      for (var s = 0; s < players; s++) {
        if (alive[s] && target[s] == t) target[s] = target[t];
      }
    }
    _advance();
  }

  void _advance() {
    final order = alivePlayers;
    final i = order.indexWhere((s) => s > turn);
    final next = i < 0 ? order.first : order[i];
    if (next <= turn) {
      round++;
      if (round > maxRounds) {
        _finishDraw();
        return;
      }
    }
    turn = next;
  }

  void _finish(int w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    host.log('$why，获胜！');
  }

  void _finishDraw() {
    // most bulls in the latest guess wins; else draw
    var best = -1, bestSc = -1;
    for (final s in alivePlayers) {
      final mine = history.where((h) => h['s'] == s && h['t'] == target[s]).toList();
      final sc = mine.isEmpty ? 0 : mine.map((h) => (h['a'] as int) * 10 + (h['b'] as int)).reduce((a, b) => a > b ? a : b);
      if (sc > bestSc) {
        bestSc = sc;
        best = s;
      }
    }
    winner = best;
    reason = '达到 $maxRounds 轮上限，按最接近程度判定';
    phase = 'over';
    host.log('$reason：${name(best)} 获胜');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'phase': phase,
      'digits': digits,
      'repeat': repeat,
      'mode': elimination ? 'elim' : 'race',
      'turn': turn,
      'round': round,
      'maxRounds': maxRounds,
      'ready': [for (final s in secret) s != null],
      'alive': alive,
      'target': target,
      'mySecret': me ? secret[seat] : null,
      'secrets': isOver ? secret : [for (var s = 0; s < players; s++) (!alive[s] || s == seat) ? secret[s] : null],
      'history': history,
      'winner': winner,
      'reason': reason,
    };
  }

  // ---------------------------------------------------------------- bot

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'setup') {
      if (secret[seat] != null) return null;
      final all = allCodes(digits, repeat: repeat);
      return {'type': 'secret', 'code': all[rng.nextInt(all.length)]};
    }
    if (phase != 'play' || seat != turn) return null;
    return {'type': 'guess', 'code': botGuess(seat)};
  }

  /// Uses only public history (guesses/feedback against the current target).
  String botGuess(int seat) {
    final t = target[seat];
    final obs = <(String, int, int)>[
      for (final h in history)
        if (h['t'] == t) (h['g'] as String, h['a'] as int, h['b'] as int),
    ];
    var pool = _candTarget[seat] == t ? _cand[seat]! : allCodes(digits, repeat: repeat);
    pool = consistent(pool, obs);
    if (pool.isEmpty) pool = allCodes(digits, repeat: repeat);
    _cand[seat] = pool;
    _candTarget[seat] = t;
    if (pool.length == 1) return pool.first;
    if (obs.isEmpty) return pool[rng.nextInt(pool.length)];
    // 简单: plays any consistent candidate, sometimes forgets a clue entirely
    if (botLevel == 0) {
      if (rng.nextInt(4) == 0) {
        final loose = consistent(allCodes(digits, repeat: repeat), obs.sublist(0, obs.length - 1));
        if (loose.isNotEmpty) return loose[rng.nextInt(loose.length)];
      }
      return pool[rng.nextInt(pool.length)];
    }
    final hard = botLevel == 2;
    // Knuth-lite: sample some candidates, pick the one minimising the worst bucket
    final ns = hard ? 120 : 40, nj = hard ? 600 : 300;
    final sample = pool.length <= ns ? pool : [for (var i = 0; i < ns; i++) pool[rng.nextInt(pool.length)]];
    final judge = pool.length <= nj ? pool : [for (var i = 0; i < nj; i++) pool[rng.nextInt(pool.length)]];
    var best = sample.first;
    var bestWorst = 1 << 30;
    for (final g in sample) {
      final buckets = <int, int>{};
      for (final c in judge) {
        final (x, y) = score(c, g);
        final k = x * 10 + y;
        buckets[k] = (buckets[k] ?? 0) + 1;
      }
      final worst = buckets.values.reduce((a, b) => a > b ? a : b);
      if (worst < bestWorst) {
        bestWorst = worst;
        best = g;
      }
    }
    return best;
  }
}
