import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../common/errors.dart';

/// A cuboid face region on the 64×64 skin texture.
class FaceRect {
  final int x, y, w, h;
  const FaceRect(this.x, this.y, this.w, this.h);
}

/// One body part: its box size and the texture origin (u, v) for the base and overlay layer.
class SkinPart {
  final String id;
  final String label;
  final int w, h, d; // width (x), height (y), depth (z) in pixels
  final int u, v; // base layer origin
  final int ou, ov; // overlay layer origin
  final double px, py, pz; // model position of the box's centre (for 3D)
  const SkinPart(this.id, this.label, this.w, this.h, this.d, this.u, this.v, this.ou, this.ov, this.px, this.py, this.pz);

  /// Texture rectangles of the six faces (Minecraft box UV layout).
  Map<String, FaceRect> faces({bool overlay = false}) {
    final bu = overlay ? ou : u, bv = overlay ? ov : v;
    return {
      'top': FaceRect(bu + d, bv, w, d),
      'bottom': FaceRect(bu + d + w, bv, w, d),
      'right': FaceRect(bu, bv + d, d, h),
      'front': FaceRect(bu + d, bv + d, w, h),
      'left': FaceRect(bu + d + w, bv + d, d, h),
      'back': FaceRect(bu + d + w + d, bv + d, w, h),
    };
  }
}

/// Skin model + texture helpers for the skin editor.
abstract class SkinModel {
  static List<SkinPart> parts({required bool slim}) {
    final aw = slim ? 3 : 4;
    return [
      const SkinPart('head', '头', 8, 8, 8, 0, 0, 32, 0, 0, 28, 0),
      const SkinPart('body', '身体', 8, 12, 4, 16, 16, 16, 32, 0, 18, 0),
      SkinPart('rarm', '右臂', aw, 12, 4, 40, 16, 40, 32, -(4 + aw / 2), 18, 0),
      SkinPart('larm', '左臂', aw, 12, 4, 32, 48, 48, 48, 4 + aw / 2, 18, 0),
      const SkinPart('rleg', '右腿', 4, 12, 4, 0, 16, 0, 32, -2, 6, 0),
      const SkinPart('lleg', '左腿', 4, 12, 4, 16, 48, 0, 48, 2, 6, 0),
    ];
  }

  /// Decodes a skin PNG, upgrading legacy 64×32 skins to 64×64 (mirrored limbs).
  static img.Image decode(Uint8List png) {
    final src = img.decodePng(png) ?? (throw const CmlException('skin_format', '无法读取皮肤图片（需要 PNG）'));
    if (src.width == 64 && src.height == 64) return src.convert(numChannels: 4);
    if (src.width == 64 && src.height == 32) return upgradeLegacy(src);
    if (src.width == src.height * 2 || src.width == src.height) {
      // HD skins: scale down to 64-based for editing
      return img.copyResize(src.width == src.height ? src : upgradeLegacy(img.copyResize(src, width: 64, height: 32)), width: 64, height: 64, interpolation: img.Interpolation.nearest)
          .convert(numChannels: 4);
    }
    throw const CmlException('skin_size', '皮肤尺寸必须是 64×64 或 64×32');
  }

  /// 64×32 → 64×64: left arm/leg are mirrored copies of the right ones.
  static img.Image upgradeLegacy(img.Image old) {
    final out = img.Image(width: 64, height: 64, numChannels: 4);
    img.compositeImage(out, old.convert(numChannels: 4), dstX: 0, dstY: 0);
    void mirrorBox(int su, int sv, int du, int dv, int w, int h, int d) {
      // copy each face with horizontal flip, swapping left/right faces
      void face(int sx, int sy, int dx, int dy, int fw, int fh) {
        for (var y = 0; y < fh; y++) {
          for (var x = 0; x < fw; x++) {
            out.setPixel(dx + fw - 1 - x, dy + y, old.getPixel(sx + x, sy + y));
          }
        }
      }

      face(su + d, sv, du + d, dv, w, d); // top
      face(su + d + w, sv, du + d + w, dv, w, d); // bottom
      face(su, sv + d, du + d + w, dv + d, d, h); // right → left
      face(su + d, sv + d, du + d, dv + d, w, h); // front
      face(su + d + w, sv + d, du, dv + d, d, h); // left → right
      face(su + d + w + d, sv + d, du + d + w + d, dv + d, w, h); // back
    }

    mirrorBox(0, 16, 16, 48, 4, 12, 4); // leg
    mirrorBox(40, 16, 32, 48, 4, 12, 4); // arm
    return out;
  }

  static Uint8List encode(img.Image skin) => Uint8List.fromList(img.encodePng(skin));

  /// Blank Steve-coloured template.
  static img.Image blank() {
    final s = img.Image(width: 64, height: 64, numChannels: 4);
    final skinTone = img.ColorRgba8(0xC6, 0x8E, 0x6A, 255), shirt = img.ColorRgba8(0x00, 0xA8, 0xA8, 255), pants = img.ColorRgba8(0x3A, 0x3A, 0x9A, 255);
    for (final part in parts(slim: false)) {
      final color = switch (part.id) { 'head' => skinTone, 'body' || 'rarm' || 'larm' => shirt, _ => pants };
      for (final f in part.faces().values) {
        img.fillRect(s, x1: f.x, y1: f.y, x2: f.x + f.w - 1, y2: f.y + f.h - 1, color: color);
      }
    }
    return s;
  }

  /// Guess model from pixel (54, 20): transparent in slim skins (arm is 3px wide).
  static bool guessSlim(img.Image s) => s.getPixel(54, 20).a == 0 && s.getPixel(55, 20).a == 0;
}
