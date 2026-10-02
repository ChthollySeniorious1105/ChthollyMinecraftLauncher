// 围棋棋盘：伪气（pseudo-liberty）增量实现，支持快速随机对局（light playout）。
// 颜色：0 空，1 黑，2 白。

import 'dart:math';

final Map<int, List<List<int>>> _adjCache = {};
final Map<int, List<List<int>>> _diagCache = {};

List<List<int>> _table(int n, List<List<int>> d) => [
      for (var p = 0; p < n * n; p++)
        [
          for (final o in d)
            if (p % n + o[0] >= 0 && p % n + o[0] < n && p ~/ n + o[1] >= 0 && p ~/ n + o[1] < n) p + o[0] + o[1] * n
        ]
    ];

class GoBoard {
  final int n;
  final List<int> col, rep, nxt, plib, gsize;
  final List<int> emp, empIdx;
  late final List<List<int>> adj, diag;
  int ko = -1;

  GoBoard(this.n)
      : col = List<int>.filled(n * n, 0),
        rep = List<int>.filled(n * n, 0),
        nxt = List<int>.filled(n * n, 0),
        plib = List<int>.filled(n * n, 0),
        gsize = List<int>.filled(n * n, 0),
        emp = List<int>.generate(n * n, (i) => i),
        empIdx = List<int>.generate(n * n, (i) => i) {
    adj = _adjCache.putIfAbsent(n, () => _table(n, const [[1, 0], [-1, 0], [0, 1], [0, -1]]));
    diag = _diagCache.putIfAbsent(n, () => _table(n, const [[1, 1], [-1, 1], [1, -1], [-1, -1]]));
  }

  GoBoard._copy(GoBoard o)
      : n = o.n,
        col = List<int>.of(o.col),
        rep = List<int>.of(o.rep),
        nxt = List<int>.of(o.nxt),
        plib = List<int>.of(o.plib),
        gsize = List<int>.of(o.gsize),
        emp = List<int>.of(o.emp),
        empIdx = List<int>.of(o.empIdx),
        ko = o.ko {
    adj = o.adj;
    diag = o.diag;
  }

  GoBoard copy() => GoBoard._copy(this);

  int get nn => n * n;
  int get emptyCount => emp.length;

  String key() => String.fromCharCodes([for (final c in col) 48 + c]);

  void _empRemove(int p) {
    final i = empIdx[p];
    final last = emp.removeLast();
    if (last != p) {
      emp[i] = last;
      empIdx[last] = i;
    }
  }

  void _empAdd(int p) {
    empIdx[p] = emp.length;
    emp.add(p);
  }

  int _adjCount(int p, int r) {
    var k = 0;
    for (final q in adj[p]) {
      if (col[q] != 0 && rep[q] == r) k++;
    }
    return k;
  }

  bool isLegal(int p, int c) {
    if (col[p] != 0 || p == ko) return false;
    for (final q in adj[p]) {
      if (col[q] == 0) return true;
    }
    for (final q in adj[p]) {
      final r = rep[q];
      final k = _adjCount(p, r);
      if (col[q] == c) {
        if (plib[r] > k) return true;
      } else if (plib[r] == k) {
        return true; // captures
      }
    }
    return false;
  }

  /// Would this be suicide (ignoring ko)? Used for error messages.
  bool isSuicide(int p, int c) {
    final k = ko;
    ko = -1;
    final ok = isLegal(p, c);
    ko = k;
    return !ok;
  }

  /// All orthogonal neighbours are colour [c].
  bool eyeish(int p, int c) {
    for (final q in adj[p]) {
      if (col[q] != c) return false;
    }
    return true;
  }

  /// Eye-like point that is not a false eye.
  bool isEye(int p, int c) {
    if (col[p] != 0 || !eyeish(p, c)) return false;
    final o = 3 - c;
    var bad = 0;
    for (final q in diag[p]) {
      if (col[q] == o) bad++;
    }
    final edge = adj[p].length < 4;
    return edge ? bad == 0 : bad < 2;
  }

  /// Plays a legal move; returns number of stones captured.
  int play(int p, int c) {
    _empRemove(p);
    col[p] = c;
    rep[p] = p;
    nxt[p] = p;
    gsize[p] = 1;
    plib[p] = 0;
    for (final q in adj[p]) {
      if (col[q] == 0) {
        plib[p]++;
      } else if (q != p) {
        plib[rep[q]]--;
      }
    }
    for (final q in adj[p]) {
      if (col[q] == c && rep[q] != rep[p]) _merge(rep[p], rep[q]);
    }
    var captured = 0, capPoint = -1;
    final o = 3 - c;
    for (final q in adj[p]) {
      if (col[q] == o && plib[rep[q]] == 0) {
        capPoint = q;
        captured += _remove(rep[q]);
      }
    }
    final r = rep[p];
    ko = (captured == 1 && gsize[r] == 1 && plib[r] == 1) ? capPoint : -1;
    return captured;
  }

  void pass() => ko = -1;

  void _merge(int a, int b) {
    if (gsize[a] < gsize[b]) {
      final t = a;
      a = b;
      b = t;
    }
    var s = b;
    do {
      rep[s] = a;
      s = nxt[s];
    } while (s != b);
    final t = nxt[a];
    nxt[a] = nxt[b];
    nxt[b] = t;
    gsize[a] += gsize[b];
    plib[a] += plib[b];
  }

  int _remove(int r) {
    final stones = stonesOf(r);
    for (final s in stones) {
      col[s] = 0;
      _empAdd(s);
    }
    for (final s in stones) {
      for (final q in adj[s]) {
        if (col[q] != 0) plib[rep[q]]++;
      }
    }
    return stones.length;
  }

  List<int> stonesOf(int r) {
    final out = <int>[];
    var s = r;
    do {
      out.add(s);
      s = nxt[s];
    } while (s != r);
    return out;
  }

  /// Exact liberties of the group with representative [r].
  Set<int> libsOf(int r) {
    final out = <int>{};
    var s = r;
    do {
      for (final q in adj[s]) {
        if (col[q] == 0) out.add(q);
      }
      s = nxt[s];
    } while (s != r);
    return out;
  }

  /// Plays random non-eye-filling moves until both sides pass.
  /// Returns ownership per point: 1 black, 2 white, 0 none.
  List<int> playout(int toMove, Random rng, int maxMoves) {
    var c = toMove, passes = 0, moves = 0;
    while (passes < 2 && moves < maxMoves) {
      final m = _randomMove(c, rng);
      if (m < 0) {
        passes++;
        ko = -1;
      } else {
        passes = 0;
        play(m, c);
      }
      c = 3 - c;
      moves++;
    }
    return [
      for (var p = 0; p < nn; p++)
        col[p] != 0
            ? col[p]
            : (eyeish(p, 1) ? 1 : (eyeish(p, 2) ? 2 : 0))
    ];
  }

  int _randomMove(int c, Random rng) {
    final len = emp.length;
    if (len == 0) return -1;
    final start = rng.nextInt(len);
    for (var i = 0; i < len; i++) {
      final p = emp[(start + i) % len];
      if (isEye(p, c)) continue;
      if (!isLegal(p, c)) continue;
      // avoid big self-atari in playouts (cheap check: single remaining liberty)
      return p;
    }
    return -1;
  }
}

/// Standard handicap points for board size [n].
List<int> handicapPoints(int n, int h) {
  if (h < 2) return const [];
  final d = n >= 13 ? 3 : 2;
  final lo = d, hi = n - 1 - d, mid = n ~/ 2;
  int pt(int x, int y) => y * n + x;
  // order: corners (BL-TR diagonal first), then center/sides
  final corners = [pt(hi, lo), pt(lo, hi), pt(hi, hi), pt(lo, lo)];
  final sidesLR = [pt(lo, mid), pt(hi, mid)];
  final sidesTB = [pt(mid, lo), pt(mid, hi)];
  final center = pt(mid, mid);
  switch (h) {
    case 2:
      return corners.sublist(0, 2);
    case 3:
      return corners.sublist(0, 3);
    case 4:
      return corners;
    case 5:
      return [...corners, center];
    case 6:
      return [...corners, ...sidesLR];
    case 7:
      return [...corners, ...sidesLR, center];
    case 8:
      return [...corners, ...sidesLR, ...sidesTB];
    default:
      return [...corners, ...sidesLR, ...sidesTB, center];
  }
}

/// Star points (hoshi) for drawing.
List<int> starPoints(int n) {
  if (n == 19) return handicapPoints(19, 9);
  if (n == 13) return handicapPoints(13, 5);
  if (n == 9) return handicapPoints(9, 5);
  return const [];
}

/// Area scoring. [dead] points are treated as removed (belonging to the opponent).
/// Returns (owner per point 0/1/2, blackArea, whiteArea).
(List<int>, int, int) areaScore(GoBoard b, Set<int> dead) {
  final n = b.n, nn = n * n;
  final c = [for (var p = 0; p < nn; p++) dead.contains(p) ? 0 : b.col[p]];
  final owner = List<int>.filled(nn, 0);
  final seen = List<bool>.filled(nn, false);
  for (var p = 0; p < nn; p++) {
    if (c[p] != 0) {
      owner[p] = c[p];
      continue;
    }
    if (seen[p]) continue;
    final region = <int>[];
    final stack = [p];
    seen[p] = true;
    var border = 0;
    while (stack.isNotEmpty) {
      final q = stack.removeLast();
      region.add(q);
      for (final r in b.adj[q]) {
        if (c[r] == 0) {
          if (!seen[r]) {
            seen[r] = true;
            stack.add(r);
          }
        } else {
          border |= c[r];
        }
      }
    }
    final o = border == 1 || border == 2 ? border : 0;
    for (final q in region) {
      owner[q] = o;
    }
  }
  var bl = 0, wh = 0;
  for (final o in owner) {
    if (o == 1) bl++;
    if (o == 2) wh++;
  }
  return (owner, bl, wh);
}

/// Monte-Carlo ownership in [-1, 1] (positive = black).
List<double> mcOwnership(GoBoard b, int toMove, Random rng, int playouts) {
  final acc = List<double>.filled(b.nn, 0);
  final maxMoves = b.nn * 3;
  for (var i = 0; i < playouts; i++) {
    final own = b.copy().playout(i.isEven ? toMove : 3 - toMove, rng, maxMoves);
    for (var p = 0; p < b.nn; p++) {
      if (own[p] == 1) acc[p] += 1;
      if (own[p] == 2) acc[p] -= 1;
    }
  }
  for (var p = 0; p < b.nn; p++) {
    acc[p] /= playouts;
  }
  return acc;
}

/// Estimates dead stones: groups whose stones are mostly owned by the opponent in playouts.
Set<int> estimateDead(GoBoard b, int toMove, Random rng) {
  final playouts = b.n >= 19 ? 48 : (b.n >= 13 ? 64 : 100);
  final own = mcOwnership(b, toMove, rng, playouts);
  final dead = <int>{};
  final done = <int>{};
  for (var p = 0; p < b.nn; p++) {
    if (b.col[p] == 0 || done.contains(b.rep[p])) continue;
    final r = b.rep[p];
    done.add(r);
    final stones = b.stonesOf(r);
    final sign = b.col[p] == 1 ? 1.0 : -1.0;
    var sum = 0.0;
    for (final s in stones) {
      sum += own[s] * sign;
    }
    if (sum / stones.length < -0.1) dead.addAll(stones);
  }
  return dead;
}
