import 'dart:collection';

import '../../src/engine.dart';

/// 跳棋 star-board geometry (shared with the client).
///
/// Axial coordinates (q, r), s = -q-r. The star is the union of two big
/// triangles; 121 holes. Corners in clockwise order from the top:
/// 0 top (r<-4), 1 upper-right (q>4), 2 lower-right (s<-4),
/// 3 bottom (r>4), 4 lower-left (q<-4), 5 upper-left (s>4).
class CCGeo {
  static final List<(int, int)> cells = _build();
  static final Map<int, int> _index = {
    for (var i = 0; i < cells.length; i++) _key(cells[i].$1, cells[i].$2): i,
  };
  static final List<List<int>> corners = [
    for (var k = 0; k < 6; k++) [for (var i = 0; i < cells.length; i++) if (cornerOf(i) == k) i],
  ];
  static const List<(int, int)> dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)];

  static int _key(int q, int r) => (q + 20) * 100 + (r + 20);

  static List<(int, int)> _build() {
    final out = <(int, int)>[];
    for (var r = -8; r <= 8; r++) {
      for (var q = -8; q <= 8; q++) {
        final s = -q - r;
        final a = q <= 4 && r <= 4 && s <= 4;
        final b = q >= -4 && r >= -4 && s >= -4;
        if (a || b) out.add((q, r));
      }
    }
    return out;
  }

  static int? at(int q, int r) => _index[_key(q, r)];

  static int cornerOf(int i) {
    final (q, r) = cells[i];
    final s = -q - r;
    if (r < -4) return 0;
    if (q > 4) return 1;
    if (s < -4) return 2;
    if (r > 4) return 3;
    if (q < -4) return 4;
    if (s > 4) return 5;
    return -1;
  }

  static int dist(int a, int b) {
    final (q1, r1) = cells[a];
    final (q2, r2) = cells[b];
    final dq = q1 - q2, dr = r1 - r2;
    return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2;
  }

  /// The tip hole of corner k (farthest from the centre).
  static int tip(int k) {
    var best = corners[k].first;
    for (final i in corners[k]) {
      if (_norm(i) > _norm(best)) best = i;
    }
    return best;
  }

  static int _norm(int i) {
    final (q, r) = cells[i];
    return (q.abs() + r.abs() + (q + r).abs()) ~/ 2;
  }

  /// Pixel-ish position (x, y) with unit spacing between neighbours.
  static (double, double) xy(int i) {
    final (q, r) = cells[i];
    return (q + r / 2, r * 0.8660254037844386);
  }

  /// Home corners for [players] players.
  static List<int> homes(int players) => switch (players) {
        2 => [0, 3],
        3 => [0, 2, 4],
        4 => [1, 2, 4, 5],
        5 => [0, 1, 2, 3, 4],
        _ => [0, 1, 2, 3, 4, 5],
      };
}

class ChineseCheckers extends GameEngine {
  ChineseCheckers(super.setup);

  final List<int> board = List.filled(CCGeo.cells.length, -1);
  late final List<int> home = CCGeo.homes(players);
  late final List<int> target = [for (final h in home) (h + 3) % 6];
  late final List<int> tips = [for (final t in target) CCGeo.tip(t)];
  late final int cap = players * 100 < 400 ? 400 : players * 100;
  int turn = 0;
  int turns = 0;
  int winner = -1;
  List<int> lastPath = [];
  int lastSeat = -1;
  bool capped = false;
  bool drawn = false;

  /// Seats that resigned, in order; their marbles are taken off the board.
  final List<int> resigned = [];

  bool active(int s) => !resigned.contains(s);

  /// Progress score used for the step cap and for placings.
  int progress(int s) => inTarget(s) * 1000 - _distSum(s);

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (drawn) return List.filled(players, 1);
    final score = <num>[
      for (var s = 0; s < players; s++)
        s == winner
            ? 1 << 30
            : resigned.contains(s)
                ? -(1 << 20) + resigned.indexOf(s)
                : progress(s),
    ];
    return rankByScore(score);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat >= players || !active(seat)) return;
    resigned.add(seat);
    for (var i = 0; i < board.length; i++) {
      if (board[i] == seat) board[i] = -1;
    }
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (active(s)) s];
    if (left.length == 1) {
      winner = left.first;
      host.log('${name(winner)} 获胜！');
      return;
    }
    if (turn == seat) _advance();
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) return;
    drawn = true;
    host.log('同意和棋');
  }

  @override
  void start() {
    for (var s = 0; s < players; s++) {
      for (final i in CCGeo.corners[home[s]]) {
        board[i] = s;
      }
    }
    turn = rng.nextInt(players);
    host.log('${name(turn)} 先行');
  }

  @override
  bool get isOver => winner >= 0 || drawn;

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  /// All destinations reachable from [from] with the predecessor map for paths.
  Map<int, int> reach(int from) {
    final prev = <int, int>{};
    final (q, r) = CCGeo.cells[from];
    for (final (dq, dr) in CCGeo.dirs) {
      final n = CCGeo.at(q + dq, r + dr);
      if (n != null && board[n] < 0) prev[n] = from;
    }
    final seen = <int>{from};
    final queue = Queue<int>()..add(from);
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      final (cq, cr) = CCGeo.cells[c];
      for (final (dq, dr) in CCGeo.dirs) {
        final over = CCGeo.at(cq + dq, cr + dr);
        final land = CCGeo.at(cq + 2 * dq, cr + 2 * dr);
        if (over == null || land == null) continue;
        if (board[over] < 0 || (board[land] >= 0 && land != from)) continue;
        if (seen.contains(land)) continue;
        seen.add(land);
        prev.putIfAbsent(land, () => c);
        queue.add(land);
      }
    }
    prev.remove(from);
    return prev;
  }

  List<int> _path(Map<int, int> prev, int from, int to) {
    final out = [to];
    var c = to;
    var guard = 0;
    while (c != from && guard++ < 200) {
      c = prev[c]!;
      out.add(c);
    }
    return out.reversed.toList();
  }

  int inTarget(int s) => CCGeo.corners[target[s]].where((i) => board[i] == s).length;

  bool _won(int s) {
    final t = CCGeo.corners[target[s]];
    return t.every((i) => board[i] >= 0) && t.any((i) => board[i] == s);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final from = asInt(a['from']);
    final to = asInt(a['to']);
    if (from < 0 || from >= board.length || board[from] != seat) throw GameError('请选择自己的棋子');
    if (to < 0 || to >= board.length) throw GameError('无效位置');
    final prev = reach(from);
    if (!prev.containsKey(to)) throw GameError('无法到达该位置');
    lastPath = _path(prev, from, to);
    lastSeat = seat;
    board[from] = -1;
    board[to] = seat;
    turns++;
    if (_won(seat)) {
      winner = seat;
      host.log('${name(seat)} 全部棋子进入对面营地，获胜！');
      return;
    }
    if (turns >= cap) {
      capped = true;
      var best = -1;
      for (var s = 0; s < players; s++) {
        if (active(s) && (best < 0 || progress(s) > progress(best))) best = s;
      }
      winner = best;
      host.log('已达 $cap 步上限，${name(best)} 进入营地棋子最多，获胜');
      return;
    }
    _advance();
  }

  bool _hasMove(int s) {
    for (var i = 0; i < board.length; i++) {
      if (board[i] == s && reach(i).isNotEmpty) return true;
    }
    return false;
  }

  void _advance() {
    for (var k = 0; k < players; k++) {
      turn = (turn + 1) % players;
      if (!active(turn)) continue;
      if (_hasMove(turn)) return;
      host.log('${name(turn)} 无路可走，跳过');
    }
  }

  int _distSum(int s) {
    var sum = 0;
    for (var i = 0; i < board.length; i++) {
      if (board[i] == s) sum += CCGeo.dist(i, tips[s]);
    }
    return sum;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'board': board,
        'home': home,
        'target': target,
        'turn': turn,
        'turns': turns,
        'cap': cap,
        'winner': winner,
        'capped': capped,
        'drawn': drawn,
        'resigned': resigned,
        'last': lastPath,
        'lastSeat': lastSeat,
        'inTarget': [for (var s = 0; s < players; s++) inTarget(s)],
      };

  @override
  int get botDelayMs => 500;

  @override
  Map<String, dynamic>? bot(int seat) {
    final tip = tips[seat];
    final tset = CCGeo.corners[target[seat]].toSet();
    final mine = [for (var i = 0; i < board.length; i++) if (board[i] == seat) i];
    var maxD = 0;
    for (final m in mine) {
      final d = CCGeo.dist(m, tip);
      if (d > maxD) maxD = d;
    }
    // Lateral-offset penalty keeps marbles on the central axis.
    double lateral(int i) {
      final (x1, y1) = CCGeo.xy(i);
      final (x2, y2) = CCGeo.xy(tip);
      final (x0, y0) = (0.0, 0.0);
      final dx = x2 - x0, dy = y2 - y0;
      final len = dx * dx + dy * dy;
      final cross = ((x1 - x0) * dy - (y1 - y0) * dx).abs();
      return len == 0 ? 0 : cross / 9.0;
    }

    // 简单: often a random forward-ish move
    if (botLevel <= 0 && rng.nextDouble() < 0.4) {
      final opts = <List<int>>[
        for (final m in mine)
          for (final to in reach(m).keys)
            if (CCGeo.dist(to, tip) <= CCGeo.dist(m, tip)) [m, to],
      ];
      if (opts.isNotEmpty) {
        final o = opts[rng.nextInt(opts.length)];
        return {'from': o[0], 'to': o[1]};
      }
    }
    final hard = botLevel >= 2;
    // 困难: one-ply lookahead — value of the best follow-up hop after this move
    int follow(int from, int to) {
      board[from] = -1;
      board[to] = seat;
      var bestGain = 0;
      for (var i = 0; i < board.length; i++) {
        if (board[i] != seat) continue;
        final d0 = CCGeo.dist(i, tip);
        for (final t2 in reach(i).keys) {
          final g = d0 - CCGeo.dist(t2, tip);
          if (g > bestGain) bestGain = g;
        }
      }
      board[to] = -1;
      board[from] = seat;
      return bestGain;
    }

    int? bf, bt;
    var best = -1e9;
    for (final m in mine) {
      final dFrom = CCGeo.dist(m, tip);
      for (final to in reach(m).keys) {
        final dTo = CCGeo.dist(to, tip);
        var sc = (dFrom - dTo) * 10.0;
        if (tset.contains(m) && !tset.contains(to)) sc -= 30;
        if (!tset.contains(m) && tset.contains(to)) sc += 4;
        sc += dFrom == maxD ? 3 : 0; // prefer moving stragglers
        sc += dFrom * 0.4;
        sc += (lateral(m) - lateral(to)) * 2;
        if (hard && dFrom - CCGeo.dist(to, tip) >= 0) sc += follow(m, to) * 3.0;
        sc += rng.nextDouble() * 0.5;
        if (sc > best) {
          best = sc;
          bf = m;
          bt = to;
        }
      }
    }
    if (bf == null) {
      // no legal move at all (virtually impossible) — pass by moving nothing is not allowed,
      // so pick any marble with any destination.
      for (final m in mine) {
        final r = reach(m);
        if (r.isNotEmpty) return {'from': m, 'to': r.keys.first};
      }
      return null;
    }
    return {'from': bf, 'to': bt};
  }
}
