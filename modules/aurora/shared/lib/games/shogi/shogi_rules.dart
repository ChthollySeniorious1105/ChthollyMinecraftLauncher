// 将棋规则：走法生成（含打入、升变）、王手检测、评估与 alpha-beta 搜索。
// 棋盘 9×9，index = row*9 + col。row 0 = 一段（后手底线），col 0 = ９筋（先手视角左侧）。
// 先手 (side 1) 棋子为正，后手 (side -1) 为负。先手向 row 减小方向前进。
// 1 步, 2 香, 3 桂, 4 银, 5 金, 6 角, 7 飞, 8 玉；升变 = 基础 + 8：9 と, 10 成香, 11 成桂, 12 成银, 14 马, 15 龙。

import 'dart:math';

const int sgP = 1, sgL = 2, sgN = 3, sgS = 4, sgG = 5, sgB = 6, sgR = 7, sgK = 8;
const int sgPromo = 8;

bool sgCanPromote(int t) => t == sgP || t == sgL || t == sgN || t == sgS || t == sgB || t == sgR;
int sgBase(int t) => t > sgK ? t - sgPromo : t;

/// Move encoding: from | to << 7 | promote << 14. Drops use from = 81 + piece type.
int sgMove(int from, int to, [bool promote = false]) => from | (to << 7) | (promote ? 1 << 14 : 0);
int sgFrom(int m) => m & 127;
int sgTo(int m) => (m >> 7) & 127;
bool sgIsPromo(int m) => (m >> 14) & 1 == 1;
bool sgIsDrop(int m) => sgFrom(m) >= 81;
int sgDropType(int m) => sgFrom(m) - 81;

// Directions, sente-relative: (dr, dc).
const List<List<int>> _dirs = [
  [-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1], //
];
// index of the direction mirrored vertically (for gote pieces)
const List<int> _flip = [5, 6, 7, 3, 4, 0, 1, 2];

const int _gold = 1 | 2 | 4 | 8 | 16 | 64; // dirs 0,1,2,3,4,6
const int _diag = 1 | 4 | 32 | 128; // 0,2,5,7
const int _orth = 2 | 8 | 16 | 64; // 1,3,4,6

// step / slide masks indexed by piece type (0..15)
const List<int> _stepMask = [
  0, 2, 0, 0, 1 | 2 | 4 | 32 | 128, _gold, 0, 0, 255, //
  _gold, _gold, _gold, _gold, 0, _orth, _diag,
];
const List<int> _slideMask = [
  0, 0, 2, 0, 0, 0, _diag, _orth, 0, //
  0, 0, 0, 0, 0, _diag, _orth,
];

class ShogiPos {
  final List<int> b = List<int>.filled(81, 0);

  /// hands[0] = 先手, hands[1] = 后手; index = piece type 1..7.
  final List<List<int>> hands = [List<int>.filled(8, 0), List<int>.filled(8, 0)];
  int side = 1;
  final List<int> kings = [-1, -1];
  final List<int> _undo = [];

  static const List<int> _back = [sgL, sgN, sgS, sgG, sgK, sgG, sgS, sgN, sgL];

  /// Standard start. [handicap]: 0 平手, 1 让香, 2 让角, 3 让飞, 4 让二枚 (pieces removed from 后手, who moves first).
  ShogiPos.initial([int handicap = 0]) {
    for (var c = 0; c < 9; c++) {
      b[c] = -_back[c];
      b[8 * 9 + c] = _back[c];
      b[2 * 9 + c] = -sgP;
      b[6 * 9 + c] = sgP;
    }
    b[1 * 9 + 1] = -sgR; // 8二飞
    b[1 * 9 + 7] = -sgB; // 2二角
    b[7 * 9 + 1] = sgB; // 8八角
    b[7 * 9 + 7] = sgR; // 2八飞
    switch (handicap) {
      case 1:
        b[8] = 0; // 1一香
      case 2:
        b[1 * 9 + 7] = 0;
      case 3:
        b[1 * 9 + 1] = 0;
      case 4:
        b[1 * 9 + 7] = 0;
        b[1 * 9 + 1] = 0;
    }
    if (handicap > 0) side = -1;
    _findKings();
  }

  ShogiPos.empty();

  void _findKings() {
    kings[0] = kings[1] = -1;
    for (var i = 0; i < 81; i++) {
      if (b[i] == sgK) kings[0] = i;
      if (b[i] == -sgK) kings[1] = i;
    }
  }

  /// Set up a custom position (used by tests). Pieces: map square -> signed type.
  void setup(Map<int, int> pieces, {int toMove = 1, List<int>? senteHand, List<int>? goteHand}) {
    b.fillRange(0, 81, 0);
    pieces.forEach((k, v) => b[k] = v);
    for (var i = 0; i < 8; i++) {
      hands[0][i] = senteHand != null && i < senteHand.length ? senteHand[i] : 0;
      hands[1][i] = goteHand != null && i < goteHand.length ? goteHand[i] : 0;
    }
    side = toMove;
    _undo.clear();
    _findKings();
  }

  bool _inZone(int sq, int s) => s > 0 ? sq < 27 : sq >= 54;

  /// Piece of type t (unpromoted) for side s has no legal move from row r.
  static bool deadEnd(int t, int r, int s) {
    final rel = s > 0 ? r : 8 - r; // distance from the far edge
    if (t == sgP || t == sgL) return rel == 0;
    if (t == sgN) return rel <= 1;
    return false;
  }

  /// Pseudo-legal moves (own king may be left in check; 打步诘 not checked).
  void gen(List<int> out, {bool caps = false}) {
    final s = side;
    for (var sq = 0; sq < 81; sq++) {
      final p = b[sq];
      if (p == 0 || (p > 0) != (s > 0)) continue;
      final t = p.abs();
      final r = sq ~/ 9, c = sq % 9;
      void add(int to) {
        final q = b[to];
        if (caps && q == 0) return;
        final tr = to ~/ 9;
        if (sgCanPromote(t) && (_inZone(sq, s) || _inZone(to, s))) {
          out.add(sgMove(sq, to, true));
          if (!deadEnd(t, tr, s)) out.add(sgMove(sq, to));
        } else {
          out.add(sgMove(sq, to));
        }
      }

      if (t == sgN) {
        final tr = r - 2 * s;
        if (tr >= 0 && tr < 9) {
          for (final dc in const [-1, 1]) {
            final tc = c + dc;
            if (tc < 0 || tc > 8) continue;
            final q = b[tr * 9 + tc];
            if (q != 0 && (q > 0) == (s > 0)) continue;
            add(tr * 9 + tc);
          }
        }
        continue;
      }
      final sm = _stepMask[t], lm = _slideMask[t];
      for (var i = 0; i < 8; i++) {
        final bit = 1 << i;
        if ((sm | lm) & bit == 0) continue;
        final dr = _dirs[i][0] * s, dc = _dirs[i][1];
        var tr = r + dr, tc = c + dc;
        while (tr >= 0 && tr < 9 && tc >= 0 && tc < 9) {
          final to = tr * 9 + tc;
          final q = b[to];
          if (q != 0 && (q > 0) == (s > 0)) break;
          add(to);
          if (q != 0 || lm & bit == 0) break;
          tr += dr;
          tc += dc;
        }
      }
    }
    if (caps) return;
    final hand = hands[s > 0 ? 0 : 1];
    var any = false;
    for (var t = 1; t <= 7; t++) {
      if (hand[t] > 0) any = true;
    }
    if (!any) return;
    final pawnFile = List<bool>.filled(9, false);
    for (var sq = 0; sq < 81; sq++) {
      if (b[sq] == sgP * s) pawnFile[sq % 9] = true;
    }
    for (var t = 1; t <= 7; t++) {
      if (hand[t] == 0) continue;
      for (var sq = 0; sq < 81; sq++) {
        if (b[sq] != 0) continue;
        if (deadEnd(t, sq ~/ 9, s)) continue;
        if (t == sgP && pawnFile[sq % 9]) continue; // 二步
        out.add(sgMove(81 + t, sq));
      }
    }
  }

  /// Is [sq] attacked by side [a]?
  bool attacked(int sq, int a) {
    final r = sq ~/ 9, c = sq % 9;
    for (var i = 0; i < 8; i++) {
      final dr = _dirs[i][0], dc = _dirs[i][1];
      // attacker at q moving in direction (dr,dc) reaches sq
      var qr = r - dr, qc = c - dc;
      if (qr < 0 || qr > 8 || qc < 0 || qc > 8) continue;
      final rel = a > 0 ? i : _flip[i];
      final bit = 1 << rel;
      var p = b[qr * 9 + qc];
      if (p != 0) {
        if ((p > 0) == (a > 0) && (_stepMask[p.abs()] | _slideMask[p.abs()]) & bit != 0) return true;
        continue;
      }
      while (true) {
        qr -= dr;
        qc -= dc;
        if (qr < 0 || qr > 8 || qc < 0 || qc > 8) break;
        p = b[qr * 9 + qc];
        if (p == 0) continue;
        if ((p > 0) == (a > 0) && _slideMask[p.abs()] & bit != 0) return true;
        break;
      }
    }
    // knights: attacker knight moves (-2a, ±1)
    final nr = r + 2 * a;
    if (nr >= 0 && nr < 9) {
      for (final dc in const [-1, 1]) {
        final nc = c + dc;
        if (nc >= 0 && nc < 9 && b[nr * 9 + nc] == sgN * a) return true;
      }
    }
    return false;
  }

  bool kingAttacked(int s) {
    final k = kings[s > 0 ? 0 : 1];
    return k >= 0 && attacked(k, -s);
  }

  bool inCheck() => kingAttacked(side);

  void make(int m) {
    final f = sgFrom(m), t = sgTo(m);
    final s = side;
    final hand = hands[s > 0 ? 0 : 1];
    if (f >= 81) {
      final pt = f - 81;
      hand[pt]--;
      b[t] = pt * s;
      _undo
        ..add(m)
        ..add(0);
    } else {
      final cap = b[t];
      _undo
        ..add(m)
        ..add(cap);
      if (cap != 0) hand[sgBase(cap.abs())]++;
      var p = b[f];
      if (sgIsPromo(m)) p += sgPromo * s;
      b[t] = p;
      b[f] = 0;
      if (p == sgK) kings[0] = t;
      if (p == -sgK) kings[1] = t;
      if (cap == sgK) kings[0] = -1;
      if (cap == -sgK) kings[1] = -1;
    }
    side = -s;
  }

  void unmake() {
    final n = _undo.length;
    final m = _undo[n - 2], cap = _undo[n - 1];
    _undo.length = n - 2;
    side = -side;
    final s = side;
    final hand = hands[s > 0 ? 0 : 1];
    final f = sgFrom(m), t = sgTo(m);
    if (f >= 81) {
      hand[f - 81]++;
      b[t] = 0;
      return;
    }
    var p = b[t];
    if (sgIsPromo(m)) p -= sgPromo * s;
    b[f] = p;
    b[t] = cap;
    if (cap != 0) hand[sgBase(cap.abs())]--;
    if (p == sgK) kings[0] = f;
    if (p == -sgK) kings[1] = f;
    if (cap == sgK) kings[0] = t;
    if (cap == -sgK) kings[1] = t;
  }

  /// Side to move has at least one move that doesn't leave its king in check.
  bool hasLegalMove() {
    final ps = <int>[];
    gen(ps);
    final me = side;
    for (final m in ps) {
      make(m);
      final ok = !kingAttacked(me);
      unmake();
      if (ok) return true;
    }
    return false;
  }

  /// Would pawn drop [m] (already made) be 打步诘? Call after make().
  bool _dropPawnMate(int m) {
    if (!sgIsDrop(m) || sgDropType(m) != sgP) return false;
    if (!inCheck()) return false;
    return !hasLegalMove();
  }

  bool isLegal(int m) {
    final me = side;
    make(m);
    final ok = !kingAttacked(me) && !_dropPawnMate(m);
    unmake();
    return ok;
  }

  List<int> legal() {
    final ps = <int>[];
    gen(ps);
    return [for (final m in ps) if (isLegal(m)) m];
  }

  int perft(int depth) {
    if (depth == 0) return 1;
    final ms = legal();
    if (depth == 1) return ms.length;
    var n = 0;
    for (final m in ms) {
      make(m);
      n += perft(depth - 1);
      unmake();
    }
    return n;
  }

  String key() => '${b.join(',')}|${hands[0].join(',')}|${hands[1].join(',')}|$side';
}

// ---------------------------------------------------------------- evaluation

const List<int> sgValue = [0, 100, 300, 350, 500, 550, 800, 1000, 0, 550, 500, 520, 550, 0, 1050, 1250];
const List<int> sgHandValue = [0, 115, 330, 380, 560, 610, 900, 1100];

/// Static evaluation from 先手's point of view.
int shogiEval(ShogiPos p) {
  var score = 0;
  for (var i = 1; i <= 7; i++) {
    score += (p.hands[0][i] - p.hands[1][i]) * sgHandValue[i];
  }
  final ks = p.kings[0], kg = p.kings[1];
  for (var sq = 0; sq < 81; sq++) {
    final v = p.b[sq];
    if (v == 0) continue;
    final t = v.abs();
    final s = v > 0 ? 1 : -1;
    var val = sgValue[t];
    if (t != sgK) {
      final r = sq ~/ 9, c = sq % 9;
      final enemyK = s > 0 ? kg : ks;
      final ownK = s > 0 ? ks : kg;
      if (enemyK >= 0) {
        final d = max((enemyK ~/ 9 - r).abs(), (enemyK % 9 - c).abs());
        if (d <= 2) val += 18;
      }
      if (ownK >= 0 && (t == sgG || t == sgS || t == 12)) {
        final d = max((ownK ~/ 9 - r).abs(), (ownK % 9 - c).abs());
        if (d <= 1) val += 30;
      }
      if (t == sgP) val += (s > 0 ? 6 - r : r - 2).clamp(0, 4) * 4;
    }
    score += s * val;
  }
  return score;
}

const int sgMate = 30000;

class ShogiSearch {
  final ShogiPos p;
  final int limitMs;
  final int maxDepth;
  final Random rng;
  final Stopwatch _sw = Stopwatch();
  int _nodes = 0;
  bool _stop = false;
  ShogiSearch(this.p, {required this.limitMs, required this.maxDepth, required this.rng});

  int _order(int m) {
    var score = sgIsPromo(m) ? 300 : 0;
    if (sgIsDrop(m)) return -10;
    final cap = p.b[sgTo(m)].abs();
    if (cap != 0) score += (cap == sgK ? 20000 : sgValue[cap] * 4) - sgValue[p.b[sgFrom(m)].abs()] ~/ 10 + 1000;
    return score;
  }

  void _sortMoves(List<int> ms) {
    final keyed = [for (var i = 0; i < ms.length; i++) (_order(ms[i]), i, ms[i])];
    keyed.sort((a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2 - b.$2);
    for (var i = 0; i < ms.length; i++) {
      ms[i] = keyed[i].$3;
    }
  }

  bool _timeUp() {
    if ((++_nodes & 255) == 0 && _sw.elapsedMilliseconds > limitMs) _stop = true;
    return _stop;
  }

  int _qs(int alpha, int beta, int ply) {
    if (_timeUp()) return 0;
    final stand = shogiEval(p) * p.side;
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
    var best = -sgMate;
    for (final m in ms) {
      p.make(m);
      if (p.kingAttacked(me)) {
        p.unmake();
        continue;
      }
      if (sgIsDrop(m) && sgDropType(m) == sgP && p.inCheck() && !p.hasLegalMove()) {
        p.unmake(); // 打步诘
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
    if (legal == 0) return -sgMate + ply;
    return best;
  }

  /// Best move among [root] (legal moves), preferring moves not in [avoid].
  int bestMove(List<int> legalRoot, {Set<int> avoid = const {}}) {
    _sw.start();
    var root = List<int>.of(legalRoot)..shuffle(rng);
    if (root.isEmpty) return -1;
    if (root.length == 1) return root.first;
    final filtered = root.where((m) => !avoid.contains(m)).toList();
    if (filtered.isNotEmpty) root = filtered;
    _sortMoves(root);
    var best = root.first;
    for (var depth = 1; depth <= maxDepth; depth++) {
      var alpha = -sgMate - 1;
      var iterBest = -1;
      for (final m in root) {
        p.make(m);
        final v = -_search(depth - 1, -sgMate - 1, -alpha, 1);
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
      if (alpha.abs() > sgMate - 100) break;
      if (_sw.elapsedMilliseconds * 4 > limitMs) break;
    }
    return best;
  }
}
