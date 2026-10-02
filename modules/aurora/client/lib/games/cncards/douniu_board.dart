import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'cn_widgets.dart';

class DouniuBoard extends StatelessWidget {
  final GameContext g;
  const DouniuBoard(this.g, {super.key});

  Map<String, dynamic> get v => g.view;

  @override
  Widget build(BuildContext context) {
    final phase = '${v['phase']}';
    final me = g.seat;
    final banker = (v['banker'] as num).toInt();
    final grab = cnInts(v, 'grab');
    final bets = cnInts(v, 'bets');
    final shown = [for (final x in v['shown'] as List) x == true];
    String status;
    bool mine = false;
    switch (phase) {
      case 'grab':
        mine = me >= 0 && grab[me] == -1;
        status = mine ? '选择抢庄倍数' : '等待其他玩家抢庄…';
        break;
      case 'bet':
        mine = me >= 0 && me != banker && bets[me] == 0;
        status = me == banker ? '你是庄家，等待闲家下注' : (mine ? '选择下注倍数' : '等待其他玩家下注…');
        break;
      case 'show':
        mine = me >= 0 && !shown[me];
        status = mine ? '查看手牌，点击摊牌' : '等待其他玩家摊牌…';
        break;
      default:
        status = phase == 'over' ? '比赛结束' : '本局结束';
    }
    final others = g.seatsFromMe().where((s) => s != me).toList();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / (c.maxWidth < 600 ? 7.5 : 15)).clamp(32.0, 66.0).toDouble();
        final byH = (c.maxHeight / 7.2).clamp(32.0, 66.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
              cnPill('第 ${v['hand']}/${v['hands']} 局', Colors.indigo),
              cnPill(v['bankerMode'] == 'grab' ? (v['mingpai'] == true ? '明牌抢庄' : '自由抢庄') : '轮流坐庄', Colors.teal),
              cnPill(v['pay'] == 'high' ? '疯狂赔率' : '经典赔率', Colors.deepOrange),
              if (banker >= 0 && (v['bankerMult'] as num) > 1) cnPill('庄 ×${v['bankerMult']}', Colors.orange.shade800),
            ]),
            const SizedBox(height: 4),
            cnOpponents(others, (s) => _panel(s, w * 0.55), c.maxWidth),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: c.maxWidth * 0.06, vertical: 4),
                child: CnFelt(felt: cnFeltColor(g, const Color(0xFF0D47A1)), child: Center(child: _center(phase, banker))),
              ),
            ),
            StatusBar(status, highlight: mine),
            const SizedBox(height: 4),
            if (me >= 0) _mine(w, phase, banker) else const SizedBox(height: 20),
            const SizedBox(height: 8),
          ]),
          if (phase == 'handEnd' || phase == 'over') Center(child: SingleChildScrollView(child: _result())),
        ]);
      }),
    );
  }

  Widget _info(int s, String phase, int banker) {
    final grab = cnInts(v, 'grab');
    final bets = cnInts(v, 'bets');
    if (phase == 'grab') {
      final gv = grab[s];
      if (gv == -1) return cnPill('思考中', Colors.grey, fontSize: 11);
      if (gv == -2) return cnPill('已选择', Colors.blueGrey, fontSize: 11);
      return cnPill(gv == 0 ? '不抢' : '抢 ×$gv', gv == 0 ? Colors.blueGrey : Colors.orange.shade800, fontSize: 11);
    }
    if (s == banker) return cnPill('庄家', Colors.orange.shade800, fontSize: 11);
    return bets[s] > 0 ? cnPill('下注 ×${bets[s]}', Colors.deepPurple, fontSize: 11) : cnPill('下注中', Colors.grey, fontSize: 11);
  }

  Widget _panel(int s, double w) {
    final phase = '${v['phase']}';
    final banker = (v['banker'] as num).toInt();
    final scores = cnInts(v, 'scores');
    final cards = cnStrs((v['cards'] as List)[s]);
    final ev = (v['evals'] as List)[s] as Map?;
    final three = ev == null ? <int>{} : {for (final x in ev['three'] as List) (x as num).toInt()};
    final waiting = g.players > 0 && _waiting(s, phase, banker);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: waiting,
          size: 30,
          sub: '${scores[s]}分',
          trailing: s == banker ? cnDisc('庄', Colors.orange.shade800) : null),
      const SizedBox(height: 3),
      cnRow(cards, w, gap: 0.42, hi: three),
      const SizedBox(height: 3),
      Row(mainAxisSize: MainAxisSize.min, children: [
        _info(s, phase, banker),
        if (ev != null) ...[const SizedBox(width: 4), cnPill('${ev['name']}', _lvColor((ev['level'] as num).toInt()), fontSize: 11)],
      ]),
    ]);
  }

  bool _waiting(int s, String phase, int banker) {
    switch (phase) {
      case 'grab':
        return cnInts(v, 'grab')[s] == -1;
      case 'bet':
        return s != banker && cnInts(v, 'bets')[s] == 0;
      case 'show':
        return (v['shown'] as List)[s] != true;
    }
    return false;
  }

  Color _lvColor(int lv) {
    if (lv >= 11) return Colors.purple;
    if (lv == 10) return Colors.red.shade700;
    if (lv >= 7) return Colors.deepOrange;
    if (lv >= 1) return Colors.teal;
    return Colors.blueGrey;
  }

  Widget _center(String phase, int banker) {
    final pay = v['pay'] == 'high';
    final table = pay
        ? '没牛/牛一 ×1 · 牛几 ×几 · 牛牛及特殊 ×10'
        : '牛一~牛六 ×1 · 牛七~牛九 ×2 · 牛牛 ×3\n五花牛 ×4 · 炸弹牛 ×5 · 五小牛 ×6';
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('斗 牛', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 6)),
          if (banker >= 0) Text('庄家：${g.name(banker)}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(table, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _mine(double w, String phase, int banker) {
    final me = g.seat;
    final scores = cnInts(v, 'scores');
    final cards = cnStrs((v['cards'] as List)[me]);
    final ev = (v['evals'] as List)[me] as Map?;
    final three = ev == null ? <int>{} : {for (final x in ev['three'] as List) (x as num).toInt()};
    final grab = cnInts(v, 'grab');
    final bets = cnInts(v, 'bets');
    final shown = (v['shown'] as List)[me] == true;
    Widget buttons = const SizedBox();
    if (phase == 'grab' && grab[me] == -1) {
      buttons = Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
        OutlinedButton(onPressed: () => g.act({'type': 'grab', 'mult': 0}), child: const Text('不抢')),
        for (var m = 1; m <= 4; m++) FilledButton.tonal(onPressed: () => g.act({'type': 'grab', 'mult': m}), child: Text('抢×$m')),
      ]);
    } else if (phase == 'bet' && me != banker && bets[me] == 0) {
      buttons = Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
        for (final m in const [1, 2, 3, 5]) FilledButton.tonal(onPressed: () => g.act({'type': 'bet', 'mult': m}), child: Text('×$m')),
      ]);
    } else if (phase == 'show' && !shown) {
      buttons = FilledButton.icon(onPressed: () => g.act({'type': 'show'}), icon: const Icon(Icons.flip), label: const Text('摊牌'));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
        g.tag(me, size: 28, sub: '${scores[me]}分', trailing: me == banker ? cnDisc('庄', Colors.orange.shade800) : null),
        if (phase != 'handEnd' && phase != 'over') _info(me, phase, banker),
        if (ev != null) cnPill('${ev['name']} · ×${ev['mult']}', _lvColor((ev['level'] as num).toInt())),
      ]),
      const SizedBox(height: 4),
      cnRow(cards, w, gap: 0.9, hi: three),
      const SizedBox(height: 6),
      buttons,
    ]);
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final scores = cnInts(v, 'scores');
    final over = v['phase'] == 'over';
    final banker = (v['banker'] as num).toInt();
    final order = List.generate(g.players, (i) => i);
    if (over) order.sort((a, b) => scores[b] - scores[a]);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: ResultBanner(
        over ? '比赛结束 · ${g.name(order.first)} 积分最高' : '第 ${v['hand']} 局结算',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < order.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 28, child: order[k] == banker ? cnDisc('庄', Colors.orange.shade800) : Text(over ? '#${k + 1}' : '')),
                  SizedBox(width: 80, child: Text(g.name(order[k]), overflow: TextOverflow.ellipsis)),
                  if (r != null) ...[
                    cnRow(cnStrs((v['cards'] as List)[order[k]]), 22, gap: 0.6,
                        hi: {for (final x in (r['three'] as List)[order[k]] as List) (x as num).toInt()}),
                    const SizedBox(width: 6),
                    SizedBox(width: 48, child: Text('${(r['names'] as List)[order[k]]}', style: const TextStyle(fontSize: 12))),
                    SizedBox(width: 44, child: cnDelta(((r['delta'] as List)[order[k]] as num).toInt())),
                  ],
                  SizedBox(width: 52, child: Text('${scores[order[k]]}分', textAlign: TextAlign.right)),
                ]),
              ),
            ),
          cnContinue(g),
        ]),
      ),
    );
  }
}
