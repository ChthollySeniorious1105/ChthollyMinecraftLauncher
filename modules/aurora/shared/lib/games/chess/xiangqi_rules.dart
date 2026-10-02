// 中国象棋规则：走法生成、将军检测、评估与 alpha-beta 搜索。
// 棋盘 9 列 × 10 行，index = row*9 + col，row 0 为红方底线。红方 > 0，黑方 < 0。
// 1 帅/将, 2 仕/士, 3 相/象, 4 马, 5 车, 6 炮, 7 兵/卒。

import 'dart:math';

const int xK = 1, xA = 2, xB = 3, xN = 4, xR = 5, xC = 6, xP = 7;

int xFrom(int m) => m & 127;
int xTo(int m) => m >> 7;
int xMove(int f, int t) => f | (t << 7);

bool _inPalace(int r, int c, int side) => c >= 3 && c <= 5 && (side > 0 ? r <= 2 : r >= 7);

class XqPos {
  final List<int> b = List<int>.filled(90, 0);
  int side = 1;
  final List<int> kings = [4, 85];
  final List<int> _undo = [];

  static const startFen = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w';

  XqPos.initial() {
    _load(startFen);
  }
  XqPos.fen(String fen) {
    _load(fen);
  }

  void _load(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    b.fillRange(0, 90, 0);
    var r = 9, c = 0;
    for (final ch in parts[0].split('')) {
      if (ch == '/') {
        r--;
        c = 0;
      } else if (RegExp(r'\d').hasMatch(ch)) {
        c += int.parse(ch);
      } else {
        final t = 'kabnrcp'.indexOf(ch.toLowerCase()) + 1;
        final v = ch == ch.toUpperCase() ? t : -t;
        b[r * 9 + c] = v;
        if (v == xK) kings[0] = r * 9 + c;
        if (v == -xK) kings[1] = r * 9 + c;
        c++;
      }
    }
    side = parts.length > 1 && parts[1] == 'b' ? -1 : 1;
  }

  bool _own(int q, int s) => q != 0 && (q > 0) == (s > 0);

  /// Pseudo-legal moves for the side to move.
  void gen(List<int> out, {bool caps = false}) {
    final s = side;
    for (var sq = 0; sq < 90; sq++) {
      final p = b[sq];
      if (p == 0 || (p > 0) != (s > 0)) continue;
      final r = sq ~/ 9, c = sq % 9;
      void add(int tr, int tc) {
        if (tr < 0 || tr > 9 || tc < 0 || tc > 8) return;
        final t = tr * 9 + tc;
        final q = b[t];
        if (_own(q, s)) return;
        if (caps && q == 0) return;
        out.add(xMove(sq, t));
      }

      switch (p.abs()) {
        case xK:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            if (_inPalace(r + d[0], c + d[1], s)) add(r + d[0], c + d[1]);
          }
        case xA:
          for (final d in const [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
            if (_inPalace(r + d[0], c + d[1], s)) add(r + d[0], c + d[1]);
          }
        case xB:
          for (final d in const [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
            final tr = r + 2 * d[0], tc = c + 2 * d[1];
            if (tr < 0 || tr > 9 || tc < 0 || tc > 8) continue;
            if (s > 0 ? tr > 4 : tr < 5) continue; // 不能过河
            if (b[(r + d[0]) * 9 + c + d[1]] != 0) continue; // 塞象眼
            add(tr, tc);
          }
        case xN:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            final lr = r + d[0], lc = c + d[1];
            if (lr < 0 || lr > 9 || lc < 0 || lc > 8) continue;
            if (b[lr * 9 + lc] != 0) continue; // 蹩马腿
            if (d[0] != 0) {
              add(r + 2 * d[0], c + 1);
              add(r + 2 * d[0], c - 1);
            } else {
              add(r + 1, c + 2 * d[1]);
              add(r - 1, c + 2 * d[1]);
            }
          }
        case xR:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            var tr = r + d[0], tc = c + d[1];
            while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
              final q = b[tr * 9 + tc];
              if (q == 0) {
                if (!caps) out.add(xMove(sq, tr * 9 + tc));
              } else {
                if (!_own(q, s)) out.add(xMove(sq, tr * 9 + tc));
                break;
              }
              tr += d[0];
              tc += d[1];
            }
          }
        case xC:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            var tr = r + d[0], tc = c + d[1];
            var screen = false;
            while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
              final q = b[tr * 9 + tc];
              if (!screen) {
                if (q == 0) {
                  if (!caps) out.add(xMove(sq, tr * 9 + tc));
                } else {
                  screen = true;
                }
              } else if (q != 0) {
                if (!_own(q, s)) out.add(xMove(sq, tr * 9 + tc));
                break;
              }
              tr += d[0];
              tc += d[1];
            }
          }
        case xP:
          final fwd = s > 0 ? 1 : -1;
          add(r + fwd, c);
          final crossed = s > 0 ? r >= 5 : r <= 4;
          if (crossed) {
            add(r, c - 1);
            add(r, c + 1);
          }
      }
    }
  }

  /// Is the king of side [s] attacked (including flying general)?
  bool kingAttacked(int s) {
    final k = kings[s > 0 ? 0 : 1];
    final kr = k ~/ 9, kc = k % 9;
    final e = -s;
    // rook / cannon / flying general along lines
    for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      var tr = kr + d[0], tc = kc + d[1];
      var screens = 0;
      while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
        final q = b[tr * 9 + tc];
        if (q != 0) {
          if (screens == 0) {
            if (q == xR * e || (q == xK * e && d[1] == 0)) return true;
            if (q == xP * e && d[1] == 0 && tr == kr + (s > 0 ? 1 : -1)) return true;
          } else if (screens == 1) {
            if (q == xC * e) return true;
            break;
          }
          screens++;
        }
        tr += d[0];
        tc += d[1];
      }
    }
    // pawns sideways
    for (final dc in const [-1, 1]) {
      final tc = kc + dc;
      if (tc >= 0 && tc <= 8 && b[kr * 9 + tc] == xP * e) return true;
    }
    // knights: knight at (kr+a, kc+b) attacks king if its leg is free.
    const nd = [[2, 1, 1, 0], [2, -1, 1, 0], [-2, 1, -1, 0], [-2, -1, -1, 0], [1, 2, 0, 1], [-1, 2, 0, 1], [1, -2, 0, -1], [-1, -2, 0, -1]];
    for (final d in nd) {
      final nr = kr + d[0], nc = kc + d[1];
      if (nr < 0 || nr > 9 || nc < 0 || nc > 8) continue;
      if (b[nr * 9 + nc] != xN * e) continue;
      // leg is adjacent to the knight, in the direction of the long leg
      final lr = nr - d[2], lc = nc - d[3];
      if (b[lr * 9 + lc] == 0) return true;
    }
    return false;
  }

  bool inCheck() => kingAttacked(side);

  void make(int m) {
    final f = xFrom(m), t = xTo(m);
    _undo
      ..add(m)
      ..add(b[t]);
    final p = b[f];
    b[t] = p;
    b[f] = 0;
    if (p == xK) kings[0] = t;
    if (p == -xK) kings[1] = t;
    side = -side;
  }

  void unmake() {
    final n = _undo.length;
    final m = _undo[n - 2], cap = _undo[n - 1];
    _undo.length = n - 2;
    side = -side;
    final f = xFrom(m), t = xTo(m);
    final p = b[t];
    b[f] = p;
    b[t] = cap;
    if (p == xK) kings[0] = f;
    if (p == -xK) kings[1] = f;
  }

  List<int> legal() {
    final ps = <int>[];
    gen(ps);
    final me = side;
    final out = <int>[];
    for (final m in ps) {
      make(m);
      if (!kingAttacked(me)) out.add(m);
      unmake();
    }
    return out;
  }

  int perft(int depth) {
    if (depth == 0) return 1;
    final ps = <int>[];
    gen(ps);
    final me = side;
    var n = 0;
    for (final m in ps) {
      make(m);
      if (!kingAttacked(me)) n += depth == 1 ? 1 : perft(depth - 1);
      unmake();
    }
    return n;
  }

  String key() => '${b.join(',')}|$side';

  /// True if neither side has any piece able to cross the river (only 将士象 left).
  bool noAttackers() {
    for (final p in b) {
      final t = p.abs();
      if (t == xN || t == xR || t == xC || t == xP) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------- evaluation

const List<int> _xval = [0, 0, 20, 20, 40, 90, 45, 10];

int _pawnBonus(int r, int c, int s) {
  final adv = s > 0 ? r : 9 - r; // 0..9
  if (adv < 5) return 0;
  var bonus = 10 + (adv - 5) * 4;
  if (adv == 9) bonus = 6; // 老兵 bottom line is weak
  if (c >= 3 && c <= 5) bonus += 6;
  return bonus;
}

/// Static evaluation from red's point of view (units ≈ 1/10 pawn*10).
int xqEval(XqPos p) {
  var score = 0;
  for (var sq = 0; sq < 90; sq++) {
    final v = p.b[sq];
    if (v == 0) continue;
    final t = v.abs();
    final s = v > 0 ? 1 : -1;
    final r = sq ~/ 9, c = sq % 9;
    var val = _xval[t] * 10;
    if (t == xP) val += _pawnBonus(r, c, s);
    if (t == xN || t == xC || t == xR) {
      // mild centralisation / advancement
      final adv = s > 0 ? r : 9 - r;
      val += (4 - (c - 4).abs()) * 2;
      if (t == xN) val += min(adv, 6) * 3;
      if (t == xR) val += adv >= 5 ? 8 : 0;
    }
    score += s * val;
  }
  return score;
}

const int xqMate = 30000;

class XqSearch {
  final XqPos p;
  final int limitMs;
  final int maxDepth;
  final Random rng;
  final Stopwatch _sw = Stopwatch();
  int _nodes = 0;
  bool _stop = false;
  XqSearch(this.p, {required this.limitMs, required this.maxDepth, required this.rng});

  int _order(int m) {
    final cap = p.b[xTo(m)].abs();
    if (cap == 0) return 0;
    return (cap == xK ? 2000 : _xval[cap] * 10) - _xval[p.b[xFrom(m)].abs()];
  }

  void _sortMoves(List<int> ms) {
    final keyed = [for (var i = 0; i < ms.length; i++) (_order(ms[i]), i, ms[i])];
    keyed.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    for (var i = 0; i < ms.length; i++) {
      ms[i] = keyed[i].$3;
    }
  }

  bool _timeUp() {
    if ((++_nodes & 511) == 0 && _sw.elapsedMilliseconds > limitMs) _stop = true;
    return _stop;
  }

  int _qs(int alpha, int beta, int ply) {
    if (_timeUp()) return 0;
    final stand = xqEval(p) * p.side;
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (ply > 10) return stand;
    final ms = <int>[];
    p.gen(ms, caps: true);
    _sortMoves(ms);
    final me = p.side;
    for (final m in ms) {
      p.make(m);
      if (p.kingAttacked(me)) {
        p.unmake();
        continue;
      }
      final v = -_qs(-beta, -alpha, ply + 1);
      p.unmake();
      if (_stop) return 0;
      if (v >= beta) return v;
      if (v > alpha) alpha = v;
    }
    return alpha;
  }

  int _search(int depth, int alpha, int beta, int ply) {
    if (_timeUp()) return 0;
    if (depth <= 0) return _qs(alpha, beta, ply);
    final ms = <int>[];
    p.gen(ms);
    _sortMoves(ms);
    final me = p.side;
    var legal = 0;
    var best = -xqMate;
    for (final m in ms) {
      p.make(m);
      if (p.kingAttacked(me)) {
        p.unmake();
        continue;
      }
      legal++;
      final v = -_search(depth - 1, -beta, -alpha, ply + 1);
      p.unmake();
      if (_stop) return 0;
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    if (legal == 0) return -xqMate + ply; // 将死或困毙都判负
    return best;
  }

  /// Best legal move, avoiding moves in [avoid] (e.g. repetition) when possible.
  int bestMove({Set<int> avoid = const {}}) {
    _sw.start();
    var root = p.legal()..shuffle(rng);
    if (root.isEmpty) return -1;
    if (root.length == 1) return root.first;
    final filtered = root.where((m) => !avoid.contains(m)).toList();
    if (filtered.isNotEmpty) root = filtered;
    _sortMoves(root);
    var best = root.first;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var alpha = -xqMate - 1;
      var iterBest = -1;
      for (final m in root) {
        p.make(m);
        final v = -_search(depth - 1, -xqMate - 1, -alpha, 1);
        p.unmake();
        if (_stop) break;
        if (v > alpha) {
          alpha = v;
          iterBest = m;
        }
      }
      if (_stop) {
        if (iterBest >= 0) best = iterBest; // previous best searched first, so iterBest is at least as good
        break;
      }
      if (iterBest >= 0) {
        best = iterBest;
        root.remove(best);
        root.insert(0, best);
      }
      if (alpha.abs() > xqMate - 100) break;
      if (_sw.elapsedMilliseconds * 5 > limitMs) break;
    }
    return best;
  }
}
