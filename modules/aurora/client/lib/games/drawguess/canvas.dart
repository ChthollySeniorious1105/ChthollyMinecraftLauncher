import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';

/// One stroke in normalized 0..1000 coordinates.
class DgStroke {
  final int id;
  final int color;
  final int width;
  final List<int> pts;
  DgStroke(this.id, this.color, this.width, this.pts);

  bool get isFill => isFillStroke(width, pts);

  static List<DgStroke> _last = const [];

  /// Parses the view's stroke list. Strokes that are unchanged since the last
  /// call (same id, colour, width and point count) are reused as-is, so a
  /// big drawing isn't re-decoded on every update.
  static List<DgStroke> parse(Object? raw) {
    if (raw is! List) return _last = const [];
    final prev = {for (final s in _last) s.id: s};
    final out = <DgStroke>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final p = e['p'];
      final id = (e['id'] as num?)?.toInt() ?? 0;
      final old = prev[id];
      if (old != null &&
          p is List &&
          old.pts.length == p.length &&
          old.color == ((e['c'] as num?)?.toInt() ?? 0xFF000000) &&
          old.width == ((e['w'] as num?)?.toInt() ?? 6)) {
        out.add(old);
        continue;
      }
      out.add(DgStroke(
        (e['id'] as num?)?.toInt() ?? 0,
        (e['c'] as num?)?.toInt() ?? 0xFF000000,
        (e['w'] as num?)?.toInt() ?? 6,
        p is List ? [for (final v in p) (v as num).toInt()] : <int>[],
      ));
    }
    return _last = out;
  }
}

const int kCanvasBg = 0xFFFFFFFF;

/// Resolves paint-bucket fills against the strokes drawn before them, on the
/// shared fixed-size grid ([kFillGridW]×[kFillGridH]) so every client fills
/// exactly the same area.
class DgFills {
  final _runs = Expando<Int32List>();
  StrokeRaster? _raster;
  List<DgStroke> _applied = const [];

  /// Filled runs `[row, x0, x1, …]` of the fill [strokes][i].
  Int32List runsFor(List<DgStroke> strokes, int i) {
    final cached = _runs[strokes[i]];
    if (cached != null) return cached;
    var r = _raster;
    var n = _applied.length;
    var ok = r != null && n <= i;
    for (var k = 0; ok && k < n; k++) {
      if (!identical(_applied[k], strokes[k])) ok = false;
    }
    if (!ok) {
      r = StrokeRaster(kFillGridW, kFillGridH);
      n = 0;
    }
    for (var k = n; k <= i; k++) {
      final s = strokes[k];
      final out = r!.add(s.color, s.width, s.pts);
      if (out != null) _runs[s] ??= out;
    }
    _raster = r;
    _applied = strokes.sublist(0, i + 1);
    return _runs[strokes[i]]!;
  }
}

void _drawFill(Canvas canvas, Int32List runs, int color, Size size) {
  if (runs.isEmpty) return;
  final cw = size.width / kFillGridW, ch = size.height / kFillGridH;
  // rects overlap by half a cell so the fill tucks under antialiased edges
  final path = Path();
  for (var i = 0; i + 2 < runs.length; i += 3) {
    path.addRect(Rect.fromLTRB(runs[i + 1] * cw - cw / 2, runs[i] * ch - ch / 2, runs[i + 2] * cw + cw / 2, (runs[i] + 1) * ch + ch / 2));
  }
  canvas.drawPath(path, Paint()..color = Color(color));
}

void _drawStroke(Canvas canvas, DgStroke s, Size size, [Int32List? fill]) {
  if (fill != null) {
    _drawFill(canvas, fill, s.color, size);
    return;
  }
  if (s.pts.length < 2) return;
  final sx = size.width / 1000, sy = size.height / 1000;
  final unit = size.width / 800; // widths are specified for an 800px wide canvas
  final paint = Paint()
    ..color = Color(s.color)
    ..strokeWidth = max(1.0, s.width * unit)
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  if (s.pts.length == 2) {
    canvas.drawCircle(Offset(s.pts[0] * sx, s.pts[1] * sy), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
    return;
  }
  final path = Path()..moveTo(s.pts[0] * sx, s.pts[1] * sy);
  for (var i = 2; i + 1 < s.pts.length; i += 2) {
    path.lineTo(s.pts[i] * sx, s.pts[i + 1] * sy);
  }
  canvas.drawPath(path, paint);
}

/// Finished strokes baked into a bitmap. New strokes are added on top of the
/// previous bitmap, so the cost per update is the new strokes only, no matter
/// how much is already on the canvas. Undo / clear / resize rebuild it.
class DgStrokeCache {
  ui.Image? image;
  Size _size = Size.zero;
  double _dpr = 1;
  List<DgStroke> _baked = const [];
  final fills = DgFills();

  /// Makes [image] show exactly [strokes] at [size] × [dpr].
  void update(List<DgStroke> strokes, Size size, double dpr) {
    var from = 0;
    final sameGeom = size == _size && dpr == _dpr && image != null;
    if (sameGeom && strokes.length >= _baked.length) {
      from = _baked.length;
      for (var i = 0; i < _baked.length; i++) {
        if (!identical(strokes[i], _baked[i])) {
          from = -1;
          break;
        }
      }
      if (from == strokes.length) return; // nothing new
    } else {
      from = -1;
    }
    if (strokes.isEmpty) {
      _set(null, strokes, size, dpr);
      return;
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.scale(dpr);
    if (from > 0) {
      c.save();
      c.scale(1 / dpr);
      c.drawImage(image!, Offset.zero, Paint());
      c.restore();
    } else {
      from = 0;
    }
    for (var i = from; i < strokes.length; i++) {
      final s = strokes[i];
      _drawStroke(c, s, size, s.isFill ? fills.runsFor(strokes, i) : null);
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync(max(1, (size.width * dpr).ceil()), max(1, (size.height * dpr).ceil()));
    pic.dispose();
    _set(img, strokes, size, dpr);
  }

  void _set(ui.Image? img, List<DgStroke> strokes, Size size, double dpr) {
    image?.dispose();
    image = img;
    _baked = List.of(strokes);
    _size = size;
    _dpr = dpr;
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}

class DgPainter extends CustomPainter {
  /// Bitmap of all finished strokes (see [DgStrokeCache]).
  final ui.Image? baked;
  final double dpr;

  /// Strokes drawn as vectors on top: the server's newest (possibly still
  /// growing) stroke and my local in-progress stroke. Never fills.
  final List<DgStroke> tail;
  final Listenable? repaintOn;
  DgPainter(this.baked, this.dpr, this.tail, {this.repaintOn}) : super(repaint: repaintOn);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..color = const Color(kCanvasBg));
    canvas.save();
    canvas.clipRect(r);
    final img = baked;
    if (img != null) {
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), r,
          Paint()..filterQuality = FilterQuality.low);
    }
    for (final s in tail) {
      _drawStroke(canvas, s, size);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DgPainter old) => old.baked != baked || old.tail.length != tail.length || !_same(old.tail, tail);

  static bool _same(List<DgStroke> a, List<DgStroke> b) {
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) || a[i].pts.length != b[i].pts.length) return false;
    }
    return true;
  }
}

/// 4:3 drawing surface. When [enabled], pointer input becomes strokes that are
/// sent through [send] in batches (≤ 8 per second).
class DgCanvas extends StatefulWidget {
  final List<DgStroke> strokes;
  final bool enabled;
  final int color;
  final int width;

  /// Paint-bucket mode: a tap sends one fill instead of drawing.
  final bool fill;
  final void Function(Map<String, dynamic> action) send;
  final Widget? overlay;
  const DgCanvas(
      {super.key,
      required this.strokes,
      required this.enabled,
      required this.color,
      required this.width,
      this.fill = false,
      required this.send,
      this.overlay});

  @override
  State<DgCanvas> createState() => _DgCanvasState();
}

class _DgCanvasState extends State<DgCanvas> {
  static const _flushMs = 130;
  static const _maxBatchInts = 560;

  DgStroke? _live;
  int _sent = 0; // ints of _live already sent
  Timer? _timer;
  bool _down = false;
  int _nextId = DateTime.now().millisecondsSinceEpoch % 100000000;
  final _cache = DgStrokeCache();

  /// Bumped on every local pointer move: repaints only the canvas layer,
  /// without rebuilding any widgets.
  final _liveTick = ValueNotifier<int>(0);

  @override
  void dispose() {
    _timer?.cancel();
    _cache.dispose();
    _liveTick.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DgCanvas old) {
    super.didUpdateWidget(old);
    // drop the local copy once the server has caught up (or cleared/undone it)
    final l = _live;
    if (l != null && !_down && _sent >= l.pts.length) {
      final srv = widget.strokes.where((s) => s.id == l.id);
      if (srv.isEmpty || srv.first.pts.length >= l.pts.length) _live = null;
    }
    if (!widget.enabled) {
      _live = null;
      _down = false;
    }
  }

  (int, int) _norm(Offset p, Size size) => (
        (p.dx / size.width * 1000).round().clamp(0, 1000),
        (p.dy / size.height * 1000).round().clamp(0, 1000),
      );

  void _start(Offset p, Size size) {
    if (!widget.enabled) return;
    _flush();
    final (x, y) = _norm(p, size);
    if (widget.fill) {
      // the previous stroke must be complete before a fill lands on it
      while (_live != null && _sent < _live!.pts.length) {
        _flush();
      }
      widget.send({'type': 'stroke', 'id': _nextId++, 'color': widget.color, 'width': kFillWidth, 'pts': [x, y]});
      return;
    }
    _live = DgStroke(_nextId++, widget.color, widget.width, [x, y]);
    _sent = 0;
    _down = true;
    _schedule();
    setState(() {});
  }

  void _move(Offset p, Size size) {
    final l = _live;
    if (!_down || l == null) return;
    final (x, y) = _norm(p, size);
    final n = l.pts.length;
    if (n >= 2 && (l.pts[n - 2] - x).abs() + (l.pts[n - 1] - y).abs() < 4) return;
    l.pts.addAll([x, y]);
    _schedule();
    _liveTick.value++;
  }

  void _end() {
    if (!_down) return;
    _down = false;
    _flush();
  }

  void _schedule() {
    _timer ??= Timer(const Duration(milliseconds: _flushMs), () {
      _timer = null;
      _flush();
      if (_live != null && _sent < _live!.pts.length) _schedule();
    });
  }

  void _flush() {
    final l = _live;
    if (l == null || _sent >= l.pts.length) return;
    final end = min(l.pts.length, _sent + _maxBatchInts);
    final chunk = l.pts.sublist(_sent, end);
    _sent = end;
    widget.send({'type': 'stroke', 'id': l.id, 'color': l.color, 'width': l.width, 'pts': chunk});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var w = c.maxWidth, h = c.maxWidth * 3 / 4;
      if (h > c.maxHeight) {
        h = c.maxHeight;
        w = h * 4 / 3;
      }
      final size = Size(w, h);
      final live = _live;
      final server = [for (final s in widget.strokes) if (live == null || s.id != live.id) s];
      // everything but the newest server stroke (unless it's a fill) is
      // baked into the bitmap
      final growing = server.isNotEmpty && !server.last.isFill;
      final baked = growing ? server.sublist(0, server.length - 1) : server;
      final dpr = MediaQuery.devicePixelRatioOf(context);
      _cache.update(baked, size, dpr);
      final canvas = RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: DgPainter(_cache.image, dpr, [if (growing) server.last, ?live], repaintOn: _liveTick),
        ),
      );
      return Center(
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(fit: StackFit.expand, children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _start(e.localPosition, size),
                onPointerMove: (e) => _move(e.localPosition, size),
                onPointerUp: (_) => _end(),
                onPointerCancel: (_) => _end(),
                child: MouseRegion(
                    cursor: !widget.enabled
                        ? MouseCursor.defer
                        : (widget.fill ? SystemMouseCursors.click : SystemMouseCursors.precise),
                    child: canvas),
              ),
              if (widget.overlay != null) widget.overlay!,
            ]),
          ),
        ),
      );
    });
  }
}
