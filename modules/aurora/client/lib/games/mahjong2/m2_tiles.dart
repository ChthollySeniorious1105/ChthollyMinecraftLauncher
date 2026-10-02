import 'package:flutter/material.dart';

import '../../widgets/pieces.dart';

const flowerChars = ['春', '夏', '秋', '冬', '梅', '兰', '竹', '菊'];
const _flowerColors = [
  Color(0xFF2E7D32),
  Color(0xFFC62828),
  Color(0xFFEF6C00),
  Color(0xFF1565C0),
  Color(0xFFAD1457),
  Color(0xFF6A1B9A),
  Color(0xFF00695C),
  Color(0xFFF9A825),
];

bool isFlowerCode(String c) => c.length == 2 && c[1] == 'f';

/// Flower tile (春夏秋冬梅兰竹菊) drawn in code (no PNG asset exists).
class M2FlowerTile extends StatelessWidget {
  final String code;
  final double width;
  final bool highlight;
  const M2FlowerTile(this.code, {super.key, this.width = 36, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final i = ((int.tryParse(code[0]) ?? 1) - 1).clamp(0, 7);
    final color = _flowerColors[i];
    return Container(
      width: width,
      height: width * 4 / 3,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFDF4), Color(0xFFF1E8D2)],
        ),
        borderRadius: BorderRadius.circular(width * 0.1),
        border: Border.all(color: highlight ? Colors.amber : const Color(0xFFD9CFB6), width: highlight ? 2 : width * 0.03),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 2, offset: const Offset(1, 2))],
      ),
      padding: EdgeInsets.all(width * 0.06),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i < 4 ? Icons.wb_sunny_outlined : Icons.local_florist, size: width * 0.34, color: color.withValues(alpha: 0.8)),
            Text(flowerChars[i], style: TextStyle(fontSize: width * 0.46, color: color, fontWeight: FontWeight.w900, height: 1.05)),
          ]),
        ),
      ),
    );
  }
}

/// Mahjong tile that also renders flower codes ('1f'..'8f').
Widget m2Tile(String code,
    {double width = 36, bool faceDown = false, bool highlight = false, bool dim = false, bool sideways = false, String? badge}) {
  if (!faceDown && isFlowerCode(code)) return M2FlowerTile(code, width: width, highlight: highlight);
  return MahjongTile(code, width: width, faceDown: faceDown, highlight: highlight, dim: dim, sideways: sideways, badge: badge);
}

const suitLabels = ['万', '筒', '条'];
const honorLabels = ['东', '南', '西', '北', '白', '发', '中'];
const windLabels = ['东', '南', '西', '北'];

List<String> codesOf(Object? l) => l is List ? [for (final e in l) '$e'] : <String>[];

int codeOrder(String c) {
  if (c.length != 2) return 999;
  final n = int.tryParse(c[0]) ?? 0;
  return switch (c[1]) { 'm' => n, 'p' => 10 + n, 's' => 20 + n, 'z' => 30 + n, 'f' => 40 + n, _ => 999 };
}

List<String> sortCodes(Iterable<String> codes) => codes.toList()..sort((a, b) => codeOrder(a).compareTo(codeOrder(b)));

String tileLabel(String c) {
  if (c.length != 2) return '?';
  final n = (int.tryParse(c[0]) ?? 1).clamp(1, 9);
  return switch (c[1]) {
    'm' || 'p' || 's' => '${'一二三四五六七八九'[n - 1]}${suitLabels['mps'.indexOf(c[1])]}',
    'z' => honorLabels[(n - 1).clamp(0, 6)],
    'f' => flowerChars[(n - 1).clamp(0, 7)],
    _ => '?',
  };
}

/// A called meld; the claimed tile lies sideways. 开杠 melds get a small badge.
Widget m2Meld(Map m, double tw) {
  final kind = m['kind'] as String;
  final tiles = codesOf(m['tiles']);
  final claimed = m['claimed'] as String?;
  var claimedIdx = -1;
  if (claimed != null && kind != 'agang') claimedIdx = kind == 'chi' ? tiles.indexOf(claimed) : 1;
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: tw * 0.12),
    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < tiles.length; i++)
        m2Tile(tiles[i],
            width: tw,
            faceDown: tiles[i] == 'back' || (kind == 'agang' && (i == 0 || i == 3)),
            sideways: i == claimedIdx,
            badge: m['open'] == true && i == tiles.length - 1 ? '开' : null),
    ]),
  );
}

Widget flowerRow(List<String> fl, double tw) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (final f in fl) Padding(padding: EdgeInsets.only(right: tw * 0.05), child: M2FlowerTile(f, width: tw)),
    ]);
