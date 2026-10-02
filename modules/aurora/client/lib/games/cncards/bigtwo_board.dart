import 'package:aurora_shared/games/cncards/bigtwo_rules.dart';
import 'package:aurora_shared/games/cncards/cards.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'cn_widgets.dart';

class BigTwoBoard extends StatefulWidget {
  final GameContext g;
  const BigTwoBoard(this.g, {super.key});
  @override
  State<BigTwoBoard> createState() => _BigTwoBoardState();
}

class _BigTwoBoardState extends State<BigTwoBoard> {
  final Set<int> _sel = {};
  String _handKey = '';
  int _hint = -1;
  String _hintKey = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => cnStrs(v['hand']);

  void _sync() {
    final k = hand.join(',');
    if (k != _handKey) {
      _handKey = k;
      _sel.clear();
    }
    final hk = '$k|${v['tableSeat']}|${(v['tableCards'] as List?)?.join(',')}|${v['turn']}';
    if (hk != _hintKey) {
      _hintKey = hk;
      _hint = -1;
    }
  }

  B2Combo? get _table {
    final t = v['table'] as Map?;
    return t == null ? null : B2Combo.fromJson(t);
  }

  void _doHint() {
    final h = hand;
    final cands = b2Hints(h, _table, mustInclude: v['mustInclude'] as String?);
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有能管上的牌'), duration: Duration(seconds: 1)));
      return;
    }
    _hint = (_hint + 1) % cands.length;
    setState(() {
      _sel
        ..clear()
        ..addAll([for (final c in cands[_hint]) h.indexOf(c)]);
    });
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final phase = '${v['phase']}';
    final turn = (v['turn'] as num).toInt();
    final me = g.seat;
    final myTurn = me >= 0 && phase == 'play' && turn == me;
    final lead = v['lead'] == true;
    final must = v['mustInclude'] as String?;
    String status;
    if (phase == 'play') {
      if (myTurn) {
        status = must != null
            ? '你先出，首手须包含${cnCardName(must)}'
            : (lead ? '轮到你出牌（任意牌型）' : '轮到你：出${_table?.len ?? 1}张管上，或选择不要');
      } else {
        status = '等待 ${g.name(turn)} 出牌';
      }
    } else {
      status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    final scores = cnInts(v, 'scores');
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 8.5 : 16)).clamp(30.0, 62.0).toDouble();
        final byH = (c.maxHeight / 7.2).clamp(30.0, 62.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              cnPill('锄大地 第 ${v['round']}/${v['rounds']} 局', Colors.indigo),
              if (_table != null) cnPill('当前：${_table!.label}', Colors.teal),
            ]),
            const SizedBox(height: 4),
            cnOpponents(others, (s) => _panel(s, w * 0.72), c.maxWidth),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.05, vertical: 2),
                child: CnFelt(felt: cnFeltColor(g), child: Center(child: _center(w))),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                g.tag(me, active: myTurn, size: 28, sub: '${scores[me]}分'),
                if (phase == 'play' && ((v['acts'] as List)[me] as Map?)?['pass'] == true) cnPill('不要', Colors.blueGrey),
              ]),
              const SizedBox(height: 4),
              if (myTurn) _buttons(lead),
              const SizedBox(height: 4),
              _hand(w, c.maxWidth - 16),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase != 'play') Center(child: SingleChildScrollView(child: _result(w))),
        ]);
      }),
    );
  }

  Widget _panel(int s, double w) {
    final counts = cnInts(v, 'counts');
    final scores = cnInts(v, 'scores');
    final active = v['phase'] == 'play' && (v['turn'] as num).toInt() == s;
    final a = v['phase'] == 'play' ? (v['acts'] as List)[s] as Map? : null;
    final n = counts[s];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: active,
          size: 30,
          sub: '剩$n张 · ${scores[s]}分',
          trailing: n == 1 ? cnPill('报单', Colors.redAccent, fontSize: 11) : null),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (n > 0)
          SizedBox(
            width: w * 0.6 + (n.clamp(1, 13) - 1) * 3.0,
            height: w * 0.84,
            child: Stack(children: [
              for (var i = 0; i < n.clamp(1, 13); i++) Positioned(left: i * 3.0, child: cnCard('back', w * 0.6)),
            ]),
          ),
        const SizedBox(width: 6),
        if (a != null && a['pass'] == true) cnPill('不要', Colors.blueGrey),
        if (a != null && a['pass'] != true) cnPill('${a['label']}', Colors.teal),
      ]),
    ]);
  }

  Widget _center(double w) {
    if (v['phase'] != 'play') return const SizedBox();
    final ts = (v['tableSeat'] as num).toInt();
    final cards = cnStrs(v['tableCards']);
    if (v['lead'] == true || cards.isEmpty) {
      final must = v['mustInclude'] as String?;
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          must != null
              ? '${g.name((v['turn'] as num).toInt())} 持${cnCardName(must)}先出'
              : '${g.name((v['turn'] as num).toInt())} 自由出牌',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          cnRow(cards, w * 0.95, gap: 0.5),
          const SizedBox(height: 4),
          cnPill('${g.name(ts)} · ${_table?.label ?? ''}', Colors.black54, fontSize: 13),
        ]),
      ),
    );
  }

  Widget _buttons(bool lead) {
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
      OutlinedButton(onPressed: lead ? null : () => g.act({'type': 'pass'}), child: const Text('不要')),
      OutlinedButton(onPressed: _doHint, child: const Text('提示')),
      if (_sel.isNotEmpty)
        OutlinedButton(onPressed: () => setState(_sel.clear), child: const Text('重选')),
      FilledButton(
        onPressed: _sel.isEmpty
            ? null
            : () {
                final h = hand;
                g.act({'type': 'play', 'cards': [for (final i in _sel) if (i >= 0 && i < h.length) h[i]]});
              },
        child: const Text('出牌'),
      ),
    ]);
  }

  Widget _hand(double cw, double maxW) {
    final h = hand;
    if (h.isEmpty) return SizedBox(height: cw * 1.4 + cw * 0.3);
    final n = h.length;
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.2, cw * 0.62).toDouble();
    final total = cw + step * (n - 1);
    int idx(double x) => (x / step).floor().clamp(0, n - 1);
    final selLabel = _sel.isEmpty ? null : b2Classify([for (final i in _sel) if (i >= 0 && i < n) h[i]])?.label;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: total,
        height: cw * 1.4 + cw * 0.3,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => setState(() {
            final i = idx(d.localPosition.dx);
            if (!_sel.remove(i)) _sel.add(i);
          }),
          child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < n; i++)
              Positioned(left: step * i, bottom: 0, child: PlayingCard(h[i], width: cw, selected: _sel.contains(i))),
            if (selLabel != null)
              Positioned(right: 0, top: 0, child: cnPill(selLabel, Colors.deepPurple, fontSize: 11)),
          ]),
        ),
      ),
    ]);
  }

  Widget _result(double w) {
    final r = v['result'] as Map?;
    final scores = cnInts(v, 'scores');
    final over = v['phase'] == 'over';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    final winner = r == null ? -1 : (r['winner'] as num).toInt();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 夺冠' : '${g.name(winner)} 先出完！',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 28, child: Text(over ? '#${k + 1}' : '')),
                  SizedBox(width: 84, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                  if (r != null) ...[
                    SizedBox(width: 50, child: Text('剩${(r['left'] as List)[order[k]]}张', style: const TextStyle(fontSize: 12))),
                    SizedBox(width: 44, child: cnDelta(((r['delta'] as List)[order[k]] as num).toInt())),
                  ],
                  SizedBox(width: 56, child: Text('${scores[order[k]]}分', textAlign: TextAlign.right)),
                  if (r != null) ...[
                    const SizedBox(width: 8),
                    cnRow(cnStrs((r['hands'] as List)[order[k]]), 22, gap: 0.45),
                  ],
                ]),
              ),
            ),
          cnContinue(g),
        ]),
      ),
    );
  }
}
