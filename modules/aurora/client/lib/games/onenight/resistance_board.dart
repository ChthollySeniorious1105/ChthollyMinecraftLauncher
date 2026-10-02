import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'on_common.dart';

const _plotNames = {'overheard': '窃听', 'openup': '坦白', 'confidence': '建立信任'};
const _plotDesc = {
  'overheard': '队长把此卡交给一名其他玩家，该玩家秘密查看相邻一名玩家的身份',
  'openup': '队长把此卡交给一名其他玩家，该玩家向任意一名玩家秘密公开自己的身份',
  'confidence': '队长必须向一名其他玩家秘密公开自己的身份',
};

class ResistanceBoard extends StatefulWidget {
  final GameContext g;
  const ResistanceBoard(this.g, {super.key});
  @override
  State<ResistanceBoard> createState() => _ResistanceBoardState();
}

class _ResistanceBoardState extends State<ResistanceBoard> {
  final Set<int> sel = {};
  bool hide = false;
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  String get phase => v['phase'] as String? ?? '';
  bool get me => g.seat >= 0;
  int get leader => onInt(v['leader'], 0);
  int get mission => onInt(v['mission'], 0);
  List<int> get sizes => onInts(v['sizes']);
  int get teamSize => mission < sizes.length ? sizes[mission] : 0;
  List<int> get team => onInts(v['team']);

  void _sync() {
    final k = '$phase|$mission|$leader|${v['plotStage']}|${v['rejects']}';
    if (k != _key) {
      _key = k;
      sel.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final bg = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(const Color(0x33000000), g.table), g.table],
      ),
    );
    return onLayout(bg: bg, main: [
      _banner(),
      _track(),
      _seats(),
      const SizedBox(height: 8),
      if (phase == 'over') _result(),
      _history(),
    ], side: [
      if (me) _identity(),
      if (me) _action(),
      if (v['lastVote'] != null) _lastVote(),
    ]);
  }

  bool get _myTurn {
    if (!me) return false;
    switch (phase) {
      case 'plot':
        return onInts(v['plotTargets']).isNotEmpty;
      case 'propose':
        return leader == g.seat;
      case 'vote':
        return v['myVote'] == null;
      case 'mission':
        return team.contains(g.seat) && v['myCard'] == null;
    }
    return false;
  }

  Widget _banner() {
    final title = switch (phase) {
      'plot' => '第 ${mission + 1} 次任务 · 计划卡',
      'propose' => '第 ${mission + 1} 次任务 · 组队',
      'vote' => '第 ${mission + 1} 次任务 · 投票',
      'mission' => '第 ${mission + 1} 次任务 · 执行',
      _ => v['winner'] == 'res' ? '抵抗组织获胜' : '间谍获胜',
    };
    final sub = switch (phase) {
      'plot' => '队长 ${g.name(leader)} 抽到【${_plotNames[v['plotCard']] ?? ''}】',
      'propose' => '队长 ${g.name(leader)} 正在挑选 $teamSize 名队员',
      'vote' => '全员表决是否同意这支队伍出发',
      'mission' => '队员秘密出牌：成功 / 失败',
      _ => v['reason'] as String? ?? '',
    };
    return OnBanner(
      title: title,
      sub: sub,
      icon: phase == 'over' ? Icons.emoji_events : Icons.flag,
      colors: phase == 'over' && v['winner'] == 'spy'
          ? const [Color(0xFFB71C1C), Color(0xFF4A148C)]
          : const [Color(0xFF1565C0), Color(0xFF00695C)],
      myTurn: _myTurn,
    );
  }

  Widget _track() {
    final results = (v['results'] as List? ?? const []);
    final rejects = onInt(v['rejects'], 0);
    final two = v['twoFail'] == true;
    final cs = Theme.of(context).colorScheme;
    return OnPanel(
      child: Column(children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: results.length > i && results[i] == 1
                      ? Colors.blue.shade600
                      : results.length > i && results[i] == 0
                          ? Colors.red.shade700
                          : cs.surfaceContainerHighest,
                  border: Border.all(color: i == mission && phase != 'over' ? Colors.amber : Colors.black26, width: i == mission ? 3 : 1),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (results.length > i && results[i] != null)
                    Icon(results[i] == 1 ? Icons.check : Icons.close, color: Colors.white, size: 26)
                  else
                    Text('${i < sizes.length ? sizes[i] : ''}人',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cs.onSurface)),
                  if (i == 3 && two)
                    Text('需2失败', style: TextStyle(fontSize: 8.5, color: results.length > i && results[i] != null ? Colors.white : cs.onSurface)),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('否决次数 ', style: TextStyle(fontSize: 12)),
          for (var i = 0; i < 5; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < rejects ? (i == 4 ? Colors.red : Colors.orange) : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
          Text('  间谍 ${onInt(v['spyCount'], 0)} 人', style: const TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }

  Set<int> get _selectable {
    if (!me) return const {};
    if (phase == 'propose' && leader == g.seat) return {for (var s = 0; s < g.players; s++) s};
    if (phase == 'plot') return onInts(v['plotTargets']).toSet();
    return const {};
  }

  Widget _seats() {
    final spies = onInts(v['spies']).toSet();
    final voted = onBools(v['voted']);
    final played = onBools(v['played']);
    final known = (v['known'] as Map? ?? const {});
    final plotHolder = onInt(v['plotHolder']);
    final active = <int>{};
    if (phase == 'propose') active.add(leader);
    if (phase == 'plot') active.add(v['plotStage'] == 'give' ? leader : plotHolder);
    if (phase == 'mission') {
      for (var i = 0; i < team.length; i++) {
        if (i >= played.length || !played[i]) active.add(team[i]);
      }
    }
    return OnSeatGrid(
      g: g,
      selectable: _selectable,
      selected: sel,
      active: active,
      onTap: (s) => setState(() {
        if (sel.contains(s)) {
          sel.remove(s);
        } else {
          final max = phase == 'plot' ? 1 : teamSize;
          if (sel.length >= max) sel.remove(sel.first);
          sel.add(s);
        }
      }),
      badges: (s) => [
        if (s == leader && phase != 'over') onBadge('队长', Colors.amber.shade800, icon: Icons.star),
        if (spies.contains(s) && !(s == g.seat && hide)) onBadge('间谍', Colors.red.shade700),
        if (known['$s'] == true) onBadge('已知间谍', Colors.red.shade900, icon: Icons.visibility),
        if (known['$s'] == false) onBadge('已知抵抗者', Colors.blue.shade700, icon: Icons.visibility),
        if (team.contains(s) && phase != 'propose') onBadge('队员', Colors.indigo),
        if (phase == 'vote' && s < voted.length && voted[s]) onBadge('已投', Colors.teal),
        if (phase == 'plot' && s == plotHolder) onBadge('持有计划卡', Colors.purple),
      ],
    );
  }

  Widget _identity() {
    final spy = v['mySpy'] == true;
    final spies = onInts(v['spies']).where((s) => s != g.seat).toList();
    final c = spy ? Colors.red.shade700 : Colors.blue.shade700;
    return OnPanel(
      title: '我的身份',
      icon: Icons.badge,
      border: hide ? null : c,
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(hide ? Icons.visibility : Icons.visibility_off, size: 20),
        onPressed: () => setState(() => hide = !hide),
      ),
      child: hide
          ? const Text('身份已隐藏（点击右上角显示）')
          : Row(children: [
              Icon(spy ? Icons.person_off : Icons.shield, color: c, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(spy ? '间谍' : '抵抗组织', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                  Text(
                      spy
                          ? '同伴：${spies.map((s) => '${s + 1}号').join('、')}。执行任务时可以出“失败”。'
                          : '你不知道谁是间谍。只能出“成功”，想办法让三次任务成功。',
                      style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            ]),
    );
  }

  Widget _action() {
    switch (phase) {
      case 'plot':
        final ts = onInts(v['plotTargets']);
        final card = v['plotCard'] as String? ?? '';
        final give = v['plotStage'] == 'give';
        return OnPanel(
          title: '计划卡【${_plotNames[card] ?? ''}】',
          icon: Icons.description,
          border: ts.isNotEmpty ? Colors.purple : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_plotDesc[card] ?? '', style: const TextStyle(fontSize: 12.5)),
            if (ts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(give ? '选择一名玩家交给他' : (card == 'overheard' ? '选择一名相邻玩家查看其身份' : '选择一名玩家向其公开身份')),
              const SizedBox(height: 6),
              FilledButton(
                onPressed: sel.length == 1 ? () => g.act({'type': 'plot', 'target': sel.first}) : null,
                child: const Text('确认'),
              ),
            ],
          ]),
        );
      case 'propose':
        if (leader != g.seat) return OnPanel(child: Text('等待队长 ${g.name(leader)} 组队……'));
        return OnPanel(
          title: '你是队长：选择 $teamSize 名队员（可以包括自己）',
          icon: Icons.group_add,
          border: Colors.amber,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('已选 ${sel.length}/$teamSize：${(sel.toList()..sort()).map((s) => '${s + 1}号').join('、')}'),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: sel.length == teamSize ? () => g.act({'type': 'propose', 'team': sel.toList()}) : null,
              child: const Text('提交队伍'),
            ),
          ]),
        );
      case 'vote':
        final mv = v['myVote'];
        return OnPanel(
          title: '队伍：${team.map((s) => '${s + 1}号').join('、')}',
          icon: Icons.how_to_vote,
          child: mv != null
              ? Text('你投了${mv == true ? '赞成' : '反对'}，等待其他人……')
              : Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => g.act({'type': 'vote', 'approve': true}),
                      icon: const Icon(Icons.thumb_up),
                      label: const Text('赞成'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () => g.act({'type': 'vote', 'approve': false}),
                      icon: const Icon(Icons.thumb_down),
                      label: const Text('反对'),
                    ),
                  ),
                ]),
        );
      case 'mission':
        if (!team.contains(g.seat)) return const OnPanel(child: Text('任务进行中，等待队员出牌……'));
        final mc = v['myCard'];
        if (mc != null) return OnPanel(child: Text('你出了「${mc == true ? '成功' : '失败'}」，等待其他队员……'));
        final spy = v['mySpy'] == true;
        return OnPanel(
          title: '执行任务：秘密出牌',
          icon: Icons.task_alt,
          border: Colors.indigo,
          child: Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
                onPressed: () => g.act({'type': 'mission', 'success': true}),
                child: const Text('成功'),
              ),
            ),
            if (spy) ...[
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                  onPressed: () => g.act({'type': 'mission', 'success': false}),
                  child: const Text('失败'),
                ),
              ),
            ],
          ]),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _lastVote() {
    final lv = v['lastVote'] as Map;
    final votes = onBools(lv['votes']);
    return OnPanel(
      title: '上次投票（第${onInt(lv['mission'], 0) + 1}次任务）：${lv['approved'] == true ? '通过' : '否决'}',
      icon: Icons.ballot,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('队长 ${onInt(lv['leader']) + 1}号 · 队伍 ${onInts(lv['team']).map((s) => '${s + 1}号').join('、')}',
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var s = 0; s < votes.length; s++)
            onBadge('${s + 1}号 ${votes[s] ? '赞成' : '反对'}', votes[s] ? Colors.green.shade700 : Colors.red.shade700),
        ]),
      ]),
    );
  }

  Widget _history() {
    final h = (v['history'] as List? ?? const []).cast<Map>();
    if (h.isEmpty) return const SizedBox.shrink();
    return OnPanel(
      title: '任务记录',
      icon: Icons.history,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final m in h)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '第${onInt(m['mission'], 0) + 1}次 ${m['success'] == true ? '成功' : '失败'}'
              '（${onInt(m['fails'], 0)}张失败） 队伍：${onInts(m['team']).map((s) => '${s + 1}号').join('、')}',
              style: TextStyle(fontSize: 12.5, color: m['success'] == true ? Colors.blue.shade800 : Colors.red.shade800),
            ),
          ),
      ]),
    );
  }

  Widget _result() {
    final spies = onInts(v['spies']);
    return ResultBanner(
      v['winner'] == 'res' ? '抵抗组织获胜！' : '间谍获胜！',
      child: Text('${v['reason']}\n间谍是：${spies.map((s) => '${s + 1}号 ${g.name(s)}').join('、')}', textAlign: TextAlign.center),
    );
  }
}
