import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/mahjong_table.dart';
import 'hand_bar.dart';
import 'result_panel.dart';
import 'tile_widgets.dart';

const _modeNames = {
  'riichi4': '四人麻将',
  'riichi3': '三人麻将',
  'shura': '修罗之战',
  'wanxiang': '万象修罗',
  'mingjing': '明镜之战',
  'anye': '暗夜之战',
};

/// Mahjong-Soul style riichi table.
class RiichiBoard extends StatefulWidget {
  final GameContext g;
  const RiichiBoard(this.g, {super.key});
  @override
  State<RiichiBoard> createState() => _RiichiBoardState();
}

class _RiichiBoardState extends State<RiichiBoard> {
  bool hideResult = false;
  int lastSerial = -1;

  GameContext get g => widget.g;

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    if (v['seats'] == null) return const Center(child: CircularProgressIndicator());
    final n = (v['n'] as num).toInt();
    final seats = (v['seats'] as List).cast<Map>();
    final phase = v['phase'] as String;
    final turn = (v['turn'] as num).toInt();
    final base = g.seat < 0 ? 0 : g.seat;
    // relative position -> seat. 3 players: me, right, left (no top).
    final pos = <int, int>{};
    for (var i = 0; i < n; i++) {
      final s = (base + i) % n;
      pos[s] = n == 3 ? [0, 1, 3][i] : i;
    }
    final res = v['result'] as Map?;
    final serial = (res?['serial'] as num?)?.toInt() ?? -1;
    if (serial != lastSerial) {
      lastSerial = serial;
      hideResult = false;
    }
    final showResult = res != null && (phase == 'result' || phase == 'over') && !hideResult;
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final callText = mjEventLabel(last?['t']);
    final callSeat = (last?['seat'] as num?)?.toInt() ?? -1;
    final callAlign = callSeat < 0
        ? Alignment.center
        : switch (pos[callSeat] ?? 0) {
            0 => const Alignment(0, 0.45),
            1 => const Alignment(0.6, 0),
            2 => const Alignment(0, -0.55),
            _ => const Alignment(-0.6, 0),
          };

    return LayoutBuilder(builder: (context, c) {
      final W = c.maxWidth, H = c.maxHeight;
      final handTile = [W / 17.5, H * 0.075, 54.0].reduce((a, b) => a < b ? a : b);
      final barH = handTile * 4 / 3 + handTile * 0.5 + 64;
      final tableH = (H - barH - 36).clamp(160.0, double.infinity);
      final S = W < tableH ? W : tableH;
      return MjTableBackground(
        felt: g.table,
        child: Stack(children: [
          Column(children: [
            SizedBox(height: 34, child: Center(child: _status(context, v, seats, turn, phase))),
            SizedBox(
              height: tableH,
              child: Stack(children: [
                Center(
                  child: SizedBox(
                    width: S,
                    height: S,
                    child: Stack(children: [
                      Center(child: _centerPanel(context, v, S, pos, seats, turn, phase)),
                      for (var s = 0; s < n; s++)
                        Positioned.fill(
                          child: RotatedBox(
                            quarterTurns: const [0, 3, 2, 1][pos[s]!],
                            child: _side(context, v, s, pos[s]!, S, n),
                          ),
                        ),
                    ]),
                  ),
                ),
                for (var s = 0; s < n; s++) _tagFor(v, s, pos[s]!, seats, turn, S, W),
              ]),
            ),
          ]),
          // Hand + floating action buttons (buttons may overlap the table like Mahjong Soul).
          Positioned.fill(child: RiichiHandBar(g: g, v: v, tileW: handTile)),
          Positioned.fill(
            child: MjCallBanner(text: callText, eventKey: last?['seq'], alignment: callAlign),
          ),
        ]),
      );
    }).withOverlay(showResult
        ? Positioned.fill(
            child: Stack(children: [
              Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
              Positioned.fill(child: MjResultEntrance(key: ValueKey(serial), child: RiichiResultPanel(g, v))),
              if (phase != 'over')
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton.filledTonal(
                    tooltip: '查看牌桌',
                    onPressed: () => setState(() => hideResult = true),
                    icon: const Icon(Icons.visibility),
                  ),
                ),
            ]),
          )
        : (res != null && (phase == 'result' || phase == 'over'))
            ? Positioned(
                right: 8,
                top: 40,
                child: FilledButton.icon(
                  onPressed: () => setState(() => hideResult = false),
                  icon: const Icon(Icons.emoji_events),
                  label: const Text('结算'),
                ),
              )
            : null);
  }

  Widget _status(BuildContext context, Map v, List<Map> seats, int turn, String phase) {
    String text;
    var hi = false;
    final me = (v['me'] as Map?);
    switch (phase) {
      case 'exchange':
        final dir = (v['exchDir'] as num?)?.toInt() ?? 0;
        final d = dir == 1 ? '交给下家' : (dir == -1 ? '交给上家' : '交给对家');
        text = me != null && me['exchPicked'] != true ? '换三张：任选 3 张牌（$d）' : '换三张（$d）：等待其他玩家';
        hi = me != null && me['exchPicked'] != true;
      case 'turn':
        hi = turn == g.seat;
        text = hi ? '轮到你出牌 · ${mjDiscardHint()}' : '等待 ${g.name(turn)} 出牌';
      case 'call':
      case 'chankan':
        hi = me?['call'] != null;
        text = hi ? '可以鸣牌 / 和牌' : '等待其他玩家操作';
      case 'anyeOpen':
        hi = me?['canOpen'] == true;
        text = hi ? '${g.name((v['discarder'] as num).toInt())} 打出暗牌：是否支付 2000 点开牌？' : '有人打出暗牌';
      case 'anyeLock':
        hi = me?['canLock'] == true;
        text = hi ? '暗牌被开：是否支付 4000 点锁定？' : '等待暗牌者决定是否锁定';
      case 'result':
        text = '本局结束';
      case 'over':
        text = '对局结束';
      default:
        text = '';
    }
    return StatusBar('${_modeNames[v['mode']] ?? ''} · $text', highlight: hi);
  }

  /// One player's river + (for opponents) hand, laid out as if they sat at the bottom.
  Widget _side(BuildContext context, Map v, int s, int rel, double S, int n) {
    final seat = v['seats'][s] as Map;
    final dw = (S * 0.058).clamp(12.0, 34.0);
    final cp = dw * 6.3;
    final last = v['last'] as Map?;
    final lastDiscard = last != null &&
        (last['t'] == 'discard' || last['t'] == 'riichi') &&
        (last['seat'] as num).toInt() == s &&
        (v['phase'] == 'call' || v['phase'] == 'anyeOpen' || v['phase'] == 'anyeLock' || v['phase'] == 'turn');
    final children = <Widget>[
      Positioned(
        left: S / 2 - cp / 2,
        top: S / 2 + cp / 2 + dw * 0.15,
        child: RiverView((seat['river'] as List), width: dw, lastHighlight: lastDiscard, flyKey: lastDiscard ? last['seq'] : null),
      ),
    ];
    if (rel != 0) {
      final ot = (S / 26).clamp(9.0, 26.0);
      final hand = (seat['hand'] as List).cast<String>();
      final drawn = seat['drawn'] as String?;
      final melds = (seat['melds'] as List).cast<Map>();
      final kita = (seat['kita'] as List).cast<String>();
      children.add(Positioned(
        left: 0,
        right: 0,
        bottom: 2,
        child: Center(
          child: FittedBox(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final t in hand) RTile(t, width: ot),
              if (drawn != null) ...[SizedBox(width: ot * 0.3), RTile(drawn, width: ot)],
              if (kita.isNotEmpty) ...[SizedBox(width: ot * 0.5), for (final k in kita) RTile(k, width: ot * 0.9)],
              ...mjMelds(s, [for (final m in melds) MeldView(m, owner: s, players: n, width: ot)], gap: ot * 0.3),
            ]),
          ),
        ),
      ));
    }
    if (seat['riichi'] == true) {
      children.add(Positioned(
        left: S / 2 - cp * 0.3,
        top: S / 2 + cp / 2 + dw * 0.02 - dw * 0.12,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutBack,
          builder: (_, t, c) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.scale(scale: t, child: c)),
          child: RiichiStick(length: cp * 0.6),
        ),
      ));
    }
    return SizedBox(width: S, height: S, child: Stack(clipBehavior: Clip.none, children: children));
  }

  Widget _centerPanel(BuildContext context, Map v, double S, Map<int, int> pos, List<Map> seats, int turn, String phase) {
    final dw = (S * 0.058).clamp(12.0, 34.0);
    final cp = dw * 6.3;
    final rw = (v['roundWind'] as num).toInt();
    final ky = (v['kyoku'] as num).toInt();
    final dora = (v['dora'] as List).cast<String>();
    final edges = List.generate(4, (_) => (wind: '', score: '', dealer: false, active: false, present: false));
    for (final e in pos.entries) {
      final seat = seats[e.key];
      final wind = (seat['wind'] as num).toInt();
      edges[e.value] = (
        wind: windName(wind),
        score: seat['won'] == true ? '${seat['score']} 和' : '${seat['score']}',
        dealer: wind == 0,
        active: turn == e.key && (phase == 'turn'),
        present: true,
      );
    }
    return MjCenterPanel(
      size: cp,
      title: '${windName(rw)}${ky + 1}局',
      subtitle: '${v['honba']}本场 · 供托 ${v['kyoutaku']}',
      wall: (v['wall'] as num).toInt(),
      edges: edges,
      extra: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [for (final d in dora) RTile(d, width: 16)]),
        if (v['wallPeek'] is List && (v['wallPeek'] as List).isNotEmpty) ...[
          const SizedBox(height: 3),
          const Text('牌山', style: TextStyle(color: Colors.white54, fontSize: 9)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final d in (v['wallPeek'] as List).cast<String>()) RTile(d, width: 11),
          ]),
        ],
      ]),
    );
  }

  Widget _tagFor(Map v, int s, int rel, List<Map> seats, int turn, double S, double W) {
    final seat = seats[s];
    final wind = (seat['wind'] as num).toInt();
    final active = turn == s && v['phase'] == 'turn';
    final small = W < 600;
    final tag = MjTurnGlow(
      active: active,
      child: g.tag(s,
          active: active,
          size: small ? 24 : 32,
          sub: '${windName(wind)}家 ${seat['score']}${seat['riichi'] == true ? ' 立直' : ''}'),
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
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: small ? 120 : 180), child: tag),
      ),
    );
  }
}

extension _Overlay on Widget {
  Widget withOverlay(Widget? overlay) => overlay == null ? this : Stack(children: [Positioned.fill(child: this), overlay]);
}
