import 'dart:typed_data';

import 'engine.dart';

/// Drawing-game strokes ({'c': argb, 'w': width, 'p': [x0,y0,x1,y1…]} in
/// 0..1000 canvas units; widths are given for an 800 px wide canvas).
///
/// A stroke with width [kFillWidth] and exactly one point is a paint-bucket
/// fill: it floods the area of the seed pixel's colour on everything drawn
/// before it. Fills are resolved on a small fixed-size raster
/// ([kFillGridW]×[kFillGridH]) so every client gets the identical result.
const int kFillWidth = 0;
const int kFillGridW = 640;
const int kFillGridH = 480;

/// Points a fill is charged against a drawing's point budget.
const int kFillCost = 50;

bool isFillStroke(int width, List pts) => width == kFillWidth && pts.length == 2;

/// Budget cost of a stored stroke map.
int strokeCost(Map<String, dynamic> s) => s['w'] == kFillWidth ? kFillCost : (s['p'] as List).length ~/ 2;

/// One drawing being made on the server: strokes plus undo / redo history.
/// Strokes are `{'id', 'c', 'w', 'p'}` maps.
class Sketch {
  final int maxPoints;
  final int maxBatch; // ints per stroke batch
  final int maxStrokes;
  Sketch({this.maxPoints = 20000, this.maxBatch = 600, this.maxStrokes = 800});

  final List<Map<String, dynamic>> strokes = [];
  int points = 0;

  /// Undone strokes, or [_clearMark] for an undone clear.
  final List<Object> _redo = [];

  /// Stroke lists removed by clear (newest last) so clear can be undone.
  final List<List<Map<String, dynamic>>> _cleared = [];
  static const _clearMark = Object();
  static const _maxCleared = 8;

  bool get canUndo => strokes.isNotEmpty || _cleared.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  List<Map<String, dynamic>> toJson() => [for (final s in strokes) {'id': s['id'], 'c': s['c'], 'w': s['w'], 'p': s['p']}];

  void reset() {
    strokes.clear();
    points = 0;
    _redo.clear();
    _cleared.clear();
  }

  /// Applies a `stroke` action: appends to the stroke with the same id or
  /// starts a new one (a fill when width is [kFillWidth] with one point).
  void stroke(Map<String, dynamic> a) {
    final id = asInt(a['id']);
    final raw = a['pts'];
    if (raw is! List || raw.isEmpty || raw.length.isOdd) throw GameError('笔画数据无效');
    if (raw.length > maxBatch) throw GameError('笔画数据过大');
    final pts = <int>[];
    for (final v in raw) {
      if (v is! num || !v.isFinite) throw GameError('笔画数据无效');
      pts.add(v.toInt().clamp(0, 1000));
    }
    Map<String, dynamic>? target;
    var fillAfter = false; // a stroke under a fill can't grow (it would change the fill)
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (strokes[i]['id'] == id) {
        target = strokes[i];
        break;
      }
      if (strokes[i]['w'] == kFillWidth) fillAfter = true;
    }
    if (target != null) {
      if (fillAfter) throw GameError('笔画数据无效');
      if (target['w'] == kFillWidth) throw GameError('笔画数据无效');
      if (points + pts.length ~/ 2 > maxPoints) throw GameError('画布已满，请清空或撤销后再画');
      (target['p'] as List<int>).addAll(pts);
      points += pts.length ~/ 2;
      return;
    }
    if (strokes.length >= maxStrokes) throw GameError('笔画太多了，请清空后再画');
    final color = asInt(a['color'], 0xFF000000) & 0xFFFFFFFF;
    var width = asInt(a['width'], 6);
    width = isFillStroke(width, pts) ? kFillWidth : width.clamp(1, 80);
    final s = <String, dynamic>{'id': id, 'c': color, 'w': width, 'p': pts};
    final cost = strokeCost(s);
    if (points + cost > maxPoints) throw GameError('画布已满，请清空或撤销后再画');
    strokes.add(s);
    points += cost;
    _redo.clear();
  }

  void undo() {
    if (strokes.isNotEmpty) {
      final s = strokes.removeLast();
      points -= strokeCost(s);
      _redo.add(s);
    } else if (_cleared.isNotEmpty) {
      strokes.addAll(_cleared.removeLast());
      points = _count();
      _redo.add(_clearMark);
    }
  }

  void redo() {
    if (_redo.isEmpty) return;
    final x = _redo.last;
    if (identical(x, _clearMark)) {
      _redo.removeLast();
      _clear();
      return;
    }
    final s = x as Map<String, dynamic>;
    if (strokes.length >= maxStrokes || points + strokeCost(s) > maxPoints) throw GameError('画布已满，无法重做');
    _redo.removeLast();
    strokes.add(s);
    points += strokeCost(s);
  }

  void clear() {
    if (strokes.isEmpty) return;
    _clear();
    _redo.clear();
  }

  void _clear() {
    _cleared.add(List.of(strokes));
    if (_cleared.length > _maxCleared) _cleared.removeAt(0);
    strokes.clear();
    points = 0;
  }

  int _count() {
    var n = 0;
    for (final s in strokes) {
      n += strokeCost(s);
    }
    return n;
  }
}

/// Non-antialiased software raster of strokes with flood fill.
class StrokeRaster {
  final int w, h;

  /// Pixels per stroke-width unit (default: widths relative to 800 px).
  final double unit;
  final Uint32List px;

  /// Extra stroke radius in cells. Negative = thinner than the vector line,
  /// so a fill tucks under the line's antialiased edge instead of leaving a
  /// white fringe.
  final double pad;

  StrokeRaster(this.w, this.h, {double? unit, this.pad = 0, int background = 0xFFFFFFFF})
      : unit = unit ?? w / 800,
        px = Uint32List(w * h)..fillRange(0, w * h, background);

  /// Draws a stroke or applies a fill. Returns the filled runs for a fill
  /// (see [fill]), otherwise null.
  Int32List? add(int color, int width, List<int> pts) {
    if (isFillStroke(width, pts)) return fill(color, pts[0], pts[1]);
    stroke(color, width, pts);
    return null;
  }

  void _dot(double cx, double cy, double r, int c) {
    final x0 = (cx - r).floor(), x1 = (cx + r).ceil(), y0 = (cy - r).floor(), y1 = (cy + r).ceil();
    for (var y = y0 < 0 ? 0 : y0; y <= y1 && y < h; y++) {
      final dy = y + 0.5 - cy;
      for (var x = x0 < 0 ? 0 : x0; x <= x1 && x < w; x++) {
        final dx = x + 0.5 - cx;
        if (dx * dx + dy * dy <= r * r) px[y * w + x] = c;
      }
    }
  }

  void stroke(int color, int width, List<int> pts) {
    if (pts.length < 2) return;
    final sx = w / 1000, sy = h / 1000;
    var r = width * unit / 2 + pad;
    if (r < 0.75) r = 0.75;
    double? lx, ly;
    for (var i = 0; i + 1 < pts.length; i += 2) {
      final x = pts[i] * sx, y = pts[i + 1] * sy;
      if (lx == null) {
        _dot(x, y, r, color);
      } else {
        final dx = x - lx, dy = y - ly!;
        final steps = ((dx.abs() > dy.abs() ? dx.abs() : dy.abs()) / (r / 2)).ceil().clamp(1, 4000);
        for (var k = 1; k <= steps; k++) {
          _dot(lx + dx * k / steps, ly + dy * k / steps, r, color);
        }
      }
      lx = x;
      ly = y;
    }
  }

  /// 4-connected flood fill from canvas point ([x], [y]) (0..1000 units).
  /// Returns the filled area as runs `[row, x0, x1, …]` (x1 exclusive), in
  /// raster cells; empty when the seed already has [color].
  Int32List fill(int color, int x, int y) {
    final cx = (x * w ~/ 1000).clamp(0, w - 1), cy = (y * h ~/ 1000).clamp(0, h - 1);
    final target = px[cy * w + cx];
    final runs = <int>[];
    if (target == color) return Int32List(0);
    final stack = <int>[cx, cy];
    while (stack.isNotEmpty) {
      final sy = stack.removeLast(), sx = stack.removeLast();
      final row = sy * w;
      if (px[row + sx] != target) continue;
      var a = sx, b = sx;
      while (a > 0 && px[row + a - 1] == target) {
        a--;
      }
      while (b < w - 1 && px[row + b + 1] == target) {
        b++;
      }
      for (var i = a; i <= b; i++) {
        px[row + i] = color;
      }
      runs.addAll([sy, a, b + 1]);
      for (final ny in [sy - 1, sy + 1]) {
        if (ny < 0 || ny >= h) continue;
        final nrow = ny * w;
        var inRun = false;
        for (var i = a; i <= b; i++) {
          if (px[nrow + i] == target) {
            if (!inRun) {
              stack.addAll([i, ny]);
              inRun = true;
            }
          } else {
            inRun = false;
          }
        }
      }
    }
    return Int32List.fromList(runs);
  }
}
