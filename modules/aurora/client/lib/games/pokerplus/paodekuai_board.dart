import 'package:aurora_shared/games/pokerplus/pdk_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'pp_widgets.dart';

class PaodekuaiBoard extends StatefulWidget {
  final GameContext g;
  const PaodekuaiBoard(this.g, {super.key});
  @override
  State<PaodekuaiBoard> createState() => _PaodekuaiBoardState();
}

class _PaodekuaiBoardState extends State<PaodekuaiBoard> {
  final Set<int> _sel = {};
  String _handKey = '';
  int _hint = -1;
  String _hintKey = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => [for (final c in (v['hand'] as List? ?? const [])) '$c'];
  List<int> _ints(String k) => [for (final x in (v[k] as List? ?? const [])) (x as num).toInt()];

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

  PdkCombo? get _table {
    final t = v['table'] as Map?;
    if (t == null) return null;
    return PdkCombo('${t['type']}', (t['key'] as num).toInt(), (t['len'] as num).toInt(), (t['n'] as num).toInt());
  }

  void _doHint() {
    final h = hand;
    var cands = pdkCandidates([for (final c in h) pdkRank(c)], _table, singleMax: v['singleMax'] == true);
    if (v['first'] == true) cands = [for (final c in cands) if (c.contains(3)) c];
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有能管上的牌'), duration: Duration(seconds: 1)));
      return;
    }
    _hint = (_hint + 1) % cands.length;
    final order = v['first'] == true ? ['3S', ...h.where((c) => c != '3S')] : h;
    final picked = pdkPick(order, cands[_hint]);
    final used = <int>{};
    for (final p in picked) {
      final i = h.indexOf(p);
      if (i >= 0) used.add(i);
    }
    setState(() {
      _sel
        ..clear()
        ..addAll(used);
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
    String status;
    if (phase == 'play') {
      if (myTurn) {
        status = v['first'] == true
            ? '你持有♠3，首出须包含♠3'
            : (lead ? '轮到你出牌（任意牌型）' : (v['must'] == true && v['canPass'] != true ? '有牌必须管！' : '轮到你出牌，管上或不要'));
      } else {
        status = '等待 ${g.name(turn)} 出牌';
      }
    } else {
      status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 9 : 15)).clamp(32.0, 62.0).toDouble();
        final byH = (c.maxHeight / 7.2).clamp(32.0, 62.0).toDouble();
        final w = cw < byH ? cw : byH;
        final small = w * 0.72;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              ppChip('第 ${v['round']}/${v['rounds']} 局', Colors.indigo),
              ppChip('${v['perHand']}张', Colors.teal),
              ppChip(v['must'] == true ? '必须管' : '可不管', Colors.deepOrange),
              if (v['singleMax'] == true && myTurn) ppChip('下家报单：单张须出最大', Colors.redAccent),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final s in others)
                  Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: _panel(s, small))),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.06, vertical: 4),
                child: FeltTable(
                  felt: Color.lerp(g.table, const Color(0xFF0B6B3A), 0.45)!,
                  child: Center(child: _center(w)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) ...[
              Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                g.tag(me, active: myTurn, size: 30, sub: '${_ints('scores')[me]}分'),
                if (phase == 'play' && ((v['acts'] as List)[me] as Map?)?['pass'] == true) ppChip('要不起', Colors.blueGrey),
              ]),
              const SizedBox(height: 4),
              if (myTurn) _buttons(lead),
              const SizedBox(height: 4),
              _hand(w, c.maxWidth - 16, myTurn),
            ] else
              const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase != 'play') Center(child: _result()),
        ]);
      }),
    );
  }

  Widget _panel(int s, double w) {
    final counts = _ints('counts');
    final scores = _ints('scores');
    final active = v['phase'] == 'play' && (v['turn'] as num).toInt() == s;
    final alarm = counts[s] == 1;
    final acts = v['acts'] as List;
    final a = v['phase'] == 'play' ? acts[s] as Map? : null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: active,
          size: 32,
          sub: '剩${counts[s]}张 · ${scores[s]}分',
          trailing: alarm ? ppChip('报单', Colors.redAccent, fontSize: 11) : null),
      const SizedBox(height: 4),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (counts[s] > 0)
          SizedBox(
            width: w * 0.6 + (counts[s].clamp(1, 16) - 1) * 3.0,
            height: w * 0.84,
            child: Stack(children: [
              for (var i = 0; i < counts[s].clamp(1, 16); i++) Positioned(left: i * 3.0, child: ppCard('back', w * 0.6)),
            ]),
          ),
        const SizedBox(width: 6),
        if (a != null && a['pass'] == true) ppChip('要不起', Colors.blueGrey),
        if (a != null && a['pass'] != true) ppChip('出 ${a['label']}', Colors.teal),
      ]),
    ]);
  }

  /// Middle of the table: the current trick (or everyone's leftover cards after a round).
  Widget _center(double w) {
    final phase = v['phase'];
    if (phase != 'play') {
      final hs = v['hands'] as List?;
      if (hs == null) return const SizedBox();
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var s = 0; s < g.players; s++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 80, child: Text(g.name(s), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
                if ((hs[s] as List).isEmpty) ppChip('出完', Colors.green),
                for (final c in hs[s] as List) Padding(padding: const EdgeInsets.only(right: 1), child: ppCard('$c', w * 0.55)),
              ]),
            ),
        ]),
      );
    }
    final ts = (v['tableSeat'] as num).toInt();
    final cards = [for (final c in (v['tableCards'] as List? ?? const [])) '$c'];
    if (v['lead'] == true || cards.isEmpty) {
      return Text(v['first'] == true ? '持♠3者先出' : '${g.name((v['turn'] as num).toInt())} 自由出牌',
          style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.bold));
    }
    final t = v['table'] as Map;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _row(cards, w * 0.9, 600),
        const SizedBox(height: 4),
        ppChip('${g.name(ts)} · ${t['label']}', Colors.black54, fontSize: 13),
      ]),
    );
  }

  Widget _row(List<String> cards, double w, double maxW) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: OverlapRow(itemWidth: w, maxSpacing: 0.42, minSpacing: 0.18, children: [for (final c in cards) ppCard(c, w)]),
      );

  Widget _buttons(bool lead) {
    final canPass = v['canPass'] == true;
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: [
      OutlinedButton(onPressed: canPass ? () => g.act({'type': 'pass'}) : null, child: const Text('不要')),
      OutlinedButton(onPressed: _doHint, child: const Text('提示')),
      FilledButton(
        onPressed: _sel.isEmpty
            ? null
            : () {
                final h = hand;
                g.act({'type': 'play', 'cards': [for (final i in _sel) if (i < h.length) h[i]]});
              },
        child: const Text('出牌'),
      ),
    ]);
  }

  Widget _hand(double cw, double maxW, bool interactive) {
    final h = hand;
    if (h.isEmpty) return SizedBox(height: cw * 1.4);
    final n = h.length;
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.2, cw * 0.62).toDouble();
    final total = cw + step * (n - 1);
    int idx(double x) => (x / step).floor().clamp(0, n - 1);
    return SizedBox(
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
        ]),
      ),
    );
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final scores = _ints('scores');
    final over = v['phase'] == 'over';
    final me = g.seat;
    final ready = (v['ready'] as List?)?.map((e) => e == true).toList();
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    final winner = r == null ? -1 : (r['winner'] as num).toInt();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 夺冠' : '${g.name(winner)} 先出完！',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null && (r['bombs'] as num) > 0) Text('本局炸弹 ${r['bombs']} 个', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 28, child: Text(over ? '#${k + 1}' : '')),
                SizedBox(width: 100, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                if (r != null) ...[
                  SizedBox(
                    width: 64,
                    child: Text(
                      '剩${(r['left'] as List)[order[k]]}${(r['closed'] as List)[order[k]] == true ? " 关门" : ""}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Builder(builder: (_) {
                      final d = ((r['delta'] as List)[order[k]] as num).toInt();
                      return Text(d >= 0 ? '+$d' : '$d',
                          style: TextStyle(color: d >= 0 ? Colors.green : Colors.redAccent, fontWeight: FontWeight.bold));
                    }),
                  ),
                ],
                SizedBox(width: 56, child: Text('${scores[order[k]]}分', textAlign: TextAlign.right)),
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
