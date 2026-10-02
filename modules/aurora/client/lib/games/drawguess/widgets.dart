import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Small pieces of the 你画我猜 board (player list, feed, hint line).

const kDgPalette = <int>[
  0xFF212121, 0xFF9E9E9E, 0xFFE53935, 0xFFFB8C00, 0xFFFDD835,
  0xFF43A047, 0xFF00ACC1, 0xFF1E88E5, 0xFF8E24AA, 0xFF795548,
];
const kDgWidths = <int>[4, 8, 16, 28];

int dgInt(Object? o, [int d = -1]) => o is num ? o.toInt() : d;
List<int> dgInts(Object? o) => o is List ? [for (final e in o) dgInt(e)] : <int>[];

/// "_ 熊 _ （3个字，动物）"
String dgHintText(Map<String, dynamic>? h) {
  if (h == null) return '';
  if (h['on'] != true) return '提示已关闭';
  final len = dgInt(h['len'], 0);
  final chars = h['chars'] is List ? h['chars'] as List : const [];
  final masked = [for (var i = 0; i < len; i++) i < chars.length && chars[i] is String ? chars[i] as String : '_'].join(' ');
  final cat = h['catShown'] == true ? (h['cat'] as String? ?? '') : '';
  return '$masked （$len个字${cat.isNotEmpty ? '，$cat' : ''}）';
}

class DgBadge extends StatelessWidget {
  final String text;
  final Color color;
  const DgBadge(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
      );
}

/// Player chips: score, guessed ✓, drawer ✎, GM badge.
class DgPlayers extends StatelessWidget {
  final GameContext g;
  final bool compact;
  const DgPlayers(this.g, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final scores = dgInts(v['scores']);
    final guessed = (v['guessed'] as List? ?? const []).map((e) => e == true).toList();
    final gm = dgInt(v['gm']);
    final drawer = dgInt(v['drawer']);
    final phase = v['phase'] as String? ?? '';
    final order = [for (var s = 0; s < g.players; s++) s]
      ..sort((a, b) {
        if (a == gm) return 1;
        if (b == gm) return -1;
        final sa = a < scores.length ? scores[a] : 0, sb = b < scores.length ? scores[b] : 0;
        return sb != sa ? sb - sa : a - b;
      });
    final chips = <Widget>[];
    for (final s in order) {
      final badges = <Widget>[
        if (s == gm) DgBadge('GM', Colors.amber.shade800),
        if (s == drawer && s != gm && phase != 'over') DgBadge('画手', Colors.deepPurple),
        if (s < guessed.length && guessed[s]) DgBadge('✓', Colors.green.shade600),
      ];
      final sub = s == gm ? '出题人' : '${s < scores.length ? scores[s] : 0} 分';
      chips.add(g.tag(
        s,
        active: s == drawer && phase != 'over' && phase != 'reveal',
        sub: sub,
        size: compact ? 26 : 32,
        trailing: badges.isEmpty ? null : Column(mainAxisSize: MainAxisSize.min, children: [
          for (final b in badges) Padding(padding: const EdgeInsets.symmetric(vertical: 1), child: b),
        ]),
      ));
    }
    if (compact) {
      return SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Center(child: chips[i]),
        ),
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}

/// Guess feed (newest at the bottom).
class DgFeed extends StatelessWidget {
  final GameContext g;
  const DgFeed(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final feed = (g.view['feed'] as List? ?? const []).whereType<Map>().toList();
    if (feed.isEmpty) {
      return Center(
        child: Text('猜测会显示在这里', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13)),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: feed.length,
      itemBuilder: (_, i) {
        final e = feed[feed.length - 1 - i];
        final s = dgInt(e['s']);
        final t = e['t'] as String?;
        final k = e['k'] as String? ?? 'guess';
        final who = g.name(s);
        Widget line;
        switch (k) {
          case 'right':
            line = Text.rich(TextSpan(children: [
              TextSpan(text: '$who 猜对了！', style: TextStyle(color: Colors.green.shade600, fontWeight: FontWeight.bold)),
              if (e['pts'] != null) TextSpan(text: ' +${e['pts']}', style: TextStyle(color: Colors.green.shade600)),
              if (t != null) TextSpan(text: '（$t）', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            ]));
          case 'close':
            line = Text.rich(TextSpan(children: [
              TextSpan(text: '$who 很接近了', style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold)),
              if (t != null) TextSpan(text: '（$t）', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            ]));
          default:
            line = Text.rich(TextSpan(children: [
              TextSpan(text: '$who：', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
              TextSpan(text: t ?? ''),
            ]));
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13), child: line),
        );
      },
    );
  }
}

/// A rounded translucent card used for overlays on the canvas.
class DgCard extends StatelessWidget {
  final Widget child;
  const DgCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withValues(alpha: 0.6), width: 1.5),
            boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
          ),
          child: child,
        ),
      ),
    );
  }
}
