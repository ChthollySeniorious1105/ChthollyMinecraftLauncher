import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

const _sushiInfo = {
  'tempura': ('天妇罗', '🍤', Color(0xFFBA68C8), '2张=5'),
  'sashimi': ('刺身', '🐟', Color(0xFF9CCC65), '3张=10'),
  'dumpling': ('饺子', '🥟', Color(0xFF4FC3F7), '1/3/6/10/15'),
  'maki1': ('卷寿司', '🍣', Color(0xFFE53935), '×1'),
  'maki2': ('卷寿司', '🍣', Color(0xFFE53935), '×2'),
  'maki3': ('卷寿司', '🍣', Color(0xFFE53935), '×3'),
  'salmon': ('三文鱼', '🍣', Color(0xFFFFB300), '2'),
  'squid': ('鱿鱼', '🦑', Color(0xFFFFB300), '3'),
  'egg': ('玉子', '🥚', Color(0xFFFFB300), '1'),
  'pudding': ('布丁', '🍮', Color(0xFFF48FB1), '终局±6'),
  'wasabi': ('芥末', '🟢', Color(0xFF7CB342), '下张握寿司×3'),
  'chopsticks': ('筷子', '🥢', Color(0xFF80CBC4), '一次拿2张'),
  'w_salmon': ('芥末三文鱼', '🍣', Color(0xFF689F38), '6'),
  'w_squid': ('芥末鱿鱼', '🦑', Color(0xFF689F38), '9'),
  'w_egg': ('芥末玉子', '🥚', Color(0xFF689F38), '3'),
};

class SushiCard extends StatelessWidget {
  final String card;
  final double width;
  final bool selected;
  final int badge;
  final VoidCallback? onTap;
  const SushiCard(this.card, {super.key, this.width = 60, this.selected = false, this.badge = 0, this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = _sushiInfo[card] ?? (card, '?', Colors.grey, '');
    final h = width * 1.4;
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.16 : 0, 0),
      decoration: BoxDecoration(
        color: info.$3,
        borderRadius: BorderRadius.circular(width * 0.14),
        border: Border.all(color: selected ? Colors.amber : Colors.white, width: selected ? 3 : width * 0.04),
        boxShadow: [BoxShadow(color: selected ? Colors.amber : Colors.black38, blurRadius: selected ? 10 : 3, offset: const Offset(1, 2))],
      ),
      padding: EdgeInsets.all(width * 0.05),
      child: Column(children: [
        SizedBox(
          height: h * 0.16,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(info.$1, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: width * 0.2, shadows: const [Shadow(color: Colors.black38, blurRadius: 2)])),
          ),
        ),
        Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(vertical: width * 0.03),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(width * 0.06),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(info.$2, style: TextStyle(fontSize: width * 0.34, fontFamilyFallback: kFontFallback)),
                  if (card.startsWith('maki'))
                    Text(card.substring(4), style: TextStyle(fontSize: width * 0.22, fontWeight: FontWeight.bold, color: info.$3)),
                ]),
              ),
            ),
          ),
        ),
        SizedBox(
          height: h * 0.13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(info.$4, style: TextStyle(color: Colors.white, fontSize: width * 0.16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
    if (badge > 1) {
      w = Stack(clipBehavior: Clip.none, children: [
        w,
        Positioned(
          right: -4,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: Text('×$badge', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ]);
    }
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class SushiGoBoard extends StatefulWidget {
  final GameContext g;
  const SushiGoBoard(this.g, {super.key});
  @override
  State<SushiGoBoard> createState() => _SushiGoBoardState();
}

class _SushiGoBoardState extends State<SushiGoBoard> {
  int sel = -1;
  int sel2 = -1;
  bool chop = false;
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final phase = v['phase'] as String? ?? 'pick';
    final hand = lList<String>(v['hand']);
    final tableau = [for (final t in lList<List>(v['tableau'])) t.whereType<String>().toList()];
    final picked = lBools(v['picked']);
    final score = lInts(v['score']);
    final pudding = lInts(v['pudding']);
    final maki = lInts(v['maki']);
    final live = lInts(v['live']);
    final me = lMe(g, n);
    final myPick = v['myPick'] == null ? null : lInts(v['myPick']);
    final canPick = me && phase == 'pick' && !g.replay && hand.isNotEmpty;
    final k = '${lInt(v['round'])}/${lInt(v['turn'])}/${hand.join(',')}';
    if (k != key) {
      key = k;
      sel = -1;
      sel2 = -1;
      chop = false;
    }
    final hasChop = me && (tableau.elementAtOrNull(g.seat) ?? const []).contains('chopsticks');

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'roundEnd') {
      status = '第 ${lInt(v['round'])} 轮计分';
    } else if (canPick && myPick == null) {
      status = '第 ${lInt(v['round'])}/3 轮：选一张寿司（所有人同时）';
    } else if (canPick) {
      status = '已选好，等待其他人…（可改选）';
    } else {
      status = '等待所有人选牌';
    }

    Widget tab(int s, double w) {
      final t = tableau.elementAtOrNull(s) ?? const <String>[];
      final counts = <String, int>{};
      for (final c in t) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
      return LPanel(
        highlight: phase == 'pick' && !(picked.elementAtOrNull(s) ?? true),
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(
              child: g.tag(s,
                  size: 26,
                  active: phase == 'pick' && !(picked.elementAtOrNull(s) ?? true),
                  sub: '总 ${score.elementAtOrNull(s) ?? 0} · 本轮 ${live.elementAtOrNull(s) ?? 0}'),
            ),
            const SizedBox(width: 4),
            Text('🍣${maki.elementAtOrNull(s) ?? 0} 🍮${pudding.elementAtOrNull(s) ?? 0}',
                style: const TextStyle(fontSize: 12, fontFamilyFallback: kFontFallback)),
            if (phase == 'pick') ...[
              const SizedBox(width: 4),
              Icon((picked.elementAtOrNull(s) ?? false) ? Icons.check_circle : Icons.hourglass_top,
                  size: 16, color: (picked.elementAtOrNull(s) ?? false) ? Colors.green : cs.outline),
            ],
          ]),
          const SizedBox(height: 4),
          if (counts.isEmpty)
            Text('（桌面为空）', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)))
          else
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final e in counts.entries) SushiCard(e.key, width: w, badge: e.value),
            ]),
        ]),
      );
    }

    Widget? result;
    final rr = v['roundResult'] == null ? null : lMap(v['roundResult']);
    if (rr != null) {
      final gained = lInts(rr['gained']);
      final mp = lInts(rr['makiPts']);
      final pp = rr['puddingPts'] == null ? null : lInts(rr['puddingPts']);
      final lines = [
        for (var s = 0; s < n; s++)
          '${g.name(s)} +${gained.elementAtOrNull(s) ?? 0}'
              '${(mp.elementAtOrNull(s) ?? 0) > 0 ? '（卷寿司 ${mp[s]}）' : ''}'
              '${pp != null && (pp.elementAtOrNull(s) ?? 0) != 0 ? ' 布丁 ${pp[s] > 0 ? '+' : ''}${pp[s]}' : ''}'
              ' = ${score.elementAtOrNull(s) ?? 0}'
      ];
      if (phase == 'over') {
        final best = score.reduce((a, b) => a > b ? a : b);
        result = ResultBanner('${[for (var s = 0; s < n; s++) if (score[s] == best) g.name(s)].join('、')} 以 $best 分获胜！',
            child: Text(lines.join('\n'), textAlign: TextAlign.center));
      } else {
        result = ResultBanner('第 ${lInt(rr['round'])} 轮计分', child: Text(lines.join('\n'), textAlign: TextAlign.center));
      }
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final hw = ((c.maxWidth.clamp(0, 900) - 20) / (hand.length.clamp(5, 10) + 0.8)).clamp(44.0, 84.0);
      final others = lOthers(g, n);
      final sw = wide ? 300.0 : c.maxWidth - 16;
      final ready = sel >= 0 && (!chop || sel2 >= 0);
      return LFrame(
        status: status,
        highlight: canPick && myPick == null,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            LChip('第 ${lInt(v['round'])}/3 轮', icon: Icons.flag),
            LChip('第 ${lInt(v['turn']) + (phase == 'pick' ? 1 : 0)} 手', icon: Icons.touch_app),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final s in others) SizedBox(width: sw, child: tab(s, wide ? 34 : 30)),
          ]),
          const SizedBox(height: 8),
          if (me) ConstrainedBox(constraints: const BoxConstraints(maxWidth: 700), child: tab(g.seat, wide ? 44 : 36)),
          const SizedBox(height: 10),
          if (me && hand.isNotEmpty) ...[
            Text('我的手牌（选完后传给下家 ${g.name((g.seat + 1) % n)}）', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(spacing: 5, runSpacing: 10, alignment: WrapAlignment.center, children: [
              for (var i = 0; i < hand.length; i++)
                SushiCard(hand[i],
                    width: hw,
                    selected: i == sel || i == sel2 || (sel < 0 && (myPick ?? const []).contains(i)),
                    onTap: canPick
                        ? () => setState(() {
                              if (chop && sel >= 0 && i != sel) {
                                sel2 = i == sel2 ? -1 : i;
                              } else {
                                sel = i;
                                if (sel2 == i) sel2 = -1;
                              }
                            })
                        : null),
            ]),
          ],
          if (canPick) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (hasChop && hand.length >= 2)
                FilterChip(
                  avatar: const Text('🥢', style: TextStyle(fontFamilyFallback: kFontFallback)),
                  label: const Text('用筷子拿两张'),
                  selected: chop,
                  onSelected: (b) => setState(() {
                    chop = b;
                    sel2 = -1;
                  }),
                ),
              FilledButton.icon(
                onPressed: ready ? () => g.act({'type': 'pick', 'card': sel, if (chop) 'second': sel2}) : null,
                icon: const Icon(Icons.check),
                label: Text(sel < 0 ? '点选一张牌' : (chop && sel2 < 0 ? '再选第二张' : '选这${chop ? '两' : ''}张')),
              ),
            ]),
          ],
        ],
      );
    });
  }
}
