import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

/// A Skull disc: null = face down, true = skull, false = rose.
class SkullDisc extends StatelessWidget {
  final bool? skull;
  final double size;
  final bool highlight;
  final VoidCallback? onTap;
  const SkullDisc(this.skull, {super.key, this.size = 44, this.highlight = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final face = skull == null
        ? const [Color(0xFF4E342E), Color(0xFF8D6E63)]
        : (skull! ? const [Color(0xFF212121), Color(0xFF616161)] : const [Color(0xFFAD1457), Color(0xFFF06292)]);
    Widget w = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [face[1], face[0]]),
        border: Border.all(color: highlight ? Colors.amber : const Color(0xFFD7CCC8), width: highlight ? 3 : size * 0.06),
        boxShadow: [BoxShadow(color: highlight ? Colors.amber : Colors.black45, blurRadius: highlight ? 10 : 3, offset: const Offset(1, 2))],
      ),
      alignment: Alignment.center,
      child: skull == null
          ? Icon(Icons.blur_circular, color: Colors.white24, size: size * 0.6)
          : Text(skull! ? '💀' : '🌹', style: TextStyle(fontSize: size * 0.5, fontFamilyFallback: kFontFallback)),
    );
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class SkullBoard extends StatefulWidget {
  final GameContext g;
  const SkullBoard(this.g, {super.key});
  @override
  State<SkullBoard> createState() => _SkullBoardState();
}

class _SkullBoardState extends State<SkullBoard> {
  int bidN = 0;

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final phase = v['phase'] as String? ?? 'place';
    final turn = lInt(v['turn']);
    final bid = lInt(v['bid']);
    final bidder = lInt(v['bidder'], -1);
    final challenger = lInt(v['challenger'], -1);
    final onTable = lInt(v['onTable']);
    final points = lInts(v['points']);
    final discs = lInts(v['discs']);
    final alive = lBools(v['alive']);
    final folded = lBools(v['folded']);
    final matCounts = lInts(v['matCounts']);
    final matFlipped = [for (final m in lList<List>(v['matFlipped'])) lBools(m)];
    final myMat = lBools(v['myMat']);
    final handRoses = lInt(v['handRoses']);
    final handSkull = v['handSkull'] == true;
    final me = lMe(g, n);
    final act = me && !g.replay && phase != 'over';
    final myPlace = act && phase == 'place' && myMat.isEmpty && (alive.elementAtOrNull(g.seat) ?? false);
    final myTurn = act && (phase == 'turn' || phase == 'bid') && turn == g.seat;
    final myFlip = act && phase == 'flip' && challenger == g.seat;
    final myDiscard = act && phase == 'discard' && challenger == g.seat;
    final lastFlip = v['lastFlip'] == null ? null : lMap(v['lastFlip']);
    final minBid = bid + 1;
    if (bidN < minBid || bidN > onTable) bidN = minBid;

    String status;
    switch (phase) {
      case 'over':
        status = '游戏结束';
      case 'place':
        status = myPlace ? '放下第一张圆牌（面朝下）' : '等待所有人放下第一张圆牌';
      case 'turn':
        status = myTurn ? '轮到你：再放一张，或发起挑战' : '等待 ${g.name(turn)} 行动';
      case 'bid':
        status = myTurn ? '当前出价 $bid（${g.name(bidder)}）：加注或放弃' : '竞价中：${g.name(bidder)} 出价 $bid，等待 ${g.name(turn)}';
      case 'flip':
        status = myFlip ? '点选别人的垫子翻牌（已翻 ${lInt(v['flips'])}/$bid）' : '${g.name(challenger)} 正在翻牌（${lInt(v['flips'])}/$bid）';
      case 'discard':
        status = myDiscard ? '你翻到了自己的骷髅：选择丢弃一张圆牌' : '${g.name(challenger)} 翻到了自己的骷髅，正在选择丢弃';
      case 'roundEnd':
        final r = lMap(v['result']);
        status = r['type'] == 'success' ? '${g.name(lInt(r['seat']))} 挑战成功！' : '${g.name(lInt(r['seat']))} 挑战失败';
      default:
        status = '';
    }

    Widget mat(int s, double ds) {
      final dead = !(alive.elementAtOrNull(s) ?? true);
      final cnt = matCounts.elementAtOrNull(s) ?? 0;
      final fl = matFlipped.elementAtOrNull(s) ?? const <bool>[];
      final isMe = s == g.seat;
      final flippable = myFlip && s != g.seat && fl.length < cnt;
      final active = !g.over &&
          ((phase == 'place' && cnt == 0 && !dead) || ((phase == 'turn' || phase == 'bid') && s == turn) || ((phase == 'flip' || phase == 'discard') && s == challenger));
      final pts = points.elementAtOrNull(s) ?? 0;
      // discs from bottom to top; flipped ones are the top [fl.length]
      final unflipped = cnt - fl.length;
      return GestureDetector(
        onTap: flippable ? () => g.act({'type': 'flip', 'target': s}) : null,
        child: MouseRegion(
          cursor: flippable ? SystemMouseCursors.click : MouseCursor.defer,
          child: LPanel(
            highlight: active || flippable,
            padding: const EdgeInsets.all(6),
            color: dead ? cs.surface.withValues(alpha: 0.4) : (flippable ? cs.primaryContainer.withValues(alpha: 0.85) : null),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(
                  child: g.tag(s,
                      size: 26,
                      active: active,
                      sub: dead
                          ? '已出局'
                          : '圆牌 ${discs.elementAtOrNull(s) ?? 0}${(folded.elementAtOrNull(s) ?? false) ? ' · 放弃' : ''}${s == bidder && phase == 'bid' ? ' · 出价 $bid' : ''}'),
                ),
                for (var i = 0; i < 2; i++)
                  Icon(i < pts ? Icons.emoji_events : Icons.emoji_events_outlined, size: 18, color: i < pts ? Colors.amber : cs.outline),
              ]),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: pts > 0 ? const Color(0xFF8D6E63).withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ds),
                ),
                child: SizedBox(
                  height: ds + 6,
                  child: cnt == 0
                      ? Center(child: Text(dead ? '' : '（空垫子）', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))))
                      : ListView(scrollDirection: Axis.horizontal, shrinkWrap: true, children: [
                          for (var i = 0; i < unflipped; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: SkullDisc(isMe && i < myMat.length ? myMat[i] : null,
                                  size: ds, highlight: flippable && i == unflipped - 1),
                            ),
                          for (var i = fl.length - 1; i >= 0; i--)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: SkullDisc(fl[i], size: ds, highlight: lastFlip != null && lInt(lastFlip['seat']) == s && i == fl.length - 1),
                            ),
                        ]),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    List<Widget> bidControls() {
      if (minBid > onTable) return const [];
      return [
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: bidN > minBid ? () => setState(() => bidN--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$bidN', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          IconButton(onPressed: bidN < onTable ? () => setState(() => bidN++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        FilledButton.tonalIcon(
          onPressed: () => g.act({'type': 'bid', 'n': bidN}),
          icon: const Icon(Icons.campaign),
          label: Text(phase == 'bid' ? '加注到 $bidN' : '挑战：翻 $bidN 张'),
        ),
      ];
    }

    List<Widget> controls() {
      if (myPlace || (myTurn && phase == 'turn')) {
        final canPlace = handRoses > 0 || handSkull;
        return [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canPlace) ...[
              FilledButton.icon(
                onPressed: handRoses > 0 ? () => g.act({'type': 'place', 'skull': false}) : null,
                icon: const Text('🌹', style: TextStyle(fontFamilyFallback: kFontFallback)),
                label: Text('放玫瑰（$handRoses）'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                onPressed: handSkull ? () => g.act({'type': 'place', 'skull': true}) : null,
                icon: const Text('💀', style: TextStyle(fontFamilyFallback: kFontFallback)),
                label: const Text('放骷髅'),
              ),
            ],
            if (!myPlace) ...bidControls(),
          ]),
        ];
      }
      if (myTurn && phase == 'bid') {
        return [
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ...bidControls(),
            OutlinedButton(onPressed: () => g.act({'type': 'fold'}), child: const Text('放弃')),
          ]),
        ];
      }
      if (myDiscard) {
        return [
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => g.act({'type': 'discard', 'skull': false}), child: const Text('丢弃一朵玫瑰')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white),
                onPressed: () => g.act({'type': 'discard', 'skull': true}),
                child: const Text('丢弃骷髅')),
          ]),
        ];
      }
      return const [];
    }

    Widget? result;
    final r = v['result'] == null ? null : lMap(v['result']);
    if (phase == 'over') {
      final w = lInt(v['winner'], -1);
      result = ResultBanner(w >= 0 ? '${g.name(w)} 获胜！' : '游戏结束',
          child: Text([for (var s = 0; s < n; s++) '${g.name(s)} ${points.elementAtOrNull(s) ?? 0}分'].join('  ')));
    } else if (phase == 'roundEnd' && r != null) {
      final ok = r['type'] == 'success';
      final lost = r['lostSkull'];
      result = ResultBanner(ok ? '${g.name(lInt(r['seat']))} 挑战 ${lInt(r['bid'])} 成功！' : '${g.name(lInt(r['seat']))} 翻到了 ${g.name(lInt(r['owner']))} 的骷髅',
          child: Text(ok ? '获得 1 分' : (lost == null ? '失去 1 张圆牌' : '你失去了 ${lost == true ? '骷髅' : '一朵玫瑰'}')));
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final others = lOthers(g, n);
      final sw = wide ? 270.0 : (c.maxWidth - 24) / 2;
      final ds = wide ? 38.0 : 28.0;
      return LFrame(
        status: status,
        highlight: myPlace || myTurn || myFlip || myDiscard,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            LChip('第 ${lInt(v['round'])} 轮', icon: Icons.flag),
            LChip('桌上 $onTable 张', icon: Icons.layers),
            if (bid > 0) LChip('出价 $bid · ${g.name(bidder)}', icon: Icons.campaign, color: Colors.deepOrange),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final s in others) SizedBox(width: sw, child: mat(s, ds)),
          ]),
          const SizedBox(height: 10),
          if (me) ...[
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: mat(g.seat, wide ? 46 : 38)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('手里：', style: TextStyle(fontSize: 12)),
              for (var i = 0; i < handRoses; i++) const Padding(padding: EdgeInsets.all(2), child: SkullDisc(false, size: 30)),
              if (handSkull) const Padding(padding: EdgeInsets.all(2), child: SkullDisc(true, size: 30)),
              if (handRoses == 0 && !handSkull) const Text('（没有）', style: TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 6),
          ],
          ...controls(),
        ],
      );
    });
  }
}
