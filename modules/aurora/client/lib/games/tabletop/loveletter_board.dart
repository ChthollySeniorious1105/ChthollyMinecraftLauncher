import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'tt_common.dart';

const llNames = ['间谍', '卫兵', '牧师', '男爵', '侍女', '王子', '大臣', '国王', '伯爵夫人', '公主'];
const llText = [
  '局末若只有你打出/弃过间谍，+1 好感',
  '猜一名玩家的手牌（非卫兵），猜中则其出局',
  '秘密查看一名玩家的手牌',
  '与一名玩家秘密比牌，小者出局',
  '直到你下回合前不受效果影响',
  '令一名玩家（可为自己）弃牌重摸',
  '摸 2 张，留 1 张，其余置于牌库底',
  '与一名玩家交换手牌',
  '与国王/王子同在手中时必须打出',
  '打出或弃掉即出局',
];
const _llColors = [
  Color(0xFF455A64), Color(0xFF1565C0), Color(0xFF00897B), Color(0xFF6D4C41), Color(0xFF7CB342),
  Color(0xFFF9A825), Color(0xFF5E35B1), Color(0xFFD84315), Color(0xFFAD1457), Color(0xFFC2185B),
];
const _llIcons = [
  Icons.visibility_off, Icons.shield, Icons.church, Icons.balance, Icons.front_hand,
  Icons.person, Icons.menu_book, Icons.workspace_premium, Icons.diamond, Icons.favorite,
];

class LLCard extends StatelessWidget {
  final int card;
  final double width;
  final bool selected;
  final bool dim;
  final bool showText;
  final VoidCallback? onTap;
  const LLCard(this.card, {super.key, this.width = 70, this.selected = false, this.dim = false, this.showText = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    Widget body;
    if (card < 0 || card > 9) {
      body = Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF880E4F), Color(0xFFE91E63)]),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: Colors.white70, width: width * 0.04),
        ),
        child: Center(child: Icon(Icons.mail, color: Colors.white70, size: width * 0.45)),
      );
    } else {
      final col = _llColors[card];
      body = Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(width * 0.1),
          border: Border.all(color: col, width: width * 0.05),
        ),
        padding: EdgeInsets.all(width * 0.05),
        child: Column(children: [
          Row(children: [
            Container(
              width: width * 0.3,
              height: width * 0.3,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('$card',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: width * 0.2)),
            ),
            const Spacer(),
            Icon(_llIcons[card], color: col, size: width * 0.26),
          ]),
          SizedBox(height: width * 0.03),
          Text(llNames[card],
              style: TextStyle(color: col, fontWeight: FontWeight.bold, fontSize: width * (card == 8 ? 0.15 : 0.19))),
          if (showText && width >= 60)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: width * 0.03),
                child: Text(llText[card],
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.fade,
                    style: TextStyle(fontSize: width * 0.105, color: Colors.black87, height: 1.2)),
              ),
            )
          else
            const Spacer(),
        ]),
      );
    }
    Widget w = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.15 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.1),
        boxShadow: [
          BoxShadow(
              color: selected ? Colors.amber : Colors.black38, blurRadius: selected ? 10 : 3, offset: const Offset(1, 2)),
        ],
      ),
      child: body,
    );
    if (dim) w = Opacity(opacity: 0.45, child: w);
    if (onTap == null) return w;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: w));
  }
}

class LoveLetterBoard extends StatefulWidget {
  final GameContext g;
  const LoveLetterBoard(this.g, {super.key});
  @override
  State<LoveLetterBoard> createState() => _LoveLetterBoardState();
}

class _LoveLetterBoardState extends State<LoveLetterBoard> {
  int sel = -1; // index in hand
  int target = -1;
  int keep = -1;
  bool reverse = false;
  String key = '';

  @override
  Widget build(BuildContext context) {
    final g = widget.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final n = ttInt(v['players']);
    final turn = ttInt(v['turn']);
    final phase = v['phase'] as String? ?? 'play';
    final hand = ttList<int>(v['hand']);
    final alive = ttList<bool>(v['alive']);
    final prot = ttList<bool>(v['protected']);
    final tokens = ttList<int>(v['tokens']);
    final discards = ttList<dynamic>(v['discards']).map((e) => ttList<int>(e)).toList();
    final handCounts = ttList<int>(v['handCounts']);
    final myTurn = turn == g.seat && (phase == 'play' || phase == 'chancellor');
    final k = '$turn/$phase/${hand.join(',')}/${ttInt(v['round'])}';
    if (k != key) {
      key = k;
      sel = -1;
      target = -1;
      keep = -1;
      reverse = false;
    }
    final rr = v['roundResult'] == null ? null : ttMap(v['roundResult']);
    final targetN = ttInt(v['target']);

    String status;
    if (phase == 'over') {
      status = '游戏结束';
    } else if (phase == 'roundEnd') {
      status = '本局结束，即将开始下一局';
    } else if (myTurn) {
      status = phase == 'chancellor' ? '大臣：选择保留一张牌' : '轮到你：选择一张牌打出';
    } else {
      status = '等待 ${g.name(turn)} 出牌';
    }

    Widget seatPanel(int s) {
      final dead = !alive[s];
      return TTPanel(
        highlight: s == turn && phase != 'over' && phase != 'roundEnd',
        padding: const EdgeInsets.all(6),
        color: dead ? cs.surface.withValues(alpha: 0.4) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: g.tag(s,
                  size: 28,
                  active: s == turn && !dead,
                  sub: dead ? '已出局' : (prot[s] ? '侍女保护中' : '手牌 ${handCounts[s]}')),
            ),
            const SizedBox(width: 4),
            if (prot[s]) const Icon(Icons.shield, size: 18, color: Colors.lightGreen),
            const Icon(Icons.favorite, size: 14, color: Colors.pinkAccent),
            Text('${tokens[s]}/$targetN', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 44,
            child: discards[s].isEmpty
                ? Center(child: Text('（无弃牌）', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))))
                : ListView(scrollDirection: Axis.horizontal, children: [
                    for (final c in discards[s])
                      Padding(padding: const EdgeInsets.only(right: 2), child: LLCard(c, width: 31, showText: false)),
                  ]),
          ),
          if (rr != null && ttList<int>(rr['hands']).elementAtOrNull(s) != null && ttList<int>(rr['hands'])[s] >= 0)
            Text('手牌：${llNames[ttList<int>(rr['hands'])[s]]}', style: const TextStyle(fontSize: 11)),
        ]),
      );
    }

    Widget actionArea() {
      if (!myTurn) return const SizedBox();
      if (phase == 'chancellor') {
        final rest = [for (var i = 0; i < hand.length; i++) if (i != keep) hand[i]];
        final order = reverse ? rest.reversed.toList() : rest;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (keep >= 0 && order.length > 1)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('放回牌库底顺序（先放 → 最底）：${order.map((c) => llNames[c]).join(' → ')}',
                    style: const TextStyle(fontSize: 12)),
              ),
              IconButton(onPressed: () => setState(() => reverse = !reverse), icon: const Icon(Icons.swap_horiz)),
            ]),
          FilledButton(
            onPressed: keep >= 0 ? () => g.act({'type': 'keep', 'card': hand[keep], 'bottom': order}) : null,
            child: Text(keep >= 0 ? '保留 ${llNames[hand[keep]]}' : '点选要保留的牌'),
          ),
        ]);
      }
      if (sel < 0) return const Text('点选一张手牌');
      final card = hand[sel];
      final needsTarget = [1, 2, 3, 5, 7].contains(card);
      final legal = [
        for (var s = 0; s < n; s++)
          if (alive[s] && !prot[s] && (s != g.seat || card == 5)) s
      ];
      final noTarget = needsTarget && legal.isEmpty;
      final ready = !needsTarget || noTarget || legal.contains(target);
      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (needsTarget && !noTarget)
          Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
            const Text('目标：'),
            for (final s in legal)
              ChoiceChip(
                label: Text(s == g.seat ? '自己' : g.name(s)),
                selected: target == s,
                onSelected: (_) => setState(() => target = s),
              ),
          ]),
        if (noTarget) const Text('所有其他玩家都受保护，此牌将无效果打出', style: TextStyle(fontSize: 12)),
        if (card == 1 && !noTarget && ready)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
              const Text('猜测：'),
              for (var c = 0; c < 10; c++)
                if (c != 1)
                  ActionChip(
                    label: Text('$c ${llNames[c]}'),
                    onPressed: () => g.act({'type': 'play', 'card': 1, 'target': target, 'guess': c}),
                  ),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton(
              onPressed: ready ? () => g.act({'type': 'play', 'card': card, 'target': noTarget ? -1 : target}) : null,
              child: Text('打出 ${llNames[card]}'),
            ),
          ),
      ]);
    }

    final others = [for (final s in g.seatsFromMe()) if (s != g.seat) s];
    final priv = ttList<String>(v['priv']);
    final log = ttList<String>(v['log']);
    final faceUp = ttList<int>(v['faceUp']);

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 760;
      final cardW = (c.maxWidth / 4.2).clamp(70.0, 110.0);
      final center = TTPanel(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const LLCard(-1, width: 34),
            const SizedBox(width: 6),
            Text('牌库 ${ttInt(v['deck'])} 张', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (faceUp.isNotEmpty) ...[
              const SizedBox(width: 10),
              const Text('明置：', style: TextStyle(fontSize: 12)),
              for (final f in faceUp) Padding(padding: const EdgeInsets.all(1), child: LLCard(f, width: 30, showText: false)),
            ],
          ]),
          const SizedBox(height: 6),
          TTLog(log, max: wide ? 7 : 4),
          if (priv.isNotEmpty) ...[
            const Divider(height: 10),
            Row(children: [
              Icon(Icons.lock, size: 14, color: cs.tertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(priv.last,
                    style: TextStyle(fontSize: 12, color: cs.tertiary, fontWeight: FontWeight.bold)),
              ),
            ]),
          ],
        ]),
      );
      final me = g.seat >= 0 && g.seat < n;
      final mySection = Column(mainAxisSize: MainAxisSize.min, children: [
        if (me) seatPanel(g.seat),
        const SizedBox(height: 6),
        if (me)
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            for (var i = 0; i < hand.length; i++)
              LLCard(hand[i],
                  width: cardW,
                  selected: phase == 'chancellor' ? keep == i : sel == i,
                  dim: myTurn && phase == 'play' && v['mustCountess'] == true && hand[i] != 8,
                  onTap: myTurn
                      ? () => setState(() {
                            if (phase == 'chancellor') {
                              keep = i;
                            } else {
                              sel = i;
                              target = -1;
                            }
                          })
                      : null),
          ]),
        const SizedBox(height: 6),
        actionArea(),
      ]);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          StatusBar(status, highlight: myTurn),
          if (rr != null)
            ResultBanner(
              phase == 'over'
                  ? '${ttList<int>(v['winners']).map(g.name).join('、')} 赢得了公主的芳心！'
                  : '本局胜者：${ttList<int>(rr['winners']).map(g.name).join('、')}',
              child: Text('${rr['why']}${ttInt(rr['spy'], -1) >= 0 ? '；${g.name(ttInt(rr['spy']))} 获得间谍奖励' : ''}'),
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
            for (final s in others) SizedBox(width: wide ? 260 : (c.maxWidth - 24) / 2, child: seatPanel(s)),
          ]),
          const SizedBox(height: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: center),
          const SizedBox(height: 6),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: mySection),
        ]),
      );
    });
  }
}
