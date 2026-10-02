import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

Color _ntColor(int c) => HSLColor.fromAHSL(1, (c.clamp(3, 35) - 3) / 32 * 300, 0.65, 0.45).toColor();

class NTCard extends StatelessWidget {
  final int card;
  final double width;
  final bool back;
  const NTCard(this.card, {super.key, this.width = 60, this.back = false});

  @override
  Widget build(BuildContext context) {
    final col = _ntColor(card);
    return Container(
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        gradient: back
            ? const LinearGradient(colors: [Color(0xFF37474F), Color(0xFF607D8B)])
            : LinearGradient(colors: [col, Color.lerp(col, Colors.white, 0.35)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(width * 0.12),
        border: Border.all(color: Colors.white, width: width * 0.05),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2))],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(width * 0.06),
          child: Text(back ? '?' : '$card',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: width * 0.5,
                  shadows: const [Shadow(color: Colors.black45, blurRadius: 3)])),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final double size;
  const _Chip({this.size = 18});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(colors: [Color(0xFFFFE082), Color(0xFFFFA000)]),
          border: Border.all(color: const Color(0xFFB26A00), width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))],
        ),
      );
}

class NoThanksBoard extends StatelessWidget {
  final GameContext g;
  const NoThanksBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final turn = lInt(v['turn']);
    final current = lInt(v['current'], -1);
    final pot = lInt(v['pot']);
    final chips = lInts(v['chips']);
    final cards = [for (final c in lList<List>(v['cards'])) lInts(c)];
    final points = lInts(v['points']);
    final total = lInts(v['total']);
    final over = v['over'] == true;
    final me = lMe(g, n);
    final myTurn = me && !over && turn == g.seat && !g.replay;
    final last = v['last'] == null ? null : lMap(v['last']);

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn) {
      status = (chips.elementAtOrNull(g.seat) ?? 0) > 0 ? '轮到你：拿走 $current，还是放 1 枚筹码说“不要”？' : '你没有筹码了，只能拿走 $current';
    } else {
      status = '等待 ${g.name(turn)} 决定';
    }

    Widget runs(List<int> cs0, double w) {
      final sorted = List.of(cs0)..sort();
      final groups = <List<int>>[];
      for (final c in sorted) {
        if (groups.isNotEmpty && groups.last.last == c - 1) {
          groups.last.add(c);
        } else {
          groups.add([c]);
        }
      }
      if (groups.isEmpty) return Text('（还没有牌）', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)));
      return Wrap(spacing: 6, runSpacing: 4, children: [
        for (final gr in groups)
          SizedBox(
            width: w + (gr.length - 1) * w * 0.35,
            height: w * 1.4,
            child: Stack(children: [
              for (var i = 0; i < gr.length; i++)
                Positioned(left: i * w * 0.35, child: Opacity(opacity: i == 0 ? 1 : 0.85, child: NTCard(gr[i], width: w))),
            ]),
          ),
      ]);
    }

    Widget seat(int s, double w) {
      final active = !over && s == turn;
      return LPanel(
        highlight: active,
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(child: g.tag(s, size: 28, active: active, sub: '牌面 ${points.elementAtOrNull(s) ?? 0} · 净分 ${total.elementAtOrNull(s) ?? 0}')),
            const SizedBox(width: 6),
            const _Chip(size: 16),
            const SizedBox(width: 2),
            Text('${chips.elementAtOrNull(s) ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          runs(cards.elementAtOrNull(s) ?? const [], w),
        ]),
      );
    }

    Widget? result;
    if (over && total.isNotEmpty) {
      final best = total.reduce((a, b) => a < b ? a : b);
      final ranked = [for (var s = 0; s < n; s++) s]..sort((a, b) => total[a].compareTo(total[b]));
      result = ResultBanner('${[for (var s = 0; s < n; s++) if (total[s] == best) g.name(s)].join('、')} 以 $best 分获胜！',
          child: Text([for (final s in ranked) '${g.name(s)} ${total[s]}'].join('  '), textAlign: TextAlign.center));
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final others = lOthers(g, n);
      final center = LPanel(
        color: g.table.withValues(alpha: 0.9),
        padding: const EdgeInsets.all(12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            NTCard(0, width: 40, back: true),
            const SizedBox(height: 4),
            Text('牌堆 ${lInt(v['deck'])}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            Text('移除 ${lInt(v['removed'])} 张', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const SizedBox(width: 16),
          if (current > 0)
            TweenAnimationBuilder<double>(
              key: ValueKey(current),
              tween: Tween(begin: 0.6, end: 1),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              builder: (_, t, child) => Transform.scale(scale: t, child: child),
              child: NTCard(current, width: wide ? 96 : 80),
            )
          else
            const SizedBox(width: 80, height: 112),
          const SizedBox(width: 16),
          Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 64,
              child: Wrap(spacing: 2, runSpacing: 2, alignment: WrapAlignment.center, children: [
                for (var i = 0; i < (pot > 15 ? 15 : pot); i++) const _Chip(size: 14),
              ]),
            ),
            const SizedBox(height: 4),
            Text('筹码 $pot', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ]),
      );
      final sw = wide ? 300.0 : (c.maxWidth - 24) / 2;
      return LFrame(
        status: status,
        highlight: myTurn,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final s in others) SizedBox(width: sw, child: seat(s, 26)),
          ]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: center),
          if (last != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                last['type'] == 'take'
                    ? '${g.name(lInt(last['seat']))} 拿走了 ${lInt(last['card'])}（+${lInt(last['pot'])} 筹码）'
                    : '${g.name(lInt(last['seat']))} 说“不要”',
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8)),
              ),
            ),
          const SizedBox(height: 8),
          if (myTurn)
            Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton.icon(
                onPressed: () => g.act({'type': 'take'}),
                icon: const Icon(Icons.pan_tool_alt),
                label: Text('拿走（+$pot 筹码）'),
              ),
              OutlinedButton.icon(
                onPressed: (chips.elementAtOrNull(g.seat) ?? 0) > 0 ? () => g.act({'type': 'pass'}) : null,
                icon: const Icon(Icons.block),
                label: const Text('不要（付 1 筹码）'),
              ),
            ]),
          if (me) ...[const SizedBox(height: 8), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: seat(g.seat, wide ? 40 : 32))],
        ],
      );
    });
  }
}
