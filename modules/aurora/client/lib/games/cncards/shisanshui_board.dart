import 'package:aurora_shared/games/cncards/cards.dart';
import 'package:aurora_shared/games/cncards/ssz_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'cn_widgets.dart';

class ShisanshuiBoard extends StatefulWidget {
  final GameContext g;
  const ShisanshuiBoard(this.g, {super.key});
  @override
  State<ShisanshuiBoard> createState() => _ShisanshuiBoardState();
}

const _laneNames = ['前墩', '中墩', '后墩'];
const _laneCap = [3, 5, 5];

class _ShisanshuiBoardState extends State<ShisanshuiBoard> {
  /// card -> lane (0/1/2); cards not in the map are still in hand.
  final Map<String, int> _lane = {};
  final Set<String> _sel = {};
  String _handKey = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => cnStrs(v['hand']);

  void _sync() {
    final k = '${v['round']}|${hand.join(',')}';
    if (k != _handKey) {
      _handKey = k;
      _lane.clear();
      _sel.clear();
    }
  }

  List<String> _laneCards(int l) {
    final cs = [for (final c in hand) if (_lane[c] == l) c];
    cs.sort((a, b) => cnRank(b) - cnRank(a));
    return cs;
  }

  List<String> get _free => [for (final c in hand) if (!_lane.containsKey(c)) c];

  void _toLane(int l, Iterable<String> cards) {
    setState(() {
      for (final c in cards) {
        if (_laneCards(l).length >= _laneCap[l]) break;
        _lane[c] = l;
        _sel.remove(c);
      }
    });
  }

  void _auto() {
    final a = ssBestArrangement(hand);
    setState(() {
      _lane.clear();
      _sel.clear();
      for (final c in a.front) {
        _lane[c] = 0;
      }
      for (final c in a.mid) {
        _lane[c] = 1;
      }
      for (final c in a.back) {
        _lane[c] = 2;
      }
    });
  }

  void _submit() {
    g.act({'type': 'arrange', 'front': _laneCards(0), 'mid': _laneCards(1), 'back': _laneCards(2)});
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final phase = '${v['phase']}';
    final me = g.seat;
    final done = [for (final x in v['done'] as List) x == true];
    final arranging = me >= 0 && phase == 'arrange' && !done[me];
    String status;
    if (phase == 'arrange') {
      if (arranging) {
        status = '点选手牌后点墩位放入（或拖动），可用自动理牌';
      } else {
        final left = [for (var s = 0; s < g.players; s++) if (!done[s]) g.name(s)];
        status = '等待 ${left.join('、')} 理牌';
      }
    } else {
      status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    final scores = cnInts(v, 'scores');
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 7.4 : 15)).clamp(28.0, 58.0).toDouble();
        final byH = (c.maxHeight / (c.maxHeight < 500 ? 9.5 : 9)).clamp(24.0, 58.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              cnPill('十三水 第 ${v['round']}/${v['rounds']} 局', Colors.indigo),
              if (me >= 0 && v['mySpecial'] != null) cnPill('特殊牌型：${v['mySpecial']}', Colors.purple),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                for (final s in others)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: g.tag(s,
                          size: 28,
                          active: phase == 'arrange' && !done[s],
                          sub: '${scores[s]}分',
                          trailing: cnPill(done[s] ? '已理好' : '理牌中', done[s] ? Colors.green : Colors.grey, fontSize: 11)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.04, vertical: 2),
                child: CnFelt(
                  felt: cnFeltColor(g),
                  child: Center(child: me >= 0 ? _lanes(w, arranging) : const SizedBox()),
                ),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: arranging),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              g.tag(me, size: 26, active: arranging, sub: '${scores[me]}分'),
              if (arranging) ...[
                const SizedBox(height: 4),
                _buttons(),
                const SizedBox(height: 4),
                _hand(w, c.maxWidth - 16),
              ],
            ],
            const SizedBox(height: 8),
          ]),
          if (phase != 'arrange') Center(child: SingleChildScrollView(child: _result())),
        ]);
      }),
    );
  }

  Widget _lanes(double w, bool arranging) {
    final mine = v['mine'] as Map?;
    List<String> cardsOf(int l) {
      if (arranging) return _laneCards(l);
      if (mine == null) return const [];
      return cnStrs(mine[['front', 'mid', 'back'][l]]);
    }

    final lanes = [for (var l = 0; l < 3; l++) cardsOf(l)];
    final full = lanes[0].length == 3 && lanes[1].length == 5 && lanes[2].length == 5;
    final foul = full && !ssValid(lanes[0], lanes[1], lanes[2]);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var l = 0; l < 3; l++) _laneRow(l, lanes[l], w, arranging, foul),
          if (foul) Padding(padding: const EdgeInsets.only(top: 4), child: cnPill('倒水！需 后墩 ≥ 中墩 ≥ 前墩', Colors.red)),
          if (!arranging && mine == null) const Text('观战中', style: TextStyle(color: Colors.white54)),
        ]),
      ),
    );
  }

  Widget _laneRow(int l, List<String> cards, double w, bool arranging, bool foul) {
    final name = cards.length == _laneCap[l] ? ssName(ssEval(cards)) : '${cards.length}/${_laneCap[l]}';
    final row = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: foul ? Colors.redAccent : Colors.white24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 58,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_laneNames[l], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(name, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
          ]),
        ),
        for (var i = 0; i < _laneCap[l]; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: i < cards.length
                ? GestureDetector(
                    onTap: arranging ? () => setState(() => _lane.remove(cards[i])) : null,
                    child: arranging ? _draggable(cards[i], w) : cnCard(cards[i], w),
                  )
                : cnSlot(w),
          ),
        // keep lane widths aligned
        for (var i = _laneCap[l]; i < 5; i++) SizedBox(width: w + 3),
      ]),
    );
    if (!arranging) return row;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => _lane[d.data] != l,
      onAcceptWithDetails: (d) {
        final moving = _sel.contains(d.data) ? [d.data, ..._sel.where((x) => x != d.data)] : [d.data];
        setState(() {
          for (final c in moving) {
            _lane.remove(c);
          }
        });
        _toLane(l, moving);
      },
      builder: (context, cand, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _sel.isEmpty ? null : () => _toLane(l, _sel.toList()),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: cand.isNotEmpty || (_sel.isNotEmpty && cards.length < _laneCap[l])
                ? const [BoxShadow(color: Colors.amberAccent, blurRadius: 6)]
                : null,
          ),
          child: row,
        ),
      ),
    );
  }

  Widget _draggable(String c, double w) => Draggable<String>(
        data: c,
        feedback: Material(color: Colors.transparent, child: cnCard(c, w)),
        childWhenDragging: cnSlot(w),
        child: cnCard(c, w),
      );

  Widget _buttons() {
    final full = _laneCards(0).length == 3 && _laneCards(1).length == 5 && _laneCards(2).length == 5;
    final valid = full && ssValid(_laneCards(0), _laneCards(1), _laneCards(2));
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
      OutlinedButton.icon(onPressed: _auto, icon: const Icon(Icons.auto_fix_high, size: 18), label: const Text('自动理牌')),
      OutlinedButton(
          onPressed: _lane.isEmpty && _sel.isEmpty
              ? null
              : () => setState(() {
                    _lane.clear();
                    _sel.clear();
                  }),
          child: const Text('重置')),
      FilledButton(onPressed: valid ? _submit : null, child: const Text('确认出牌')),
    ]);
  }

  Widget _hand(double cw, double maxW) {
    final h = _free;
    if (h.isEmpty) return SizedBox(height: cw * 1.4 + cw * 0.3);
    final n = h.length;
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.3, cw * 1.05).toDouble();
    final total = cw + step * (n - 1);
    return SizedBox(
      width: total,
      height: cw * 1.4 + cw * 0.3,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < n; i++)
          Positioned(
            left: step * i,
            bottom: 0,
            child: Draggable<String>(
              data: h[i],
              feedback: Material(color: Colors.transparent, child: cnCard(h[i], cw)),
              childWhenDragging: SizedBox(width: cw, height: cw * 1.4),
              child: GestureDetector(
                onTap: () => setState(() {
                  if (!_sel.remove(h[i])) _sel.add(h[i]);
                }),
                child: PlayingCard(h[i], width: cw, selected: _sel.contains(h[i])),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final scores = cnInts(v, 'scores');
    final over = v['phase'] == 'over';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    final guns = [for (final x in (r?['guns'] as List? ?? const [])) cnInts({'x': x}, 'x')];
    final homerun = r == null ? <int>[] : cnInts(Map<String, dynamic>.from(r), 'homerun');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 积分最高' : '第 ${v['round']} 局结算',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (guns.isNotEmpty || homerun.isNotEmpty)
            Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
              for (final gn in guns) cnPill('${g.name(gn[0])} 打枪 ${g.name(gn[1])}', Colors.red.shade700, fontSize: 11),
              for (final s in homerun) cnPill('${g.name(s)} 全垒打', Colors.purple, fontSize: 11),
            ]),
          const SizedBox(height: 4),
          for (var k = 0; k < order.length; k++) _resultRow(r, order[k], over ? k : -1, scores),
          cnContinue(g),
        ]),
      ),
    );
  }

  Widget _resultRow(Map? r, int s, int rank, List<int> scores) {
    final lanes = <Widget>[];
    String? special;
    bool foul = false;
    if (r != null) {
      final arr = (r['arr'] as List)[s] as Map;
      final names = cnStrs((r['laneNames'] as List)[s]);
      special = (r['special'] as List)[s] as String?;
      foul = (r['foul'] as List)[s] == true;
      for (var l = 0; l < 3; l++) {
        lanes.add(Column(mainAxisSize: MainAxisSize.min, children: [
          cnRow(cnStrs(arr[['front', 'mid', 'back'][l]]), 20, gap: 0.5),
          Text(names[l], style: const TextStyle(fontSize: 10)),
        ]));
        lanes.add(const SizedBox(width: 6));
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 26, child: Text(rank >= 0 ? '#${rank + 1}' : '')),
          SizedBox(
            width: 76,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(g.name(s), overflow: TextOverflow.ellipsis),
              if (special != null) Text(special, style: const TextStyle(fontSize: 10, color: Colors.purple)),
              if (foul && special == null) const Text('倒水', style: TextStyle(fontSize: 10, color: Colors.red)),
            ]),
          ),
          ...lanes,
          if (r != null) SizedBox(width: 40, child: cnDelta(((r['delta'] as List)[s] as num).toInt())),
          SizedBox(width: 50, child: Text('${scores[s]}分', textAlign: TextAlign.right)),
        ]),
      ),
    );
  }
}
