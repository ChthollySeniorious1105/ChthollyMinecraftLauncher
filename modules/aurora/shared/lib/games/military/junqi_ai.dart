/// Fair 军棋 bots.
///
/// Nothing in this file touches the engine's true board. A bot only receives
///  * the view its seat got when the game started (`startBoard`),
///  * its current view (`view(seat)`), and
///  * the public event log (moves, 裁判 results, flips, flag reveals, eliminations).
/// From those it keeps a per-seat belief (a set of possible ranks for every
/// piece) and decides with expected values over those beliefs.
library;

import 'dart:math';

import 'junqi.dart';
import 'junqi_geo.dart';

const _nRanks = 12;
const _allMask = (1 << _nRanks) - 1;
int _bit(int r) => 1 << r;
bool _has(int mask, int r) => mask & (1 << r) != 0;

/// Material values used by the bots.
const junqiValue = <int, double>{
  9: 100, 8: 80, 7: 60, 6: 45, 5: 35, 4: 25, 3: 15, 2: 10, 1: 18, 10: 50, 11: 20, 0: 1000, //
};
const _flagPrize = 3000.0;

final List<int> _armyCount = () {
  final c = List.filled(_nRanks, 0);
  for (final r in junqiArmy) {
    c[r]++;
  }
  return c;
}();

/// Public result code of attacker [a] hitting defender [d]:
/// 2 flag captured, 1 attacker wins, -1 attacker dies, 0 both removed.
int junqiOutcome(int a, int d) => d == kFlag ? 2 : junqiBattle(a, d);

const _resCode = {'win': 1, 'lose': -1, 'tie': 0, 'flag': 2};

/// Rank mask allowed by the layout rules at [n] before anything is known.
int junqiInitialMask(JNode n) {
  var m = _allMask;
  if (n.kind != JKind.hq) m &= ~_bit(kFlag);
  if (n.lr < 4) m &= ~_bit(kMine);
  if (n.lr == 0) m &= ~_bit(kBomb);
  return m;
}

class _Tok {
  final int owner;
  int mask;
  bool moved = false;
  bool alive = true;
  _Tok(this.owner, this.mask);
  bool get known => mask != 0 && (mask & (mask - 1)) == 0;
  int get rank => known ? mask.bitLength - 1 : -1;
}

/// Belief state of one seat in 两国/四国.
class JunqiMind {
  final JunqiGeo geo;
  final bool four;
  final int seat;
  final List<_Tok> _toks = [];
  late final List<int?> _at;
  int _seen = 0;
  List<int> _lastDead = const [];

  JunqiMind(this.geo, this.four, this.seat, List startBoard) {
    _at = List.filled(geo.nodes.length, null);
    for (var i = 0; i < startBoard.length; i++) {
      final c = startBoard[i];
      if (c == null) continue;
      final m = c as Map;
      final o = m['o'] as int, k = m['k'] as int;
      _at[i] = _toks.length;
      _toks.add(_Tok(o, k >= 0 ? _bit(k) : junqiInitialMask(geo.nodes[i])));
    }
  }

  int team(int s) => four ? s % 2 : s;

  /// Possible ranks (bit mask) of the piece at [node], or null if empty.
  int? maskAt(int node) {
    final t = _at[node];
    return t == null ? null : _toks[t].mask;
  }

  /// Feeds the not-yet-seen part of the public log.
  void update(List<Map<String, dynamic>> log) {
    for (; _seen < log.length; _seen++) {
      final e = log[_seen];
      switch (e['t']) {
        case 'mv':
          _move(e['s'] as int, e['f'] as int, e['to'] as int, e['r'] as String);
        case 'flagshown':
          final o = e['o'] as int;
          final t = _at[e['n'] as int];
          if (t != null) _toks[t].mask = _bit(kFlag);
          // the 司令 just died: it is the piece of that owner lost in the last battle
          final dead = _lastDead.where((x) => _toks[x].owner == o).toList();
          if (dead.length == 1) _toks[dead.first].mask = _bit(kCmd);
        case 'out':
          final s = e['s'] as int;
          for (var i = 0; i < _at.length; i++) {
            final t = _at[i];
            if (t != null && _toks[t].owner == s) {
              _toks[t].alive = false;
              _at[i] = null;
            }
          }
      }
    }
  }

  List<JP?> _pseudoBoard() => [
        for (final t in _at)
          t == null ? null : JP(_toks[t].owner, _toks[t].known ? _toks[t].rank : 5)
      ];

  /// Targets of the piece at [from] if it were a non-engineer ([eng]=false) or an engineer.
  List<int> _reach(List<JP?> bd, int from, bool eng) {
    final p = bd[from]!;
    final save = bd[from];
    bd[from] = JP(p.owner, eng ? kEng : 5);
    final t = junqiTargets(geo, bd, from, (q) => team(q.owner) == team(p.owner));
    bd[from] = save;
    return t;
  }

  void _narrow(_Tok t, int keep) {
    final m = t.mask & keep;
    if (m != 0) t.mask = m;
  }

  void _move(int s, int f, int to, String res) {
    final a = _at[f];
    if (a == null) return;
    final ta = _toks[a];
    ta.moved = true;
    _narrow(ta, ~(_bit(kFlag) | _bit(kMine)));
    // travelled where a non-engineer can't (turned a corner on the railway) -> 工兵
    if (!ta.known && _has(ta.mask, kEng) && !geo.adj[f].contains(to) && !_reach(_pseudoBoard(), f, false).contains(to)) {
      ta.mask = _bit(kEng);
    }
    final d = _at[to];
    switch (res) {
      case 'move':
        _at[to] = a;
        _at[f] = null;
        _lastDead = const [];
      default:
        if (d == null) return;
        final code = _resCode[res]!;
        _prune(a, d, code);
        if (code == 1 || code == 2) {
          _toks[d].alive = false;
          _at[to] = a;
          _at[f] = null;
          _lastDead = [d];
        } else if (code == -1) {
          ta.alive = false;
          _at[f] = null;
          _lastDead = [a];
        } else {
          ta.alive = false;
          _toks[d].alive = false;
          _at[f] = null;
          _at[to] = null;
          _lastDead = [a, d];
        }
    }
  }

  /// Keeps only rank pairs consistent with the observed 裁判 result.
  void _prune(int a, int d, int code) {
    final ma = _toks[a].mask, md = _toks[d].mask;
    var na = 0, nd = 0;
    for (var x = 0; x < _nRanks; x++) {
      if (!_has(ma, x)) continue;
      for (var y = 0; y < _nRanks; y++) {
        if (_has(md, y) && junqiOutcome(x, y) == code) {
          na |= _bit(x);
          nd |= _bit(y);
        }
      }
    }
    if (na != 0) _toks[a].mask = na;
    if (nd != 0) _toks[d].mask = nd;
  }

  /// Hard counting deductions for one army.
  void _propagate(int owner) {
    final ts = [for (final t in _toks) if (t.owner == owner) t];
    for (var guard = 0; guard < 30; guard++) {
      var changed = false;
      for (var r = 0; r < _nRanks; r++) {
        final sure = ts.where((t) => t.mask == _bit(r)).length;
        final can = ts.where((t) => _has(t.mask, r)).toList();
        if (sure >= _armyCount[r]) {
          for (final t in can) {
            if (t.mask != _bit(r) && t.mask & ~_bit(r) != 0) {
              t.mask &= ~_bit(r);
              changed = true;
            }
          }
        } else if (can.length == _armyCount[r]) {
          for (final t in can) {
            if (t.mask != _bit(r)) {
              t.mask = _bit(r);
              changed = true;
            }
          }
        }
      }
      if (!changed) break;
    }
  }

  /// Marginal rank probabilities for every token of [owner] (Sinkhorn balancing
  /// of the masks against the army's rank counts).
  Map<int, List<double>> _probs(int owner) {
    final ids = [for (var i = 0; i < _toks.length; i++) if (_toks[i].owner == owner) i];
    final w = {
      for (final i in ids) i: [for (var r = 0; r < _nRanks; r++) _has(_toks[i].mask, r) ? 1.0 : 0.0]
    };
    for (var it = 0; it < 25; it++) {
      for (final row in w.values) {
        final s = row.fold(0.0, (x, y) => x + y);
        if (s > 0) {
          for (var r = 0; r < _nRanks; r++) {
            row[r] /= s;
          }
        }
      }
      for (var r = 0; r < _nRanks; r++) {
        var s = 0.0;
        for (final row in w.values) {
          s += row[r];
        }
        if (s > 0) {
          final f = _armyCount[r] / s;
          for (final row in w.values) {
            row[r] *= f;
          }
        }
      }
    }
    for (final row in w.values) {
      final s = row.fold(0.0, (x, y) => x + y);
      if (s > 0) {
        for (var r = 0; r < _nRanks; r++) {
          row[r] /= s;
        }
      }
    }
    return w;
  }

  /// Probability distribution over ranks of the piece at [node] (after [prepare]).
  List<double>? probsAt(int node) {
    final t = _at[node];
    if (t == null) return null;
    return _cur[t] ?? [for (var r = 0; r < _nRanks; r++) _toks[t].mask == _bit(r) ? 1.0 : 0.0];
  }

  Map<int, List<double>> _cur = {};

  /// Runs counting deductions and computes probabilities for all enemy armies.
  void prepare() {
    _cur = {};
    final owners = {for (final t in _toks) if (team(t.owner) != team(seat)) t.owner};
    for (final o in owners) {
      _propagate(o);
      _cur.addAll(_probs(o));
    }
  }

  // --------------------------------------------------------------- decision

  Map<String, dynamic> decide(Map<String, dynamic> view, Random rng, {double noise = 3}) {
    prepare();
    final cells = view['board'] as List;
    final alive = (view['alive'] as List).cast<bool>();
    final moves = <int, List<int>>{
      for (final e in (view['moves'] as Map).entries) int.parse(e.key as String): (e.value as List).cast<int>()
    };
    if (moves.isEmpty) return {'type': 'resign'};
    int? myRank(int n) {
      final c = cells[n];
      if (c == null) return null;
      final k = (c as Map)['k'] as int;
      return k >= 0 ? k : null;
    }

    bool isEnemy(int n) {
      final c = cells[n];
      return c != null && team((c as Map)['o'] as int) != team(seat);
    }

    final bd = _pseudoBoard();
    // reach of every enemy piece (as non-engineer and, when possible, as engineer)
    final enemies = <int>[];
    final reachNon = <int, Set<int>>{}, reachEng = <int, Set<int>>{};
    for (var n = 0; n < bd.length; n++) {
      if (!isEnemy(n) || _at[n] == null) continue;
      final m = _toks[_at[n]!].mask;
      if (m & ~(_bit(kFlag) | _bit(kMine)) == 0) continue;
      if (geo.nodes[n].kind == JKind.hq) continue;
      enemies.add(n);
      reachNon[n] = _reach(bd, n, false).toSet();
      reachEng[n] = _has(m, kEng) && geo.nodes[n].rail ? _reach(bd, n, true).toSet() : reachNon[n]!;
    }

    /// Expected gain of the most dangerous enemy that can hit my piece of rank [a] at [node].
    double threatAt(int node, int a, {int skip = -1}) {
      var worst = 0.0;
      for (final e in enemies) {
        if (e == skip) continue;
        final inNon = reachNon[e]!.contains(node), inEng = reachEng[e]!.contains(node);
        if (!inNon && !inEng) continue;
        final p = probsAt(e)!;
        var g = 0.0;
        for (var r = 0; r < _nRanks; r++) {
          if (p[r] == 0 || r == kFlag || r == kMine) continue;
          if (!(r == kEng ? inEng : inNon)) continue;
          final o = junqiOutcome(r, a);
          g += p[r] * (o == 2 ? _flagPrize : o == 1 ? junqiValue[a]! : o == 0 ? junqiValue[a]! - junqiValue[r]! : -junqiValue[r]!);
        }
        if (g > worst) worst = g;
      }
      return worst;
    }

    // distance to enemy 大本营 that may still hold a flag
    final dist = List.filled(bd.length, 99);
    final queue = <int>[];
    for (final n in geo.nodes) {
      if (n.kind != JKind.hq || n.arm < 0 || n.arm >= alive.length) continue;
      if (team(n.arm) == team(seat) || !alive[n.arm]) continue;
      final m = maskAt(n.id);
      if (m != null && !_has(m, kFlag)) continue;
      dist[n.id] = 0;
      queue.add(n.id);
    }
    for (var i = 0; i < queue.length; i++) {
      final c = queue[i];
      for (final x in geo.adj[c]) {
        if (dist[x] > dist[c] + 1) {
          dist[x] = dist[c] + 1;
          queue.add(x);
        }
      }
    }
    var flagAt = -1;
    for (var n = 0; n < cells.length; n++) {
      final c = cells[n];
      if (c != null && (c as Map)['o'] == seat && c['k'] == kFlag) flagAt = n;
    }
    // own flag's neighbourhood (defence)
    final nearFlag = <int>{};
    if (flagAt >= 0) {
      nearFlag.add(flagAt);
      for (final x in geo.adj[flagAt]) {
        nearFlag.add(x);
        nearFlag.addAll(geo.adj[x]);
      }
    }

    var best = -1e18;
    Map<String, dynamic>? pick;
    final keys = moves.keys.toList()..sort();
    for (final from in keys) {
      final a = myRank(from) ?? 5;
      final va = junqiValue[a]!;
      final here = threatAt(from, a);
      for (final to in moves[from]!) {
        final node = geo.nodes[to];
        var s = rng.nextDouble() * noise;
        if (isEnemy(to)) {
          final p = probsAt(to)!;
          var ev = 0.0;
          final after = threatAt(to, a, skip: to);
          for (var r = 0; r < _nRanks; r++) {
            if (p[r] == 0) continue;
            switch (junqiOutcome(a, r)) {
              case 2:
                ev += p[r] * _flagPrize;
              case 1:
                ev += p[r] * (junqiValue[r]! - 0.6 * after);
              case -1:
                ev += p[r] * -va;
              default:
                ev += p[r] * (junqiValue[r]! - va);
            }
          }
          s += ev + 0.6 * here;
          // cheap pieces probing unknown pieces gather information
          if ((a == 2 || a == 3) && _toks[_at[to]!].mask.bitLength > 1) s += 3;
          if (nearFlag.contains(to)) s += 15;
        } else {
          final w = a == kEng ? 1.0 : a == kBomb ? 0.6 : 2.0;
          if (dist[from] < 99) s += (dist[from] - dist[to]) * w;
          if (node.kind == JKind.hq) s -= 30;
          if (node.kind == JKind.camp) s += 3;
          s += 0.6 * (here - threatAt(to, a));
        }
        if (flagAt >= 0 && geo.adj[flagAt].contains(from) && a >= 5 && a <= 9) s -= 6;
        if (s > best) {
          best = s;
          pick = {'type': 'move', 'from': from, 'to': to};
        }
      }
    }
    return pick ?? {'type': 'resign'};
  }
}

// ------------------------------------------------------------------ 翻翻棋

/// Fair 翻翻棋 bot: face-up pieces are public; every face-down piece is an
/// unknown draw from the remaining pool (both armies minus everything flipped).
Map<String, dynamic> junqiFlipDecide(JunqiGeo geo, int seat, Map<String, dynamic> view, List<Map<String, dynamic>> log, Random rng,
    {double noise = 3}) {
  final cells = view['board'] as List;
  final colors = (view['colors'] as List).cast<int>();
  final me = colors[seat], opp = colors[1 - seat];
  final pool = [List.of(_armyCount), List.of(_armyCount)];
  for (final e in log) {
    if (e['t'] == 'flip') pool[e['o'] as int][e['k'] as int]--;
  }
  final bd = <JP?>[
    for (final c in cells)
      c == null
          ? null
          : (c as Map)['u'] == true
              ? JP(c['o'] as int, c['k'] as int, up: true)
              : JP(-1, -1)
  ];
  final downs = [for (var i = 0; i < bd.length; i++) if (bd[i] != null && !bd[i]!.up) i];
  final moves = <int, List<int>>{
    for (final e in (view['moves'] as Map).entries) int.parse(e.key as String): (e.value as List).cast<int>()
  };
  if (me < 0) {
    if (downs.isEmpty) return {'type': 'resign'};
    return {'type': 'flip', 'node': downs[rng.nextInt(downs.length)]};
  }

  bool minesLeft(List<JP?> b, int colour) =>
      pool[colour][kMine] > 0 || b.any((p) => p != null && p.up && p.owner == colour && p.rank == kMine);

  /// Gain for the attacker, or null if the capture is not allowed (flag behind mines).
  double? gain(List<JP?> b, int a, int d, int dColour) {
    if (d == kFlag) return minesLeft(b, dColour) ? null : _flagPrize;
    final o = junqiBattle(a, d);
    final va = junqiValue[a]!, vd = junqiValue[d]!;
    return o == 1 ? vd : o == -1 ? -va : vd - va;
  }

  bool Function(JP) friendOf(int colour) => (p) => !p.up || p.owner == colour;
  List<int> targets(List<JP?> b, int from) => junqiTargets(geo, b, from, friendOf(b[from]!.owner));

  double threat(List<JP?> b, int colour) {
    var worst = 0.0;
    final ms = junqiMoves(geo, b, (p) => p.up && p.owner == colour, friendOf(colour), hqLock: false);
    ms.forEach((from, tos) {
      for (final to in tos) {
        final q = b[to];
        if (q == null) continue;
        final g = gain(b, b[from]!.rank, q.rank, q.owner);
        if (g != null && g > worst) worst = g;
      }
    });
    return worst;
  }

  var best = -1e18;
  Map<String, dynamic>? pick;
  final keys = moves.keys.toList()..sort();
  for (final from in keys) {
    final p = bd[from]!;
    for (final to in moves[from]!) {
      final q = bd[to];
      final nb = List.of(bd);
      var g = 0.0;
      if (q != null) {
        g = gain(bd, p.rank, q.rank, q.owner) ?? 0;
        final r = junqiBattle(p.rank, q.rank);
        if (q.rank == kFlag || r == 1) {
          nb[to] = p;
          nb[from] = null;
        } else if (r == -1) {
          nb[from] = null;
        } else {
          nb[from] = null;
          nb[to] = null;
        }
      } else {
        nb[to] = p;
        nb[from] = null;
      }
      final s = g - threat(nb, opp) * 0.9 + rng.nextDouble() * noise;
      if (s > best) {
        best = s;
        pick = {'type': 'move', 'from': from, 'to': to};
      }
    }
  }

  if (downs.isNotEmpty) {
    final baseThreat = threat(bd, opp);
    final total = downs.length;
    for (final n in downs) {
      // who could hit a piece appearing at n, and what could it hit from n
      List<int> reachers(int colour, int shownAs) {
        final b = List.of(bd);
        b[n] = JP(shownAs, 5, up: true);
        return [
          for (var x = 0; x < b.length; x++)
            if (b[x] != null && b[x]!.up && b[x]!.owner == colour && junqiMovable(b[x]!.rank) && targets(b, x).contains(n)) b[x]!.rank
        ];
      }

      List<int> hits(int colour, bool eng) {
        final b = List.of(bd);
        b[n] = JP(colour, eng ? kEng : 5, up: true);
        return [
          for (final t in targets(b, n))
            if (b[t] != null) t
        ];
      }

      final oppReach = reachers(opp, me), myReach = reachers(me, opp);
      final hitsFor = {
        for (final c in [me, opp])
          for (final e in [false, true]) (c, e): hits(c, e)
      };
      var ev = 0.0;
      for (final c in [me, opp]) {
        for (var r = 0; r < _nRanks; r++) {
          final cnt = pool[c][r];
          if (cnt == 0) continue;
          final pr = cnt / total;
          var oppBest = 0.0, myBest = 0.0;
          final hitList = junqiMovable(r) ? hitsFor[(c, r == kEng)]! : const <int>[];
          if (c == opp) {
            for (final t in hitList) {
              final g = gain(bd, r, bd[t]!.rank, bd[t]!.owner);
              if (g != null && g > oppBest) oppBest = g;
            }
            for (final a in myReach) {
              final g = gain(bd, a, r, c);
              if (g != null && g > myBest) myBest = g;
            }
          } else {
            for (final a in oppReach) {
              final g = gain(bd, a, r, c);
              if (g != null && g > oppBest) oppBest = g;
            }
            for (final t in hitList) {
              final g = gain(bd, r, bd[t]!.rank, bd[t]!.owner);
              if (g != null && g > myBest) myBest = g;
            }
          }
          ev += pr * (-0.9 * max(baseThreat, oppBest) + 0.3 * myBest);
        }
      }
      final s = 4 + ev + rng.nextDouble() * noise;
      if (s > best) {
        best = s;
        pick = {'type': 'flip', 'node': n};
      }
    }
  }
  return pick ?? {'type': 'resign'};
}
