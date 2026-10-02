import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import 'tw_board.dart';
import 'tw_tiles.dart';

/// Bottom area: my hand (雀魂 MjHand) + 吃/碰/杠/胡/自摸/过 buttons.
/// Chi options are separate buttons with tile previews.
class TwHandBar extends StatefulWidget {
  final GameContext g;
  final Map<String, dynamic> v;
  final double tileW;
  const TwHandBar({super.key, required this.g, required this.v, required this.tileW});
  @override
  State<TwHandBar> createState() => _TwHandBarState();
}

class _TwHandBarState extends State<TwHandBar> {
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
    final drawn = me['drawn'] as String?;
    var hasDrawn = false;
    if (drawn != null && hand.contains(drawn)) {
      hand.remove(drawn);
      hasDrawn = true;
    }
    final seen = <String, int>{};
    final out = <(String, String)>[
      for (final c in sortCodes(hand)) ('$c#${seen[c] = (seen[c] ?? 0) + 1}', c),
    ];
    if (hasDrawn) out.add(('$drawn#d', drawn!));
    return out;
  }

  void _autoPlay(Map me, bool myTurn, String? drawnId) {
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
      _auto.run('$key|giri', () => g.act({'type': 'discard', 'tile': _code(drawnId)}), delayMs: 600);
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
    final myTurn = phase == 'act' && v['turn'] == g.seat;
    final tiles = _tiles(sv, me);
    final drawnId = tiles.isNotEmpty && tiles.last.$1.endsWith('#d') ? tiles.last.$1 : null;
    _autoPlay(me, myTurn, drawnId);
    final tw = widget.tileW;
    final fl = codesOf(sv['flowers']);

    final hand = MjHand(
      tileWidth: tw,
      active: myTurn,
      onDiscard: (id) => g.act({'type': 'discard', 'tile': _code(id)}),
      tiles: [
        for (final (id, c) in tiles)
          MjHandTile(
            id: id,
            drawn: id.endsWith('#d'),
            tile: (w, {dim = false}) => anyTile(c, width: w, dim: dim),
          ),
      ],
      trailing: [
        ...mjMelds('me', [for (final m in sv['melds'] as List) twMeld(m as Map, tw * 0.8)], gap: tw * 0.2),
        if (fl.isNotEmpty) ...[SizedBox(width: tw * 0.4), flowerRow(fl, tw * 0.6)],
      ],
    );

    final actions = _actions(me, phase, myTurn);
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
                for (final w in waits.take(9)) Padding(padding: const EdgeInsets.all(1), child: anyTile(w, width: 14)),
              ]),
            ),
          ),
        ),
      Padding(padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4), child: hand),
    ]);
  }

  List<MjAction> _actions(Map me, String phase, bool myTurn) {
    final out = <MjAction>[];
    Widget preview(List<String> cs, [String? hi]) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (final c in cs) anyTile(c, width: 18, highlight: c == hi),
        ]);
    if (myTurn) {
      if (me['canHu'] == true) out.add(MjAction.win('自摸', () => g.act({'type': 'hu'})));
      for (final k in codesOf(me['kongs'])) {
        out.add(MjAction.kan('杠', () => g.act({'type': 'gang', 'tile': k}), preview: preview([k])));
      }
      return out;
    }
    final claim = codesOf(me['claim']);
    if (phase == 'claim' && claim.isNotEmpty) {
      final tile = v['claimTile'] as String;
      final chis = [for (final c in (me['chis'] as List? ?? const [])) (c as List).cast<String>()];
      if (claim.contains('hu')) {
        out.add(MjAction.win(v['claimRob'] == true ? '抢杠' : '胡', () => g.act({'type': 'hu'})));
      }
      if (claim.contains('gang')) out.add(MjAction.kan('杠', () => g.act({'type': 'gang'}), preview: preview([tile])));
      if (claim.contains('peng')) out.add(MjAction.call('碰', () => g.act({'type': 'peng'}), preview: preview([tile])));
      if (claim.contains('chi')) {
        for (final c in chis) {
          out.add(MjAction.call('吃', () => g.act({'type': 'chi', 'tile': c.first}), preview: preview(c, tile)));
        }
      }
      out.add(MjAction.skip(() => g.act({'type': 'pass'}), '过'));
    }
    return out;
  }
}

/// End-of-hand / end-of-match settlement with the 台 list.
class TwSettlePanel extends StatelessWidget {
  final GameContext g;
  final Map<String, dynamic> view;
  final VoidCallback onHide;
  const TwSettlePanel({super.key, required this.g, required this.view, required this.onHide});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = (view['settle'] as Map).cast<String, dynamic>();
    final over = view['phase'] == 'over';
    final seats = (view['seats'] as List).cast<Map>();
    final delta = (st['delta'] as List).cast<int>();
    final n = seats.length;
    final waiting = (view['waiting'] as List).contains(g.seat);
    final small = TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8));
    final win = st['kind'] == 'win';
    final order = over ? (view['ranking'] as List).cast<int>() : List.generate(n, (i) => i);
    final di = view['di'] as int;
    final perTai = view['perTai'] as int;
    final lian = st['lian'] as int;

    Widget winBlock() {
      final s = st['winner'] as int;
      final from = st['from'] as int;
      final sv = seats[s];
      final hand = sortCodes(((sv['hand'] as List?) ?? const []).cast<String>());
      final items = (st['items'] as List).cast<List>();
      final flowerWin = st['flowerWin'] as String?;
      var total = 0;
      for (final it in items) {
        total += it[1] as int;
      }
      final String title;
      if (flowerWin != null) {
        title = from < 0 ? '${g.name(s)} 八仙过海' : '${g.name(s)} 七抢一（抢 ${g.name(from)} 的花）';
      } else {
        title = st['tsumo'] == true ? '${g.name(s)} 自摸' : '${g.name(s)} 胡 ${g.name(from)} 的牌${st['rob'] == true ? '（抢杠）' : ''}';
      }
      final pay = (st['pay'] as Map).cast<String, dynamic>();
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final f in ((sv['flowers'] as List?) ?? const []).cast<String>()) FlowerTile(f, width: 18),
            const SizedBox(width: 4),
            for (final c in hand) anyTile(c, width: 22),
            const SizedBox(width: 4),
            for (final m in (sv['melds'] as List).cast<Map>()) ...[
              for (final t in (m['tiles'] as List).cast<String>()) anyTile(t, width: 18, faceDown: m['kind'] == 'agang'),
              const SizedBox(width: 3),
            ],
            if (flowerWin == null) ...[
              const SizedBox(width: 6),
              anyTile(st['tile'] as String, width: 22, highlight: true),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final it in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Text('${it[0]} ${it[1]}台',
                  style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          '共 $total 台 · 底 $di + 每台 $perTai · '
          '${pay.entries.map((e) => '${g.name(int.parse(e.key))} 付 ${e.value}').join('，')}',
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary),
        ),
      ]);
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 580),
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
                  over ? '终局排名' : '第 ${st['hand']} 局结算${win ? '' : '（流局）'}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary),
                ),
              ),
              IconButton(onPressed: onHide, icon: const Icon(Icons.visibility), tooltip: '查看牌桌'),
            ]),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(
                      '${windLabels[st['roundWind'] as int]}风圈 · 庄家 ${g.name(st['dealer'] as int)}'
                      '${lian > 0 ? ' · 连$lian拉$lian' : ''}${over ? ' · 最后一局' : ''}',
                      style: small),
                  const SizedBox(height: 4),
                  if (win) winBlock() else Text('牌墙摸完（留尾 16 张），无人胡牌，庄家连庄', style: small),
                  const Divider(height: 14),
                  for (var i = 0; i < order.length; i++)
                    _scoreRow(context, order[i], over ? i + 1 : 0, delta[order[i]], seats[order[i]]['score'] as int),
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

  Widget _scoreRow(BuildContext context, int s, int rank, int d, int total) {
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
        SizedBox(width: 64, child: Align(alignment: Alignment.centerRight, child: MjScoreDelta(d, fontSize: 15))),
        SizedBox(width: 70, child: Text('$total', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
