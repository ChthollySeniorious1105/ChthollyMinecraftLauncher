import '../../src/engine.dart';

/// 快艇骰子 (Yahtzee) categories.
const yahtzeeCats = [
  'ones', 'twos', 'threes', 'fours', 'fives', 'sixes', //
  'threeKind', 'fourKind', 'fullHouse', 'smallStraight', 'largeStraight', 'yahtzee', 'chance',
];

const yahtzeeCatNames = {
  'ones': '一点',
  'twos': '二点',
  'threes': '三点',
  'fours': '四点',
  'fives': '五点',
  'sixes': '六点',
  'threeKind': '三条',
  'fourKind': '四条',
  'fullHouse': '葫芦',
  'smallStraight': '小顺',
  'largeStraight': '大顺',
  'yahtzee': '快艇',
  'chance': '全计',
};

List<int> _counts(List<int> dice) {
  final c = List.filled(7, 0);
  for (final d in dice) {
    c[d]++;
  }
  return c;
}

bool isYahtzeeRoll(List<int> dice) => dice.length == 5 && dice.every((d) => d == dice[0]);

/// Raw score of [dice] in [cat] (no joker rules).
int yahtzeeScore(String cat, List<int> dice) {
  final c = _counts(dice);
  final sum = dice.fold(0, (a, b) => a + b);
  final upper = yahtzeeCats.indexOf(cat);
  if (upper >= 0 && upper < 6) return c[upper + 1] * (upper + 1);
  bool hasRun(int len) {
    for (var s = 1; s + len - 1 <= 6; s++) {
      var ok = true;
      for (var v = s; v < s + len; v++) {
        if (c[v] == 0) ok = false;
      }
      if (ok) return true;
    }
    return false;
  }

  switch (cat) {
    case 'threeKind':
      return c.any((x) => x >= 3) ? sum : 0;
    case 'fourKind':
      return c.any((x) => x >= 4) ? sum : 0;
    case 'fullHouse':
      return (c.contains(3) && c.contains(2)) ? 25 : 0;
    case 'smallStraight':
      return hasRun(4) ? 30 : 0;
    case 'largeStraight':
      return hasRun(5) ? 40 : 0;
    case 'yahtzee':
      return isYahtzeeRoll(dice) ? 50 : 0;
    case 'chance':
      return sum;
  }
  return 0;
}

/// Scorecard of one player. null = not yet filled.
class YahtzeeCard {
  final Map<String, int?> s = {for (final c in yahtzeeCats) c: null};
  int bonusYahtzees = 0;

  int get upper => [for (var i = 0; i < 6; i++) s[yahtzeeCats[i]] ?? 0].fold(0, (a, b) => a + b);
  int get upperBonus => upper >= 63 ? 35 : 0;
  int get lower => [for (var i = 6; i < 13; i++) s[yahtzeeCats[i]] ?? 0].fold(0, (a, b) => a + b);
  int get total => upper + upperBonus + lower + bonusYahtzees * 100;
  bool get full => s.values.every((v) => v != null);

  /// Legal categories and their scores for [dice], applying the forced joker rule.
  Map<String, int> options(List<int> dice) {
    final out = <String, int>{};
    final open = [for (final c in yahtzeeCats) if (s[c] == null) c];
    final joker = isYahtzeeRoll(dice) && s['yahtzee'] != null;
    if (!joker) {
      for (final c in open) {
        out[c] = yahtzeeScore(c, dice);
      }
      return out;
    }
    // Joker rules: must use matching upper box if open.
    final upperCat = yahtzeeCats[dice[0] - 1];
    if (s[upperCat] == null) return {upperCat: yahtzeeScore(upperCat, dice)};
    final lowerOpen = open.where((c) => yahtzeeCats.indexOf(c) >= 6).toList();
    if (lowerOpen.isNotEmpty) {
      for (final c in lowerOpen) {
        out[c] = switch (c) {
          'fullHouse' => 25,
          'smallStraight' => 30,
          'largeStraight' => 40,
          _ => yahtzeeScore(c, dice),
        };
      }
      return out;
    }
    for (final c in open) {
      out[c] = 0;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'scores': {for (final c in yahtzeeCats) c: s[c]},
        'upper': upper,
        'upperBonus': upperBonus,
        'bonusYahtzees': bonusYahtzees,
        'total': total,
      };
}

class Yahtzee extends GameEngine {
  Yahtzee(super.setup);

  late final List<YahtzeeCard> cards = [for (var i = 0; i < players; i++) YahtzeeCard()];
  List<int> dice = [1, 1, 1, 1, 1];
  List<bool> held = List.filled(5, false);
  int rollsLeft = 3;
  int turn = 0;
  int round = 1;
  bool over = false;
  List<int> winners = [];
  String last = '';

  /// 认输顺序：resignOrder[s] = 第几个认输（从 1 开始），0 = 未认输。
  late List<int> resignOrder = List.filled(players, 0);
  int _resigns = 0;

  bool _active(int s) => resignOrder[s] == 0;

  @override
  void start() {
    turn = 0;
    host.log('快艇骰子开始！每回合最多掷 3 次，共 13 回合');
  }

  @override
  bool get isOver => over;

  @override
  List<int>? get placings {
    if (!over) return null;
    return rankByScore([
      for (var i = 0; i < players; i++) _active(i) ? cards[i].total : -100000 + resignOrder[i],
    ]);
  }

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    if (!_active(seat)) throw GameError('你已经认输了');
    resignOrder[seat] = ++_resigns;
    host.log('${name(seat)} 认输');
    final left = [for (var i = 0; i < players; i++) if (_active(i)) i];
    if (left.length <= (players == 1 ? 0 : 1)) {
      _finish();
      return;
    }
    if (seat == turn) _next();
  }

  void _finish() {
    over = true;
    final act = [for (var i = 0; i < players; i++) if (_active(i)) i];
    if (act.isEmpty) {
      winners = [];
      host.log('游戏结束');
      return;
    }
    final best = act.map((i) => cards[i].total).reduce((a, b) => a > b ? a : b);
    winners = [for (final i in act) if (cards[i].total == best) i];
    host.log('游戏结束！${winners.map(name).join('、')} 以 $best 分获胜');
  }

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  bool get rolled => rollsLeft < 3;

  void _roll(List<bool> hold) {
    for (var i = 0; i < 5; i++) {
      if (!hold[i] || !rolled) dice[i] = rng.nextInt(6) + 1;
    }
    held = rolled ? List.of(hold) : List.filled(5, false);
    rollsLeft--;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'roll') {
      if (rollsLeft <= 0) throw GameError('本回合已掷 3 次，请选择计分项');
      final raw = a['hold'];
      final hold = List.filled(5, false);
      if (raw is List) {
        for (var i = 0; i < 5 && i < raw.length; i++) {
          hold[i] = raw[i] == true;
        }
      }
      if (rolled && hold.every((h) => h)) throw GameError('全部保留就不用再掷了，请选择计分项');
      _roll(hold);
      last = '${name(seat)} 第 ${3 - rollsLeft} 次掷骰：${dice.join(' ')}';
      return;
    }
    if (type == 'score') {
      if (!rolled) throw GameError('请先掷骰');
      final cat = asStr(a['cat']);
      final card = cards[seat];
      final opts = card.options(dice);
      if (!opts.containsKey(cat)) throw GameError('不能填这一项');
      if (isYahtzeeRoll(dice) && (card.s['yahtzee'] ?? 0) == 50) {
        card.bonusYahtzees++;
        host.log('${name(seat)} 再次掷出快艇！奖励 +100');
      }
      card.s[cat] = opts[cat];
      last = '${name(seat)} 将 ${dice.join(' ')} 记入「${yahtzeeCatNames[cat]}」得 ${opts[cat]} 分';
      _next();
      return;
    }
    throw GameError('未知操作');
  }

  void _next() {
    rollsLeft = 3;
    held = List.filled(5, false);
    if ([for (var i = 0; i < players; i++) if (_active(i)) cards[i]].every((c) => c.full)) {
      _finish();
      return;
    }
    do {
      turn++;
      if (turn >= players) {
        turn = 0;
        round++;
      }
    } while (!_active(turn) || cards[turn].full);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'players': players,
        'turn': turn,
        'round': round > 13 ? 13 : round,
        'dice': dice,
        'held': held,
        'rolled': rolled,
        'rollsLeft': rollsLeft,
        'cards': [for (final c in cards) c.toJson()],
        'options': over || !rolled ? <String, int>{} : cards[turn].options(dice),
        'last': last,
        'over': over,
        'winners': winners,
        'resigned': [for (final r in resignOrder) r > 0],
      };

  // ---------------- bot ----------------

  static const _baseline = {
    'ones': 2.0,
    'twos': 5.0,
    'threes': 8.0,
    'fours': 11.0,
    'fives': 14.0,
    'sixes': 17.0,
    'threeKind': 16.0,
    'fourKind': 8.0,
    'fullHouse': 14.0,
    'smallStraight': 20.0,
    'largeStraight': 18.0,
    'yahtzee': 14.0,
    'chance': 22.0,
  };

  /// Heuristic utility of scoring [dice] into [cat].
  double _util(YahtzeeCard card, String cat, int score) {
    var u = score - _baseline[cat]!;
    final i = yahtzeeCats.indexOf(cat);
    if (i < 6 && card.upper < 63) {
      final face = i + 1;
      // progress towards upper bonus: 3 of a face is "par".
      u += (score - 3 * face) * 0.6;
      if (card.upper + score >= 63) u += 20;
    }
    if (cat == 'chance' && round < 10) u -= 3;
    return u;
  }

  double _bestUtil(YahtzeeCard card, List<int> d) {
    final opts = card.options(d);
    var best = -1e9;
    opts.forEach((c, sc) {
      var u = _util(card, c, sc);
      if (isYahtzeeRoll(d) && (card.s['yahtzee'] ?? 0) == 50) u += 100;
      if (u > best) best = u;
    });
    return best;
  }

  static final Map<int, List<(List<int>, double)>> _outcomes = {};

  /// All multisets of [k] dice with probabilities.
  static List<(List<int>, double)> _outs(int k) => _outcomes.putIfAbsent(k, () {
        final res = <(List<int>, double)>[];
        final fact = [1, 1, 2, 6, 24, 120];
        void rec(List<int> cur, int minFace) {
          if (cur.length == k) {
            final c = _counts(cur);
            var ways = fact[k];
            for (var f = 1; f <= 6; f++) {
              ways ~/= fact[c[f]];
            }
            var p = ways.toDouble();
            for (var i = 0; i < k; i++) {
              p /= 6;
            }
            res.add((List.of(cur), p));
            return;
          }
          for (var f = minFace; f <= 6; f++) {
            cur.add(f);
            rec(cur, f);
            cur.removeLast();
          }
        }

        rec([], 1);
        return res;
      });

  @override
  Map<String, dynamic>? bot(int seat) {
    final card = cards[seat];
    if (!rolled) return {'type': 'roll', 'hold': List.filled(5, false)};
    if (botLevel == 0) return _easyBot(card);
    if (botLevel >= 2 && rollsLeft == 2) return _hardRoll(card);
    final nowBest = _bestUtil(card, dice);
    if (rollsLeft > 0) {
      // Evaluate every distinct kept multiset by one-step expected value.
      var bestEv = nowBest;
      List<bool>? bestHold;
      final seen = <String>{};
      for (var mask = 0; mask < 31; mask++) {
        final kept = <int>[];
        for (var i = 0; i < 5; i++) {
          if (mask & (1 << i) != 0) kept.add(dice[i]);
        }
        final key = (List.of(kept)..sort()).join();
        if (!seen.add(key)) continue;
        var ev = 0.0;
        for (final (o, p) in _outs(5 - kept.length)) {
          ev += p * _bestUtil(card, [...kept, ...o]);
        }
        // a second remaining roll is worth a little extra
        if (rollsLeft == 2) ev += 1.5;
        if (ev > bestEv + 0.01) {
          bestEv = ev;
          bestHold = [for (var i = 0; i < 5; i++) mask & (1 << i) != 0];
        }
      }
      if (bestHold != null) return {'type': 'roll', 'hold': bestHold};
    }
    final opts = card.options(dice);
    String? bestCat;
    var bestU = -1e9;
    opts.forEach((c, sc) {
      final u = _util(card, c, sc);
      if (u > bestU) {
        bestU = u;
        bestCat = c;
      }
    });
    return {'type': 'score', 'cat': bestCat};
  }

  String? _bestCat(YahtzeeCard card) {
    String? bestCat;
    var bestU = -1e9;
    card.options(dice).forEach((c, sc) {
      final u = _util(card, c, sc);
      if (u > bestU) {
        bestU = u;
        bestCat = c;
      }
    });
    return bestCat;
  }

  /// 简单：只保留最多的点数、常常不重掷，填分时经常随便挑。
  Map<String, dynamic> _easyBot(YahtzeeCard card) {
    if (rollsLeft > 0 && rng.nextDouble() < 0.6) {
      final c = _counts(dice);
      var face = 1;
      for (var f = 2; f <= 6; f++) {
        if (c[f] > c[face] || (c[f] == c[face] && rng.nextBool())) face = f;
      }
      final hold = [for (final d in dice) d == face];
      if (!hold.every((h) => h)) return {'type': 'roll', 'hold': hold};
    }
    if (rng.nextDouble() < 0.4) {
      final keys = card.options(dice).keys.toList();
      return {'type': 'score', 'cat': keys[rng.nextInt(keys.length)]};
    }
    return {'type': 'score', 'cat': _bestCat(card)};
  }

  /// 困难：第一次重掷时考虑剩余两次重掷的完整期望。
  Map<String, dynamic> _hardRoll(YahtzeeCard card) {
    final memo0 = <int, double>{};
    double util(List<int> d) {
      final c = _counts(d);
      var key = 0;
      for (var f = 1; f <= 6; f++) {
        key = key * 6 + c[f];
      }
      return memo0.putIfAbsent(key, () => _bestUtil(card, d));
    }

    final memo1 = <String, double>{};
    // value of a roll with exactly one reroll left: max(stop, best one-step EV)
    double value1(List<int> d) {
      final sorted = List.of(d)..sort();
      return memo1.putIfAbsent(sorted.join(), () {
        var best = util(sorted);
        final seen = <String>{};
        for (var mask = 0; mask < 31; mask++) {
          final kept = <int>[for (var i = 0; i < 5; i++) if (mask & (1 << i) != 0) sorted[i]];
          if (!seen.add(kept.join())) continue;
          var ev = 0.0;
          for (final (o, p) in _outs(5 - kept.length)) {
            ev += p * util([...kept, ...o]);
          }
          if (ev > best) best = ev;
        }
        return best;
      });
    }

    var bestEv = util(dice);
    List<bool>? bestHold;
    final seen = <String>{};
    for (var mask = 0; mask < 31; mask++) {
      final kept = <int>[for (var i = 0; i < 5; i++) if (mask & (1 << i) != 0) dice[i]];
      if (!seen.add((List.of(kept)..sort()).join())) continue;
      var ev = 0.0;
      for (final (o, p) in _outs(5 - kept.length)) {
        ev += p * value1([...kept, ...o]);
      }
      if (ev > bestEv + 0.01) {
        bestEv = ev;
        bestHold = [for (var i = 0; i < 5; i++) mask & (1 << i) != 0];
      }
    }
    if (bestHold != null) return {'type': 'roll', 'hold': bestHold};
    return {'type': 'score', 'cat': _bestCat(card)};
  }
}
