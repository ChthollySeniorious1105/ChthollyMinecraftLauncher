import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tr_common.dart';

/// 红心大战 牌桌
class HeartsBoard extends StatefulWidget {
  final GameContext g;
  const HeartsBoard(this.g, {super.key});
  @override
  State<HeartsBoard> createState() => _HeartsBoardState();
}

class _HeartsBoardState extends State<HeartsBoard> {
  final Set<String> _sel = {};
  bool _sheet = false;
  int _selHand = -1;

  static const _dirNames = ['向左传', '向右传', '向对家传', '不传牌'];
  static const _dirArrows = ['←', '→', '↑', '·'];

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<int> _ints(Object? x) => x is List ? [for (final e in x) (e as num).toInt()] : <int>[];

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final handNo = (v['handNo'] as num?)?.toInt() ?? 0;
    if (_selHand != handNo || phase != 'pass') {
      if (_selHand != handNo) _sel.clear();
      _selHand = handNo;
    }
    final hand = trList(v['hand']);
    _sel.removeWhere((c) => !hand.contains(c));
    final scores = _ints(v['scores']);
    final taken = _ints(v['taken']);
    final counts = _ints(v['counts']);
    final passed = (v['passed'] as List?)?.cast<bool>() ?? const [false, false, false, false];
    final turn = (v['turn'] as num?)?.toInt() ?? 0;
    final passDir = (v['passDir'] as num?)?.toInt() ?? 0;
    final trick = (v['trick'] as List?) ?? const [];
    final lastWinner = (v['lastWinner'] as num?)?.toInt() ?? -1;
    final me = g.seat;

    Widget panel(int s, double w) {
      final active = (phase == 'play' && turn == s) || (phase == 'pass' && !passed[s]);
      final sub = '总分 ${scores[s]} · 本局 ${taken[s]}';
      return Column(mainAxisSize: MainAxisSize.min, children: [
        g.tag(s, active: active, sub: sub, size: 32),
        const SizedBox(height: 4),
        Row(mainAxisSize: MainAxisSize.min, children: [
          trBacks(counts[s], w * 0.8),
          const SizedBox(width: 8),
          if (phase == 'pass') trBadge(passed[s] ? '已传' : '选牌中', passed[s] ? Colors.teal : Colors.orange),
          if (taken[s] > 0) trBadge('♥ ${taken[s]}', Colors.red.shade700),
        ]),
      ]);
    }

    // ---- status ----
    String status;
    var hi = false;
    if (phase == 'pass') {
      final mine = me >= 0 && !passed[me];
      status = mine ? '请选择 3 张牌${_dirNames[passDir]}（已选 ${_sel.length}/3）' : '等待其他玩家传牌…';
      hi = mine;
    } else if (phase == 'play') {
      hi = turn == me;
      status = hi ? '轮到你出牌' : '等待 ${g.name(turn)} 出牌';
      if (hi && trick.isEmpty && (v['trickNo'] as num? ?? 0) == 0) status = '由你首出梅花 2';
    } else if (phase == 'trickEnd') {
      status = '${g.name(lastWinner)} 赢得这一墩';
    } else if (phase == 'handEnd') {
      status = '本局结束';
    } else {
      status = '比赛结束';
    }

    final info = Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        StatusBar(status, highlight: hi),
        trChip('第 ${handNo + 1} 局 ${_dirArrows[passDir]} ${_dirNames[passDir]}', Colors.indigo),
        trChip(v['heartsBroken'] == true ? '♥ 已破' : '♥ 未破', v['heartsBroken'] == true ? Colors.red.shade700 : Colors.grey.shade700),
        trChip('目标 ${v['target']}', Colors.brown),
        trChip('记分表', Colors.blueGrey, onTap: () => setState(() => _sheet = !_sheet)),
      ],
    );

    final center = TrTrick(
      g: g,
      trick: trick,
      winner: phase == 'trickEnd' ? lastWinner : -1,
      w: 52,
      middle: trick.isEmpty && phase == 'pass'
          ? trNote(passDir == 3 ? '本局不传牌' : '${_dirArrows[passDir]} ${_dirNames[passDir]}')
          : null,
    );

    Widget bottom(double cw, double maxW) {
      final legal = trList(v['legal']).toSet();
      final canPass = phase == 'pass' && me >= 0 && !passed[me];
      final received = (v['trickNo'] as num? ?? 0) == 0 ? trList(v['received']).toSet() : <String>{};
      final myPass = trList(v['myPass']).toSet();
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (me >= 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              g.tag(me, active: hi, sub: '总分 ${scores[me]} · 本局 ${taken[me]}', size: 28),
              if (canPass) ...[
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _sel.length == 3
                      ? () {
                          g.act({'type': 'pass', 'cards': _sel.toList()});
                          setState(_sel.clear);
                        }
                      : null,
                  child: Text('传出 ${_sel.length}/3'),
                ),
              ],
            ]),
          ),
        SizedBox(
          width: maxW,
          child: Center(
            child: TrHand(
              cards: hand,
              cardW: cw,
              legal: canPass ? hand.toSet() : legal,
              selected: canPass ? _sel : myPass,
              fresh: received,
              dimIllegal: phase == 'play' && turn == me,
              onTap: canPass
                  ? (c) => setState(() {
                        if (!_sel.remove(c) && _sel.length < 3) _sel.add(c);
                      })
                  : (phase == 'play' && turn == me ? (c) => g.act({'type': 'play', 'card': c}) : null),
            ),
          ),
        ),
      ]);
    }

    Widget? overlay;
    if (phase == 'handEnd' || phase == 'over') {
      overlay = _resultPanel(phase == 'over');
    } else if (_sheet) {
      overlay = _card(Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetGrid(),
        TextButton(onPressed: () => setState(() => _sheet = false), child: const Text('关闭')),
      ]));
    }

    return TrTable(g: g, panel: panel, center: center, info: info, bottom: bottom, overlay: overlay);
  }

  Widget _card(Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: cs.onSurface), child: child),
    );
  }

  Widget _sheetGrid() {
    final hist = (v['history'] as List?) ?? const [];
    final scores = _ints(v['scores']);
    final rows = <List<String>>[
      for (var i = 0; i < hist.length; i++) ['${i + 1}', for (final x in hist[i] as List) '+$x'],
      ['合计', for (final s in scores) '$s'],
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: trGrid(['局', for (var s = 0; s < 4; s++) g.name(s)], rows.length > 12 ? rows.sublist(rows.length - 12) : rows, colW: 70),
    );
  }

  Widget _resultPanel(bool over) {
    final r = (v['result'] as Map?) ?? const {};
    final taken = _ints(r['taken']);
    final add = _ints(r['add']);
    final moon = (r['moon'] as num?)?.toInt() ?? -1;
    final cards = (r['cards'] as List?) ?? const [];
    final winners = _ints(v['winners']);
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      if (moon >= 0) Padding(padding: const EdgeInsets.only(bottom: 6), child: FittedBox(fit: BoxFit.scaleDown, child: trNote('${g.name(moon)} 射月成功！其他人各 +26', color: Colors.deepPurple))),
      for (var s = 0; s < 4 && s < taken.length; s++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 90, child: Text(g.name(s), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold))),
            SizedBox(width: 60, child: Text('吃 ${taken[s]}')),
            SizedBox(width: 50, child: Text('+${add[s]}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
            SizedBox(
              width: 150,
              height: 30,
              child: s < cards.length
                  ? Row(children: [
                      for (final c in trList(cards[s]).take(14))
                        Align(widthFactor: 0.45, child: trMini(c, 20)),
                    ])
                  : null,
            ),
          ])),
        ),
      const SizedBox(height: 8),
      _sheetGrid(),
      if (!over) trContinue(g, (v['ready'] as List?)?.cast<bool>()),
    ]);
    if (over) {
      return ResultBanner('${winners.map(g.name).join('、')} 获胜！', child: body);
    }
    return _card(body);
  }
}
