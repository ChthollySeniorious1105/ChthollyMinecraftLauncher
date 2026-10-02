import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import 'm2_tiles.dart';

/// Bottom area: my hand (雀魂 MjHand) + 起手胡 / 吃 / 碰 / 杠(补张/开杠) / 胡 / 过 buttons.
class M2HandBar extends StatefulWidget {
  final GameContext g;
  final Map<String, dynamic> v;
  final double tileW;
  const M2HandBar({super.key, required this.g, required this.v, required this.tileW});
  @override
  State<M2HandBar> createState() => _M2HandBarState();
}

class _M2HandBarState extends State<M2HandBar> {
  final _auto = MjAutoRunner();

  GameContext get g => widget.g;
  Map<String, dynamic> get v => widget.v;
  bool get isCs => v['rule'] == 'changsha';
  String get huWord => isCs ? '胡' : '和';

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

  void _autoPlay(Map me, bool myTurn, String? drawnId, Set<String>? discardable) {
    if (g.replay) return;
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
      if (discardable == null || discardable.contains(c)) {
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
    final myTurn = phase == 'act' && v['turn'] == g.seat;
    final tiles = _tiles(sv, me);
    final drawnId = tiles.isNotEmpty && tiles.last.$1.endsWith('#d') ? tiles.last.$1 : null;
    final discardable = me['discardable'] == null ? null : codesOf(me['discardable']).toSet();
    _autoPlay(me, myTurn, drawnId, discardable);
    final tw = widget.tileW;
    final fl = codesOf(sv['flowers']);
    final locked = sv['locked'] == true;

    final hand = MjHand(
      tileWidth: tw,
      active: myTurn,
      onDiscard: (id) => g.act({'type': 'discard', 'tile': _code(id)}),
      tiles: [
        for (final (id, c) in tiles)
          MjHandTile(
            id: id,
            drawn: id.endsWith('#d'),
            enabled: !myTurn || discardable == null || discardable.contains(c),
            tile: (w, {dim = false}) => m2Tile(c, width: w, dim: dim || (locked && !id.endsWith('#d'))),
          ),
      ],
      trailing: [
        ...mjMelds('me', [for (final m in sv['melds'] as List) m2Meld(m as Map, tw * 0.8)], gap: tw * 0.2),
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
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: MjActionBar(actions: actions, scale: (tw / 44).clamp(0.75, 1.2)),
            ),
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
                for (final w in waits.take(9)) Padding(padding: const EdgeInsets.all(1), child: m2Tile(w, width: 14)),
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
          for (final c in cs) m2Tile(c, width: 18, highlight: c == hi),
        ]);
    if (phase == 'qishou' && me['qishou'] != null) {
      out.add(MjAction.win('起手胡', () => g.act({'type': 'qishou'})));
      out.add(MjAction.skip(() => g.act({'type': 'pass'}), '不亮'));
      return out;
    }
    if (myTurn) {
      if (me['canHu'] == true) out.add(MjAction.win('自摸', () => g.act({'type': 'hu'})));
      for (final k in (me['kongs'] as List? ?? const [])) {
        if (k is Map) {
          final t = k['tile'] as String;
          out.add(MjAction.kan('补张', () => g.act({'type': 'gang', 'tile': t, 'mode': 'bu'}), preview: preview([t])));
          if (k['kai'] == true) {
            out.add(MjAction('开杠', MjColors.riichi, () => g.act({'type': 'gang', 'tile': t, 'mode': 'kai'}), preview: preview([t])));
          }
        } else {
          final t = '$k';
          out.add(MjAction.kan('杠', () => g.act({'type': 'gang', 'tile': t}), preview: preview([t])));
        }
      }
      return out;
    }
    final claim = codesOf(me['claim']);
    if (phase == 'claim' && claim.isNotEmpty) {
      final tile = v['claimTile'] as String;
      final kind = v['claimKind'] ?? (v['claimRob'] == true ? 'rob' : 'discard');
      final chis = [for (final c in (me['chis'] as List? ?? const [])) codesOf(c)];
      if (claim.contains('hu')) {
        final label = switch (kind) { 'rob' => '抢杠', 'flip' => '杠上炮', _ => huWord };
        final ht = me['huTile'] as String?;
        out.add(MjAction(label, MjColors.win, () => g.act({'type': 'hu'}), primary: true, preview: ht == null || kind == 'discard' ? null : preview([ht])));
      }
      if (claim.contains('gang')) {
        if (isCs) {
          out.add(MjAction.kan('补张', () => g.act({'type': 'gang', 'mode': 'bu'}), preview: preview([tile])));
          if (me['kaiOk'] == true) {
            out.add(MjAction('开杠', MjColors.riichi, () => g.act({'type': 'gang', 'mode': 'kai'}), preview: preview([tile])));
          }
        } else {
          out.add(MjAction.kan('杠', () => g.act({'type': 'gang'}), preview: preview([tile])));
        }
      }
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

/// End-of-hand / end-of-match settlement.
class M2SettlePanel extends StatelessWidget {
  final GameContext g;
  final Map<String, dynamic> view;
  final VoidCallback onHide;
  const M2SettlePanel({super.key, required this.g, required this.view, required this.onHide});

  bool get isCs => view['rule'] == 'changsha';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = (view['settle'] as Map).cast<String, dynamic>();
    final over = view['phase'] == 'over';
    final seats = (view['seats'] as List).cast<Map>();
    final delta = [for (final d in st['delta'] as List) (d as num).toInt()];
    final n = seats.length;
    final waiting = (view['waiting'] as List).contains(g.seat);
    final small = TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8));
    final order = over && view['ranking'] != null ? [for (final r in view['ranking'] as List) (r as num).toInt()] : List.generate(n, (i) => i);

    Widget chip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer, fontWeight: FontWeight.bold)),
        );

    Widget handRow(int s, String tile, List<String> hand) {
      final sv = seats[s];
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final f in codesOf(sv['flowers'])) M2FlowerTile(f, width: 18),
          const SizedBox(width: 4),
          for (final c in sortCodes(hand)) m2Tile(c, width: 24),
          const SizedBox(width: 4),
          for (final m in (sv['melds'] as List).cast<Map>()) ...[
            for (final t in codesOf(m['tiles'])) m2Tile(t, width: 20, faceDown: t == 'back'),
            const SizedBox(width: 3),
          ],
          const SizedBox(width: 6),
          m2Tile(tile, width: 24, highlight: true),
        ]),
      );
    }

    final body = <Widget>[];
    var noWin = true;
    if (isCs) {
      final events = (st['events'] as List).cast<Map>();
      for (final e in events) {
        final s = (e['seat'] as num).toInt();
        if (e['kind'] == 'qishou') {
          body.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('起手胡：${g.name(s)} ${e['text']}（每家付 ${(e['pay'] as Map).values.first}）', style: small),
          ));
          continue;
        }
        noWin = false;
        final from = (e['from'] as num).toInt();
        final items = [for (final it in (e['items'] as List).cast<List>()) (it[1] as num) > 1 ? '${it[0]}×${it[1]}' : '${it[0]}'];
        body.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              e['zimo'] == true ? '${g.name(s)} 自摸' : '${g.name(s)} 胡 ${g.name(from)} 的牌${e['rob'] == true ? '（抢杠）' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            handRow(s, e['tile'] as String, codesOf(e['hand'])),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: [for (final t in items) chip(t)]),
            const SizedBox(height: 2),
            Text(
              [for (final p in (e['pay'] as Map).entries) '${g.name(int.parse(p.key as String))} 付 ${p.value}'].join('，'),
              style: small,
            ),
          ]),
        ));
      }
      final birds = codesOf(st['birds']);
      if (birds.isNotEmpty) {
        final bs = [for (final b in st['birdSeats'] as List) (b as num).toInt()];
        body.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
            Text('扎鸟：', style: small),
            for (var i = 0; i < birds.length; i++)
              Column(mainAxisSize: MainAxisSize.min, children: [
                m2Tile(birds[i], width: 20, highlight: true),
                Text(g.name(bs[i]), style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis),
              ]),
          ]),
        ));
      }
      if (noWin) body.insert(0, Text('海底摸完，流局（庄家连庄）', style: small));
    } else {
      if (st['kind'] == 'win') {
        noWin = false;
        final s = (st['winner'] as num).toInt();
        final from = (st['from'] as num).toInt();
        final items = (st['items'] as List).cast<List>();
        body.addAll([
          Text(
            st['tsumo'] == true ? '${g.name(s)} 自摸' : '${g.name(s)} 和 ${g.name(from)} 的牌${st['rob'] == true ? '（抢杠）' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 6),
          handRow(s, st['tile'] as String, codesOf(seats[s]['hand'])),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final it in items) chip('${it[0]} ${it[1]}番${(it[2] as num) > 1 ? ' ×${it[2]}' : ''}'),
          ]),
          const SizedBox(height: 6),
          Text('共 ${st['fan']} 番 · ${st['tsumo'] == true ? '自摸 16+番' : '8+番'} = ${st['points']} 分',
              style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
        ]);
      } else if (st['kind'] == 'resign') {
        body.add(Text('${g.name((st['resigned'] as num?)?.toInt() ?? 0)} 认输', style: small));
      } else {
        body.add(Text('牌墙摸完，无人和牌（荒庄）', style: small));
      }
      if (st['resigned'] != null && st['kind'] != 'resign') {
        body.add(Text('${g.name((st['resigned'] as num).toInt())} 认输', style: small));
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
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
                  over ? '终局排名' : '第 ${st['hand']} 局结算${noWin ? '（流局）' : ''}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.primary),
                ),
              ),
              IconButton(onPressed: onHide, icon: const Icon(Icons.visibility), tooltip: '查看牌桌'),
            ]),
            Flexible(
              child: SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (over) Text('第 ${st['hand']} 局（最后一局）', style: small),
                  ...body,
                  const Divider(height: 14),
                  for (var i = 0; i < order.length; i++)
                    _scoreRow(context, order[i], over ? i + 1 : 0, delta[order[i]], (seats[order[i]]['score'] as num).toInt()),
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
        SizedBox(width: 64, child: Text('$total', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
      ]),
    );
  }
}
