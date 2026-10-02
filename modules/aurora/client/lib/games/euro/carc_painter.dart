import 'dart:math';
import 'dart:ui' as ui;

import 'package:aurora_shared/games/euro/carc_tiles.dart';
import 'package:flutter/material.dart';

const _field = Color(0xFF7FB55A);
const _fieldDark = Color(0xFF6A9E48);
const _city = Color(0xFFC9A46A);
const _cityEdge = Color(0xFF8A6534);
const _road = Color(0xFFF1E9D6);
const _roadEdge = Color(0xFF9C8D70);

TileType? carcType(String? id) {
  if (id == null) return null;
  final i = carcTypeIndex(id);
  return i < 0 ? null : carcTiles[i];
}

Offset _p(double x, double y, int r) {
  final (a, b) = rotatePoint(x, y, r);
  return Offset(a, b);
}

/// City polygon (unit coords) for a city feature occupying [sides].
Path _cityPath(List<int> sides) {
  final s = sides.toSet();
  final path = Path();
  void poly(List<Offset> pts, List<int?> ctrlIdx, List<Offset> ctrls) {
    path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i <= pts.length; i++) {
      final to = pts[i % pts.length];
      final ci = ctrlIdx[i - 1];
      if (ci == null) {
        path.lineTo(to.dx, to.dy);
      } else {
        path.quadraticBezierTo(ctrls[ci].dx, ctrls[ci].dy, to.dx, to.dy);
      }
    }
    path.close();
  }

  if (s.length == 4) {
    path.addRect(const Rect.fromLTWH(0, 0, 1, 1));
  } else if (s.length == 1) {
    final r = s.first;
    poly([_p(0, 0, r), _p(1, 0, r)], [null, 0], [_p(0.5, 0.48, r)]);
  } else if (s.length == 2 && (s.first - s.last).abs() == 2) {
    final r = s.contains(1) ? 0 : 1; // base: E+W band
    poly([_p(0, 0, r), _p(0, 1, r), _p(1, 1, r), _p(1, 0, r)], [null, 0, null, 1], [_p(0.5, 0.62, r), _p(0.5, 0.38, r)]);
  } else if (s.length == 2) {
    // adjacent: base = N+W (sides 0,3)
    var r = 0;
    for (var k = 0; k < 4; k++) {
      if (s.contains(k) && s.contains((k + 3) % 4)) r = k;
    }
    poly([_p(0, 0, r), _p(1, 0, r), _p(0, 1, r)], [null, 0, null], [_p(0.62, 0.62, r)]);
  } else {
    final missing = [0, 1, 2, 3].firstWhere((k) => !s.contains(k));
    final r = (missing + 2) % 4; // base missing = S
    poly([_p(0, 0, r), _p(1, 0, r), _p(1, 1, r), _p(0, 1, r)], [null, null, 0, null], [_p(0.5, 0.52, r)]);
  }
  return path;
}

Offset _sideMid(int s) => switch (s) { 0 => const Offset(0.5, 0), 1 => const Offset(1, 0.5), 2 => const Offset(0.5, 1), _ => const Offset(0, 0.5) };

/// Paints tile [t] rotated [rot] quarter turns into [rect].
void paintCarcTile(Canvas canvas, Rect rect, TileType t, int rot, {double opacity = 1}) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width, rect.height);
  if (opacity < 1) {
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
  }
  // rotate about the centre
  canvas.translate(0.5, 0.5);
  canvas.rotate(rot * pi / 2);
  canvas.translate(-0.5, -0.5);

  // field
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1, 1),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(1, 1), [_field, _fieldDark]));
  final grass = Paint()
    ..color = const Color(0x3325501A)
    ..strokeWidth = 0.012
    ..strokeCap = StrokeCap.round;
  final seed = t.id.codeUnitAt(0);
  for (var i = 0; i < 9; i++) {
    final x = ((seed * 37 + i * 53) % 90) / 100 + 0.05, y = ((seed * 17 + i * 71) % 90) / 100 + 0.05;
    canvas.drawLine(Offset(x, y), Offset(x + 0.02, y - 0.04), grass);
    canvas.drawLine(Offset(x + 0.03, y), Offset(x + 0.035, y - 0.035), grass);
  }

  // roads
  final roadW = Paint()
    ..color = _roadEdge
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.13
    ..strokeCap = StrokeCap.butt;
  final roadIn = Paint()
    ..color = _road
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.09
    ..strokeCap = StrokeCap.butt;
  final roadPaths = <Path>[];
  var junction = false;
  for (final f in t.features) {
    if (f.kind != FeatureKind.road) continue;
    final p = Path();
    if (f.sides.length == 2) {
      final a = _sideMid(f.sides[0]), b = _sideMid(f.sides[1]);
      p.moveTo(a.dx, a.dy);
      if ((f.sides[0] - f.sides[1]).abs() == 2) {
        p.lineTo(b.dx, b.dy);
      } else {
        p.quadraticBezierTo(0.5, 0.5, b.dx, b.dy);
      }
    } else {
      final a = _sideMid(f.sides[0]);
      final end = t.hasCloister ? const Offset(0.5, 0.55) : (t.roadCount == 1 ? const Offset(0.5, 0.62) : const Offset(0.5, 0.5));
      if (t.roadCount >= 3) junction = true;
      p.moveTo(a.dx, a.dy);
      p.lineTo(end.dx, end.dy);
    }
    roadPaths.add(p);
  }
  for (final p in roadPaths) {
    canvas.drawPath(p, roadW);
  }
  for (final p in roadPaths) {
    canvas.drawPath(p, roadIn);
  }

  // cities
  for (final f in t.features) {
    if (f.kind != FeatureKind.city) continue;
    final path = _cityPath(f.sides);
    canvas.drawPath(path, Paint()..color = _city);
    canvas.save();
    canvas.clipPath(path);
    final roof = Paint()..color = const Color(0xFFB0473A);
    final wall = Paint()..color = const Color(0xFFE6D2A8);
    for (var i = 0; i < 16; i++) {
      final x = (i % 4) * 0.25 + 0.06 + (i ~/ 4 % 2) * 0.1, y = (i ~/ 4) * 0.25 + 0.07;
      canvas.drawRect(Rect.fromLTWH(x, y + 0.035, 0.07, 0.05), wall);
      canvas.drawPath(
          Path()
            ..moveTo(x - 0.01, y + 0.04)
            ..lineTo(x + 0.035, y)
            ..lineTo(x + 0.08, y + 0.04)
            ..close(),
          roof);
    }
    canvas.restore();
    canvas.drawPath(
        path,
        Paint()
          ..color = _cityEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.035);
  }
  // shields
  for (final f in t.features) {
    if (!f.shield) continue;
    final c = Offset((f.ax + 0.2).clamp(0.12, 0.88), (f.ay - 0.14).clamp(0.1, 0.88));
    final sp = Path()
      ..moveTo(c.dx - 0.07, c.dy - 0.07)
      ..lineTo(c.dx + 0.07, c.dy - 0.07)
      ..lineTo(c.dx + 0.07, c.dy + 0.01)
      ..quadraticBezierTo(c.dx + 0.06, c.dy + 0.07, c.dx, c.dy + 0.1)
      ..quadraticBezierTo(c.dx - 0.06, c.dy + 0.07, c.dx - 0.07, c.dy + 0.01)
      ..close();
    canvas.drawPath(sp, Paint()..color = const Color(0xFF2D5BB8));
    canvas.drawPath(
        sp,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.018);
    canvas.drawRect(Rect.fromCenter(center: c.translate(0, 0.005), width: 0.02, height: 0.08), Paint()..color = Colors.white);
    canvas.drawRect(Rect.fromCenter(center: c.translate(0, -0.01), width: 0.08, height: 0.02), Paint()..color = Colors.white);
  }
  // cloister
  for (final f in t.features) {
    if (f.kind != FeatureKind.cloister) continue;
    final c = Offset(f.ax, f.ay);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 0.4, height: 0.36), const Radius.circular(0.04)),
        Paint()..color = const Color(0x55305020));
    canvas.drawRect(Rect.fromLTWH(c.dx - 0.13, c.dy - 0.02, 0.26, 0.16), Paint()..color = const Color(0xFFEDE0C4));
    canvas.drawPath(
        Path()
          ..moveTo(c.dx - 0.17, c.dy)
          ..lineTo(c.dx, c.dy - 0.13)
          ..lineTo(c.dx + 0.17, c.dy)
          ..close(),
        Paint()..color = const Color(0xFFB0473A));
    canvas.drawRect(Rect.fromLTWH(c.dx - 0.03, c.dy + 0.06, 0.06, 0.08), Paint()..color = const Color(0xFF6B4A2A));
    final cross = Paint()
      ..color = const Color(0xFF6B4A2A)
      ..strokeWidth = 0.02;
    canvas.drawLine(Offset(c.dx, c.dy - 0.21), Offset(c.dx, c.dy - 0.12), cross);
    canvas.drawLine(Offset(c.dx - 0.035, c.dy - 0.18), Offset(c.dx + 0.035, c.dy - 0.18), cross);
  }
  if (junction) {
    canvas.drawRect(Rect.fromCenter(center: const Offset(0.5, 0.5), width: 0.16, height: 0.16), Paint()..color = const Color(0xFF9A6B3E));
    canvas.drawPath(
        Path()
          ..moveTo(0.4, 0.44)
          ..lineTo(0.5, 0.36)
          ..lineTo(0.6, 0.44)
          ..close(),
        Paint()..color = const Color(0xFFB0473A));
  }
  canvas.restore();
  if (opacity < 1) canvas.restore();
  // frame (unrotated)
  canvas.drawRect(
      rect.deflate(0.25),
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5);
}

/// Stand-alone tile widget (for previews / the current tile panel).
class CarcTileView extends StatelessWidget {
  final String? id;
  final int rot;
  final double size;
  const CarcTileView(this.id, {super.key, this.rot = 0, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final t = carcType(id);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38, offset: Offset(1, 2))]),
      child: t == null
          ? const ColoredBox(color: Colors.black12)
          : CustomPaint(size: Size.square(size), painter: _TilePainter(t, rot)),
    );
  }
}

class _TilePainter extends CustomPainter {
  final TileType t;
  final int rot;
  _TilePainter(this.t, this.rot);
  @override
  void paint(Canvas canvas, Size size) => paintCarcTile(canvas, Offset.zero & size, t, rot);
  @override
  bool shouldRepaint(_TilePainter old) => old.t != t || old.rot != rot;
}
