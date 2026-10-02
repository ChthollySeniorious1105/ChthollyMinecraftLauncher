import 'package:aurora_shared/games/monopoly/board_data.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'monopoly_painter.dart';
import 'monopoly_view.dart';

Color mPlayerColor(int s) => mPlayerColors[s % mPlayerColors.length];

/// Small round token for a player.
class MToken extends StatelessWidget {
  final int seat;
  final double size;
  final bool active;
  const MToken(this.seat, {super.key, this.size = 18, this.active = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mPlayerColor(seat),
        border: Border.all(color: active ? Colors.amberAccent : Colors.white, width: active ? 2.2 : 1.4),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black54, offset: Offset(0, 1))],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('${seat + 1}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
      ),
    );
  }
}

/// One row per player: avatar, cash, worth, status.
class MPlayersPanel extends StatelessWidget {
  final MView m;
  final bool compact;
  const MPlayersPanel(this.m, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ps = m.players;
    final owner = m.owner;
    final tiles = <Widget>[];
    for (var s = 0; s < ps.length; s++) {
      final p = ps[s];
      final props = [for (var i = 0; i < 40; i++) if (owner[i] == s) i].length;
      final flags = [
        if (p.bankrupt) '破产',
        if (p.jail) '在狱',
        if (p.cards > 0) '许可证×${p.cards}',
      ];
      final active = !m.isOver && m.turn == s;
      tiles.add(Opacity(
        opacity: p.bankrupt ? 0.45 : 1,
        child: Container(
          width: compact ? 172 : double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: active ? 0.95 : 0.75),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? cs.primary : mPlayerColor(s).withValues(alpha: 0.6), width: active ? 2 : 1),
          ),
          child: Row(children: [
            MToken(s, size: 16, active: active),
            const SizedBox(width: 4),
            Avatar(m.g.avatar(s), size: 26, bot: m.g.bot(s)),
            const SizedBox(width: 5),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Flexible(
                    child: Text(m.g.name(s) + (s == m.me ? '（我）' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
                  ),
                  const SizedBox(width: 4),
                  Text('¥${p.cash}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: p.cash < 100 ? Colors.red.shade400 : cs.primary)),
                ]),
                Text('资产 ¥${p.worth} · 地产 $props${flags.isEmpty ? '' : ' · ${flags.join(' ')}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.7))),
              ]),
            ),
          ]),
        ),
      ));
    }
    if (compact) return Wrap(spacing: 6, runSpacing: 6, children: tiles);
    return Column(children: [for (final t in tiles) Padding(padding: const EdgeInsets.only(bottom: 4), child: t)]);
  }
}


/// Details of one square with management buttons (pure view of current state).
class MPropertyCard extends StatelessWidget {
  final MView m;
  final int sq;
  final VoidCallback onClose;
  const MPropertyCard(this.m, this.sq, {super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = mBoard[sq];
    final o = m.owner[sq];
    final h = m.houses[sq];
    final mort = m.mortgaged[sq];
    final head = s.type == SqType.street ? mGroupColors[s.group] : cs.primaryContainer;
    final headInk = s.type == SqType.street && (s.group == 1 || s.group == 5) ? Colors.black87 : Colors.white;
    final rows = <(String, String)>[];
    if (s.type == SqType.street) {
      rows.add(('基础租金', '¥${s.rents[0]}（整组 ¥${s.rents[0] * 2}）'));
      for (var k = 1; k <= 4; k++) {
        rows.add(('$k 栋房屋', '¥${s.rents[k]}'));
      }
      rows.add(('酒店', '¥${s.rents[5]}'));
      rows.add(('建房费用', '¥${s.houseCost} / 栋'));
    } else if (s.type == SqType.station) {
      rows.addAll([('1 座车站', '¥25'), ('2 座车站', '¥50'), ('3 座车站', '¥100'), ('4 座车站', '¥200')]);
    } else if (s.type == SqType.utility) {
      rows.addAll([('拥有 1 家', '骰子点数 ×4'), ('拥有 2 家', '骰子点数 ×10')]);
    } else if (s.type == SqType.tax) {
      rows.add(('缴税', '¥${s.rents[0]}'));
    } else {
      rows.add(('说明', _cornerText(s)));
    }
    if (s.ownable) rows.add(('抵押 / 赎回', '¥${s.mortgage} / ¥${s.unmortgageCost}'));

    final btns = <Widget>[];
    if (m.canManage && o == m.me) {
      void add(String k, String label, IconData ic) {
        final ok = m.legal(k).contains(sq);
        btns.add(OutlinedButton.icon(
          onPressed: ok ? () => m.g.act({'t': k, 'sq': sq}) : null,
          icon: Icon(ic, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        ));
      }

      if (s.type == SqType.street) {
        add('build', h == 4 ? '建酒店 ¥${s.houseCost}' : '建房 ¥${s.houseCost}', Icons.home_work);
        add('sell', '拆房 +¥${s.houseCost ~/ 2}', Icons.remove_circle_outline);
      }
      add('mortgage', '抵押 +¥${s.mortgage}', Icons.lock_outline);
      add('unmortgage', '赎回 ¥${s.unmortgageCost}', Icons.lock_open);
    }

    return Material(
      color: cs.surface,
      elevation: 10,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: head,
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mSqKind(s), style: TextStyle(fontSize: 11, color: headInk.withValues(alpha: 0.8))),
                  Text(s.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: headInk)),
                ]),
              ),
              if (s.ownable) Text('¥${s.price}', style: TextStyle(fontWeight: FontWeight.bold, color: headInk)),
              IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: headInk, size: 18),
                  visualDensity: VisualDensity.compact),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s.ownable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      if (o >= 0) ...[MToken(o, size: 14), const SizedBox(width: 4)],
                      Expanded(
                        child: Text(
                          o < 0
                              ? '无主（可购买）'
                              : '${m.g.name(o)}${mort ? ' · 已抵押' : ''}${h == 5 ? ' · 酒店' : h > 0 ? ' · $h 栋房屋' : ''}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                        ),
                      ),
                    ]),
                  ),
                for (final r in rows)
                  Row(children: [
                    Expanded(child: Text(r.$1, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                    Text(r.$2, style: TextStyle(fontSize: 12, color: cs.onSurface, fontWeight: FontWeight.w600)),
                  ]),
                if (btns.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: btns),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  static String _cornerText(Sq s) => switch (s.type) {
        SqType.go => '经过或停留领取 ¥200',
        SqType.jail => '入狱玩家在此；路过只是探监',
        SqType.parking => '休息一下（开启奖池时可领取奖池）',
        SqType.goToJail => '直接入狱，不经过起点',
        SqType.chance => '抽一张机会卡',
        SqType.chest => '抽一张命运卡',
        _ => '',
      };
}
