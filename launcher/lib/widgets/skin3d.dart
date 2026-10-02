import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cml_core/cml_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:vector_math/vector_math_64.dart' as vm;

/// Software-rendered 3D Minecraft player: each texel is a quad, sorted back-to-front.
/// Fast enough for a 64×64 skin (≈ 3–5k visible quads) and needs no GPU plumbing.
class Skin3DView extends StatefulWidget {
  final img.Image skin;
  final bool slim;
  final bool showOverlay;
  final ui.Image? cape;

  /// Bumped by the editor whenever pixels change.
  final int revision;
  const Skin3DView({super.key, required this.skin, required this.slim, this.showOverlay = true, this.cape, this.revision = 0});

  @override
  State<Skin3DView> createState() => _Skin3DViewState();
}

class _Skin3DViewState extends State<Skin3DView> {
  double yaw = -0.5, pitch = 0.15, zoom = 1;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onPanUpdate: (d) => setState(() {
          yaw += d.delta.dx * 0.01;
          pitch = (pitch + d.delta.dy * 0.01).clamp(-1.4, 1.4);
        }),
        onDoubleTap: () => setState(() {
          yaw = -0.5;
          pitch = 0.15;
          zoom = 1;
        }),
        child: Listener(
          onPointerSignal: (e) {
            if (e is PointerScrollEvent) setState(() => zoom = (zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(0.5, 3));
          },
          child: CustomPaint(
            painter: _SkinPainter(widget.skin, widget.slim, widget.showOverlay, yaw, pitch, zoom, widget.revision),
            size: Size.infinite,
          ),
        ),
      );
}

class _Quad {
  final List<vm.Vector3> pts;
  final Color color;
  final double depth;
  _Quad(this.pts, this.color, this.depth);
}

class _SkinPainter extends CustomPainter {
  final img.Image skin;
  final bool slim, overlay;
  final double yaw, pitch, zoom;
  final int revision;
  _SkinPainter(this.skin, this.slim, this.overlay, this.yaw, this.pitch, this.zoom, this.revision);

  Color _px(int x, int y) {
    final p = skin.getPixel(x, y);
    return Color.fromARGB(p.a.toInt(), p.r.toInt(), p.g.toInt(), p.b.toInt());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rot = vm.Matrix4.rotationX(pitch)..rotateY(yaw);
    final quads = <_Quad>[];
    final light = vm.Vector3(0.4, 0.8, 0.6)..normalize();

    void box(SkinPart part, {required bool outer}) {
      final inflate = outer ? (part.id == 'head' ? 0.5 : 0.25) : 0.0;
      final w = part.w + inflate * 2, h = part.h + inflate * 2, d = part.d + inflate * 2;
      final cx = part.px, cy = part.py, cz = part.pz;
      final faces = part.faces(overlay: outer);
      // face → (origin corner, u axis, v axis, normal) in model space; v goes down the texture
      final x0 = cx - w / 2, x1 = cx + w / 2, y0 = cy + h / 2, y1 = cy - h / 2, z0 = cz - d / 2, z1 = cz + d / 2;
      final defs = <String, (vm.Vector3, vm.Vector3, vm.Vector3, vm.Vector3)>{
        'front': (vm.Vector3(x1, y0, z1), vm.Vector3(-1, 0, 0), vm.Vector3(0, -1, 0), vm.Vector3(0, 0, 1)),
        'back': (vm.Vector3(x0, y0, z0), vm.Vector3(1, 0, 0), vm.Vector3(0, -1, 0), vm.Vector3(0, 0, -1)),
        'right': (vm.Vector3(x1, y0, z0), vm.Vector3(0, 0, 1), vm.Vector3(0, -1, 0), vm.Vector3(1, 0, 0)),
        'left': (vm.Vector3(x0, y0, z1), vm.Vector3(0, 0, -1), vm.Vector3(0, -1, 0), vm.Vector3(-1, 0, 0)),
        'top': (vm.Vector3(x1, y0, z0), vm.Vector3(-1, 0, 0), vm.Vector3(0, 0, 1), vm.Vector3(0, 1, 0)),
        'bottom': (vm.Vector3(x1, y1, z1), vm.Vector3(-1, 0, 0), vm.Vector3(0, 0, -1), vm.Vector3(0, -1, 0)),
      };
      for (final e in defs.entries) {
        final rect = faces[e.key]!;
        final (origin, uAxis, vAxis, normal) = e.value;
        final n = rot.transform3(normal.clone());
        if (n.z <= 0 && !outer) continue; // back-face cull (keep outer layer two-sided for gaps)
        final shade = 0.55 + 0.45 * math.max(0, n.dot(light));
        final su = (e.key == 'top' || e.key == 'bottom' || e.key == 'front' || e.key == 'back') ? w / rect.w : d / rect.w;
        final sv = (e.key == 'top' || e.key == 'bottom') ? d / rect.h : h / rect.h;
        for (var ty = 0; ty < rect.h; ty++) {
          for (var tx = 0; tx < rect.w; tx++) {
            final c = _px(rect.x + tx, rect.y + ty);
            if (c.a == 0) continue;
            final a = origin + uAxis * (tx * su) + vAxis * (ty * sv);
            final pts = [a, a + uAxis * su, a + uAxis * su + vAxis * sv, a + vAxis * sv].map((p) => rot.transform3(p.clone())).toList();
            final depth = (pts[0].z + pts[2].z) / 2;
            quads.add(_Quad(pts, Color.fromARGB((c.a * 255).round(), (c.r * 255 * shade).round().clamp(0, 255), (c.g * 255 * shade).round().clamp(0, 255), (c.b * 255 * shade).round().clamp(0, 255)), depth));
          }
        }
      }
    }

    for (final part in SkinModel.parts(slim: slim)) {
      box(part, outer: false);
      if (overlay) box(part, outer: true);
    }
    quads.sort((a, b) => a.depth.compareTo(b.depth));

    final scale = size.shortestSide / 40 * zoom;
    final center = Offset(size.width / 2, size.height / 2 + 2 * scale);
    final paint = Paint()..isAntiAlias = false;
    final path = Path();
    for (final q in quads) {
      path.reset();
      path.moveTo(center.dx + q.pts[0].x * scale, center.dy - (q.pts[0].y - 16) * scale);
      for (var i = 1; i < 4; i++) {
        path.lineTo(center.dx + q.pts[i].x * scale, center.dy - (q.pts[i].y - 16) * scale);
      }
      path.close();
      paint.color = q.color;
      canvas.drawPath(path, paint);
      // a hairline in the same colour hides seams between neighbouring quads
      canvas.drawPath(path, Paint()
        ..color = q.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6);
    }
  }

  @override
  bool shouldRepaint(_SkinPainter o) =>
      o.revision != revision || o.yaw != yaw || o.pitch != pitch || o.zoom != zoom || o.slim != slim || o.overlay != overlay || !identical(o.skin, skin);
}
