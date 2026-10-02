import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p3_common.dart';

class JustOneBoard extends StatefulWidget {
  final GameContext g;
  const JustOneBoard(this.g, {super.key});
  @override
  State<JustOneBoard> createState() => _JustOneBoardState();
}

class _JustOneBoardState extends State<JustOneBoard> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final Set<int> _cancel = {};
  int _cardSeen = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = p3Str(v['phase']);
    final guesser = p3Int(v['guesser'], 0);
    final me = g.seat;
    final isGuesser = me == guesser;
    final isWriter = me >= 0 && !isGuesser;
    final card = p3Int(v['card'], 0);
    if (card != _cardSeen) {
      _cardSeen = card;
      _cancel.clear();
    }
    final submitted = p3Ints(v['submitted']).toSet();
    final confirmed = p3Ints(v['confirmed']).toSet();
    final clues = p3Maps(v['clues']);
    final result = p3Map(v['result']);
    final word = v['word'] as String?;

    String status;
    var hl = false;
    switch (phase) {
      case 'clue':
        if (isGuesser) {
          status = '你是猜词者：等待队友写提示（${submitted.length}/${g.players - 1}）';
        } else if (isWriter) {
          hl = !submitted.contains(me);
          status = hl ? '写一个提示词帮 ${g.name(guesser)} 猜词' : '已提交，等待其他人（${submitted.length}/${g.players - 1}）';
        } else {
          status = '${g.name(guesser)} 猜词中，其他人写提示';
        }
      case 'review':
        hl = isWriter && !confirmed.contains(me);
        status = isGuesser ? '队友正在审核提示…' : (hl ? '审核提示：点选要作废的提示，然后确认' : '等待其他人确认…');
      case 'guess':
        hl = isGuesser;
        status = isGuesser ? '根据有效提示猜词！' : '等待 ${g.name(guesser)} 猜词…';
      case 'result':
        status = '第 $card 张结果';
      default:
        status = '游戏结束';
    }

    Widget wordCard() {
      final cat = v['cat'] as String?;
      final show = word ?? (phase == 'result' || phase == 'over' ? (result?['word'] as String?) : null);
      return P3Panel(
        border: cs.primary,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            P3Chip('第 $card / ${v['totalCards']} 张', cs.primary, fg: cs.onPrimary),
            const SizedBox(width: 6),
            P3Chip('已猜中 ${v['success']}', Colors.green.shade700),
            const SizedBox(width: 6),
            P3Chip('牌堆 ${v['deck']}', Colors.blueGrey),
          ]),
          const SizedBox(height: 8),
          if (cat != null) Text('类别：$cat', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              show ?? (isGuesser ? '？？？' : '···'),
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: show != null ? cs.primary : cs.onSurface.withValues(alpha: 0.5), letterSpacing: 4),
            ),
          ),
          if (isGuesser && phase != 'result' && phase != 'over')
            Text('你看不到神秘词', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
        ]),
      );
    }

    Widget clueTile(Map<String, dynamic> c, {bool selectable = false}) {
      final id = p3Int(c['id']);
      final auto = c['auto'] == true;
      final cancelled = c['cancelled'] == true;
      final sel = _cancel.contains(id);
      final votes = p3Ints(c['votes']).length;
      final bg = auto || cancelled ? Colors.red.shade300 : (sel ? Colors.orange.shade300 : cs.secondaryContainer);
      return GestureDetector(
        onTap: selectable && !auto ? () => setState(() => sel ? _cancel.remove(id) : _cancel.add(id)) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? Colors.deepOrange : Colors.transparent, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26, offset: Offset(0, 1))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${c['t']}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cs.onSecondaryContainer,
                  decoration: auto || cancelled ? TextDecoration.lineThrough : null,
                )),
            Text(
              auto ? '重复·作废' : (cancelled ? '投票作废' : '${g.name(p3Int(c['s']))}${votes > 0 ? ' · $votes 票作废' : ''}'),
              style: TextStyle(fontSize: 10, color: cs.onSecondaryContainer.withValues(alpha: 0.75)),
            ),
          ]),
        ),
      );
    }

    Widget cluesArea() {
      if (phase == 'clue') {
        return Wrap(alignment: WrapAlignment.center, children: [
          for (var s = 0; s < g.players; s++)
            if (s != guesser)
              Container(
                margin: const EdgeInsets.all(3),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: submitted.contains(s) ? Colors.green.shade400 : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(submitted.contains(s) ? '${g.name(s)} ✓' : '${g.name(s)} ✎', style: const TextStyle(fontSize: 12)),
              ),
        ]);
      }
      final list = phase == 'result' || phase == 'over' ? p3Maps(result?['clues']) : clues;
      if (list.isEmpty) {
        return Text(phase == 'review' && isGuesser ? '（提示审核中，你暂时看不到）' : '没有有效提示', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)));
      }
      return Wrap(alignment: WrapAlignment.center, children: [
        for (final c in list) clueTile(c, selectable: phase == 'review' && isWriter && !confirmed.contains(me)),
      ]);
    }

    Widget main() => P3Panel(
          child: SingleChildScrollView(
            child: Column(children: [
              wordCard(),
              const SizedBox(height: 10),
              cluesArea(),
              if (phase == 'guess' && isGuesser && p3Int(v['cancelledCount'], 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('另有 ${v['cancelledCount']} 条提示被作废', style: TextStyle(fontSize: 12, color: cs.error)),
                ),
            ]),
          ),
        );

    Widget controls() {
      if (me < 0) return const SizedBox.shrink();
      switch (phase) {
        case 'clue':
          if (!isWriter) return const SizedBox.shrink();
          if (submitted.contains(me)) {
            final mine = (v['myClues'] as List?)?.join('、') ?? '';
            return Text('你的提示：$mine', style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold));
          }
          final two = p3Int(v['cluesPer'], 1) == 2;
          InputDecoration dec(String h) => InputDecoration(
                hintText: h,
                isDense: true,
                counterText: '',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              );
          void send() {
            final texts = [_c1.text.trim(), if (two) _c2.text.trim()];
            if (texts.any((t) => t.isEmpty)) return;
            g.act({'type': 'clue', 'texts': texts});
            _c1.clear();
            _c2.clear();
          }

          return Row(children: [
            Expanded(child: TextField(controller: _c1, maxLength: 8, decoration: dec(two ? '提示 1' : '一个词的提示'), onSubmitted: (_) => two ? null : send())),
            if (two) ...[const SizedBox(width: 6), Expanded(child: TextField(controller: _c2, maxLength: 8, decoration: dec('提示 2'), onSubmitted: (_) => send()))],
            const SizedBox(width: 6),
            FilledButton(onPressed: send, child: const Text('提交')),
            if (submitted.isEmpty && p3Int(v['skipsLeft'], 0) > 0) ...[
              const SizedBox(width: 4),
              IconButton(tooltip: '换词（剩 ${v['skipsLeft']}）', onPressed: () => g.act({'type': 'skipWord'}), icon: const Icon(Icons.refresh)),
            ],
          ]);
        case 'review':
          if (!isWriter || confirmed.contains(me)) return const SizedBox.shrink();
          return FilledButton.icon(
            onPressed: () => g.act({'type': 'confirm', 'cancel': _cancel.toList()}),
            icon: const Icon(Icons.check),
            label: Text(_cancel.isEmpty ? '确认（不作废）' : '确认作废 ${_cancel.length} 条'),
          );
        case 'guess':
          if (!isGuesser) return const SizedBox.shrink();
          return P3Input(
            hint: '你的答案',
            button: '猜！',
            maxLength: 12,
            onSubmit: (t) => g.act({'type': 'guess', 'text': t}),
            extra: OutlinedButton(onPressed: () => g.act({'type': 'pass'}), child: const Text('放弃')),
          );
      }
      return const SizedBox.shrink();
    }

    final hist = [for (final h in p3Maps(v['history']).reversed) h];
    Widget feed() => p3Feed(context, '战绩', [
          for (final h in hist)
            p3FeedRow(
              context,
              lead: Text(switch (h['outcome']) { 'right' => '✅', 'pass' => '⏭', _ => '❌' }, style: const TextStyle(fontSize: 16)),
              text: '第 ${h['card']} 张 · ${h['word']}',
              sub: '${g.name(p3Int(h['guesser']))}${h['guess'] != null ? ' 猜「${h['guess']}」' : ' 放弃'}',
              tint: h['outcome'] == 'right' ? Colors.green : null,
            ),
        ], empty: '还没有结果');

    Widget? banner;
    if (phase == 'over') {
      banner = ResultBanner('猜中 ${v['success']} / ${v['totalCards']}', child: Text('${v['rating'] ?? ''}', style: const TextStyle(fontSize: 16)));
    } else if (phase == 'result' && result != null) {
      final o = result['outcome'];
      banner = ResultBanner(
        o == 'right' ? '猜对了！「${result['word']}」' : (o == 'pass' ? '放弃：答案是「${result['word']}」' : '猜错：答案是「${result['word']}」'),
        child: o == 'wrong' ? Text('${g.name(p3Int(result['guesser']))} 猜了「${result['guess']}」${result['lost'] == 2 ? '，额外失去 1 张牌' : ''}') : null,
      );
    }

    return p3Layout(
      status: P3Status(status, view: v, highlight: hl, replay: g.replay),
      players: p3Players(g,
          active: (s) => s == guesser,
          sub: (s) => s == guesser
              ? '猜词者'
              : phase == 'clue'
                  ? (submitted.contains(s) ? '已提交' : '写提示中')
                  : phase == 'review'
                      ? (confirmed.contains(s) ? '已确认' : '审核中')
                      : '提示者'),
      main: main(),
      feed: feed(),
      controls: controls(),
      banner: banner,
    );
  }
}
