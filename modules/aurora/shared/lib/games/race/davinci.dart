import '../../src/engine.dart';

/// 达芬奇密码 (Coda).
///
/// Tile id 0..23: value = id ~/ 2 (0..11), colour = id % 2 (0 黑, 1 白).
/// 24 = 黑百搭, 25 = 白百搭 (value 12, shown as "-").
/// Order key for non-jokers = id (so black < white for equal numbers).
class DaVinci extends GameEngine {
  DaVinci(super.setup);

  static const joker = 12;
  static int val(int t) => t >= 24 ? joker : t ~/ 2;
  static int col(int t) => t % 2;
  static bool isJoker(int t) => t >= 24;

  late final bool useJoker = setup.opt<bool>('joker', false);
  late final List<List<int>> hand = [for (var s = 0; s < players; s++) <int>[]];
  final Set<int> revealed = {};
  final Map<int, Set<int>> wrong = {}; // tile -> values publicly guessed wrong
  List<int> deck = [];
  int turn = 0;
  String phase = 'guess'; // placeJoker | guess | reveal | over
  int fresh = -1; // tile drawn this turn (in hand, hidden)
  int correctThisTurn = 0;
  int winner = -1;
  Map<String, dynamic>? last;

  /// Seats in the order they were knocked out (all tiles revealed or resigned).
  final List<int> outOrder = [];
  final Set<int> resigned = {};

  @override
  List<int>? get placings {
    if (!isOver) return null;
    // winner 1st; later knock-outs rank better than earlier ones
    return [
      for (var s = 0; s < players; s++)
        s == winner ? 1 : (outOrder.contains(s) ? players - outOrder.indexOf(s) : 2),
    ];
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat >= players || !alive(seat)) return;
    host.log('${name(seat)} 认输');
    resigned.add(seat);
    if (seat == turn && fresh >= 0 && phase == 'placeJoker') {
      hand[seat].add(fresh);
    }
    revealed.addAll(hand[seat]);
    _noteOut();
    if (seat == turn) {
      _endTurn();
    } else {
      _checkOver();
    }
  }

  void _noteOut() {
    for (var s = 0; s < players; s++) {
      if (!alive(s) && !outOrder.contains(s)) outOrder.add(s);
    }
  }

  /// Insert a non-joker tile [t] into [h] keeping order among non-jokers.
  static int insertPos(List<int> h, int t) {
    for (var i = 0; i < h.length; i++) {
      if (!isJoker(h[i]) && h[i] > t) return i;
    }
    return h.length;
  }

  /// Whether [h] is correctly ordered (ignoring jokers).
  static bool ordered(List<int> h) {
    var prev = -1;
    for (final t in h) {
      if (isJoker(t)) continue;
      if (t < prev) return false;
      prev = t;
    }
    return true;
  }

  @override
  void start() {
    deck = shuffled([for (var i = 0; i < (useJoker ? 26 : 24); i++) i], rng);
    final n = players >= 4 ? 3 : 4;
    for (var s = 0; s < players; s++) {
      for (var k = 0; k < n; k++) {
        final t = deck.removeLast();
        if (isJoker(t)) {
          hand[s].insert(rng.nextInt(hand[s].length + 1), t);
        } else {
          hand[s].insert(insertPos(hand[s], t), t);
        }
      }
    }
    turn = rng.nextInt(players);
    host.log('每人 $n 张牌，${name(turn)} 先手');
    _beginTurn();
  }

  bool alive(int s) => !resigned.contains(s) && hand[s].any((t) => !revealed.contains(t));

  void _beginTurn() {
    correctThisTurn = 0;
    fresh = -1;
    if (deck.isNotEmpty) {
      final t = deck.removeLast();
      fresh = t;
      if (isJoker(t)) {
        phase = 'placeJoker';
        return;
      }
      hand[turn].insert(insertPos(hand[turn], t), t);
    }
    phase = 'guess';
  }

  void _endTurn() {
    fresh = -1;
    _noteOut();
    final left = [for (var s = 0; s < players; s++) if (alive(s)) s];
    if (left.length <= 1) {
      winner = left.isEmpty ? turn : left.first;
      phase = 'over';
      host.log('${name(winner)} 保住了最后的密码，获胜！');
      return;
    }
    do {
      turn = (turn + 1) % players;
    } while (!alive(turn));
    _beginTurn();
  }

  void _checkOver() {
    _noteOut();
    final left = [for (var s = 0; s < players; s++) if (alive(s)) s];
    if (left.length <= 1) {
      winner = left.first;
      phase = 'over';
      host.log('${name(winner)} 破解了所有对手的密码，获胜！');
    }
  }

  @override
  bool get isOver => winner >= 0;

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  String _v(int v) => v == joker ? '-' : '$v';
  String _c(int t) => col(t) == 0 ? '黑' : '白';

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final t = asStr(a['t']);
    switch (t) {
      case 'place':
        if (phase != 'placeJoker') throw GameError('现在不能放置百搭牌');
        final pos = asInt(a['pos']);
        if (pos < 0 || pos > hand[seat].length) throw GameError('无效位置');
        hand[seat].insert(pos, fresh);
        phase = 'guess';
        return;
      case 'guess':
        if (phase != 'guess') throw GameError('现在不能猜牌');
        final target = asInt(a['target']);
        final idx = asInt(a['index']);
        final v = asInt(a['value']);
        if (target == seat || target < 0 || target >= players || !alive(target)) throw GameError('请选择对手');
        if (idx < 0 || idx >= hand[target].length) throw GameError('无效的牌');
        final tile = hand[target][idx];
        if (revealed.contains(tile)) throw GameError('这张牌已经翻开');
        if (v < 0 || v > joker || (v == joker && !useJoker)) throw GameError('无效的数字');
        if (val(tile) == v) {
          revealed.add(tile);
          correctThisTurn++;
          last = {'seat': seat, 'target': target, 'index': idx, 'value': v, 'ok': true};
          host.log('${name(seat)} 猜中 ${name(target)} 的${_c(tile)}${_v(v)}！');
          if (!alive(target)) host.log('${name(target)} 的密码全部被破解，出局');
          _checkOver();
          return;
        }
        (wrong[tile] ??= {}).add(v);
        last = {'seat': seat, 'target': target, 'index': idx, 'value': v, 'ok': false};
        host.log('${name(seat)} 猜 ${name(target)} 的第 ${idx + 1} 张是 ${_v(v)}，猜错了');
        if (fresh >= 0) {
          revealed.add(fresh);
          host.log('${name(seat)} 翻开了刚摸的${_c(fresh)}${_v(val(fresh))}');
          _endTurn();
        } else {
          phase = 'reveal';
        }
        return;
      case 'stop':
        if (phase != 'guess' || correctThisTurn == 0) throw GameError('至少要猜一次');
        last = {'seat': seat, 'stop': true};
        host.log('${name(seat)} 停止猜牌');
        _endTurn();
        return;
      case 'reveal':
        if (phase != 'reveal') throw GameError('现在不需要翻牌');
        final idx = asInt(a['index']);
        if (idx < 0 || idx >= hand[seat].length || revealed.contains(hand[seat][idx])) {
          throw GameError('请选择自己的一张暗牌');
        }
        final tile = hand[seat][idx];
        revealed.add(tile);
        host.log('${name(seat)} 翻开了自己的${_c(tile)}${_v(val(tile))}');
        _endTurn();
        return;
    }
    throw GameError('未知操作');
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'hands': [
          for (var s = 0; s < players; s++)
            [
              for (final t in hand[s])
                {
                  'c': col(t),
                  'v': (s == seat || revealed.contains(t) || isOver) ? val(t) : null,
                  'r': revealed.contains(t),
                  'f': t == fresh && phase != 'placeJoker',
                  'w': (wrong[t]?.toList() ?? <int>[])..sort(),
                },
            ],
        ],
        'pending': phase == 'placeJoker' ? (seat == turn ? {'c': col(fresh), 'v': joker} : {'c': col(fresh)}) : null,
        'deck': deck.length,
        'turn': turn,
        'phase': phase,
        'correct': correctThisTurn,
        'alive': [for (var s = 0; s < players; s++) alive(s)],
        'winner': winner,
        'last': last,
        'joker': useJoker,
        'resigned': resigned.toList(),
      };

  @override
  int get botDelayMs => 900;

  // ---------------- bot ----------------

  /// Candidate values for every hidden tile of [target] from [seat]'s knowledge.
  List<Set<int>?> candidates(int seat, int target) {
    final known = <int>{...hand[seat], ...revealed};
    final h = hand[target];
    final out = List<Set<int>?>.filled(h.length, null);
    for (var i = 0; i < h.length; i++) {
      final t = h[i];
      if (revealed.contains(t)) continue;
      final c = col(t);
      var lo = -1, hi = 99;
      for (var j = i - 1; j >= 0; j--) {
        if (revealed.contains(h[j]) && !isJoker(h[j])) {
          lo = h[j];
          break;
        }
      }
      for (var j = i + 1; j < h.length; j++) {
        if (revealed.contains(h[j]) && !isJoker(h[j])) {
          hi = h[j];
          break;
        }
      }
      final set = <int>{};
      for (var id = c; id < 24; id += 2) {
        if (known.contains(id) || id <= lo || id >= hi) continue;
        set.add(val(id));
      }
      final jk = 24 + c;
      if (useJoker && !known.contains(jk)) set.add(joker);
      set.removeAll(wrong[t] ?? const <int>{});
      out[i] = set;
    }
    // Chain refinement between adjacent hidden tiles (only exact without jokers):
    // ids must strictly increase left to right, id = 2*value + colour.
    if (!useJoker) {
      for (var pass = 0; pass < 3; pass++) {
        for (var i = 1; i < h.length; i++) {
          final a = out[i - 1], b = out[i];
          if (a == null || b == null || a.isEmpty) continue;
          final minA = a.map((v) => 2 * v + col(h[i - 1])).reduce((x, y) => x < y ? x : y);
          b.removeWhere((v) => 2 * v + col(h[i]) <= minA);
        }
        for (var i = h.length - 2; i >= 0; i--) {
          final a = out[i], b = out[i + 1];
          if (a == null || b == null || b.isEmpty) continue;
          final maxB = b.map((v) => 2 * v + col(h[i + 1])).reduce((x, y) => x > y ? x : y);
          a.removeWhere((v) => 2 * v + col(h[i]) >= maxB);
        }
      }
    }
    return out;
  }

  ({int target, int index, int value, int n})? _bestGuess(int seat) {
    ({int target, int index, int value, int n})? best;
    for (var o = 0; o < players; o++) {
      if (o == seat || !alive(o)) continue;
      final cand = candidates(seat, o);
      for (var i = 0; i < cand.length; i++) {
        var s = cand[i];
        if (s == null) continue;
        if (s.isEmpty) {
          // inconsistent deduction (should not happen) — fall back to any not-yet-wrong value
          s = {for (var v = 0; v < (useJoker ? 13 : 12); v++) v}..removeAll(wrong[hand[o][i]] ?? const <int>{});
          if (s.isEmpty) s = {0};
        }
        final n = s.length;
        final list = s.toList();
        final v = list[rng.nextInt(list.length)];
        if (best == null || n < best.n || (n == best.n && rng.nextBool())) {
          best = (target: o, index: i, value: v, n: n);
        }
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'placeJoker':
        return {'t': 'place', 'pos': rng.nextInt(hand[seat].length + 1)};
      case 'reveal':
        final hidden = [for (var i = 0; i < hand[seat].length; i++) if (!revealed.contains(hand[seat][i])) i];
        return {'t': 'reveal', 'index': hidden[rng.nextInt(hidden.length)]};
      case 'guess':
        final g = _bestGuess(seat);
        if (g == null) return {'t': 'stop'};
        if (botLevel <= 0 && correctThisTurn == 0 && rng.nextDouble() < 0.5) {
          // 简单: guesses a random hidden tile with a random plausible value
          final opts = <List<int>>[];
          for (var o = 0; o < players; o++) {
            if (o == seat || !alive(o)) continue;
            for (var i = 0; i < hand[o].length; i++) {
              if (!revealed.contains(hand[o][i])) opts.add([o, i]);
            }
          }
          if (opts.isNotEmpty) {
            final o = opts[rng.nextInt(opts.length)];
            final c = candidates(seat, o[0])[o[1]];
            final vals = (c == null || c.isEmpty) ? [rng.nextInt(12)] : c.toList();
            return {'t': 'guess', 'target': o[0], 'index': o[1], 'value': vals[rng.nextInt(vals.length)]};
          }
        }
        if (correctThisTurn > 0) {
          final risky = fresh >= 0 || deck.isEmpty;
          if (botLevel >= 2) {
            // 困难: keep going only on certain guesses (or a coin-flip when nothing is at stake)
            if (g.n > 1 && (risky || g.n > 2)) return {'t': 'stop'};
          } else if (botLevel <= 0) {
            if (rng.nextDouble() < 0.4) return {'t': 'stop'};
          } else if (g.n > 1 && (risky || g.n > 2 || rng.nextBool())) {
            return {'t': 'stop'};
          }
        }
        return {'t': 'guess', 'target': g.target, 'index': g.index, 'value': g.value};
    }
    return null;
  }
}
