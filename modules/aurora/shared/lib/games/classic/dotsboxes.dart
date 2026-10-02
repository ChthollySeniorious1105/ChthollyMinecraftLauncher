import 'dart:typed_data';

import '../../src/engine.dart';

/// 点格棋 geometry for an n×n box grid.
/// Horizontal edges: index r*n + c  (r 0..n, c 0..n-1).
/// Vertical edges:   H + r*(n+1) + c (r 0..n-1, c 0..n), H = n*(n+1).
class DBGeo {
  final int n;
  DBGeo(this.n);
  int get h => n * (n + 1);
  int get edges => 2 * n * (n + 1);
  int get boxes => n * n;

  List<int> boxEdges(int b) {
    final r = b ~/ n, c = b % n;
    return [r * n + c, (r + 1) * n + c, h + r * (n + 1) + c, h + r * (n + 1) + c + 1];
  }

  /// Boxes adjacent to edge e (1 or 2).
  List<int> edgeBoxes(int e) {
    if (e < h) {
      final r = e ~/ n, c = e % n;
      return [if (r > 0) (r - 1) * n + c, if (r < n) r * n + c];
    }
    final k = e - h, r = k ~/ (n + 1), c = k % (n + 1);
    return [if (c > 0) r * n + c - 1, if (c < n) r * n + c];
  }
}

class DotsBoxes extends GameEngine {
  DotsBoxes(super.setup);

  late final int n = setup.opt<int>('size', 4);
  late final DBGeo geo = DBGeo(n);
  late final List<int> edges = List.filled(geo.edges, -1); // seat who drew
  late final List<int> boxes = List.filled(geo.boxes, -1); // owner seat
  late final List<int> scores = List.filled(players, 0);
  int turn = 0;
  int lastEdge = -1;
  List<int> turnEdges = []; // edges drawn in the current / last turn
  int drawn = 0;
  List<int> winners = [];
  String result = '';
  String note = '';

  /// Ended early by 认输 / 求和 (placings set explicitly).
  List<int>? _forced;

  bool get over => _forced != null || drawn >= geo.edges;

  @override
  List<int>? get placings => !over ? null : (_forced ?? rankByScore(scores));

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不是玩家');
    // 认输者末名，其余按当前格子数排名
    final sc = [for (var s = 0; s < players; s++) s == seat ? -1 : scores[s]];
    _forced = rankByScore(sc);
    winners = [for (var s = 0; s < players; s++) if (_forced![s] == 1) s];
    result = '${name(seat)} 认输，${winners.map(name).join('、')} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;

  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    _forced = List.filled(players, 1);
    winners = [for (var s = 0; s < players; s++) s];
    result = '全体同意和棋';
    host.log(result);
  }

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    turn = rng.nextInt(players);
    host.log('点格棋 $n×$n：${name(turn)} 先手。围成格子可再走一步');
  }

  int sides(List<int> ed, int b) => geo.boxEdges(b).where((e) => ed[e] >= 0).length;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final e = asInt(a['edge']);
    if (e < 0 || e >= geo.edges || edges[e] >= 0) throw GameError('这条边不能画');
    if (lastEdge >= 0 && edges[lastEdge] != seat) turnEdges = [];
    edges[e] = seat;
    drawn++;
    lastEdge = e;
    turnEdges.add(e);
    var got = 0;
    for (final b in geo.edgeBoxes(e)) {
      if (sides(edges, b) == 4) {
        boxes[b] = seat;
        got++;
      }
    }
    scores[seat] += got;
    note = got > 0 ? '${name(seat)} 围成 $got 格，继续' : '';
    if (over) {
      final best = scores.reduce((x, y) => x > y ? x : y);
      winners = [for (var s = 0; s < players; s++) if (scores[s] == best) s];
      result = winners.length == 1
          ? '${name(winners.first)} 以 $best 格获胜'
          : '${winners.map(name).join('、')} 并列第一（$best 格）';
      host.log(result);
      return;
    }
    if (got == 0) {
      turn = (turn + 1) % players;
      turnEdges = [];
    }
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'size': n,
        'edges': edges,
        'boxes': boxes,
        'scores': scores,
        'turn': turn,
        'lastEdge': lastEdge,
        'turnEdges': turnEdges,
        'winners': winners,
        'result': result,
        'note': note,
        'over': over,
      };

  // ------------------------------------------------------------------ bot

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final ai = DotsAI(geo, edges);
    if (botLevel <= 0 && rng.nextDouble() < 0.5) {
      final free = [for (var x = 0; x < edges.length; x++) if (edges[x] < 0) x];
      return {'type': 'edge', 'edge': free[rng.nextInt(free.length)]};
    }
    if (botLevel >= 2 && players == 2) {
      final e = ai.solve(18);
      if (e >= 0) return {'type': 'edge', 'edge': e};
    }
    return {'type': 'edge', 'edge': ai.best(rng.nextInt(1 << 30))};
  }
}

class DotsAI {
  final DBGeo geo;
  final List<int> ed;
  DotsAI(this.geo, List<int> edges) : ed = List.of(edges);

  int _sides(List<int> e, int b) {
    var k = 0;
    for (final x in geo.boxEdges(b)) {
      if (e[x] >= 0) k++;
    }
    return k;
  }

  bool _completes(List<int> e, int edge) => geo.edgeBoxes(edge).any((b) => _sides(e, b) == 3);
  bool _safe(List<int> e, int edge) => geo.edgeBoxes(edge).every((b) => _sides(e, b) < 2);

  /// Boxes the side to move would grab greedily after [edge] is drawn (by the other side).
  int _giveaway(List<int> e0, int edge) {
    final e = List.of(e0);
    e[edge] = 0;
    var total = 0;
    while (true) {
      var found = -1;
      for (var x = 0; x < e.length; x++) {
        if (e[x] < 0 && _completes(e, x)) {
          found = x;
          break;
        }
      }
      if (found < 0) break;
      for (final b in geo.edgeBoxes(found)) {
        if (_sides(e, b) == 3) total++;
      }
      e[found] = 0;
    }
    return total;
  }

  int best(int seed) {
    final free = [for (var x = 0; x < ed.length; x++) if (ed[x] < 0) x];
    final capt = [for (final x in free) if (_completes(ed, x)) x];
    final safe = [for (final x in free) if (!_completes(ed, x) && _safe(ed, x)) x];
    if (capt.isNotEmpty) {
      if (safe.isEmpty) {
        final dd = _doubleDeal(capt);
        if (dd >= 0) return dd;
      }
      // prefer a capture that doesn't open something new
      return capt.first;
    }
    if (safe.isNotEmpty) return safe[seed % safe.length];
    // forced sacrifice: give away as little as possible
    var bestE = free.first, bestV = 1 << 30;
    for (final x in free) {
      final v = _giveaway(ed, x);
      if (v < bestV) {
        bestV = v;
        bestE = x;
      }
    }
    return bestE;
  }

  /// Exact two-player endgame solve when at most [maxFree] edges remain:
  /// memoised negamax over the set of drawn free edges. Returns -1 if too big.
  int solve(int maxFree) {
    final free = [for (var x = 0; x < ed.length; x++) if (ed[x] < 0) x];
    final k = free.length;
    if (k == 0 || k > maxFree) return -1;
    final bitOf = {for (var i = 0; i < k; i++) free[i]: i};
    // for each free edge: masks of the (undecided) boxes it touches
    final boxMasks = <List<int>>[];
    for (final e in free) {
      final ms = <int>[];
      for (final b in geo.edgeBoxes(e)) {
        var m = 0;
        for (final x in geo.boxEdges(b)) {
          final i = bitOf[x];
          if (i != null) m |= 1 << i;
        }
        ms.add(m);
      }
      boxMasks.add(ms);
    }
    final full = (1 << k) - 1;
    final memo = Int16List(1 << k)..fillRange(0, 1 << k, -32768);
    int v(int mask) {
      if (mask == full) return 0;
      final c = memo[mask];
      if (c != -32768) return c;
      var best = -1 << 20;
      for (var i = 0; i < k; i++) {
        final bit = 1 << i;
        if (mask & bit != 0) continue;
        final nm = mask | bit;
        var g = 0;
        for (final m in boxMasks[i]) {
          if (nm & m == m) g++;
        }
        final val = g > 0 ? g + v(nm) : -v(nm);
        if (val > best) best = val;
      }
      memo[mask] = best;
      return best;
    }

    var bestE = -1, bestV = -1 << 20;
    for (var i = 0; i < k; i++) {
      final nm = 1 << i;
      var g = 0;
      for (final m in boxMasks[i]) {
        if (nm & m == m) g++;
      }
      final val = g > 0 ? g + v(nm) : -v(nm);
      if (val > bestV) {
        bestV = val;
        bestE = free[i];
      }
    }
    return bestE;
  }

  /// Chain rule / double-dealing: when the only capturable run is a chain
  /// with exactly 2 boxes left and enough boxes remain elsewhere, decline the
  /// last two by drawing the far edge, keeping control.
  int _doubleDeal(List<int> capt) {
    final undecided = [for (var b = 0; b < geo.boxes; b++) if (_sides(ed, b) < 4) b].length;
    for (final e1 in capt) {
      final bs = geo.edgeBoxes(e1);
      if (bs.length != 2) continue;
      final s0 = _sides(ed, bs[0]), s1 = _sides(ed, bs[1]);
      int a, bb;
      if (s0 == 3 && s1 == 2) {
        a = bs[0];
        bb = bs[1];
      } else if (s1 == 3 && s0 == 2) {
        a = bs[1];
        bb = bs[0];
      } else {
        continue;
      }
      // A must have exactly one open edge (e1); B's other open edge e2
      final openB = [for (final x in geo.boxEdges(bb)) if (ed[x] < 0 && x != e1) x];
      if (openB.length != 1) continue;
      final e2 = openB.first;
      final beyond = geo.edgeBoxes(e2).where((x) => x != bb).toList();
      if (beyond.isNotEmpty && _sides(ed, beyond.first) >= 2) continue;
      // other capturable runs would be left for the opponent too: keep it simple
      if (capt.length > 1) return -1;
      if (undecided - 2 < 3) return -1;
      if (a < 0) return -1;
      return e2;
    }
    return -1;
  }
}
