// International chess rules: move generation, make/unmake, SAN, evaluation and
// a small alpha-beta search. Squares are 0..63, index = rank*8 + file
// (a1 = 0, h1 = 7, a8 = 56). Pieces: 1 P, 2 N, 3 B, 4 R, 5 Q, 6 K; white > 0, black < 0.

import 'dart:math';

const int cP = 1, cN = 2, cB = 3, cR = 4, cQ = 5, cK = 6;
const int fEp = 1, fCastle = 2, fDouble = 4;

int mFrom(int m) => m & 63;
int mTo(int m) => (m >> 6) & 63;
int mPromo(int m) => (m >> 12) & 7;
int mFlag(int m) => m >> 16;
int mkMove(int f, int t, [int promo = 0, int flag = 0]) => f | (t << 6) | (promo << 12) | (flag << 16);

String sqName(int sq) => '${'abcdefgh'[sq & 7]}${(sq >> 3) + 1}';

final List<List<int>> _knightT = _jumpTable(const [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]]);
final List<List<int>> _kingT = _jumpTable(const [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]);
// rays[sq][dir]: dirs 0..3 orthogonal, 4..7 diagonal
final List<List<List<int>>> _rays = _rayTable();

List<List<int>> _jumpTable(List<List<int>> d) => [
      for (var sq = 0; sq < 64; sq++)
        [
          for (final o in d)
            if ((sq & 7) + o[0] >= 0 && (sq & 7) + o[0] < 8 && (sq >> 3) + o[1] >= 0 && (sq >> 3) + o[1] < 8)
              sq + o[0] + o[1] * 8
        ]
    ];

List<List<List<int>>> _rayTable() {
  const dirs = [[0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [1, -1], [-1, 1], [-1, -1]];
  return [
    for (var sq = 0; sq < 64; sq++)
      [
        for (final d in dirs)
          () {
            final out = <int>[];
            var f = (sq & 7) + d[0], r = (sq >> 3) + d[1];
            while (f >= 0 && f < 8 && r >= 0 && r < 8) {
              out.add(r * 8 + f);
              f += d[0];
              r += d[1];
            }
            return out;
          }()
      ]
  ];
}

final List<int> _castleMask = () {
  final m = List<int>.filled(64, 15);
  m[0] = 13;
  m[7] = 14;
  m[4] = 12;
  m[56] = 7;
  m[63] = 11;
  m[60] = 3;
  return m;
}();

class ChessPos {
  final List<int> b = List<int>.filled(64, 0);
  int side = 1;
  int castle = 15; // 1 WK, 2 WQ, 4 BK, 8 BQ
  int ep = -1;
  int half = 0;
  int full = 1;
  final List<int> kings = [4, 60];
  final List<int> _undo = [];

  static const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  ChessPos.initial() {
    _load(startFen);
  }
  ChessPos.fen(String fen) {
    _load(fen);
  }

  void _load(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    b.fillRange(0, 64, 0);
    var r = 7, f = 0;
    for (final ch in parts[0].split('')) {
      if (ch == '/') {
        r--;
        f = 0;
      } else if (RegExp(r'\d').hasMatch(ch)) {
        f += int.parse(ch);
      } else {
        final t = 'pnbrqk'.indexOf(ch.toLowerCase()) + 1;
        final v = ch == ch.toUpperCase() ? t : -t;
        b[r * 8 + f] = v;
        if (v == cK) kings[0] = r * 8 + f;
        if (v == -cK) kings[1] = r * 8 + f;
        f++;
      }
    }
    side = parts.length > 1 && parts[1] == 'b' ? -1 : 1;
    castle = 0;
    if (parts.length > 2) {
      if (parts[2].contains('K')) castle |= 1;
      if (parts[2].contains('Q')) castle |= 2;
      if (parts[2].contains('k')) castle |= 4;
      if (parts[2].contains('q')) castle |= 8;
    }
    ep = -1;
    if (parts.length > 3 && parts[3] != '-') {
      ep = (int.parse(parts[3][1]) - 1) * 8 + 'abcdefgh'.indexOf(parts[3][0]);
    }
    half = parts.length > 4 ? int.tryParse(parts[4]) ?? 0 : 0;
    full = parts.length > 5 ? int.tryParse(parts[5]) ?? 1 : 1;
  }

  bool _enemy(int q, int s) => q != 0 && (q > 0) != (s > 0);

  void gen(List<int> out, {bool caps = false}) {
    final s = side;
    for (var sq = 0; sq < 64; sq++) {
      final p = b[sq];
      if (p == 0 || (p > 0) != (s > 0)) continue;
      switch (p.abs()) {
        case cP:
          _genPawn(sq, out, caps);
        case cN:
          _genJump(sq, _knightT[sq], out, caps);
        case cK:
          _genJump(sq, _kingT[sq], out, caps);
          if (!caps) _genCastle(sq, out);
        case cB:
          _genSlide(sq, 4, 8, out, caps);
        case cR:
          _genSlide(sq, 0, 4, out, caps);
        case cQ:
          _genSlide(sq, 0, 8, out, caps);
      }
    }
  }

  void _genJump(int sq, List<int> t, List<int> out, bool caps) {
    for (final to in t) {
      final q = b[to];
      if (q == 0) {
        if (!caps) out.add(mkMove(sq, to));
      } else if (_enemy(q, side)) {
        out.add(mkMove(sq, to));
      }
    }
  }

  void _genSlide(int sq, int d0, int d1, List<int> out, bool caps) {
    final rays = _rays[sq];
    for (var d = d0; d < d1; d++) {
      for (final to in rays[d]) {
        final q = b[to];
        if (q == 0) {
          if (!caps) out.add(mkMove(sq, to));
        } else {
          if (_enemy(q, side)) out.add(mkMove(sq, to));
          break;
        }
      }
    }
  }

  void _genPawn(int sq, List<int> out, bool caps) {
    final s = side;
    final dir = s > 0 ? 8 : -8;
    final r = sq >> 3, f = sq & 7;
    final preRank = s > 0 ? 6 : 1;
    final startRank = s > 0 ? 1 : 6;
    final to = sq + dir;
    void addPromo(int t) {
      if (caps) {
        out.add(mkMove(sq, t, cQ));
      } else {
        for (final pr in const [cQ, cR, cB, cN]) {
          out.add(mkMove(sq, t, pr));
        }
      }
    }

    if (b[to] == 0) {
      if (r == preRank) {
        addPromo(to);
      } else if (!caps) {
        out.add(mkMove(sq, to));
        if (r == startRank && b[to + dir] == 0) out.add(mkMove(sq, to + dir, 0, fDouble));
      }
    }
    for (final df in const [-1, 1]) {
      final nf = f + df;
      if (nf < 0 || nf > 7) continue;
      final c = to + df;
      final q = b[c];
      if (_enemy(q, s)) {
        if (r == preRank) {
          addPromo(c);
        } else {
          out.add(mkMove(sq, c));
        }
      } else if (q == 0 && c == ep) {
        out.add(mkMove(sq, c, 0, fEp));
      }
    }
  }

  void _genCastle(int sq, List<int> out) {
    if (side > 0) {
      if (sq != 4) return;
      if (castle & 1 != 0 && b[5] == 0 && b[6] == 0 && b[7] == cR &&
          !attacked(4, -1) && !attacked(5, -1) && !attacked(6, -1)) {
        out.add(mkMove(4, 6, 0, fCastle));
      }
      if (castle & 2 != 0 && b[3] == 0 && b[2] == 0 && b[1] == 0 && b[0] == cR &&
          !attacked(4, -1) && !attacked(3, -1) && !attacked(2, -1)) {
        out.add(mkMove(4, 2, 0, fCastle));
      }
    } else {
      if (sq != 60) return;
      if (castle & 4 != 0 && b[61] == 0 && b[62] == 0 && b[63] == -cR &&
          !attacked(60, 1) && !attacked(61, 1) && !attacked(62, 1)) {
        out.add(mkMove(60, 62, 0, fCastle));
      }
      if (castle & 8 != 0 && b[59] == 0 && b[58] == 0 && b[57] == 0 && b[56] == -cR &&
          !attacked(60, 1) && !attacked(59, 1) && !attacked(58, 1)) {
        out.add(mkMove(60, 58, 0, fCastle));
      }
    }
  }

  /// Is [sq] attacked by side [by] (1 white, -1 black)?
  bool attacked(int sq, int by) {
    final f = sq & 7;
    if (by > 0) {
      if (sq >= 8) {
        if (f > 0 && b[sq - 9] == cP) return true;
        if (f < 7 && b[sq - 7] == cP) return true;
      }
    } else {
      if (sq < 56) {
        if (f > 0 && b[sq + 7] == -cP) return true;
        if (f < 7 && b[sq + 9] == -cP) return true;
      }
    }
    final n = cN * by, k = cK * by, r = cR * by, bi = cB * by, q = cQ * by;
    for (final t in _knightT[sq]) {
      if (b[t] == n) return true;
    }
    for (final t in _kingT[sq]) {
      if (b[t] == k) return true;
    }
    final rays = _rays[sq];
    for (var d = 0; d < 8; d++) {
      for (final t in rays[d]) {
        final p = b[t];
        if (p == 0) continue;
        if (p == q || (d < 4 ? p == r : p == bi)) return true;
        break;
      }
    }
    return false;
  }

  bool inCheck() => attacked(kings[side > 0 ? 0 : 1], -side);

  void make(int m) {
    final from = mFrom(m), to = mTo(m), promo = mPromo(m), flag = mFlag(m);
    final piece = b[from];
    var cap = b[to];
    _undo
      ..add(m)
      ..add(0)
      ..add(castle)
      ..add(ep)
      ..add(half);
    if (flag & fEp != 0) {
      final cs = to - 8 * side;
      cap = b[cs];
      b[cs] = 0;
    }
    _undo[_undo.length - 4] = cap;
    b[to] = promo != 0 ? promo * side : piece;
    b[from] = 0;
    if (flag & fCastle != 0) {
      if (to == from + 2) {
        b[from + 1] = b[from + 3];
        b[from + 3] = 0;
      } else {
        b[from - 1] = b[from - 4];
        b[from - 4] = 0;
      }
    }
    if (piece == cK) kings[0] = to;
    if (piece == -cK) kings[1] = to;
    castle &= _castleMask[from] & _castleMask[to];
    ep = flag & fDouble != 0 ? (from + to) >> 1 : -1;
    half = (piece.abs() == cP || cap != 0) ? 0 : half + 1;
    if (side < 0) full++;
    side = -side;
  }

  void unmake() {
    final n = _undo.length;
    final m = _undo[n - 5], cap = _undo[n - 4];
    castle = _undo[n - 3];
    ep = _undo[n - 2];
    half = _undo[n - 1];
    _undo.length = n - 5;
    side = -side;
    if (side < 0) full--;
    final from = mFrom(m), to = mTo(m), promo = mPromo(m), flag = mFlag(m);
    final piece = promo != 0 ? cP * side : b[to];
    b[from] = piece;
    if (flag & fEp != 0) {
      b[to] = 0;
      b[to - 8 * side] = cap;
    } else {
      b[to] = cap;
    }
    if (flag & fCastle != 0) {
      if (to == from + 2) {
        b[from + 3] = b[from + 1];
        b[from + 1] = 0;
      } else {
        b[from - 4] = b[from - 1];
        b[from - 1] = 0;
      }
    }
    if (piece == cK) kings[0] = from;
    if (piece == -cK) kings[1] = from;
  }

  List<int> legal() {
    final ps = <int>[];
    gen(ps);
    final out = <int>[];
    final me = side;
    for (final m in ps) {
      make(m);
      if (!attacked(kings[me > 0 ? 0 : 1], -me)) out.add(m);
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
      if (!attacked(kings[me > 0 ? 0 : 1], -me)) n += depth == 1 ? 1 : perft(depth - 1);
      unmake();
    }
    return n;
  }

  /// Position key for repetition detection.
  String key() {
    var epKey = -1;
    if (ep >= 0) {
      // only relevant if a pawn could actually capture en passant
      final pawnFrom = ep - 8 * side;
      final f = ep & 7;
      if ((f > 0 && b[pawnFrom - 1] == cP * side) || (f < 7 && b[pawnFrom + 1] == cP * side)) epKey = ep;
    }
    return '${b.join(',')}|$side|$castle|$epKey';
  }

  bool insufficientMaterial() {
    final minors = <int>[];
    for (var sq = 0; sq < 64; sq++) {
      final t = b[sq].abs();
      if (t == 0 || t == cK) continue;
      if (t == cP || t == cR || t == cQ) return false;
      minors.add(sq);
    }
    if (minors.length <= 1) return true;
    // only bishops, all on same square colour
    if (minors.every((s) => b[s].abs() == cB)) {
      final c = ((minors.first >> 3) + (minors.first & 7)) & 1;
      return minors.every((s) => (((s >> 3) + (s & 7)) & 1) == c);
    }
    return false;
  }

  String san(int m, List<int> legalMoves) {
    final from = mFrom(m), to = mTo(m), promo = mPromo(m), flag = mFlag(m);
    final t = b[from].abs();
    String s;
    if (flag & fCastle != 0) {
      s = to > from ? 'O-O' : 'O-O-O';
    } else {
      final capture = b[to] != 0 || flag & fEp != 0;
      if (t == cP) {
        s = capture ? '${'abcdefgh'[from & 7]}x${sqName(to)}' : sqName(to);
        if (promo != 0) s += '=${' PNBRQK'[promo]}';
      } else {
        var dis = '';
        final others = [
          for (final o in legalMoves)
            if (mTo(o) == to && mFrom(o) != from && b[mFrom(o)].abs() == t) mFrom(o)
        ];
        if (others.isNotEmpty) {
          if (!others.any((o) => (o & 7) == (from & 7))) {
            dis = 'abcdefgh'[from & 7];
          } else if (!others.any((o) => (o >> 3) == (from >> 3))) {
            dis = '${(from >> 3) + 1}';
          } else {
            dis = sqName(from);
          }
        }
        s = '${' PNBRQK'[t]}$dis${capture ? 'x' : ''}${sqName(to)}';
      }
    }
    make(m);
    if (inCheck()) s += legal().isEmpty ? '#' : '+';
    unmake();
    return s;
  }
}

// ---------------------------------------------------------------- evaluation

const List<int> _val = [0, 100, 320, 330, 500, 900, 0];

// piece-square tables from white's view, rank 8 first (Michniewski)
const List<List<int>> _pst = [
  [],
  [
    0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, //
    0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0,
  ],
  [
    -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, //
    -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, //
    -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50,
  ],
  [
    -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, //
    -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, //
    -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20,
  ],
  [
    0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, //
    -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0,
  ],
  [
    -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, //
    -5, 0, 5, 5, 5, 5, 0, -5, 0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, //
    -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20,
  ],
  [
    -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, //
    -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, //
    -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, //
    20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20,
  ],
];

const List<int> _kingEnd = [
  -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, //
  -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, //
  -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, //
  -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50,
];

/// Static evaluation from white's point of view.
int chessEval(ChessPos p) {
  var score = 0, heavy = 0;
  final mat = [0, 0];
  for (var sq = 0; sq < 64; sq++) {
    final v = p.b[sq];
    if (v == 0) continue;
    final t = v.abs();
    if (t != cP && t != cK) heavy += _val[t];
    final idx = v > 0 ? (7 - (sq >> 3)) * 8 + (sq & 7) : sq;
    final s = _val[t] + (t == cK ? 0 : _pst[t][idx]);
    mat[v > 0 ? 0 : 1] += _val[t];
    score += v > 0 ? s : -s;
  }
  final endgame = heavy <= 1400;
  for (var c = 0; c < 2; c++) {
    final sq = p.kings[c];
    final idx = c == 0 ? (7 - (sq >> 3)) * 8 + (sq & 7) : sq;
    final s = endgame ? _kingEnd[idx] : _pst[cK][idx];
    score += c == 0 ? s : -s;
  }
  if (endgame) {
    // drive the losing king to the edge and bring our king closer (helps mating)
    final diff = mat[0] - mat[1];
    if (diff.abs() >= 300) {
      final strong = diff > 0 ? 0 : 1;
      final wk = p.kings[strong], lk = p.kings[1 - strong];
      final lf = lk & 7, lr = lk >> 3;
      final int centerDist = max(3 - lf, lf - 4) + max(3 - lr, lr - 4);
      final kingDist = (lf - (wk & 7)).abs() + (lr - (wk >> 3)).abs();
      final int bonus = centerDist * 10 + (14 - kingDist) * 4;
      score += strong == 0 ? bonus : -bonus;
    }
  }
  return score;
}

const int chessMate = 30000;

class ChessSearch {
  final ChessPos p;
  final int limitMs;
  final int maxDepth;
  final Random rng;
  final Stopwatch _sw = Stopwatch();
  int _nodes = 0;
  bool _stop = false;
  ChessSearch(this.p, {required this.limitMs, required this.maxDepth, required this.rng});

  int _order(int m) {
    final cap = p.b[mTo(m)].abs();
    var s = 0;
    if (cap != 0) s += 1000 + _val[cap] * 10 - _val[p.b[mFrom(m)].abs()] ~/ 10;
    if (mFlag(m) & fEp != 0) s += 1000 + 900;
    if (mPromo(m) != 0) s += 8000 + mPromo(m);
    return s;
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
    final stand = chessEval(p) * p.side;
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (ply > 12) return stand;
    final ms = <int>[];
    p.gen(ms, caps: true);
    _sortMoves(ms);
    final me = p.side;
    for (final m in ms) {
      p.make(m);
      if (p.attacked(p.kings[me > 0 ? 0 : 1], -me)) {
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
    var best = -chessMate;
    for (final m in ms) {
      p.make(m);
      if (p.attacked(p.kings[me > 0 ? 0 : 1], -me)) {
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
    if (legal == 0) return p.inCheck() ? -chessMate + ply : 0;
    return best;
  }

  /// Returns the best legal move (or -1 if none).
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
      var alpha = -chessMate - 1;
      var iterBest = -1;
      for (final m in root) {
        p.make(m);
        final v = -_search(depth - 1, -chessMate - 1, -alpha, 1);
        p.unmake();
        if (_stop) break;
        if (v > alpha) {
          alpha = v;
          iterBest = m;
        }
      }
      if (_stop) {
        // previous best was searched first at this depth, so iterBest is at least as good
        if (iterBest >= 0) best = iterBest;
        break;
      }
      if (iterBest >= 0) {
        best = iterBest;
        root.remove(best);
        root.insert(0, best);
      }
      if (alpha.abs() > chessMate - 100) break; // mate found
      if (_sw.elapsedMilliseconds * 4 > limitMs) break; // next depth would not finish
    }
    return best;
  }
}
