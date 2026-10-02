import 'dart:math';

import 'package:aurora_shared/games/monopoly/board_data.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'monopoly_actions.dart';
import 'monopoly_painter.dart';
import 'monopoly_panels.dart';
import 'monopoly_view.dart';

class MonopolyBoard extends StatefulWidget {
  final GameContext g;
  const MonopolyBoard(this.g, {super.key});
  @override
  State<MonopolyBoard> createState() => _MonopolyBoardState();
}

class _MonopolyBoardState extends State<MonopolyBoard> {
  int sel = -1; // property card shown

  @override
  Widget build(BuildContext context) {
    final m = MView(widget.g);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final wide = w > h * 1.15;
      if (wide) {
        final side = min(h - 8, w * 0.62);
        final panelW = w - side - 16;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.all(4), child: _board(m, side)),
          SizedBox(
            width: panelW,
            height: h,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 6, 6),
              child: Column(children: [
                StatusBar(m.status(), highlight: _needsMe(m)),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      _panel(context, m, MActionPanel(m, onTrade: () => showTradeDialog(context, m))),
                      const SizedBox(height: 6),
                      MPlayersPanel(m),
                      const SizedBox(height: 4),
                      _bank(context, m),
                      _events(context, m),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ]);
      }
      final side = min(w - 8, h * 0.56);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
          child: FittedBox(fit: BoxFit.scaleDown, child: StatusBar(m.status(), highlight: _needsMe(m))),
        ),
        const SizedBox(height: 4),
        _board(m, side),
        const SizedBox(height: 4),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(children: [
              _panel(context, m, MActionPanel(m, onTrade: () => showTradeDialog(context, m))),
              const SizedBox(height: 6),
              MPlayersPanel(m, compact: true),
              const SizedBox(height: 4),
              _bank(context, m),
              _events(context, m),
            ]),
          ),
        ),
      ]);
    });
  }

  bool _needsMe(MView m) {
    if (m.isOver || m.me < 0) return false;
    return switch (m.phase) {
      'auction' => m.auction?['waiting'] is List && (m.auction!['waiting'] as List).contains(m.me),
      'debt' => m.iAmDebtor,
      'trade' => m.trade?['to'] == m.me,
      _ => m.myTurn,
    };
  }

  Widget _panel(BuildContext context, MView m, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: child,
    );
  }

  Widget _bank(BuildContext context, MView m) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '银行剩余：房屋 ${m.housesLeft}/32 · 酒店 ${m.hotelsLeft}/12${m.potOn ? ' · 停车奖池 ¥${m.pot}' : ''}',
        style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.75)),
      ),
    );
  }

  Widget _events(BuildContext context, MView m) {
    final cs = Theme.of(context).colorScheme;
    final ev = m.events.reversed.take(6).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < ev.length; i++)
          Text(ev[i],
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: i == 0 ? 1 : 0.65),
                  fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }

  Set<int> _highlight(MView m) {
    if (!m.canManage) return const {};
    if (m.phase == 'debt') return {...m.legal('mortgage'), ...m.legal('sell')};
    return m.legal('build').toSet();
  }

  Widget _board(MView m, double side) {
    final u = side / MGeo.total;
    final ps = m.players;
    final tokens = <Widget>[];
    final byCell = <int, List<int>>{};
    for (var s = 0; s < ps.length; s++) {
      if (ps[s].bankrupt) continue;
      byCell.putIfAbsent(ps[s].pos, () => []).add(s);
    }
    final ts = u * 0.42;
    for (final e in byCell.entries) {
      final r = MGeo.cell(e.key, u);
      final list = e.value;
      final jailed = e.key == mJailSq ? list.where((s) => ps[s].jail).toList() : <int>[];
      final free = list.where((s) => !jailed.contains(s)).toList();
      void place(List<int> ss, Rect area) {
        final cols = ss.length <= 2 ? ss.length : 3;
        final rows = (ss.length / max(cols, 1)).ceil();
        for (var k = 0; k < ss.length; k++) {
          final cx = area.left + area.width * ((k % cols) + 0.5) / cols;
          final cy = area.top + area.height * ((k ~/ cols) + 0.5) / rows;
          tokens.add(AnimatedPositioned(
            key: ValueKey('tok${ss[k]}'),
            duration: const Duration(milliseconds: 350),
            left: cx - ts / 2,
            top: cy - ts / 2,
            child: IgnorePointer(child: MToken(ss[k], size: ts, active: !m.isOver && ss[k] == m.turn)),
          ));
        }
      }

      if (e.key == mJailSq) {
        place(jailed, Rect.fromLTWH(r.left + r.width * 0.3, r.top, r.width * 0.7, r.height * 0.7));
        place(free, Rect.fromLTWH(r.left, r.top + r.height * 0.7, r.width, r.height * 0.3));
      } else {
        final body = MGeo.side(e.key) < 0 ? r.deflate(u * 0.2) : MGeo.bodyRect(e.key, u);
        place(free, Rect.fromCenter(center: body.center, width: body.width * 0.9, height: body.height * 0.55));
      }
    }

    final inner = Rect.fromLTWH(MGeo.corner * u, MGeo.corner * u, 9 * u, 9 * u);
    final dice = m.dice;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: GestureDetector(
            onTapUp: (d) {
              final i = MGeo.hit(d.localPosition, u);
              setState(() => sel = i == null || i == sel ? -1 : i);
            },
            child: CustomPaint(
              painter: MonopolyPainter(
                cs: Theme.of(context).colorScheme,
                owner: m.owner,
                houses: m.houses,
                mortgaged: m.mortgaged,
                highlight: _highlight(m),
                focus: m.focus,
                pot: m.pot,
                potOn: m.potOn,
              ),
            ),
          ),
        ),
        // centre: dice and last event
        Positioned.fromRect(
          rect: inner.deflate(inner.width * 0.18),
          child: IgnorePointer(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (dice.length == 2 && dice[0] > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    DieFace(dice[0], size: 44),
                    const SizedBox(width: 10),
                    DieFace(dice[1], size: 44),
                  ]),
                const SizedBox(height: 8),
                if (m.events.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(m.events.last,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: Color(0xFF263238), fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ),
        ),
        ...tokens,
        if (sel >= 0)
          Positioned.fromRect(
            rect: inner.deflate(u * 0.1),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 280,
                  child: MPropertyCard(m, sel, onClose: () => setState(() => sel = -1)),
                ),
              ),
            ),
          ),
        if (m.isOver && sel < 0)
          Positioned.fromRect(
            rect: inner,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: _result(m))),
          ),
      ]),
    );
  }

  Widget _result(MView m) {
    final w = m.winner;
    return ResultBanner(
      w >= 0 ? '${m.g.name(w)} 获胜！' : '游戏结束',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var k = 0; k < m.result.length; k++)
          Builder(builder: (context) {
            final r = m.result[k];
            final s = (r['seat'] as num).toInt();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${k + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold)),
                MToken(s, size: 14),
                const SizedBox(width: 4),
                Text('${m.g.name(s)}  ${r['bankrupt'] == true ? '破产' : '总资产 ¥${r['worth']}'}'),
              ]),
            );
          }),
      ]),
    );
  }
}
