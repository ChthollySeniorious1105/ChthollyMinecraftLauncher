import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p2_common.dart';

class BullsCowsBoard extends StatefulWidget {
  final GameContext g;
  const BullsCowsBoard(this.g, {super.key});
  @override
  State<BullsCowsBoard> createState() => _BullsCowsBoardState();
}

class _BullsCowsBoardState extends State<BullsCowsBoard> {
  String _buf = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  int get digits => p2Int(v['digits'], 4);
  bool get repeat => v['repeat'] == true;

  void _press(int d) {
    if (_buf.length >= digits) return;
    if (!repeat && _buf.contains('$d')) return;
    setState(() => _buf += '$d');
  }

  void _submit(String type) {
    if (_buf.length != digits) return;
    g.act({'type': type, 'code': _buf});
    setState(() => _buf = '');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = v['phase'] as String? ?? '';
    final turn = p2Int(v['turn']);
    final me = g.seat;
    final ready = p2Bools(v['ready']);
    final alive = p2Bools(v['alive']);
    final target = p2Ints(v['target']);
    final secrets = v['secrets'] as List? ?? const [];
    final history = p2Maps(v['history']);
    final mySecret = v['mySecret'] as String?;
    final winner = p2Int(v['winner']);

    final needSecret = phase == 'setup' && me >= 0 && me < ready.length && !ready[me];
    final myTurn = phase == 'play' && turn == me;
    String status;
    switch (phase) {
      case 'setup':
        status = needSecret ? '请设定你的 $digits 位密码${repeat ? '' : '（数字互不相同）'}' : '等待其他人设定密码…';
      case 'play':
        status = myTurn
            ? '轮到你猜 ${g.name(target[me])} 的密码'
            : '${g.name(turn)} 正在猜 ${g.name(turn < target.length ? target[turn] : 0)} 的密码  · 第 ${v['round']}/${v['maxRounds']} 轮';
      default:
        status = '游戏结束';
    }

    Widget players() => Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
          for (final s in g.seatsFromMe())
            Opacity(
              opacity: s < alive.length && !alive[s] ? 0.45 : 1,
              child: g.tag(
                s,
                size: 28,
                active: phase == 'play' && s == turn,
                sub: phase == 'setup'
                    ? (s < ready.length && ready[s] ? '已设定' : '设定中…')
                    : (s < secrets.length && secrets[s] is String && s != me ? '密码 ${secrets[s]}' : '→ ${g.name(s < target.length ? target[s] : 0)}'),
              ),
            ),
        ]);

    Widget historyList() {
      final items = history.reversed.toList();
      if (items.isEmpty) {
        return Center(child: Text(phase == 'setup' ? '设定完成后开始猜测' : '还没有人猜过', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))));
      }
      return ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final h = items[i];
          final s = p2Int(h['s']), t = p2Int(h['t']);
          final a = p2Int(h['a'], 0), b = p2Int(h['b'], 0);
          final mine = s == me || t == me;
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: mine ? cs.primaryContainer.withValues(alpha: 0.6) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Expanded(
                child: Text('${g.name(s)} → ${g.name(t)}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
              Text('${h['g']}', style: const TextStyle(fontFamilyFallback: kFontFallback, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(width: 8),
              P2Chip('${a}A', a == digits ? Colors.green.shade700 : Colors.teal.shade600),
              const SizedBox(width: 3),
              P2Chip('${b}B', Colors.orange.shade700),
            ]),
          );
        },
      );
    }

    Widget pad() {
      final action = needSecret ? 'secret' : 'guess';
      final enabled = needSecret || myTurn;
      final slots = Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < digits; i++)
          Container(
            width: 34,
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: i == _buf.length && enabled ? cs.primary : cs.outline, width: i == _buf.length && enabled ? 2 : 1),
            ),
            child: Text(i < _buf.length ? _buf[i] : '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
      ]);
      Widget key(String label, VoidCallback? f, {Color? color}) => Padding(
            padding: const EdgeInsets.all(2),
            child: SizedBox(
              width: 38,
              height: 36,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: color),
                onPressed: enabled ? f : null,
                child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          );
      return P2Panel(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (mySecret != null) Text('我的密码：$mySecret', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            slots,
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [for (var d = 1; d <= 5; d++) key('$d', () => _press(d))]),
            Row(mainAxisSize: MainAxisSize.min, children: [for (var d = 6; d <= 9; d++) key('$d', () => _press(d)), key('0', () => _press(0))]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              key('⌫', () => setState(() => _buf = _buf.isEmpty ? '' : _buf.substring(0, _buf.length - 1))),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: enabled && _buf.length == digits ? () => _submit(action) : null,
                child: Text(needSecret ? '确定密码' : '猜！'),
              ),
            ]),
          ]),
        ),
      );
    }

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.2;
      final result = phase == 'over'
          ? ResultBanner(
              winner == me ? '你赢了！' : '${g.name(winner)} 获胜',
              child: Text('${v['reason'] ?? ''}', textAlign: TextAlign.center),
            )
          : null;
      final showPad = me >= 0 && phase != 'over' && (me < alive.length && alive[me]);
      if (wide) {
        return Column(children: [
          p2Status(status, highlight: needSecret || myTurn),
          Expanded(
            child: Row(children: [
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(children: [
                  Padding(padding: const EdgeInsets.all(4), child: players()),
                  if (result != null) FittedBox(fit: BoxFit.scaleDown, child: result),
                  if (showPad) Expanded(child: Center(child: pad())),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: P2Panel(padding: const EdgeInsets.all(6), child: historyList())),
              const SizedBox(width: 8),
            ]),
          ),
          const SizedBox(height: 8),
        ]);
      }
      return Column(children: [
        p2Status(status, highlight: needSecret || myTurn),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: players()),
        if (result != null) FittedBox(fit: BoxFit.scaleDown, child: result),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: P2Panel(padding: const EdgeInsets.all(6), child: historyList()),
          ),
        ),
        if (showPad) SizedBox(height: box.maxHeight * 0.34, child: Center(child: pad())),
        const SizedBox(height: 6),
      ]);
    });
  }
}
