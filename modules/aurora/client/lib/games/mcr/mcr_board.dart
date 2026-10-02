import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import 'mcr_panels.dart';
import 'mcr_tiles.dart';

List<String> codesOf(Object? l) => l is List ? [for (final e in l) e as String] : <String>[];

/// A called meld; the claimed tile lies sideways.
Widget mcrMeld(Map m, double tw) {
  final kind = m['kind'] as String;
  final tiles = codesOf(m['tiles']);
  final claimed = m['claimed'] as String?;
  var claimedIdx = -1;
  if (claimed != null && kind != 'agang') claimedIdx = kind == 'chi' ? tiles.indexOf(claimed) : 1;
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: tw * 0.12),
    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < tiles.length; i++)
        anyTile(tiles[i], width: tw, faceDown: kind == 'agang' && (i == 0 || i == 3), sideways: i == claimedIdx),
    ]),
  );
}

Widget flowerRow(List<String> fl, double tw) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (final f in fl) Padding(padding: EdgeInsets.only(right: tw * 0.05), child: FlowerTile(f, width: tw)),
    ]);

/// 国标麻将 / 广东推倒胡 — 雀魂-style table.
class McrBoard extends StatefulWidget {
  final GameContext g;
  const McrBoard(this.g, {super.key});
  @override
  State<McrBoard> createState() => _McrBoardState();
}

class _McrBoardState extends State<McrBoard> {
  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  bool _hideSettle = false;
  int _settleHand = -1;

  Map<String, dynamic> seatV(int s) => ((v['seats'] as List)[s] as Map).cast<String, dynamic>();
  String get phase => v['phase'] as String;
  bool get isMcr => v['rule'] == 'mcr';

  @override
  Widget build(BuildContext context) {
    if (v['seats'] == null) return const Center(child: CircularProgressIndicator());
    final settle = v['settle'] as Map?;
    final sh = settle == null ? -1 : (settle['hand'] as num).toInt();
    if (sh != _settleHand) {
      _settleHand = sh;
      _hideSettle = false;
    }
    final n = (v['seats'] as List).length;
    final base = g.seat < 0 ? 0 : g.seat;
    final pos = <int, int>{for (var i = 0; i < n; i++) (base + i) % n: i};
    final ev = (v['event'] as Map?)?.cast<String, dynamic>();
    var callText = mjEventLabel(ev?['t']);
    if (callText == '胡' && isMcr) callText = '和';
    final callSeat = (ev?['seat'] as num?)?.toInt() ?? -1;
    final callAlign = callSeat < 0
        ? Alignment.center
        : switch (pos[callSeat] ?? 0) {
            0 => const Alignment(0, 0.45),
            1 => const Alignment(0.6, 0),
            2 => const Alignment(0, -0.55),
            _ => const Alignment(-0.6, 0),
          };
    final showSettle = settle != null && (phase == 'settle' || phase == 'over');

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final handTile = [w / 19, h * 0.072, 52.0].reduce(math.min);
      final barH = handTile * 4 / 3 + handTile * 0.5 + 64;
      final tableH = math.max(160.0, h - barH - 36);
      final sq = math.min(w, tableH);
      return MjTableBackground(
        felt: g.table,
        child: Stack(children: [
          Column(children: [
            SizedBox(height: 34, child: Center(child: _status())),
            SizedBox(
              height: tableH,
              child: Stack(children: [
                Center(
                  child: SizedBox(
                    width: sq,
                    height: sq,
                    child: Stack(children: [
                      Center(child: _centerPanel(sq, pos)),
                      for (var s = 0; s < n; s++)
                        Positioned.fill(
                          child: RotatedBox(quarterTurns: const [0, 3, 2, 1][pos[s]!], child: _side(s, pos[s]!, sq)),
                        ),
                    ]),
                  ),
                ),
                for (var s = 0; s < n; s++) _tagFor(s, pos[s]!, w),
              ]),
            ),
          ]),
          _toggles(w, tableH, sq),
          Positioned.fill(child: McrHandBar(g: g, v: v, tileW: handTile)),
          Positioned.fill(child: MjCallBanner(text: callText, eventKey: ev?['seq'], alignment: callAlign)),
          if (showSettle && !_hideSettle) ...[
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
            Positioned.fill(
              child: MjResultEntrance(
                key: ValueKey('settle$sh$phase'),
                child: Center(child: McrSettlePanel(g: g, view: v, onHide: () => setState(() => _hideSettle = true))),
              ),
            ),
          ],
          if (showSettle && _hideSettle)
            Positioned(
              top: 40,
              right: 8,
              child: FilledButton.icon(
                onPressed: () => setState(() => _hideSettle = false),
                icon: const Icon(Icons.receipt_long),
                label: Text(phase == 'over' ? '最终结算' : '本局结算'),
              ),
            ),
        ]),
      );
    });
  }

  Widget _toggles(double w, double tableH, double sq) {
    if (g.seat < 0) return const SizedBox.shrink();
    final side = (w - sq) / 2;
    if (side >= 110) return Positioned(left: 8, top: 34 + tableH / 2 - 48, child: const MjAutoToggles());
    final free = (tableH - sq) / 2 - 46;
    if (free < 40) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      top: 34 + (tableH + sq) / 2 + 2,
      height: free,
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: const MjAutoToggles()),
    );
  }

  Widget _status() {
    final me = (v['me'] as Map?)?.cast<String, dynamic>();
    final seat = g.seat;
    var text = '${v['last'] ?? ''}';
    var hi = false;
    switch (phase) {
      case 'act':
        if (seat >= 0 && v['turn'] == seat) {
          hi = true;
          text = '轮到你出牌 · ${mjDiscardHint()}';
        }
      case 'claim':
        if (me?['claim'] != null) {
          hi = true;
          final tile = v['claimTile'] as String;
          final from = v['claimFrom'] as int;
          text = v['claimRob'] == true
              ? '${g.name(from)} 补杠 ${tileLabel(tile)}，可以抢杠${isMcr ? '和' : '胡'}'
              : '${g.name(from)} 打出 ${tileLabel(tile)}';
        }
      case 'settle':
        text = '本局结束';
      case 'over':
        text = '对局结束';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar('${isMcr ? '国标麻将' : '广东推倒胡'} · $text', highlight: hi)),
    );
  }

  Widget _centerPanel(double sq, Map<int, int> pos) {
    final dw = (sq * 0.05).clamp(11.0, 30.0);
    final cp = dw * 6.3;
    final dealer = v['dealer'] as int;
    final turn = v['turn'] as int;
    final edges = List.generate(4, (_) => (wind: '', score: '', dealer: false, active: false, present: false));
    for (final e in pos.entries) {
      final sv = seatV(e.key);
      edges[e.value] = (
        wind: windLabels[sv['wind'] as int],
        score: '${sv['score']}',
        dealer: e.key == dealer,
        active: turn == e.key && phase == 'act',
        present: true,
      );
    }
    final rule = isMcr ? '8番起和' : (v['minFan'] == 0 ? '鸡胡可胡' : '${v['minFan']}番起胡');
    return MjCenterPanel(
      size: cp,
      title: isMcr ? '${windLabels[v['roundWind'] as int]}风圈' : '第${v['hand']}局',
      subtitle: isMcr ? '第${v['hand']}/${v['hands']}局 · $rule' : '共${v['hands']}局 · $rule',
      wall: (v['wall'] as num).toInt(),
      edges: edges,
    );
  }

  Widget _side(int s, int rel, double sq) {
    final sv = seatV(s);
    final dw = (sq * 0.05).clamp(11.0, 30.0);
    final cp = dw * 6.3;
    final ds = (sv['discards'] as List).cast<Map>();
    final ev = v['event'] as Map?;
    final newestLive = ds.isNotEmpty && ds.last['taken'] != true;
    final fly = ev != null && ev['t'] == 'discard' && ev['seat'] == s && newestLive;
    final lastHi = v['lastDiscard'] == s && newestLive && (phase == 'act' || phase == 'claim');
    final children = <Widget>[
      Positioned(
        left: sq / 2 - cp / 2,
        top: sq / 2 + cp / 2 + dw * 0.15,
        child: _river(ds, dw, lastHi, fly ? ev['seq'] : null),
      ),
    ];
    if (rel != 0 || g.seat < 0) {
      final ot = (sq / 26).clamp(9.0, 26.0);
      final hand = sv['hand'];
      final count = sv['count'] as int;
      final tiles = <Widget>[];
      if (hand is List) {
        for (final cd in sortCodes(codesOf(hand))) {
          tiles.add(anyTile(cd, width: ot));
        }
      } else {
        for (var i = 0; i < count; i++) {
          if (i == count - 1 && sv['drawn'] == true) tiles.add(SizedBox(width: ot * 0.3));
          tiles.add(anyTile('back', width: ot, faceDown: true));
        }
      }
      final fl = codesOf(sv['flowers']);
      children.add(Positioned(
        left: 0,
        right: 0,
        bottom: 2,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (fl.isNotEmpty) ...[flowerRow(fl, ot * 0.8), SizedBox(width: ot * 0.4)],
              ...tiles,
              ...mjMelds(s, [for (final m in sv['melds'] as List) mcrMeld(m as Map, ot)], gap: ot * 0.2),
            ]),
          ),
        ),
      ));
    }
    return SizedBox(width: sq, height: sq, child: Stack(clipBehavior: Clip.none, children: children));
  }

  Widget _river(List<Map> ds, double dw, bool lastHi, Object? flyKey) {
    final rows = <List<Widget>>[];
    for (var i = 0; i < ds.length; i++) {
      if (i % 6 == 0) rows.add([]);
      final last = i == ds.length - 1;
      Widget t = anyTile(ds[i]['t'] as String, width: dw, dim: ds[i]['taken'] == true, highlight: lastHi && last);
      t = mjGiri(t, ds[i], dw);
      if (flyKey != null && last) t = MjDiscardFly(key: ValueKey(flyKey), highlight: false, child: t);
      rows.last.add(t);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final r in rows)
        Padding(padding: EdgeInsets.only(bottom: dw * 0.04), child: Row(mainAxisSize: MainAxisSize.min, children: r)),
    ]);
  }

  Widget _tagFor(int s, int rel, double w) {
    final sv = seatV(s);
    final active = phase == 'act' && v['turn'] == s;
    final waiting = (v['waiting'] as List).contains(s);
    final small = w < 600;
    final fl = codesOf(sv['flowers']);
    final chips = <Widget>[
      if (v['dealer'] == s) _chip('庄', Colors.deepOrange),
      if (fl.isNotEmpty) _chip('花${fl.length}', Colors.pink),
    ];
    final tag = MjTurnGlow(
      active: active,
      child: g.tag(s,
          active: active,
          size: small ? 24 : 32,
          sub: '${windLabels[sv['wind'] as int]}家 ${sv['score']}${phase == 'claim' && waiting ? ' · 思考中' : ''}',
          trailing: chips.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: chips)),
    );
    final align = switch (rel) {
      0 => Alignment.bottomRight,
      1 => Alignment.topRight,
      2 => Alignment.topLeft,
      _ => Alignment.bottomLeft,
    };
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: small ? 150 : 220), child: tag),
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        margin: const EdgeInsets.only(left: 3),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      );
}
