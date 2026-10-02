import 'package:aurora_shared/games/poker/ddz_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';

class DoudizhuBoard extends StatefulWidget {
  final GameContext g;
  const DoudizhuBoard(this.g, {super.key});
  @override
  State<DoudizhuBoard> createState() => _DoudizhuBoardState();
}

class _DoudizhuBoardState extends State<DoudizhuBoard> {
  final Set<int> _sel = {};
  String _handKey = '';
  int _hint = -1;
  String _hintKey = '';
  // drag selection
  final Set<int> _dragSeen = {};
  bool _dragMode = true;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<String> get hand => [for (final c in (v['hand'] as List? ?? const [])) '$c'];

  void _syncHand() {
    final k = hand.join(',');
    if (k != _handKey) {
      _handKey = k;
      _sel.clear();
      _hint = -1;
    }
    final hk = '$k|${v['tableSeat']}|${(v['tableCards'] as List?)?.join(',')}|${v['turn']}';
    if (hk != _hintKey) {
      _hintKey = hk;
      _hint = -1;
    }
  }

  Combo? get _tableCombo {
    if (v['lead'] == true) return null;
    final t = v['table'] as Map?;
    if (t == null) return null;
    return Combo('${t['type']}', t['key'] as int, t['len'] as int);
  }

  void _doHint() {
    final h = hand;
    final two = v['two'] == true;
    final cands = ddzCandidates([for (final c in h) ddzRank(c)], _tableCombo, two);
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有能管上的牌，请点不出'), duration: Duration(seconds: 1)));
      return;
    }
    _hint = (_hint + 1) % cands.length;
    final want = cands[_hint];
    final used = <int>{};
    for (final r in want) {
      for (var i = h.length - 1; i >= 0; i--) {
        if (!used.contains(i) && ddzRank(h[i]) == r) {
          used.add(i);
          break;
        }
      }
    }
    setState(() {
      _sel
        ..clear()
        ..addAll(used);
    });
  }

  String _bidText(Object? b) {
    if (b == null) return '';
    if (b is int) return b == 0 ? '不叫' : '$b分';
    return const {'call': '叫地主', 'grab': '抢地主', 'pass': '不叫', 'nograb': '不抢'}['$b'] ?? '';
  }

  Widget _cards(List cards, double w, {double maxW = double.infinity}) {
    if (cards.isEmpty) return const SizedBox();
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: OverlapRow(
        itemWidth: w,
        maxSpacing: 0.42,
        minSpacing: 0.18,
        children: [for (final c in cards) w < 40 ? _mini('$c', w) : PlayingCard('$c', width: w)],
      ),
    );
  }

  Widget _actView(int s, double w, {double maxW = 400}) {
    final acts = v['acts'] as List? ?? const [];
    final phase = v['phase'];
    final cs = Theme.of(context).colorScheme;
    if (phase == 'bid') {
      final t = _bidText((v['bids'] as List)[s]);
      if (t.isEmpty) return const SizedBox();
      return _chip(t, cs.tertiary);
    }
    if (phase == 'roundEnd' || phase == 'over') {
      final hs = v['hands'] as List?;
      if (hs == null || s == g.seat) return const SizedBox();
      return _cards(hs[s] as List, w * 0.8, maxW: maxW);
    }
    final a = s < acts.length ? acts[s] as Map? : null;
    if (a == null) return const SizedBox();
    if (a['pass'] == true) return _chip('不出', cs.outline);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _cards(a['cards'] as List, w, maxW: maxW),
      const SizedBox(height: 2),
      Text('${a['label']}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ]);
  }

  /// Small card rendered at a legible base size and scaled down (avoids face overflow).
  Widget _mini(String code, double w) => SizedBox(
        width: w,
        height: w * 1.4,
        child: FittedBox(child: PlayingCard(code, width: 48, faceDown: code == 'back')),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );

  Widget _playerPanel(int s, double w, double maxW) {
    final counts = (v['counts'] as List).cast<int>();
    final scores = (v['scores'] as List).cast<int>();
    final landlord = v['landlord'] as int;
    final turn = v['turn'] as int;
    final active = !g.over && (v['phase'] == 'bid' || v['phase'] == 'play') && turn == s;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(
        s,
        active: active,
        size: 32,
        sub: '剩${counts[s]}张 · ${scores[s]}分',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (landlord == s) _badge('地主', Colors.deepOrange) else if (landlord >= 0) _badge('农民', Colors.green),
          if (active) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.timer, size: 18, color: Colors.amber)),
        ]),
      ),
      const SizedBox(height: 4),
      _actView(s, w, maxW: maxW),
    ]);
  }

  Widget _badge(String t, Color c) => Container(
        margin: const EdgeInsets.only(left: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    _syncHand();
    final cs = Theme.of(context).colorScheme;
    final phase = '${v['phase']}';
    final turn = v['turn'] as int;
    final me = g.seat;
    final myTurn = me >= 0 && !g.over && turn == me && (phase == 'bid' || phase == 'play');
    final landlord = v['landlord'] as int;
    final bottom = v['bottom'] as List?;
    final others = g.seatsFromMe().where((s) => s != me).toList();

    String status;
    if (phase == 'bid') {
      status = myTurn ? (v['grab'] == true ? '轮到你叫/抢地主' : '轮到你叫分') : '等待 ${g.name(turn)} ${v['grab'] == true ? "叫地主" : "叫分"}';
    } else if (phase == 'play') {
      status = myTurn ? (v['lead'] == true ? '轮到你出牌（任意牌型）' : '轮到你出牌，管上或不出') : '等待 ${g.name(turn)} 出牌';
    } else if (phase == 'roundEnd') {
      status = '本局结束';
    } else {
      status = '比赛结束';
    }

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final wCard = (c.maxWidth / 13).clamp(34.0, 64.0).toDouble();
        final byH = (c.maxHeight / 7.5).clamp(34.0, 64.0).toDouble();
        final cw = wCard < byH ? wCard : byH;
        final small = cw * 0.72;
        final panelMax = (c.maxWidth / others.length - 12).clamp(120.0, 420.0).toDouble();
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            // top info line
            Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              _chip('第 ${(v['round'] as int) + (phase == 'roundEnd' || phase == 'over' ? 0 : 1)}/${v['rounds']} 局', cs.primary),
              _chip('倍数 ×${v['mult']}', Colors.deepOrange),
              if ((v['bombs'] as int) > 0) _chip('炸弹 ${v['bombs']}', Colors.redAccent),
              if (bottom != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('底牌 ', style: TextStyle(color: Colors.white70)),
                  for (final b in bottom)
                    Padding(padding: const EdgeInsets.only(right: 2), child: _mini('$b', small * 0.7)),
                ])
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('底牌 ', style: TextStyle(color: Colors.white70)),
                  for (var i = 0; i < (v['bottomCount'] as int); i++)
                    Padding(padding: const EdgeInsets.only(right: 2), child: _mini('back', small * 0.5)),
                ]),
            ]),
            const SizedBox(height: 6),
            // opponents
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: c.maxWidth,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final s in others)
                        Expanded(child: Center(child: _playerPanel(s, small, panelMax))),
                    ]),
                  ),
                ),
              ),
            ),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 6),
            if (me >= 0) ...[
              _myRow(cs, small, landlord),
              const SizedBox(height: 4),
              if (myTurn) _buttons(phase),
              const SizedBox(height: 4),
              _hand(cw, c.maxWidth - 16, myTurn && phase == 'play'),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase == 'roundEnd' || phase == 'over') Center(child: _result()),
        ]);
      }),
    );
  }

  Widget _myRow(ColorScheme cs, double small, int landlord) {
    final me = g.seat;
    final scores = (v['scores'] as List).cast<int>();
    final turn = v['turn'] as int;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
      g.tag(me,
          size: 30,
          active: !g.over && turn == me && (v['phase'] == 'bid' || v['phase'] == 'play'),
          sub: '${scores[me]}分',
          trailing: landlord == me ? _badge('地主', Colors.deepOrange) : (landlord >= 0 ? _badge('农民', Colors.green) : null)),
      _actView(me, small, maxW: 360),
    ]);
  }

  Widget _buttons(String phase) {
    final btns = <Widget>[];
    if (phase == 'bid') {
      if (v['grab'] == true) {
        final called = (v['bidder'] as int) >= 0;
        btns.add(FilledButton(onPressed: () => g.act({'type': 'bid', 'value': 1}), child: Text(called ? '抢地主' : '叫地主')));
        btns.add(OutlinedButton(onPressed: () => g.act({'type': 'bid', 'value': 0}), child: Text(called ? '不抢' : '不叫')));
      } else {
        final cur = v['bidValue'] as int;
        for (var i = 1; i <= 3; i++) {
          btns.add(FilledButton(onPressed: i > cur ? () => g.act({'type': 'bid', 'value': i}) : null, child: Text('$i分')));
        }
        btns.add(OutlinedButton(onPressed: () => g.act({'type': 'bid', 'value': 0}), child: const Text('不叫')));
      }
    } else {
      final lead = v['lead'] == true;
      btns.add(OutlinedButton(onPressed: lead ? null : () => g.act({'type': 'pass'}), child: const Text('不出')));
      btns.add(OutlinedButton(onPressed: _doHint, child: const Text('提示')));
      btns.add(FilledButton(
        onPressed: _sel.isEmpty
            ? null
            : () {
                final h = hand;
                g.act({'type': 'play', 'cards': [for (final i in _sel) if (i < h.length) h[i]]});
              },
        child: const Text('出牌'),
      ));
    }
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: btns);
  }

  Widget _hand(double cw, double maxW, bool interactive) {
    final h = hand;
    if (h.isEmpty) return SizedBox(height: cw * 1.4);
    final n = h.length;
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.18, cw * 0.62).toDouble();
    final total = cw + step * (n - 1);
    int idx(double x) => (x / step).floor().clamp(0, n - 1);
    void toggle(int i) => setState(() {
          if (!_sel.remove(i)) _sel.add(i);
        });
    return SizedBox(
      width: total,
      height: cw * 1.4 + cw * 0.3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => toggle(idx(d.localPosition.dx)),
        onHorizontalDragStart: (d) {
          final i = idx(d.localPosition.dx);
          _dragSeen
            ..clear()
            ..add(i);
          _dragMode = !_sel.contains(i);
          setState(() => _dragMode ? _sel.add(i) : _sel.remove(i));
        },
        onHorizontalDragUpdate: (d) {
          final i = idx(d.localPosition.dx);
          if (_dragSeen.add(i)) setState(() => _dragMode ? _sel.add(i) : _sel.remove(i));
        },
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: step * i,
              bottom: 0,
              child: PlayingCard(h[i], width: cw, selected: _sel.contains(i)),
            ),
        ]),
      ),
    );
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final scores = (v['scores'] as List).cast<int>();
    final over = v['phase'] == 'over';
    final me = g.seat;
    final ready = (v['ready'] as List?)?.cast<bool>();
    final title = r == null
        ? '比赛结束'
        : '${r['landlordWin'] == true ? "地主" : "农民"}获胜！${r['spring'] ?? ''}';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 夺冠' : title,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null)
            Text('叫分 ${r['bid']} · 炸弹 ${r['bombs']} · 倍数 ×${r['mult']}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 28, child: Text(over ? '#${k + 1}' : '')),
                SizedBox(width: 110, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                if (r != null)
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${((r['delta'] as List)[order[k]] as int) >= 0 ? "+" : ""}${(r['delta'] as List)[order[k]]}',
                      style: TextStyle(
                          color: ((r['delta'] as List)[order[k]] as int) >= 0 ? Colors.green : Colors.redAccent,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                SizedBox(width: 60, child: Text('${scores[order[k]]}分', textAlign: TextAlign.right)),
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
