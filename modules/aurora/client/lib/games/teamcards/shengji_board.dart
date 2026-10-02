import 'package:aurora_shared/games/teamcards/shengji_rules.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tc_common.dart';

class ShengjiBoard extends StatefulWidget {
  final GameContext g;
  const ShengjiBoard(this.g, {super.key});
  @override
  State<ShengjiBoard> createState() => _ShengjiBoardState();
}

class _ShengjiBoardState extends State<ShengjiBoard> {
  Set<int> _sel = {};
  String _key = '';
  bool _showLast = false;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => [for (final c in (v['hand'] as List? ?? const [])) '$c'];
  String get phase => '${v['phase']}';
  int get level => v['level'] as int;
  SjTrump get trump => SjTrump(level, '${v['trump']}');
  List<String> _list(Object? l) => [for (final c in (l as List? ?? const [])) '$c'];

  void _sync() {
    final k = '${hand.join(',')}|${v['turn']}|$phase';
    if (k != _key) {
      _key = k;
      _sel = {};
    }
  }

  List<String> get _selCards {
    final h = hand;
    return [for (final i in (_sel.toList()..sort())) if (i < h.length) h[i]];
  }

  void _select(List<String> cards) {
    final h = hand;
    final used = <int>{};
    for (final c in cards) {
      for (var i = 0; i < h.length; i++) {
        if (!used.contains(i) && h[i] == c) {
          used.add(i);
          break;
        }
      }
    }
    setState(() => _sel = used);
  }

  void _hint() {
    final t = trump;
    final h = hand;
    if (phase == 'bury') {
      final side = h.where((c) => !t.isTrump(c)).toList()
        ..sort((a, b) => (t.order(a) + sjPoints(a) * 2).compareTo(t.order(b) + sjPoints(b) * 2));
      final pick = [...side, ...h.where(t.isTrump).toList().reversed].take(8).toList();
      _select(pick);
      return;
    }
    final lead = _list(v['leadCards']);
    final leader = v['leader'] as int;
    if (leader == g.seat) {
      _select([h.last]);
      return;
    }
    final comps = sjDecompose(lead, t);
    final cls = t.cls(lead.first);
    for (final high in [true, false]) {
      final c = sjBuildFollow(t, h, cls, comps, high, false);
      if (sjFollowError(lead, c, h, t) == null) {
        _select(c);
        return;
      }
    }
  }

  bool get _isLead => phase == 'play' && v['leader'] == g.seat && v['turn'] == g.seat;

  Widget _panel(int s, double w, double maxW) {
    final counts = (v['counts'] as List).cast<int>();
    final turn = v['turn'] as int;
    final banker = v['banker'] as int;
    final active = !g.over && turn == s && (phase == 'play' || phase == 'declare' || phase == 'bury');
    Widget body;
    if (phase == 'declare' || phase == 'bury') {
      final d = (v['declActs'] as List)[s];
      body = d == null ? SizedBox(height: w * 0.8) : tcNote(d == 'pass' ? '不亮' : '$d', color: d == 'pass' ? Colors.black45 : Colors.deepOrange);
      if (phase == 'declare' && v['declarer'] == s) {
        body = Column(mainAxisSize: MainAxisSize.min, children: [tcCards(_list(v['declCards']), w, maxW: maxW), const SizedBox(height: 2), body]);
      }
    } else {
      final a = (v['acts'] as List)[s] as Map?;
      if (a == null) {
        body = SizedBox(height: w * 1.4);
      } else {
        final win = a['win'] == true;
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          tcCards(_list(a['cards']), w, maxW: maxW, mark: win ? (_) => true : null),
          if (a['label'] != null || win) ...[
            const SizedBox(height: 2),
            tcNote(win ? '本轮最大' : '${a['label']}', color: win ? Colors.orange : Colors.black45),
          ],
        ]);
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      g.tag(s,
          active: active,
          size: 30,
          sub: '剩${counts[s]}张',
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (banker == s) tcBadge('庄', Colors.deepOrange),
            if (g.seat >= 0 && s == (g.seat + 2) % 4) tcBadge('队友', Colors.teal),
            if (active) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.timer, size: 18, color: Colors.amber)),
          ])),
      const SizedBox(height: 4),
      body,
    ]);
  }

  Widget _info(ColorScheme cs) {
    final levels = (v['levels'] as List).cast<int>();
    final bt = v['bankerTeam'] as int;
    final me = g.seat < 0 ? 0 : g.seat;
    final suit = '${v['trump']}';
    Widget teamChip(int t) {
      final mine = t == me % 2;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: (mine ? Colors.teal : Colors.blueGrey).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          border: bt == t ? Border.all(color: Colors.amber, width: 2) : null,
        ),
        child: Text('${mine ? "我方" : "对方"} ${sjRankName(levels[t])}${bt == t ? " 庄" : ""}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      );
    }

    final cap = v['cap'] as int;
    final pts = v['points'] as int;
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
      tcChip('第 ${(v['deal'] as int) + 1}${cap > 0 ? "/$cap" : ""} 局', cs.primary),
      teamChip(me % 2),
      teamChip(1 - me % 2),
      tcChip('打${sjRankName(level)} · 主 ${suit.isEmpty ? "未定" : sjSuitNames[suit]}', Colors.deepOrange),
      tcChip('闲家得分 $pts', pts >= 80 ? Colors.redAccent : Colors.indigo),
      if ((v['lastTrick'] as List).isNotEmpty && phase == 'play')
        InkWell(
          onTap: () => setState(() => _showLast = !_showLast),
          child: tcChip(_showLast ? '隐藏上一轮' : '上一轮', Colors.black54),
        ),
    ]);
  }

  Widget _center() {
    final tf = v['throwFail'] as Map?;
    final children = <Widget>[];
    if (tf != null && phase == 'play') {
      children.add(Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${g.name(tf['seat'] as int)} 甩牌失败 罚${tf['penalty']}分', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          tcCards(_list(tf['tried']), 22, maxW: 240),
        ]),
      ));
    }
    if (_showLast && phase == 'play') {
      final lt = v['lastTrick'] as List;
      children.add(Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('上一轮 · ${g.name(v['lastWinner'] as int)} 最大', style: const TextStyle(color: Colors.white70)),
          for (final e in lt)
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 64, child: Text(g.name(e['seat'] as int), overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white))),
              tcCards(_list(e['cards']), 20, maxW: 200),
            ]),
        ]),
      ));
    }
    if (children.isEmpty) return const SizedBox(width: 60, height: 40);
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  String _status(bool mine) {
    final turn = v['turn'] as int;
    switch (phase) {
      case 'declare':
        return mine ? '亮主阶段：可以亮主/反主，或选择不亮' : '亮主阶段：等待 ${g.name(turn)}';
      case 'bury':
        return mine ? '你是庄家：请选择 8 张牌扣底' : '等待庄家 ${g.name(v['banker'] as int)} 扣底';
      case 'play':
        if (mine) return _isLead ? '轮到你首出（可甩牌）' : '轮到你跟牌（需跟 ${(v['leadCards'] as List).length} 张）';
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
    final mine = me >= 0 && !g.over && v['turn'] == me && (phase == 'declare' || phase == 'play' || phase == 'bury');
    final t = trump;
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
          StatusBar(_status(mine), highlight: mine),
          const SizedBox(height: 4),
          if (me >= 0) ...[
            FittedBox(fit: BoxFit.scaleDown, child: _mine(w * 0.62)),
            if (mine) Padding(padding: const EdgeInsets.only(top: 4), child: _buttons()),
            const SizedBox(height: 2),
            TcHand(
              cards: hand,
              selected: _sel,
              cardW: w,
              maxW: c.maxWidth - 12,
              interactive: mine && phase != 'declare',
              mark: '${v['trump']}'.isEmpty
                  ? (code) => sjNat(code) == level || sjNat(code) >= 16 ? '主' : null
                  : (code) => t.isTrump(code) ? '主' : null,
              markColor: (code) => sjNat(code) == level ? Colors.indigo : Colors.deepOrange,
              onChanged: (s) => setState(() => _sel = s),
            ),
          ],
        ]);
      }),
    );
  }

  Widget _mine(double w) {
    final me = g.seat;
    final banker = v['banker'] as int;
    Widget? body;
    if (phase == 'play') {
      final a = (v['acts'] as List)[me] as Map?;
      if (a != null) {
        body = Row(mainAxisSize: MainAxisSize.min, children: [
          tcCards(_list(a['cards']), w, maxW: 300, mark: a['win'] == true ? (_) => true : null),
          if (a['win'] == true) ...[const SizedBox(width: 4), tcNote('本轮最大', color: Colors.orange)],
        ]);
      }
    } else if (phase == 'bury') {
      final bd = _list(v['bottomDealt']);
      if (bd.isNotEmpty) {
        body = Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('底牌 ', style: TextStyle(color: Colors.white70)),
          tcCards(bd, w, maxW: 260),
        ]);
      }
    } else if (phase == 'declare') {
      final d = (v['declActs'] as List)[me];
      if (d != null) body = tcNote(d == 'pass' ? '不亮' : '$d');
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      g.tag(me,
          size: 28,
          active: v['turn'] == me && !g.over && phase != 'dealEnd',
          sub: '级${sjRankName((v['levels'] as List).cast<int>()[me % 2])}',
          trailing: banker == me ? tcBadge('庄', Colors.deepOrange) : null),
      if (body != null) ...[const SizedBox(width: 8), body],
    ]);
  }

  Widget _buttons() {
    final btns = <Widget>[];
    if (phase == 'declare') {
      for (final o in (v['declOptions'] as List? ?? const [])) {
        final str = o['strength'] as int;
        final suit = '${o['suit']}';
        final label = str >= 3 ? (str == 4 ? '大王对 无主' : '小王对 无主') : (str == 2 ? '对${sjSuitNames[suit]}' : '亮${sjSuitNames[suit]}');
        btns.add(FilledButton(onPressed: () => g.act({'type': 'declare', 'strength': str, 'suit': suit}), child: Text(label)));
      }
      btns.add(OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('不亮')));
      return Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: btns);
    }
    final sel = _selCards;
    if (phase == 'bury') {
      btns.add(OutlinedButton(onPressed: _hint, child: const Text('提示')));
      btns.add(FilledButton(
        onPressed: sel.length == 8 ? () => g.act({'type': 'bury', 'cards': sel}) : null,
        child: Text('扣底（${sel.length}/8）'),
      ));
      return Wrap(alignment: WrapAlignment.center, spacing: 8, children: btns);
    }
    btns.add(OutlinedButton(onPressed: _hint, child: const Text('提示')));
    btns.add(FilledButton(
      onPressed: sel.isEmpty ? null : () => g.act({'type': 'play', 'cards': sel}),
      child: Text(_isLead && sel.length > 1 && sjDecompose(sel, trump).length > 1 ? '甩牌' : '出牌'),
    ));
    return Wrap(alignment: WrapAlignment.center, spacing: 8, children: btns);
  }

  Widget _result() {
    final r = v['result'] as Map?;
    final over = phase == 'over';
    final me = g.seat;
    final ready = (v['ready'] as List?)?.cast<bool>();
    final winner = v['winner'] as int;
    final myTeam = me < 0 ? -1 : me % 2;
    final levels = (v['levels'] as List).cast<int>();
    String title;
    if (over) {
      title = winner == 2 ? '比赛结束 · 平局' : (myTeam < 0 ? '${tcTeamName(winner)}获胜！' : (winner == myTeam ? '我方获胜！' : '对方获胜'));
    } else if (r != null) {
      title = r['hold'] == true ? '庄家守住！' : '闲家上台！';
    } else {
      title = '本局结束';
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ResultBanner(
        title,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (r != null) ...[
            Text('闲家得分 ${r['points']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if ((r['mult'] as int) > 0) Text('抠底：底分 ${r['bottomPts']} ×${r['mult']}'),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('底牌 '),
              tcCards(_list(r['bottom']), 24, maxW: 220),
            ]),
            const SizedBox(height: 4),
            if ((r['up'] as int) > 0) Text('${tcTeamName(r['upTeam'] as int)} 升 ${r['up']} 级'),
          ],
          Text('南北队 ${sjRankName(levels[0])} · 东西队 ${sjRankName(levels[1])}'),
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
