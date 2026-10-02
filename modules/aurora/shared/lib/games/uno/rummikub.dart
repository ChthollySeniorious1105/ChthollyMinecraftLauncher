import '../../src/engine.dart';

/// Tiles are ids 0..105. id 104/105 = jokers.
/// Otherwise color = (id ~/ 13) % 4  (0 红 1 蓝 2 黄 3 黑), number = id % 13 + 1.
const rkColorNames = ['红', '蓝', '黄', '黑'];
const rkJokerPenalty = 30;

bool rkIsJoker(int id) => id >= 104;
int rkColor(int id) => rkIsJoker(id) ? -1 : (id ~/ 13) % 4;
int rkNumber(int id) => rkIsJoker(id) ? 0 : id % 13 + 1;
int rkPenalty(int id) => rkIsJoker(id) ? rkJokerPenalty : rkNumber(id);

/// Returns the point value of a valid set (jokers take the value they represent), or null if invalid.
int? rkSetValue(List<int> set) {
  if (set.length < 3) return null;
  final nums = [for (final t in set) if (!rkIsJoker(t)) t];
  if (nums.isEmpty) return null; // all jokers: ambiguous, disallow
  // group
  if (set.length <= 4) {
    final n = rkNumber(nums.first);
    final cols = nums.map(rkColor).toSet();
    if (nums.every((t) => rkNumber(t) == n) && cols.length == nums.length) {
      return n * set.length;
    }
  }
  // run: tiles taken in the given order (left to right ascending)
  final c = rkColor(nums.first);
  if (!nums.every((t) => rkColor(t) == c)) return null;
  if (set.length > 13) return null;
  // find position of first non-joker to anchor
  final firstIdx = set.indexWhere((t) => !rkIsJoker(t));
  final start = rkNumber(set[firstIdx]) - firstIdx;
  if (start < 1 || start + set.length - 1 > 13) return null;
  var sum = 0;
  for (var i = 0; i < set.length; i++) {
    final want = start + i;
    if (!rkIsJoker(set[i]) && rkNumber(set[i]) != want) return null;
    sum += want;
  }
  return sum;
}

bool rkValid(List<int> set) => rkSetValue(set) != null;

/// Try to order a set's tiles into a valid arrangement (sorts runs, places jokers).
List<int>? rkNormalize(List<int> set) {
  if (rkValid(set)) return set;
  final nums = [for (final t in set) if (!rkIsJoker(t)) t]..sort((a, b) => rkNumber(a).compareTo(rkNumber(b)));
  final jokers = [for (final t in set) if (rkIsJoker(t)) t];
  if (nums.isEmpty) return null;
  final grp = [...nums, ...jokers];
  if (rkValid(grp)) return grp;
  // run: fill gaps with jokers, extra jokers at end (or start if hitting 13)
  final out = <int>[];
  var j = List.of(jokers);
  for (var i = 0; i < nums.length; i++) {
    if (i > 0) {
      final gap = rkNumber(nums[i]) - rkNumber(nums[i - 1]) - 1;
      if (gap < 0) return null;
      for (var k = 0; k < gap; k++) {
        if (j.isEmpty) return null;
        out.add(j.removeLast());
      }
    }
    out.add(nums[i]);
  }
  while (j.isNotEmpty) {
    final endNum = rkNumber(nums.last) + (out.length - out.lastIndexOf(nums.last) - 1);
    if (endNum < 13) {
      out.add(j.removeLast());
    } else {
      out.insert(0, j.removeLast());
    }
  }
  return rkValid(out) ? out : null;
}

class RummikubGame extends GameEngine {
  RummikubGame(super.setup);

  List<List<int>> racks = [];
  List<List<int>> table = [];
  List<int> wall = [];
  List<bool> melded = [];
  int turn = 0;
  bool over = false;
  int winner = -1;
  int passes = 0;
  String last = '';
  List<int> lastAdded = [];
  List<int> finalScores = [];

  @override
  void start() {
    wall = shuffled(List.generate(106, (i) => i), rng);
    racks = [for (var s = 0; s < players; s++) [for (var i = 0; i < 14; i++) wall.removeLast()]];
    melded = List.filled(players, false);
    turn = rng.nextInt(players);
    host.log('拉密开始，${name(turn)} 先手');
  }

  @override
  bool get isOver => over;

  int resigned = -1;

  @override
  List<int>? get placings {
    if (!over) return null;
    if (resigned >= 0) return rankWinners(players, [winner]);
    // 胜者（手牌为空或点数最少）第一，其余按剩余牌点数从少到多
    final total = [
      for (var s = 0; s < players; s++) s == winner ? -1 : racks[s].fold<int>(0, (a, t) => a + rkPenalty(t))
    ];
    return rankByScore(total, lowWins: true);
  }

  @override
  bool get canResign => !over && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    over = true;
    winner = 1 - seat;
    final total = [for (var s = 0; s < players; s++) racks[s].fold<int>(0, (a, t) => a + rkPenalty(t))];
    finalScores = [for (var s = 0; s < players; s++) s == winner ? total[seat] : -total[s]];
    last = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log('${name(seat)} 认输');
  }

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final t = asStr(a['type']);
    if (t == 'draw') {
      if (wall.isEmpty) {
        passes++;
        last = '${name(seat)} 牌池已空，跳过';
        if (passes >= players) {
          _finishByWall();
          return;
        }
      } else {
        racks[seat].add(wall.removeLast());
        last = '${name(seat)} 摸了一张牌';
        passes = 0;
      }
      lastAdded = [];
      _next();
      return;
    }
    if (t != 'submit') throw GameError('未知操作');
    final rawTable = a['table'];
    if (rawTable is! List) throw GameError('桌面数据无效');
    final newTable = <List<int>>[
      for (final s in rawTable)
        if (s is List && s.isNotEmpty) asIntList(s)
    ];
    submit(seat, newTable);
  }

  /// Validates and applies a new table for [seat]. Throws [GameError] if illegal.
  void submit(int seat, List<List<int>> newTable) {
    final oldTiles = [for (final s in table) ...s];
    final newTiles = [for (final s in newTable) ...s];
    if (newTiles.toSet().length != newTiles.length) throw GameError('有重复的牌');
    final oldSet = oldTiles.toSet();
    if (!oldSet.every(newTiles.contains)) throw GameError('桌面上原有的牌不能拿回手里');
    final added = [for (final t in newTiles) if (!oldSet.contains(t)) t];
    if (added.isEmpty) throw GameError('至少要从手牌打出一张牌，否则请摸牌');
    final rack = racks[seat];
    if (!added.every(rack.contains)) throw GameError('你手里没有这些牌');
    final fixed = <List<int>>[];
    for (final s in newTable) {
      final n = rkNormalize(s);
      if (n == null) throw GameError('桌面上存在不合法的组合：${s.map(rkLabel).join(' ')}');
      fixed.add(n);
    }
    if (!melded[seat]) {
      // Initial meld: only new sets made purely of own tiles; old sets untouched.
      final oldKeys = {for (final s in table) (List.of(s)..sort()).join(',')};
      var pts = 0;
      for (final s in fixed) {
        final key = (List.of(s)..sort()).join(',');
        if (oldKeys.contains(key)) continue;
        if (!s.every(added.contains)) throw GameError('首次出牌只能用自己的牌组成新组合，不能动桌面');
        pts += rkSetValue(s)!;
      }
      final untouched = table.every((s) => fixed.any((f) => (List.of(f)..sort()).join(',') == (List.of(s)..sort()).join(',')));
      if (!untouched) throw GameError('首次出牌不能改动桌面上的组合');
      if (pts < 30) throw GameError('首次出牌总点数需≥30（当前 $pts）');
      melded[seat] = true;
    }
    table = fixed;
    rack.removeWhere(added.contains);
    lastAdded = added;
    passes = 0;
    last = '${name(seat)} 打出 ${added.length} 张牌';
    host.log(last);
    if (rack.isEmpty) {
      over = true;
      winner = seat;
      final total = [for (var s = 0; s < players; s++) racks[s].fold<int>(0, (a, t) => a + rkPenalty(t))];
      finalScores = [for (var s = 0; s < players; s++) s == seat ? total.fold<int>(0, (a, b) => a + b) : -total[s]];
      host.log('${name(seat)} 出完所有牌，获胜！');
      last = '${name(seat)} 获胜！';
      return;
    }
    _next();
  }

  void _finishByWall() {
    over = true;
    final total = [for (var s = 0; s < players; s++) racks[s].fold<int>(0, (a, t) => a + rkPenalty(t))];
    var best = 0;
    for (var s = 1; s < players; s++) {
      if (total[s] < total[best]) best = s;
    }
    winner = best;
    finalScores = [for (var s = 0; s < players; s++) -total[s]];
    host.log('牌池耗尽，手牌点数最少的 ${name(best)} 获胜');
    last = '牌池耗尽，${name(best)} 获胜';
  }

  void _next() => turn = (turn + 1) % players;

  static String rkLabel(int t) => rkIsJoker(t) ? '鬼' : '${rkColorNames[rkColor(t)]}${rkNumber(t)}';

  @override
  Map<String, dynamic> view(int seat) => {
        'table': table,
        'rack': seat >= 0 && seat < players ? racks[seat] : [],
        'counts': [for (final r in racks) r.length],
        'melded': melded,
        'wall': wall.length,
        'turn': turn,
        'last': last,
        'lastAdded': lastAdded,
        'over': over,
        'winner': winner,
        'scores': finalScores,
        if (over) 'racks': racks,
      };

  // ---------------- bot ----------------

  /// All valid sets (runs of maximal length / groups) formable from [tiles].
  static List<List<int>> findSets(List<int> tiles) {
    final res = <List<int>>[];
    final jokers = [for (final t in tiles) if (rkIsJoker(t)) t];
    final byCN = <int, List<int>>{};
    for (final t in tiles) {
      if (!rkIsJoker(t)) byCN.putIfAbsent(rkColor(t) * 13 + rkNumber(t) - 1, () => []).add(t);
    }
    // runs
    for (var c = 0; c < 4; c++) {
      var n = 1;
      while (n <= 13) {
        if (!byCN.containsKey(c * 13 + n - 1)) {
          n++;
          continue;
        }
        final run = <int>[];
        var m = n;
        while (m <= 13 && byCN.containsKey(c * 13 + m - 1)) {
          run.add(byCN[c * 13 + m - 1]!.first);
          m++;
        }
        if (run.length >= 3) {
          res.add(run);
        } else if (jokers.isNotEmpty && run.length == 2) {
          res.add(rkNormalize([...run, jokers.first])!);
        }
        n = m;
      }
    }
    // groups
    for (var n = 1; n <= 13; n++) {
      final g = <int>[];
      for (var c = 0; c < 4; c++) {
        final l = byCN[c * 13 + n - 1];
        if (l != null) g.add(l.first);
      }
      if (g.length >= 3) {
        res.add(g);
      } else if (g.length == 2 && jokers.isNotEmpty) {
        res.add([...g, jokers.first]);
      }
    }
    return res;
  }

  /// Greedy: pick disjoint sets with highest value.
  static List<List<int>> greedyMeld(List<int> rack) {
    final chosen = <List<int>>[];
    var remaining = List.of(rack);
    while (true) {
      final sets = findSets(remaining);
      if (sets.isEmpty) break;
      sets.sort((a, b) => rkSetValue(b)!.compareTo(rkSetValue(a)!));
      final s = sets.first;
      chosen.add(s);
      remaining = [for (final t in remaining) if (!s.contains(t)) t];
    }
    return chosen;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final rack = racks[seat];
    final lvl = botLevel;
    // 简单：经常直接摸牌，也不会往桌面接牌
    if (lvl == 0 && wall.isNotEmpty && rng.nextDouble() < 0.4) return {'type': 'draw'};
    final sets = lvl == 2 ? bestMeld(rack) : greedyMeld(rack);
    final newTable = [for (final s in table) List.of(s)];
    if (!melded[seat]) {
      final pts = sets.fold<int>(0, (a, s) => a + rkSetValue(s)!);
      if (pts >= 30) return {'type': 'submit', 'table': [...newTable, ...sets]};
      return {'type': 'draw'};
    }
    if (lvl == 0) {
      if (sets.isEmpty) return {'type': 'draw'};
      return {'type': 'submit', 'table': [...newTable, sets.first]};
    }
    newTable.addAll(sets);
    final used = {for (final s in sets) ...s};
    // add single tiles to table set ends (困难：还会拆开顺子把牌插进中间、从四张同数组借牌)
    var changed = true;
    while (changed) {
      changed = false;
      for (final t in rack) {
        if (used.contains(t)) continue;
        for (var i = 0; i < newTable.length; i++) {
          final s = newTable[i];
          List<int>? ok;
          for (final cand in [
            [...s, t],
            [t, ...s]
          ]) {
            if (rkValid(cand)) {
              ok = cand;
              break;
            }
          }
          if (ok != null) {
            newTable[i] = ok;
            used.add(t);
            changed = true;
            break;
          }
          if (lvl == 2) {
            final split = _splitRun(s, t);
            if (split != null) {
              newTable[i] = split.$1;
              newTable.add(split.$2);
              used.add(t);
              changed = true;
              break;
            }
          }
        }
      }
    }
    if (used.isEmpty) return {'type': 'draw'};
    return {'type': 'submit', 'table': newTable};
  }

  /// Inserting a duplicate tile into the middle of a run splits it into two
  /// valid runs (e.g. 红3-7 + 红5 → 红3-5 与 红5-7).
  static (List<int>, List<int>)? _splitRun(List<int> run, int t) {
    if (rkIsJoker(t) || run.length < 5) return null;
    for (var k = 2; k <= run.length - 3; k++) {
      final a = [...run.sublist(0, k + 1)];
      final b = [t, ...run.sublist(k + 1)];
      if (rkValid(a) && rkValid(b)) return (a, b);
    }
    return null;
  }

  /// 困难：在所有可组的牌组里搜索（有限深度）使打出的牌数/点数最多的不重叠组合。
  static List<List<int>> bestMeld(List<int> rack) {
    var best = greedyMeld(rack);
    int value(List<List<int>> m) => m.fold<int>(0, (a, s) => a + s.length * 100 + rkSetValue(s)!);
    var bestV = value(best);
    var budget = 4000;
    void go(List<int> remaining, List<List<int>> chosen) {
      if (budget-- <= 0) return;
      final v = value(chosen);
      if (v > bestV) {
        bestV = v;
        best = [for (final s in chosen) List.of(s)];
      }
      final sets = findSets(remaining);
      // also consider trimmed runs (length 3 prefixes/suffixes) to free tiles for groups
      final cands = <List<int>>[...sets];
      for (final s in sets) {
        if (s.length > 3 && s.every((t) => !rkIsJoker(t))) {
          for (var i = 0; i + 3 <= s.length; i++) {
            final sub = s.sublist(i, i + 3);
            if (rkValid(sub)) cands.add(sub);
          }
        }
      }
      for (final s in cands) {
        go([for (final t in remaining) if (!s.contains(t)) t], [...chosen, s]);
        if (budget <= 0) return;
      }
    }

    go(List.of(rack), []);
    return best;
  }
}
