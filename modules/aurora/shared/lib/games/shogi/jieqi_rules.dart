// 揭棋规则：基于中国象棋。暗子按所在初始格的兵种走法移动，走动后翻开成为真实身份。
// 棋盘 9 列 × 10 行，index = row*9 + col，row 0 为红方底线。红方 > 0，黑方 < 0。
// 1 帅/将, 2 仕/士, 3 相/象, 4 马, 5 车, 6 炮, 7 兵/卒。hidden[sq] 表示该格棋子为暗子。
// 翻开后的仕/相可以离开九宫、过河。

import 'dart:math';

const int jK = 1, jA = 2, jB = 3, jN = 4, jR = 5, jC = 6, jP = 7;

/// Marker used in views for a face-down piece (±jHidden).
const int jHidden = 8;

int jFrom(int m) => m & 127;
int jTo(int m) => m >> 7;
int jMove(int f, int t) => f | (t << 7);

bool _inPalace(int r, int c, int side) => c >= 3 && c <= 5 && (side > 0 ? r <= 2 : r >= 7);

/// Piece type of the standard xiangqi starting square [sq] (0 if none), unsigned.
final List<int> jStartType = () {
  final t = List<int>.filled(90, 0);
  const back = [jR, jN, jB, jA, jK, jA, jB, jN, jR];
  for (var c = 0; c < 9; c++) {
    t[c] = back[c];
    t[81 + c] = back[c];
  }
  for (final c in const [1, 7]) {
    t[2 * 9 + c] = jC;
    t[7 * 9 + c] = jC;
  }
  for (var c = 0; c < 9; c += 2) {
    t[3 * 9 + c] = jP;
    t[6 * 9 + c] = jP;
  }
  return t;
}();

/// The 15 non-king pieces of one side.
const List<int> jPieceSet = [jA, jA, jB, jB, jN, jN, jR, jR, jC, jC, jP, jP, jP, jP, jP];

/// Start squares of the non-king pieces of side [s].
List<int> jStartSquares(int s) => [
      for (var sq = 0; sq < 90; sq++)
        if (jStartType[sq] != 0 && jStartType[sq] != jK && (s > 0 ? sq < 45 : sq >= 45)) sq
    ];

class JqPos {
  final List<int> b = List<int>.filled(90, 0);
  final List<bool> hidden = List<bool>.filled(90, false);
  int side = 1;
  final List<int> kings = [4, 85];
  final List<int> _undo = [];

  JqPos();

  /// Random jieqi start: each side's 15 pieces shuffled over its own start squares.
  JqPos.shuffledStart(Random rng) {
    for (final s in const [1, -1]) {
      final sqs = jStartSquares(s);
      final pieces = List<int>.of(jPieceSet)..shuffle(rng);
      for (var i = 0; i < sqs.length; i++) {
        b[sqs[i]] = pieces[i] * s;
        hidden[sqs[i]] = true;
      }
    }
    b[4] = jK;
    b[85] = -jK;
  }

  JqPos copy() {
    final p = JqPos();
    p.b.setAll(0, b);
    p.hidden.setAll(0, hidden);
    p.side = side;
    p.kings
      ..[0] = kings[0]
      ..[1] = kings[1];
    return p;
  }

  void findKings() {
    for (var i = 0; i < 90; i++) {
      if (b[i] == jK) kings[0] = i;
      if (b[i] == -jK) kings[1] = i;
    }
  }

  /// How the piece on [sq] moves (square type while face-down).
  int moveType(int sq) => hidden[sq] ? jStartType[sq] : b[sq].abs();

  bool _own(int q, int s) => q != 0 && (q > 0) == (s > 0);

  /// Pseudo-legal moves for the side to move.
  void gen(List<int> out, {bool caps = false}) {
    final s = side;
    for (var sq = 0; sq < 90; sq++) {
      final p = b[sq];
      if (p == 0 || (p > 0) != (s > 0)) continue;
      final r = sq ~/ 9, c = sq % 9;
      final hid = hidden[sq];
      void add(int tr, int tc) {
        if (tr < 0 || tr > 9 || tc < 0 || tc > 8) return;
        final t = tr * 9 + tc;
        final q = b[t];
        if (_own(q, s)) return;
        if (caps && q == 0) return;
        out.add(jMove(sq, t));
      }

      switch (moveType(sq)) {
        case jK:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            if (_inPalace(r + d[0], c + d[1], s)) add(r + d[0], c + d[1]);
          }
        case jA:
          for (final d in const [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
            if (!hid || _inPalace(r + d[0], c + d[1], s)) add(r + d[0], c + d[1]);
          }
        case jB:
          for (final d in const [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
            final tr = r + 2 * d[0], tc = c + 2 * d[1];
            if (tr < 0 || tr > 9 || tc < 0 || tc > 8) continue;
            if (hid && (s > 0 ? tr > 4 : tr < 5)) continue;
            if (b[(r + d[0]) * 9 + c + d[1]] != 0) continue; // 塞象眼
            add(tr, tc);
          }
        case jN:
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
        case jR:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            var tr = r + d[0], tc = c + d[1];
            while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
              final q = b[tr * 9 + tc];
              if (q == 0) {
                if (!caps) out.add(jMove(sq, tr * 9 + tc));
              } else {
                if (!_own(q, s)) out.add(jMove(sq, tr * 9 + tc));
                break;
              }
              tr += d[0];
              tc += d[1];
            }
          }
        case jC:
          for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            var tr = r + d[0], tc = c + d[1];
            var screen = false;
            while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
              final q = b[tr * 9 + tc];
              if (!screen) {
                if (q == 0) {
                  if (!caps) out.add(jMove(sq, tr * 9 + tc));
                } else {
                  screen = true;
                }
              } else if (q != 0) {
                if (!_own(q, s)) out.add(jMove(sq, tr * 9 + tc));
                break;
              }
              tr += d[0];
              tc += d[1];
            }
          }
        case jP:
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

  bool _enemyIs(int sq, int e, int type) {
    final q = b[sq];
    return q != 0 && (q > 0) == (e > 0) && moveType(sq) == type;
  }

  /// Is the king of side [s] attacked (including flying general)?
  bool kingAttacked(int s) {
    final k = kings[s > 0 ? 0 : 1];
    final kr = k ~/ 9, kc = k % 9;
    final e = -s;
    for (final d in const [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      var tr = kr + d[0], tc = kc + d[1];
      var screens = 0;
      while (tr >= 0 && tr <= 9 && tc >= 0 && tc <= 8) {
        final sq = tr * 9 + tc;
        if (b[sq] != 0) {
          if (screens == 0) {
            if (_enemyIs(sq, e, jR) || (b[sq] == jK * e && d[1] == 0)) return true;
            // enemy pawn directly in front of the king (moving towards it)
            if (_enemyIs(sq, e, jP) && d[1] == 0 && tr == kr + (s > 0 ? 1 : -1)) return true;
          } else if (screens == 1) {
            if (_enemyIs(sq, e, jC)) return true;
            break;
          }
          screens++;
        }
        tr += d[0];
        tc += d[1];
      }
    }
    // pawns sideways (only after crossing the river = the king's half)
    for (final dc in const [-1, 1]) {
      final tc = kc + dc;
      if (tc < 0 || tc > 8) continue;
      final sq = kr * 9 + tc;
      if (_enemyIs(sq, e, jP)) {
        final crossed = e > 0 ? kr >= 5 : kr <= 4;
        if (crossed) return true;
      }
    }
    const nd = [[2, 1, 1, 0], [2, -1, 1, 0], [-2, 1, -1, 0], [-2, -1, -1, 0], [1, 2, 0, 1], [-1, 2, 0, 1], [1, -2, 0, -1], [-1, -2, 0, -1]];
    for (final d in nd) {
      final nr = kr + d[0], nc = kc + d[1];
      if (nr < 0 || nr > 9 || nc < 0 || nc > 8) continue;
      if (!_enemyIs(nr * 9 + nc, e, jN)) continue;
      final lr = nr - d[2], lc = nc - d[3];
      if (b[lr * 9 + lc] == 0) return true;
    }
    // advisors / elephants (revealed ones roam freely)
    for (final d in const [[1, 1], [1, -1], [-1, 1], [-1, -1]]) {
      final ar = kr + d[0], ac = kc + d[1];
      if (ar < 0 || ar > 9 || ac < 0 || ac > 8) continue;
      final asq = ar * 9 + ac;
      if (_enemyIs(asq, e, jA) && (!hidden[asq] || _inPalace(kr, kc, e))) return true;
      if (b[asq] != 0) continue; // elephant eye blocked
      final br = kr + 2 * d[0], bc = kc + 2 * d[1];
      if (br < 0 || br > 9 || bc < 0 || bc > 8) continue;
      final bsq = br * 9 + bc;
      if (_enemyIs(bsq, e, jB) && (!hidden[bsq] || (e > 0 ? kr <= 4 : kr >= 5))) return true;
    }
    return false;
  }

  bool inCheck() => kingAttacked(side);

  /// Applies [m]; the moved piece is revealed.
  void make(int m) {
    final f = jFrom(m), t = jTo(m);
    _undo
      ..add(m)
      ..add(b[t])
      ..add((hidden[t] ? 1 : 0) | (hidden[f] ? 2 : 0));
    final p = b[f];
    b[t] = p;
    b[f] = 0;
    hidden[t] = false;
    hidden[f] = false;
    if (p == jK) kings[0] = t;
    if (p == -jK) kings[1] = t;
    side = -side;
  }

  void unmake() {
    final n = _undo.length;
    final m = _undo[n - 3], cap = _undo[n - 2], flags = _undo[n - 1];
    _undo.length = n - 3;
    side = -side;
    final f = jFrom(m), t = jTo(m);
    final p = b[t];
    b[f] = p;
    b[t] = cap;
    hidden[t] = flags & 1 != 0;
    hidden[f] = flags & 2 != 0;
    if (p == jK) kings[0] = f;
    if (p == -jK) kings[1] = f;
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

  /// Copy where every face-down piece's identity is replaced by [jHidden]
  /// (what a player actually knows). A face-down piece that moves inside a
  /// search stays "unknown" (type jHidden, no further moves).
  JqPos sanitized() {
    final p = copy();
    for (var i = 0; i < 90; i++) {
      if (p.hidden[i]) p.b[i] = p.b[i] > 0 ? jHidden : -jHidden;
    }
    return p;
  }

  /// Public position key (face-down pieces shown only as "hidden").
  String key() {
    final sb = StringBuffer();
    for (var i = 0; i < 90; i++) {
      final v = b[i];
      sb.write(hidden[i] ? (v > 0 ? 'H' : 'h') : '$v');
      sb.write(',');
    }
    sb.write(side);
    return sb.toString();
  }

  /// Only the two kings remain.
  bool onlyKings() {
    for (final p in b) {
      if (p != 0 && p.abs() != jK) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------- bot (information-fair)

const List<int> jValue = [0, 0, 25, 25, 40, 90, 45, 10];

int _pawnBonus(int r, int c, int s) {
  final adv = s > 0 ? r : 9 - r;
  if (adv < 5) return 0;
  var bonus = 10 + (adv - 5) * 4;
  if (adv == 9) bonus = 6;
  if (c >= 3 && c <= 5) bonus += 6;
  return bonus;
}

/// Evaluation from red's point of view. Face-down pieces count as
/// [hiddenValue][0] (red) / [hiddenValue][1] (black) — expected value of the unknown pool.
int jqEval(JqPos p, List<int> hiddenValue) {
  var score = 0;
  for (var sq = 0; sq < 90; sq++) {
    final v = p.b[sq];
    if (v == 0) continue;
    final s = v > 0 ? 1 : -1;
    final t = v.abs();
    if (p.hidden[sq] || t == jHidden) {
      score += s * hiddenValue[s > 0 ? 0 : 1];
      continue;
    }
    final r = sq ~/ 9, c = sq % 9;
    var val = jValue[t] * 10;
    if (t == jP) val += _pawnBonus(r, c, s);
    if (t == jN || t == jC || t == jR) {
      final adv = s > 0 ? r : 9 - r;
      val += (4 - (c - 4).abs()) * 2;
      if (t == jN) val += min(adv, 6) * 3;
      if (t == jR) val += adv >= 5 ? 8 : 0;
    }
    score += s * val;
  }
  return score;
}

const int jqMate = 30000;

class JqSearch {
  final JqPos p;
  final List<int> hiddenValue;
  final int limitMs;
  final int maxDepth;
  final int maxNodes;
  final Stopwatch _sw = Stopwatch();
  int _nodes = 0;
  bool _stop = false;
  JqSearch(this.p, this.hiddenValue, {required this.limitMs, required this.maxDepth, this.maxNodes = 1 << 30});

  int _val(int sq) => p.hidden[sq] || p.b[sq].abs() == jHidden ? hiddenValue[p.b[sq] > 0 ? 0 : 1] : (p.b[sq].abs() == jK ? 2000 : jValue[p.b[sq].abs()] * 10);

  void _sortMoves(List<int> ms) {
    final keyed = [
      for (var i = 0; i < ms.length; i++)
        (p.b[jTo(ms[i])] == 0 ? 0 : _val(jTo(ms[i])) * 4 - _val(jFrom(ms[i])) ~/ 10 + 100, i, ms[i])
    ];
    keyed.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    for (var i = 0; i < ms.length; i++) {
      ms[i] = keyed[i].$3;
    }
  }

  bool _timeUp() {
    ++_nodes;
    if (_nodes > maxNodes) _stop = true;
    if ((_nodes & 255) == 0 && _sw.elapsedMilliseconds > limitMs) _stop = true;
    return _stop;
  }

  int _qs(int alpha, int beta, int ply) {
    if (_timeUp()) return 0;
    final stand = jqEval(p, hiddenValue) * p.side;
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (ply > 8) return stand;
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
    var best = -jqMate;
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
    if (legal == 0) return -jqMate + ply; // 将死或困毙
    return best;
  }

  /// Best move among [root] (legal moves, already in a deterministic order),
  /// preferring moves not in [avoid].
  int bestMove(List<int> legalRoot, {Set<int> avoid = const {}}) {
    _sw.start();
    var root = List<int>.of(legalRoot);
    if (root.isEmpty) return -1;
    if (root.length == 1) return root.first;
    final filtered = root.where((m) => !avoid.contains(m)).toList();
    if (filtered.isNotEmpty) root = filtered;
    _sortMoves(root);
    var best = root.first;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var alpha = -jqMate - 1;
      var iterBest = -1;
      for (final m in root) {
        p.make(m);
        final v = -_search(depth - 1, -jqMate - 1, -alpha, 1);
        p.unmake();
        if (_stop) break;
        if (v > alpha) {
          alpha = v;
          iterBest = m;
        }
      }
      if (_stop) {
        if (iterBest >= 0) best = iterBest;
        break;
      }
      if (iterBest >= 0) {
        best = iterBest;
        root.remove(best);
        root.insert(0, best);
      }
      if (alpha.abs() > jqMate - 100) break;
      if (_sw.elapsedMilliseconds * 5 > limitMs) break;
    }
    return best;
  }
}
