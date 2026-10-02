import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'cn_widgets.dart';

class ZhajinhuaBoard extends StatefulWidget {
  final GameContext g;
  const ZhajinhuaBoard(this.g, {super.key});
  @override
  State<ZhajinhuaBoard> createState() => _ZhajinhuaBoardState();
}

class _ZhajinhuaBoardState extends State<ZhajinhuaBoard> {
  bool _picking = false; // choosing a compare target

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<bool> _bools(String k) => [for (final x in (v[k] as List? ?? const [])) x == true];

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final turn = (v['turn'] as num).toInt();
    final me = g.seat;
    final meInfo = v['me'] as Map?;
    final myTurn = me >= 0 && phase == 'bet' && turn == me && meInfo != null;
    if (!myTurn) _picking = false;
    String status;
    if (phase == 'bet') {
      if (_picking) {
        status = '选择一名玩家比牌（点对方头像）';
      } else if (myTurn) {
        status = '轮到你：跟注 ${meInfo['call']}${meInfo['canCompare'] == true ? '，或比牌' : ''}';
      } else {
        status = '等待 ${g.name(turn)} 行动';
      }
    } else {
      status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 7 : 14)).clamp(34.0, 70.0).toDouble();
        final byH = (c.maxHeight / 7).clamp(34.0, 70.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              cnPill('第 ${v['hand']}/${v['hands']} 局', Colors.indigo),
              cnPill('第 ${v['round']}/${v['cap']} 轮', Colors.teal),
              cnPill('单注 ${v['unit']}', Colors.deepOrange),
              if (v['r235'] == true) cnPill('235吃豹子', Colors.purple),
            ]),
            const SizedBox(height: 4),
            cnOpponents(others, (s) => _panel(s, w * 0.62), c.maxWidth),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.06, vertical: 4),
                child: CnFelt(felt: cnFeltColor(g, const Color(0xFF7B1F1F)), child: Center(child: _center())),
              ),
            ),
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            if (me >= 0) _mine(w, myTurn) else const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase != 'bet') Center(child: SingleChildScrollView(child: _result())),
        ]);
      }),
    );
  }

  String _state(int s) {
    final out = _bools('out'), folded = _bools('folded'), lost = _bools('lost'), seen = _bools('seen');
    if (out[s]) return '出局';
    if (lost[s]) return '比牌输';
    if (folded[s]) return '弃牌';
    return seen[s] ? '已看牌' : '闷牌';
  }

  Widget _panel(int s, double w) {
    final chips = cnInts(v, 'chips');
    final put = cnInts(v, 'put');
    final cards = cnStrs((v['cards'] as List)[s]);
    final active = v['phase'] == 'bet' && (v['turn'] as num).toInt() == s;
    final st = _state(s);
    final gone = st == '出局' || st == '弃牌' || st == '比牌输';
    final canTarget = _picking && !gone;
    final la = '${(v['lastAct'] as List)[s]}';
    Widget p = Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: active,
          size: 30,
          sub: '筹码 ${chips[s]}',
          trailing: (v['dealer'] as num).toInt() == s ? cnDisc('庄', Colors.orange.shade800) : null),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (cards.isNotEmpty) cnRow(cards, w, gap: 0.45, dim: gone),
        const SizedBox(width: 4),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          cnPill(st, gone ? Colors.grey : (st == '闷牌' ? Colors.deepPurple : Colors.teal), fontSize: 11),
          if (put[s] > 0) ...[const SizedBox(height: 2), cnPill('下注 ${put[s]}', Colors.black54, fontSize: 11)],
          if (la.isNotEmpty && !gone) ...[const SizedBox(height: 2), Text(la, style: const TextStyle(color: Colors.white70, fontSize: 11))],
        ]),
      ]),
    ]);
    if (canTarget) {
      p = GestureDetector(
        onTap: () {
          setState(() => _picking = false);
          g.act({'type': 'compare', 'target': s});
        },
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.amberAccent, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: p,
        ),
      );
    }
    return p;
  }

  Widget _center() {
    final lc = v['lastCompare'] as Map?;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.savings, color: Colors.amberAccent, size: 32),
          Text('底池 ${v['pot']}',
              style: const TextStyle(color: Colors.amberAccent, fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('闷牌 ${v['unit']} / 看牌 ${(v['unit'] as num) * 2}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (lc != null) ...[
            const SizedBox(height: 6),
            cnPill(
                '${g.name((lc['a'] as num).toInt())} vs ${g.name((lc['b'] as num).toInt())} → ${g.name((lc['winner'] as num).toInt())} 胜',
                Colors.black54),
          ],
        ]),
      ),
    );
  }

  Widget _mine(double w, bool myTurn) {
    final me = g.seat;
    final chips = cnInts(v, 'chips');
    final put = cnInts(v, 'put');
    final cards = cnStrs((v['cards'] as List)[me]);
    final info = v['me'] as Map?;
    final st = _state(me);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
        g.tag(me,
            active: myTurn,
            size: 28,
            sub: '筹码 ${chips[me]} · 已下 ${put[me]}',
            trailing: (v['dealer'] as num).toInt() == me ? cnDisc('庄', Colors.orange.shade800) : null),
        cnPill(st, Colors.teal),
        if (info?['hand'] != null) cnPill('${info!['hand']}', Colors.deepOrange),
      ]),
      const SizedBox(height: 4),
      if (cards.isNotEmpty)
        GestureDetector(
          onTap: info != null && info['seen'] != true ? () => g.act({'type': 'look'}) : null,
          child: cnRow(cards, w, gap: 0.8, dim: st == '弃牌' || st == '比牌输'),
        ),
      const SizedBox(height: 4),
      if (info != null) _buttons(info, myTurn),
    ]);
  }

  Widget _buttons(Map info, bool myTurn) {
    final raises = [for (final x in (info['raises'] as List? ?? const [])) (x as num).toInt()];
    final seen = info['seen'] == true;
    return Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
      if (!seen) OutlinedButton(onPressed: () => g.act({'type': 'look'}), child: const Text('看牌')),
      if (myTurn) ...[
        OutlinedButton(onPressed: () => g.act({'type': 'fold'}), child: const Text('弃牌')),
        FilledButton(
          onPressed: info['canCall'] == true ? () => g.act({'type': 'call'}) : null,
          child: Text('${seen ? '跟注' : '闷跟'} ${info['call']}'),
        ),
        if (raises.isNotEmpty)
          PopupMenuButton<int>(
            onSelected: (u) => g.act({'type': 'raise', 'unit': u}),
            itemBuilder: (_) => [
              for (final u in raises) PopupMenuItem(value: u, child: Text('加到 $u（需 ${seen ? u * 2 : u}）')),
            ],
            child: const Chip(avatar: Icon(Icons.add, size: 16), label: Text('加注')),
          ),
        FilledButton.tonal(
          onPressed: info['canCompare'] == true ? () => setState(() => _picking = !_picking) : null,
          child: Text(_picking ? '取消比牌' : '比牌 ${info['compare']}'),
        ),
      ],
    ]);
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final chips = cnInts(v, 'chips');
    final over = v['phase'] == 'over';
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => chips[b] - chips[a]);
    final winners = r == null ? <int>[] : [for (final x in r['winners'] as List) (x as num).toInt()];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 筹码最多' : '${winners.map(g.name).join('、')} 赢得底池 ${r?['pot'] ?? ''}',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null && r['showdown'] == true) const Text('达到封顶轮数，全员开牌', style: TextStyle(fontSize: 12)),
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 28, child: Text(over ? '#${k + 1}' : (winners.contains(order[k]) ? '★' : ''))),
                  SizedBox(width: 80, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                  if (r != null) ...[
                    cnRow(cnStrs((r['hands'] as List)[order[k]]), 24, gap: 0.7),
                    const SizedBox(width: 6),
                    SizedBox(width: 40, child: Text('${(r['names'] as List)[order[k]]}', style: const TextStyle(fontSize: 12))),
                    SizedBox(width: 48, child: cnDelta(((r['delta'] as List)[order[k]] as num).toInt())),
                  ],
                  SizedBox(width: 56, child: Text('${chips[order[k]]}', textAlign: TextAlign.right)),
                ]),
              ),
            ),
          cnContinue(g),
        ]),
      ),
    );
  }
}
