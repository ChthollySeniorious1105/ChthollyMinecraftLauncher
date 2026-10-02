import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import '../../widgets/pieces.dart';
import 'sichuan_panels.dart';

const suitLabels = ['万', '筒', '条'];
const suitColors = [Color(0xFFE53935), Color(0xFF1E88E5), Color(0xFF43A047)];
const _winds = ['东', '南', '西', '北'];
const dirText = {1: '换给下家', 2: '换给对家', 3: '换给上家'};

int codeSuit(String c) => 'mps'.indexOf(c[1]);
int codeRank(String c) => int.tryParse(c[0]) ?? 0;

/// Sort tile codes by suit (缺 suit last) then rank.
List<String> sortCodes(Iterable<String> codes, int que) {
  int key(String c) {
    final s = codeSuit(c);
    return (s == que ? 3 : s) * 10 + codeRank(c);
  }

  return codes.toList()..sort((a, b) => key(a).compareTo(key(b)));
}

String tileLabel(String c) => '${'一二三四五六七八九'[codeRank(c) - 1]}${suitLabels[codeSuit(c)]}';

List<String> codesOf(Object? l) => l is List ? [for (final e in l) e as String] : <String>[];

/// A 碰/杠 meld; the claimed tile lies sideways on the side of the player it came from.
Widget sichuanMeld(Map m, double tw, int owner, int players) {
  final t = m['tile'] as String;
  final kind = m['kind'] as String;
  final n = kind == 'peng' ? 3 : 4;
  final from = (m['from'] as num?)?.toInt() ?? -1;
  var side = -1;
  if (from >= 0 && kind != 'agang') {
    final rel = (from - owner + players) % players;
    side = rel == players - 1 ? 0 : (rel == 1 ? n - 1 : 1);
  }
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: tw * 0.12),
    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 0; i < n; i++)
        MahjongTile(t, width: tw, faceDown: kind == 'agang' && (i == 0 || i == 3), sideways: i == side),
    ]),
  );
}

/// 四川麻将（血战到底）— 雀魂-style table.
class SichuanBoard extends StatefulWidget {
  final GameContext g;
  const SichuanBoard(this.g, {super.key});
  @override
  State<SichuanBoard> createState() => _SichuanBoardState();
}

class _SichuanBoardState extends State<SichuanBoard> {
  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  bool _hideSettle = false;
  int _settleHand = -1;

  Map<String, dynamic> seatV(int s) => ((v['seats'] as List)[s] as Map).cast<String, dynamic>();
  String get phase => v['phase'] as String;

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
    final callText = mjEventLabel(ev?['t']);
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
      final handTile = [w / 17.5, h * 0.075, 54.0].reduce(math.min);
      final barH = handTile * 4 / 3 + handTile * 0.5 + 64;
      final tableH = math.max(160.0, h - barH - 36);
      final sq = math.min(w, tableH);
      return MjTableBackground(
        felt: g.table,
        child: Stack(children: [
          Column(children: [
            SizedBox(height: 34, child: Center(child: _status(w))),
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
                          child: RotatedBox(quarterTurns: const [0, 3, 2, 1][pos[s]!], child: _side(s, pos[s]!, sq, n)),
                        ),
                    ]),
                  ),
                ),
                for (var s = 0; s < n; s++) _tagFor(s, pos[s]!, w),
              ]),
            ),
          ]),
          _toggles(w, tableH, sq),
          Positioned.fill(child: SichuanHandBar(g: g, v: v, tileW: handTile)),
          Positioned.fill(child: MjCallBanner(text: callText, eventKey: ev?['seq'], alignment: callAlign)),
          if (showSettle && !_hideSettle) ...[
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
            Positioned.fill(
              child: MjResultEntrance(
                key: ValueKey('settle$sh$phase'),
                child: Center(child: SettlePanel(g: g, view: v, onHide: () => setState(() => _hideSettle = true))),
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

  /// 雀魂 quick toggles: in the free side margin, or under the table square on tall screens.
  Widget _toggles(double w, double tableH, double sq) {
    if (g.seat < 0) return const SizedBox.shrink();
    final side = (w - sq) / 2;
    if (side >= 110) {
      return Positioned(left: 8, top: 34 + tableH / 2 - 48, child: const MjAutoToggles());
    }
    final free = (tableH - sq) / 2 - 46;
    if (free < 40) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      top: 34 + (tableH + sq) / 2 + 2,
      height: free,
      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topLeft, child: const MjAutoToggles()),
    );
  }

  Widget _status(double w) {
    final me = (v['me'] as Map?)?.cast<String, dynamic>();
    final seat = g.seat;
    var text = '${v['last'] ?? ''}';
    var hi = false;
    switch (phase) {
      case 'swap':
        hi = me != null && me['swapPick'] == null;
        text = hi ? '换三张：选择三张同花色的牌' : '换三张：等待其他玩家…';
      case 'que':
        hi = me != null && me['quePick'] == null;
        final got = codesOf(me?['swapGot']);
        final dir = (v['swapDir'] as num?)?.toInt() ?? 0;
        final swapped = v['swapOn'] == true && got.isNotEmpty ? '${dirText[dir]}，换入 ${got.map(tileLabel).join(' ')} · ' : '';
        text = hi ? '$swapped请选择定缺花色' : '定缺：等待其他玩家…';
      case 'act':
        if (seat >= 0 && v['turn'] == seat) {
          hi = true;
          final que = seatV(seat)['que'] as int;
          final disc = codesOf(me?['discardable']);
          final mustQue = disc.isNotEmpty && que >= 0 && disc.every((c) => codeSuit(c) == que);
          text = mustQue ? '请先打缺门（${suitLabels[que]}）' : '轮到你出牌 · ${mjDiscardHint()}';
        }
      case 'claim':
        if (me?['claim'] != null) {
          hi = true;
          final tile = v['claimTile'] as String;
          final from = v['claimFrom'] as int;
          text = v['claimQiang'] == true ? '${g.name(from)} 补杠 ${tileLabel(tile)}，可以抢杠胡' : '${g.name(from)} 打出 ${tileLabel(tile)}';
        }
      case 'settle':
        text = '本局结束';
      case 'over':
        text = '对局结束';
    }
    if (seat >= 0 && !hi && (seatV(seat)['won'] as int) > 0 && (phase == 'act' || phase == 'claim')) {
      text = '你已胡牌，观战中 · $text';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar('血战到底 · $text', highlight: hi)),
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
        wind: _winds[(e.key - dealer + 4) % 4],
        score: (sv['won'] as int) > 0 ? '${sv['score']} 胡' : '${sv['score']}',
        dealer: e.key == dealer,
        active: turn == e.key && phase == 'act',
        present: true,
      );
    }
    return MjCenterPanel(
      size: cp,
      title: '第${v['hand']}局',
      subtitle: '共${v['hands']}局 · 封顶${v['cap']}番',
      wall: (v['wall'] as num).toInt(),
      edges: edges,
    );
  }

  /// One seat's river + (for opponents) hand, laid out as if the seat were at the bottom.
  Widget _side(int s, int rel, double sq, int n) {
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
      final que = sv['que'] as int;
      final won = sv['won'] as int;
      final tiles = <Widget>[];
      if (hand is List) {
        for (final cd in sortCodes(codesOf(hand), que)) {
          tiles.add(MahjongTile(cd, width: ot));
        }
      } else {
        for (var i = 0; i < count; i++) {
          if (i == count - 1 && sv['drawn'] == true) tiles.add(SizedBox(width: ot * 0.3));
          tiles.add(MahjongTile('back', width: ot, faceDown: true));
        }
      }
      children.add(Positioned(
        left: 0,
        right: 0,
        bottom: 2,
        child: Center(
          child: Opacity(
            opacity: won > 0 ? 0.8 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                ...tiles,
                ...mjMelds(s, [for (final m in sv['melds'] as List) sichuanMeld(m as Map, ot, s, n)], gap: ot * 0.2),
                if (won > 0 && sv['winTile'] != null) ...[
                  SizedBox(width: ot * 0.4),
                  MahjongTile(sv['winTile'] as String, width: ot, highlight: true, badge: '胡'),
                ],
              ]),
            ),
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
      Widget t = MahjongTile(ds[i]['t'] as String, width: dw, dim: ds[i]['taken'] == true, highlight: lastHi && last);
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
    final que = sv['que'] as int;
    final won = sv['won'] as int;
    final active = phase == 'act' && v['turn'] == s;
    final waiting = (v['waiting'] as List).contains(s);
    final small = w < 600;
    String? status;
    if (phase == 'swap') status = sv['swapDone'] == true ? '已选牌' : '选牌中';
    if (phase == 'que') status = sv['queDone'] == true ? '已定缺' : '定缺中';
    if (phase == 'claim' && waiting) status = '思考中';
    final chips = <Widget>[
      if (v['dealer'] == s) _chip('庄', Colors.deepOrange),
      if (que >= 0) _chip('缺${suitLabels[que]}', suitColors[que]),
      if (won > 0) _chip('胡${won <= 3 ? '①②③'[won - 1] : won}', MjColors.win),
    ];
    final tag = MjTurnGlow(
      active: active,
      child: g.tag(s,
          active: active,
          size: small ? 24 : 32,
          sub: '${sv['score']}${status == null ? '' : ' · $status'}',
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
