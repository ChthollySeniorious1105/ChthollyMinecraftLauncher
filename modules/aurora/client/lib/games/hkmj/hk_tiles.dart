import 'package:flutter/material.dart';

import '../../widgets/pieces.dart';

const flowerChars = ['春', '夏', '秋', '冬', '梅', '兰', '竹', '菊'];
const _flowerColors = [
  Color(0xFF2E7D32), // 春
  Color(0xFFC62828), // 夏
  Color(0xFFEF6C00), // 秋
  Color(0xFF1565C0), // 冬
  Color(0xFFAD1457), // 梅
  Color(0xFF6A1B9A), // 兰
  Color(0xFF00695C), // 竹
  Color(0xFFF9A825), // 菊
];

bool isFlowerCode(String c) => c.length == 2 && c[1] == 'f';

/// Flower tile (春夏秋冬梅兰竹菊), drawn in code; same size API as [MahjongTile].
class FlowerTile extends StatelessWidget {
  final String code;
  final double width;
  final bool highlight;
  final bool sideways;
  const FlowerTile(this.code, {super.key, this.width = 36, this.highlight = false, this.sideways = false});

  @override
  Widget build(BuildContext context) {
    final i = ((int.tryParse(code[0]) ?? 1) - 1).clamp(0, 7);
    final color = _flowerColors[i];
    final h = width * 4 / 3;
    Widget face = Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF4), Color(0xFFF1E8D2)],
        ),
        borderRadius: BorderRadius.circular(width * 0.1),
        border: Border.all(color: const Color(0xFFD9CFB6), width: width * 0.03),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 2, offset: const Offset(1, 2))],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.9, 0.9],
          colors: [Color(0x00000000), Color(0xFF8FB39A)],
        ),
      ),
      padding: EdgeInsets.all(width * 0.06),
      child: Stack(children: [
        Positioned(
          left: 0,
          top: 0,
          child: Text('${i % 4 + 1}',
              style: TextStyle(fontSize: width * 0.2, color: color, fontWeight: FontWeight.bold, height: 1)),
        ),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(i < 4 ? Icons.wb_sunny_outlined : Icons.local_florist, size: width * 0.34, color: color.withValues(alpha: 0.8)),
              Text(flowerChars[i],
                  style: TextStyle(fontSize: width * 0.46, color: color, fontWeight: FontWeight.w900, height: 1.05)),
            ]),
          ),
        ),
        if (highlight)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.amber, width: 2),
                borderRadius: BorderRadius.circular(width * 0.08),
              ),
            ),
          ),
      ]),
    );
    if (sideways) face = RotatedBox(quarterTurns: 1, child: face);
    return face;
  }
}

/// Mahjong tile that also renders flower codes ('1f'..'8f').
Widget anyTile(String code,
    {double width = 36,
    bool faceDown = false,
    bool selected = false,
    bool highlight = false,
    bool dim = false,
    bool sideways = false,
    VoidCallback? onTap,
    String? badge}) {
  if (!faceDown && isFlowerCode(code)) return FlowerTile(code, width: width, highlight: highlight, sideways: sideways);
  return MahjongTile(code,
      width: width,
      faceDown: faceDown,
      selected: selected,
      highlight: highlight,
      dim: dim,
      sideways: sideways,
      onTap: onTap,
      badge: badge);
}

// ---------------------------------------------------------------------------
// code helpers

const suitLabels = ['万', '筒', '条'];
const honorLabels = ['东', '南', '西', '北', '白', '发', '中'];
const windLabels = ['东', '南', '西', '北'];

int codeOrder(String c) {
  if (c.length != 2) return 999;
  final n = int.tryParse(c[0]) ?? 0;
  switch (c[1]) {
    case 'm':
      return n;
    case 'p':
      return 10 + n;
    case 's':
      return 20 + n;
    case 'z':
      return 30 + n;
    case 'f':
      return 40 + n;
  }
  return 999;
}

List<String> sortCodes(Iterable<String> codes) => codes.toList()..sort((a, b) => codeOrder(a).compareTo(codeOrder(b)));

String tileLabel(String c) {
  if (c.length != 2) return '?';
  final n = int.tryParse(c[0]) ?? 1;
  switch (c[1]) {
    case 'm':
    case 'p':
    case 's':
      return '${'一二三四五六七八九'[n - 1]}${suitLabels['mps'.indexOf(c[1])]}';
    case 'z':
      return honorLabels[n - 1];
    case 'f':
      return flowerChars[n - 1];
  }
  return '?';
}
