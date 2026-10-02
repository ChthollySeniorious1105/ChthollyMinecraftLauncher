import 'dart:math' as math;

import 'package:flutter/material.dart';

const unoColorValues = {
  'r': Color(0xFFE53935),
  'y': Color(0xFFFDD835),
  'g': Color(0xFF43A047),
  'b': Color(0xFF1E88E5),
  'p': Color(0xFFEC407A),
  't': Color(0xFF00ACC1),
  'o': Color(0xFFFB8C00),
  'v': Color(0xFF7E57C2),
  'w': Color(0xFF212121),
};

const unoColorLabel = {
  'r': '红',
  'y': '黄',
  'g': '绿',
  'b': '蓝',
  'p': '粉',
  't': '青',
  'o': '橙',
  'v': '紫',
};

/// A custom-drawn UNO-style card. [face] null = generic card back.
class UnoCard extends StatelessWidget {
  final String? face;
  final double width;
  final bool selected;
  final bool dim;
  final bool highlight;

  /// FLIP dark side (affects wild colour wheel and black-card accent).
  final bool darkSide;
  final VoidCallback? onTap;
  const UnoCard(this.face,
      {super.key, this.width = 60, this.selected = false, this.dim = false, this.highlight = false, this.darkSide = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.5;
    final f = face;
    final bg = f == null ? const Color(0xFF151515) : unoColorValues[f[0]] ?? Colors.grey;
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.25 : 0, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(width * 0.12),
        border: highlight ? Border.all(color: Colors.amberAccent, width: 2.5) : null,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 3, offset: const Offset(1, 2)),
          if (highlight) const BoxShadow(color: Colors.amberAccent, blurRadius: 6),
        ],
      ),
      padding: EdgeInsets.all(width * 0.05),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * 0.09),
        child: CustomPaint(
          painter: _UnoCardPainter(bg, f == null || f[0] == 'w', darkSide),
          child: f == null ? _back() : _front(f),
        ),
      ),
    );
    if (dim) card = Opacity(opacity: 0.45, child: card);
    if (onTap == null) return card;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
  }

  Widget _back() => Center(
        child: Transform.rotate(
          angle: -0.35,
          child: Text('UNO',
              style: TextStyle(
                  color: const Color(0xFFFDD835),
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  fontSize: width * 0.3,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 2, offset: Offset(1, 1))])),
        ),
      );

  Widget _front(String f) {
    final col = unoColorValues[f[0]] ?? Colors.grey;
    final k = f.substring(1);
    final ink = f[0] == 'w' ? Colors.white : col;
    final corner = _cornerLabel(k);
    return Stack(children: [
      Center(child: _symbol(k, ink, width * 0.42)),
      Positioned(left: width * 0.05, top: width * 0.02, child: _smallLabel(corner)),
      Positioned(
          right: width * 0.05,
          bottom: width * 0.02,
          child: Transform.rotate(angle: math.pi, child: _smallLabel(corner))),
    ]);
  }

  Widget _smallLabel(String s) => Text(s,
      style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: width * (s.length > 2 ? 0.14 : 0.2),
          height: 1,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 1, offset: Offset(0.5, 0.5))]));

  static String _cornerLabel(String k) {
    switch (k) {
      case 'S':
        return '⊘';
      case 'R':
        return '⇄';
      case 'F':
        return 'F';
      case 'SA':
        return '⊘⊘';
      case 'DA':
        return '弃';
      case 'W':
        return 'W';
      case 'R4':
        return '+4';
      case 'C':
        return 'W';
      case 'RL':
        return 'W';
    }
    return k;
  }

  Widget _symbol(String k, Color ink, double size) {
    TextStyle ts(double s) => TextStyle(
        color: ink,
        fontWeight: FontWeight.w900,
        fontSize: s,
        height: 1,
        shadows: const [Shadow(color: Colors.black38, blurRadius: 1, offset: Offset(1, 1))]);
    Widget icon(IconData d, [double scale = 1]) => Icon(d, color: ink, size: size * scale);
    switch (k) {
      case 'S':
        return icon(Icons.block);
      case 'R':
        return icon(Icons.sync);
      case 'F':
        return Column(mainAxisSize: MainAxisSize.min, children: [icon(Icons.flip, 0.8), Text('FLIP', style: ts(size * 0.3))]);
      case 'SA':
        return Column(mainAxisSize: MainAxisSize.min, children: [icon(Icons.block, 0.75), Text('全体', style: ts(size * 0.3))]);
      case 'DA':
        return Column(mainAxisSize: MainAxisSize.min, children: [icon(Icons.layers_clear, 0.75), Text('全弃', style: ts(size * 0.3))]);
      case 'W':
        return _wheel(size);
      case 'R4':
        return Column(mainAxisSize: MainAxisSize.min, children: [icon(Icons.sync, 0.6), Text('+4', style: ts(size * 0.5))]);
      case 'C':
        return Column(mainAxisSize: MainAxisSize.min, children: [_wheel(size * 0.55), Text('抽色', style: ts(size * 0.3))]);
      case 'RL':
        return Column(mainAxisSize: MainAxisSize.min, children: [_wheel(size * 0.55), Text('轮盘', style: ts(size * 0.3))]);
    }
    return Text(k, style: ts(k.length > 2 ? size * 0.55 : size * 0.85));
  }

  Widget _wheel(double s) => SizedBox(
        width: s,
        height: s,
        child: CustomPaint(painter: _WheelPainter(darkSide)),
      );
}

class _UnoCardPainter extends CustomPainter {
  final Color bg;
  final bool black;
  final bool dark;
  _UnoCardPainter(this.bg, this.black, this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(0.45);
    final r = Rect.fromCenter(center: Offset.zero, width: size.width * 0.82, height: size.height * 0.62);
    canvas.drawOval(r, Paint()..color = black ? (dark ? const Color(0xFF6A1B9A) : const Color(0xFFD32F2F)) : (dark ? const Color(0xFF212121) : Colors.white));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _UnoCardPainter old) => old.bg != bg || old.black != black || old.dark != dark;
}

class _WheelPainter extends CustomPainter {
  final bool dark;
  _WheelPainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final cols = dark
        ? [unoColorValues['p']!, unoColorValues['t']!, unoColorValues['o']!, unoColorValues['v']!]
        : [unoColorValues['r']!, unoColorValues['b']!, unoColorValues['y']!, unoColorValues['g']!];
    final rect = Offset.zero & size;
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(rect, -math.pi / 2 + i * math.pi / 2, math.pi / 2, true, Paint()..color = cols[i]);
    }
    canvas.drawOval(rect, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.dark != dark;
}
