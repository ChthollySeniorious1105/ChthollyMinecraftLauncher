import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p2_common.dart';

const _ansLabel = {'yes': '是', 'no': '否', 'irrelevant': '无关', 'both': '是也不是', 'close': '很接近'};
const _verdictLabel = {'right': '猜对了', 'close': '很接近', 'wrong': '不对'};
const _ansColor = {
  'yes': Color(0xFF2E7D32),
  'no': Color(0xFFC62828),
  'irrelevant': Color(0xFF616161),
  'both': Color(0xFF6A1B9A),
  'close': Color(0xFFEF6C00),
  'right': Color(0xFF2E7D32),
  'wrong': Color(0xFFC62828),
};

class TurtleSoupBoard extends StatefulWidget {
  final GameContext g;
  const TurtleSoupBoard(this.g, {super.key});
  @override
  State<TurtleSoupBoard> createState() => _TurtleSoupBoardState();
}

class _TurtleSoupBoardState extends State<TurtleSoupBoard> {
  bool _guessMode = false;
  final _title = TextEditingController();
  final _surface = TextEditingController();
  final _bottom = TextEditingController();

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    _title.dispose();
    _surface.dispose();
    _bottom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = v['phase'] as String? ?? '';
    final gm = p2Int(v['gm'], 0);
    final isGm = v['isGm'] == true;
    final story = p2Map(v['story']);
    final items = p2Maps(v['items']);
    final scores = p2Ints(v['scores']);
    final left = p2Ints(v['guessesLeft']);
    final me = g.seat;
    final asked = p2Int(v['asked'], 0), cap = p2Int(v['cap'], 0);
    final myPending = items.any((e) => e['s'] == me && e['a'] == null);
    final pending = [for (final e in items) if (e['a'] == null) e];

    String status;
    var hl = false;
    switch (phase) {
      case 'prepare':
        status = isGm ? (v['source'] == 'gm' ? '请自拟一道海龟汤' : '确认题目后开始（可换题）') : '等待主持人 ${g.name(gm)} 准备题目…';
        hl = isGm;
      case 'ask':
        if (isGm) {
          status = pending.isEmpty ? '等待玩家提问…' : '有 ${pending.length} 条待回答';
          hl = pending.isNotEmpty;
        } else {
          status = myPending ? '等待主持人回答…' : '提问或猜汤底（已问 $asked/$cap）';
          hl = !myPending && me >= 0;
        }
      case 'reveal':
        status = '汤底揭晓！';
      default:
        status = '游戏结束';
    }

    Widget storyPanel() {
      if (story == null) {
        return P2Panel(child: Center(child: Text('题目准备中…', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))));
      }
      final bottom = story['bottom'] as String?;
      return P2Panel(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.soup_kitchen, size: 18),
              const SizedBox(width: 4),
              Expanded(
                child: Text('《${story['title']}》  第 ${v['round']}/${v['totalRounds']} 题',
                    style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('汤面：${story['surface']}', style: const TextStyle(fontSize: 15, height: 1.4)),
            if (bottom != null) ...[
              const Divider(height: 12),
              Text(phase == 'reveal' || phase == 'over' ? '汤底：$bottom' : '汤底（仅主持人可见）：$bottom',
                  style: TextStyle(fontSize: 13, height: 1.4, color: cs.tertiary)),
            ],
          ]),
        ),
      );
    }

    Widget itemTile(Map<String, dynamic> e) {
      final s = p2Int(e['s']);
      final isQ = e['k'] == 'q';
      final a = e['a'] as String?;
      final label = a == null ? null : (isQ ? _ansLabel[a] : _verdictLabel[a]);
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isQ ? cs.surfaceContainerHighest.withValues(alpha: 0.55) : cs.tertiaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            P2Chip(isQ ? '问' : '猜', isQ ? cs.primary : cs.tertiary, fg: isQ ? cs.onPrimary : cs.onTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '${g.name(s)}：', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                TextSpan(text: '${e['t']}', style: const TextStyle(fontSize: 13)),
              ])),
            ),
            const SizedBox(width: 4),
            if (label != null) P2Chip(label, _ansColor[a] ?? Colors.grey) else const P2Chip('待回答', Colors.blueGrey),
          ]),
          if (isGm && a == null && phase == 'ask')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 4, runSpacing: 4, children: [
                for (final en in (isQ ? _ansLabel : _verdictLabel).entries)
                  SizedBox(
                    height: 30,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _ansColor[en.key],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () => g.act({'type': 'answer', 'id': e['id'], 'answer': en.key}),
                      child: Text(en.value, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ]),
            ),
        ]),
      );
    }

    Widget feed() {
      // GM sees pending first so answering is quick
      final list = isGm ? [...pending, ...items.reversed.where((e) => e['a'] != null)] : items.reversed.toList();
      if (list.isEmpty) {
        return Center(child: Text(phase == 'ask' ? '还没有人提问' : '', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))));
      }
      return ListView(children: [for (final e in list) itemTile(e)]);
    }

    Widget controls() {
      if (me < 0) return const SizedBox.shrink();
      if (isGm) {
        switch (phase) {
          case 'prepare':
            if (v['source'] == 'gm') return _composeForm();
            return Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: p2Int(v['swapsLeft'], 0) > 0 ? () => g.act({'type': 'swap'}) : null,
                icon: const Icon(Icons.shuffle),
                label: Text('换一题（剩 ${v['swapsLeft']}）'),
              ),
              FilledButton.icon(onPressed: () => g.act({'type': 'begin'}), icon: const Icon(Icons.play_arrow), label: const Text('开始')),
            ]);
          case 'ask':
            return Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => g.act({'type': 'reveal'}),
                icon: const Icon(Icons.visibility),
                label: const Text('公布汤底'),
              ),
            );
          case 'reveal':
            return FilledButton(onPressed: () => g.act({'type': 'next'}), child: const Text('下一题 / 结算'));
        }
        return const SizedBox.shrink();
      }
      if (phase != 'ask') return const SizedBox.shrink();
      final myLeft = me < left.length ? left[me] : 0;
      final canAsk = asked < cap;
      final guess = _guessMode || !canAsk;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('提问'), selected: !guess, onSelected: canAsk ? (_) => setState(() => _guessMode = false) : null),
          const SizedBox(width: 6),
          ChoiceChip(label: Text('猜汤底（剩 $myLeft）'), selected: guess, onSelected: myLeft > 0 ? (_) => setState(() => _guessMode = true) : null),
        ]),
        const SizedBox(height: 4),
        P2Input(
          key: ValueKey(guess),
          hint: guess ? '说出你还原的完整真相…' : '问一个能用“是/否”回答的问题',
          button: guess ? '猜' : '问',
          maxLength: guess ? 150 : 60,
          enabled: !myPending && (guess ? myLeft > 0 : canAsk),
          onSubmit: (t) => g.act({'type': guess ? 'guess' : 'ask', 'text': t}),
        ),
      ]);
    }

    final rr = p2Map(v['roundResult']);
    Widget? banner;
    if (phase == 'over') {
      banner = p2Ranking(g, '游戏结束', p2Maps(v['final']), (r) => '${r['score']} 分');
    } else if (phase == 'reveal' && rr != null) {
      banner = ResultBanner('${rr['why']}');
    }

    Widget scoreRow() => SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final s in g.seatsFromMe())
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: g.tag(s, size: 26, active: s == gm, sub: s == gm ? '主持人' : '${s < scores.length ? scores[s] : 0} 分'),
              ),
          ]),
        );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.2;
      final ctl = Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 6), child: controls());
      if (wide) {
        return Column(children: [
          p2Status(status, highlight: hl),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: scoreRow()),
          Expanded(
            child: Row(children: [
              const SizedBox(width: 8),
              Expanded(
                child: Column(children: [
                  Expanded(child: SizedBox(width: double.infinity, child: storyPanel())),
                  if (banner != null) FittedBox(fit: BoxFit.scaleDown, child: banner),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(children: [Expanded(child: P2Panel(padding: const EdgeInsets.all(6), child: feed())), ctl])),
              const SizedBox(width: 8),
            ]),
          ),
        ]);
      }
      return Column(children: [
        p2Status(status, highlight: hl),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: scoreRow()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.3),
            child: SizedBox(width: double.infinity, child: storyPanel()),
          ),
        ),
        if (banner != null) FittedBox(fit: BoxFit.scaleDown, child: banner),
        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: P2Panel(padding: const EdgeInsets.all(6), child: feed()))),
        ctl,
      ]);
    });
  }

  Widget _composeForm() {
    InputDecoration dec(String h) => InputDecoration(hintText: h, isDense: true, filled: true, counterText: '', border: const OutlineInputBorder());
    return P2Panel(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, maxLength: 20, decoration: dec('标题')),
          const SizedBox(height: 4),
          TextField(controller: _surface, maxLength: 300, maxLines: 2, decoration: dec('汤面（所有人可见）')),
          const SizedBox(height: 4),
          TextField(controller: _bottom, maxLength: 800, maxLines: 2, decoration: dec('汤底（只有你可见）')),
          const SizedBox(height: 4),
          FilledButton(
            onPressed: () => g.act({'type': 'compose', 'title': _title.text, 'surface': _surface.text, 'bottom': _bottom.text}),
            child: const Text('出题并开始'),
          ),
        ]),
      ),
    );
  }
}
