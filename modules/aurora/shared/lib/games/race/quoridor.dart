import 'dart:collection';

import '../../src/engine.dart';

/// 路墙棋 (Quoridor).
///
/// Cells (r, c) 0..8. A wall at (r, c) with r, c in 0..7 sits on the
/// intersection below-right of cell (r, c):
///  * 'h' blocks moving between rows r and r+1 in columns c and c+1;
///  * 'v' blocks moving between columns c and c+1 in rows r and r+1.
class Quoridor extends GameEngine {
  Quoridor(super.setup);

  static const n = 9;
  static const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];

  /// side of the board each seat starts on: 0 bottom, 1 left, 2 top, 3 right
  late final List<int> sides = players == 2 ? [0, 2] : [0, 1, 2, 3].sublist(0, players);
  late final List<(int, int)> pawn = [for (final s in sides) _startOf(s)];
  late final List<int> wallsLeft = List.filled(players, switch (players) { 2 => 10, 3 => 7, _ => 5 });
  final Set<String> walls = {}; // "r,c,o"
  final List<List<Object>> wallList = [];
  int turn = 0;
  int turns = 0;
  int winner = -1;
  bool capped = false;
  bool drawn = false;

  /// Seats that resigned, in order (multi-player: they drop out, pawn stays as an obstacle).
  final List<int> resigned = [];
  Map<String, dynamic>? last;
  static const cap = 400;

  static (int, int) _startOf(int side) => const [(8, 4), (4, 0), (0, 4), (4, 8)][side];

  bool atGoal(int seat, (int, int) p) => switch (sides[seat]) {
        0 => p.$1 == 0,
        1 => p.$2 == 8,
        2 => p.$1 == 8,
        _ => p.$2 == 0,
      };

  @override
  void start() {
    turn = 0;
    host.log('${name(turn)} 先行');
  }

  @override
  bool get isOver => winner >= 0 || drawn;

  bool active(int s) => !resigned.contains(s);

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (drawn) return List.filled(players, 1);
    // winner first, then remaining players by distance to goal, resigned last (earliest resign = worst)
    final score = <num>[
      for (var s = 0; s < players; s++)
        s == winner
            ? -1
            : resigned.contains(s)
                ? 10000 - resigned.indexOf(s)
                : dist(s, pawn[s]),
    ];
    return rankByScore(score, lowWins: true);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat >= players || !active(seat)) return;
    resigned.add(seat);
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (active(s)) s];
    if (left.length == 1) {
      winner = left.first;
      host.log('${name(winner)} 获胜！');
      return;
    }
    if (turn == seat) _nextTurn();
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) return;
    drawn = true;
    host.log('同意和棋');
  }

  void _nextTurn() {
    do {
      turn = (turn + 1) % players;
    } while (!active(turn));
  }

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  static bool _in(int r, int c) => r >= 0 && r < n && c >= 0 && c < n;

  /// Is the step from (r,c) by (dr,dc) blocked by a wall (or the edge)?
  bool blocked(int r, int c, int dr, int dc, [Set<String>? ws]) {
    final w = ws ?? walls;
    final nr = r + dr, nc = c + dc;
    if (!_in(nr, nc)) return true;
    if (dr != 0) {
      final wr = dr > 0 ? r : nr; // wall row between wr and wr+1
      return w.contains('$wr,$c,h') || w.contains('$wr,${c - 1},h');
    } else {
      final wc = dc > 0 ? c : nc;
      return w.contains('$r,$wc,v') || w.contains('${r - 1},$wc,v');
    }
  }

  /// Shortest distance (ignoring pawns) from [from] to [seat]'s goal, or -1.
  int dist(int seat, (int, int) from, [Set<String>? ws]) {
    if (atGoal(seat, from)) return 0;
    final seen = List.filled(n * n, false);
    final q = Queue<((int, int), int)>()..add((from, 0));
    seen[from.$1 * n + from.$2] = true;
    while (q.isNotEmpty) {
      final ((r, c), d) = q.removeFirst();
      for (final (dr, dc) in dirs) {
        if (blocked(r, c, dr, dc, ws)) continue;
        final p = (r + dr, c + dc);
        final k = p.$1 * n + p.$2;
        if (seen[k]) continue;
        if (atGoal(seat, p)) return d + 1;
        seen[k] = true;
        q.add((p, d + 1));
      }
    }
    return -1;
  }

  int? _pawnAt(int r, int c) {
    for (var s = 0; s < players; s++) {
      if (pawn[s] == (r, c)) return s;
    }
    return null;
  }

  List<(int, int)> pawnMoves(int seat) {
    final (r, c) = pawn[seat];
    final out = <(int, int)>{};
    for (final (dr, dc) in dirs) {
      if (blocked(r, c, dr, dc)) continue;
      final nr = r + dr, nc = c + dc;
      if (_pawnAt(nr, nc) == null) {
        out.add((nr, nc));
        continue;
      }
      // jump straight
      if (!blocked(nr, nc, dr, dc) && _pawnAt(nr + dr, nc + dc) == null) {
        out.add((nr + dr, nc + dc));
        continue;
      }
      // diagonal
      for (final (pr, pc) in dirs) {
        if (pr == dr && pc == dc || pr == -dr && pc == -dc) continue;
        if (blocked(nr, nc, pr, pc)) continue;
        final tr = nr + pr, tc = nc + pc;
        if (_pawnAt(tr, tc) == null) out.add((tr, tc));
      }
    }
    return out.toList();
  }

  /// Returns an error message if the wall is illegal, else null.
  String? wallError(int r, int c, String o, [bool checkPaths = true]) {
    if (r < 0 || r > 7 || c < 0 || c > 7 || (o != 'h' && o != 'v')) return '无效的墙位置';
    if (walls.contains('$r,$c,h') || walls.contains('$r,$c,v')) return '墙不能重叠或交叉';
    if (o == 'h' && (walls.contains('$r,${c - 1},h') || walls.contains('$r,${c + 1},h'))) return '墙不能重叠';
    if (o == 'v' && (walls.contains('${r - 1},$c,v') || walls.contains('${r + 1},$c,v'))) return '墙不能重叠';
    if (!checkPaths) return null;
    final ws = {...walls, '$r,$c,$o'};
    for (var s = 0; s < players; s++) {
      if (active(s) && dist(s, pawn[s], ws) < 0) return '不能完全堵死任何棋子的去路';
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final t = asStr(a['t']);
    final r = asInt(a['r']), c = asInt(a['c']);
    if (t == 'move') {
      if (!pawnMoves(seat).contains((r, c))) throw GameError('不能移动到那里');
      last = {'t': 'move', 'seat': seat, 'from': [pawn[seat].$1, pawn[seat].$2], 'to': [r, c]};
      pawn[seat] = (r, c);
      if (atGoal(seat, (r, c))) {
        winner = seat;
        host.log('${name(seat)} 到达终点，获胜！');
        return;
      }
    } else if (t == 'wall') {
      if (wallsLeft[seat] <= 0) throw GameError('你的墙已用完');
      final o = asStr(a['o']);
      final err = wallError(r, c, o);
      if (err != null) throw GameError(err);
      walls.add('$r,$c,$o');
      wallList.add([r, c, o, seat]);
      wallsLeft[seat]--;
      last = {'t': 'wall', 'seat': seat, 'wall': [r, c, o]};
    } else if (t == 'pass') {
      if (pawnMoves(seat).isNotEmpty || _anyWall(seat)) throw GameError('还有可行的操作，不能跳过');
      last = {'t': 'pass', 'seat': seat};
    } else {
      throw GameError('未知操作');
    }
    turns++;
    if (turns >= cap) {
      capped = true;
      var best = -1;
      for (var s = 0; s < players; s++) {
        if (active(s) && (best < 0 || dist(s, pawn[s]) < dist(best, pawn[best]))) best = s;
      }
      winner = best;
      host.log('已达 $cap 步上限，${name(best)} 离终点最近，获胜');
      return;
    }
    _nextTurn();
  }

  bool _anyWall(int seat) {
    if (wallsLeft[seat] <= 0) return false;
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        for (final o in const ['h', 'v']) {
          if (wallError(r, c, o) == null) return true;
        }
      }
    }
    return false;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'pawns': [for (final p in pawn) [p.$1, p.$2]],
        'sides': sides,
        'walls': wallList,
        'wallsLeft': wallsLeft,
        'turn': turn,
        'turns': turns,
        'cap': cap,
        'winner': winner,
        'capped': capped,
        'drawn': drawn,
        'resigned': resigned,
        'last': last,
        'moves': isOver ? [] : [for (final m in pawnMoves(turn)) [m.$1, m.$2]],
        'dist': [for (var s = 0; s < players; s++) dist(s, pawn[s])],
      };

  @override
  int get botDelayMs => 600;

  @override
  Map<String, dynamic>? bot(int seat) {
    final myD = dist(seat, pawn[seat]);
    // 简单: frequently a random legal pawn step, rarely walls
    if (botLevel <= 0 && rng.nextDouble() < 0.45) {
      final ms = pawnMoves(seat);
      if (ms.isNotEmpty) {
        final m = ms[rng.nextInt(ms.length)];
        return {'t': 'move', 'r': m.$1, 'c': m.$2};
      }
    }
    var leader = -1, leadD = 999;
    for (var s = 0; s < players; s++) {
      if (s == seat || !active(s)) continue;
      final d = dist(s, pawn[s]);
      if (d < leadD) {
        leadD = d;
        leader = s;
      }
    }
    // consider a wall when the leading opponent is ahead (or about to win)
    final hard = botLevel >= 2;
    final behind = leadD < myD || (leadD == myD && (hard || (players == 2 && leadD <= 4)));
    final wallOk = botLevel > 0 || rng.nextDouble() < 0.3;
    if (wallOk && wallsLeft[seat] > 0 && leader >= 0 && (behind || leadD <= (hard ? 3 : 2))) {
      String? bestW;
      var bestGain = 0.0;
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          for (final o in const ['h', 'v']) {
            if (wallError(r, c, o, false) != null) continue;
            final ws = {...walls, '$r,$c,$o'};
            final ld = dist(leader, pawn[leader], ws);
            if (ld < 0) continue;
            final md = dist(seat, pawn[seat], ws);
            if (md < 0) continue;
            var ok = true;
            for (var s = 0; s < players && ok; s++) {
              if (s != seat && s != leader && active(s) && dist(s, pawn[s], ws) < 0) ok = false;
            }
            if (!ok) continue;
            var gain = (ld - leadD) - (md - myD) * (hard ? 1.0 : 1.2) + rng.nextDouble() * 0.3;
            if (hard) {
              // also count the hindrance to the other opponents
              for (var s = 0; s < players; s++) {
                if (s == seat || s == leader || !active(s)) continue;
                gain += (dist(s, pawn[s], ws) - dist(s, pawn[s])) * 0.3;
              }
            }
            if (gain > bestGain) {
              bestGain = gain;
              bestW = '$r,$c,$o';
            }
          }
        }
      }
      if (bestW != null && bestGain >= 1) {
        final p = bestW.split(',');
        return {'t': 'wall', 'r': int.parse(p[0]), 'c': int.parse(p[1]), 'o': p[2]};
      }
    }
    final moves = pawnMoves(seat);
    if (moves.isEmpty) {
      // fully surrounded by pawns: must place a wall (any legal one)
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          for (final o in const ['h', 'v']) {
            if (wallsLeft[seat] > 0 && wallError(r, c, o) == null) return {'t': 'wall', 'r': r, 'c': c, 'o': o};
          }
        }
      }
      return {'t': 'pass'};
    }
    (int, int)? best;
    var bd = 1 << 30;
    for (final m in moves..shuffle(rng)) {
      final d = atGoal(seat, m) ? -1 : dist(seat, m);
      if (d >= 0 || atGoal(seat, m)) {
        if (d < bd) {
          bd = d;
          best = m;
        }
      }
    }
    best ??= moves.first;
    return {'t': 'move', 'r': best.$1, 'c': best.$2};
  }
}
