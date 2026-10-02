import 'dart:math';

import '../../src/engine.dart';

/// 蜂巢 Hive — 六角格（轴向坐标 q, r），无棋盘，棋子即棋盘。
///
/// 棋子编码：piece = color * 8 + type；type 见 [hiveTypes]。
/// 格子编码：key = ((q + 128) << 8) | (r + 128)，相邻格为 key + [hDirs]。
const hiveTypes = ['Q', 'S', 'B', 'G', 'A', 'M', 'L', 'P'];
const hiveNames = ['蜂后', '蜘蛛', '甲虫', '蚱蜢', '蚂蚁', '蚊子', '瓢虫', '鼠妇'];
const hiveBaseCounts = [1, 2, 2, 3, 3, 0, 0, 0];

const tQ = 0, tS = 1, tB = 2, tG = 3, tA = 4, tM = 5, tL = 6, tP = 7;

int hk(int q, int r) => ((q + 128) << 8) | (r + 128);
int hq(int k) => (k >> 8) - 128;
int hr(int k) => (k & 255) - 128;

/// (1,0) (1,-1) (0,-1) (-1,0) (-1,1) (0,1) — 依次相邻（绕一圈）。
const hDirs = [256, 255, -1, -256, -255, 1];

class HiveMove {
  /// 0 打入 / 1 移动 / 2 鼠妇搬运
  final int kind;
  final int piece; // kind 0: piece code
  final int from;
  final int to;
  final int by; // kind 2: the pillbug (or mosquito) cell
  const HiveMove.place(this.piece, this.to)
      : kind = 0,
        from = -1,
        by = -1;
  const HiveMove.move(this.from, this.to)
      : kind = 1,
        piece = -1,
        by = -1;
  const HiveMove.thrown(this.by, this.from, this.to)
      : kind = 2,
        piece = -1;

  @override
  bool operator ==(Object o) =>
      o is HiveMove && o.kind == kind && o.piece == piece && o.from == from && o.to == to && o.by == by;
  @override
  int get hashCode => Object.hash(kind, piece, from, to, by);
}

class HiveState {
  final Map<int, List<int>> st;
  final List<List<int>> hand; // [color][type]
  int toMove;
  final List<int> placed;

  /// Cell of the piece thrown by a pillbug last turn: it can't move / act now.
  int frozen;

  /// Cell of the piece the opponent moved/placed last turn: can't be thrown.
  int lastMoved;

  HiveState(bool expansion)
      : st = {},
        hand = [
          for (var c = 0; c < 2; c++) [for (var t = 0; t < 8; t++) t >= 5 ? (expansion ? 1 : 0) : hiveBaseCounts[t]]
        ],
        toMove = 0,
        placed = [0, 0],
        frozen = -1,
        lastMoved = -1;

  HiveState._(this.st, this.hand, this.toMove, this.placed, this.frozen, this.lastMoved);

  HiveState clone() => HiveState._(
        {for (final e in st.entries) e.key: List.of(e.value)},
        [List.of(hand[0]), List.of(hand[1])],
        toMove,
        List.of(placed),
        frozen,
        lastMoved,
      );

  int height(int k) => st[k]?.length ?? 0;
  int top(int k) => st[k]!.last;
  bool queenPlaced(int c) => hand[c][tQ] == 0;
  int piecesInHand(int c) => hand[c].fold(0, (a, b) => a + b);

  int _lift(int k) {
    final s = st[k]!;
    final p = s.removeLast();
    if (s.isEmpty) st.remove(k);
    return p;
  }

  void _drop(int k, int p) => (st[k] ??= []).add(p);

  /// Queen cell of color c (queen may be buried under beetles) or -1.
  int queenCell(int c) {
    final q = c * 8 + tQ;
    for (final e in st.entries) {
      if (e.value.contains(q)) return e.key;
    }
    return -1;
  }

  int occupiedAround(int k) {
    var n = 0;
    for (final d in hDirs) {
      if (st.containsKey(k + d)) n++;
    }
    return n;
  }

  bool surrounded(int c) {
    final q = queenCell(c);
    return q >= 0 && occupiedAround(q) == 6;
  }

  /// Cells whose removal would split the hive (one-hive rule).
  Set<int> articulation() {
    final out = <int>{};
    if (st.length < 3) return out;
    final disc = <int, int>{}, low = <int, int>{};
    var t = 0;
    void dfs(int u, int parent) {
      disc[u] = low[u] = t++;
      var children = 0;
      for (final d in hDirs) {
        final v = u + d;
        if (!st.containsKey(v)) continue;
        if (!disc.containsKey(v)) {
          children++;
          dfs(v, u);
          if (low[v]! < low[u]!) low[u] = low[v]!;
          if (parent != -1 && low[v]! >= disc[u]!) out.add(u);
        } else if (v != parent) {
          if (disc[v]! < low[u]!) low[u] = disc[v]!;
        }
      }
      if (parent == -1 && children > 1) out.add(u);
    }

    dfs(st.keys.first, -1);
    return out;
  }

  /// Freedom-to-move / gate rule between [from] and from+dir[i]. [a] = height
  /// at the source without the moving piece, [b] = height of the destination.
  bool canSlide(int from, int i, int a, int b) {
    final h1 = height(from + hDirs[(i + 5) % 6]), h2 = height(from + hDirs[(i + 1) % 6]);
    final hi = a > b ? a : b;
    if ((h1 < h2 ? h1 : h2) > hi) return false;
    if (hi == 0 && h1 == 0 && h2 == 0) return false; // would lose contact with the hive
    return true;
  }

  // ---- movement patterns (call with the moving piece lifted) ----

  void _slide1(int from, Set<int> out) {
    for (var i = 0; i < 6; i++) {
      final to = from + hDirs[i];
      if (height(to) == 0 && canSlide(from, i, 0, 0)) out.add(to);
    }
  }

  void _beetle(int from, Set<int> out) {
    final a = height(from);
    for (var i = 0; i < 6; i++) {
      final to = from + hDirs[i];
      final b = height(to);
      if (a == 0 && b == 0) {
        if (canSlide(from, i, 0, 0)) out.add(to);
      } else if (canSlide(from, i, a, b)) {
        out.add(to);
      }
    }
  }

  void _hopper(int from, Set<int> out) {
    for (final d in hDirs) {
      var t = from + d;
      if (height(t) == 0) continue;
      while (height(t) > 0) {
        t += d;
      }
      out.add(t);
    }
  }

  void _ant(int from, Set<int> out) {
    final seen = <int>{from};
    final q = <int>[from];
    while (q.isNotEmpty) {
      final x = q.removeLast();
      for (var i = 0; i < 6; i++) {
        final y = x + hDirs[i];
        if (seen.contains(y) || height(y) != 0) continue;
        if (!canSlide(x, i, 0, 0)) continue;
        seen.add(y);
        q.add(y);
        out.add(y);
      }
    }
  }

  void _spider(int from, Set<int> out) {
    final path = <int>[from];
    void go(int x, int depth) {
      if (depth == 3) {
        out.add(x);
        return;
      }
      for (var i = 0; i < 6; i++) {
        final y = x + hDirs[i];
        if (height(y) != 0 || path.contains(y)) continue;
        if (!canSlide(x, i, 0, 0)) continue;
        path.add(y);
        go(y, depth + 1);
        path.removeLast();
      }
    }

    go(from, 0);
  }

  void _ladybug(int from, Set<int> out) {
    final a0 = height(from);
    for (var i = 0; i < 6; i++) {
      final n1 = from + hDirs[i];
      final h1 = height(n1);
      if (h1 == 0 || !canSlide(from, i, a0, h1)) continue;
      for (var j = 0; j < 6; j++) {
        final n2 = n1 + hDirs[j];
        final h2 = height(n2);
        if (n2 == from || h2 == 0 || !canSlide(n1, j, h1, h2)) continue;
        for (var k = 0; k < 6; k++) {
          final e = n2 + hDirs[k];
          if (e == from || height(e) != 0) continue;
          if (canSlide(n2, k, h2, 0)) out.add(e);
        }
      }
    }
  }

  void _byType(int t, int from, Set<int> out) {
    switch (t) {
      case tQ:
      case tP:
        _slide1(from, out);
      case tB:
        _beetle(from, out);
      case tG:
        _hopper(from, out);
      case tA:
        _ant(from, out);
      case tS:
        _spider(from, out);
      case tL:
        _ladybug(from, out);
    }
  }

  /// Destinations for the top piece at [from] moving itself.
  Set<int> destinations(int from) {
    final p = _lift(from);
    final out = <int>{};
    try {
      final t = p & 7;
      if (t == tM) {
        if (height(from) > 0) {
          _beetle(from, out);
        } else {
          final types = <int>{};
          for (final d in hDirs) {
            final n = from + d;
            if (height(n) > 0) types.add(top(n) & 7);
          }
          types.remove(tM);
          for (final tt in types) {
            _byType(tt, from, out);
          }
        }
      } else {
        _byType(t, from, out);
      }
    } finally {
      _drop(from, p);
    }
    out.remove(from);
    return out;
  }

  /// Does the top piece at [k] have the pillbug power right now?
  bool _hasPillbugPower(int k) {
    if (height(k) != 1) return false;
    final t = top(k) & 7;
    if (t == tP) return true;
    if (t != tM) return false;
    for (final d in hDirs) {
      final n = k + d;
      if (height(n) > 0 && (top(n) & 7) == tP) return true;
    }
    return false;
  }

  void _throws(int p, Set<int> pinned, List<HiveMove> out) {
    for (var i = 0; i < 6; i++) {
      final n = p + hDirs[i];
      if (height(n) != 1 || n == frozen || n == lastMoved || pinned.contains(n)) continue;
      final piece = _lift(n);
      try {
        if (!canSlide(n, (i + 3) % 6, 0, 1)) continue;
        for (var j = 0; j < 6; j++) {
          final e = p + hDirs[j];
          if (e == n || height(e) != 0) continue;
          if (canSlide(p, j, 1, 0)) out.add(HiveMove.thrown(p, n, e));
        }
      } finally {
        _drop(n, piece);
      }
    }
  }

  /// Legal placement cells for color [c].
  List<int> placeCells(int c) {
    if (st.isEmpty) return [hk(0, 0)];
    final cand = <int>{};
    if (placed[c] == 0) {
      for (final k in st.keys) {
        for (final d in hDirs) {
          if (!st.containsKey(k + d)) cand.add(k + d);
        }
      }
      return cand.toList()..sort();
    }
    for (final e in st.entries) {
      if (e.value.last >> 3 != c) continue;
      for (final d in hDirs) {
        final x = e.key + d;
        if (st.containsKey(x)) continue;
        var ok = true;
        for (final d2 in hDirs) {
          final y = x + d2;
          final s = st[y];
          if (s != null && s.last >> 3 != c) {
            ok = false;
            break;
          }
        }
        if (ok) cand.add(x);
      }
    }
    return cand.toList()..sort();
  }

  /// Piece types color [c] may place now.
  List<int> placeTypes(int c) {
    if (placed[c] == 3 && hand[c][tQ] > 0) return [tQ];
    return [
      for (var t = 0; t < 8; t++)
        if (hand[c][t] > 0 && !(t == tQ && placed[c] == 0)) t
    ];
  }

  List<HiveMove> legalMoves() {
    final c = toMove;
    final out = <HiveMove>[];
    final types = placeTypes(c);
    if (types.isNotEmpty) {
      final cells = placeCells(c);
      for (final t in types) {
        for (final k in cells) {
          out.add(HiveMove.place(c * 8 + t, k));
        }
      }
    }
    if (!queenPlaced(c)) return out;
    final pinned = articulation();
    final seenThrow = <HiveMove>{};
    for (final k in st.keys.toList()) {
      final s = st[k]!;
      if (s.last >> 3 != c || k == frozen) continue;
      if (!(s.length == 1 && pinned.contains(k))) {
        for (final to in destinations(k)) {
          out.add(HiveMove.move(k, to));
        }
      }
      if (_hasPillbugPower(k)) {
        final th = <HiveMove>[];
        _throws(k, pinned, th);
        for (final m in th) {
          if (seenThrow.add(m)) out.add(m);
        }
      }
    }
    return out;
  }

  void apply(HiveMove m) {
    final c = toMove;
    if (m.kind == 0) {
      _drop(m.to, m.piece);
      hand[c][m.piece & 7]--;
      placed[c]++;
      frozen = -1;
    } else {
      final p = _lift(m.from);
      _drop(m.to, p);
      frozen = m.kind == 2 ? m.to : -1;
    }
    lastMoved = m.to;
    toMove = 1 - c;
  }

  void pass() {
    toMove = 1 - toMove;
    frozen = -1;
    lastMoved = -1;
  }

  String key() {
    final ks = st.keys.toList()..sort();
    final b = StringBuffer('$toMove|$frozen|$lastMoved|');
    for (final k in ks) {
      b
        ..write(k)
        ..write(':')
        ..write(st[k]!.join(','))
        ..write(';');
    }
    b.write(hand[0].join(','));
    b.write('/');
    b.write(hand[1].join(','));
    return b.toString();
  }
}

/// Iterative-deepening alpha-beta for Hive.
class HiveAI {
  final Stopwatch _sw = Stopwatch();
  int _limit = 400;
  bool _timeout = false;
  final Random rng;
  HiveAI(this.rng);

  static const _w = [3, 2, 4, 2, 6, 5, 3, 3];
  static const _win = 100000;

  int eval(HiveState s, int me) {
    final opp = 1 - me;
    var v = 0;
    final qm = s.queenCell(me), qo = s.queenCell(opp);
    final nm = qm < 0 ? 0 : s.occupiedAround(qm), no = qo < 0 ? 0 : s.occupiedAround(qo);
    v += (no * no * 9 + no * 20) - (nm * nm * 9 + nm * 20);
    final pinned = s.articulation();
    for (final e in s.st.entries) {
      final k = e.key;
      final stack = e.value;
      final p = stack.last;
      final c = p >> 3, t = p & 7;
      final sign = c == me ? 1 : -1;
      var mobile = !(stack.length == 1 && pinned.contains(k));
      if (mobile && stack.length == 1 && t != tB && t != tG && t != tM && t != tL) {
        // ground crawlers with every side blocked can't move
        if (s.occupiedAround(k) >= 5) mobile = false;
      }
      if (mobile) v += sign * _w[t] * 3;
      if (stack.length > 1) {
        // beetle sitting on something: pins it
        for (var i = 0; i < stack.length - 1; i++) {
          final under = stack[i];
          if (under >> 3 != c) v += sign * (under & 7 == tQ ? 40 : _w[under & 7] * 2);
        }
      }
      // pieces touching the enemy queen
      if (c == me && qo >= 0 && _adj(k, qo)) v += 6;
      if (c == opp && qm >= 0 && _adj(k, qm)) v -= 6;
    }
    // queen still in hand late is bad
    if (!s.queenPlaced(me) && s.placed[me] >= 2) v -= 30;
    if (!s.queenPlaced(opp) && s.placed[opp] >= 2) v += 30;
    return v;
  }

  static bool _adj(int a, int b) {
    for (final d in hDirs) {
      if (a + d == b) return true;
    }
    return false;
  }

  /// Terminal score for the side to move in [s] (or null).
  int? _terminal(HiveState s, int ply) {
    final me = s.toMove;
    final a = s.surrounded(me), b = s.surrounded(1 - me);
    if (a && b) return 0;
    if (a) return -_win + ply;
    if (b) return _win - ply;
    return null;
  }

  List<HiveMove> _order(HiveState s, List<HiveMove> ms) {
    final opp = 1 - s.toMove;
    final qo = s.queenCell(opp), qm = s.queenCell(s.toMove);
    int score(HiveMove m) {
      var v = 0;
      if (qo >= 0 && _adj(m.to, qo)) v += 10;
      if (qo >= 0 && m.from >= 0 && _adj(m.from, qo)) v -= 6;
      if (qm >= 0 && m.kind == 2 && _adj(m.from, qm)) v += 8; // pull attackers off my queen
      if (m.kind == 1 && m.to == qo) v += 12;
      if (m.kind == 0) v -= 1;
      return v;
    }

    final sc = {for (final m in ms) m: score(m) + rng.nextInt(3)};
    return List.of(ms)..sort((a, b) => sc[b]!.compareTo(sc[a]!));
  }

  int _search(HiveState s, int depth, int alpha, int beta, int ply) {
    if (_sw.elapsedMilliseconds > _limit) {
      _timeout = true;
      return 0;
    }
    final term = _terminal(s, ply);
    if (term != null) return term;
    if (depth <= 0) return eval(s, s.toMove);
    var ms = s.legalMoves();
    if (ms.isEmpty) {
      final n = s.clone()..pass();
      return -_search(n, depth - 1, -beta, -alpha, ply + 1);
    }
    ms = _order(s, ms);
    var best = -_win * 2;
    for (final m in ms) {
      final n = s.clone()..apply(m);
      final v = -_search(n, depth - 1, -beta, -alpha, ply + 1);
      if (_timeout) return 0;
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  HiveMove best(HiveState root, {int maxDepth = 3, int limitMs = 400}) {
    var ms = root.legalMoves();
    _sw
      ..reset()
      ..start();
    _limit = limitMs;
    ms = _order(root, ms);
    var bestMove = ms.first;
    // immediate win
    for (final m in ms) {
      final n = root.clone()..apply(m);
      if (n.surrounded(1 - root.toMove) && !n.surrounded(root.toMove)) return m;
    }
    for (var d = 1; d <= maxDepth; d++) {
      _timeout = false;
      var alpha = -_win * 2;
      HiveMove? bm;
      final order = [bestMove, ...ms.where((m) => m != bestMove)];
      for (final m in order) {
        final n = root.clone()..apply(m);
        final v = -_search(n, d - 1, -_win * 2, -alpha, 1);
        if (_timeout) break;
        if (v > alpha || bm == null) {
          alpha = v;
          bm = m;
        }
      }
      if (_timeout && d > 1) break;
      if (bm != null) bestMove = bm;
      if (_timeout || alpha > _win ~/ 2) break;
    }
    return bestMove;
  }
}

class Hive extends GameEngine {
  Hive(super.setup);

  late HiveState s;
  int whiteSeat = 0;
  int plies = 0;
  int winner = -1; // seat, 2 = draw
  String result = '';
  String note = '';
  Map<String, dynamic>? last;
  final Map<String, int> _reps = {};
  static const maxPlies = 400;

  bool get expansion => setup.opt<bool>('expansion', false);
  bool get over => winner != -1;
  int seatOf(int color) => color == 0 ? whiteSeat : 1 - whiteSeat;
  int colorOf(int seat) => seat == whiteSeat ? 0 : 1;
  int get turnSeat => seatOf(s.toMove);

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turnSeat];

  @override
  void start() {
    s = HiveState(expansion);
    whiteSeat = rng.nextInt(2);
    _reps[s.key()] = 1;
    host.log('蜂巢：${name(whiteSeat)} 执白先行');
  }

  static String cellText(int k) => '(${hq(k)},${hr(k)})';

  HiveMove _parse(Map<String, dynamic> a) {
    final type = a['type'];
    if (type == 'place') {
      final t = hiveTypes.indexOf(asStr(a['piece']));
      if (t < 0) throw GameError('未知棋子');
      return HiveMove.place(s.toMove * 8 + t, hk(asInt(a['q'], 999).clamp(-100, 100), asInt(a['r'], 999).clamp(-100, 100)));
    }
    final f = asIntList(a['from']), t = asIntList(a['to']);
    if (f.length != 2 || t.length != 2) throw GameError('操作格式错误');
    int key(List<int> xy) => hk(xy[0].clamp(-100, 100), xy[1].clamp(-100, 100));
    if (type == 'move') return HiveMove.move(key(f), key(t));
    if (type == 'throw') {
      final b = asIntList(a['by']);
      if (b.length != 2) throw GameError('操作格式错误');
      return HiveMove.thrown(key(b), key(f), key(t));
    }
    throw GameError('未知操作');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') return resign(seat);
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    if (seat != turnSeat) throw GameError('还没轮到你');
    final m = _parse(a);
    final legal = s.legalMoves();
    if (!legal.contains(m)) {
      if (m.kind == 0) {
        final c = s.toMove;
        if (s.placed[c] == 3 && s.hand[c][tQ] > 0) throw GameError('第 4 手之前必须放下蜂后');
        if (s.placed[c] == 0 && m.piece & 7 == tQ) throw GameError('第一手不能放蜂后（锦标赛规则）');
        if (s.hand[c][m.piece & 7] <= 0) throw GameError('这种棋子已经用完了');
        throw GameError('这里不能放（新棋子只能挨着己方、不能挨着对方）');
      }
      if (!s.queenPlaced(s.toMove)) throw GameError('放下蜂后之前不能移动棋子');
      throw GameError('不能这样走（注意一体规则与自由移动规则）');
    }
    final c = s.toMove;
    final mover = m.kind == 0 ? m.piece : s.top(m.from);
    s.apply(m);
    plies++;
    final pn = hiveNames[mover & 7];
    last = {
      'kind': m.kind,
      'piece': hiveTypes[mover & 7],
      'color': mover >> 3,
      'from': m.from < 0 ? null : [hq(m.from), hr(m.from)],
      'to': [hq(m.to), hr(m.to)],
      'by': m.by < 0 ? null : [hq(m.by), hr(m.by)],
    };
    note = switch (m.kind) {
      0 => '${name(seat)} 打入 $pn',
      1 => '${name(seat)} 移动$pn',
      _ => '${name(seat)} 用鼠妇搬运 ${(mover >> 3) == c ? '己方' : '对方'}$pn',
    };
    _afterMove();
  }

  void _afterMove() {
    final w = s.surrounded(0), b = s.surrounded(1);
    if (w || b) {
      if (w && b) {
        winner = 2;
        result = '双方蜂后同时被围，和棋';
      } else {
        winner = seatOf(w ? 1 : 0);
        result = '${name(winner)} 围住对方蜂后，获胜';
      }
      host.log(result);
      return;
    }
    // auto pass while the side to move has nothing legal
    for (var i = 0; i < 2; i++) {
      if (s.legalMoves().isNotEmpty) break;
      if (i == 1) {
        winner = 2;
        result = '双方都无棋可走，和棋';
        host.log(result);
        return;
      }
      final msg = '${name(turnSeat)} 无棋可走，跳过';
      note = note.isEmpty ? msg : '$note · $msg';
      host.log(msg);
      s.pass();
      plies++;
    }
    final k = s.key();
    final n = (_reps[k] ?? 0) + 1;
    _reps[k] = n;
    if (n >= 3) {
      winner = 2;
      result = '同一局面第三次出现，和棋';
      host.log(result);
      return;
    }
    if (plies >= maxPlies) {
      winner = 2;
      result = '达到 $maxPlies 手上限，和棋';
      host.log(result);
    }
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    winner = 1 - seat;
    result = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;
  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    winner = 2;
    result = '双方同意和棋';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final moves = <List<int>>[];
    final placeCells = <List<int>>[];
    var placeTypes = <String>[];
    if (!over) {
      final c = s.toMove;
      for (final m in s.legalMoves()) {
        if (m.kind == 1) moves.add([hq(m.from), hr(m.from), hq(m.to), hr(m.to)]);
        if (m.kind == 2) moves.add([hq(m.from), hr(m.from), hq(m.to), hr(m.to), hq(m.by), hr(m.by)]);
      }
      final types = s.placeTypes(c);
      if (types.isNotEmpty) {
        placeTypes = [for (final t in types) hiveTypes[t]];
        placeCells.addAll([for (final k in s.placeCells(c)) [hq(k), hr(k)]]);
      }
    }
    final ks = s.st.keys.toList()..sort();
    return {
      'stacks': [
        for (final k in ks)
          {
            'q': hq(k),
            'r': hr(k),
            'p': [for (final p in s.st[k]!) '${p >> 3 == 0 ? 'w' : 'b'}${hiveTypes[p & 7]}'],
          }
      ],
      'hand': [
        for (var c = 0; c < 2; c++) {for (var t = 0; t < 8; t++) hiveTypes[t]: s.hand[c][t]}
      ],
      'expansion': expansion,
      'whiteSeat': whiteSeat,
      'toMove': s.toMove,
      'turn': turnSeat,
      'placed': s.placed,
      'queenPlaced': [s.queenPlaced(0), s.queenPlaced(1)],
      'moves': moves,
      'placeCells': placeCells,
      'placeTypes': placeTypes,
      'frozen': s.frozen < 0 ? null : [hq(s.frozen), hr(s.frozen)],
      'last': last,
      'note': note,
      'plies': plies,
      'winner': winner,
      'result': result,
      'over': over,
    };
  }

  Map<String, dynamic> _enc(HiveMove m) => switch (m.kind) {
        0 => {'type': 'place', 'piece': hiveTypes[m.piece & 7], 'q': hq(m.to), 'r': hr(m.to)},
        1 => {'type': 'move', 'from': [hq(m.from), hr(m.from)], 'to': [hq(m.to), hr(m.to)]},
        _ => {
            'type': 'throw',
            'by': [hq(m.by), hr(m.by)],
            'from': [hq(m.from), hr(m.from)],
            'to': [hq(m.to), hr(m.to)]
          },
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turnSeat) return null;
    final ms = s.legalMoves();
    if (ms.isEmpty) return null; // never happens: engine auto-passes
    final ai = HiveAI(rng);
    final lvl = botLevel;
    if (lvl == 0) {
      if (rng.nextDouble() < 0.45) return _enc(ms[rng.nextInt(ms.length)]);
      return _enc(ai.best(s, maxDepth: 1, limitMs: 150));
    }
    // Opening book-ish: early placements don't need search.
    if (s.placed[s.toMove] < 2 && ms.every((m) => m.kind == 0)) {
      final pref = [tG, tS, tB, tA, tM, tL, tP];
      for (final t in pref) {
        final c = ms.where((m) => (m.piece & 7) == t).toList();
        if (c.isNotEmpty && rng.nextDouble() < 0.7) return _enc(c[rng.nextInt(c.length)]);
      }
      return _enc(ms[rng.nextInt(ms.length)]);
    }
    return _enc(ai.best(s, maxDepth: lvl >= 2 ? 3 : 2, limitMs: lvl >= 2 ? 1200 : 400));
  }
}
