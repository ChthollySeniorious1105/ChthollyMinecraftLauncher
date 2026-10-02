/// Carcassonne base-game tile catalogue (shared by engine and client painter).
///
/// Geometry conventions (unrotated tile, y grows downward):
///  * sides: 0 = N, 1 = E, 2 = S, 3 = W.
///  * field half-ports 0..7 go clockwise around the border starting at the
///    north-west corner: N = (0 west half, 1 east half), E = (2 north, 3 south),
///    S = (4 east, 5 west), W = (6 south, 7 north).
///  * rotating a tile by r quarter turns clockwise maps side s -> (s+r)%4 and
///    half-port p -> (p+2r)%8.
library;

enum FeatureKind { city, road, field, cloister }

class TileFeature {
  final FeatureKind kind;

  /// Sides occupied (cities / roads).
  final List<int> sides;

  /// Half-ports occupied (fields).
  final List<int> halves;
  final bool shield;

  /// For fields: local indices of the city features this field borders.
  final List<int> adj;

  /// Meeple anchor in unrotated unit coordinates.
  final double ax, ay;

  const TileFeature(this.kind, {this.sides = const [], this.halves = const [], this.shield = false, this.adj = const [], this.ax = 0.5, this.ay = 0.5});

  TileFeature rotated(int r) {
    if (r % 4 == 0) return this;
    final (x, y) = rotatePoint(ax, ay, r);
    return TileFeature(kind,
        sides: [for (final s in sides) (s + r) % 4],
        halves: [for (final h in halves) (h + 2 * r) % 8],
        shield: shield,
        adj: adj,
        ax: x,
        ay: y);
  }
}

/// Rotates a unit-square point by r quarter turns clockwise around the centre.
(double, double) rotatePoint(double x, double y, int r) {
  var px = x, py = y;
  for (var i = 0; i < r % 4; i++) {
    final nx = 1 - py, ny = px;
    px = nx;
    py = ny;
  }
  return (px, py);
}

class TileType {
  final String id;
  final int count;

  /// Edge type per side (unrotated): 'C' city, 'R' road, 'F' field.
  final String edges;
  final List<TileFeature> features;
  const TileType(this.id, this.count, this.edges, this.features);

  String edge(int side, int rot) => edges[((side - rot) % 4 + 4) % 4];

  List<TileFeature> featuresAt(int rot) => [for (final f in features) f.rotated(rot)];

  bool get hasCloister => features.any((f) => f.kind == FeatureKind.cloister);
  int get roadCount => features.where((f) => f.kind == FeatureKind.road).length;
}

const _c = FeatureKind.city, _r = FeatureKind.road, _f = FeatureKind.field, _m = FeatureKind.cloister;

/// All 24 base tile types A..X. Counts sum to 72 (the start tile is one of the D tiles).
const List<TileType> carcTiles = [
  TileType('A', 2, 'FFRF', [
    TileFeature(_m, ax: 0.5, ay: 0.42),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.84),
    TileFeature(_f, halves: [0, 1, 2, 3, 4, 5, 6, 7], ax: 0.18, ay: 0.2),
  ]),
  TileType('B', 4, 'FFFF', [
    TileFeature(_m, ax: 0.5, ay: 0.46),
    TileFeature(_f, halves: [0, 1, 2, 3, 4, 5, 6, 7], ax: 0.18, ay: 0.2),
  ]),
  TileType('C', 1, 'CCCC', [
    TileFeature(_c, sides: [0, 1, 2, 3], shield: true, ax: 0.5, ay: 0.55),
  ]),
  TileType('D', 4, 'CRFR', [
    TileFeature(_c, sides: [0], ax: 0.5, ay: 0.13),
    TileFeature(_r, sides: [1, 3], ax: 0.5, ay: 0.5),
    TileFeature(_f, halves: [2, 7], adj: [0], ax: 0.84, ay: 0.33),
    TileFeature(_f, halves: [3, 4, 5, 6], ax: 0.5, ay: 0.8),
  ]),
  TileType('E', 5, 'CFFF', [
    TileFeature(_c, sides: [0], ax: 0.5, ay: 0.13),
    TileFeature(_f, halves: [2, 3, 4, 5, 6, 7], adj: [0], ax: 0.5, ay: 0.66),
  ]),
  TileType('F', 2, 'FCFC', [
    TileFeature(_c, sides: [1, 3], shield: true, ax: 0.5, ay: 0.5),
    TileFeature(_f, halves: [0, 1], adj: [0], ax: 0.5, ay: 0.1),
    TileFeature(_f, halves: [4, 5], adj: [0], ax: 0.5, ay: 0.9),
  ]),
  TileType('G', 1, 'CFCF', [
    TileFeature(_c, sides: [0, 2], ax: 0.5, ay: 0.5),
    TileFeature(_f, halves: [2, 3], adj: [0], ax: 0.9, ay: 0.5),
    TileFeature(_f, halves: [6, 7], adj: [0], ax: 0.1, ay: 0.5),
  ]),
  TileType('H', 3, 'FCFC', [
    TileFeature(_c, sides: [1], ax: 0.87, ay: 0.5),
    TileFeature(_c, sides: [3], ax: 0.13, ay: 0.5),
    TileFeature(_f, halves: [0, 1, 4, 5], adj: [0, 1], ax: 0.5, ay: 0.5),
  ]),
  TileType('I', 2, 'FCCF', [
    TileFeature(_c, sides: [1], ax: 0.87, ay: 0.45),
    TileFeature(_c, sides: [2], ax: 0.45, ay: 0.87),
    TileFeature(_f, halves: [0, 1, 6, 7], adj: [0, 1], ax: 0.3, ay: 0.3),
  ]),
  TileType('J', 3, 'CRRF', [
    TileFeature(_c, sides: [0], ax: 0.5, ay: 0.13),
    TileFeature(_r, sides: [1, 2], ax: 0.63, ay: 0.63),
    TileFeature(_f, halves: [3, 4], ax: 0.87, ay: 0.87),
    TileFeature(_f, halves: [2, 5, 6, 7], adj: [0], ax: 0.3, ay: 0.55),
  ]),
  TileType('K', 3, 'CFRR', [
    TileFeature(_c, sides: [0], ax: 0.5, ay: 0.13),
    TileFeature(_r, sides: [3, 2], ax: 0.37, ay: 0.63),
    TileFeature(_f, halves: [5, 6], ax: 0.13, ay: 0.87),
    TileFeature(_f, halves: [2, 3, 4, 7], adj: [0], ax: 0.7, ay: 0.55),
  ]),
  TileType('L', 3, 'CRRR', [
    TileFeature(_c, sides: [0], ax: 0.5, ay: 0.13),
    TileFeature(_r, sides: [1], ax: 0.8, ay: 0.5),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.8),
    TileFeature(_r, sides: [3], ax: 0.2, ay: 0.5),
    TileFeature(_f, halves: [2, 7], adj: [0], ax: 0.84, ay: 0.33),
    TileFeature(_f, halves: [3, 4], ax: 0.84, ay: 0.84),
    TileFeature(_f, halves: [5, 6], ax: 0.16, ay: 0.84),
  ]),
  TileType('M', 2, 'CFFC', [
    TileFeature(_c, sides: [0, 3], shield: true, ax: 0.3, ay: 0.3),
    TileFeature(_f, halves: [2, 3, 4, 5], adj: [0], ax: 0.78, ay: 0.78),
  ]),
  TileType('N', 3, 'CFFC', [
    TileFeature(_c, sides: [0, 3], ax: 0.3, ay: 0.3),
    TileFeature(_f, halves: [2, 3, 4, 5], adj: [0], ax: 0.78, ay: 0.78),
  ]),
  TileType('O', 2, 'CRRC', [
    TileFeature(_c, sides: [0, 3], shield: true, ax: 0.26, ay: 0.26),
    TileFeature(_r, sides: [1, 2], ax: 0.63, ay: 0.63),
    TileFeature(_f, halves: [3, 4], ax: 0.87, ay: 0.87),
    TileFeature(_f, halves: [2, 5], adj: [0], ax: 0.88, ay: 0.3),
  ]),
  TileType('P', 3, 'CRRC', [
    TileFeature(_c, sides: [0, 3], ax: 0.26, ay: 0.26),
    TileFeature(_r, sides: [1, 2], ax: 0.63, ay: 0.63),
    TileFeature(_f, halves: [3, 4], ax: 0.87, ay: 0.87),
    TileFeature(_f, halves: [2, 5], adj: [0], ax: 0.88, ay: 0.3),
  ]),
  TileType('Q', 1, 'CCFC', [
    TileFeature(_c, sides: [0, 1, 3], shield: true, ax: 0.5, ay: 0.38),
    TileFeature(_f, halves: [4, 5], adj: [0], ax: 0.5, ay: 0.9),
  ]),
  TileType('R', 3, 'CCFC', [
    TileFeature(_c, sides: [0, 1, 3], ax: 0.5, ay: 0.38),
    TileFeature(_f, halves: [4, 5], adj: [0], ax: 0.5, ay: 0.9),
  ]),
  TileType('S', 2, 'CCRC', [
    TileFeature(_c, sides: [0, 1, 3], shield: true, ax: 0.5, ay: 0.36),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.88),
    TileFeature(_f, halves: [4], adj: [0], ax: 0.86, ay: 0.92),
    TileFeature(_f, halves: [5], adj: [0], ax: 0.14, ay: 0.92),
  ]),
  TileType('T', 1, 'CCRC', [
    TileFeature(_c, sides: [0, 1, 3], ax: 0.5, ay: 0.36),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.88),
    TileFeature(_f, halves: [4], adj: [0], ax: 0.86, ay: 0.92),
    TileFeature(_f, halves: [5], adj: [0], ax: 0.14, ay: 0.92),
  ]),
  TileType('U', 8, 'RFRF', [
    TileFeature(_r, sides: [0, 2], ax: 0.5, ay: 0.5),
    TileFeature(_f, halves: [1, 2, 3, 4], ax: 0.8, ay: 0.5),
    TileFeature(_f, halves: [5, 6, 7, 0], ax: 0.2, ay: 0.5),
  ]),
  TileType('V', 9, 'FFRR', [
    TileFeature(_r, sides: [3, 2], ax: 0.37, ay: 0.63),
    TileFeature(_f, halves: [5, 6], ax: 0.14, ay: 0.86),
    TileFeature(_f, halves: [0, 1, 2, 3, 4, 7], ax: 0.66, ay: 0.34),
  ]),
  TileType('W', 4, 'FRRR', [
    TileFeature(_r, sides: [1], ax: 0.8, ay: 0.5),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.8),
    TileFeature(_r, sides: [3], ax: 0.2, ay: 0.5),
    TileFeature(_f, halves: [7, 0, 1, 2], ax: 0.5, ay: 0.2),
    TileFeature(_f, halves: [3, 4], ax: 0.84, ay: 0.84),
    TileFeature(_f, halves: [5, 6], ax: 0.16, ay: 0.84),
  ]),
  TileType('X', 1, 'RRRR', [
    TileFeature(_r, sides: [0], ax: 0.5, ay: 0.2),
    TileFeature(_r, sides: [1], ax: 0.8, ay: 0.5),
    TileFeature(_r, sides: [2], ax: 0.5, ay: 0.8),
    TileFeature(_r, sides: [3], ax: 0.2, ay: 0.5),
    TileFeature(_f, halves: [7, 0], ax: 0.16, ay: 0.16),
    TileFeature(_f, halves: [1, 2], ax: 0.84, ay: 0.16),
    TileFeature(_f, halves: [3, 4], ax: 0.84, ay: 0.84),
    TileFeature(_f, halves: [5, 6], ax: 0.16, ay: 0.84),
  ]),
];

/// Index of the start tile type (D).
const int carcStartType = 3;

int carcTypeIndex(String id) => carcTiles.indexWhere((t) => t.id == id);

/// Opposite half-port across the shared border.
int oppositeHalf(int p) {
  final s = p ~/ 2, k = p % 2;
  return 2 * ((s + 2) % 4) + (1 - k);
}

const List<(int, int)> sideDelta = [(0, -1), (1, 0), (0, 1), (-1, 0)];

const Map<FeatureKind, String> featureNames = {
  FeatureKind.city: '城市',
  FeatureKind.road: '道路',
  FeatureKind.field: '草地',
  FeatureKind.cloister: '修道院',
};
