import 'package:aurora_shared/games/teamcards/guandan_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tc_common.dart';

class GuandanBoard extends StatefulWidget {
  final GameContext g;
  const GuandanBoard(this.g, {super.key});
  @override
  State<GuandanBoard> createState() => _GuandanBoardState();
}

class _GuandanBoardState extends State<GuandanBoard> {
  Set<int> _sel = {};
  String _key = '';
  int _hint = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => [for (final c in (v['hand'] as List? ?? const [])) '$c'];
  int get level => v['level'] as int;
  String get phase => '${v['phase']}';
  List<String> _list(Object? l) => [for (final c in (l as List? ?? const [])) '$c'];

  void _sync() {
    final k = '${hand.join(',')}|${v['turn']}|${v['tableSeat']}|$phase';
    if (k != _key) {
      _key = k;
      _sel = {};
      _hint = -1;
    }
  }

  List<String> get _selCards {
    final h = hand;
    return [for (final i in (_sel.toList()..sort())) if (i < h.length) h[i]];
  }

  void _doHint() {
    final h = hand;
    final table = GdCombo.fromJson(v['table']);
    final cands = gdCandidates(h, table, level);
    cands.sort((a, b) {
      if (a.combo.isBomb != b.combo.isBomb) return a.combo.isBomb ? 1 : -1;
      final w = a.wilds(level) - b.wilds(level);
      if (w != 0) return w;
      if (table == null && a.cards.length != b.cards.length) return b.cards.length - a.cards.length;
      return a.combo.key - b.combo.key;
    });
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有能管上的牌，请点不出'), duration: Duration(seconds: 1)));
      return;
    }
    _hint = (_hint + 1) % cands.length;
    final used = <int>{};
    for (final c in cands[_hint].cards) {
      for (var i = 0; i < h.length; i++) {
        if (!used.contains(i) && h[i] == c) {
          used.add(i);
          break;
        }
      }
    }
    setState(() => _sel = used);
  }

  Widget _panel(int s, double w, double maxW) {
    final counts = (v['counts'] as List).cast<int>();
    final turn = v['turn'] as int;
    final finish = (v['finish'] as List).cast<int>();
    final active = !g.over && turn == s && phase == 'play';
    final lvl = (v['levels'] as List).cast<int>()[s % 2];
    final rankIdx = finish.indexOf(s);
    final showHands = v['hands'] as List?;
    Widget body;
    final acts = v['acts'] as List;
    final a = acts[s] as Map?;
    if (showHands != null && s != g.seat) {
      body = tcCards(_list(showHands[s]), w * 0.8, maxW: maxW);
    } else if (phase == 'tribute' || phase == 'return') {
      body = _tributeNote(s);
    } else if (a == null) {
      body = SizedBox(height: w * 1.4);
    } else if (a['pass'] == true) {
      body = tcNote('不出');
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        tcCards(_list(a['cards']), w, maxW: maxW, mark: (c) => gdIsWild(c, level)),
        const SizedBox(height: 2),
        tcNote('${a['label']}', color: a['type'] == 'bomb' || a['type'] == 'sf' || a['type'] == 'jokers' ? Colors.redAccent : Colors.black45),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: active,
          size: 30,
          sub: '剩${counts[s]}张 · 级${gdRankName(lvl)}',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (g.seat >= 0 && s == (g.seat + 2) % 4) tcBadge('队友', Colors.teal),
            if (rankIdx >= 0 && phase == 'play') tcBadge(const ['头游', '二游', '三游', '末游'][rankIdx], Colors.orange),
            if (counts[s] > 0 && counts[s] <= 10 && phase == 'play') tcBadge('报${counts[s]}', Colors.redAccent),
            if (active) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.timer, size: 18, color: Colors.amber)),
          ])),
      const SizedBox(height: 4),
      body,
    ]);
  }

  Widget _tributeNote(int s) {
    final payers = (v['payers'] as List).cast<int>();
    final receivers = (v['receivers'] as List).cast<int>();
    final paid = (v['paid'] as List).cast<bool>();
    if (phase == 'tribute' && payers.contains(s)) {
      return tcNote(paid[payers.indexOf(s)] ? '已进贡' : '进贡中…', color: Colors.deepOrange);
    }
    if (phase == 'return' && receivers.contains(s)) return tcNote('还贡中…', color: Colors.indigo);
    return const SizedBox(height: 20);
  }

  Widget _info(ColorScheme cs) {
    final levels = (v['levels'] as List).cast<int>();
    final lt = v['levelTeam'] as int;
    final me = g.seat < 0 ? 0 : g.seat;
    Widget teamChip(int t) {
      final mine = t == me % 2;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: (mine ? Colors.teal : Colors.blueGrey).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: lt == t ? Border.all(color: Colors.amber, width: 2) : null,
        ),
        child: Text('${mine ? "我方" : "对方"} ${gdRankName(levels[t])}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      );
    }

    final cap = v['cap'] as int;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
      tcChip('第 ${(v['deal'] as int) + (phase == 'dealEnd' || phase == 'over' ? 0 : 1)}${cap > 0 ? "/$cap" : ""} 局', cs.primary),
      teamChip(me % 2),
      teamChip(1 - me % 2),
      tcChip('打${gdRankName(level)} · 目标${gdRankName(v['target'] as int)}', Colors.deepOrange),
      Row(mainAxisSize: MainAxisSize.min, children: [
        tcMini('${v['wild']}', 18),
        const Text(' 逢人配', style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]);
  }

  Widget _center() {
    final t = v['tribute'] as Map?;
    if (t == null || phase == 'dealEnd' || phase == 'over') return const SizedBox(width: 60, height: 40);
    if (t['resist'] == true) return tcNote('抗贡！', color: Colors.deepPurple);
    final pay = t['pay'] as List?;
    if (pay == null) return const SizedBox(width: 60, height: 40);
    final returns = t['returns'] as Map?;
    if (phase == 'play' && (v['counts'] as List).cast<int>().any((c) => c < 27)) {
      return const SizedBox(width: 60, height: 40);
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('进贡', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        for (final p in pay)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${g.name(p['from'] as int)} → ${g.name(p['to'] as int)} ', style: const TextStyle(color: Colors.white70)),
              tcMini('${p['card']}', 24),
              if (returns?['${p['to']}'] != null) ...[
                const Text('  还 ', style: TextStyle(color: Colors.white70)),
                tcMini('${returns!['${p['to']}']}', 24),
              ],
            ]),
          ),
      ]),
    );
  }

  String _status(bool myTurn) {
    final turn = v['turn'] as int;
    switch (phase) {
      case 'tribute':
        return (g.seat >= 0 && (v['payers'] as List).contains(g.seat) && !(v['paid'] as List)[(v['payers'] as List).indexOf(g.seat)])
            ? '请选择最大的一张牌进贡（红桃级牌除外）'
            : '等待进贡';
      case 'return':
        return (g.seat >= 0 && (v['receivers'] as List).contains(g.seat)) ? '请选择一张不大于10的牌还贡' : '等待还贡';
      case 'play':
        if (myTurn) return v['lead'] == true ? '轮到你出牌（任意牌型）' : '轮到你出牌，管上或不出';
        return '等待 ${g.name(turn)} 出牌';
      case 'dealEnd':
        return '本局结束';
    }
    return '比赛结束';
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final cs = Theme.of(context).colorScheme;
    final me = g.seat;
    final turn = v['turn'] as int;
    final waitingMe = me >= 0 &&
        ((phase == 'play' && turn == me) ||
            (phase == 'tribute' && (v['payers'] as List).contains(me) && !(v['paid'] as List)[(v['payers'] as List).indexOf(me)]) ||
            (phase == 'return' && (v['receivers'] as List).contains(me)));
    return TcTable(
      g: g,
      info: _info(cs),
      panel: _panel,
      center: _center(),
      overlay: (phase == 'dealEnd' || phase == 'over') ? _result() : null,
      bottom: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / 14).clamp(34.0, 60.0).toDouble();
        final byH = (MediaQuery.sizeOf(context).height / 9).clamp(30.0, 60.0).toDouble();
        final w = cw < byH ? cw : byH;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          StatusBar(_status(waitingMe), highlight: waitingMe),
          const SizedBox(height: 4),
          if (me >= 0) ...[
            FittedBox(fit: BoxFit.scaleDown, child: _panelMine(w * 0.62)),
            if (waitingMe) Padding(padding: const EdgeInsets.only(top: 4), child: _buttons()),
            const SizedBox(height: 2),
            TcHand(
              cards: hand,
              selected: _sel,
              cardW: w,
              maxW: c.maxWidth - 12,
              interactive: waitingMe,
              mark: (code) => gdIsWild(code, level) ? '配' : (gdNat(code) == level ? '级' : null),
              markColor: (code) => gdIsWild(code, level) ? Colors.deepOrange : Colors.indigo,
              onChanged: (s) => setState(() => _sel = s),
            ),
          ],
        ]);
      }),
    );
  }

  Widget _panelMine(double w) {
    final me = g.seat;
    final a = (v['acts'] as List)[me] as Map?;
    final finish = (v['finish'] as List).cast<int>();
    final rankIdx = finish.indexOf(me);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      g.tag(me,
          size: 28,
          active: phase == 'play' && v['turn'] == me && !g.over,
          sub: '级${gdRankName((v['levels'] as List).cast<int>()[me % 2])}',
          trailing: rankIdx >= 0 && phase == 'play' ? tcBadge(const ['头游', '二游', '三游', '末游'][rankIdx], Colors.orange) : null),
      const SizedBox(width: 8),
      if (phase == 'tribute' || phase == 'return')
        _tributeNote(me)
      else if (a != null && a['pass'] == true)
        tcNote('不出')
      else if (a != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          tcCards(_list(a['cards']), w, maxW: 300, mark: (c) => gdIsWild(c, level)),
          const SizedBox(width: 4),
          tcNote('${a['label']}'),
        ]),
    ]);
  }

  Widget _buttons() {
    final btns = <Widget>[];
    if (phase == 'tribute' || phase == 'return') {
      final isT = phase == 'tribute';
      btns.add(FilledButton(
        onPressed: _sel.length == 1 ? () => g.act({'type': isT ? 'tribute' : 'return', 'card': _selCards.first}) : null,
        child: Text(isT ? '进贡' : '还贡'),
      ));
      btns.add(OutlinedButton(
        onPressed: () {
          final h = hand;
          int? pick;
          if (isT) {
            final mv = v['maxTribute'] as int?;
            for (var i = 0; i < h.length; i++) {
              if (!gdIsWild(h[i], level) && gdValue(h[i], level) == mv) {
                pick = i;
                break;
              }
            }
          } else {
            for (var i = h.length - 1; i >= 0; i--) {
              if (gdNat(h[i]) <= 10) {
                pick = i;
                break;
              }
            }
            pick ??= h.length - 1;
          }
          if (pick != null) setState(() => _sel = {pick!});
        },
        child: const Text('提示'),
      ));
      return Wrap(alignment: WrapAlignment.center, spacing: 8, children: btns);
    }
    final lead = v['lead'] == true;
    btns.add(OutlinedButton(onPressed: lead ? null : () => g.act({'type': 'pass'}), child: const Text('不出')));
    btns.add(OutlinedButton(onPressed: _doHint, child: const Text('提示')));
    final sel = _selCards;
    final table = GdCombo.fromJson(v['table']);
    final interps = sel.isEmpty
        ? <GdCombo>[]
        : gdAnalyze(sel, level).where((c) => table == null || gdBeats(c, table)).toList();
    if (interps.length > 1) {
      for (final c in interps) {
        btns.add(FilledButton(onPressed: () => g.act({'type': 'play', 'cards': sel, 'as': c.type}), child: Text('出${c.label}')));
      }
    } else {
      btns.add(FilledButton(
        onPressed: sel.isEmpty ? null : () => g.act({'type': 'play', 'cards': sel}),
        child: Text(interps.length == 1 ? '出牌（${interps.first.label}）' : '出牌'),
      ));
    }
    return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: btns);
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final over = phase == 'over';
    final me = g.seat;
    final ready = (v['ready'] as List?)?.cast<bool>();
    final winner = v['winner'] as int;
    final myTeam = me < 0 ? -1 : me % 2;
    String title;
    if (over) {
      title = winner == 2 ? '比赛结束 · 平局' : (myTeam < 0 ? '${tcTeamName(winner)}获胜！' : (winner == myTeam ? '我方获胜！' : '对方获胜'));
    } else {
      final w = r?['winTeam'] as int? ?? 0;
      title = myTeam < 0 ? '${tcTeamName(w)}赢得本局' : (w == myTeam ? '我方赢得本局' : '对方赢得本局');
    }
    final finish = r == null ? <int>[] : (r['finish'] as List).cast<int>();
    final levels = (v['levels'] as List).cast<int>();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ResultBanner(
        title,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 0; k < finish.length; k++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(width: 44, child: Text(const ['头游', '二游', '三游', '末游'][k], style: const TextStyle(fontWeight: FontWeight.bold))),
                SizedBox(width: 120, child: Text(g.name(finish[k]), overflow: TextOverflow.ellipsis)),
                Text(tcTeamName(finish[k] % 2), style: const TextStyle(fontSize: 12)),
              ]),
            ),
          const SizedBox(height: 6),
          if (r != null && (r['up'] as int) > 0)
            Text('${tcTeamName(r['winTeam'] as int)} 升 ${r['up']} 级', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('南北队 ${gdRankName(levels[0])} · 东西队 ${gdRankName(levels[1])}'),
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
