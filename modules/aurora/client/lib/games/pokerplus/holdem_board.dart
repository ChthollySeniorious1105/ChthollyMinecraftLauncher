import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'pp_widgets.dart';

class HoldemBoard extends StatefulWidget {
  final GameContext g;
  const HoldemBoard(this.g, {super.key});
  @override
  State<HoldemBoard> createState() => _HoldemBoardState();
}

class _HoldemBoardState extends State<HoldemBoard> {
  double? _raise;
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  List<int> _ints(String k) => [for (final x in (v[k] as List? ?? const [])) (x as num).toInt()];
  List<bool> _bools(String k) => [for (final x in (v[k] as List? ?? const [])) x == true];

  static const _streets = {'preflop': '翻牌前', 'flop': '翻牌', 'turn': '转牌', 'river': '河牌', 'showdown': '摊牌'};

  @override
  Widget build(BuildContext context) {
    final me = v['me'] as Map?;
    final k = '${v['hand']}|${v['street']}|${v['turn']}|${me?['minTo']}';
    if (k != _key) {
      _key = k;
      _raise = null;
    }
    final phase = '${v['phase']}';
    final turn = (v['turn'] as num).toInt();
    final myTurn = g.seat >= 0 && turn == g.seat && me != null && phase == 'bet';
    String status;
    if (phase == 'over') {
      status = '比赛结束';
    } else if (phase == 'handEnd') {
      status = '第 ${v['hand']} 手结束';
    } else if (myTurn) {
      status = '轮到你行动';
    } else {
      status = turn >= 0 ? '等待 ${g.name(turn)} 行动' : '发牌中…';
    }
    final limit = (v['handsLimit'] as num).toInt();
    final next = (v['nextLevel'] as num).toInt();
    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final compact = c.maxHeight < 500;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 4),
            Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ppChip('第 ${v['hand']}${limit > 0 ? "/$limit" : ""} 手', Colors.indigo),
              ppChip('盲注 ${v['sb']}/${v['bb']}', Colors.deepOrange),
              if (next > 0) ppChip('$next 手后升盲', Colors.brown),
              ppChip(_streets['${v['street']}'] ?? '', Colors.teal),
              StatusBar(status, highlight: myTurn),
            ]),
            Expanded(child: _table(c.maxWidth, compact)),
            if (myTurn) _actionBar(me, compact) else SizedBox(height: compact ? 4 : 8),
          ]),
          if (phase == 'over') Center(child: _final()),
        ]);
      }),
    );
  }

  Widget _table(double fullW, bool compact) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final n = g.players;
      final order = g.seatsFromMe();
      final seatW = min(118.0, max(78.0, w / (n > 6 ? 5.2 : 4.2)));
      final seatH = compact ? 62.0 : 84.0;
      final cx = w / 2, cy = h / 2;
      final rx = max(40.0, w / 2 - seatW / 2 - 4);
      final ry = max(30.0, h / 2 - seatH / 2 - 4);
      final tableRect = Rect.fromCenter(center: Offset(cx, cy), width: rx * 2 - seatW * 0.2, height: ry * 2 - seatH * 0.3);
      final free = n > 2 ? min(tableRect.width - 40, w - 2 * seatW - 8) : tableRect.width - 40;
      final boardW = min(free / 5.6, (tableRect.height * 0.42) / 1.4).clamp(22.0, 60.0).toDouble();
      final myW = min(170.0, max(seatW, w * 0.36)), myH = compact ? 78.0 : 118.0;
      final stacks = _ints('stacks'), bets = _ints('bets');
      final children = <Widget>[
        Positioned.fromRect(rect: tableRect, child: FeltTable(felt: Color.lerp(g.table, const Color(0xFF0B6B3A), 0.55)!)),
        Positioned(
          left: tableRect.left,
          width: tableRect.width,
          top: tableRect.top,
          height: tableRect.height,
          child: Center(child: _center(boardW)),
        ),
      ];
      for (var i = 0; i < n; i++) {
        final s = order[i];
        final ang = pi / 2 + 2 * pi * i / n;
        final px = cx + rx * cos(ang), py = cy + ry * sin(ang);
        final sw = i == 0 ? myW : seatW, sh = i == 0 ? myH : seatH;
        children.add(Positioned(
          left: px - sw / 2,
          top: i == 0 ? h - sh : py - sh / 2,
          width: sw,
          height: sh,
          child: _seat(s, sw, sh, stacks[s]),
        ));
        if (bets[s] > 0) {
          final bx = cx + (px - cx) * 0.58, by = cy + (py - cy) * 0.55;
          children.add(Positioned(
            left: bx - 40,
            top: by - 11,
            width: 80,
            height: 22,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: ChipStack(bets[s], size: 15))),
          ));
        }
        if ((v['dealer'] as num).toInt() == s) {
          final dx = cx + (px - cx) * 0.75 + (i == 0 ? seatW * 0.45 : 0), dy = cy + (py - cy) * 0.72;
          children.add(Positioned(left: dx - 10, top: dy - 10, child: ppDisc('D', Colors.white, Colors.black87)));
        }
      }
      return Stack(clipBehavior: Clip.none, children: children);
    });
  }

  Widget _center(double cw) {
    final board = [for (final c in (v['board'] as List? ?? const [])) '$c'];
    final res = v['result'] as Map?;
    final best = <String>{};
    if (res != null && res['type'] == 'showdown') {
      final pots = res['pots'] as List;
      final bests = res['best'] as List;
      for (final w in ((pots.first as Map)['winners'] as List)) {
        best.addAll([for (final c in bests[(w as num).toInt()] as List) '$c']);
      }
    }
    final pots = _ints('pots');
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: cw * 0.05),
              child: i < board.length ? ppCard(board[i], cw, highlight: best.contains(board[i])) : ppSlot(cw),
            ),
        ]),
        const SizedBox(height: 6),
        if (res != null)
          _resultLine(res)
        else
          Wrap(spacing: 6, children: [
            Text('底池 ${v['pot']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            if (pots.length > 1)
              for (var i = 0; i < pots.length; i++)
                Text(i == 0 ? '主池 ${pots[i]}' : '边池$i ${pots[i]}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
      ]),
    );
  }

  Widget _resultLine(Map res) {
    final lines = <String>[];
    final pots = res['pots'] as List;
    for (var i = 0; i < pots.length; i++) {
      final p = pots[i] as Map;
      final ws = [for (final w in p['winners'] as List) g.name((w as num).toInt())].join('、');
      final what = pots.length == 1 ? '底池' : (i == 0 ? '主池' : '边池$i');
      lines.add(res['type'] == 'fold' ? '$ws 赢得$what ${p['amount']}' : '$ws 以「${p['hand']}」赢得$what ${p['amount']}');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final l in lines) Text(l, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
      ]),
    );
  }

  Widget _seat(int s, double w, double h, int stack) {
    final cs = Theme.of(context).colorScheme;
    final out = _bools('out'), folded = _bools('folded'), allIn = _bools('allIn');
    final holes = v['holes'] as List;
    final cards = [for (final c in holes[s] as List) '$c'];
    final turn = (v['turn'] as num).toInt();
    final active = turn == s && v['phase'] == 'bet';
    final act = '${(v['lastAct'] as List)[s]}';
    final res = v['result'] as Map?;
    String? handName;
    var won = false;
    if (res != null) {
      handName = (res['hands'] as List)[s] as String?;
      won = ((res['delta'] as List)[s] as num) > 0;
    }
    final isMe = s == g.seat;
    final cw = isMe ? min(w * 0.3, h * 0.42) : min(w * 0.3, h * 0.36);
    final bestSet = res != null && res['type'] == 'showdown' ? {for (final c in (res['best'] as List)[s] as List) '$c'} : <String>{};
    String badge = '';
    if (s == (v['sbSeat'] as num).toInt() && v['street'] == 'preflop') badge = '小盲';
    if (s == (v['bbSeat'] as num).toInt() && v['street'] == 'preflop') badge = '大盲';
    final label = out[s]
        ? '已出局'
        : handName ?? (allIn[s] ? '全下' : (act.isNotEmpty ? act : badge));
    return Opacity(
      opacity: out[s] ? 0.4 : (folded[s] && res == null ? 0.6 : 1),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          width: w,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: (active ? cs.primary : Colors.black).withValues(alpha: active ? 0.5 : 0.38),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: won ? Colors.amberAccent : (active ? cs.primary : Colors.white24), width: won || active ? 2 : 1),
            boxShadow: active ? [BoxShadow(color: cs.primary.withValues(alpha: 0.6), blurRadius: 10)] : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (cards.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (final c in cards)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: ppCard(c, cw, highlight: bestSet.contains(c))),
              ])
            else
              SizedBox(height: cw * 0.6),
            const SizedBox(height: 2),
            Text(g.name(s),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            Text('筹码 $stack', style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            if (label.isNotEmpty)
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: handName != null ? Colors.lightGreenAccent : Colors.white70, fontSize: 11)),
            if (isMe && v['myHand'] != null && res == null)
              Text('${v['myHand']}', style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _actionBar(Map me, bool compact) {
    final toCall = (me['toCall'] as num).toInt();
    final minTo = (me['minTo'] as num).toInt();
    final maxTo = (me['maxTo'] as num).toInt();
    final myBet = (me['bet'] as num).toInt();
    final canRaise = me['canRaise'] == true;
    final pot = (v['pot'] as num).toInt();
    final curBet = myBet + toCall;
    final lo = min(minTo, maxTo).toDouble(), hi = maxTo.toDouble();
    final val = (_raise ?? lo).clamp(lo, hi).toDouble();
    int potTo(double frac) => min(maxTo, max(minTo, curBet + ((pot + toCall) * frac).round()));
    final isBet = curBet == 0;
    final raiseLabel = val >= hi ? '全下 $maxTo' : (isBet ? '下注 ${val.round()}' : '加注到 ${val.round()}');
    final buttons = Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: [
      OutlinedButton(
        style: OutlinedButton.styleFrom(backgroundColor: Colors.black26, foregroundColor: Colors.white),
        onPressed: () => g.act({'type': 'fold'}),
        child: const Text('弃牌'),
      ),
      FilledButton.tonal(
        onPressed: () => g.act({'type': toCall > 0 ? 'call' : 'check'}),
        child: Text(toCall > 0 ? (toCall >= maxTo - myBet ? '全下跟注 $toCall' : '跟注 $toCall') : '过牌'),
      ),
      if (canRaise)
        FilledButton(
          onPressed: () => g.act(val >= hi ? {'type': 'allin'} : {'type': 'raise', 'to': val.round()}),
          child: Text(raiseLabel),
        ),
    ]);
    if (!canRaise) return Padding(padding: const EdgeInsets.all(6), child: buttons);
    final presets = Wrap(spacing: 4, children: [
      for (final (t, f) in [('½池', 0.5), ('池', 1.0)])
        ActionChip(
          visualDensity: VisualDensity.compact,
          label: Text(t),
          onPressed: () => setState(() => _raise = potTo(f).toDouble()),
        ),
      ActionChip(visualDensity: VisualDensity.compact, label: const Text('全下'), onPressed: () => setState(() => _raise = hi)),
    ]);
    return Container(
      margin: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
      ),
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (hi > lo)
          Row(children: [
            Text('${lo.round()}', style: const TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                value: val,
                min: lo,
                max: hi,
                onChanged: (x) => setState(() => _raise = x.roundToDouble()),
              ),
            ),
            Text('$maxTo', style: const TextStyle(fontSize: 11)),
          ]),
        Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 2, children: [
          if (hi > lo) presets,
          buttons,
        ]),
      ]),
    );
  }

  Widget _final() {
    final ranking = _ints('ranking');
    final stacks = _ints('stacks');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: ResultBanner(
        ranking.isEmpty ? '比赛结束' : '${g.name(ranking.first)} 获胜！',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < ranking.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 30, child: Text('#${i + 1}')),
                SizedBox(width: 120, child: Text(g.name(ranking[i]), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 70, child: Text('${stacks[ranking[i]]}', textAlign: TextAlign.right)),
              ]),
            ),
        ]),
      ),
    );
  }
}
