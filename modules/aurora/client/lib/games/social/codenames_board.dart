import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _teamNames = ['红队', '蓝队'];
const _teamColors = [Color(0xFFD32F2F), Color(0xFF1976D2)];
const _bystander = Color(0xFFD7C9A7);
const _assassin = Color(0xFF212121);

List<int> _ints(Object? v) => v is List ? [for (final e in v) (e as num).toInt()] : <int>[];

class CodenamesBoard extends StatefulWidget {
  final GameContext g;
  const CodenamesBoard(this.g, {super.key});
  @override
  State<CodenamesBoard> createState() => _CodenamesBoardState();
}

class _CodenamesBoardState extends State<CodenamesBoard> {
  final _clue = TextEditingController();
  int _num = 1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    _clue.dispose();
    super.dispose();
  }

  Color _keyColor(int k) => switch (k) { 0 => _teamColors[0], 1 => _teamColors[1], 2 => _bystander, 3 => _assassin, _ => Colors.transparent };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final words = (v['words'] as List).cast<String>();
    final revealed = (v['revealed'] as List).cast<bool>();
    final key = _ints(v['key']);
    final teams = _ints(v['teams']);
    final spies = _ints(v['spymasters']);
    final team = v['team'] as int;
    final phase = v['phase'] as String;
    final remaining = _ints(v['remaining']);
    final me = g.seat;
    final mySpy = v['mySpy'] == true;
    final myTeam = me >= 0 ? teams[me] : -1;
    final canGuess = !g.over && phase == 'guess' && myTeam == team && !mySpy;
    final canClue = !g.over && phase == 'clue' && me >= 0 && spies[team] == me;
    final lastCard = v['lastCard'] as int;

    String status;
    if (phase == 'over') {
      status = '${_teamNames[v['winner'] as int]}获胜！${v['reason']}';
    } else if (phase == 'clue') {
      status = canClue ? '你是${_teamNames[team]}队长：请给出提示（一个词 + 数字）' : '等待${_teamNames[team]}队长 ${g.name(spies[team])} 给出提示';
    } else {
      status = canGuess
          ? '提示「${v['clue']} ${v['clueNum']}」：点击卡片猜词（剩余 ${v['guessesLeft']} 次）'
          : '${_teamNames[team]}正在根据「${v['clue']} ${v['clueNum']}」猜词';
    }

    Widget teamPanel(int t) {
      final members = [for (var s = 0; s < g.players; s++) if (teams[s] == t) s];
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _teamColors[t].withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _teamColors[t], width: team == t && phase != 'over' ? 3 : 1),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${_teamNames[t]} 剩余 ${remaining[t]}', style: TextStyle(fontWeight: FontWeight.bold, color: _teamColors[t], fontSize: 16)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, alignment: WrapAlignment.center, children: [
            for (final s in members)
              g.tag(s,
                  size: 26,
                  active: phase != 'over' && team == t && (phase == 'clue' ? spies[t] == s : spies[t] != s),
                  sub: spies[t] == s ? '队长' : '队员'),
          ]),
        ]),
      );
    }

    Widget card(int i, double w, double h) {
      final k = key[i];
      final open = revealed[i];
      final showColor = open || (k >= 0);
      final base = open ? _keyColor(k) : Colors.white;
      final tint = !open && showColor ? _keyColor(k) : null;
      final textColor = open ? (k == 2 ? Colors.black87 : Colors.white) : Colors.black87;
      return Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: base,
          elevation: open ? 0 : 3,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: canGuess && !open
                ? () => g.act({'type': 'guess', 'card': i})
                : null,
            child: Container(
              width: w,
              height: h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: i == lastCard ? Colors.amber : (tint ?? Colors.black26),
                    width: i == lastCard ? 3 : (tint != null ? 4 : 1)),
                color: tint?.withValues(alpha: 0.18),
              ),
              child: Stack(alignment: Alignment.center, children: [
                if (open && k == 3) const Icon(Icons.dangerous, color: Colors.white24, size: 36),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(words[i],
                        style: TextStyle(
                            fontSize: h * 0.32,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            decoration: open && mySpy ? TextDecoration.lineThrough : null)),
                  ),
                ),
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
          width: 160,
          child: TextField(
            controller: _clue,
            decoration: const InputDecoration(labelText: '提示词', isDense: true, border: OutlineInputBorder()),
            maxLength: 12,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
        ),
        DropdownButton<int>(
          value: _num,
          items: [for (var n = 1; n <= 9; n++) DropdownMenuItem(value: n, child: Text('$n'))],
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
    if (canGuess && (v['guessesMade'] as int) > 0) {
      controls.add(OutlinedButton.icon(onPressed: () => g.act({'type': 'pass'}), icon: const Icon(Icons.stop_circle), label: const Text('结束猜词')));
    }

    final clues = (v['clues'] as List).cast<Map>();

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 900;
      final grid = LayoutBuilder(builder: (context, gc) {
        final w = (gc.maxWidth / 5 - 6).clamp(40.0, 160.0);
        final h = ((gc.maxHeight / 5) - 6).clamp(30.0, w * 0.62);
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var r = 0; r < 5; r++)
              Row(mainAxisSize: MainAxisSize.min, children: [for (var col = 0; col < 5; col++) card(r * 5 + col, w, h)]),
          ]),
        );
      });
      final clueLog = Card(
        color: cs.surface.withValues(alpha: 0.8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('提示记录', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final cl in clues.reversed.take(12))
              Text('${_teamNames[cl['team'] as int]}：${cl['word']} ${cl['num']}',
                  style: TextStyle(color: _teamColors[cl['team'] as int], fontWeight: FontWeight.bold)),
          ]),
        ),
      );
      final top = [
        const SizedBox(height: 6),
        StatusBar(status, highlight: canClue || canGuess),
        if (mySpy && phase != 'over') const Text('你是队长：带颜色边框的是答案，只有队长能看到', style: TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
      ];
      if (wide) {
        return Row(children: [
          SizedBox(width: 200, child: SingleChildScrollView(padding: const EdgeInsets.all(6), child: teamPanel(0))),
          Expanded(
            child: Column(children: [
              ...top,
              Expanded(child: grid),
              ...controls.map((w) => Padding(padding: const EdgeInsets.all(4), child: w)),
              if (phase == 'over') ResultBanner(status),
            ]),
          ),
          SizedBox(
            width: 200,
            child: ListView(padding: const EdgeInsets.all(6), children: [teamPanel(1), const SizedBox(height: 8), clueLog]),
          ),
        ]);
      }
      return Column(children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: teamPanel(0)),
            const SizedBox(width: 4),
            Expanded(child: teamPanel(1)),
          ]),
        ),
        ...top,
        Expanded(child: grid),
        ...controls.map((w) => Padding(padding: const EdgeInsets.all(4), child: w)),
        if (phase == 'over') ResultBanner(status),
      ]);
    });
  }
}
