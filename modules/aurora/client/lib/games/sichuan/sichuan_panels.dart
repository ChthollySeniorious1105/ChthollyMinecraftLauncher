import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import '../../widgets/pieces.dart';
import 'sichuan_board.dart';

/// Bottom area: my hand (雀魂 MjHand), 换三张 selection, 定缺 / 胡 / 杠 / 碰 buttons.
class SichuanHandBar extends StatefulWidget {
  final GameContext g;
  final Map<String, dynamic> v;
  final double tileW;
  const SichuanHandBar({super.key, required this.g, required this.v, required this.tileW});
  @override
  State<SichuanHandBar> createState() => _SichuanHandBarState();
}

class _SichuanHandBarState extends State<SichuanHandBar> {
  final Set<String> _swapSel = {};
  final _auto = MjAutoRunner();

  GameContext get g => widget.g;
  Map<String, dynamic> get v => widget.v;

  @override
  void initState() {
    super.initState();
    for (final n in [MjAutoState.autoWin, MjAutoState.noCall, MjAutoState.tsumogiri]) {
      n.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    for (final n in [MjAutoState.autoWin, MjAutoState.noCall, MjAutoState.tsumogiri]) {
      n.removeListener(_rebuild);
    }
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  static String _code(Object id) => (id as String).split('#').first;

  /// My concealed tiles as (id, code), sorted, with the freshly drawn tile last.
  List<(String, String)> _tiles(Map sv, Map me) {
    final hand = codesOf(sv['hand']);
    final que = sv['que'] as int;
    final drawn = me['drawn'] as String?;
    var hasDrawn = false;
    if (drawn != null && hand.contains(drawn)) {
      hand.remove(drawn);
      hasDrawn = true;
    }
    final seen = <String, int>{};
    final out = <(String, String)>[
      for (final c in sortCodes(hand, que)) ('$c#${seen[c] = (seen[c] ?? 0) + 1}', c),
    ];
    if (hasDrawn) out.add(('$drawn#d', drawn!));
    return out;
  }

  void _autoPlay(Map me, bool myTurn, String? drawnId, Set<String> discardable) {
    final key = '${v['hand']}|${v['phase']}|${v['turn']}|${v['event']?['seq']}|$drawnId';
    final claim = codesOf(me['claim']);
    if (MjAutoState.autoWin.value) {
      if (myTurn && me['canHu'] == true) return _auto.run('$key|zimo', () => g.act({'type': 'hu'}));
      if (claim.contains('hu')) return _auto.run('$key|hu', () => g.act({'type': 'hu'}));
    }
    if (claim.isNotEmpty && !claim.contains('hu') && MjAutoState.noCall.value) {
      return _auto.run('$key|pass', () => g.act({'type': 'pass'}), delayMs: 250);
    }
    if (myTurn && MjAutoState.tsumogiri.value && drawnId != null && me['canHu'] != true) {
      final c = _code(drawnId);
      if (discardable.contains(c)) {
        _auto.run('$key|giri', () => g.act({'type': 'discard', 'tile': c}), delayMs: 600);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = (v['me'] as Map?)?.cast<String, dynamic>();
    if (me == null || g.seat < 0) {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(padding: EdgeInsets.only(bottom: 8), child: Text('观战中', style: TextStyle(color: Colors.white70))),
      );
    }
    final phase = v['phase'] as String;
    final sv = ((v['seats'] as List)[g.seat] as Map).cast<String, dynamic>();
    final que = sv['que'] as int;
    final won = sv['won'] as int;
    final myTurn = phase == 'act' && v['turn'] == g.seat;
    final swapping = phase == 'swap' && me['swapPick'] == null;
    if (phase != 'swap') _swapSel.clear();
    final tiles = _tiles(sv, me);
    final ids = {for (final t in tiles) t.$1};
    _swapSel.removeWhere((id) => !ids.contains(id));
    final discardable = codesOf(me['discardable']).toSet();
    final drawnId = tiles.isNotEmpty && tiles.last.$1.endsWith('#d') ? tiles.last.$1 : null;
    _autoPlay(me, myTurn, drawnId, discardable);
    final gotSwap = codesOf(me['swapGot']);
    final tw = widget.tileW;
    final n = (v['seats'] as List).length;

    final hand = MjHand(
      tileWidth: tw,
      active: myTurn,
      selectedIds: swapping ? _swapSel.cast<Object>() : const {},
      onToggle: swapping
          ? (id) => setState(() {
                final s = id as String;
                if (!_swapSel.remove(s)) {
                  if (_swapSel.isNotEmpty && codeSuit(_code(_swapSel.first)) != codeSuit(_code(s))) _swapSel.clear();
                  if (_swapSel.length < 3) _swapSel.add(s);
                }
              })
          : null,
      onDiscard: (id) => g.act({'type': 'discard', 'tile': _code(id)}),
      tiles: [
        for (final (id, c) in tiles)
          MjHandTile(
            id: id,
            drawn: id.endsWith('#d'),
            enabled: myTurn && discardable.contains(c),
            marked: (myTurn && que >= 0 && codeSuit(c) == que) || (phase == 'que' && gotSwap.contains(c)),
            tile: (w, {dim = false}) => MahjongTile(c, width: w, dim: dim || won > 0),
          ),
      ],
      trailing: [
        if (won > 0 && sv['winTile'] != null) ...[
          SizedBox(width: tw * 0.4),
          MahjongTile(sv['winTile'] as String, width: tw, highlight: true, badge: '胡'),
        ],
        ...mjMelds('me', [for (final m in sv['melds'] as List) sichuanMeld(m as Map, tw * 0.8, g.seat, n)], gap: tw * 0.2),
      ],
    );

    final actions = _actions(me, sv, phase, myTurn, swapping, tiles);
    final waits = codesOf(me['waits']);
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      if (actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6, right: 12, left: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: MjActionBar(actions: actions, scale: (tw / 44).clamp(0.75, 1.2)),
          ),
        ),
      if (waits.isNotEmpty && !myTurn)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('听：', style: TextStyle(color: MjColors.winGlow, fontSize: 12, fontWeight: FontWeight.bold)),
                for (final w in waits.take(9)) Padding(padding: const EdgeInsets.all(1), child: MahjongTile(w, width: 14)),
              ]),
            ),
          ),
        ),
      Padding(padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4), child: hand),
    ]);
  }

  List<MjAction> _actions(Map me, Map sv, String phase, bool myTurn, bool swapping, List<(String, String)> tiles) {
    final out = <MjAction>[];
    Widget preview(String c, [int k = 1]) =>
        Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < k; i++) MahjongTile(c, width: 18)]);
    if (swapping) {
      out.add(MjAction.skip(() {
        final hint = codesOf(me['swapHint']);
        final used = <String>{};
        for (final h in hint) {
          for (final (id, c) in tiles) {
            if (c == h && !used.contains(id)) {
              used.add(id);
              break;
            }
          }
        }
        setState(() => _swapSel
          ..clear()
          ..addAll(used));
      }, '推荐'));
      out.add(MjAction.call('换三张 ${_swapSel.length}/3', () {
        if (_swapSel.length != 3) return;
        g.act({'type': 'swap', 'tiles': [for (final id in _swapSel) _code(id)]});
        setState(() => _swapSel.clear());
      }));
      return out;
    }
    if (phase == 'que' && me['quePick'] == null) {
      final hint = (me['queHint'] as num?)?.toInt() ?? -1;
      for (var s = 0; s < 3; s++) {
        out.add(MjAction('缺${suitLabels[s]}', suitColors[s], () => g.act({'type': 'que', 'suit': s}),
            preview: s == hint
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: MjColors.winGlow, borderRadius: BorderRadius.circular(6)),
                    child: const Text('荐', style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                  )
                : null));
      }
      return out;
    }
    if (myTurn) {
      if (me['canHu'] == true) out.add(MjAction.win('自摸', () => g.act({'type': 'hu'})));
      for (final k in codesOf(me['kongs'])) {
        out.add(MjAction.kan('杠', () => g.act({'type': 'gang', 'tile': k}), preview: preview(k)));
      }
      return out;
    }
    final claim = codesOf(me['claim']);
    if (phase == 'claim' && claim.isNotEmpty) {
      final tile = v['claimTile'] as String;
      if (claim.contains('hu')) out.add(MjAction.win(v['claimQiang'] == true ? '抢杠胡' : '胡', () => g.act({'type': 'hu'})));
      if (claim.contains('gang')) out.add(MjAction.kan('杠', () => g.act({'type': 'gang'}), preview: preview(tile)));
      if (claim.contains('peng')) out.add(MjAction.call('碰', () => g.act({'type': 'peng'}), preview: preview(tile)));
      out.add(MjAction.skip(() => g.act({'type': 'pass'}), '过'));
    }
    return out;
  }
}

/// End-of-hand / end-of-match settlement.
class SettlePanel extends StatelessWidget {
  final GameContext g;
  final Map<String, dynamic> view;
  final VoidCallback onHide;
  const SettlePanel({super.key, required this.g, required this.view, required this.onHide});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = (view['settle'] as Map).cast<String, dynamic>();
    final over = view['phase'] == 'over';
    final seats = (view['seats'] as List).cast<Map>();
    final delta = (st['delta'] as List).cast<int>();
    final events = (st['events'] as List).cast<Map>();
    final cj = (st['chajiao'] as List).cast<Map>();
    final n = seats.length;
    final waiting = (view['waiting'] as List).contains(g.seat);
    final small = TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8));

    Widget hu(Map e) {
      final s = e['seat'] as int;
      final from = e['from'] as int;
      final items = (e['items'] as List).map((x) {
        final l = x as List;
        final f = l[1] as int;
        return f > 0 && l[0] != '平胡' ? '${l[0]} $f番' : '${l[0]}';
      }).join('  ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: MjColors.win, borderRadius: BorderRadius.circular(4)),
            child: Text('胡${e['order']}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 6),
          MahjongTile(e['tile'] as String, width: 22, highlight: true),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['zimo'] == true ? '${g.name(s)} 自摸' : '${g.name(s)} 胡 ${g.name(from)} 点炮',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('$items · 共${e['fan']}番${e['capped'] == true ? '（封顶）' : ''}', style: small),
            ]),
          ),
          Text(e['zimo'] == true ? '每家 ${e['points']}' : '${e['points']}',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
        ]),
      );
    }

    final gangLines = [for (final e in events) if (e['kind'] == 'gang') e['text'] as String];
    final order = over ? (view['ranking'] as List).cast<int>() : List.generate(n, (i) => i);
    final noHu = events.every((e) => e['kind'] != 'hu');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber.shade600, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 20, color: Colors.black54)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Text(
                  over ? '终局排名' : '第 ${st['hand']} 局结算${st['exhausted'] == true && noHu ? '（流局）' : ''}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: cs.primary, letterSpacing: 2),
                ),
              ),
              IconButton(onPressed: onHide, icon: const Icon(Icons.visibility), tooltip: '查看牌桌'),
            ]),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (over) Text('第 ${st['hand']} 局（最后一局）', style: small),
                  for (final e in events)
                    if (e['kind'] == 'hu') hu(e),
                  if (gangLines.isNotEmpty) ...[
                    const Divider(height: 10),
                    Text('刮风下雨：${gangLines.join('，')}', style: small),
                  ],
                  if (cj.isNotEmpty) ...[
                    const Divider(height: 10),
                    for (final c in cj)
                      Text('${c['why']}：${g.name(c['from'] as int)} → ${g.name(c['to'] as int)}  ${c['amount']}', style: small),
                  ],
                  const Divider(height: 14),
                  for (var i = 0; i < order.length; i++)
                    _scoreRow(context, order[i], over ? i + 1 : 0, delta[order[i]], seats[order[i]]['score'] as int,
                        (st['huazhu'] as List)[order[i]] == true, seats[order[i]]['won'] as int),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            if (!over)
              FilledButton(
                onPressed: waiting ? () => g.act({'type': 'next'}) : null,
                child: Text(waiting ? '下一局' : '等待其他玩家…'),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _scoreRow(BuildContext context, int s, int rank, int d, int total, bool huazhu, int won) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        if (rank > 0)
          SizedBox(
            width: 28,
            child: Text('$rank',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: rank == 1 ? Colors.amber : cs.onSurface)),
          ),
        Avatar(g.avatar(s), size: 26, bot: g.bot(s)),
        const SizedBox(width: 6),
        Expanded(child: Text(g.name(s), overflow: TextOverflow.ellipsis)),
        if (won > 0) Text('胡$won ', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        if (huazhu) const Text('花猪 ', style: TextStyle(color: Colors.pinkAccent, fontSize: 12)),
        SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: MjScoreDelta(d, fontSize: 15))),
        SizedBox(width: 64, child: Text('$total', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
