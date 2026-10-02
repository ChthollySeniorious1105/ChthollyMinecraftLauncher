import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'c4_widgets.dart';

class GinRummyBoard extends StatefulWidget {
  final GameContext g;
  const GinRummyBoard(this.g, {super.key});
  @override
  State<GinRummyBoard> createState() => _GinRummyBoardState();
}

class _GinRummyBoardState extends State<GinRummyBoard> {
  String? _sel;
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  static const _kindName = {'gin': 'Gin！', 'biggin': 'Big Gin！', 'knock': '敲牌', 'undercut': '反敲（Undercut）', 'dead': '流局'};

  @override
  Widget build(BuildContext context) {
    final hand = c4Strs(v['hand']);
    final k = '${hand.join(',')}|${v['phase']}';
    if (k != _key) {
      _key = k;
      if (!hand.contains(_sel)) _sel = null;
    }
    final me = g.seat;
    final phase = '${v['phase']}';
    final turn = c4Int(v['turn']);
    final myTurn = me >= 0 && turn == me && !g.over;
    final foe = me >= 0 ? 1 - me : 1;
    final bottom = me >= 0 ? me : 0;
    final knockLimit = c4Int(v['knockLimit'], 10);
    final deadPts = c4Int(v['deadPts'], 0);
    String status;
    switch (phase) {
      case 'first':
        status = myTurn ? '要翻开的这张牌吗？（不要则由对手决定）' : '等待 ${g.name(turn)} 决定是否拿翻开的牌';
      case 'draw':
        status = myTurn ? '轮到你：从牌堆或弃牌堆摸一张' : '等待 ${g.name(turn)} 摸牌';
      case 'discard':
        status = myTurn
            ? (deadPts == 0 && hand.length == 11 ? '11 张全成组合，可以 Big Gin！' : '选一张牌弃掉（或敲牌）')
            : '等待 ${g.name(turn)} 弃牌';
      case 'handEnd':
        status = '本手结束';
      default:
        status = '比赛结束';
    }
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final landscape = c.maxWidth > c.maxHeight * 1.3;
        final w = (c.maxWidth / (landscape ? 16 : 9)).clamp(30.0, 70.0).toDouble().clamp(0.0, c.maxHeight / (landscape ? 6.2 : 7.5)).toDouble();
        final sc = c4Ints(v['scores']);
        final target = c4Int(v['target'], 100);
        final counts = c4Ints(v['counts']);
        return Stack(fit: StackFit.expand, children: [
          Column(children: [
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                c4Pill('Gin Rummy · 第 ${v['handNo']} 手', Colors.indigo),
                const SizedBox(width: 6),
                c4Pill(target == 0 ? '单手决胜' : '目标 $target 分', Colors.brown),
                const SizedBox(width: 6),
                c4Pill('敲牌上限 $knockLimit', Colors.teal.shade700),
              ]),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                g.tag(foe, active: turn == foe && !g.over, size: 30, sub: '${sc[foe]}分${c4Int(v['dealer']) == foe ? ' · 庄' : ''}'),
                const SizedBox(width: 10),
                c4Row(List.filled(counts.isEmpty ? 0 : counts[foe], 'back'), w * 0.6, gap: 0.25),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.05, vertical: 4),
                child: C4Felt(felt: c4FeltColor(g, const Color(0xFF004D40)), child: Center(child: _piles(w, myTurn, phase))),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(status, highlight: myTurn)),
            ),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  g.tag(bottom, active: myTurn, size: 26, sub: '${sc[bottom]}分${c4Int(v['dealer']) == bottom ? ' · 庄' : ''}'),
                  const SizedBox(width: 8),
                  if (v['deadPts'] != null) c4Pill('散牌 $deadPts 点', deadPts <= knockLimit ? Colors.green.shade700 : Colors.blueGrey),
                  const SizedBox(width: 8),
                  if (myTurn && phase == 'discard') ..._discardButtons(hand, knockLimit),
                ]),
              ),
              const SizedBox(height: 4),
              _hand(hand, w, c.maxWidth - 12, myTurn && phase == 'discard'),
            ] else
              const SizedBox(height: 12),
            const SizedBox(height: 6),
          ]),
          if (phase == 'handEnd' || phase == 'over') Center(child: SingleChildScrollView(child: _result(w))),
        ]);
      }),
    );
  }

  List<Widget> _discardButtons(List<String> hand, int limit) {
    final sel = _sel;
    final taken = v['taken'] as String?;
    final canPick = sel != null && sel != taken;
    return [
      if (c4Int(v['deadPts'], 99) == 0 && hand.length == 11) ...[
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade800),
          onPressed: () => g.act({'type': 'knock', 'card': null}),
          child: const Text('Big Gin'),
        ),
        const SizedBox(width: 6),
      ],
      OutlinedButton(onPressed: canPick ? () => g.act({'type': 'knock', 'card': sel}) : null, child: const Text('弃牌并敲牌')),
      const SizedBox(width: 6),
      FilledButton(onPressed: canPick ? () => g.act({'type': 'discard', 'card': sel}) : null, child: const Text('弃牌')),
    ];
  }

  Widget _piles(double w, bool myTurn, String phase) {
    final disc = c4Strs(v['discard']);
    final stock = c4Int(v['stock'], 0);
    final canStock = myTurn && phase == 'draw';
    final canDisc = myTurn && (phase == 'draw' || phase == 'first') && disc.isNotEmpty;
    Widget glow(Widget child, bool on) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: on ? const [BoxShadow(color: Colors.amberAccent, blurRadius: 12, spreadRadius: 2)] : const [],
          ),
          child: child,
        );
    final log = c4Strs(v['log']);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Column(children: [
              GestureDetector(
                onTap: canStock ? () => g.act({'type': 'draw', 'from': 'stock'}) : null,
                child: MouseRegion(
                  cursor: canStock ? SystemMouseCursors.click : MouseCursor.defer,
                  child: glow(
                      SizedBox(
                        width: w + 8,
                        height: w * 1.4 + 8,
                        child: Stack(children: [
                          for (var i = 0; i < 3; i++) Positioned(left: i * 3.0, top: i * 3.0, child: c4Card('back', w)),
                        ]),
                      ),
                      canStock),
                ),
              ),
              const SizedBox(height: 4),
              c4Pill('牌堆 $stock', Colors.black54, fontSize: 11),
            ]),
            SizedBox(width: w * 0.8),
            Column(children: [
              GestureDetector(
                onTap: canDisc ? () => g.act({'type': 'draw', 'from': 'discard'}) : null,
                child: MouseRegion(
                  cursor: canDisc ? SystemMouseCursors.click : MouseCursor.defer,
                  child: glow(
                      disc.isEmpty
                          ? Container(
                              width: w,
                              height: w * 1.4,
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white38, width: 2), borderRadius: BorderRadius.circular(8)))
                          : c4Row(disc, w, gap: 0.28, hi: {disc.last}),
                      canDisc),
                ),
              ),
              const SizedBox(height: 4),
              c4Pill('弃牌堆 ${v['discardCount']}', Colors.black54, fontSize: 11),
            ]),
          ]),
          if (phase == 'first' && myTurn) ...[
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(onPressed: () => g.act({'type': 'draw', 'from': 'discard'}), child: const Text('拿这张')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('不要')),
            ]),
          ],
          const SizedBox(height: 6),
          c4Log(log, max: 2),
        ]),
      ),
    );
  }

  Widget _hand(List<String> hand, double w, double maxW, bool canSelect) {
    final melds = [for (final m in (v['melds'] as List? ?? const [])) c4Strs(m)];
    final dead = c4Strs(v['deadwood']);
    final groups = [...melds, if (dead.isNotEmpty) dead];
    if (groups.isEmpty && hand.isNotEmpty) groups.add(hand);
    final taken = v['taken'] as String?;
    final n = hand.length + groups.length - 1;
    var cw = w;
    // step between cards inside a group; groups separated by a gap
    double stepFor(double cw) => (maxW - cw * 1.2) / (n <= 0 ? 1 : n);
    var step = stepFor(cw).clamp(cw * 0.3, cw * 0.62).toDouble();
    while (cw > 24 && cw * 1.2 + step * n > maxW) {
      cw *= 0.92;
      step = stepFor(cw).clamp(cw * 0.3, cw * 0.62).toDouble();
    }
    final children = <Widget>[];
    var x = 0.0;
    for (var gi = 0; gi < groups.length; gi++) {
      final grp = groups[gi];
      final isMeld = gi < melds.length;
      final start = x;
      for (final card in grp) {
        final sel = _sel == card;
        children.add(Positioned(
          left: x,
          top: cw * 0.3,
          child: GestureDetector(
            onTap: canSelect ? () => setState(() => _sel = sel ? null : card) : null,
            child: Stack(clipBehavior: Clip.none, children: [
              c4Face(card, cw, selected: sel, dim: canSelect && card == taken),
              if (card == taken)
                Positioned(right: 2, top: 2, child: Icon(Icons.push_pin, size: cw * 0.28, color: Colors.orange)),
            ]),
          ),
        ));
        x += step;
      }
      final end = x - step + cw;
      if (isMeld) {
        children.insert(
            0,
            Positioned(
              left: start - 3,
              top: cw * 0.3 - 3,
              width: end - start + 6,
              height: cw * 1.4 + 6,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.8), width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ));
      }
      x = end + cw * 0.18;
    }
    return SizedBox(width: x, height: cw * 1.4 + cw * 0.3 + 4, child: Stack(clipBehavior: Clip.none, children: children));
  }

  Widget _meldLine(String who, List<List<String>> melds, List<String> dead, int pts, {List<String> laid = const []}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 80, child: Text(who, overflow: TextOverflow.ellipsis)),
          for (final m in melds) ...[
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 1.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: c4Row(m, 24, gap: 0.5, hi: laid.toSet()),
            ),
            const SizedBox(width: 4),
          ],
          if (dead.isNotEmpty) ...[const SizedBox(width: 6), c4Row(dead, 24, gap: 0.5, dim: true)],
          const SizedBox(width: 8),
          Text('散牌 $pts', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _result(double w) {
    final r = v['result'] as Map?;
    final sc = c4Ints(v['scores']);
    final over = v['phase'] == 'over';
    final winner = c4Int(v['winner']);
    final kind = '${r?['kind'] ?? ''}';
    String title;
    if (over) {
      title = v['resigned'] == true
          ? '${g.name(winner)} 获胜（对手认输）'
          : (winner < 0 ? '比赛结束 · 平局' : '比赛结束 · ${g.name(winner)} 获胜');
    } else if (kind == 'dead') {
      title = '流局';
    } else {
      title = '${g.name(c4Int(r?['winner']))} ${_kindName[kind] ?? ''} +${r?['points']}';
    }
    final fin = c4Ints(v['final']);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: ResultBanner(
        title,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null && kind != 'dead' && r['knocker'] != null) ...[
            _meldLine('${g.name(c4Int(r['knocker']))}（敲）', [for (final m in r['knockerMelds'] as List) c4Strs(m)],
                c4Strs(r['knockerDead']), c4Int(r['knockerPts'], 0),
                laid: c4Strs(r['laid'])),
            _meldLine(g.name(1 - c4Int(r['knocker'])), [for (final m in r['defMelds'] as List) c4Strs(m)], c4Strs(r['defDead']),
                c4Int(r['defPts'], 0)),
            if (c4Strs(r['laid']).isNotEmpty)
              Text('贴牌：${c4Strs(r['laid']).join(' ')}', style: const TextStyle(fontSize: 12)),
          ],
          if (r != null && kind == 'dead')
            for (var s = 0; s < 2; s++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 80, child: Text(g.name(s))),
                      c4Row(c4Strs((r['hands'] as List)[s]), 24, gap: 0.5),
                    ])),
              ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (var s = 0; s < 2; s++)
              c4Pill('${g.name(s)} ${sc[s]}分${fin.length == 2 ? ' · 总计 ${fin[s]}' : ''}', s == 0 ? Colors.blue.shade700 : Colors.pink.shade600),
          ]),
          c4Continue(g),
        ]),
      ),
    );
  }
}
