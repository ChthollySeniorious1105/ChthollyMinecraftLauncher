import 'package:aurora_shared/games/monopoly/board_data.dart';
import 'package:flutter/material.dart';

import '../../widgets/pieces.dart';
import 'monopoly_painter.dart';
import 'monopoly_panels.dart';
import 'monopoly_view.dart';

int _n(Object? v) => v is num ? v.toInt() : 0;
List<int> _ints(Object? v) => v is List ? [for (final e in v) _n(e)] : <int>[];

/// Dice + context-sensitive action buttons.
class MActionPanel extends StatelessWidget {
  final MView m;
  final void Function() onTrade;
  const MActionPanel(this.m, {super.key, required this.onTrade});

  Widget _btn(String label, VoidCallback? f, {bool primary = false, IconData? icon}) {
    final child = FittedBox(fit: BoxFit.scaleDown, child: Text(label));
    final style = ButtonStyle(visualDensity: VisualDensity.compact);
    if (primary) {
      return icon != null
          ? FilledButton.icon(onPressed: f, icon: Icon(icon, size: 18), label: child, style: style)
          : FilledButton(onPressed: f, style: style, child: child);
    }
    return icon != null
        ? OutlinedButton.icon(onPressed: f, icon: Icon(icon, size: 16), label: child, style: style)
        : OutlinedButton(onPressed: f, style: style, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = m.g;
    final act = g.act;
    final me = m.mine;
    final btns = <Widget>[];
    Widget? extra;

    switch (m.phase) {
      case 'roll':
        if (m.myTurn) {
          btns.add(_btn(me!.jail ? '掷骰（求对子）' : '掷骰子', () => act({'t': 'roll'}), primary: true, icon: Icons.casino));
          if (me.jail) {
            btns.add(_btn('保释 ¥50', me.cash >= 50 ? () => act({'t': 'payJail'}) : null));
            if (me.cards > 0) btns.add(_btn('使用许可证', () => act({'t': 'useCard'})));
          }
          if (m.tradesLeft > 0) btns.add(_btn('交易', onTrade, icon: Icons.swap_horiz));
        }
      case 'buy':
        if (m.myTurn) {
          final s = mBoard[m.buySq.clamp(0, 39)];
          btns.add(_btn('购买 ¥${s.price}', me!.cash >= s.price ? () => act({'t': 'buy'}) : null,
              primary: true, icon: Icons.shopping_cart));
          btns.add(_btn(m.auctionOn ? '放弃（拍卖）' : '放弃', () => act({'t': 'decline'})));
        }
      case 'auction':
        extra = _MAuction(m);
      case 'debt':
        final d = m.debt!;
        if (m.iAmDebtor) {
          final amt = _n(d['amount']);
          final liquid = _n(d['liquid']);
          extra = Text('现金 ¥${me!.cash} / 需付 ¥$amt · 可变现 ¥$liquid\n点击自己的地产抵押或拆房筹款',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface));
          btns.add(_btn('付款', me.cash >= amt ? () => act({'t': 'pay'}) : null, primary: true));
          btns.add(_btn('宣告破产', me.cash + liquid < amt || me.cash < amt ? () => _confirmBankrupt(context) : null));
        }
      case 'trade':
        final tr = m.trade!;
        extra = _tradeSummary(context, tr);
        if (_n(tr['to']) == m.me) {
          btns.add(_btn('接受', () => act({'t': 'accept'}), primary: true));
          btns.add(_btn('拒绝', () => act({'t': 'reject'})));
        }
      case 'end':
        if (m.myTurn) {
          btns.add(_btn('结束回合', () => act({'t': 'end'}), primary: true, icon: Icons.check));
          if (m.tradesLeft > 0) btns.add(_btn('交易', onTrade, icon: Icons.swap_horiz));
        }
    }

    final dice = m.dice;
    final card = m.card;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (dice.length == 2 && dice[0] > 0) ...[
          DieFace(dice[0], size: 34),
          const SizedBox(width: 6),
          DieFace(dice[1], size: 34),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            m.timed ? '第 ${m.round}/${m.roundLimit} 回合' : '第 ${m.round} 回合',
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.8)),
          ),
        ),
      ]),
      if (card != null && _n(card['n']) == m.rolls) ...[
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: card['deck'] == 'chance' ? const Color(0xFFFFE0B2) : const Color(0xFFD1C4E9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${card['label']}：${card['text']}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black87)),
        ),
      ],
      if (extra != null) ...[const SizedBox(height: 4), extra],
      if (btns.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 4, children: btns),
      ],
    ]);
  }

  Widget _tradeSummary(BuildContext context, Map<String, dynamic> tr) {
    final cs = Theme.of(context).colorScheme;
    final from = _n(tr['from']), to = _n(tr['to']);
    String side(List<int> sqs, int cash) {
      final parts = [for (final i in sqs) mBoard[i].name, if (cash > 0) '¥$cash'];
      return parts.isEmpty ? '无' : parts.join('、');
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: cs.secondaryContainer.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(8)),
      child: Text(
        '${m.g.name(from)} → ${m.g.name(to)}\n'
        '给出：${side(_ints(tr['give']), _n(tr['giveCash']))}\n'
        '索要：${side(_ints(tr['get']), _n(tr['getCash']))}',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer),
      ),
    );
  }

  void _confirmBankrupt(BuildContext context) {
    showDialog<void>(useRootNavigator: false, 
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('宣告破产'),
        content: const Text('确定宣告破产吗？你的全部资产将转交给债权人（或归还银行），你将出局。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                m.g.act({'t': 'bankrupt'});
              },
              child: const Text('破产')),
        ],
      ),
    );
  }
}

class _MAuction extends StatefulWidget {
  final MView m;
  const _MAuction(this.m);
  @override
  State<_MAuction> createState() => _MAuctionState();
}

class _MAuctionState extends State<_MAuction> {
  int add = 10;

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final cs = Theme.of(context).colorScheme;
    final a = m.auction!;
    final sq = _n(a['sq']).clamp(0, 39);
    final high = _n(a['high']);
    final leader = _n(a['leader']);
    final waiting = _ints(a['waiting']);
    final last = (a['last'] as Map?) ?? const {};
    final mine = waiting.contains(m.me);
    final cash = m.mine?.cash ?? 0;
    final bid = high + add;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('拍卖 ${mBoard[sq].name}（标价 ¥${mBoard[sq].price}）· 第 ${_n(a['round'])} 轮',
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface, fontSize: 13)),
      Text(leader >= 0 ? '最高价 ¥$high · ${m.g.name(leader)}' : '尚无人出价',
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
      if (last.isNotEmpty)
        Text(
          '上轮：${[for (final e in last.entries) '${m.g.name(int.tryParse('${e.key}') ?? -1)} ${_n(e.value) > 0 ? '¥${e.value}' : '放弃'}'].join('，')}',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)),
        ),
      Wrap(spacing: 4, children: [
        for (final s in waiting)
          Row(mainAxisSize: MainAxisSize.min, children: [
            MToken(s, size: 12),
            Text(' 待出价 ', style: TextStyle(fontSize: 11, color: cs.onSurface)),
          ]),
        if (a['myBid'] != null)
          Text('你已出价 ¥${a['myBid']}', style: TextStyle(fontSize: 11, color: cs.onSurface)),
      ]),
      if (mine) ...[
        const SizedBox(height: 4),
        Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
          for (final d in const [10, 50, 100])
            ChoiceChip(
              label: Text('+$d'),
              selected: add == d,
              onSelected: (_) => setState(() => add = d),
              visualDensity: VisualDensity.compact,
            ),
          FilledButton(
            onPressed: bid <= cash ? () => m.g.act({'t': 'bid', 'amount': bid}) : null,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            child: Text('出价 ¥$bid'),
          ),
          OutlinedButton(
            onPressed: () => m.g.act({'t': 'pass'}),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            child: const Text('放弃'),
          ),
        ]),
      ],
    ]);
  }
}

/// Trade composer dialog. Returns the action map or null.
Future<void> showTradeDialog(BuildContext context, MView m) async {
  final res = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TradeDialog(m));
  if (res != null) m.g.act(res);
}

class _TradeDialog extends StatefulWidget {
  final MView m;
  const _TradeDialog(this.m);
  @override
  State<_TradeDialog> createState() => _TradeDialogState();
}

class _TradeDialogState extends State<_TradeDialog> {
  late int to;
  final give = <int>{}, get = <int>{};
  int giveCash = 0, getCash = 0;

  MView get m => widget.m;
  List<int> get others => [
        for (var s = 0; s < m.players.length; s++)
          if (s != m.me && !m.players[s].bankrupt) s
      ];

  @override
  void initState() {
    super.initState();
    to = others.isEmpty ? -1 : others.first;
  }

  bool _tradable(int i) {
    final gr = mBoard[i].group;
    return gr < 0 || !mGroups[gr].any((k) => m.houses[k] > 0);
  }

  Widget _props(int seat, Set<int> sel) {
    final owner = m.owner;
    final list = [for (var i = 0; i < 40; i++) if (owner[i] == seat && _tradable(i)) i];
    if (list.isEmpty) return const Text('（无可交易地产）', style: TextStyle(fontSize: 12));
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final i in list)
        FilterChip(
          label: Text('${mBoard[i].name}${m.mortgaged[i] ? '(押)' : ''}', style: const TextStyle(fontSize: 12)),
          avatar: mBoard[i].group >= 0
              ? CircleAvatar(backgroundColor: mGroupColors[mBoard[i].group], radius: 6)
              : null,
          selected: sel.contains(i),
          visualDensity: VisualDensity.compact,
          onSelected: (v) => setState(() => v ? sel.add(i) : sel.remove(i)),
        ),
    ]);
  }

  Widget _cash(String label, int value, int maxV, ValueChanged<int> f) {
    final mx = maxV <= 0 ? 0 : (maxV ~/ 10) * 10;
    return Row(children: [
      SizedBox(width: 92, child: Text('$label ¥$value', style: const TextStyle(fontSize: 12))),
      Expanded(
        child: mx <= 0
            ? const SizedBox()
            : Slider(
                value: value.clamp(0, mx).toDouble(),
                max: mx.toDouble(),
                divisions: (mx ~/ 10).clamp(1, 500),
                onChanged: (v) => setState(() => f(v.round())),
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final valid = to >= 0 && (give.isNotEmpty || get.isNotEmpty);
    return AlertDialog(
      title: const Text('发起交易'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, children: [
              for (final s in others)
                ChoiceChip(
                  avatar: MToken(s, size: 14),
                  label: Text(m.g.name(s)),
                  selected: to == s,
                  onSelected: (_) => setState(() {
                    to = s;
                    get.clear();
                    getCash = 0;
                  }),
                ),
            ]),
            const Divider(),
            const Text('我给出', style: TextStyle(fontWeight: FontWeight.bold)),
            _props(m.me, give),
            _cash('现金', giveCash, m.mine?.cash ?? 0, (v) => giveCash = v),
            const Divider(),
            const Text('我索要', style: TextStyle(fontWeight: FontWeight.bold)),
            if (to >= 0) _props(to, get),
            if (to >= 0) _cash('现金', getCash, m.players[to].cash, (v) => getCash = v),
            Text('交易须至少包含一处地产；有房屋的色组需先拆房。本回合还可发起 ${m.tradesLeft} 次。',
                style: const TextStyle(fontSize: 11)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, {
                    't': 'trade',
                    'to': to,
                    'give': give.toList(),
                    'get': get.toList(),
                    'giveCash': giveCash,
                    'getCash': getCash,
                  })
              : null,
          child: const Text('发出'),
        ),
      ],
    );
  }
}
