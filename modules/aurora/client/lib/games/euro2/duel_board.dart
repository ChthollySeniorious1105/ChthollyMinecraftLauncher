import 'dart:math';

import 'package:aurora_shared/games/euro2/duel_data.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'x_common.dart';

const _kindColor = {
  'brown': Color(0xFF8B5A2B),
  'grey': Color(0xFF8E8E93),
  'blue': Color(0xFF2F6BD8),
  'green': Color(0xFF2E9E4A),
  'yellow': Color(0xFFE9A826),
  'red': Color(0xFFD13A30),
  'guild': Color(0xFF7E57C2),
};
const _resColor = [Color(0xFF6D8B3A), Color(0xFFC0602F), Color(0xFF8A8A8A), Color(0xFF3FB6D0), Color(0xFFD9C38F)];
const _ageBack = [Color(0xFF9C6B3C), Color(0xFF4A6FA5), Color(0xFF7B4B94)];

Widget _resChip(int r, {double size = 14, int count = 1, bool slash = false}) => Container(
      margin: const EdgeInsets.all(0.5),
      padding: EdgeInsets.symmetric(horizontal: size * 0.12),
      height: size,
      constraints: BoxConstraints(minWidth: size),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _resColor[r], borderRadius: BorderRadius.circular(size * 0.22), border: Border.all(color: Colors.black26, width: 0.6)),
      child: Text('${count > 1 ? '$count' : ''}${duelResShort[r]}${slash ? '/' : ''}',
          style: TextStyle(fontSize: size * 0.62, color: r == 4 ? Colors.black87 : Colors.white, fontWeight: FontWeight.bold, height: 1.1)),
    );

Widget _coin(int n, {double size = 14}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [Color(0xFFFFE27A), Color(0xFFD9A21B)]),
        boxShadow: [BoxShadow(blurRadius: 1, color: Colors.black38)],
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text('$n', style: TextStyle(fontSize: size * 0.62, fontWeight: FontWeight.w900, color: const Color(0xFF5A3D00)))),
    );

Widget _sci(int s, {double size = 16}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFFF2EAD3), shape: BoxShape.circle, border: Border.all(color: const Color(0xFF2E9E4A), width: 1.2)),
      child: Text(duelSciShort[s], style: TextStyle(fontSize: size * 0.58, color: const Color(0xFF1B5E20), fontWeight: FontWeight.bold, height: 1.1)),
    );

Widget _shield(int n, {double size = 14}) => Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < n; i++) Icon(Icons.shield, size: size, color: const Color(0xFFD13A30)),
    ]);

Widget _vp(int n, {double size = 14}) => Container(
      padding: EdgeInsets.symmetric(horizontal: size * 0.2),
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: const Color(0xFF2F6BD8), borderRadius: BorderRadius.circular(size * 0.25)),
      child: Text('$n分', style: TextStyle(fontSize: size * 0.62, color: Colors.white, fontWeight: FontWeight.bold, height: 1.1)),
    );

List<Widget> _costWidgets(List<int> cost, int coins, double s) => [
      if (coins > 0) _coin(coins, size: s),
      for (var r = 0; r < 5; r++)
        if (cost[r] > 0) _resChip(r, size: s, count: cost[r]),
    ];

List<Widget> _effectWidgets(DuelCard d, double s) => [
      if (d.prod.any((x) => x > 0))
        for (var r = 0; r < 5; r++)
          if (d.prod[r] > 0) _resChip(r, size: s * 1.1, count: d.prod[r]),
      if (d.choice.isNotEmpty) for (var i = 0; i < d.choice.length; i++) _resChip(d.choice[i], size: s, slash: i < d.choice.length - 1),
      if (d.shields > 0) _shield(d.shields, size: s * 1.05),
      if (d.sci >= 0) _sci(d.sci, size: s * 1.2),
      if (d.vp > 0) _vp(d.vp, size: s),
      if (d.fx.isNotEmpty && d.choice.isEmpty) SizedBox(width: s * 4.4, child: Text(d.text, maxLines: 3, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: s * 0.55, height: 1.05, color: Colors.black87))),
    ];

/// A face-up age / guild card.
class DuelCardView extends StatelessWidget {
  final int card;
  final double w;
  final bool selected, playable, highlight;
  final int? price;
  final bool chain;
  final VoidCallback? onTap;
  const DuelCardView(this.card, {super.key, this.w = 60, this.selected = false, this.playable = false, this.highlight = false, this.price, this.chain = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = duelCards[card];
    final col = _kindColor[d.kind]!;
    final h = w * 1.3;
    final s = w * 0.2;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: w,
        height: h,
        transform: Matrix4.translationValues(0, selected ? -w * 0.1 : 0, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F1E3),
          borderRadius: BorderRadius.circular(w * 0.1),
          border: Border.all(color: selected ? Colors.white : (highlight ? const Color(0xFFFFE066) : (playable ? col : Colors.black45)), width: selected || highlight ? 2.5 : 1.2),
          boxShadow: [BoxShadow(blurRadius: selected ? 10 : 3, color: selected ? const Color(0xCCFFFFFF) : Colors.black45, offset: const Offset(1, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.09),
          child: Column(children: [
            Container(
              height: h * 0.26,
              width: double.infinity,
              color: col,
              padding: EdgeInsets.symmetric(horizontal: w * 0.04),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(d.name, style: TextStyle(fontSize: w * 0.19, color: Colors.white, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 2, color: Colors.black45)])),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(w * 0.04),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: w * 0.95),
                      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 1, runSpacing: 1, children: _effectWidgets(d, s)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: h * 0.2,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    ..._costWidgets(d.cost, d.coins, s * 0.9),
                    if (d.cost.every((x) => x == 0) && d.coins == 0) Text('免费', style: TextStyle(fontSize: s * 0.6, color: Colors.black54)),
                    if (d.chain.isNotEmpty) Text(' ⟵${d.chain}', style: TextStyle(fontSize: s * 0.55, color: Colors.black54)),
                    if (d.link.isNotEmpty) Text(' ⟶${d.link}', style: TextStyle(fontSize: s * 0.55, color: Colors.black87, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
            if (price != null)
              Container(
                width: double.infinity,
                color: chain ? const Color(0xFF2E9E4A) : Colors.black.withValues(alpha: 0.7),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(chain ? '连锁免费' : (price == 0 ? '免费' : '需 $price 金'), style: TextStyle(fontSize: w * 0.15, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final int age;
  final bool guild;
  final double w;
  const _CardBack(this.age, this.guild, this.w);
  @override
  Widget build(BuildContext context) {
    final col = guild ? const Color(0xFF5E3A7A) : _ageBack[(age - 1).clamp(0, 2)];
    return Container(
      width: w,
      height: w * 1.3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(col, Colors.white, 0.15)!, Color.lerp(col, Colors.black, 0.3)!]),
        border: Border.all(color: const Color(0xFFE6C675), width: 1.2),
        boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black45, offset: Offset(1, 2))],
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(guild ? '行会' : ['Ⅰ', 'Ⅱ', 'Ⅲ'][(age - 1).clamp(0, 2)],
            style: TextStyle(fontSize: w * 0.34, color: const Color(0xFFE6C675), fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class DuelWonderView extends StatelessWidget {
  final int id;
  final double w;
  final bool built, out, playable, selected;
  final int? price;
  final VoidCallback? onTap;
  const DuelWonderView(this.id, {super.key, this.w = 110, this.built = false, this.out = false, this.playable = false, this.selected = false, this.price, this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = duelWonders[id];
    final h = w * 0.62;
    final s = w * 0.12;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: out ? 0.35 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.07),
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: built ? const [Color(0xFFF6D77A), Color(0xFFC9973A)] : const [Color(0xFFE8E0CC), Color(0xFFB9AC8C)]),
            border: Border.all(color: selected ? Colors.white : (playable ? const Color(0xFFFFE066) : Colors.black38), width: playable || selected ? 2.4 : 1),
            boxShadow: [BoxShadow(blurRadius: playable ? 8 : 3, color: playable ? const Color(0x99FFE066) : Colors.black38, offset: const Offset(1, 2))],
          ),
          padding: EdgeInsets.all(w * 0.03),
          child: Column(children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (built) Icon(Icons.check_circle, size: s * 1.2, color: const Color(0xFF2E7D32)),
                Text(d.name, style: TextStyle(fontSize: s * 1.05, fontWeight: FontWeight.bold, color: Colors.black87)),
              ]),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (d.vp > 0) _vp(d.vp, size: s * 1.2),
                    if (d.shields > 0) _shield(d.shields, size: s * 1.2),
                    if (d.replay) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Icon(Icons.replay, size: s * 1.3, color: const Color(0xFF6A1B9A))),
                  ]),
                ),
              ),
            ),
            SizedBox(
              height: h * 0.2,
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(d.text, style: TextStyle(fontSize: s * 0.8, color: Colors.black87))),
            ),
            SizedBox(
              height: h * 0.2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ..._costWidgets(d.cost, 0, s),
                  if (price != null && !built) Text('  需 $price 金', style: TextStyle(fontSize: s * 0.85, fontWeight: FontWeight.bold, color: Colors.black87)),
                  if (out) Text('  已移出', style: TextStyle(fontSize: s * 0.85, color: Colors.black87)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TokenView extends StatelessWidget {
  final int t;
  final double size;
  final bool playable;
  final VoidCallback? onTap;
  const _TokenView(this.t, {this.size = 40, this.playable = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final tk = duelTokens[t];
    return Tooltip(
      message: '${tk.name}：${tk.text}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(colors: [Color(0xFF9AD68F), Color(0xFF2E7D32)]),
            border: Border.all(color: playable ? const Color(0xFFFFE066) : Colors.white70, width: playable ? 2.5 : 1.2),
            boxShadow: [BoxShadow(blurRadius: playable ? 8 : 2, color: playable ? const Color(0xAAFFE066) : Colors.black45)],
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.08),
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(tk.name, style: TextStyle(fontSize: size * 0.3, color: Colors.white, fontWeight: FontWeight.bold))),
          ),
        ),
      ),
    );
  }
}

class _MilitaryPainter extends CustomPainter {
  final int pos; // from my perspective: + toward opponent (right)
  final List<bool> oppLoot, myLoot; // [2 coins, 5 coins]
  final Color accent;
  _MilitaryPainter(this.pos, this.myLoot, this.oppLoot, this.accent);
  @override
  void paint(Canvas canvas, Size s) {
    final cw = s.width / 19;
    final h = s.height;
    for (var i = -9; i <= 9; i++) {
      final r = Rect.fromLTWH((i + 9) * cw, h * 0.2, cw, h * 0.6).deflate(0.6);
      final a = i.abs();
      Color c;
      if (a == 9) {
        c = const Color(0xFF5D4037);
      } else if (a >= 6) {
        c = const Color(0xFFE0B08A);
      } else if (a >= 3) {
        c = const Color(0xFFEBCBA9);
      } else if (a >= 1) {
        c = const Color(0xFFF3E1C8);
      } else {
        c = const Color(0xFFFFF5E1);
      }
      canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(cw * 0.15)), Paint()..color = c);
      if (a == 9) paintLabel(canvas, '都', r.center, paintText(cw * 0.5, Colors.white));
    }
    // vp labels
    for (final (from, to, vp) in const [(1, 2, 2), (3, 5, 5), (6, 8, 10)]) {
      for (final sg in const [-1, 1]) {
        final x = ((from + to) / 2 * sg + 9 + 0.5) * cw;
        paintLabel(canvas, '$vp', Offset(x, h * 0.1), paintText(max(7, h * 0.16), accent));
      }
    }
    // loot tokens
    void lootAt(int i, int amt, bool present) {
      if (!present) return;
      final c = Offset((i + 9 + 0.5) * cw, h * 0.9);
      canvas.drawCircle(c, h * 0.12, Paint()..color = const Color(0xFFD9A21B));
      paintLabel(canvas, '$amt', c, paintText(h * 0.14, Colors.black87));
    }

    lootAt(4, 2, oppLoot[0]);
    lootAt(7, 5, oppLoot[1]);
    lootAt(-4, 2, myLoot[0]);
    lootAt(-7, 5, myLoot[1]);
    // conflict pawn
    final pc = Offset((pos + 9 + 0.5) * cw, h * 0.5);
    final pawn = Path()
      ..moveTo(pc.dx, pc.dy - h * 0.3)
      ..lineTo(pc.dx + cw * 0.35, pc.dy + h * 0.25)
      ..lineTo(pc.dx - cw * 0.35, pc.dy + h * 0.25)
      ..close();
    canvas.drawShadow(pawn, Colors.black, 2, false);
    canvas.drawPath(pawn, Paint()..color = const Color(0xFFD13A30));
    canvas.drawPath(
        pawn,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DuelBoard extends StatefulWidget {
  final GameContext g;
  const DuelBoard(this.g, {super.key});
  @override
  State<DuelBoard> createState() => _DuelBoardState();
}

class _DuelBoardState extends State<DuelBoard> {
  int? sel;
  int? detail; // card id shown in the detail line
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final phase = '${v['phase']}';
    final over = phase == 'over';
    final turn = xInt(v['turn']);
    final me = g.seat;
    final meS = me >= 0 ? me : 0;
    final oppS = 1 - meS;
    final myTurn = !over && me >= 0 && turn == me && !g.replay;
    final age = xInt(v['age']);
    final slots = xList<dynamic>(v['slots']).map(xMap).toList();
    final ps = xList<dynamic>(v['players']).map(xMap).toList();
    final last = xMap(v['last']);
    final k = '$phase/$turn/$age/${slots.where((s) => s['taken'] == true).length}';
    if (k != key) {
      key = k;
      sel = null;
    }
    final myP = ps[meS];
    final myCoins = xInt(myP['coins']);
    final selSlot = sel != null && sel! < slots.length ? slots[sel!] : null;

    String status;
    switch (phase) {
      case 'draft':
        status = myTurn ? '挑选奇迹：选择一座奇迹' : '等待 ${g.name(turn)} 挑选奇迹';
      case 'start':
        status = myTurn ? '你的军事较弱：决定第 ${['一', '二', '三'][(age - 1).clamp(0, 2)]} 时代谁先手' : '等待 ${g.name(turn)} 决定先手';
      case 'token':
        status = myTurn ? '凑齐一对科学符号：选择一个进步标记' : '等待 ${g.name(turn)} 选择进步标记';
      case 'library':
        status = myTurn ? '亚历山大图书馆：从 3 个标记中选 1 个' : '等待 ${g.name(turn)} 选择进步标记';
      case 'destroy':
        status = myTurn ? '摧毁对手一张${v['destroyKind'] == 'grey' ? '灰' : '棕'}卡' : '等待 ${g.name(turn)} 摧毁卡牌';
      case 'revive':
        status = myTurn ? '摩索拉斯陵墓：从弃牌堆免费建造一张卡' : '等待 ${g.name(turn)} 从弃牌堆选卡';
      case 'over':
        status = '游戏结束';
      default:
        status = myTurn ? (sel == null ? '第 $age 时代 · 轮到你：点一张可拿取的卡' : '选择：建造 / 弃掉换钱 / 建造奇迹') : '第 $age 时代 · 等待 ${g.name(turn)}';
    }

    // ------------------------------------------------------------ structure
    Widget structure(double cw) {
      if (age == 0 || slots.isEmpty) return const SizedBox.shrink();
      final rows = xInt(v['rows']);
      final u = cw * 0.54;
      final ch = cw * 1.3;
      final step = ch * 0.5;
      final xs = [for (final sl in slots) xInt(sl['x'])];
      final minX = xs.reduce(min), maxX = xs.reduce(max);
      final width = 12 * u;
      final height = (rows - 1) * step + ch + cw * 0.15;
      return SizedBox(
        width: width,
        height: height,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var i = 0; i < slots.length; i++)
            if (slots[i]['taken'] != true)
              Positioned(
                left: (xInt(slots[i]['x']) - minX) * u + (width - (maxX - minX) * u - cw) / 2,
                top: xInt(slots[i]['row']) * step + cw * 0.1,
                child: Builder(builder: (_) {
                  final s = slots[i];
                  final card = s['card'] as int?;
                  if (card == null) return _CardBack(age, s['guild'] == true, cw);
                  final acc = s['acc'] == true;
                  return DuelCardView(card,
                      w: cw,
                      selected: sel == i,
                      playable: acc && myTurn && phase == 'play',
                      price: acc ? s['cost'] as int? : null,
                      chain: s['chain'] == true,
                      onTap: () => setState(() {
                            detail = card;
                            if (acc && myTurn && phase == 'play') sel = sel == i ? null : i;
                          }));
                }),
              ),
        ]),
      );
    }

    // ------------------------------------------------------------ city panel
    Widget city(int s, {required bool mine, double scale = 1}) {
      final p = ps[s];
      final built = xInts(p['built']);
      final prod = xInts(p['prod']);
      final choice = xList<dynamic>(p['choice']).map(xInts).toList();
      final syms = xInts(p['symbols']);
      final wonders = xList<dynamic>(p['wonders']).map(xMap).toList();
      final tokens = xInts(p['tokens']);
      final counts = <String, int>{};
      for (final c in built) {
        counts[duelCards[c].kind] = (counts[duelCards[c].kind] ?? 0) + 1;
      }
      final active = !over && turn == s;
      final canWonder = mine && myTurn && phase == 'play' && selSlot != null;
      final sz = 14.0 * scale;
      final wonderW = 104.0 * scale;
      return XPanel(
        highlight: active,
        padding: const EdgeInsets.all(5),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
            g.tag(s, active: active, size: 24 * scale, sub: '约 ${xInt(p['vp'])} 分'),
            Row(mainAxisSize: MainAxisSize.min, children: [_coin(xInt(p['coins']), size: sz * 1.5)]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var r = 0; r < 5; r++)
                if (prod[r] > 0) _resChip(r, size: sz, count: prod[r]),
              for (final ch in choice) ...[
                for (var i = 0; i < ch.length; i++) _resChip(ch[i], size: sz, slash: i < ch.length - 1),
                const SizedBox(width: 2),
              ],
            ]),
            if (syms.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [for (final x in syms) _sci(x, size: sz * 1.1)]),
          ]),
          const SizedBox(height: 3),
          Wrap(spacing: 3, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final kd in duelKinds)
              if ((counts[kd] ?? 0) > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _kindColor[kd], borderRadius: BorderRadius.circular(4)),
                  child: Text('${duelKindNames[kd]} ${counts[kd]}', style: TextStyle(fontSize: 10 * scale, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            for (final t in tokens) _TokenView(t, size: 22 * scale),
            if (mine)
              Text('交易价 ${[for (var r = 0; r < 5; r++) '${duelResShort[r]}${xInts(p['prices']).elementAtOrNull(r) ?? 2}'].join(' ')}',
                  style: TextStyle(fontSize: 10 * scale, color: cs.onSurface.withValues(alpha: 0.7))),
          ]),
          if (built.isNotEmpty) ...[
            const SizedBox(height: 3),
            SizedBox(
              height: 18 * scale,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in built)
                  GestureDetector(
                    onTap: () => setState(() => detail = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: _kindColor[duelCards[c].kind]!.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: xInt(last['card'], -1) == c && last['type'] == 'build' ? const Color(0xFFFFE066) : Colors.transparent, width: 1.5)),
                      child: Text(duelCards[c].name, style: TextStyle(fontSize: 10 * scale, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
          ],
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (var w = 0; w < wonders.length; w++)
              Builder(builder: (_) {
                final wd = wonders[w];
                final price = wd['cost'] as int?;
                final ok = canWonder && wd['built'] != true && wd['out'] != true && price != null && price <= myCoins;
                return DuelWonderView(xInt(wd['id']),
                    w: wonderW,
                    built: wd['built'] == true,
                    out: wd['out'] == true,
                    playable: ok,
                    price: mine ? price : null,
                    onTap: ok ? () => g.act({'type': 'wonder', 'slot': sel, 'w': w}) : null);
              }),
          ]),
        ]),
      );
    }

    // ------------------------------------------------------------ top strip
    Widget militaryBar(double w) {
      final mil = xInt(v['military']);
      final pos = meS == 0 ? mil : -mil;
      final loot = xList<dynamic>(v['loot']).map((l) => xList<bool>(l)).toList();
      return XPanel(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: w,
            child: Row(children: [
              Text(g.name(meS), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const Spacer(),
              const Text('军事', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD13A30))),
              const Spacer(),
              Text(g.name(oppS), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: cs.onSurface)),
            ]),
          ),
          CustomPaint(size: Size(w, min(40, w / 19 * 1.8)), painter: _MilitaryPainter(pos, loot.elementAtOrNull(meS) ?? const [true, true], loot.elementAtOrNull(oppS) ?? const [true, true], cs.onSurface.withValues(alpha: 0.8))),
        ]),
      );
    }

    Widget tokenRow() {
      final bt = xInts(v['boardTokens']);
      return Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('进步标记', style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.75))),
        for (final t in bt)
          _TokenView(t, size: 34, playable: myTurn && phase == 'token', onTap: myTurn && phase == 'token' ? () => g.act({'type': 'token', 't': t}) : null),
      ]);
    }

    // ------------------------------------------------------------ action area
    Widget actionArea() {
      final children = <Widget>[];
      if (phase == 'draft') {
        final offer = xInts(v['offer']);
        children.add(Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < offer.length; i++)
            DuelWonderView(offer[i], w: 130, playable: myTurn, onTap: myTurn ? () => g.act({'type': 'draft', 'w': i}) : null),
        ]));
      } else if (phase == 'start' && myTurn) {
        children.add(Wrap(spacing: 8, children: [
          XButton('我先手', icon: Icons.play_arrow, onTap: () => g.act({'type': 'start', 'seat': me})),
          XButton('对手先手', primary: false, onTap: () => g.act({'type': 'start', 'seat': 1 - me})),
        ]));
      } else if (phase == 'library' && myTurn) {
        children.add(Wrap(spacing: 6, children: [
          for (final t in xInts(v['library'])) _TokenView(t, size: 48, playable: true, onTap: () => g.act({'type': 'token', 't': t})),
        ]));
      } else if (phase == 'destroy' && myTurn) {
        final kind = '${v['destroyKind']}';
        children.add(Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (final c in xInts(ps[oppS]['built']))
            if (duelCards[c].kind == kind) DuelCardView(c, w: 58, playable: true, onTap: () => g.act({'type': 'destroy', 'card': c})),
        ]));
      } else if (phase == 'revive' && myTurn) {
        children.add(SizedBox(
          height: 80,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in xInts(v['discard']))
              Padding(padding: const EdgeInsets.all(2), child: DuelCardView(c, w: 56, playable: true, onTap: () => g.act({'type': 'revive', 'card': c}))),
          ]),
        ));
      } else if (phase == 'play' && myTurn && selSlot != null) {
        final price = selSlot['cost'] as int?;
        final sell = xInt(myP['sell'], 2);
        children.add(Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
          XButton(selSlot['chain'] == true ? '建造（连锁免费）' : '建造 (${price ?? '?'} 金)',
              icon: Icons.construction, onTap: price != null && price <= myCoins ? () => g.act({'type': 'build', 'slot': sel}) : null),
          XButton('弃掉 +$sell 金', icon: Icons.sell, primary: false, onTap: () => g.act({'type': 'discard', 'slot': sel})),
          Text('或点下方亮起的奇迹建造', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.75))),
        ]));
      }
      if (detail != null) {
        final d = duelCards[detail!];
        final eff = <String>[
          if (d.prod.any((x) => x > 0)) '产出 ${[for (var r = 0; r < 5; r++) if (d.prod[r] > 0) '${duelResNames[r]}×${d.prod[r]}'].join(' ')}',
          if (d.shields > 0) '${d.shields} 盾',
          if (d.sci >= 0) '科学符号 ${duelSciNames[d.sci]}',
          if (d.vp > 0) '${d.vp} 分',
          if (d.text.isNotEmpty) d.text,
          if (d.chain.isNotEmpty) '持有「${d.chain}」标志可免费建造',
          if (d.link.isNotEmpty) '提供连锁标志「${d.link}」',
        ];
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('「${d.name}」${duelKindNames[d.kind]}：${eff.join('；')}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.85))),
        ));
      }
      if (children.isEmpty) return const SizedBox.shrink();
      return XPanel(highlight: myTurn, child: Column(mainAxisSize: MainAxisSize.min, children: children));
    }

    // ------------------------------------------------------------ result
    Widget? banner;
    if (over) {
      final res = xMap(v['result']);
      final w = xInt(v['winner'], -1);
      final type = '${res['type']}';
      final how = {'military': '军事胜利', 'science': '科技胜利', 'civil': '文明胜利', 'resign': '对手认输'}[type] ?? '';
      final rows = xList<dynamic>(res['rows']).map(xMap).toList();
      final title = w == -2 ? '平局！' : '${g.name(w)} $how！';
      banner = ResultBanner(title,
          child: rows.length < 2
              ? null
              : scoreTable(context, ['', g.name(0), g.name(1)], [
                  for (final (k2, lbl) in const [
                    ('blue', '蓝卡'), ('green', '绿卡'), ('yellow', '黄卡'), ('guild', '行会'), ('wonder', '奇迹'), ('token', '进步'), ('military', '军事'), ('coins', '金币'), ('total', '总分'),
                  ])
                    [lbl, '${xInt(rows[0][k2])}', '${xInt(rows[1][k2])}'],
                ], bold: const [8]));
    }

    final log = XPanel(child: XLog(xList<String>(v['recent']), max: 4));

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.1;
      if (wide) {
        final sideW = min(380.0, c.maxWidth * 0.34);
        final midW = c.maxWidth - sideW - 20;
        final rows = max(5, xInt(v['rows']));
        final cwByH = (c.maxHeight - 110) / (1.3 + (rows - 1) * 0.65);
        final cw = min(min(96.0, midW / 6.6), cwByH);
        final scale = c.maxHeight < 500 ? 0.72 : 0.9;
        return Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  StatusBar(status, highlight: myTurn),
                  const SizedBox(height: 4),
                  militaryBar(min(midW - 30, 480)),
                  const SizedBox(height: 4),
                  if (phase == 'draft') actionArea() else FittedBox(fit: BoxFit.scaleDown, child: structure(cw)),
                  const SizedBox(height: 4),
                  tokenRow(),
                ]),
              ),
            ),
            SizedBox(
              width: sideW,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  city(oppS, mine: false, scale: scale * 0.9),
                  const SizedBox(height: 4),
                  if (phase != 'draft') actionArea(),
                  const SizedBox(height: 4),
                  city(meS, mine: me >= 0, scale: scale),
                  const SizedBox(height: 4),
                  log,
                ]),
              ),
            ),
          ]),
          if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
        ]);
      }
      final cw = min(64.0, (c.maxWidth - 16) / 6.6);
      return Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(4),
          child: Column(children: [
            StatusBar(status, highlight: myTurn),
            const SizedBox(height: 4),
            city(oppS, mine: false, scale: 0.8),
            const SizedBox(height: 4),
            militaryBar(c.maxWidth - 30),
            const SizedBox(height: 4),
            tokenRow(),
            const SizedBox(height: 4),
            if (phase != 'draft') FittedBox(fit: BoxFit.scaleDown, child: structure(cw)),
            const SizedBox(height: 4),
            actionArea(),
            const SizedBox(height: 4),
            city(meS, mine: me >= 0, scale: 0.9),
            const SizedBox(height: 4),
            log,
          ]),
        ),
        if (banner != null) Align(alignment: Alignment.topCenter, child: banner),
      ]);
    });
  }
}
