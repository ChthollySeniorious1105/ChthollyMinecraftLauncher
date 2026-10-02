import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'p2_common.dart';

const _teamNames = ['红队', '蓝队'];
const _teamColors = [Color(0xFFD32F2F), Color(0xFF1976D2)];

class DecryptoBoard extends StatefulWidget {
  final GameContext g;
  const DecryptoBoard(this.g, {super.key});
  @override
  State<DecryptoBoard> createState() => _DecryptoBoardState();
}

class _DecryptoBoardState extends State<DecryptoBoard> {
  final _clues = [TextEditingController(), TextEditingController(), TextEditingController()];
  final _tb = [TextEditingController(), TextEditingController(), TextEditingController(), TextEditingController()];
  List<int> _code = [];
  int _tab = 0;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    for (final c in [..._clues, ..._tb]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String>? _strs(Object? o) => o is List ? [for (final e in o) '$e'] : null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = v['phase'] as String? ?? '';
    final t = p2Int(v['team']);
    final me = g.seat;
    final round = p2Int(v['round'], 1);
    final enc = p2Ints(v['encryptor']);
    final keywords = v['keywords'] as List? ?? const [null, null];
    final myKeys = t >= 0 ? _strs(keywords[t]) : null;
    final myCode = p2Ints(v['myCode']);
    final clues = v['clues'] as List? ?? const [null, null];
    final ints = p2Ints(v['ints']), miss = p2Ints(v['miss']);
    final clueDone = p2Bools(v['clueDone']);
    final ownDone = p2Bools(v['ownDone']), icptDone = p2Bools(v['icptDone']);
    final history = p2Maps(v['history']);
    final isEnc = t >= 0 && enc.length > t && enc[t] == me;

    String status;
    var hl = false;
    switch (phase) {
      case 'clue':
        if (isEnc && t < clueDone.length && !clueDone[t]) {
          status = '你是本轮加密者：为密码 ${myCode.join('-')} 写 3 条线索';
          hl = true;
        } else {
          status = '第 $round 轮：等待加密者给出线索…';
        }
      case 'guess':
        if (t >= 0 && !isEnc && (!ownDone[t] || (round >= 2 && !icptDone[t]))) {
          status = round >= 2 ? '破译本队密码，并尝试拦截对方！' : '根据线索破译本队密码';
          hl = true;
        } else {
          status = '等待各队提交…';
        }
      case 'result':
        status = '第 $round 轮结算';
      case 'tiebreak':
        status = '决胜：猜出对方的 4 个关键词';
        hl = t >= 0;
      default:
        status = '游戏结束';
    }

    Widget scoreBox(int team) => P2Panel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          border: team == t ? _teamColors[team] : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_teamNames[team] + (team == t ? '（我方）' : ''), style: TextStyle(color: _teamColors[team], fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.gps_fixed, size: 14, color: Colors.green),
              Text(' 拦截 ${team < ints.length ? ints[team] : 0}  ', style: const TextStyle(fontSize: 12)),
              const Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
              Text(' 失误 ${team < miss.length ? miss[team] : 0}', style: const TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 2),
            Wrap(spacing: 4, children: [
              for (final s in (v['teams'] as List? ?? const [])[team] as List? ?? const [])
                g.tag(p2Int(s), size: 22, active: enc.length > team && enc[team] == p2Int(s) && (phase == 'clue' || phase == 'guess')),
            ]),
          ]),
        );

    Widget keywordCards() {
      final keys = myKeys;
      return Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(3),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              decoration: BoxDecoration(
                color: t >= 0 ? _teamColors[t].withValues(alpha: 0.85) : Colors.black45,
                borderRadius: BorderRadius.circular(8),
                border: myCode.contains(i + 1) && isEnc ? Border.all(color: Colors.amberAccent, width: 3) : null,
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${i + 1}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(keys == null ? '？？' : keys[i], style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
      ]);
    }

    /// Clue sheet of [team]: per keyword position, the clues given so far.
    Widget sheet(int team) {
      final cols = [<String>[], <String>[], <String>[], <String>[]];
      for (final h in history) {
        if (p2Int(h['t']) != team) continue;
        final cl = _strs(h['clues']) ?? const [];
        final cd = p2Ints(h['code']);
        for (var i = 0; i < 3 && i < cl.length && i < cd.length; i++) {
          cols[cd[i] - 1].add('R${h['r']} ${cl[i]}');
        }
      }
      final teamKeys = _strs(keywords[team]);
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var p = 0; p < 4; p++)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: _teamColors[team].withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(teamKeys == null ? '#${p + 1}' : '#${p + 1} ${teamKeys[p]}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: _teamColors[team])),
                for (final c in cols[p]) Text(c, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ),
      ]);
    }

    Widget currentClues() {
      final rows = <Widget>[];
      for (var team = 0; team < 2; team++) {
        final c = _strs(clues[team]);
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            P2Chip(_teamNames[team], _teamColors[team]),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                c == null ? (team < clueDone.length && clueDone[team] ? '（已给出，等待对方）' : '（加密中…）') : c.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('   '),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ));
      }
      return Column(mainAxisSize: MainAxisSize.min, children: rows);
    }

    Widget codePicker(String label, String type, bool done) {
      if (done) return Text('$label：已提交', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)));
      return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
        Text('$label：'),
        for (var d = 1; d <= 4; d++)
          SizedBox(
            width: 38,
            height: 34,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: _code.length < 3 && !_code.contains(d) ? () => setState(() => _code = [..._code, d]) : null,
              child: Text('$d'),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outline)),
          child: Text(_code.isEmpty ? '_ _ _' : _code.join(' '), style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        ),
        IconButton(onPressed: () => setState(() => _code = []), icon: const Icon(Icons.backspace_outlined, size: 18)),
        FilledButton(
          onPressed: _code.length == 3
              ? () {
                  g.act({'type': type, 'code': _code});
                  setState(() => _code = []);
                }
              : null,
          child: const Text('提交'),
        ),
      ]);
    }

    Widget actions() {
      if (t < 0) return const SizedBox.shrink();
      switch (phase) {
        case 'clue':
          if (!isEnc || clueDone[t]) return const SizedBox.shrink();
          return Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: TextField(
                  controller: _clues[i],
                  maxLength: 12,
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    filled: true,
                    prefixText: '${myCode.length > i ? myCode[i] : '?'} → ',
                    hintText: '线索 ${i + 1}（提示关键词 ${myCode.length > i ? myCode[i] : '?'}）',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            FilledButton(
              onPressed: () {
                g.act({'type': 'clue', 'clues': [for (final c in _clues) c.text]});
                for (final c in _clues) {
                  c.clear();
                }
              },
              child: const Text('提交线索'),
            ),
          ]);
        case 'guess':
          if (isEnc) return const Text('你是加密者，请等待队友破译（不要提示！）');
          if (!ownDone[t]) return codePicker('本队密码', 'guess', false);
          if (round >= 2 && !icptDone[t]) return codePicker('拦截${_teamNames[1 - t]}', 'intercept', false);
          return const Text('已提交，等待对方…');
        case 'tiebreak':
          if (p2Bools(v['tbDone'])[t]) return const Text('已提交，等待对方…');
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: TextField(
                      controller: _tb[i],
                      maxLength: 8,
                      decoration: InputDecoration(isDense: true, counterText: '', filled: true, hintText: '#${i + 1}', border: const OutlineInputBorder()),
                    ),
                  ),
                ),
            ]),
            FilledButton(onPressed: () => g.act({'type': 'tiebreak', 'words': [for (final c in _tb) c.text]}), child: const Text('提交猜测')),
          ]);
      }
      return const SizedBox.shrink();
    }

    Widget? banner;
    if (phase == 'result') {
      final lr = p2Map(v['lastResult']);
      banner = ResultBanner('第 ${lr?['round'] ?? round} 轮结果', child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final r in p2Maps(lr?['teams']))
          Text(
            '${_teamNames[p2Int(r['t'], 0)]} 密码 ${p2Ints(r['code']).join()}：${r['ok'] == true ? '✓ 破译成功' : '✗ 破译失败'}'
            '${r['icpt'] == null ? '' : r['caught'] == true ? '，被拦截！' : '，拦截失败'}',
            style: const TextStyle(fontSize: 13),
          ),
      ]));
    } else if (phase == 'over') {
      final w = p2Int(v['winner']);
      banner = ResultBanner(w < 0 ? '平局' : (w == t ? '我方获胜！' : '${_teamNames[w]}获胜'), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${v['reason'] ?? ''}'),
        for (var team = 0; team < 2; team++)
          Text('${_teamNames[team]}：${(_strs(keywords[team]) ?? const []).join('、')}', style: TextStyle(color: _teamColors[team], fontWeight: FontWeight.bold)),
      ]));
    }

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > box.maxHeight * 1.2;
      final sheets = Column(children: [
        Row(children: [
          for (var team = 0; team < 2; team++)
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _tab = team),
                child: Text('${_teamNames[team]}线索表', style: TextStyle(color: _teamColors[team], fontWeight: _tab == team ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
        ]),
        Expanded(child: SingleChildScrollView(child: sheet(_tab))),
      ]);
      final main = Column(children: [
        keywordCards(),
        P2Panel(padding: const EdgeInsets.all(6), child: currentClues()),
        if (banner != null) FittedBox(fit: BoxFit.scaleDown, child: banner),
        Padding(padding: const EdgeInsets.all(6), child: actions()),
      ]);
      final scores = Row(children: [
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: scoreBox(0))),
        const SizedBox(width: 6),
        Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: scoreBox(1))),
      ]);
      if (wide) {
        return Column(children: [
          p2Status('$status  · 第 $round/${v['maxRounds']} 轮', highlight: hl),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: scores),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(width: 8),
              Expanded(flex: 5, child: SingleChildScrollView(child: main)),
              const SizedBox(width: 8),
              Expanded(flex: 4, child: P2Panel(padding: const EdgeInsets.all(4), child: sheets)),
              const SizedBox(width: 8),
            ]),
          ),
          const SizedBox(height: 6),
        ]);
      }
      return Column(children: [
        p2Status('$status  · 第 $round/${v['maxRounds']} 轮', highlight: hl),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: scores),
        Expanded(
          flex: 3,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: SingleChildScrollView(child: main)),
        ),
        Expanded(
          flex: 2,
          child: Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 6), child: P2Panel(padding: const EdgeInsets.all(4), child: sheets)),
        ),
      ]);
    });
  }
}
