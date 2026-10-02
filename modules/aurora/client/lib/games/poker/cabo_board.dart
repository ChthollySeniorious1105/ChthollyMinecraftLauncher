import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// CABO card face. value -1 = face down.
class CaboCard extends StatelessWidget {
  final int value;
  final double width;
  final bool selected;
  final bool highlight;
  final VoidCallback? onTap;
  const CaboCard(this.value, {super.key, this.width = 56, this.selected = false, this.highlight = false, this.onTap});

  static Color colorOf(int v) {
    if (v <= 0) return const Color(0xFF2E7D32);
    if (v <= 4) return const Color(0xFF00897B);
    if (v <= 6) return const Color(0xFF1E88E5);
    if (v <= 8) return const Color(0xFF5E35B1); // peek
    if (v <= 10) return const Color(0xFFF57C00); // spy
    if (v <= 12) return const Color(0xFFC62828); // swap
    return const Color(0xFF263238);
  }

  static String powerOf(int v) {
    if (v == 7 || v == 8) return '👁 看自己';
    if (v == 9 || v == 10) return '🔍 看别人';
    if (v == 11 || v == 12) return '🔄 盲换';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    Widget body;
    if (value < 0) {
      body = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: const LinearGradient(colors: [Color(0xFF37474F), Color(0xFF0D47A1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white70, width: width * 0.04),
        ),
        child: Center(
          child: Text('CABO',
              style: TextStyle(fontSize: width * 0.2, color: Colors.white70, fontWeight: FontWeight.w900, letterSpacing: 1)),
        ),
      );
    } else {
      final c = colorOf(value);
      final p = powerOf(value);
      body = Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDF7),
          borderRadius: BorderRadius.circular(width * 0.12),
          border: Border.all(color: c, width: width * 0.06),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$value', style: TextStyle(fontSize: width * 0.5, fontWeight: FontWeight.w900, color: c, height: 1.1)),
              if (p.isNotEmpty && width >= 44) Text(p, style: TextStyle(fontSize: width * 0.14, color: c)),
            ]),
          ),
        ),
      );
    }
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.12),
        boxShadow: [
          BoxShadow(
            color: selected ? Colors.amber : (highlight ? Colors.lightGreenAccent : Colors.black45),
            blurRadius: selected || highlight ? 10 : 3,
            spreadRadius: selected || highlight ? 2 : 0,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: body,
    );
    if (onTap == null) return card;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
  }
}

class CaboBoard extends StatefulWidget {
  final GameContext g;
  const CaboBoard(this.g, {super.key});
  @override
  State<CaboBoard> createState() => _CaboBoardState();
}

class _CaboBoardState extends State<CaboBoard> {
  final Set<int> _mine = {}; // selected own slots
  int _oOwner = -1, _oSlot = -1; // selected opponent slot
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  void _reset() {
    _mine.clear();
    _oOwner = -1;
    _oSlot = -1;
  }

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final turn = v['turn'] as int;
    final me = g.seat;
    final power = '${v['power']}';
    final k = '$phase|$turn|$power|${v['round']}';
    if (k != _key) {
      _key = k;
      _reset();
    }
    final grid = [for (final r in v['grid'] as List) (r as List).cast<int>()];
    final scores = (v['scores'] as List).cast<int>();
    final peekDone = (v['peekDone'] as List).cast<bool>();
    final caller = v['caller'] as int;
    final drawn = v['drawn'] as int?;
    final reveal = v['reveal'] as Map?;
    final myTurn = me >= 0 && turn == me && (phase == 'turn' || phase == 'drawn' || phase == 'power');
    final needPeek = me >= 0 && phase == 'peek' && !peekDone[me];
    final last = v['last'] as Map?;

    String status;
    switch (phase) {
      case 'peek':
        status = needPeek ? '选择自己的两张牌偷看（记住它们！）' : '等待其他玩家偷看…';
        break;
      case 'turn':
        status = myTurn ? '轮到你：摸牌、拿弃牌堆顶，或喊 CABO' : '等待 ${g.name(turn)}';
        break;
      case 'drawn':
        status = myTurn
            ? (v['fromDiscard'] == true ? '选择要替换的牌（可多选相同点数）' : '选择要替换的牌（可多选相同点数），或直接弃掉')
            : '${g.name(turn)} 正在考虑…';
        break;
      case 'power':
        status = myTurn
            ? const {'peek': '技能：选择自己的一张牌偷看', 'spy': '技能：选择对手的一张牌偷看', 'swap': '技能：各选一张自己和对手的牌盲换'}[power]!
            : '${g.name(turn)} 正在使用技能';
        break;
      case 'roundEnd':
        status = '本局结束';
        break;
      default:
        status = '游戏结束';
    }
    if (caller >= 0 && (phase == 'turn' || phase == 'drawn' || phase == 'power')) status += '（${g.name(caller)} 已喊 CABO）';

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final others = g.seatsFromMe().where((s) => s != me).toList();
        final cw = (c.maxWidth / (others.length >= 3 ? 11 : 8)).clamp(34.0, 70.0).toDouble().clamp(30.0, c.maxHeight / 9).toDouble();
        final myCw = (cw * 1.3).clamp(36.0, 84.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final s in others) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _seat(s, grid[s], cw, scores, caller, turn, phase, reveal)),
                ]),
              ),
            ),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Column(children: [
                      CaboCard(-1, width: cw),
                      Text('牌堆 ${v['deck']}', style: const TextStyle(color: Colors.white)),
                    ]),
                    const SizedBox(width: 16),
                    Column(children: [
                      if (v['discardTop'] == null) SizedBox(width: cw, height: cw * 1.4) else CaboCard(v['discardTop'] as int, width: cw),
                      const Text('弃牌堆', style: TextStyle(color: Colors.white)),
                    ]),
                    if (drawn != null) ...[
                      const SizedBox(width: 24),
                      Column(children: [
                        CaboCard(drawn, width: cw * 1.15, highlight: true),
                        const Text('手中的牌', style: TextStyle(color: Colors.amberAccent)),
                      ]),
                    ],
                    if (last != null) ...[
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text('${g.name(last['seat'] as int)} ${last['text']}', style: const TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            StatusBar(status, highlight: myTurn || needPeek),
            const SizedBox(height: 6),
            if (me >= 0) ...[
              _buttons(phase, power, myTurn, needPeek, caller, grid[me]),
              const SizedBox(height: 6),
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: _seat(me, grid[me], myCw, scores, caller, turn, phase, reveal, mine: true),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ]),
          if (phase == 'roundEnd' || phase == 'over') Center(child: _result(scores)),
        ]);
      }),
    );
  }

  bool _canTapMine(String phase, String power, bool myTurn, bool needPeek) =>
      needPeek || (myTurn && (phase == 'drawn' || (phase == 'power' && (power == 'peek' || power == 'swap'))));

  bool _canTapOther(int s, String phase, String power, bool myTurn, int caller) =>
      myTurn && phase == 'power' && (power == 'spy' || (power == 'swap' && s != caller));

  Widget _seat(int s, List<int> cards, double cw, List<int> scores, int caller, int turn, String phase, Map? reveal,
      {bool mine = false}) {
    final me = g.seat;
    final power = '${v['power']}';
    final myTurn = me >= 0 && turn == me && (phase == 'turn' || phase == 'drawn' || phase == 'power');
    final needPeek = me >= 0 && phase == 'peek' && !(v['peekDone'] as List)[me];
    final lastSwap = (v['last'] as Map?)?['swap'] as List?;
    Widget cell(int i) {
      final val = cards[i];
      final revealed = reveal != null && reveal['owner'] == s && reveal['slot'] == i;
      final swapped = lastSwap != null && ((lastSwap[0] == s && lastSwap[1] == i) || (lastSwap[2] == s && lastSwap[3] == i));
      VoidCallback? tap;
      if (mine && _canTapMine(phase, power, myTurn, needPeek)) {
        tap = () => setState(() {
              if (needPeek) {
                if (!_mine.remove(i) && _mine.length < 2) _mine.add(i);
              } else if (phase == 'drawn') {
                if (!_mine.remove(i)) _mine.add(i);
              } else {
                _mine
                  ..clear()
                  ..add(i);
              }
            });
      } else if (!mine && _canTapOther(s, phase, power, myTurn, caller)) {
        tap = () => setState(() {
              _oOwner = s;
              _oSlot = i;
            });
      }
      final sel = mine ? _mine.contains(i) : (_oOwner == s && _oSlot == i);
      return Padding(
        padding: EdgeInsets.all(cw * 0.06),
        child: CaboCard(val, width: cw, selected: sel, highlight: revealed || swapped, onTap: tap),
      );
    }

    final rows = <Widget>[];
    for (var r = 0; r * 2 < cards.length && cards.length <= 4; r++) {
      rows.add(Row(mainAxisSize: MainAxisSize.min, children: [
        cell(r * 2),
        if (r * 2 + 1 < cards.length) cell(r * 2 + 1),
      ]));
    }
    // extra penalty cards go in a third column when there are more than 4
    Widget gridW;
    if (cards.length <= 4) {
      gridW = Column(mainAxisSize: MainAxisSize.min, children: rows);
    } else {
      final cols = (cards.length + 1) ~/ 2;
      gridW = Column(mainAxisSize: MainAxisSize.min, children: [
        for (var r = 0; r < 2; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = r * cols; i < (r + 1) * cols && i < cards.length; i++) cell(i),
          ]),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          size: 30,
          active: (phase == 'turn' || phase == 'drawn' || phase == 'power') && turn == s,
          sub: '总分 ${scores[s]}',
          trailing: caller == s
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                  child: const Text('CABO', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                )
              : null),
      const SizedBox(height: 4),
      gridW,
    ]);
  }

  Widget _buttons(String phase, String power, bool myTurn, bool needPeek, int caller, List<int> mine) {
    final btns = <Widget>[];
    if (needPeek) {
      btns.add(FilledButton(
        onPressed: _mine.length == 2 ? () => g.act({'type': 'peek', 'slots': _mine.toList()}) : null,
        child: Text('偷看所选 (${_mine.length}/2)'),
      ));
    } else if (myTurn && phase == 'turn') {
      btns.add(FilledButton(onPressed: () => g.act({'type': 'draw'}), child: const Text('摸牌')));
      btns.add(FilledButton.tonal(onPressed: v['discardTop'] == null ? null : () => g.act({'type': 'take'}), child: const Text('拿弃牌')));
      btns.add(FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
        onPressed: caller >= 0 ? null : () => g.act({'type': 'cabo'}),
        child: const Text('喊 CABO！'),
      ));
    } else if (myTurn && phase == 'drawn') {
      btns.add(FilledButton(
        onPressed: _mine.isEmpty ? null : () => g.act({'type': 'swap', 'slots': _mine.toList()}),
        child: Text(_mine.length > 1 ? '替换 ${_mine.length} 张' : '替换所选'),
      ));
      if (v['fromDiscard'] != true) {
        final d = v['drawn'] as int?;
        final p = d == null ? '' : CaboCard.powerOf(d);
        btns.add(OutlinedButton(onPressed: () => g.act({'type': 'discard'}), child: Text(p.isEmpty ? '弃掉' : '弃掉并使用 $p')));
      }
    } else if (myTurn && phase == 'power') {
      if (power == 'peek') {
        btns.add(FilledButton(
          onPressed: _mine.isEmpty ? null : () => g.act({'type': 'peek', 'slot': _mine.first}),
          child: const Text('偷看'),
        ));
      } else if (power == 'spy') {
        btns.add(FilledButton(
          onPressed: _oOwner < 0 ? null : () => g.act({'type': 'spy', 'owner': _oOwner, 'slot': _oSlot}),
          child: const Text('偷看对手'),
        ));
      } else {
        btns.add(FilledButton(
          onPressed: _oOwner < 0 || _mine.isEmpty
              ? null
              : () => g.act({'type': 'blind', 'slot': _mine.first, 'owner': _oOwner, 'oslot': _oSlot}),
          child: const Text('交换'),
        ));
      }
      btns.add(OutlinedButton(onPressed: () => g.act({'type': 'skipPower'}), child: const Text('放弃技能')));
    }
    if (btns.isEmpty) return const SizedBox(height: 4);
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: btns);
  }

  Widget _result(List<int> scores) {
    final r = v['result'] as Map?;
    final over = v['phase'] == 'over';
    final me = g.seat;
    final ready = (v['ready'] as List?)?.cast<bool>();
    final order = List.generate(g.players, (i) => i);
    final resigned = v['resigned'] is int ? v['resigned'] as int : -1;
    if (over) order.sort((a, b) => a == resigned ? 1 : (b == resigned ? -1 : scores[a] - scores[b]));
    final sums = (r?['sums'] as List?)?.cast<int>();
    final delta = (r?['delta'] as List?)?.cast<int>();
    final reset = (r?['reset'] as List?)?.cast<int>() ?? const [];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: ResultBanner(
        over ? '游戏结束 · ${g.name(order.first)} 获胜' : '本局结算',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null && (r['caller'] as int) >= 0) Text('${g.name(r['caller'] as int)} 喊了 CABO', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          for (var i = 0; i < order.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 28, child: Text(over ? '#${i + 1}' : '')),
                SizedBox(width: 100, child: Text(g.name(order[i]), overflow: TextOverflow.ellipsis)),
                if (sums != null) SizedBox(width: 60, child: Text('${sums[order[i]]}点')),
                if (delta != null)
                  SizedBox(
                    width: 50,
                    child: Text('+${delta[order[i]]}',
                        style: TextStyle(color: delta[order[i]] == 0 ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                SizedBox(
                  width: 70,
                  child: Text('${scores[order[i]]}分${reset.contains(order[i]) ? " ↺" : ""}', textAlign: TextAlign.right),
                ),
              ]),
            ),
          if (!over && ready != null && me >= 0) ...[
            const SizedBox(height: 8),
            FilledButton(
              onPressed: ready[me] ? null : () => g.act({'type': 'continue'}),
              child: Text(ready[me] ? '等待其他玩家…' : '继续下一局'),
            ),
          ],
        ]),
      ),
    );
  }
}
