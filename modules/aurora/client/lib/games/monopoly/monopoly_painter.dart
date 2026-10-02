import 'dart:math';

import 'package:aurora_shared/games/monopoly/board_data.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const List<Color> mPlayerColors = [
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFFB300),
  Color(0xFF8E24AA),
  Color(0xFF00ACC1),
];

const List<Color> mGroupColors = [
  Color(0xFF8D5A3B), // 棕
  Color(0xFF81D4FA), // 浅蓝
  Color(0xFFEC407A), // 粉
  Color(0xFFFF9800), // 橙
  Color(0xFFE53935), // 红
  Color(0xFFFDD835), // 黄
  Color(0xFF2E7D32), // 绿
  Color(0xFF1A3C8F), // 深蓝
];

/// Board geometry in board units: 9 side cells of 1 unit plus corners of [corner] units.
class MGeo {
  static const double corner = 1.6;
  static const double total = corner * 2 + 9; // 12.2
  static const double band = 0.3;

  /// 0 bottom, 1 left, 2 top, 3 right; -1 corner.
  static int side(int i) => i % 10 == 0 ? -1 : i ~/ 10;

  static Rect cell(int i, double u) {
    const c = corner;
    Rect r;
    if (i == 0) {
      r = const Rect.fromLTWH(c + 9, c + 9, c, c);
    } else if (i < 10) {
      r = Rect.fromLTWH(c + 9 - i, c + 9, 1, c);
    } else if (i == 10) {
      r = const Rect.fromLTWH(0, c + 9, c, c);
    } else if (i < 20) {
      r = Rect.fromLTWH(0, c + 9 - (i - 10), c, 1);
    } else if (i == 20) {
      r = const Rect.fromLTWH(0, 0, c, c);
    } else if (i < 30) {
      r = Rect.fromLTWH(c + (i - 21), 0, 1, c);
    } else if (i == 30) {
      r = const Rect.fromLTWH(c + 9, 0, c, c);
    } else {
      r = Rect.fromLTWH(c + 9, c + (i - 31), c, 1);
    }
    return Rect.fromLTWH(r.left * u, r.top * u, r.width * u, r.height * u);
  }

  /// Colour band on the inner edge of a side cell.
  static Rect bandRect(int i, double u) {
    final r = cell(i, u);
    final b = band * u;
    switch (side(i)) {
      case 0:
        return Rect.fromLTWH(r.left, r.top, r.width, b);
      case 1:
        return Rect.fromLTWH(r.right - b, r.top, b, r.height);
      case 2:
        return Rect.fromLTWH(r.left, r.bottom - b, r.width, b);
      case 3:
        return Rect.fromLTWH(r.left, r.top, b, r.height);
    }
    return r;
  }

  /// Owner strip on the outer edge.
  static Rect ownerRect(int i, double u) {
    final r = cell(i, u);
    final b = 0.13 * u;
    switch (side(i)) {
      case 0:
        return Rect.fromLTWH(r.left, r.bottom - b, r.width, b);
      case 1:
        return Rect.fromLTWH(r.left, r.top, b, r.height);
      case 2:
        return Rect.fromLTWH(r.left, r.top, r.width, b);
      case 3:
        return Rect.fromLTWH(r.right - b, r.top, b, r.height);
    }
    return r;
  }

  /// Area for text (cell minus band and owner strip).
  static Rect bodyRect(int i, double u) {
    final r = cell(i, u);
    final b = band * u, o = 0.13 * u;
    switch (side(i)) {
      case 0:
        return Rect.fromLTRB(r.left, r.top + b, r.right, r.bottom - o);
      case 1:
        return Rect.fromLTRB(r.left + o, r.top, r.right - b, r.bottom);
      case 2:
        return Rect.fromLTRB(r.left, r.top + o, r.right, r.bottom - b);
      case 3:
        return Rect.fromLTRB(r.left + b, r.top, r.right - o, r.bottom);
    }
    return r;
  }

  static int? hit(Offset p, double u) {
    for (var i = 0; i < 40; i++) {
      if (cell(i, u).contains(p)) return i;
    }
    return null;
  }
}

String mSqIcon(Sq s) => switch (s.type) {
      SqType.station => '🚄',
      SqType.utility => s.name.contains('电') ? '⚡' : '💧',
      SqType.tax => '💰',
      SqType.chance => '？',
      SqType.chest => '🎁',
      _ => '',
    };

class MonopolyPainter extends CustomPainter {
  final ColorScheme cs;
  final List<int> owner;
  final List<int> houses;
  final List<bool> mortgaged;
  final Set<int> highlight;
  final int focus; // square to emphasise (buy / auction / last landing)
  final int pot;
  final bool potOn;
  MonopolyPainter({
    required this.cs,
    required this.owner,
    required this.houses,
    required this.mortgaged,
    required this.highlight,
    required this.focus,
    required this.pot,
    required this.potOn,
  });

  static const _paper = Color(0xFFF3F0E2);
  static const _ink = Color(0xFF263238);

  void _text(Canvas canvas, String s, Rect box, double size,
      {Color color = _ink, FontWeight weight = FontWeight.w600, double dy = 0, int lines = 2}) {
    var fs = size;
    TextPainter tp;
    while (true) {
      tp = TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                fontSize: fs,
                color: color,
                fontWeight: weight,
                height: 1.05,
                fontFamily: kFontFallback.first,
                fontFamilyFallback: kFontFallback)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: max(1, box.width));
      if ((tp.width <= box.width + 0.5 && !tp.didExceedMaxLines) || fs < 5) break;
      fs *= 0.88;
    }
    tp.paint(canvas, Offset(box.center.dx - tp.width / 2, box.center.dy - tp.height / 2 + dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / MGeo.total;
    final full = Offset.zero & size;
    // board shadow + base
    canvas.drawRRect(RRect.fromRectAndRadius(full.shift(Offset(u * 0.05, u * 0.1)), Radius.circular(u * 0.3)),
        Paint()..color = Colors.black38..maskFilter = MaskFilter.blur(BlurStyle.normal, u * 0.15));
    canvas.drawRRect(RRect.fromRectAndRadius(full, Radius.circular(u * 0.3)), Paint()..color = _paper);

    // centre
    final inner = Rect.fromLTWH(MGeo.corner * u, MGeo.corner * u, 9 * u, 9 * u);
    canvas.drawRect(
        inner,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xFFDDEFD9), Color(0xFFBFDDBA)])
              .createShader(inner));
    // big diagonal title
    canvas.save();
    canvas.translate(inner.center.dx, inner.center.dy);
    canvas.rotate(-pi / 4);
    _text(canvas, '大富翁', Rect.fromCenter(center: Offset.zero, width: 9 * u, height: 2 * u), u * 1.5,
        color: const Color(0xFFB71C1C).withValues(alpha: 0.12), weight: FontWeight.w900, lines: 1);
    canvas.restore();

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, u * 0.025)
      ..color = _ink.withValues(alpha: 0.7);

    for (var i = 0; i < 40; i++) {
      final sq = mBoard[i];
      final r = MGeo.cell(i, u);
      canvas.drawRect(r, Paint()..color = i == focus ? const Color(0xFFFFF3C4) : _paper);
      if (MGeo.side(i) < 0) {
        _corner(canvas, i, r, u);
      } else {
        final body = MGeo.bodyRect(i, u).deflate(u * 0.04);
        if (sq.type == SqType.street) {
          final band = MGeo.bandRect(i, u);
          canvas.drawRect(band, Paint()..color = mGroupColors[sq.group]);
          canvas.drawRect(band, line);
          _houses(canvas, i, band, u);
        }
        final icon = mSqIcon(sq);
        final vertical = MGeo.side(i) == 0 || MGeo.side(i) == 2;
        if (icon.isNotEmpty) {
          final iconBox = vertical
              ? Rect.fromLTWH(body.left, body.top + body.height * 0.3, body.width, body.height * 0.4)
              : Rect.fromLTWH(body.left, body.top + body.height * 0.4, body.width, body.height * 0.36);
          _text(canvas, icon, iconBox, u * 0.42,
              color: sq.type == SqType.chance ? const Color(0xFFE65100) : _ink, weight: FontWeight.w900, lines: 1);
        }
        final nameBox = Rect.fromLTWH(body.left, body.top, body.width, body.height * (icon.isEmpty ? 0.55 : 0.34));
        _text(canvas, sq.name, nameBox, u * 0.24, lines: 2);
        final priceText = sq.ownable ? '¥${sq.price}' : (sq.type == SqType.tax ? '¥${sq.rents[0]}' : '');
        if (priceText.isNotEmpty) {
          final pb = Rect.fromLTWH(body.left, body.bottom - body.height * 0.28, body.width, body.height * 0.28);
          _text(canvas, priceText, pb, u * 0.2, weight: FontWeight.w500, lines: 1);
        }
      }
      // owner strip
      if (sq.ownable && owner[i] >= 0) {
        final o = MGeo.ownerRect(i, u);
        canvas.drawRect(o, Paint()..color = mPlayerColors[owner[i] % mPlayerColors.length]);
      }
      if (mortgaged[i]) {
        canvas.drawRect(r, Paint()..color = Colors.black.withValues(alpha: 0.35));
        _text(canvas, '押', Rect.fromCenter(center: r.center, width: u * 0.6, height: u * 0.6), u * 0.42,
            color: Colors.white, weight: FontWeight.w900, lines: 1);
      }
      canvas.drawRect(r, line);
      if (highlight.contains(i)) {
        canvas.drawRect(
            r.deflate(u * 0.05),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.1
              ..color = Colors.amber);
      }
    }
    canvas.drawRect(inner, line);
    canvas.drawRRect(
        RRect.fromRectAndRadius(full, Radius.circular(u * 0.3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.08
          ..color = const Color(0xFF455A64));
  }

  void _houses(Canvas canvas, int i, Rect band, double u) {
    final h = houses[i];
    if (h <= 0) return;
    final horiz = band.width > band.height;
    final len = horiz ? band.width : band.height;
    final thick = horiz ? band.height : band.width;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.5, u * 0.02)
      ..color = Colors.black87;
    if (h == 5) {
      final r = horiz
          ? Rect.fromCenter(center: band.center, width: len * 0.55, height: thick * 0.72)
          : Rect.fromCenter(center: band.center, width: thick * 0.72, height: len * 0.55);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(u * 0.04));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFFD32F2F));
      canvas.drawRRect(rr, border);
      return;
    }
    final s = min(thick * 0.7, len / 4.6);
    final gap = (len - s * 4) / 5;
    for (var k = 0; k < h; k++) {
      final along = gap + k * (s + gap) + s / 2;
      final c = horiz
          ? Offset(band.left + along, band.center.dy)
          : Offset(band.center.dx, band.top + along);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s, height: s), Radius.circular(s * 0.15));
      canvas.drawRRect(r, Paint()..color = const Color(0xFF2E7D32));
      canvas.drawRRect(r, border);
    }
  }

  void _corner(Canvas canvas, int i, Rect r, double u) {
    final big = u * 0.34;
    switch (i) {
      case 0:
        _text(canvas, '起点', Rect.fromLTWH(r.left, r.top + r.height * 0.08, r.width, r.height * 0.3), big,
            color: const Color(0xFFC62828), weight: FontWeight.w900, lines: 1);
        _text(canvas, '←', Rect.fromLTWH(r.left, r.top + r.height * 0.36, r.width, r.height * 0.32), u * 0.6,
            color: const Color(0xFFC62828), weight: FontWeight.w900, lines: 1);
        _text(canvas, '经过领 ¥200', Rect.fromLTWH(r.left, r.top + r.height * 0.68, r.width, r.height * 0.26), u * 0.2,
            lines: 1);
      case 10:
        // jail box in the inner-top-right part; "探监" around the outer edges
        final jail = Rect.fromLTWH(r.left + r.width * 0.3, r.top, r.width * 0.7, r.height * 0.7);
        canvas.drawRect(jail, Paint()..color = const Color(0xFFFFB74D));
        final bars = Paint()
          ..color = Colors.black54
          ..strokeWidth = u * 0.04;
        for (var k = 1; k < 5; k++) {
          final x = jail.left + jail.width * k / 5;
          canvas.drawLine(Offset(x, jail.top), Offset(x, jail.bottom), bars);
        }
        canvas.drawRect(
            jail,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = u * 0.04
              ..color = _ink);
        _text(canvas, '监狱', jail.deflate(u * 0.1), big, weight: FontWeight.w900, lines: 1);
        _text(canvas, '探监', Rect.fromLTWH(r.left, r.bottom - r.height * 0.3, r.width, r.height * 0.3), u * 0.24,
            lines: 1);
      case 20:
        _text(canvas, '🅿', Rect.fromLTWH(r.left, r.top + r.height * 0.12, r.width, r.height * 0.4), u * 0.6,
            color: const Color(0xFF1565C0), lines: 1);
        _text(canvas, '免费停车', Rect.fromLTWH(r.left, r.top + r.height * 0.52, r.width, r.height * 0.22), u * 0.26,
            weight: FontWeight.w800, lines: 1);
        if (potOn) {
          _text(canvas, '奖池 ¥$pot', Rect.fromLTWH(r.left, r.top + r.height * 0.74, r.width, r.height * 0.2),
              u * 0.22, color: const Color(0xFF2E7D32), weight: FontWeight.w800, lines: 1);
        }
      case 30:
        _text(canvas, '👮', Rect.fromLTWH(r.left, r.top + r.height * 0.12, r.width, r.height * 0.42), u * 0.6,
            lines: 1);
        _text(canvas, '入狱', Rect.fromLTWH(r.left, r.top + r.height * 0.56, r.width, r.height * 0.3), big,
            color: const Color(0xFF1A237E), weight: FontWeight.w900, lines: 1);
    }
  }

  @override
  bool shouldRepaint(covariant MonopolyPainter o) => true;
}
