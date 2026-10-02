import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import '../../widgets/pieces.dart';
import 'tt_common.dart';

const _cardLabel = {'Q': 'Q', 'K': 'K', 'A': 'A', 'J': '王', 'D': '恶魔', 'C': '混沌'};

class BarCard extends StatelessWidget {
  final String code; // '' = back
  final double width;
  final bool selected;
  final VoidCallback? onTap;
  const BarCard(this.code, {super.key, this.width = 56, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.45;
    Widget body;
    if (code.isEmpty) {
      body = Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF4E342E), Color(0xFF8D6E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: const Color(0xFFFFD54F), width: width * 0.04),
        ),
        child: Center(child: Icon(Icons.local_bar, color: const Color(0xFFFFD54F), size: width * 0.45)),
      );
    } else {
      final special = code == 'J' || code == 'D' || code == 'C';
      final color = switch (code) {
        'D' => const Color(0xFFB71C1C),
        'C' => const Color(0xFF6A1B9A),
        'J' => const Color(0xFF2E7D32),
        _ => const Color(0xFF212121),
      };
      final icon = switch (code) {
        'Q' => Icons.face_3,
        'K' => Icons.face_6,
        'A' => Icons.star,
        'J' => Icons.auto_awesome,
        'D' => Icons.whatshot,
        _ => Icons.cyclone,
      };
      body = Container(
        decoration: BoxDecoration(
          color: special ? Color.lerp(color, Colors.white, 0.85) : const Color(0xFFFFFBF2),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: color, width: width * 0.04),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_cardLabel[code] ?? code,
              style: TextStyle(fontSize: width * (code.length > 1 || special ? 0.26 : 0.42), fontWeight: FontWeight.w900, color: color)),
          Icon(icon, color: color, size: width * 0.38),
        ]),
      );
    }
    final w = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.25 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        boxShadow: [BoxShadow(color: selected ? Colors.amber : Colors.black45, blurRadius: selected ? 10 : 3, offset: const Offset(1, 2))],
      ),
      child: body,
    );
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

/// Revolver cylinder: 6 chambers, [used] already pulled.
class Revolver extends StatelessWidget {
  final int used;
  final bool dead;
  final double size;
  const Revolver(this.used, {super.key, this.dead = false, this.size = 34});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _RevolverPainter(used, dead));
}

class _RevolverPainter extends CustomPainter {
  final int used;
  final bool dead;
  _RevolverPainter(this.used, this.dead);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF546E7A));
    canvas.drawCircle(c, r, Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    for (var i = 0; i < 6; i++) {
      final a = -pi / 2 + i * pi / 3;
      final p = c + Offset(cos(a), sin(a)) * r * 0.58;
      final color = dead && i == used - 1
          ? Colors.redAccent
          : (i < used ? Colors.black87 : const Color(0xFFCFD8DC));
      canvas.drawCircle(p, r * 0.22, Paint()..color = color);
    }
    canvas.drawCircle(c, r * 0.14, Paint()..color = Colors.black54);
  }

  @override
  bool shouldRepaint(_RevolverPainter o) => o.used != used || o.dead != dead;
}

class LiarsBarBoard extends StatefulWidget {
  final GameContext g;
  const LiarsBarBoard(this.g, {super.key});
  @override
  State<LiarsBarBoard> createState() => _LiarsBarBoardState();
}

class _LiarsBarBoardState extends State<LiarsBarBoard> {
  Set<int> sel = {};
  int qty = 1;
  int face = 2;
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = ttInt(v['players']);
    final mode = v['mode'] as String? ?? 'deck';
    final isDice = mode == 'dice' || mode == 'classic';
    final phase = v['phase'] as String? ?? 'play';
    final turn = ttInt(v['turn']);
    final alive = ttList<bool>(v['alive']);
    final shots = ttList<int>(v['shots']);
    final myTurn = phase == 'play' && turn == g.seat;
    final reveal = v['reveal'] == null ? null : ttMap(v['reveal']);
    final bidQty = ttInt(v['bidQty']);
    final bidFace = ttInt(v['bidFace']);
    final wild = v['wild'] == true;
    final totalDice = ttInt(v['totalDice'], 1);
    final k = '$turn/$phase/${ttInt(v['round'])}/${v['pile']}/$bidQty/$bidFace';
    if (k != key) {
      key = k;
      sel = {};
      if (isDice) {
        if (ttInt(v['bidder'], -1) < 0) {
          qty = 1;
          face = 2;
        } else {
          face = bidFace;
          qty = bidQty + 1;
          if (qty > totalDice) qty = totalDice;
        }
      }
    }
    final deadShots = <int>{
      for (final s in ttList<dynamic>(reveal?['shots']).map(ttMap))
        if (s['dead'] == true) ttInt(s['seat'])
    };

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'reveal') {
      status = '开牌结算中……';
    } else if (myTurn) {
      if (isDice) {
        status = ttInt(v['bidder'], -1) < 0 ? '轮到你：先叫价' : '轮到你：加价或喊骗子';
      } else {
        status = v['mustChallenge'] == true ? '你没有手牌了，只能喊骗子！' : '轮到你：出 1~3 张牌，声称都是 ${v['tableCard']}';
      }
    } else {
      status = '等待 ${g.name(turn)}';
    }

    Widget seat(int s) {
      final dead = !alive[s];
      final sub = isDice
          ? '骰子 ${ttList<int>(v['diceCounts']).elementAtOrNull(s) ?? 0}'
          : '手牌 ${ttList<int>(v['handCounts']).elementAtOrNull(s) ?? 0}';
      final revealDice = reveal == null ? null : ttList<dynamic>(reveal['dice']).elementAtOrNull(s);
      return Opacity(
        opacity: dead && !deadShots.contains(s) ? 0.45 : 1,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: g.tag(s, size: 28, active: s == turn && phase == 'play', sub: dead ? '已出局 ☠' : sub)),
            const SizedBox(width: 4),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Revolver(shots[s], dead: dead, size: 26),
              Text('${shots[s]}/6', style: const TextStyle(fontSize: 10, color: Colors.white70)),
            ]),
          ]),
          if (revealDice != null && (revealDice as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Wrap(spacing: 2, children: [for (final d in ttList<int>(revealDice)) DieFace(d, size: 16)]),
            ),
        ]),
      );
    }

    Widget tableCenter() {
      final children = <Widget>[];
      if (!isDice) {
        children.add(Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('桌牌', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 6),
          BarCard(v['tableCard'] as String? ?? 'Q', width: 34),
          const SizedBox(width: 12),
          const Text('牌堆', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(width: 4),
          Text('${ttInt(v['pile'])}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ]));
        final lp = ttInt(v['lastPlayer'], -1);
        if (reveal != null) {
          children.add(const SizedBox(height: 6));
          children.add(Wrap(spacing: 4, children: [for (final c in ttList<String>(reveal['cards'])) BarCard(c, width: 40)]));
        } else if (lp >= 0) {
          children.add(const SizedBox(height: 6));
          children.add(Wrap(spacing: 4, children: [for (var i = 0; i < ttInt(v['lastCount']); i++) const BarCard('', width: 36)]));
          children.add(Text('${g.name(lp)} 声称：${ttInt(v['lastCount'])} 张 ${v['tableCard']}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)));
        }
      } else {
        final bidder = ttInt(v['bidder'], -1);
        children.add(Text('场上共 $totalDice 颗骰子${wild ? '（1 点万能）' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)));
        if (bidder >= 0) {
          children.add(const SizedBox(height: 4));
          children.add(Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${g.name(bidder)} 叫：$bidQty × ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            DieFace(bidFace, size: 26),
          ]));
        }
      }
      if (reveal != null) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(reveal['why'] as String? ?? '',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
        ));
        for (final s in ttList<dynamic>(reveal['shots']).map(ttMap)) {
          children.add(Text(
              '${g.name(ttInt(s['seat']))} 扣动扳机：${s['dead'] == true ? '砰！出局' : '咔哒，空枪'}（${ttInt(s['shot'])}/6）',
              style: TextStyle(color: s['dead'] == true ? Colors.redAccent : Colors.white, fontSize: 13)));
        }
      }
      return Column(mainAxisSize: MainAxisSize.min, children: children);
    }

    Widget myArea(double w) {
      if (g.seat < 0 || g.seat >= n) return const SizedBox();
      if (!alive[g.seat]) return const Text('你已出局，观战中', style: TextStyle(color: Colors.white70));
      if (isDice) {
        final myDice = ttList<int>(v['dice']);
        final bidder = ttInt(v['bidder'], -1);
        bool higher(int q, int f) {
          if (bidder < 0) return true;
          int rank(int x) => wild && x == 1 ? 7 : x;
          return q > bidQty || (q == bidQty && rank(f) > rank(bidFace));
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [for (final d in myDice) DieFace(d, size: (w / 9).clamp(32.0, 52.0))]),
          const SizedBox(height: 8),
          if (myTurn)
            TTPanel(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: qty > 1 ? () => setState(() => qty--) : null, icon: const Icon(Icons.remove)),
                  Text('$qty 个', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(onPressed: qty < totalDice ? () => setState(() => qty++) : null, icon: const Icon(Icons.add)),
                ]),
                Wrap(spacing: 4, children: [
                  for (var f = 1; f <= 6; f++)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: face == f ? cs.primary : Colors.transparent, width: 3),
                      ),
                      child: DieFace(f, size: 32, onTap: () => setState(() => face = f)),
                    ),
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  FilledButton(
                      onPressed: higher(qty, face) ? () => g.act({'type': 'bid', 'qty': qty, 'face': face}) : null,
                      child: Text('叫 $qty 个 $face')),
                  if (bidder >= 0)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () => g.act({'type': 'challenge'}),
                      child: const Text('骗子！'),
                    ),
                ]),
              ]),
            ),
        ]);
      }
      final hand = ttList<String>(v['hand']);
      final cw = (w / 7).clamp(44.0, 76.0);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, children: [
          for (var i = 0; i < hand.length; i++)
            BarCard(hand[i],
                width: cw,
                selected: sel.contains(i),
                onTap: myTurn && v['mustChallenge'] != true
                    ? () => setState(() {
                          if (!sel.remove(i) && sel.length < 3) sel.add(i);
                        })
                    : null),
        ]),
        const SizedBox(height: 10),
        if (myTurn)
          Wrap(spacing: 8, children: [
            if (v['mustChallenge'] != true)
              FilledButton(
                onPressed: sel.isNotEmpty ? () => g.act({'type': 'play', 'cards': sel.toList()}) : null,
                child: Text(sel.isEmpty ? '选择 1~3 张牌' : '打出 ${sel.length} 张 ${v['tableCard']}'),
              ),
            if (v['canChallenge'] == true)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: () => g.act({'type': 'challenge'}),
                child: const Text('骗子！'),
              ),
          ]),
      ]);
    }

    final others = [for (final s in g.seatsFromMe()) if (s != g.seat) s];
    final log = ttList<String>(v['log']);
    final winner = ttInt(v['winner'], -1);
    final rules = switch (mode) {
      'devil' => '恶魔牌：被质疑时若恶魔牌为真，除出牌者外所有人开枪',
      'chaos' => '混沌牌：被质疑的牌中有混沌牌，双方都要开枪',
      'dice' => '输家对自己开一枪',
      'classic' => '输家失去一颗骰子，没有骰子即出局',
      _ => '王牌为万能牌；被识破者开枪',
    };

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 700;
      final table = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const RadialGradient(colors: [Color(0xFF6D4C41), Color(0xFF3E2723)], radius: 1.1),
          borderRadius: BorderRadius.circular(wide ? 120 : 40),
          border: Border.all(color: const Color(0xFF1B0F0A), width: 8),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.sports_bar, color: Color(0xFFFFD54F), size: 18),
            const SizedBox(width: 4),
            Text('${v['modeName']} · 第 ${ttInt(v['round'])} 轮',
                style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold)),
          ]),
          Text(rules, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [for (final s in others) seat(s)]),
          const SizedBox(height: 10),
          tableCenter(),
          const SizedBox(height: 10),
          if (g.seat >= 0 && g.seat < n) seat(g.seat),
          const SizedBox(height: 8),
          myArea(min(c.maxWidth, 640)),
        ]),
      );
      final logPanel = TTPanel(child: SizedBox(width: double.infinity, child: TTLog(log, max: wide ? 10 : 5)));
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          StatusBar(status, highlight: myTurn),
          if (phase == 'over') ResultBanner(winner >= 0 ? '${g.name(winner)} 是最后的幸存者！' : '无人生还'),
          const SizedBox(height: 8),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 7, child: table),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: logPanel),
            ])
          else ...[
            table,
            const SizedBox(height: 8),
            logPanel,
          ],
        ]),
      );
    });
  }
}
