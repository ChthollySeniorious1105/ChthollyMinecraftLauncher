import 'dart:math' as math;

import 'package:aurora_shared/games/arcade2/dobble.dart';
import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'a2_common.dart';

/// Deterministic layout of a Dobble card: for every slot (0 = centre,
/// 1..7 = ring) the symbol index, its size factor and rotation.
class _Layout {
  final List<int> syms;
  final List<Offset> pos; // in units of the card radius, centre = (0,0)
  final List<double> size; // symbol diameter in units of the card radius
  final List<double> rot;
  _Layout(this.syms, this.pos, this.size, this.rot);

  static final _cache = <int, _Layout>{};

  static _Layout of(int card) => _cache.putIfAbsent(card, () {
        final r = math.Random(card * 7919 + 17);
        final syms = List.of(Dobble.cards[card])..shuffle(r);
        final pos = <Offset>[];
        final size = <double>[];
        final rot = <double>[];
        // centre symbol
        final cs = 0.5 + r.nextDouble() * 0.22;
        pos.add(Offset((r.nextDouble() - 0.5) * 0.08, (r.nextDouble() - 0.5) * 0.08));
        size.add(cs);
        rot.add((r.nextDouble() - 0.5) * 2 * math.pi);
        final start = r.nextDouble() * 2 * math.pi;
        for (var i = 0; i < 7; i++) {
          final a = start + i * 2 * math.pi / 7 + (r.nextDouble() - 0.5) * 0.18;
          final s = 0.32 + r.nextDouble() * 0.2;
          final rad = 0.68 - (s - 0.32) * 0.35;
          pos.add(Offset(math.cos(a) * rad, math.sin(a) * rad));
          size.add(s);
          rot.add((r.nextDouble() - 0.5) * 2 * math.pi);
        }
        return _Layout(syms, pos, size, rot);
      });
}

/// A round Dobble card. [onTap] makes the symbols tappable.
class DobbleCard extends StatelessWidget {
  final int? card;
  final double size;
  final void Function(int sym)? onTap;
  final int? highlight;
  final bool dim;
  final Color? ring;
  const DobbleCard(this.card, {super.key, required this.size, this.onTap, this.highlight, this.dim = false, this.ring});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = card;
    final R = size / 2;
    final face = c == null || c < 0 || c >= Dobble.cardCount;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: face ? null : const Color(0xFFFFFDF7),
        gradient: face
            ? LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.4)!], begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        border: Border.all(color: ring ?? (face ? Colors.white70 : const Color(0xFFD7CCC8)), width: ring != null ? math.max(3, size * 0.02) : 2),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38, offset: Offset(0, 3))],
      ),
      child: face
          ? Center(
              child: Text('?',
                  style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: 0.6))))
          : Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < 8; i++) _symbol(_Layout.of(c), i, R),
              if (dim)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.35))),
                  ),
                ),
            ]),
    );
  }

  Widget _symbol(_Layout l, int i, double R) {
    final sym = l.syms[i];
    final d = l.size[i] * R;
    final o = l.pos[i] * R;
    final hot = highlight == sym;
    Widget w = Transform.rotate(
      angle: l.rot[i],
      child: SizedBox(
        width: d,
        height: d,
        child: Center(
          child: Text(
            Dobble.symbols[sym],
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: d * 0.74, height: 1.0, color: const Color(0xFF3E2723), fontFamilyFallback: kFontFallback),
          ),
        ),
      ),
    );
    if (hot) {
      w = Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFFFEB3B).withValues(alpha: 0.55),
          border: Border.all(color: const Color(0xFFFF6F00), width: math.max(2, R * 0.025)),
        ),
        child: w,
      );
    }
    if (onTap != null) {
      w = GestureDetector(behavior: HitTestBehavior.opaque, onTapDown: (_) => onTap!(sym), child: w);
    }
    return Positioned(left: R + o.dx - d / 2, top: R + o.dy - d / 2, width: d, height: d, child: w);
  }
}

class DobbleBoard extends StatelessWidget {
  final GameContext g;
  const DobbleBoard(this.g, {super.key});

  @override
  Widget build(BuildContext context) {
    final v = g.view;
    final phase = aStr(v['phase']);
    final mode = aStr(v['mode']);
    final tops = v['top'] is List ? (v['top'] as List) : const [];
    final n = aInts(v['n']);
    final wins = aInts(v['wins']);
    final lock = aInts(v['lock']);
    final out = v['out'] is List ? (v['out'] as List) : const [];
    final last = aMap(v['last']);
    final ver = aInt(v['ver'], 0);
    final centre = v['centre'] is num ? aInt(v['centre']) : null;
    final me = g.seat;
    final seated = me >= 0 && me < tops.length;
    final myTop = seated && tops[me] is num ? aInt(tops[me]) : null;
    final myLock = seated && me < lock.length ? lock[me] : 0;
    final myOut = seated && me < out.length && out[me] == true;
    final tickMs = aInt(v['tickMs'], 100);
    final reveal = phase == 'reveal' || phase == 'over';
    final winSym = reveal && last?['k'] == 'win' ? aInt(last!['sym']) : null;
    final winner = reveal && last?['k'] == 'win' ? aInt(last!['s']) : -1;
    final canTap = seated && phase == 'play' && myTop != null && myLock == 0 && !myOut && !g.over;

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'countdown') {
      status = '准备… ${(aInt(v['cd'], 0) * tickMs / 1000).ceil()}  找出你的牌和中央牌唯一相同的图案！';
    } else if (phase == 'reveal' && winner >= 0) {
      status = winner == me ? '你抢到了 ${Dobble.symbols[winSym!]}！' : '${g.name(winner)} 抢到了 ${Dobble.symbols[winSym!]}';
    } else if (!seated) {
      status = '观战中';
    } else if (myOut) {
      status = '你已认输';
    } else if (myTop == null) {
      status = '你的牌已出完';
    } else if (myLock > 0) {
      status = '点错了！冷却 ${(myLock * tickMs / 1000).toStringAsFixed(1)} 秒';
    } else {
      status = '快！点你牌上和中央牌相同的图案';
    }
    final pileText = mode == 'well' ? '深井' : '塔楼 · 剩余 ${aInt(v['centreN'], 0)} 张';

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.1;
      final others = [for (final s in g.seatsFromMe()) if (s != me) s];
      final compactOpp = !wide && others.length > 3;
      final stripH = wide ? 0.0 : (compactOpp ? 76.0 : 50.0);
      final sideW = wide ? math.min(230.0, box.maxWidth * 0.25) : 0.0;
      final availH = box.maxHeight - 40 - stripH;
      final availW = box.maxWidth - sideW;
      double cardD;
      if (wide) {
        cardD = math.min((availW - 48) / (seated ? 2 : 1), availH - 44);
      } else {
        cardD = math.min(availW - 24, (availH - 60) / (seated ? 2 : 1));
      }
      cardD = math.max(60.0, cardD);

      Widget label(String t, {Color? color}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SizedBox(
              height: 18,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(t,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color ?? Colors.white,
                        shadows: const [Shadow(blurRadius: 3, color: Colors.black54)])),
              ),
            ),
          );

      final centreCard = Column(mainAxisSize: MainAxisSize.min, children: [
        label('中央 · $pileText'),
        DobbleCard(
          centre,
          key: ValueKey('c$ver'),
          size: cardD,
          highlight: winSym,
          ring: winner >= 0 ? const Color(0xFFFF6F00) : null,
        ),
      ]);
      final myCard = !seated
          ? const SizedBox.shrink()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              label('你的牌 · ${me < n.length ? n[me] : 0} 张 · 抢到 ${me < wins.length ? wins[me] : 0} 次',
                  color: myLock > 0 ? Colors.redAccent : null),
              Stack(alignment: Alignment.center, children: [
                DobbleCard(
                  myTop,
                  size: cardD,
                  highlight: winner == me ? winSym : null,
                  dim: myLock > 0 || myOut,
                  ring: myLock > 0 ? Colors.redAccent : (canTap ? Theme.of(context).colorScheme.primary : null),
                  onTap: canTap ? (sym) => g.act({'type': 'tap', 'sym': sym, 'ver': ver}) : null,
                ),
                if (myLock > 0)
                  IgnorePointer(
                    child: Text('❌',
                        style: TextStyle(fontSize: cardD * 0.3, fontFamilyFallback: kFontFallback, color: Colors.white.withValues(alpha: 0.85))),
                  ),
              ]),
            ]);

      Widget oppTile(int s) {
        final top = s < tops.length && tops[s] is num ? aInt(tops[s]) : null;
        final locked = s < lock.length && lock[s] > 0;
        final isOut = s < out.length && out[s] == true;
        final mini = wide ? 46.0 : 40.0;
        if (compactOpp) {
          return Opacity(
            opacity: isOut ? 0.45 : 1,
            child: Container(
              width: 50,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: s == winner ? const Color(0xFFFFE082).withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: locked ? Colors.redAccent : Colors.transparent, width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DobbleCard(top, size: 36, highlight: s == winner ? winSym : null, dim: locked),
                Text(g.name(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white)),
                Text('${s < n.length ? n[s] : 0} 张', style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ]),
            ),
          );
        }
        return Opacity(
          opacity: isOut ? 0.45 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: s == winner ? const Color(0xFFFFE082).withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: locked ? Colors.redAccent : Colors.transparent, width: 1.5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              DobbleCard(top, size: mini, highlight: s == winner ? winSym : null, dim: locked),
              const SizedBox(width: 4),
              g.tag(s, size: 22, active: s == winner, sub: '${s < n.length ? n[s] : 0} 张${locked ? ' · 冷却' : ''}${isOut ? ' · 认输' : ''}'),
            ]),
          ),
        );
      }

      final opps = Wrap(
        direction: wide ? Axis.vertical : Axis.horizontal,
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [for (final s in others) oppTile(s)],
      );

      Widget body;
      if (wide) {
        body = Row(children: [
          SizedBox(
            width: sideW,
            child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(6), child: FittedBox(fit: BoxFit.scaleDown, child: opps))),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  centreCard,
                  if (seated) const SizedBox(width: 32),
                  myCard,
                ]),
              ),
            ),
          ),
        ]);
      } else {
        body = Column(children: [
          SizedBox(
            height: stripH,
            child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.all(4), child: opps))),
          ),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  centreCard,
                  if (seated) const SizedBox(height: 8),
                  myCard,
                ]),
              ),
            ),
          ),
        ]);
      }

      return Column(children: [
        SizedBox(height: 40, child: aStatus(status, highlight: canTap)),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: body),
            if (phase == 'countdown')
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Text('${(aInt(v['cd'], 0) * tickMs / 1000).ceil()}',
                        style: const TextStyle(
                            fontSize: 80, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 12, color: Colors.black)])),
                  ),
                ),
              ),
            if (phase == 'over')
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  child: aRanking(g, aMaps(v['final']), (r) => '${mode == 'well' ? '剩 ' : ''}${r['cards']} 张 · 抢到 ${r['wins']} 次'),
                ),
              ),
          ]),
        ),
      ]);
    });
  }
}
