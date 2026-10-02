/// Board geometry for 军棋 (两国 / 四国 / 翻翻棋). Pure Dart, shared by engine and client.
library;

enum JKind { station, camp, hq }

class JNode {
  final int id;
  final int r, c; // grid coordinates
  final JKind kind;
  final int arm; // owning arm (seat), -1 = 中央九宫
  final int lr, lc; // local row (0 = front row) / column inside the arm, -1 for center
  bool rail = false;
  JNode(this.id, this.r, this.c, this.kind, this.arm, this.lr, this.lc);
}

class JunqiGeo {
  /// true = 四国 cross board (17×17 grid), false = 两国 board (12 rows × 5 cols).
  final bool four;
  final List<JNode> nodes = [];
  final Map<int, int> _byPos = {};
  final List<Set<int>> _adj = [];
  final List<Set<int>> _rail = [];
  final List<List<int>> lines = [];

  /// For each node, the rail lines passing through it (indices into [lines]).
  final List<List<int>> linesAt = [];

  /// Straight connection segments for drawing: (a, b, rail?).
  final List<(int, int, bool)> edges = [];

  /// Corner arcs of the 四国 board (node a, node b, arc center r, c).
  final List<(int, int, double, double)> arcs = [];

  /// Node ids of each arm in (lr, lc) order, 30 per arm.
  final List<List<int>> armNodes = [];

  late final List<List<int>> adj;
  late final List<List<int>> railAdj;

  int get rows => four ? 17 : 12;
  int get cols => four ? 17 : 5;

  static const camps = {(1, 1), (1, 3), (2, 2), (3, 1), (3, 3)};

  static final JunqiGeo two = JunqiGeo._(false);
  static final JunqiGeo cross = JunqiGeo._(true);
  static JunqiGeo of(bool four) => four ? cross : two;

  int? at(int r, int c) => _byPos[r * 32 + c];

  JunqiGeo._(this.four) {
    if (!four) {
      _addArm(0, (lr, lc) => (6 + lr, lc));
      _addArm(1, (lr, lc) => (5 - lr, 4 - lc));
      for (final r in [1, 5, 6, 10]) {
        _line(_rowSeg(r, 0, 4));
      }
      _line(_colSeg(0, 1, 10));
      _line(_colSeg(4, 1, 10));
      _line(_colSeg(2, 5, 6));
    } else {
      _addArm(0, (lr, lc) => (11 + lr, 6 + lc));
      _addArm(1, (lr, lc) => (10 - lc, 11 + lr));
      _addArm(2, (lr, lc) => (5 - lr, 10 - lc));
      _addArm(3, (lr, lc) => (6 + lc, 5 - lr));
      for (final r in [6, 8, 10]) {
        for (final c in [6, 8, 10]) {
          _addNode(r, c, JKind.station, -1, -1, -1);
        }
      }
      _line(_colSeg(6, 1, 15));
      _line(_colSeg(10, 1, 15));
      _line(_colSeg(8, 5, 11));
      _line(_rowSeg(6, 1, 15));
      _line(_rowSeg(10, 1, 15));
      _line(_rowSeg(8, 5, 11));
      for (final r in [1, 5, 11, 15]) {
        _line(_rowSeg(r, 6, 10));
      }
      for (final c in [1, 5, 11, 15]) {
        _line(_colSeg(c, 6, 10));
      }
      // corner arcs: non-engineers may follow them like a straight line
      _line([..._colSeg(6, 15, 11), ..._rowSeg(10, 5, 1)], arc: (11, 5));
      _line([..._colSeg(10, 15, 11), ..._rowSeg(10, 11, 15)], arc: (11, 11));
      _line([..._colSeg(6, 1, 5), ..._rowSeg(6, 5, 1)], arc: (5, 5));
      _line([..._colSeg(10, 1, 5), ..._rowSeg(6, 11, 15)], arc: (5, 11));
    }
    adj = [for (final s in _adj) s.toList()..sort()];
    railAdj = [for (final s in _rail) s.toList()..sort()];
    for (var i = 0; i < nodes.length; i++) {
      linesAt.add([
        for (var l = 0; l < lines.length; l++)
          if (lines[l].contains(i)) l
      ]);
    }
    // drawing edges: every step connection, marked rail when it is a rail edge
    for (var a = 0; a < nodes.length; a++) {
      for (final b in adj[a]) {
        if (b <= a) continue;
        final isArc = arcs.any((x) => (x.$1 == a && x.$2 == b) || (x.$1 == b && x.$2 == a));
        if (isArc) continue;
        edges.add((a, b, _rail[a].contains(b)));
      }
    }
  }

  int _addNode(int r, int c, JKind k, int arm, int lr, int lc) {
    final id = nodes.length;
    nodes.add(JNode(id, r, c, k, arm, lr, lc));
    _byPos[r * 32 + c] = id;
    _adj.add({});
    _rail.add({});
    return id;
  }

  void _link(int a, int b) {
    _adj[a].add(b);
    _adj[b].add(a);
  }

  void _addArm(int arm, (int, int) Function(int lr, int lc) map) {
    final ids = List.generate(6, (_) => List.filled(5, -1));
    for (var lr = 0; lr < 6; lr++) {
      for (var lc = 0; lc < 5; lc++) {
        final (r, c) = map(lr, lc);
        final kind = camps.contains((lr, lc))
            ? JKind.camp
            : (lr == 5 && (lc == 1 || lc == 3))
                ? JKind.hq
                : JKind.station;
        ids[lr][lc] = _addNode(r, c, kind, arm, lr, lc);
      }
    }
    for (var lr = 0; lr < 6; lr++) {
      for (var lc = 0; lc < 5; lc++) {
        if (lr < 5) _link(ids[lr][lc], ids[lr + 1][lc]);
        if (lc < 4) _link(ids[lr][lc], ids[lr][lc + 1]);
      }
    }
    for (final (lr, lc) in camps) {
      for (final dr in [-1, 1]) {
        for (final dc in [-1, 1]) {
          final r2 = lr + dr, c2 = lc + dc;
          if (r2 >= 0 && r2 < 6 && c2 >= 0 && c2 < 5) _link(ids[lr][lc], ids[r2][c2]);
        }
      }
    }
    armNodes.add([for (final row in ids) ...row]);
  }

  List<int> _rowSeg(int r, int c1, int c2) {
    final out = <int>[];
    final step = c2 >= c1 ? 1 : -1;
    for (var c = c1;; c += step) {
      final id = at(r, c);
      if (id != null) out.add(id);
      if (c == c2) break;
    }
    return out;
  }

  List<int> _colSeg(int c, int r1, int r2) {
    final out = <int>[];
    final step = r2 >= r1 ? 1 : -1;
    for (var r = r1;; r += step) {
      final id = at(r, c);
      if (id != null) out.add(id);
      if (r == r2) break;
    }
    return out;
  }

  void _line(List<int> ids, {(int, int)? arc}) {
    lines.add(ids);
    for (var i = 0; i + 1 < ids.length; i++) {
      final a = ids[i], b = ids[i + 1];
      _link(a, b);
      _rail[a].add(b);
      _rail[b].add(a);
      nodes[a].rail = true;
      nodes[b].rail = true;
      if (arc != null) {
        final na = nodes[a], nb = nodes[b];
        if (na.r != nb.r && na.c != nb.c) arcs.add((a, b, arc.$1.toDouble(), arc.$2.toDouble()));
      }
    }
  }
}
