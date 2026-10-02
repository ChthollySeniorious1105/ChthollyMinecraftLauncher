import 'package:flutter/material.dart';

import '../theme/themes.dart';

/// Mahjong tile codes used by every mahjong engine (see shared/lib/games/riichi):
///   "1m".."9m" 万, "1p".."9p" 筒, "1s".."9s" 索, "0m"/"0p"/"0s" red fives,
///   "1z".."7z" 东南西北白发中.
/// Anything else (e.g. "back", "") renders as a face-down tile.
String mahjongAsset(String code) {
  if (code.length != 2) return '${assetPrefix}assets/mahjong/Back.png';
  final n = code[0];
  final s = code[1];
  const suits = {'m': 'Man', 'p': 'Pin', 's': 'Sou'};
  if (suits.containsKey(s)) {
    if (n == '0') return '${assetPrefix}assets/mahjong/${suits[s]}5-Dora.png';
    return '${assetPrefix}assets/mahjong/${suits[s]}$n.png';
  }
  if (s == 'z') {
    const honors = ['Ton', 'Nan', 'Shaa', 'Pei', 'Haku', 'Hatsu', 'Chun'];
    final i = int.tryParse(n) ?? 0;
    if (i >= 1 && i <= 7) return '${assetPrefix}assets/mahjong/${honors[i - 1]}.png';
  }
  return '${assetPrefix}assets/mahjong/Back.png';
}

/// A mahjong tile (public-domain artwork by FluffyStuff, CC0).
class MahjongTile extends StatelessWidget {
  final String code;
  final double width;
  final bool faceDown;
  final bool selected;
  final bool highlight;
  final bool dim;

  /// Rotated 90° (e.g. riichi declaration tile, called tile in a meld).
  final bool sideways;
  final VoidCallback? onTap;
  final String? badge;
  const MahjongTile(this.code,
      {super.key,
      this.width = 36,
      this.faceDown = false,
      this.selected = false,
      this.highlight = false,
      this.dim = false,
      this.sideways = false,
      this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    final h = width * 4 / 3;
    // Each PNG is a pre-composited tile (face on ivory body), 150×200.
    Widget face = Stack(children: [
      Positioned.fill(
        child: Image.asset(faceDown ? '${assetPrefix}assets/mahjong/Back.png' : mahjongAsset(code),
            fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true),
      ),
      if (highlight)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(width * 0.1),
              border: Border.all(color: Colors.amber, width: 2),
            ),
          ),
        ),
      if (dim) Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.4))),
      if (badge != null)
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
            child: Text(badge!, style: TextStyle(fontSize: width * 0.28, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
    ]);
    face = SizedBox(width: width, height: h, child: face);
    if (sideways) face = RotatedBox(quarterTurns: 1, child: face);
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, selected ? -width * 0.35 : 0, 0),
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 2, offset: const Offset(1, 2))],
        borderRadius: BorderRadius.circular(width * 0.1),
      ),
      child: face,
    );
    if (onTap == null) return tile;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: tile));
  }
}

/// Standard playing card.
/// Codes: rank + suit, rank in "3".."9","T","J","Q","K","A","2"; suit in "S","H","D","C".
/// Jokers: "BJ" (小王), "RJ" (大王). Anything else = card back.
class PlayingCard extends StatelessWidget {
  final String code;
  final double width;
  final bool faceDown;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;
  const PlayingCard(this.code,
      {super.key, this.width = 48, this.faceDown = false, this.selected = false, this.dim = false, this.onTap});

  static const _suitSym = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    Widget content;
    if (faceDown || code.length < 2) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.1),
          gradient: const LinearGradient(colors: [Color(0xFF283593), Color(0xFF5C6BC0)]),
          border: Border.all(color: Colors.white, width: width * 0.05),
        ),
        child: Center(child: Icon(Icons.auto_awesome, color: Colors.white54, size: width * 0.5)),
      );
    } else if (code == 'BJ' || code == 'RJ') {
      final red = code == 'RJ';
      content = _face(
        FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('JOKER',
              style: TextStyle(
                  fontSize: width * 0.17, fontWeight: FontWeight.bold, color: red ? Colors.red : Colors.black87)),
          Icon(Icons.face_retouching_natural, size: width * 0.5, color: red ? Colors.red : Colors.black87),
          Text(red ? '大王' : '小王', style: TextStyle(fontSize: width * 0.2, color: red ? Colors.red : Colors.black87)),
        ])),
      );
    } else {
      final rank = code.substring(0, code.length - 1);
      final suit = code[code.length - 1];
      final red = suit == 'H' || suit == 'D';
      final color = red ? const Color(0xFFD32F2F) : Colors.black87;
      final r = rank == 'T' ? '10' : rank;
      content = _face(Stack(children: [
        Positioned(
          left: width * 0.07,
          top: width * 0.03,
          child: Column(children: [
            Text(r, style: TextStyle(fontSize: width * 0.3, fontWeight: FontWeight.bold, color: color, height: 1.1)),
            Text(_suitSym[suit] ?? '', style: TextStyle(fontSize: width * 0.24, color: color, height: 1)),
          ]),
        ),
        Center(child: Text(_suitSym[suit] ?? '', style: TextStyle(fontSize: width * 0.55, color: color))),
      ]));
    }
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.3 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 3, offset: const Offset(1, 2))],
        border: selected ? Border.all(color: Colors.amber, width: 2) : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(width * 0.1), child: content),
    );
    if (dim) card = Opacity(opacity: 0.5, child: card);
    if (onTap == null) return card;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
  }

  Widget _face(Widget child) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF7),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: Colors.black26),
        ),
        child: child,
      );
}

/// Lays out children as an overlapping fan (cards in hand). Overlap shrinks to fit width.
class OverlapRow extends StatelessWidget {
  final List<Widget> children;
  final double itemWidth;
  final double maxSpacing;
  final double minSpacing;
  const OverlapRow({super.key, required this.children, required this.itemWidth, this.maxSpacing = 1.05, this.minSpacing = 0.25});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = children.length;
      if (n == 0) return const SizedBox();
      final avail = c.maxWidth.isFinite ? c.maxWidth : n * itemWidth * maxSpacing;
      var step = n <= 1 ? itemWidth : (avail - itemWidth) / (n - 1);
      step = step.clamp(itemWidth * minSpacing, itemWidth * maxSpacing);
      final total = itemWidth + step * (n - 1);
      return SizedBox(
        width: total,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++) Positioned(left: step * i, bottom: 0, child: children[i]),
          // keep height from the first child
          Opacity(opacity: 0, child: IgnorePointer(child: children.first)),
        ]),
      );
    });
  }
}

/// Simple die face 1-6.
class DieFace extends StatelessWidget {
  final int value;
  final double size;
  final bool held;
  final VoidCallback? onTap;
  const DieFace(this.value, {super.key, this.size = 48, this.held = false, this.onTap});

  static const _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  Widget build(BuildContext context) {
    final pips = _pips[value] ?? const <int>[];
    final d = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: held ? Colors.amber.shade100 : Colors.white,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: held ? Colors.amber.shade800 : Colors.black26, width: held ? 3 : 1),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2))],
      ),
      child: GridView.count(
        crossAxisCount: 3,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 9; i++)
            Center(
              child: pips.contains(i)
                  ? Container(
                      width: size * 0.17,
                      height: size * 0.17,
                      decoration: BoxDecoration(
                          color: value == 1 ? Colors.red : Colors.black87, shape: BoxShape.circle),
                    )
                  : null,
            ),
        ],
      ),
    );
    if (onTap == null) return d;
    return GestureDetector(onTap: onTap, child: d);
  }
}
