import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'tt_common.dart';

const _cats = [
  'ones', 'twos', 'threes', 'fours', 'fives', 'sixes', //
  'threeKind', 'fourKind', 'fullHouse', 'smallStraight', 'largeStraight', 'yahtzee', 'chance',
];
const _catNames = {
  'ones': '一点',
  'twos': '二点',
  'threes': '三点',
  'fours': '四点',
  'fives': '五点',
  'sixes': '六点',
  'threeKind': '三条',
  'fourKind': '四条',
  'fullHouse': '葫芦 25',
  'smallStraight': '小顺 30',
  'largeStraight': '大顺 40',
  'yahtzee': '快艇 50',
  'chance': '全计',
};

class YahtzeeBoard extends StatefulWidget {
  final GameContext g;
  const YahtzeeBoard(this.g, {super.key});
  @override
  State<YahtzeeBoard> createState() => _YahtzeeBoardState();
}

class _YahtzeeBoardState extends State<YahtzeeBoard> {
  List<bool> hold = List.filled(5, false);
  String stateKey = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final turn = ttInt(v['turn']);
    final dice = ttList<int>(v['dice']);
    final rolled = v['rolled'] == true;
    final rollsLeft = ttInt(v['rollsLeft']);
    final over = v['over'] == true;
    final myTurn = !over && turn == g.seat;
    final key = '$turn/$rollsLeft/${ttInt(v['round'])}';
    if (key != stateKey) {
      stateKey = key;
      hold = List.of(ttList<bool>(v['held']));
      if (hold.length != 5) hold = List.filled(5, false);
    }
    final cards = ttList<dynamic>(v['cards']).map(ttMap).toList();
    final opts = ttMap(v['options']);
    final winners = ttList<int>(v['winners']);

    String status;
    if (over) {
      status = '游戏结束';
    } else if (myTurn) {
      status = !rolled ? '轮到你了：掷骰' : (rollsLeft > 0 ? '点骰子保留，再掷（剩 $rollsLeft 次）或选择计分项' : '请选择计分项');
    } else {
      status = '等待 ${g.name(turn)}（剩 $rollsLeft 次掷骰）';
    }

    Widget diceArea(double size) => Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: size * 0.18, runSpacing: 8, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < 5; i++)
              Opacity(
                opacity: rolled ? 1 : 0.35,
                child: DieFace(dice.length > i ? dice[i] : 1,
                    size: size,
                    held: rolled && (myTurn ? hold[i] : ttList<bool>(v['held']).elementAtOrNull(i) == true),
                    onTap: myTurn && rolled && rollsLeft > 0 ? () => setState(() => hold[i] = !hold[i]) : null),
              ),
          ]),
          const SizedBox(height: 12),
          if (myTurn)
            FilledButton.icon(
              onPressed: rollsLeft > 0 && !(rolled && hold.every((h) => h)) ? () => g.act({'type': 'roll', 'hold': hold}) : null,
              icon: const Icon(Icons.casino),
              label: Text(rolled ? '再掷一次（剩 $rollsLeft）' : '掷骰子'),
            ),
          const SizedBox(height: 6),
          Text('第 ${ttInt(v['round'])} / 13 回合', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.8))),
          if ((v['last'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(v['last'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ),
        ]);

    Widget scoreTable() {
      final n = cards.length;
      TableRow row(String label, List<Widget> cells, {Color? bg}) => TableRow(
            decoration: BoxDecoration(color: bg),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              ...cells,
            ],
          );
      Widget cell(String t, {bool bold = false, Color? color}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Text(t,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
          );
      final rows = <TableRow>[
        row('', [
          for (var s = 0; s < n; s++)
            Padding(
              padding: const EdgeInsets.all(3),
              child: Column(children: [
                Avatar(g.avatar(s), size: 22, bot: g.bot(s)),
                Text(g.name(s),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: s == turn && !over ? cs.primary : null)),
              ]),
            ),
        ]),
      ];
      for (var i = 0; i < _cats.length; i++) {
        final c = _cats[i];
        rows.add(row(_catNames[c]!, [
          for (var s = 0; s < n; s++)
            () {
              final sc = ttMap(cards[s]['scores'])[c];
              if (sc != null) return cell('$sc', bold: true);
              if (s == turn && opts.containsKey(c)) {
                final p = ttInt(opts[c]);
                final btn = Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: (p > 0 ? cs.primary : cs.error).withValues(alpha: myTurn ? 0.25 : 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: (p > 0 ? cs.primary : cs.error).withValues(alpha: 0.6)),
                  ),
                  child: Text('$p',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: p > 0 ? cs.primary : cs.error, fontWeight: FontWeight.bold)),
                );
                return myTurn
                    ? InkWell(onTap: () => g.act({'type': 'score', 'cat': c}), child: btn)
                    : btn;
              }
              return cell('');
            }(),
        ], bg: i < 6 ? null : cs.secondaryContainer.withValues(alpha: 0.15)));
        if (i == 5) {
          rows.add(row('上区小计', [
            for (var s = 0; s < n; s++) cell('${ttInt(cards[s]['upper'])}/63', color: cs.onSurface.withValues(alpha: 0.7)),
          ]));
          rows.add(row('奖励 35', [
            for (var s = 0; s < n; s++) cell('${ttInt(cards[s]['upperBonus'])}'),
          ]));
        }
      }
      rows.add(row('快艇奖励', [
        for (var s = 0; s < n; s++) cell('${ttInt(cards[s]['bonusYahtzees']) * 100}'),
      ]));
      rows.add(row('总分', [
        for (var s = 0; s < n; s++) cell('${ttInt(cards[s]['total'])}', bold: true, color: cs.primary),
      ], bg: cs.primary.withValues(alpha: 0.12)));
      return TTPanel(
        padding: const EdgeInsets.all(4),
        child: Table(
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          border: TableBorder(horizontalInside: BorderSide(color: cs.outline.withValues(alpha: 0.2))),
          columnWidths: {0: const IntrinsicColumnWidth(), for (var s = 0; s < n; s++) s + 1: const FlexColumnWidth()},
          children: rows,
        ),
      );
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 720 && c.maxWidth > c.maxHeight;
      final dieSize = (wide ? c.maxWidth * 0.45 : c.maxWidth) / 7.5;
      final top = Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        StatusBar(status, highlight: myTurn),
        if (over)
          ResultBanner('${winners.map(g.name).join('、')} 获胜！',
              child: Text(winners.isEmpty ? '' : '${ttInt(cards[winners.first]['total'])} 分')),
        const SizedBox(height: 10),
        diceArea(dieSize.clamp(36.0, 64.0)),
        const SizedBox(height: 10),
      ]);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: Center(child: SingleChildScrollView(child: top))),
          Expanded(
            flex: 5,
            child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: scoreTable()),
          ),
        ]);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(children: [top, scoreTable(), const SizedBox(height: 12)]),
      );
    });
  }
}
