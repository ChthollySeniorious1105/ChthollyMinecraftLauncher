import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tt_common.dart';

const gemColors = [
  Color(0xFFF5F5F5), // 白
  Color(0xFF1E88E5), // 蓝
  Color(0xFF43A047), // 绿
  Color(0xFFE53935), // 红
  Color(0xFF424242), // 黑
  Color(0xFFFFC107), // 黄金
];
const gemNames = ['白', '蓝', '绿', '红', '黑', '黄金'];
Color gemInk(int c) => (c == 0 || c == 5) ? Colors.black87 : Colors.white;

class Gem extends StatelessWidget {
  final int color;
  final double size;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;
  const Gem(this.color, {super.key, this.size = 30, this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [Color.lerp(gemColors[color], Colors.white, 0.35)!, gemColors[color]], center: const Alignment(-0.3, -0.3)),
        border: Border.all(color: selected ? Colors.amber : Colors.black38, width: selected ? 3 : 1.2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1))],
      ),
      child: label == null
          ? null
          : Text(label!, style: TextStyle(fontSize: size * 0.45, fontWeight: FontWeight.bold, color: gemInk(color))),
    );
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class DevCard extends StatelessWidget {
  final Map<String, dynamic>? card;
  final double width;
  final bool selected;
  final bool affordable;
  final VoidCallback? onTap;
  const DevCard(this.card, {super.key, this.width = 72, this.selected = false, this.affordable = false, this.onTap});

  /// Card faces are laid out at this width and scaled, so tiny cards never overflow.
  static const double _design = 90;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.35;
    final c = card;
    final body = SizedBox(
      width: width,
      height: h,
      child: FittedBox(child: SizedBox(width: _design, height: _design * 1.35, child: _body(c, _design))),
    );
    final w = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.08),
        boxShadow: [
          BoxShadow(color: selected ? Colors.amber : Colors.black38, blurRadius: selected ? 10 : 3, offset: const Offset(1, 2)),
        ],
      ),
      child: body,
    );
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }

  Widget _body(Map<String, dynamic>? c, double width) {
    final h = width * 1.35;
    Widget body;
    if (c == null) {
      body = Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(width * 0.08),
        ),
      );
    } else if (ttInt(c['id'], -1) < 0) {
      final t = ttInt(c['tier']);
      body = _back(t, width);
    } else {
      final col = ttInt(c['color']);
      final pts = ttInt(c['points']);
      final cost = ttList<int>(c['cost']);
      final base = gemColors[col];
      body = Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFAF6EC),
          borderRadius: BorderRadius.circular(width * 0.08),
          border: Border.all(color: affordable ? Colors.greenAccent : Colors.black26, width: affordable ? 2.5 : 1),
        ),
        child: Column(children: [
          Container(
            height: h * 0.3,
            padding: EdgeInsets.symmetric(horizontal: width * 0.08),
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.85),
              borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.08)),
            ),
            child: Row(children: [
              Text(pts > 0 ? '$pts' : '',
                  style: TextStyle(fontSize: width * 0.3, fontWeight: FontWeight.bold, color: gemInk(col))),
              const Spacer(),
              Icon(Icons.diamond, size: width * 0.26, color: col == 0 ? Colors.blueGrey : Colors.white),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(width * 0.05),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (var g = 0; g < 5; g++)
                    if (cost[g] > 0)
                      Padding(
                        padding: EdgeInsets.only(top: width * 0.01),
                        child: Gem(g, size: width * 0.18, label: '${cost[g]}'),
                      ),
                ]),
              ),
            ),
          ),
        ]),
      );
    }
    return body;
  }

  static Widget _back(int t, double width) {
    const cols = [Color(0xFF2E7D32), Color(0xFFF9A825), Color(0xFF1565C0)];
    return Container(
      decoration: BoxDecoration(
        color: cols[t.clamp(0, 2)],
        borderRadius: BorderRadius.circular(width * 0.08),
        border: Border.all(color: Colors.white54, width: 2),
      ),
      alignment: Alignment.center,
      child: Text('${'Ⅰ Ⅱ Ⅲ'.split(' ')[t.clamp(0, 2)]}\n璀璨宝石',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: width * 0.16)),
    );
  }
}

class NobleTile extends StatelessWidget {
  final Map<String, dynamic> noble;
  final double size;
  final VoidCallback? onTap;
  const NobleTile(this.noble, {super.key, this.size = 60, this.onTap});
  @override
  Widget build(BuildContext context) {
    final req = ttList<int>(noble['req']);
    final w = Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: const Color(0xFFEAD9B5),
        borderRadius: BorderRadius.circular(size * 0.1),
        border: Border.all(color: onTap != null ? Colors.amber : Colors.brown, width: onTap != null ? 3 : 1),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      child: FittedBox(child: SizedBox(width: size * 0.88, height: size * 0.88, child: Row(children: [
        Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (var g = 0; g < 5; g++)
            if (req[g] > 0)
              Container(
                width: size * 0.24,
                height: size * 0.24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: gemColors[g], borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black26)),
                child: Text('${req[g]}', style: TextStyle(fontSize: size * 0.15, fontWeight: FontWeight.bold, color: gemInk(g))),
              ),
        ]),
        Expanded(
          child: Column(children: [
            Text('3', style: TextStyle(fontSize: size * 0.3, fontWeight: FontWeight.bold, color: Colors.brown.shade800)),
            Icon(Icons.account_circle, size: size * 0.38, color: Colors.brown.shade400),
          ]),
        ),
      ]))),
    );
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class SplendorBoard extends StatefulWidget {
  final GameContext g;
  const SplendorBoard(this.g, {super.key});
  @override
  State<SplendorBoard> createState() => _SplendorBoardState();
}

class _SplendorBoardState extends State<SplendorBoard> {
  List<int> picks = [];
  Map<String, dynamic>? selCard; // selected dev card (board or reserved)
  int selDeck = -1;
  List<int> ret = List.filled(6, 0);
  String key = '';

  bool _afford(Map<String, dynamic> c, List<int> tokens, List<int> bonus) {
    final cost = ttList<int>(c['cost']);
    var need = 0;
    for (var g = 0; g < 5; g++) {
      final r = cost[g] - bonus[g] - tokens[g];
      if (r > 0) need += r;
    }
    return need <= tokens[5];
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final n = ttInt(v['players']);
    final turn = ttInt(v['turn']);
    final phase = v['phase'] as String? ?? 'main';
    final supply = ttList<int>(v['supply']);
    final ps = ttList<dynamic>(v['ps']).map(ttMap).toList();
    final myTurn = turn == g.seat && phase != 'over';
    final k = '$turn/$phase/${v['last']}';
    if (k != key) {
      key = k;
      picks = [];
      selCard = null;
      selDeck = -1;
      ret = List.filled(6, 0);
    }
    final me = g.seat >= 0 && g.seat < n ? ps[g.seat] : null;
    final myTokens = me == null ? List.filled(6, 0) : ttList<int>(me['tokens']);
    final myBonus = me == null ? List.filled(5, 0) : ttList<int>(me['bonus']);
    final myReserved = me == null ? <Map<String, dynamic>>[] : ttList<dynamic>(me['reserved']).map(ttMap).toList();

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (myTurn) {
      status = switch (phase) {
        'return' => '宝石超过 10 枚，请退回 ${myTokens.fold(0, (a, b) => a + b) - 10} 枚',
        'noble' => '多位贵族可来访，请选择一位',
        _ => '轮到你：拿宝石 / 保留 / 购买',
      };
    } else {
      status = '等待 ${g.name(turn)}';
    }
    if (v['finalRound'] == true && phase != 'over') status += '（最后一轮）';

    void tapGem(int c) {
      if (!myTurn || phase != 'main' || c == 5 || supply[c] <= 0) return;
      setState(() {
        selCard = null;
        selDeck = -1;
        final same = picks.where((x) => x == c).length;
        if (same == 1 && picks.length == 1 && supply[c] >= 4) {
          picks.add(c);
        } else if (picks.contains(c)) {
          picks.removeWhere((x) => x == c);
        } else if (picks.length < 3 && !(picks.length == 2 && picks[0] == picks[1])) {
          picks.add(c);
        }
      });
    }

    Widget supplyRow(double gs) => Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (var c = 0; c < 6; c++)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior: Clip.none, children: [
                Gem(c, size: gs, label: '${supply[c]}', selected: picks.contains(c), onTap: myTurn && phase == 'main' && c < 5 ? () => tapGem(c) : null),
                if (picks.where((x) => x == c).length > 1)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: CircleAvatar(radius: 8, backgroundColor: Colors.amber, child: Text('2', style: TextStyle(fontSize: 10, color: Colors.black))),
                  ),
              ]),
              Text(gemNames[c], style: const TextStyle(fontSize: 10)),
            ]),
        ]);

    Widget boardArea(double cw) {
      final board = ttList<dynamic>(v['board']);
      final decks = ttList<int>(v['decks']);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        for (var t = 2; t >= 0; t--)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Stack(children: [
                DevCard({'id': -1, 'tier': t},
                    width: cw * 0.8,
                    selected: selDeck == t,
                    onTap: myTurn && phase == 'main' && decks[t] > 0
                        ? () => setState(() {
                              selDeck = t;
                              selCard = null;
                              picks = [];
                            })
                        : null),
                Positioned(
                  bottom: 2,
                  right: 4,
                  child: Text('${decks[t]}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(width: 6),
              for (final raw in ttList<dynamic>(board[t]))
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: () {
                    final c = raw == null ? null : ttMap(raw);
                    return DevCard(c,
                        width: cw,
                        selected: c != null && selCard?['id'] == c['id'],
                        affordable: c != null && me != null && _afford(c, myTokens, myBonus),
                        onTap: c != null && myTurn && phase == 'main'
                            ? () => setState(() {
                                  selCard = c;
                                  selDeck = -1;
                                  picks = [];
                                })
                            : null);
                  }(),
                ),
            ]),
          ),
      ]);
    }

    Widget playerPanel(int s, {bool compact = false}) {
      final p = ps[s];
      final tokens = ttList<int>(p['tokens']);
      final bonus = ttList<int>(p['bonus']);
      final reserved = ttList<dynamic>(p['reserved']).map(ttMap).toList();
      final nobles = ttList<dynamic>(p['nobles']).map(ttMap).toList();
      return TTPanel(
        highlight: s == turn && phase != 'over',
        padding: const EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(child: g.tag(s, size: 26, active: s == turn, sub: '${ttInt(p['points'])} 分 · ${ttInt(p['bought'])} 张卡')),
            if (nobles.isNotEmpty) ...[
              const SizedBox(width: 4),
              Icon(Icons.account_circle, size: 18, color: Colors.brown.shade300),
              Text('×${nobles.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 2, children: [
            for (var c = 0; c < 6; c++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (c < 5)
                  Container(
                    width: 16,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: gemColors[c], borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.black26)),
                    child: Text('${bonus[c]}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: gemInk(c))),
                  ),
                Gem(c, size: 18, label: '${tokens[c]}'),
                const SizedBox(width: 2),
              ]),
          ]),
          if (reserved.isNotEmpty && s != g.seat)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Text('保留：', style: TextStyle(fontSize: 11)),
                for (final r in reserved) Padding(padding: const EdgeInsets.only(right: 2), child: DevCard(r, width: 30)),
              ]),
            ),
        ]),
      );
    }

    Widget actionBar() {
      if (!myTurn) return const SizedBox();
      if (phase == 'return') {
        final excess = myTokens.fold(0, (a, b) => a + b) - 10;
        final chosen = ret.fold(0, (a, b) => a + b);
        return TTPanel(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('选择要退回的宝石（$chosen/$excess）'),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              for (var c = 0; c < 6; c++)
                if (myTokens[c] > 0)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Gem(c,
                        size: 30,
                        label: '${myTokens[c] - ret[c]}',
                        onTap: ret[c] < myTokens[c] && chosen < excess ? () => setState(() => ret[c]++) : null),
                    if (ret[c] > 0)
                      InkWell(onTap: () => setState(() => ret[c]--), child: Text('退 ${ret[c]} ↺', style: const TextStyle(fontSize: 11))),
                  ]),
            ]),
            const SizedBox(height: 4),
            FilledButton(onPressed: chosen == excess ? () => g.act({'type': 'return', 'tokens': ret}) : null, child: const Text('确认退回')),
          ]),
        );
      }
      if (phase == 'noble') {
        return TTPanel(
          child: Wrap(spacing: 8, children: [
            for (final nb in ttList<dynamic>(v['nobleChoices']).map(ttMap))
              NobleTile(nb, size: 64, onTap: () => g.act({'type': 'noble', 'noble': nb['id']})),
          ]),
        );
      }
      final buttons = <Widget>[];
      if (picks.isNotEmpty) {
        buttons.add(FilledButton(
            onPressed: () => g.act({'type': 'take', 'colors': picks}),
            child: Text('拿取 ${picks.map((c) => gemNames[c]).join('')}')));
        buttons.add(TextButton(onPressed: () => setState(() => picks = []), child: const Text('取消')));
      } else if (selCard != null) {
        final c = selCard!;
        final canBuy = _afford(c, myTokens, myBonus);
        final isReserved = myReserved.any((r) => r['id'] == c['id']);
        buttons.add(FilledButton(onPressed: canBuy ? () => g.act({'type': 'buy', 'card': c['id']}) : null, child: const Text('购买')));
        if (!isReserved) {
          buttons.add(OutlinedButton(
              onPressed: myReserved.length < 3 ? () => g.act({'type': 'reserve', 'card': c['id']}) : null,
              child: Text(supply[5] > 0 ? '保留 +1 黄金' : '保留')));
        }
      } else if (selDeck >= 0) {
        buttons.add(OutlinedButton(
            onPressed: myReserved.length < 3 ? () => g.act({'type': 'reserve', 'card': -1, 'tier': selDeck}) : null,
            child: Text('从 ${selDeck + 1} 级牌堆盲保留')));
      } else {
        buttons.add(const Text('点宝石拿取（3 种不同色，或同色点两次拿 2 枚），或点卡牌购买/保留', style: TextStyle(fontSize: 12)));
        buttons.add(TextButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('无法行动')));
      }
      return Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: buttons);
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final boardW = wide ? c.maxWidth * 0.62 : c.maxWidth;
      final hMax = wide && c.maxHeight.isFinite ? (c.maxHeight - 150) / 3 / 1.35 : 96.0;
      final cw = ((boardW - 20) / 5.3).clamp(48.0, hMax < 48.0 ? 48.0 : (hMax > 110.0 ? 110.0 : hMax)).toDouble();
      final nobles = ttList<dynamic>(v['nobles']).map(ttMap).toList();
      final center = Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [for (final nb in nobles) NobleTile(nb, size: cw * 0.8)]),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, child: boardArea(cw)),
        supplyRow((cw * 0.5).clamp(28.0, 44.0)),
        const SizedBox(height: 6),
        actionBar(),
      ]);
      final mine = me == null
          ? const SizedBox()
          : Column(mainAxisSize: MainAxisSize.min, children: [
              playerPanel(g.seat),
              if (myReserved.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('我的保留：'),
                    for (final r in myReserved)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: DevCard(r,
                            width: 56,
                            selected: selCard?['id'] == r['id'],
                            affordable: _afford(r, myTokens, myBonus),
                            onTap: myTurn && phase == 'main' ? () => setState(() {
                                  selCard = r;
                                  selDeck = -1;
                                  picks = [];
                                }) : null),
                      ),
                  ]),
                ),
            ]);
      final others = [for (final s in g.seatsFromMe()) if (s != g.seat) s];
      final header = Column(mainAxisSize: MainAxisSize.min, children: [
        StatusBar(status, highlight: myTurn),
        if ((v['last'] as String? ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(v['last'] as String, style: const TextStyle(fontSize: 12))),
        if (phase == 'over')
          ResultBanner('${ttList<int>(v['winners']).map(g.name).join('、')} 获胜！',
              child: Text([for (var s = 0; s < n; s++) '${g.name(s)} ${ttInt(ps[s]['points'])} 分'].join('  '))),
      ]);
      if (wide) {
        return Padding(
          padding: const EdgeInsets.all(6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 62, child: SingleChildScrollView(child: Column(children: [header, const SizedBox(height: 6), center]))),
            const SizedBox(width: 6),
            Expanded(
              flex: 38,
              child: SingleChildScrollView(
                child: Column(children: [
                  for (final s in others) Padding(padding: const EdgeInsets.only(bottom: 6), child: playerPanel(s)),
                  mine,
                ]),
              ),
            ),
          ]),
        );
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          header,
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in others) SizedBox(width: c.maxWidth > 560 ? (c.maxWidth - 24) / 2 : c.maxWidth - 12, child: playerPanel(s)),
          ]),
          const SizedBox(height: 6),
          center,
          const SizedBox(height: 6),
          mine,
        ]),
      );
    });
  }
}
