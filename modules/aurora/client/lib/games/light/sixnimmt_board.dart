import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'lt_common.dart';

int _bulls(int c) {
  if (c == 55) return 7;
  if (c % 11 == 0) return 5;
  if (c % 10 == 0) return 3;
  if (c % 5 == 0) return 2;
  return 1;
}

Color _bullColor(int b) => switch (b) {
      7 => const Color(0xFF8E24AA),
      5 => const Color(0xFFD32F2F),
      3 => const Color(0xFFF57C00),
      2 => const Color(0xFF1E88E5),
      _ => const Color(0xFF43A047),
    };

/// A 6 nimmt! card. card <= 0 = face down.
class NimmtCard extends StatelessWidget {
  final int card;
  final double width;
  final bool selected;
  final bool highlight;
  final bool dim;
  final VoidCallback? onTap;
  const NimmtCard(this.card, {super.key, this.width = 48, this.selected = false, this.highlight = false, this.dim = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    Widget body;
    if (card <= 0) {
      body = Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF5D4037), Color(0xFF8D6E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: Colors.white70, width: 1.5),
        ),
        child: Center(child: Text('🐮', style: TextStyle(fontSize: width * 0.42, fontFamilyFallback: kFontFallback))),
      );
    } else {
      final b = _bulls(card);
      final col = _bullColor(b);
      body = Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF5),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: col, width: width * 0.05),
        ),
        padding: EdgeInsets.all(width * 0.05),
        child: Column(children: [
          SizedBox(
            height: h * 0.2,
            child: FittedBox(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < b; i++) Icon(Icons.pets, size: width * 0.2, color: col),
              ]),
            ),
          ),
          Expanded(
            child: Container(
              margin: EdgeInsets.symmetric(vertical: width * 0.02),
              decoration: BoxDecoration(
                color: col.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(width * 0.3),
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$card',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: width * 0.42, color: col, height: 1)),
              ),
            ),
          ),
          SizedBox(
            height: h * 0.12,
            child: FittedBox(child: Text('$b 🐮', style: TextStyle(fontSize: width * 0.2, color: col, fontFamilyFallback: kFontFallback))),
          ),
        ]),
      );
    }
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.18 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.12),
        boxShadow: [
          BoxShadow(
            color: selected || highlight ? Colors.amber : Colors.black38,
            blurRadius: selected || highlight ? 10 : 3,
            spreadRadius: highlight ? 1 : 0,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: body,
    );
    if (dim) w = Opacity(opacity: 0.45, child: w);
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class SixNimmtBoard extends StatefulWidget {
  final GameContext g;
  const SixNimmtBoard(this.g, {super.key});
  @override
  State<SixNimmtBoard> createState() => _SixNimmtBoardState();
}

class _SixNimmtBoardState extends State<SixNimmtBoard> {
  int sel = -1;

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = lInt(v['players'], g.players);
    final phase = v['phase'] as String? ?? 'choose';
    final rows = [for (final r in lList<List>(v['rows'])) lInts(r)];
    final hand = lInts(v['hand']);
    final chosen = lBools(v['chosen']);
    final myChoice = lInt(v['myChoice'], -1);
    final score = lInts(v['score']);
    final pen = lInts(v['roundPen']);
    final picker = lInt(v['picker'], -1);
    final me = lMe(g, n);
    final canAct = me && !g.replay && !g.over;
    final myChoose = canAct && phase == 'choose' && hand.isNotEmpty;
    final myPick = canAct && phase == 'pickRow' && picker == g.seat;
    if (!hand.contains(sel)) sel = -1;
    final pending = [for (final p in lList<Map>(v['pending'])) lMap(p)];
    final lastTurn = [for (final p in lList<Map>(phase == 'pickRow' ? v['turnSoFar'] : v['lastTurn'])) lMap(p)];
    final placedNow = {for (final p in lastTurn) lInt(p['card'])};
    final endMode = lInt(v['endMode'], 66);

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'roundEnd') {
      status = '第 ${lInt(v['round'])} 局结束，即将开始下一局';
    } else if (phase == 'pickRow') {
      status = myPick ? '你的牌最小：点选一列收走' : '${g.name(picker)} 的牌最小，正在选择要收走的一列';
    } else if (myChoose && myChoice <= 0) {
      status = '选一张牌出（所有人同时出牌）';
    } else if (myChoose) {
      status = '已选 $myChoice，等待其他人…（可改选）';
    } else {
      status = '等待所有人选牌';
    }

    Widget rowView(int r, double cw) {
      final row = r < rows.length ? rows[r] : <int>[];
      final bulls = row.fold(0, (a, c) => a + _bulls(c));
      final pickable = myPick;
      return GestureDetector(
        onTap: pickable ? () => g.act({'type': 'row', 'row': r}) : null,
        child: MouseRegion(
          cursor: pickable ? SystemMouseCursors.click : MouseCursor.defer,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: pickable ? cs.primary.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: pickable ? cs.primary : Colors.transparent, width: 2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 34,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${r + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('$bulls🐮', style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamilyFallback: kFontFallback)),
                ]),
              ),
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: i < row.length
                      ? NimmtCard(row[i], width: cw, highlight: placedNow.contains(row[i]))
                      : Container(
                          width: cw,
                          height: cw * 1.4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(cw * 0.12),
                            border: Border.all(
                                color: i == 5 ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white24, width: i == 5 ? 2 : 1),
                            color: i == 5 ? Colors.redAccent.withValues(alpha: 0.1) : null,
                          ),
                          child: i == 5
                              ? const Center(child: Icon(Icons.warning_amber, color: Colors.redAccent, size: 16))
                              : null,
                        ),
                ),
            ]),
          ),
        ),
      );
    }

    Widget playersStrip() => Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (var s = 0; s < n; s++)
            g.tag(
              s,
              size: 28,
              active: (phase == 'choose' && !chosen.elementAtOrNull(s).orFalse) || (phase == 'pickRow' && picker == s),
              sub: '${score.elementAtOrNull(s) ?? 0}🐮${(pen.elementAtOrNull(s) ?? 0) > 0 ? ' (+${pen[s]})' : ''}',
              trailing: phase == 'choose'
                  ? Icon(chosen.elementAtOrNull(s).orFalse ? Icons.check_circle : Icons.hourglass_top,
                      size: 16, color: chosen.elementAtOrNull(s).orFalse ? Colors.green : cs.outline)
                  : null,
            ),
        ]);

    Widget reveal() {
      final items = [...lastTurn, ...pending];
      if (items.isEmpty) return const SizedBox();
      return LPanel(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(phase == 'pickRow' ? '本轮亮牌：' : '上一轮：', style: const TextStyle(fontSize: 12)),
          for (final p in items)
            Row(mainAxisSize: MainAxisSize.min, children: [
              NimmtCard(lInt(p['card']), width: 26, highlight: pending.contains(p) && pending.first == p),
              const SizedBox(width: 3),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(g.name(lInt(p['seat'])), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                if (lInt(p['bulls']) > 0)
                  Text('收 ${lInt(p['bulls'])}🐮', style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontFamilyFallback: kFontFallback))
                else if (p.containsKey('row'))
                  Text('→ 第 ${lInt(p['row']) + 1} 列', style: const TextStyle(fontSize: 11))
                else
                  const Text('待放置', style: TextStyle(fontSize: 11)),
              ]),
            ]),
        ]),
      );
    }

    Widget? result;
    final rr = v['roundResult'] == null ? null : lMap(v['roundResult']);
    if (phase == 'over') {
      final best = score.isEmpty ? 0 : score.reduce((a, b) => a < b ? a : b);
      final winners = [for (var s = 0; s < n; s++) if (score[s] == best) g.name(s)];
      final res = lInt(v['resigned'], -1);
      result = ResultBanner(res >= 0 ? '${g.name(res)} 认输' : '${winners.join('、')} 获胜！',
          child: Text([for (var s = 0; s < n; s++) '${g.name(s)} ${score[s]}🐮'].join('  '),
              textAlign: TextAlign.center, style: const TextStyle(fontFamilyFallback: kFontFallback)));
    } else if (rr != null) {
      final p = lInts(rr['pen']);
      result = ResultBanner('第 ${lInt(rr['round'])} 局结束',
          child: Text([for (var s = 0; s < n; s++) '${g.name(s)} +${p.elementAtOrNull(s) ?? 0}'].join('  '), textAlign: TextAlign.center));
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final side = c.maxWidth > 980;
      final hLimit = c.maxHeight.isFinite ? ((c.maxHeight - (side ? 250 : 330)) / 4 / 1.52) : 64.0;
      final cw = ((c.maxWidth.clamp(0, side ? 620 : 760) - 60) / 6.4).clamp(34.0, wide ? 64.0 : 58.0).clamp(30.0, hLimit < 34 ? 34.0 : hLimit);
      final hw = ((c.maxWidth.clamp(0, 900) - 20) / (hand.length.clamp(5, 10) + 0.8)).clamp(36.0, side ? 60.0 : 70.0);
      final table = Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: g.table,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [for (var r = 0; r < 4; r++) rowView(r, cw)]),
        ),
      );
      final unseen = lInts(v['unseen']);
      return LFrame(
        status: status,
        highlight: (myChoose && myChoice <= 0) || myPick,
        result: result,
        log: lList<String>(v['log']),
        children: [
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            LChip('第 ${lInt(v['round'])} 局 · 第 ${lInt(v['trick'])}/10 轮', icon: Icons.flag),
            LChip(endMode == 66 ? '66 牛头结束' : '共 $endMode 局', icon: Icons.sports_score),
            if (v['pro'] == true) LChip('专业变体 1~${lInt(v['deckMax'])}', icon: Icons.school),
          ]),
          const SizedBox(height: 6),
          if (side)
            Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              table,
              const SizedBox(width: 10),
              SizedBox(
                width: 300,
                child: Column(mainAxisSize: MainAxisSize.min, children: [playersStrip(), const SizedBox(height: 8), reveal()]),
              ),
            ])
          else ...[
            playersStrip(),
            const SizedBox(height: 6),
            table,
            const SizedBox(height: 6),
            reveal(),
          ],
          if (unseen.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('未出现的牌：${unseen.join(' ')}', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7))),
          ],
          const SizedBox(height: 10),
          if (me)
            Wrap(spacing: 4, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final c in hand)
                NimmtCard(c,
                    width: hw,
                    selected: sel == c || (sel < 0 && myChoice == c),
                    highlight: myChoice == c,
                    onTap: myChoose ? () => setState(() => sel = c) : null),
            ]),
          if (myChoose) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: sel > 0 && sel != myChoice ? () => g.act({'type': 'choose', 'card': sel}) : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(sel > 0 ? (sel == myChoice ? '已选 $sel' : '出这张：$sel') : '点选一张手牌'),
            ),
          ],
          if (myPick) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (var r = 0; r < rows.length; r++)
                OutlinedButton(
                  onPressed: () => g.act({'type': 'row', 'row': r}),
                  child: Text('收第 ${r + 1} 列（${rows[r].fold(0, (a, c) => a + _bulls(c))}🐮）',
                      style: const TextStyle(fontFamilyFallback: kFontFallback)),
                ),
            ]),
          ],
        ],
      );
    });
  }
}

extension on bool? {
  bool get orFalse => this ?? false;
}
