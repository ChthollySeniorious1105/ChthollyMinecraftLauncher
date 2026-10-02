import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'uno_card.dart';

const _darkCols = {'p', 't', 'o', 'v'};

class UnoBoard extends StatefulWidget {
  final GameContext g;
  const UnoBoard(this.g, {super.key});
  @override
  State<UnoBoard> createState() => _UnoBoardState();
}

class _UnoBoardState extends State<UnoBoard> {
  bool _sayUno = false;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  bool get dark => v['dark'] == true;
  List<String> get colors => dark ? ['p', 't', 'o', 'v'] : ['r', 'y', 'g', 'b'];

  bool isDarkFace(String? f) {
    if (f == null) return false;
    if (f[0] == 'w') return dark;
    return _darkCols.contains(f[0]);
  }

  Future<String?> _pickColor(String title) => showDialog<String>(useRootNavigator: false, 
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final c in colors)
              InkWell(
                onTap: () => Navigator.pop(ctx, c),
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: unoColorValues[c],
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
                  ),
                  child: Text(unoColorLabel[c]!,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ),
          ]),
        ),
      );

  Future<int?> _pickTarget() {
    final ps = (v['players'] as List).cast<Map>();
    return showDialog<int>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('选择要交换手牌的玩家'), children: [
        for (var s = 0; s < ps.length; s++)
          if (s != g.seat && ps[s]['out'] != true)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Text('${g.name(s)}（${ps[s]['count']} 张）'),
            ),
      ]),
    );
  }

  Future<void> _play(int id, String f, int handCount) async {
    final a = <String, dynamic>{'type': 'play', 'card': id};
    final k = f.substring(1);
    if (f[0] == 'w' && k != 'RL') {
      final c = await _pickColor('选择颜色');
      if (c == null) return;
      a['color'] = c;
    }
    final ps = (v['players'] as List).cast<Map>();
    final active = ps.where((p) => p['out'] != true).length;
    if (v['mode'] == 'nomercy' && k == '7' && handCount > 1 && active > 2) {
      final t = await _pickTarget();
      if (t == null) return;
      a['target'] = t;
    }
    if (handCount == 2 && _sayUno) a['uno'] = true;
    g.act(a);
    setState(() => _sayUno = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ps = (v['players'] as List).cast<Map>();
    final turn = v['turn'] as int;
    final phase = v['phase'] as String;
    final me = g.seat;
    final myTurn = !g.over && turn == me && phase != 'roundEnd';
    final hand = (v['hand'] as List).cast<Map>();
    final playable = (v['playable'] as List).cast<int>().toSet();
    final pending = v['pending'] as int;
    final pendingColor = v['pendingColor'] == true;
    final vulnerable = v['vulnerable'] as int;
    final color = v['color'] as String?;
    final mode = v['mode'] as String;

    String status;
    if (g.over) {
      final w = v['winner'] as int;
      status = w >= 0 ? '${g.name(w)} 获胜！' : '游戏结束';
    } else if (phase == 'roundEnd') {
      status = '${g.name(v['roundWinner'] as int)} 赢得本局，下一局即将开始';
    } else if (myTurn) {
      if (phase == 'roulette') {
        status = '颜色轮盘：选择一种颜色，翻牌直到出现该色';
      } else if (phase == 'drawn') {
        status = '可以打出刚摸到的牌，或选择不出';
      } else if (pendingColor) {
        status = '被万能抽色！摸牌直到出现${unoColorLabel[color] ?? ''}色${v['challengeFrom'] >= 0 ? '，或质疑' : ''}';
      } else if (pending > 0) {
        status = '被罚 $pending 张！${v['stacking'] == true ? '可叠加加牌，' : ''}${v['challengeFrom'] >= 0 ? '可质疑，' : ''}或摸牌';
      } else {
        status = '轮到你出牌';
      }
    } else {
      status = '等待 ${g.name(turn)}';
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.2;
      final cardW = (wide ? c.maxHeight * 0.13 : c.maxWidth * 0.15).clamp(40.0, 76.0);
      final oppIds = [for (final s in g.seatsFromMe()) if (s != me) s];

      Widget opp(int s) {
        final p = ps[s];
        final backs = (p['backs'] as List?)?.cast<String?>();
        final active = !g.over && s == turn;
        final sub = p['out'] == true
            ? '已淘汰'
            : '${p['count']} 张${(v['target'] as int) > 0 ? ' · ${p['score']}分' : ''}';
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            g.tag(s, active: active, sub: sub, size: 30),
            if (p['uno'] == true)
              Positioned(right: -4, top: -8, child: _badge('UNO', Colors.redAccent)),
          ]),
          if (backs != null && backs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SizedBox(
                width: 130,
                child: OverlapRowFit(
                  itemWidth: 18,
                  children: [for (final b in backs) UnoCard(b, width: 18, darkSide: isDarkFace(b))],
                ),
              ),
            ),
        ]);
      }

      final opponents = Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [for (final s in oppIds) opp(s)],
      );

      final dirIcon = Icon(
        (v['dir'] as int) == 1 ? Icons.rotate_right : Icons.rotate_left,
        size: cardW * 0.7,
        color: cs.onSurface.withValues(alpha: 0.8),
      );

      final drawBack = v['drawBack'] as String?;
      final canDraw = myTurn && (phase == 'play');
      final center = Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          UnoCard(drawBack, width: cardW, darkSide: isDarkFace(drawBack), highlight: canDraw, onTap: canDraw ? () => g.act({'type': 'draw'}) : null),
          const SizedBox(height: 2),
          Text('牌堆 ${v['drawCount']}', style: const TextStyle(fontSize: 12)),
        ]),
        SizedBox(width: cardW * 0.3),
        Column(mainAxisSize: MainAxisSize.min, children: [
          UnoCard(v['top'] as String?, width: cardW * 1.15, darkSide: isDarkFace(v['top'] as String?)),
          const SizedBox(height: 2),
          Text('弃牌 ${v['discardCount']}', style: const TextStyle(fontSize: 12)),
        ]),
        SizedBox(width: cardW * 0.3),
        Column(mainAxisSize: MainAxisSize.min, children: [
          dirIcon,
          const SizedBox(height: 4),
          Container(
            width: cardW * 0.55,
            height: cardW * 0.55,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color == null ? Colors.grey : unoColorValues[color],
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
            ),
            alignment: Alignment.center,
            child: Text(color == null ? '任意' : unoColorLabel[color] ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          if (pending > 0 || pendingColor) ...[
            const SizedBox(height: 4),
            _badge(pendingColor ? '抽色' : '+$pending', Colors.deepOrange, big: true),
          ],
        ]),
      ]);

      final buttons = <Widget>[];
      if (myTurn && phase == 'drawn') {
        buttons.add(FilledButton.tonal(onPressed: () => g.act({'type': 'pass'}), child: const Text('不出')));
      }
      if (myTurn && phase == 'play' && (pending > 0 || pendingColor)) {
        buttons.add(FilledButton(
            onPressed: () => g.act({'type': 'draw'}),
            child: Text(pendingColor ? '接受抽色' : '摸 $pending 张')));
        if ((v['challengeFrom'] as int) >= 0) {
          buttons.add(OutlinedButton(onPressed: () => g.act({'type': 'challenge'}), child: const Text('质疑')));
        }
      } else if (myTurn && phase == 'play') {
        buttons.add(OutlinedButton.icon(
            onPressed: () => g.act({'type': 'draw'}), icon: const Icon(Icons.add), label: const Text('摸牌')));
      }
      if (myTurn && phase == 'roulette') {
        for (final col in colors) {
          buttons.add(FilledButton(
            style: FilledButton.styleFrom(backgroundColor: unoColorValues[col]),
            onPressed: () => g.act({'type': 'roulette', 'color': col}),
            child: Text(unoColorLabel[col]!, style: const TextStyle(color: Colors.white)),
          ));
        }
      }
      if (me >= 0 && hand.length == 2 && myTurn && !g.over) {
        buttons.add(FilterChip(
          label: const Text('UNO!'),
          selected: _sayUno,
          selectedColor: Colors.redAccent,
          onSelected: (b) => setState(() => _sayUno = b),
        ));
      }
      if (me >= 0 && vulnerable == me) {
        buttons.add(FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => g.act({'type': 'uno'}),
            child: const Text('喊 UNO！')));
      }
      if (me >= 0 && vulnerable >= 0 && vulnerable != me && ps[me]['out'] != true) {
        buttons.add(FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => g.act({'type': 'catch'}),
            child: Text('抓 ${g.name(vulnerable)} 没喊UNO')));
      }

      Widget handView() {
        if (me < 0) return const SizedBox();
        final w = cardW;
        final children = [
          for (final h in hand)
            UnoCard(
              h['f'] as String,
              width: w,
              darkSide: dark,
              highlight: myTurn && playable.contains(h['id']),
              dim: myTurn && !playable.contains(h['id']),
              onTap: myTurn && playable.contains(h['id'])
                  ? () => _play(h['id'] as int, h['f'] as String, hand.length)
                  : null,
            ),
        ];
        final avail = c.maxWidth - 16;
        final perRow = ((avail - w) / (w * 0.32)).floor() + 1;
        final rows = <List<Widget>>[];
        for (var i = 0; i < children.length; i += perRow) {
          rows.add(children.sublist(i, (i + perRow).clamp(0, children.length)));
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in rows)
            Padding(
              padding: EdgeInsets.only(top: w * 0.28),
              child: SizedBox(width: avail, child: Center(child: OverlapRowFit(itemWidth: w, children: r))),
            ),
        ]);
      }

      final modeLabel = {'classic': '经典', 'flip': 'FLIP', 'nomercy': 'NO MERCY'}[mode] ?? mode;
      final result = (v['result'] as List).cast<Map>();

      return Container(
        color: g.table.withValues(alpha: 0.25),
        child: Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: c.maxHeight * (wide ? 0.3 : 0.28)),
                child: SingleChildScrollView(child: opponents),
              ),
            ),
            const SizedBox(height: 4),
            StatusBar(status, highlight: myTurn),
            Text('$modeLabel${dark ? ' · 暗面' : ''}${v['stacking'] == true ? ' · 可叠加' : ''} · ${v['last']}',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8))),
            Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: center))),
            if (buttons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: buttons),
              ),
            if (me >= 0)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                g.tag(me, active: myTurn, size: 26, sub: '${hand.length} 张${(v['target'] as int) > 0 ? ' · ${ps[me]['score']}分' : ''}'),
                if (ps[me]['uno'] == true) Padding(padding: const EdgeInsets.only(left: 6), child: _badge('UNO', Colors.redAccent)),
              ]),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: c.maxHeight * 0.42),
                child: SingleChildScrollView(child: handView()),
              ),
            ),
            const SizedBox(height: 6),
          ]),
          if (result.isNotEmpty && (g.over || phase == 'roundEnd'))
            Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 420, maxHeight: c.maxHeight * 0.8),
                child: ResultBanner(
                  status,
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final r in result)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${g.name(r['seat'] as int)}：${r['out'] == true ? '淘汰' : mode == 'nomercy' ? '剩 ${r['points']} 张' : '剩 ${(r['cards'] as List).length} 张 / ${r['points']} 点'}'
                            '${(v['target'] as int) > 0 ? '，总分 ${ps[r['seat'] as int]['score']}' : ''}',
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }

  Widget _badge(String s, Color c, {bool big = false}) => Container(
        padding: EdgeInsets.symmetric(horizontal: big ? 8 : 5, vertical: big ? 3 : 1),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)),
        child: Text(s,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: big ? 16 : 11)),
      );
}

/// Overlapping row that always fits the available width (children overlap as needed).
class OverlapRowFit extends StatelessWidget {
  final List<Widget> children;
  final double itemWidth;
  const OverlapRowFit({super.key, required this.children, required this.itemWidth});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = children.length;
      if (n == 0) return const SizedBox();
      final avail = c.maxWidth.isFinite ? c.maxWidth : n * itemWidth * 1.05;
      var step = n <= 1 ? itemWidth : (avail - itemWidth) / (n - 1);
      if (step > itemWidth * 1.05) step = itemWidth * 1.05;
      if (step < 1) step = 1;
      final total = itemWidth + step * (n - 1);
      return SizedBox(
        width: total,
        child: Stack(clipBehavior: Clip.none, children: [
          Opacity(opacity: 0, child: IgnorePointer(child: children.first)),
          for (var i = 0; i < n; i++) Positioned(left: step * i, bottom: 0, child: children[i]),
        ]),
      );
    });
  }
}
