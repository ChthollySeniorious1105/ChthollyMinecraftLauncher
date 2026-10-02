import 'dart:math';

/// Static geometry of the standard 19-hex Catan board (pointy-top hexes).
/// Shared by the engine and the client renderer so indices always agree.
class CatanGeo {
  static final CatanGeo instance = CatanGeo._();

  /// Axial coordinates (q, r), row by row (r = -2..2), left to right.
  final List<(int, int)> hexes = [];

  /// Hex centres in unit-size pixel space (size = distance centre->corner = 1).
  final List<double> hx = [], hy = [];

  /// Vertex positions.
  final List<double> vx = [], vy = [];

  /// 6 vertex indices per hex, clockwise starting at the top corner.
  final List<List<int>> hexVerts = [];
  final List<List<int>> vertHexes = [];

  /// Edge endpoints [a, b].
  final List<List<int>> edgeVerts = [];
  final List<List<int>> vertEdges = [];
  final List<List<int>> vertNeighbors = [];
  final List<List<int>> hexNeighbors = [];
  final List<List<int>> edgeHexes = [];

  /// Coastal edges (belonging to one hex) sorted by angle around the centre.
  final List<int> coast = [];

  /// Coastal edge indices that carry harbours (9).
  final List<int> harborEdges = [];

  int get nHex => hexes.length;
  int get nVert => vx.length;
  int get nEdge => edgeVerts.length;

  CatanGeo._() {
    for (var r = -2; r <= 2; r++) {
      for (var q = max(-2, -2 - r); q <= min(2, 2 - r); q++) {
        hexes.add((q, r));
      }
    }
    final vKey = <String, int>{};
    final eKey = <String, int>{};
    final s3 = sqrt(3);
    for (var h = 0; h < hexes.length; h++) {
      final (q, r) = hexes[h];
      final cx = s3 * (q + r / 2), cy = 1.5 * r;
      hx.add(cx);
      hy.add(cy);
      final vs = <int>[];
      for (var i = 0; i < 6; i++) {
        final ang = (60 * i - 90) * pi / 180;
        final x = cx + cos(ang), y = cy + sin(ang);
        final k = '${(x * 100).round()},${(y * 100).round()}';
        var id = vKey[k];
        if (id == null) {
          id = vx.length;
          vKey[k] = id;
          vx.add(x);
          vy.add(y);
          vertHexes.add([]);
          vertEdges.add([]);
          vertNeighbors.add([]);
        }
        vs.add(id);
        vertHexes[id].add(h);
      }
      hexVerts.add(vs);
      for (var i = 0; i < 6; i++) {
        final a = vs[i], b = vs[(i + 1) % 6];
        final k = a < b ? '$a-$b' : '$b-$a';
        var id = eKey[k];
        if (id == null) {
          id = edgeVerts.length;
          eKey[k] = id;
          edgeVerts.add([a, b]);
          edgeHexes.add([]);
          vertEdges[a].add(id);
          vertEdges[b].add(id);
          vertNeighbors[a].add(b);
          vertNeighbors[b].add(a);
        }
        edgeHexes[id].add(h);
      }
    }
    for (var h = 0; h < hexes.length; h++) {
      final (q, r) = hexes[h];
      final ns = <int>[];
      for (final (dq, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)]) {
        final j = hexes.indexOf((q + dq, r + dr));
        if (j >= 0) ns.add(j);
      }
      hexNeighbors.add(ns);
    }
    for (var e = 0; e < edgeVerts.length; e++) {
      if (edgeHexes[e].length == 1) coast.add(e);
    }
    double ang(int e) {
      final [a, b] = edgeVerts[e];
      return atan2((vy[a] + vy[b]) / 2, (vx[a] + vx[b]) / 2);
    }

    coast.sort((a, b) => ang(a).compareTo(ang(b)));
    for (final i in const [0, 3, 6, 10, 13, 16, 20, 23, 26]) {
      harborEdges.add(coast[i]);
    }
  }

  /// Pip count ("probability dots") of a number token.
  static int pips(int n) => n < 2 || n > 12 || n == 7 ? 0 : 6 - (7 - n).abs();
}
