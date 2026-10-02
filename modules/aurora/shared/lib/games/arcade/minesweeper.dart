import 'dart:math';

import '../../src/engine.dart';
import 'arcade_util.dart';

/// 扫雷竞速 (2-6 人). Not tick-based: everyone plays their own copy of the
/// same seeded board. A player's first click is always safe (if needed the
/// mines around it are moved in that player's copy, Windows-style).
/// First to clear wins; a mine hit eliminates (or, with the option, costs a
/// 10 s penalty). A 1 s clock drives the timer and the time cap.
class MinesweeperRace extends GameEngine {
  MinesweeperRace(super.setup);

  static const levels = {
    'easy': (9, 9, 10),
    'medium': (16, 16, 40),
    'hard': (30, 16, 99),
  };
  static const levelNames = {'easy': '初级', 'medium': '中级', 'hard': '高级'};
  static const penaltySec = 10;

  late int w, h, mineCount;
  late String level;
  late bool penaltyMode;
  late int maxSec;
  late List<bool> baseMines;
  late List<MsPlayer> ps;
  int sec = 0;
  int moves = 0;
  bool over = false;
  List<Map<String, dynamic>>? ranking;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? placingsOf(ranking, players) : null;

  int _resigns = 0;

  @override
  bool get canResign => !over;

  /// 认输 = eliminated now (ranked after everyone who didn't resign). If no
  /// more than one player is still in the race, the game ends.
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (p.resigned) throw GameError('你已认输');
    p
      ..resigned = true
      ..out = true
      ..outSec = sec;
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (!ps[s].resigned) s];
    if (left.length <= 1) {
      _finish(left.isEmpty ? '所有人都已认输' : '其他人都已认输');
    } else if (!ps.any((q) => !q.out && !q.done)) {
      _finish('所有人都已出局');
    }
  }

  @override
  int get botDelayMs => 700;

  @override
  void start() {
    level = setup.opt<String>('level', 'easy');
    if (!levels.containsKey(level)) level = 'easy';
    final (lw, lh, lm) = levels[level]!;
    w = lw;
    h = lh;
    mineCount = lm;
    penaltyMode = setup.opt<String>('hit', 'out') == 'penalty';
    maxSec = level == 'easy' ? 300 : (level == 'medium' ? 600 : 900);
    baseMines = List.filled(w * h, false);
    for (final i in shuffled(List.generate(w * h, (i) => i), rng).take(mineCount)) {
      baseMines[i] = true;
    }
    ps = [for (var s = 0; s < players; s++) MsPlayer(List.of(baseMines), w * h)];
    host.log('扫雷竞速开始（${levelNames[level]} $w×$h，$mineCount 颗雷）！所有人同一张雷图，最先扫完者获胜。'
        '${penaltyMode ? '踩雷罚时 $penaltySec 秒。' : '踩雷即出局。'}');
    host.schedule(1000, _clock);
  }

  int get safeCells => w * h - mineCount;

  void _clock() {
    if (over) return;
    sec++;
    if (sec >= maxSec) {
      _finish('时间到');
      return;
    }
    host.schedule(1000, _clock);
  }

  Iterable<int> neighbors(int i) sync* {
    final x = i % w, y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < w && ny < h) yield ny * w + nx;
      }
    }
  }

  int count(List<bool> mines, int i) => neighbors(i).where((j) => mines[j]).length;

  /// Moves mines away from [i] and its neighbours in [mines] (first click).
  void makeSafe(List<bool> mines, int i) {
    final zone = {i, ...neighbors(i)};
    final free = [for (var j = 0; j < w * h; j++) if (!mines[j] && !zone.contains(j)) j];
    for (final z in zone) {
      if (!mines[z]) continue;
      if (free.isEmpty) {
        if (z == i) {
          // tiny board edge case: at least keep the clicked cell safe
          final any = [for (var j = 0; j < w * h; j++) if (!mines[j] && j != i) j];
          if (any.isNotEmpty) {
            mines[any.first] = true;
            mines[i] = false;
          }
        }
        continue;
      }
      mines[free.removeAt(0)] = true;
      mines[z] = false;
    }
  }

  /// Reveals [i] for [p] (flood-filling zeros). Returns false on a mine.
  bool reveal(MsPlayer p, int i) {
    if (p.state[i] != 0) return true;
    if (p.mines[i]) {
      p.state[i] = 3;
      return false;
    }
    final stack = [i];
    while (stack.isNotEmpty) {
      final c = stack.removeLast();
      if (p.state[c] == 1) continue;
      if (p.state[c] == 2) continue; // keep flags
      p.state[c] = 1;
      p.opened++;
      if (count(p.mines, c) == 0) {
        for (final n in neighbors(c)) {
          if (p.state[n] == 0 && !p.mines[n]) stack.add(n);
        }
      }
    }
    return true;
  }

  bool active(int s) => !ps[s].out && !ps[s].done;

  @override
  List<int> get waitingFor => over ? const [] : rotated([for (var s = 0; s < players; s++) if (active(s)) s], moves);

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    final p = ps[seat];
    if (p.out) throw GameError('你已出局');
    if (p.done) throw GameError('你已完成');
    final x = asInt(a['x']), y = asInt(a['y']);
    if (x < 0 || y < 0 || x >= w || y >= h) throw GameError('坐标无效');
    final i = y * w + x;
    switch (type) {
      case 'reveal':
        if (p.state[i] == 2) throw GameError('已插旗，先取消旗子');
        if (p.state[i] != 0) throw GameError('该格已翻开');
        if (!p.started) {
          p.started = true;
          makeSafe(p.mines, i);
        }
        moves++;
        p.clicks++;
        if (!reveal(p, i)) _hit(seat, [i]);
      case 'flag':
        if (p.state[i] == 1 || p.state[i] == 3) throw GameError('该格已翻开');
        moves++;
        p.state[i] = p.state[i] == 2 ? 0 : 2;
      case 'chord':
        if (p.state[i] != 1) throw GameError('只能在已翻开的数字上双击');
        final ns = neighbors(i).toList();
        final flags = ns.where((n) => p.state[n] == 2 || p.state[n] == 3).length;
        if (flags != count(p.mines, i)) throw GameError('周围旗子数与数字不符');
        final hidden = ns.where((n) => p.state[n] == 0).toList();
        if (hidden.isEmpty) throw GameError('周围没有可翻开的格子');
        moves++;
        p.clicks++;
        final boom = <int>[];
        for (final n in hidden) {
          if (!reveal(p, n)) boom.add(n);
        }
        if (boom.isNotEmpty) _hit(seat, boom);
      default:
        throw GameError('未知操作');
    }
    _checkDone(seat);
  }

  void _hit(int seat, List<int> cells) {
    final p = ps[seat];
    p.hits += cells.length;
    p.lastHit = [moves, ...cells];
    if (penaltyMode) {
      p.penalty += penaltySec * cells.length;
      host.log('${name(seat)} 踩雷了！罚时 ${penaltySec * cells.length} 秒');
    } else {
      p.out = true;
      p.outSec = sec;
      host.log('${name(seat)} 踩雷了，出局！（进度 ${progress(seat)}%）');
    }
  }

  int progress(int s) => ps[s].opened * 100 ~/ safeCells;

  void _checkDone(int seat) {
    final p = ps[seat];
    if (!p.out && p.opened >= safeCells) {
      p.done = true;
      p.doneSec = sec + p.penalty;
      host.log('${name(seat)} 扫完了全部雷区！用时 ${p.doneSec} 秒');
      _finish('${name(seat)} 率先完成');
      return;
    }
    if (!ps.any((q) => !q.out && !q.done)) _finish('所有人都已出局');
  }

  void _finish(String why) {
    if (over) return;
    over = true;
    ranking = buildRanking(players, (a, b) {
      final pa = ps[a], pb = ps[b];
      if (pa.resignNo != pb.resignNo) return pa.resignNo == 0 ? -1 : (pb.resignNo == 0 ? 1 : pb.resignNo - pa.resignNo);
      if (pa.done != pb.done) return pa.done ? -1 : 1;
      if (pa.done) return pa.doneSec - pb.doneSec;
      if (pa.opened != pb.opened) return pb.opened - pa.opened;
      if (pa.out != pb.out) return pa.out ? 1 : -1;
      return pa.penalty - pb.penalty;
    }, (s) => {'pct': progress(s), 'done': ps[s].done, 'out': ps[s].out, 'time': ps[s].done ? ps[s].doneSec : null, 'hits': ps[s].hits});
    host.log('游戏结束（$why）！冠军：${winnersText(ranking!, name)}');
  }

  // ---------------------------------------------------------------- bot

  /// Picks a move using only [seat]'s own revealed cells. [level] 0 skips
  /// the subset rule, flags a lot and sometimes guesses despite a known safe
  /// cell; 2 never wastes moves on flags and guesses the least likely mine.
  Map<String, dynamic> botMove(int seat, {int level = 1}) {
    final p = ps[seat];
    int num(int i) => count(p.mines, i); // number shown on a revealed cell
    Map<String, dynamic> at(String t, int i) => {'type': t, 'x': i % w, 'y': i ~/ w};
    if (!p.started) return at('reveal', (h ~/ 2) * w + w ~/ 2);
    // flags placed by a human may be wrong; bots trust only exploded mines + own deductions
    final mine = <int>{for (var i = 0; i < w * h; i++) if (p.state[i] == 3) i};
    final safe = <int>{};
    for (var round = 0; round < 3 && safe.isEmpty; round++) {
      for (var i = 0; i < w * h; i++) {
        if (p.state[i] != 1) continue;
        final ns = neighbors(i).toList();
        final hid = [for (final n in ns) if ((p.state[n] == 0 || p.state[n] == 2) && !mine.contains(n)) n];
        if (hid.isEmpty) continue;
        final m = num(i) - ns.where(mine.contains).length;
        if (m == 0) {
          safe.addAll(hid);
        } else if (m == hid.length) {
          mine.addAll(hid);
        }
      }
    }
    // simple subset rule between neighbouring numbers
    if (safe.isEmpty && level > 0) {
      final cons = <(Set<int>, int)>[];
      for (var i = 0; i < w * h; i++) {
        if (p.state[i] != 1) continue;
        final ns = neighbors(i).toList();
        final hid = {for (final n in ns) if ((p.state[n] == 0 || p.state[n] == 2) && !mine.contains(n)) n};
        if (hid.isEmpty) continue;
        cons.add((hid, num(i) - ns.where(mine.contains).length));
      }
      outer:
      for (final (a, ma) in cons) {
        for (final (b, mb) in cons) {
          if (identical(a, b) || b.length <= a.length || !b.containsAll(a)) continue;
          final diff = b.difference(a);
          if (mb - ma == 0) {
            safe.addAll(diff);
            break outer;
          }
          if (mb - ma == diff.length) mine.addAll(diff);
        }
      }
    }
    safe.removeWhere((i) => p.state[i] == 1 || mine.contains(i));
    final blunder = level <= 0 && rng.nextInt(8) == 0;
    if (safe.isNotEmpty && !blunder) {
      final i = safe.reduce(min);
      if (p.state[i] == 2) return at('flag', i); // remove a wrong flag first
      return at('reveal', i);
    }
    // occasionally flag a deduced mine (looks human, helps chord)
    final unflagged = [for (final i in mine) if (p.state[i] == 0) i];
    if (unflagged.isNotEmpty && level < 2 && rng.nextInt(level <= 0 ? 2 : 3) == 0) return at('flag', unflagged[rng.nextInt(unflagged.length)]);
    // guess: prefer cells not adjacent to any number (fresh territory)
    final hidden = [for (var i = 0; i < w * h; i++) if (p.state[i] == 0 && !mine.contains(i)) i];
    if (hidden.isEmpty) {
      final flagged = [for (var i = 0; i < w * h; i++) if (p.state[i] == 2 && !mine.contains(i)) i];
      if (flagged.isNotEmpty) return at('flag', flagged.first);
      final anyHidden = [for (var i = 0; i < w * h; i++) if (p.state[i] == 0) i];
      if (anyHidden.isNotEmpty) return at('reveal', anyHidden.first);
      return {'type': 'idle'};
    }
    if (level >= 2) return at('reveal', _safestGuess(p, hidden, mine));
    final fresh = [for (final i in hidden) if (!neighbors(i).any((n) => p.state[n] == 1)) i];
    final pool = fresh.isNotEmpty && rng.nextBool() ? fresh : hidden;
    return at('reveal', pool[rng.nextInt(pool.length)]);
  }

  /// Hidden cell with the lowest estimated mine probability: the worst
  /// local ratio (remaining mines / hidden neighbours) of any adjacent
  /// number, or the global density for cells next to no number.
  int _safestGuess(MsPlayer p, List<int> hidden, Set<int> mine) {
    final unknown = [for (var i = 0; i < w * h; i++) if ((p.state[i] == 0 || p.state[i] == 2) && !mine.contains(i)) i];
    final density = unknown.isEmpty ? 1.0 : (mineCount - mine.length).clamp(0, unknown.length) / unknown.length;
    final prob = <int, double>{};
    for (var i = 0; i < w * h; i++) {
      if (p.state[i] != 1) continue;
      final ns = neighbors(i).toList();
      final hid = [for (final n in ns) if ((p.state[n] == 0 || p.state[n] == 2) && !mine.contains(n)) n];
      if (hid.isEmpty) continue;
      final r = (count(p.mines, i) - ns.where(mine.contains).length) / hid.length;
      for (final c in hid) {
        if ((prob[c] ?? -1) < r) prob[c] = r;
      }
    }
    var best = hidden.first;
    var bestP = 2.0;
    for (final c in shuffled(hidden, rng)) {
      final q = prob[c] ?? density;
      if (q < bestP - 1e-9) {
        bestP = q;
        best = c;
      }
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players || !active(seat)) return null;
    return botMove(seat, level: botLevel);
  }

  // ---------------------------------------------------------------- view

  /// Cell codes: '.' hidden, 'F' flag, '0'-'8' number, 'X' exploded mine,
  /// '*' mine (shown after the game / elimination), 'x' wrong flag.
  String board(int s) {
    final p = ps[s];
    final showAll = over || p.out || p.done;
    final b = StringBuffer();
    for (var i = 0; i < w * h; i++) {
      final st = p.state[i];
      if (st == 1) {
        b.write(count(p.mines, i));
      } else if (st == 3) {
        b.write('X');
      } else if (st == 2) {
        b.write(showAll && !p.mines[i] ? 'x' : 'F');
      } else {
        b.write(showAll && p.mines[i] ? '*' : '.');
      }
    }
    return b.toString();
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : 'play',
        'w': w,
        'h': h,
        'mines': mineCount,
        'level': level,
        'penalty': penaltyMode,
        'sec': sec,
        'max': maxSec,
        'board': seat >= 0 && seat < players ? board(seat) : null,
        'lastHit': seat >= 0 && seat < players ? ps[seat].lastHit : null,
        'ps': [
          for (var s = 0; s < players; s++)
            {
              'pct': progress(s),
              'out': ps[s].out,
              'done': ps[s].done,
              'pen': ps[s].penalty,
              'flags': ps[s].state.where((c) => c == 2).length,
              'time': ps[s].done ? ps[s].doneSec : null,
            },
        ],
        'final': ranking,
      };
}

class MsPlayer {
  final List<bool> mines;

  /// 0 hidden, 1 revealed, 2 flagged, 3 exploded mine.
  final List<int> state;
  bool started = false;
  bool out = false, done = false;
  int opened = 0, clicks = 0, hits = 0, penalty = 0;
  int doneSec = 0, outSec = 0;
  List<int>? lastHit;
  bool resigned = false;
  int resignNo = 0; // order of resigning (later = better placed)
  MsPlayer(this.mines, int n) : state = List.filled(n, 0);
}
