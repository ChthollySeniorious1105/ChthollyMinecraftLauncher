import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _ekInfo = {
  'bomb': ('爆炸猫', '💣', Color(0xFF212121), '摸到且无拆除即出局'),
  'defuse': ('拆除', '🛠', Color(0xFF43A047), '拆掉爆炸猫并放回牌堆'),
  'skip': ('跳过', '⏭', Color(0xFF1E88E5), '结束一个回合，不摸牌'),
  'attack': ('攻击', '⚡', Color(0xFFE65100), '结束回合，下家连续 2 回合'),
  'shuffle': ('洗牌', '🔀', Color(0xFF6D4C41), '把牌堆洗乱'),
  'future': ('先知', '🔮', Color(0xFF8E24AA), '偷看牌堆顶 3 张'),
  'favor': ('索要', '🎁', Color(0xFF546E7A), '指定一人交给你一张牌'),
  'nope': ('不要', '✋', Color(0xFFC62828), '阻止任意行动（可反制）'),
  'cat1': ('彩虹猫', '🌈', Color(0xFFEC407A), '两张：随机抽一张；三张：指定索要'),
  'cat2': ('西瓜猫', '🍉', Color(0xFF66BB6A), '两张：随机抽一张；三张：指定索要'),
  'cat3': ('胡子猫', '🧔', Color(0xFFFFA726), '两张：随机抽一张；三张：指定索要'),
  'cat4': ('土豆猫', '🥔', Color(0xFFA1887F), '两张：随机抽一张；三张：指定索要'),
  'cat5': ('章鱼猫', '🐙', Color(0xFF26C6DA), '两张：随机抽一张；三张：指定索要'),
};

String ekName(String c) => _ekInfo[c]?.$1 ?? c;

/// Original card face: colored rounded rectangle with an emoji icon and a Chinese name.
class EkCard extends StatelessWidget {
  final String code;
  final double width;
  final bool selected;
  final bool dim;
  final VoidCallback? onTap;
  final bool back;
  const EkCard(this.code, {super.key, this.width = 64, this.selected = false, this.dim = false, this.onTap, this.back = false});

  @override
  Widget build(BuildContext context) {
    final h = width * 1.4;
    final info = _ekInfo[code];
    Widget body;
    if (back || info == null) {
      body = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: const LinearGradient(colors: [Color(0xFFB71C1C), Color(0xFF311B92)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white, width: width * 0.04),
        ),
        child: Center(child: Text('🐱', style: TextStyle(fontSize: width * 0.45))),
      );
    } else {
      body = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: LinearGradient(
            colors: [info.$3, Color.lerp(info.$3, Colors.black, 0.35)!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: width * 0.04),
        ),
        padding: EdgeInsets.all(width * 0.05),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: width * 0.82,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            child: Text(info.$1, style: TextStyle(fontSize: width * 0.2, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          Text(info.$2, style: TextStyle(fontSize: width * 0.42)),
          if (width >= 56)
            Text(info.$4,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: width * 0.1, color: Colors.white70, height: 1.1)),
            ]),
          ),
        ),
      );
    }
    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: h,
      transform: Matrix4.translationValues(0, selected ? -width * 0.25 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.12),
        boxShadow: [
          BoxShadow(color: selected ? Colors.amber : Colors.black45, blurRadius: selected ? 8 : 3, offset: const Offset(1, 2)),
        ],
      ),
      child: body,
    );
    if (dim) card = Opacity(opacity: 0.45, child: card);
    if (onTap == null) return card;
    return MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: card));
  }
}

class ExplodingBoard extends StatefulWidget {
  final GameContext g;
  const ExplodingBoard(this.g, {super.key});
  @override
  State<ExplodingBoard> createState() => _ExplodingBoardState();
}

class _ExplodingBoardState extends State<ExplodingBoard> {
  int _sel = -1; // index into hand
  int _placePos = 0;
  String _handKey = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  List<String> get hand => [for (final c in (v['hand'] as List? ?? const [])) '$c'];

  Future<int?> _pickTarget() async {
    final alive = (v['alive'] as List).cast<bool>();
    final counts = (v['counts'] as List).cast<int>();
    final opts = [for (var s = 0; s < g.players; s++) if (s != g.seat && alive[s] && counts[s] > 0) s];
    if (opts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可选择的对手')));
      return null;
    }
    if (opts.length == 1) return opts.first;
    return showDialog<int>(useRootNavigator: false, 
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('选择目标'),
        children: [
          for (final s in opts)
            SimpleDialogOption(onPressed: () => Navigator.pop(c, s), child: Text('${g.name(s)}（${counts[s]}张）')),
        ],
      ),
    );
  }

  Future<String?> _pickName() => showDialog<String>(useRootNavigator: false, 
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('指定要索取的牌'),
          children: [
            for (final k in _ekInfo.keys)
              if (k != 'bomb')
                SimpleDialogOption(onPressed: () => Navigator.pop(c, k), child: Text('${_ekInfo[k]!.$2} ${_ekInfo[k]!.$1}')),
          ],
        ),
      );

  Future<void> _play(String card, {int count = 1}) async {
    final a = <String, dynamic>{'type': 'play', 'card': card};
    if (card == 'favor' || card.startsWith('cat')) {
      final t = await _pickTarget();
      if (t == null) return;
      a['target'] = t;
    }
    if (card.startsWith('cat')) {
      a['count'] = count;
      if (count == 3) {
        final n = await _pickName();
        if (n == null) return;
        a['named'] = n;
      }
    }
    g.act(a);
    setState(() => _sel = -1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = hand;
    final k = h.join(',');
    if (k != _handKey) {
      _handKey = k;
      _sel = -1;
    }
    if (_sel >= h.length) _sel = -1;
    final phase = '${v['phase']}';
    final turn = v['turn'] as int;
    final me = g.seat;
    final alive = (v['alive'] as List).cast<bool>();
    final counts = (v['counts'] as List).cast<int>();
    final nopers = (v['nopers'] as List).cast<int>();
    final pending = v['pending'] as Map?;
    final myTurn = me >= 0 && phase == 'turn' && turn == me;
    final canNope = phase == 'nope' && nopers.contains(me);
    final favorMe = phase == 'favor' && v['favorFrom'] == me;
    final defuseMe = phase == 'defuse' && turn == me;
    final future = (v['future'] as List?)?.cast<String>();
    final winner = v['winner'] as int;

    String status;
    switch (phase) {
      case 'turn':
        status = myTurn
            ? '轮到你：出牌或摸牌结束回合${(v['turnsLeft'] as int) > 1 ? "（还需 ${v['turnsLeft']} 回合）" : ""}'
            : '等待 ${g.name(turn)}${(v['turnsLeft'] as int) > 1 ? "（${v['turnsLeft']} 回合）" : ""}';
        break;
      case 'nope':
        status = canNope ? '可以打出「不要」阻止！' : '等待其他玩家是否「不要」…';
        break;
      case 'favor':
        status = favorMe ? '选择一张牌交给 ${g.name(v['favorTo'] as int)}' : '等待 ${g.name(v['favorFrom'] as int)} 给牌';
        break;
      case 'defuse':
        status = defuseMe ? '选择爆炸猫放回牌堆的位置' : '${g.name(turn)} 正在放回爆炸猫…';
        break;
      default:
        status = winner >= 0 ? '${g.name(winner)} 获胜！' : '游戏结束';
    }

    return Container(
      color: g.table,
      child: LayoutBuilder(builder: (context, c) {
        final cw = (c.maxWidth / 7.5).clamp(48.0, 92.0).toDouble().clamp(40.0, c.maxHeight / 5.2).toDouble();
        final others = g.seatsFromMe().where((s) => s != me).toList();
        final sel = _sel >= 0 ? h[_sel] : null;
        final selCount = sel == null ? 0 : h.where((x) => x == sel).length;
        return Stack(children: [
          Column(children: [
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
              for (final s in others)
                Opacity(
                  opacity: alive[s] ? 1 : 0.45,
                  child: g.tag(s,
                      size: 32,
                      active: alive[s] && (phase == 'turn' || phase == 'defuse') && turn == s,
                      sub: alive[s] ? '手牌 ${counts[s]}' : '💥 已出局'),
                ),
            ]),
            const SizedBox(height: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Column(children: [
                        EkCard('back', width: cw, back: true),
                        const SizedBox(height: 4),
                        Text('牌堆 ${v['deck']} 张', style: const TextStyle(color: Colors.white)),
                        Text('其中 ${v['kittens']} 只爆炸猫', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                      ]),
                      const SizedBox(width: 24),
                      Column(children: [
                        if ((v['discard'] as List).isEmpty)
                          SizedBox(width: cw, height: cw * 1.4)
                        else
                          EkCard('${(v['discard'] as List).last}', width: cw),
                        const SizedBox(height: 4),
                        const Text('弃牌堆', style: TextStyle(color: Colors.white)),
                        const Text('', style: TextStyle(fontSize: 12)),
                      ]),
                    ]),
                    const SizedBox(height: 10),
                    if (pending != null) _pendingBox(pending, cs),
                    if (future != null && future.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
                        child: Column(children: [
                          const Text('🔮 牌堆顶（左为最上）', style: TextStyle(color: Colors.white)),
                          const SizedBox(height: 4),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            for (final f in future) Padding(padding: const EdgeInsets.all(3), child: EkCard(f, width: cw * 0.7)),
                          ]),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    for (final e in (v['events'] as List).reversed.take(3))
                      Text('$e', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
              ),
            ),
            StatusBar(status, highlight: myTurn || canNope || favorMe || defuseMe),
            const SizedBox(height: 6),
            if (me >= 0) ...[
              _actions(myTurn, canNope, favorMe, defuseMe, sel, selCount),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                g.tag(me,
                    size: 28,
                    active: alive[me] && (phase == 'turn' || phase == 'defuse') && turn == me,
                    sub: alive[me] ? '手牌 ${h.length}' : '💥 已出局'),
              ]),
              const SizedBox(height: 4),
              SizedBox(
                height: cw * 1.4 + cw * 0.3,
                child: Center(
                  child: _handRow(h, cw, c.maxWidth - 16),
                ),
              ),
            ],
            const SizedBox(height: 6),
          ]),
          if (phase == 'over')
            Center(
              child: ResultBanner(
                winner == me ? '你是最后的幸存者！🎉' : '${g.name(winner)} 获胜！',
                child: Text(alive.asMap().entries.where((e) => !e.value).map((e) => g.name(e.key)).join('、').isEmpty
                    ? ''
                    : '出局：${[for (var s = 0; s < g.players; s++) if (!alive[s]) g.name(s)].join('、')}'),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _pendingBox(Map pending, ColorScheme cs) {
    final nope = (v['nopeCount'] as int).isOdd;
    final card = '${pending['card']}';
    final target = pending['target'] as int;
    final count = (pending['count'] as int?) ?? 1;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: (nope ? Colors.red : Colors.black).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: nope ? Colors.redAccent : Colors.white30),
      ),
      child: Column(children: [
        Text(
          '${g.name(pending['seat'] as int)} 打出 ${count > 1 ? "$count×" : ""}「${ekName(card)}」${target >= 0 && card != 'attack' ? " → ${g.name(target)}" : ""}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        Text(nope ? '✋ 当前被「不要」阻止（×${v['nopeCount']}）' : '等待响应…',
            style: TextStyle(color: nope ? Colors.redAccent : Colors.white70)),
      ]),
    );
  }

  Widget _actions(bool myTurn, bool canNope, bool favorMe, bool defuseMe, String? sel, int selCount) {
    final btns = <Widget>[];
    if (myTurn) {
      btns.add(FilledButton.icon(onPressed: () => g.act({'type': 'draw'}), icon: const Icon(Icons.style), label: const Text('摸牌')));
      if (sel != null) {
        if (const {'skip', 'attack', 'shuffle', 'future', 'favor'}.contains(sel)) {
          btns.add(FilledButton.tonal(onPressed: () => _play(sel), child: Text('打出「${ekName(sel)}」')));
        } else if (sel.startsWith('cat')) {
          btns.add(FilledButton.tonal(onPressed: selCount >= 2 ? () => _play(sel, count: 2) : null, child: const Text('出一对')));
          btns.add(FilledButton.tonal(onPressed: selCount >= 3 ? () => _play(sel, count: 3) : null, child: const Text('出三张')));
        }
      }
    }
    if (canNope) {
      btns.add(FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.red),
        onPressed: () => g.act({'type': 'nope'}),
        child: const Text('✋ 不要！'),
      ));
      btns.add(OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('放行')));
    }
    if (favorMe) {
      btns.add(FilledButton(
        onPressed: sel == null ? null : () => g.act({'type': 'give', 'card': sel}),
        child: Text(sel == null ? '选择一张牌' : '交出「${ekName(sel)}」'),
      ));
    }
    if (defuseMe) {
      final deck = v['deck'] as int;
      if (_placePos > deck) _placePos = deck;
      btns.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Text('位置：${_placePos == 0 ? "最上面" : (_placePos == deck ? "最底下" : "第 ${_placePos + 1} 张")}',
            style: const TextStyle(color: Colors.white)),
        SizedBox(
          width: 180,
          child: Slider(
            value: _placePos.toDouble(),
            min: 0,
            max: deck.toDouble() <= 0 ? 1 : deck.toDouble(),
            divisions: deck <= 0 ? 1 : deck,
            onChanged: (x) => setState(() => _placePos = x.round().clamp(0, deck)),
          ),
        ),
      ]));
      btns.add(FilledButton(onPressed: () => g.act({'type': 'place', 'pos': _placePos}), child: const Text('放回')));
    }
    if (btns.isEmpty) return const SizedBox(height: 8);
    return Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: btns);
  }

  Widget _handRow(List<String> h, double cw, double maxW) {
    if (h.isEmpty) return const SizedBox();
    final n = h.length;
    var step = n <= 1 ? cw : (maxW - cw) / (n - 1);
    step = step.clamp(cw * 0.3, cw * 1.05).toDouble();
    return SizedBox(
      width: cw + step * (n - 1),
      height: cw * 1.4 + cw * 0.3,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < n; i++)
          Positioned(
            left: step * i,
            bottom: 0,
            child: EkCard(h[i], width: cw, selected: _sel == i, onTap: () => setState(() => _sel = _sel == i ? -1 : i)),
          ),
      ]),
    );
  }
}
