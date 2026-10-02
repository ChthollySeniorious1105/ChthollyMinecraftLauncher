import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import '../../widgets/pieces.dart';

/// Strip engine prefixes: 'W' = wildcard (百搭), 'G' = transparent (明镜).
({String code, bool wild, bool glass}) parseCode(String raw) {
  var c = raw;
  var wild = false, glass = false;
  if (c.startsWith('W')) {
    wild = true;
    c = c.substring(1);
  }
  if (c.startsWith('G')) {
    glass = true;
    c = c.substring(1);
  }
  return (code: c, wild: wild, glass: glass);
}

/// Mahjong tile with riichi-specific decorations (wildcard / glass / badges).
class RTile extends StatelessWidget {
  final String code;
  final double width;
  final bool sideways;
  final bool selected;
  final bool highlight;
  final bool dim;
  final bool glass;
  final String? badge;
  final VoidCallback? onTap;
  const RTile(this.code,
      {super.key,
      required this.width,
      this.sideways = false,
      this.selected = false,
      this.highlight = false,
      this.dim = false,
      this.glass = false,
      this.badge,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = parseCode(code);
    if (p.wild && p.code.isEmpty) {
      // 万象修罗 百搭牌: its own tile, not a relabelled real tile
      Widget t = WildTile(width: width, sideways: sideways); // never dimmed: it is not meant to be discarded
      if (selected) t = Transform.translate(offset: Offset(0, -width * 0.35), child: t);
      if (onTap == null) return t;
      return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: t));
    }
    final isBack = p.code == 'back' || p.code.isEmpty;
    final isGlass = glass || p.glass;
    Widget t = MahjongTile(
      isBack ? 'back' : p.code,
      width: width,
      faceDown: isBack,
      sideways: sideways,
      highlight: highlight || p.wild,
      dim: dim,
      badge: badge ?? (p.wild ? '百搭' : null),
    );
    if (p.wild) {
      t = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.8), blurRadius: width * 0.25)],
        ),
        child: t,
      );
    }
    if (isGlass) {
      t = Stack(children: [
        Opacity(opacity: 0.88, child: t),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * 0.1),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.lightBlueAccent.withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.cyanAccent.withValues(alpha: 0.22),
                  ],
                ),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.8), width: 1),
              ),
            ),
          ),
        ),
      ]);
    }
    if (selected) t = Transform.translate(offset: Offset(0, -width * 0.35), child: t);
    if (onTap == null) return t;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: t));
  }
}

/// A called meld (吃/碰/杠) laid out horizontally with the called tile sideways.
class MeldView extends StatelessWidget {
  final Map meld;
  final int owner;
  final int players;
  final double width;
  const MeldView(this.meld, {super.key, required this.owner, required this.players, required this.width});

  @override
  Widget build(BuildContext context) {
    final type = meld['type'] as String;
    final tiles = (meld['tiles'] as List).cast<String>();
    final called = meld['called'] as String?;
    final from = (meld['from'] as num?)?.toInt() ?? -1;
    if (type == 'ankan') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 4; i++) RTile(i == 0 || i == 3 ? 'back' : tiles[i], width: width),
      ]);
    }
    final rel = (from - owner + players) % players;
    // 上家 -> left, 对家 -> middle, 下家 -> right
    final rest = List<String>.of(tiles);
    if (called != null) rest.remove(called);
    String? added;
    if (type == 'kakan' && rest.isNotEmpty) added = rest.removeLast();
    final count = rest.length + 1;
    // 上家 -> leftmost, 下家 -> rightmost, 对家 -> second
    final pos = rel == players - 1 ? 0 : (rel == 1 ? count - 1 : 1);
    Widget calledW = RTile(called ?? 'back', width: width, sideways: true);
    if (added != null) {
      calledW = Column(mainAxisSize: MainAxisSize.min, children: [
        RTile(added, width: width, sideways: true),
        calledW,
      ]);
    }
    final children = <Widget>[for (final c in rest) RTile(c, width: width)];
    children.insert(pos.clamp(0, children.length), calledW);
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: children);
  }
}

/// Discard river: two rows of 6, then the rest in a third row.
class RiverView extends StatelessWidget {
  final List river;
  final double width;
  final bool lastHighlight;

  /// Changes per discard; the newest tile plays a fly-in animation when set.
  final Object? flyKey;
  const RiverView(this.river, {super.key, required this.width, this.lastHighlight = false, this.flyKey});

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[[], [], []];
    for (var i = 0; i < river.length; i++) {
      final d = river[i] as Map;
      final row = i < 6 ? 0 : (i < 12 ? 1 : 2);
      final c = d['c'] as String;
      String? badge;
      if (d['lock'] == true) {
        badge = '锁';
      } else if (d['dark'] == true) {
        badge = '暗';
      } else if (d['ron'] == true) {
        badge = '和';
      }
      Widget t = RTile(
        c,
        width: width,
        sideways: d['side'] == true,
        highlight: lastHighlight && i == river.length - 1,
        dim: d['dark'] == true && c != 'back',
        badge: badge,
      );
      if (c != 'back') t = mjGiri(t, d, width);
      if (flyKey != null && i == river.length - 1) {
        t = MjDiscardFly(key: ValueKey(flyKey), highlight: false, child: t);
      }
      rows[row].add(t);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          if (r.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: width * 0.04),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: r),
            ),
      ],
    );
  }
}

/// Riichi stick (1000 点棒).
class RiichiStick extends StatelessWidget {
  final double length;
  const RiichiStick({super.key, required this.length});
  @override
  Widget build(BuildContext context) => Container(
        width: length,
        height: length * 0.12,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(length),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)],
        ),
        alignment: Alignment.center,
        child: Container(
          width: length * 0.1,
          height: length * 0.1,
          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
        ),
      );
}

/// The 百搭 tile face: ivory tile with a golden rainbow "百搭" emblem.
class WildTile extends StatelessWidget {
  final double width;
  final bool dim;
  final bool sideways;
  const WildTile({super.key, required this.width, this.dim = false, this.sideways = false});

  @override
  Widget build(BuildContext context) {
    final h = width * 4 / 3;
    Widget t = Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF0), Color(0xFFF3E6C8)],
        ),
        border: Border.all(color: const Color(0xFFB8860B), width: max(1, width * 0.04)),
        boxShadow: [
          BoxShadow(color: Colors.amber.withValues(alpha: 0.85), blurRadius: width * 0.28),
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 2, offset: const Offset(1, 2)),
        ],
      ),
      child: Stack(children: [
        Center(
          child: Container(
            width: width * 0.78,
            height: width * 0.78,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(colors: [
                Color(0xFFFF5252), Color(0xFFFFC107), Color(0xFF66BB6A),
                Color(0xFF29B6F6), Color(0xFFAB47BC), Color(0xFFFF5252),
              ]),
            ),
            alignment: Alignment.center,
            child: Container(
              width: width * 0.62,
              height: width * 0.62,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFF8E1)),
              alignment: Alignment.center,
              child: FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(width * 0.04),
                  child: Text('百\n搭',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: width * 0.3,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFB71C1C),
                        fontFamilyFallback: kFontFallback,
                      )),
                ),
              ),
            ),
          ),
        ),
        if (dim) Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(width * 0.12)))),
      ]),
    );
    if (sideways) t = RotatedBox(quarterTurns: 1, child: t);
    return t;
  }
}
