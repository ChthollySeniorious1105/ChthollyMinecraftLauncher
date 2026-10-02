import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'race_common.dart';

class DaVinciBoard extends StatefulWidget {
  final GameContext g;
  const DaVinciBoard(this.g, {super.key});
  @override
  State<DaVinciBoard> createState() => _DaVinciBoardState();
}

class _DaVinciBoardState extends State<DaVinciBoard> {
  (int, int)? pick; // (target seat, index)

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final hands = [
      for (final h in v['hands'] as List) [for (final t in h as List) (t as Map).cast<String, dynamic>()],
    ];
    final turn = v['turn'] as int;
    final phase = v['phase'] as String;
    final winner = v['winner'] as int;
    final alive = (v['alive'] as List).cast<bool>();
    final deck = v['deck'] as int;
    final correct = v['correct'] as int;
    final joker = v['joker'] == true;
    final pending = (v['pending'] as Map?)?.cast<String, dynamic>();
    final last = (v['last'] as Map?)?.cast<String, dynamic>();
    final me = g.seat;
    final myTurn = !g.over && winner < 0 && turn == me;
    final cs = Theme.of(context).colorScheme;
    if (!myTurn || phase != 'guess') pick = null;
    if (pick != null) {
      final (t, i) = pick!;
      if (i >= hands[t].length || hands[t][i]['r'] == true) pick = null;
    }

    String status;
    if (winner >= 0) {
      status = '${g.name(winner)} 获胜！';
    } else if (myTurn) {
      status = switch (phase) {
        'placeJoker' => '你摸到了百搭牌，点击插入位置',
        'reveal' => '猜错了！牌堆已空，请翻开自己的一张暗牌',
        _ => correct > 0 ? '猜中了！可以继续猜，或停止' : (pick == null ? '点击对手的一张暗牌进行猜测' : '选择你猜的数字'),
      };
    } else {
      status = '等待 ${g.name(turn)}${phase == 'placeJoker' ? ' 放置百搭牌' : ' 猜牌'}';
    }

    String lastText = '';
    if (last != null && last['target'] != null) {
      final val = last['value'] as int;
      lastText = '${g.name(last['seat'] as int)} 猜 ${g.name(last['target'] as int)} 的第 ${(last['index'] as int) + 1} 张是 '
          '${val == 12 ? '-' : val}：${last['ok'] == true ? '猜中！' : '猜错'}';
    } else if (last != null && last['stop'] == true) {
      lastText = '${g.name(last['seat'] as int)} 停止猜牌';
    }

    Widget row(int s, double tw) {
      final h = hands[s];
      final isMe = s == me;
      final canPlace = isMe && myTurn && phase == 'placeJoker';
      final children = <Widget>[];
      for (var i = 0; i <= h.length; i++) {
        if (canPlace) {
          children.add(_InsertSlot(width: tw * 0.45, height: tw * 1.45, onTap: () => g.act({'t': 'place', 'pos': i})));
        }
        if (i == h.length) break;
        final t = h[i];
        final hidden = t['r'] != true;
        final selectable = myTurn && phase == 'guess' && !isMe && hidden && alive[s];
        final revealPick = myTurn && phase == 'reveal' && isMe && hidden;
        final lastHit = last != null && last['target'] == s && last['index'] == i;
        children.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: tw * 0.05),
          child: _Tile(
            color: t['c'] as int,
            value: t['v'] as int?,
            revealed: !hidden,
            fresh: t['f'] == true,
            width: tw,
            selected: pick == (s, i),
            highlight: selectable || revealPick,
            flash: lastHit,
            wrong: (t['w'] as List).cast<int>(),
            onTap: selectable
                ? () => setState(() => pick = pick == (s, i) ? null : (s, i))
                : revealPick
                    ? () => g.act({'t': 'reveal', 'index': i})
                    : null,
          ),
        ));
      }
      final left = h.where((t) => t['r'] != true).length;
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: alive[s] ? 0.35 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s == turn && winner < 0 ? cs.primary : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          g.tag(s,
              active: winner < 0 && turn == s,
              size: 28,
              sub: alive[s] ? '暗牌 $left 张' : '已出局'),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
        ]),
      );
    }

    final numbers = Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
      for (var n = 0; n <= (joker ? 12 : 11); n++)
        Builder(builder: (context) {
          final t = pick == null ? null : hands[pick!.$1][pick!.$2];
          final ruled = t != null && (t['w'] as List).contains(n);
          return SizedBox(
            width: 42,
            height: 38,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: pick == null || ruled
                  ? null
                  : () {
                      final (s, i) = pick!;
                      setState(() => pick = null);
                      g.act({'t': 'guess', 'target': s, 'index': i, 'value': n});
                    },
              child: Text(n == 12 ? '-' : '$n', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          );
        }),
    ]);

    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.layers, size: 18),
        Text(' 牌堆 $deck 张', style: const TextStyle(fontWeight: FontWeight.bold)),
        if (pending != null) ...[
          const SizedBox(width: 12),
          const Text('摸到：'),
          _Tile(color: pending['c'] as int, value: pending['v'] as int?, revealed: false, width: 28),
        ],
      ]),
      if (lastText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(lastText, textAlign: TextAlign.center)),
      if (myTurn && phase == 'guess') ...[
        const SizedBox(height: 6),
        numbers,
        if (correct > 0) ...[
          const SizedBox(height: 6),
          FilledButton.icon(onPressed: () => g.act({'t': 'stop'}), icon: const Icon(Icons.pan_tool), label: const Text('停止猜牌')),
        ],
      ],
    ]);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.2 && c.maxWidth > 700;
      final order = g.seatsFromMe();
      final others = order.where((s) => s != me).toList();
      final tw = (min(c.maxWidth * (wide ? 0.62 : 1), 900) / 15).clamp(26.0, 46.0);
      final rows = Column(mainAxisSize: MainAxisSize.min, children: [
        for (final s in others) row(s, tw),
        if (me >= 0) ...[
          const Divider(height: 12),
          row(me, tw),
        ],
      ]);
      final body = wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(8), child: rows)),
              SizedBox(
                width: min(340, c.maxWidth * 0.36),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [StatusBar(status, highlight: myTurn), const SizedBox(height: 8), controls]),
                ),
              ),
            ])
          : Column(children: [
              const SizedBox(height: 4),
              StatusBar(status, highlight: myTurn),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(6), child: rows)),
              Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: controls),
            ]);
      return Stack(children: [
        Positioned.fill(child: body),
        if (winner >= 0)
          Positioned(
            left: 0,
            right: 0,
            top: c.maxHeight * 0.3,
            child: Center(child: DismissibleResult(winner == me ? '你守住了最后的密码！' : '${g.name(winner)} 获胜！')),
          ),
      ]);
    });
  }
}

class _InsertSlot extends StatelessWidget {
  final double width, height;
  final VoidCallback onTap;
  const _InsertSlot({required this.width, required this.height, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: width,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber, width: 1.5),
            ),
            child: const Icon(Icons.add, size: 14),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  final int color; // 0 black 1 white
  final int? value;
  final bool revealed;
  final bool fresh;
  final bool selected;
  final bool highlight;
  final bool flash;
  final double width;
  final List<int> wrong;
  final VoidCallback? onTap;
  const _Tile({
    required this.color,
    required this.value,
    required this.revealed,
    required this.width,
    this.fresh = false,
    this.selected = false,
    this.highlight = false,
    this.flash = false,
    this.wrong = const [],
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final black = color == 0;
    final bg = black ? const Color(0xFF212121) : const Color(0xFFF5F5F5);
    final fg = black ? Colors.white : Colors.black87;
    final h = width * 1.45;
    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.25 : 0, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(bg, Colors.white, black ? 0.18 : 0)!, Color.lerp(bg, Colors.black, black ? 0 : 0.12)!],
        ),
        borderRadius: BorderRadius.circular(width * 0.16),
        border: Border.all(
          color: selected
              ? Colors.amber
              : highlight
                  ? Colors.amber.withValues(alpha: 0.7)
                  : (flash ? Colors.redAccent : Colors.black26),
          width: selected || highlight || flash ? 2.5 : 1,
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 2))],
      ),
      child: Stack(children: [
        Center(
          child: value == null
              ? Icon(Icons.help_outline, color: fg.withValues(alpha: 0.35), size: width * 0.5)
              : Text(value == 12 ? '-' : '$value',
                  style: TextStyle(color: fg, fontSize: width * 0.55, fontWeight: FontWeight.bold)),
        ),
        if (revealed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 2,
            child: Center(child: Container(width: width * 0.5, height: 3, color: Colors.redAccent)),
          ),
        if (!revealed && value != null)
          Positioned(right: 2, top: 1, child: Icon(Icons.lock, size: width * 0.26, color: fg.withValues(alpha: 0.5))),
        if (fresh)
          Positioned(left: 2, top: 1, child: Icon(Icons.fiber_new, size: width * 0.3, color: Colors.amber)),
        if (wrong.isNotEmpty && !revealed)
          Positioned(
            left: 1,
            right: 1,
            bottom: 1,
            child: Text(
              '≠${wrong.map((w) => w == 12 ? '-' : '$w').join(',')}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: width * 0.2, color: Colors.redAccent),
            ),
          ),
      ]),
    );
    if (revealed) tile = Opacity(opacity: 0.9, child: tile);
    if (onTap == null) return tile;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: tile));
  }
}
