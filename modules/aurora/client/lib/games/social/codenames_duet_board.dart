import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _sideNames = ['A 方', 'B 方'];
const _sideColors = [Color(0xFF00897B), Color(0xFF8E24AA)];
const _agent = Color(0xFF2E7D32);
const _bystander = Color(0xFFD7C9A7);
const _assassin = Color(0xFF212121);

List<int> _ints(Object? v) => v is List ? [for (final e in v) (e as num).toInt()] : <int>[];
List<bool> _bools(Object? v) => v is List ? [for (final e in v) e == true] : List.filled(25, false);

String _numText(int n) => n < 0 ? '∞' : '$n';

class CodenamesDuetBoard extends StatefulWidget {
  final GameContext g;
  const CodenamesDuetBoard(this.g, {super.key});
  @override
  State<CodenamesDuetBoard> createState() => _CodenamesDuetBoardState();
}

class _CodenamesDuetBoardState extends State<CodenamesDuetBoard> {
  final _clue = TextEditingController();
  int _num = 1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    _clue.dispose();
    super.dispose();
  }

  Color _keyColor(int k) => switch (k) { 0 => _agent, 1 => _bystander, 2 => _assassin, _ => Colors.transparent };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final words = (v['words'] as List).cast<String>();
    final found = _bools(v['found']);
    final byMarks = [_bools(v['byA']), _bools(v['byB'])];
    final sides = _ints(v['sides']);
    final mySide = (v['mySide'] as num?)?.toInt() ?? -1;
    final myKey = v['myKey'] == null ? null : _ints(v['myKey']);
    final allKeys = v['keys'] is List ? [for (final k in v['keys'] as List) _ints(k)] : null;
    final giver = v['giver'] as int;
    final phase = v['phase'] as String;
    final tokens = v['tokens'] as int;
    final maxTokens = v['maxTokens'] as int;
    final foundCount = v['foundCount'] as int;
    final total = v['totalAgents'] as int;
    final remaining = _ints(v['remaining']);
    final waiting = _ints(v['waiting']);
    final lastCard = v['lastCard'] as int;
    final lossCard = v['lossCard'] as int;
    final clue = v['clue'] as String;
    final clueNum = v['clueNum'] as int;
    final guesses = v['guesses'] as int;
    final me = g.seat;
    final over = g.over || phase == 'over';
    final myTurn = !over && me >= 0 && waiting.contains(me);
    final canClue = myTurn && phase == 'clue';
    final canGuess = myTurn && (phase == 'guess' || phase == 'sudden');

    String status;
    if (over) {
      status = v['won'] == true ? '任务成功！${v['reason']}' : '任务失败：${v['reason']}';
    } else if (phase == 'clue') {
      status = canClue ? '轮到你（${_sideNames[giver]}）给提示：一个词 + 数字' : '等待${_sideNames[giver]}给出提示';
    } else if (phase == 'guess') {
      final c = '「$clue ${_numText(clueNum)}」';
      status = canGuess ? '提示$c：点击卡片猜测（已猜 $guesses）' : '${_sideNames[1 - giver]}正在根据$c猜测';
    } else {
      status = canGuess ? '突然死亡：直接点对方钥匙卡上的特工，猜错即失败' : '突然死亡：等待其他玩家猜测';
    }

    Widget sidePanel(int s) {
      final members = [for (var p = 0; p < g.players; p++) if (p < sides.length && sides[p] == s) p];
      final active = !over && (phase == 'clue' ? giver == s : phase == 'guess' ? giver != s : true);
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _sideColors[s].withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _sideColors[s], width: active ? 3 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('${_sideNames[s]}${s == mySide ? '（我方）' : ''} 钥匙卡剩余 ${remaining[s]}',
                style: TextStyle(fontWeight: FontWeight.bold, color: _sideColors[s], fontSize: 14)),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (final p in members)
              g.tag(p,
                  size: 24,
                  active: active && waiting.contains(p),
                  sub: phase == 'clue' && giver == s ? '提示者' : (phase == 'guess' && giver != s ? '猜词' : '')),
          ]),
        ]),
      );
    }

    Widget counters() {
      return Wrap(spacing: 10, runSpacing: 4, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.person_search, size: 18, color: _agent),
          label: Text('特工 $foundCount / $total'),
        ),
        Chip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.hourglass_bottom, size: 18),
          label: Text(phase == 'sudden' || (tokens == 0 && !over) ? '突然死亡' : '计时 $tokens / $maxTokens'),
        ),
      ]);
    }

    Widget halfMarker(int s, bool left) => Positioned(
          left: left ? 2 : null,
          right: left ? null : 2,
          bottom: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: _bystander, borderRadius: BorderRadius.circular(4), border: Border.all(color: _sideColors[s], width: 1.5)),
            child: Text(s == 0 ? 'A路人' : 'B路人', style: const TextStyle(fontSize: 8, color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        );

    Widget card(int i, double w, double h) {
      final open = found[i];
      final k = myKey != null ? myKey[i] : -1;
      final marked = byMarks[mySide < 0 ? 0 : mySide][i];
      final tappable = canGuess && !open && !marked;
      Color base = open ? _agent : Colors.white;
      final lostHere = over && i == lossCard;
      if (lostHere) base = _assassin;
      final border = i == lastCard ? Colors.amber : (k >= 0 && !open ? _keyColor(k) : Colors.black26);
      // game over: show both keys as small corner dots
      Widget? endKeys;
      if (over && allKeys != null && !open) {
        endKeys = Positioned(
          top: 2,
          right: 2,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var s = 0; s < 2; s++)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(color: _keyColor(allKeys[s][i]), shape: BoxShape.circle, border: Border.all(color: _sideColors[s], width: 1)),
              ),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: base,
          elevation: open ? 0 : 3,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: tappable ? () => g.act({'type': 'guess', 'card': i}) : null,
            child: Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: border, width: i == lastCard ? 3 : (k >= 0 && !open ? 4 : 1)),
                color: !open && k >= 0 ? _keyColor(k).withValues(alpha: 0.16) : null,
              ),
              child: Stack(alignment: Alignment.center, children: [
                if (open) const Icon(Icons.verified_user, color: Colors.white24, size: 30),
                if (lostHere) const Icon(Icons.dangerous, color: Colors.white24, size: 34),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(words[i],
                        style: TextStyle(
                          fontSize: h * 0.3,
                          fontWeight: FontWeight.bold,
                          color: open || lostHere ? Colors.white : (marked ? Colors.black38 : Colors.black87),
                        )),
                  ),
                ),
                if (!open && k == 2)
                  const Positioned(top: 2, left: 2, child: Icon(Icons.dangerous, size: 12, color: _assassin)),
                if (!open && k == 0)
                  const Positioned(top: 2, left: 2, child: Icon(Icons.person, size: 12, color: _agent)),
                if (!open && byMarks[0][i]) halfMarker(0, true),
                if (!open && byMarks[1][i]) halfMarker(1, false),
                ?endKeys,
              ]),
            ),
          ),
        ),
      );
    }

    final controls = <Widget>[];
    if (canClue) {
      controls.add(Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 150,
          child: TextField(
            controller: _clue,
            decoration: const InputDecoration(labelText: '提示词', isDense: true, border: OutlineInputBorder()),
            maxLength: 12,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
        ),
        DropdownButton<int>(
          value: _num,
          items: [
            for (var n = 1; n <= 9; n++) DropdownMenuItem(value: n, child: Text('$n')),
            const DropdownMenuItem(value: 0, child: Text('0')),
            const DropdownMenuItem(value: -1, child: Text('∞')),
          ],
          onChanged: (x) => setState(() => _num = x ?? 1),
        ),
        FilledButton.icon(
          onPressed: () {
            final w = _clue.text.trim();
            if (w.isEmpty) return;
            g.act({'type': 'clue', 'word': w, 'num': _num});
            _clue.clear();
          },
          icon: const Icon(Icons.send),
          label: const Text('给出提示'),
        ),
      ]));
    }
    if (canGuess && phase == 'guess' && guesses > 0) {
      controls.add(OutlinedButton.icon(
          onPressed: () => g.act({'type': 'pass'}), icon: const Icon(Icons.stop_circle), label: const Text('停止猜测')));
    }

    final clues = (v['clues'] as List).cast<Map>();
    Widget clueLog() => Card(
          color: cs.surface.withValues(alpha: 0.85),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('提示记录', style: TextStyle(fontWeight: FontWeight.bold)),
              if (clues.isEmpty) const Text('暂无', style: TextStyle(fontSize: 12)),
              for (final cl in clues.reversed.take(14))
                Text('${_sideNames[cl['side'] as int]}：${cl['word']} ${_numText(cl['num'] as int)}（中 ${cl['hits']}）',
                    style: TextStyle(color: _sideColors[cl['side'] as int], fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ),
        );

    final keyHint = myKey != null && !over
        ? const Text('彩色边框为你的钥匙卡：绿=特工 黑=刺客 米色=路人（提示给对方用）', style: TextStyle(fontSize: 11), textAlign: TextAlign.center)
        : null;

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 900;
      final landscape = !wide && c.maxWidth > c.maxHeight;
      final grid = LayoutBuilder(builder: (context, gc) {
        final w = (gc.maxWidth / 5 - 6).clamp(20.0, 160.0);
        final h = ((gc.maxHeight / 5) - 6).clamp(14.0, w * 0.62);
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var r = 0; r < 5; r++)
              Row(mainAxisSize: MainAxisSize.min, children: [for (var col = 0; col < 5; col++) card(r * 5 + col, w, h)]),
          ]),
        );
      });
      final center = Column(children: [
        const SizedBox(height: 4),
        StatusBar(status, highlight: canClue || canGuess),
        ?keyHint,
        Expanded(child: grid),
        ...controls.map((w) => Padding(padding: const EdgeInsets.all(3), child: w)),
        if (over) ResultBanner(status),
      ]);
      if (wide || landscape) {
        final sideW = wide ? 220.0 : 200.0;
        return Row(children: [
          SizedBox(
            width: sideW,
            child: ListView(padding: const EdgeInsets.all(6), children: [
              counters(),
              const SizedBox(height: 6),
              sidePanel(0),
              const SizedBox(height: 6),
              sidePanel(1),
              if (!wide) ...[const SizedBox(height: 6), clueLog()],
            ]),
          ),
          Expanded(child: center),
          if (wide) SizedBox(width: 200, child: ListView(padding: const EdgeInsets.all(6), children: [clueLog()])),
        ]);
      }
      final lastClue = clues.isEmpty ? null : clues.last;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: sidePanel(0)),
            const SizedBox(width: 4),
            Expanded(child: sidePanel(1)),
          ]),
        ),
        counters(),
        if (lastClue != null)
          Text('上一条提示：${_sideNames[lastClue['side'] as int]} ${lastClue['word']} ${_numText(lastClue['num'] as int)}（共 ${clues.length} 条）',
              style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        Expanded(child: center),
      ]);
    });
  }
}
