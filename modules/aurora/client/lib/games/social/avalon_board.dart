import 'package:flutter/material.dart';

import '../../widgets/common.dart';

const _roleNames = {
  'merlin': '梅林',
  'assassin': '刺客',
  'percival': '派西维尔',
  'morgana': '莫甘娜',
  'mordred': '莫德雷德',
  'oberon': '奥伯伦',
  'servant': '亚瑟的忠臣',
  'minion': '莫德雷德的爪牙',
};
const _roleDesc = {
  'merlin': '你知道邪恶方（莫德雷德除外）。帮助正义方，但别被刺客发现！',
  'assassin': '邪恶方。若正义方完成三次任务，你可以刺杀梅林翻盘。',
  'percival': '你能看到梅林与莫甘娜，但分不清谁是谁。',
  'morgana': '邪恶方。你在派西维尔眼中与梅林一样。',
  'mordred': '邪恶方。梅林看不到你。',
  'oberon': '邪恶方。你不认识同伴，同伴也不认识你。',
  'servant': '正义方。找出邪恶方，让任务成功。',
  'minion': '邪恶方。破坏任务，隐藏身份。',
};
const _evil = {'assassin', 'morgana', 'mordred', 'oberon', 'minion'};

List<int> _ints(Object? v) => v is List ? [for (final e in v) (e as num).toInt()] : <int>[];

class AvalonBoard extends StatefulWidget {
  final GameContext g;
  const AvalonBoard(this.g, {super.key});
  @override
  State<AvalonBoard> createState() => _AvalonBoardState();
}

class _AvalonBoardState extends State<AvalonBoard> {
  final Set<int> picked = {};
  bool showRole = true;
  int _pickQuest = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  String get phase => v['phase'] as String;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leader = v['leader'] as int;
    final quest = v['quest'] as int;
    final sizes = _ints(v['sizes']);
    final team = _ints(v['team']);
    final known = ((v['known'] as Map?) ?? {}).map((k, val) => MapEntry(int.parse(k as String), val as String));
    final roles = (v['roles'] as List?)?.cast<String>();
    final voted = (v['voted'] as List).cast<bool>();
    final lastVote = (v['lastVote'] as Map?)?.cast<String, dynamic>();
    final me = g.seat;
    final myRole = v['myRole'] as String?;
    if (_pickQuest != quest || phase != 'propose') {
      if (_pickQuest != quest) picked.clear();
      _pickQuest = quest;
    }
    final size = quest < 5 ? sizes[quest] : 0;
    final assassin = v['assassin'] as int;

    String status;
    var hl = false;
    switch (phase) {
      case 'propose':
        hl = me == leader;
        status = me == leader ? '你是队长：选择 $size 名队员执行第 ${quest + 1} 次任务' : '等待队长 ${g.name(leader)} 组队（$size 人）';
        break;
      case 'vote':
        hl = me >= 0 && !voted[me];
        status = hl ? '请投票：是否同意这支队伍？' : '等待其他玩家投票';
        break;
      case 'quest':
        hl = team.contains(me) && v['myCard'] == null;
        status = hl ? '你在任务中：请出任务牌' : '任务进行中：${team.map(g.name).join('、')}';
        break;
      case 'assassin':
        hl = me == assassin;
        status = hl ? '你是刺客：选择你认为是梅林的玩家' : '正义方完成三次任务！等待刺客 ${g.name(assassin)} 刺杀梅林';
        break;
      default:
        status = '${v['winner'] == 'good' ? '正义方' : '邪恶方'}获胜：${v['reason']}';
    }

    Widget seatTile(int s) {
      final isLeader = s == leader;
      final onTeam = team.contains(s) && phase != 'propose';
      final sel = picked.contains(s);
      final label = roles != null ? _roleNames[roles[s]] : known[s];
      final bad = roles != null ? _evil.contains(roles[s]) : known[s] == '邪恶' || known[s] == '同伴';
      final voteMark = lastVote != null ? ((lastVote['votes'] as List)[s] == true) : null;
      VoidCallback? onTap;
      if (phase == 'propose' && me == leader && !g.over) {
        onTap = () => setState(() {
              if (sel) {
                picked.remove(s);
              } else if (picked.length < size) {
                picked.add(s);
              }
            });
      } else if (phase == 'assassin' && me == assassin && s != me && !(roles?[s] != null && _evil.contains(roles![s])) && known[s] != '同伴') {
        onTap = () => _confirm('确认刺杀 ${g.name(s)}？', () => g.act({'type': 'assassinate', 'target': s}));
      }
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 150,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: sel ? cs.primary.withValues(alpha: 0.35) : cs.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: sel || onTeam ? cs.primary : (s == v['assassinTarget'] ? Colors.red : cs.outline.withValues(alpha: 0.3)),
                width: sel || onTeam ? 2.5 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            g.tag(s, active: isLeader && !g.over, size: 30),
            const SizedBox(height: 3),
            Wrap(spacing: 4, runSpacing: 2, alignment: WrapAlignment.center, children: [
              if (isLeader) _badge('👑队长', Colors.amber),
              if (onTeam) _badge('⚔队员', cs.primary),
              if (label != null) _badge(label, bad ? Colors.red : Colors.blue),
              if (phase == 'vote') _badge(voted[s] ? '已投票' : '思考中', voted[s] ? Colors.green : Colors.grey),
              if (phase != 'vote' && voteMark != null) _badge(voteMark ? '上轮赞成' : '上轮反对', voteMark ? Colors.green : Colors.deepOrange),
              if (s == me) _badge('我', Colors.purple),
            ]),
          ]),
        ),
      );
    }

    final actions = <Widget>[];
    if (!g.over && me >= 0) {
      if (phase == 'propose' && me == leader) {
        actions.add(FilledButton.icon(
          onPressed: picked.length == size ? () => g.act({'type': 'propose', 'team': picked.toList()..sort()}) : null,
          icon: const Icon(Icons.groups),
          label: Text('提交队伍（${picked.length}/$size）'),
        ));
      } else if (phase == 'vote' && !voted[me]) {
        actions.addAll([
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () => g.act({'type': 'vote', 'approve': true}),
              icon: const Icon(Icons.thumb_up),
              label: const Text('赞成')),
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: () => g.act({'type': 'vote', 'approve': false}),
              icon: const Icon(Icons.thumb_down),
              label: const Text('反对')),
        ]);
      } else if (phase == 'vote') {
        actions.add(Text('你投了${v['myVote'] == true ? '赞成' : '反对'}'));
      } else if (phase == 'quest' && team.contains(me) && v['myCard'] == null) {
        final evil = myRole != null && _evil.contains(myRole);
        actions.addAll([
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () => g.act({'type': 'quest', 'success': true}),
              icon: const Icon(Icons.check_circle),
              label: const Text('成功')),
          if (evil)
            FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => g.act({'type': 'quest', 'success': false}),
                icon: const Icon(Icons.cancel),
                label: const Text('失败')),
        ]);
      } else if (phase == 'quest' && team.contains(me)) {
        actions.add(const Text('已出牌，等待其他队员'));
      }
    }

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 820;
      final main = Column(children: [
        const SizedBox(height: 6),
        StatusBar(status, highlight: hl),
        const SizedBox(height: 6),
        _questTrack(sizes, quest),
        const SizedBox(height: 4),
        _rejectTrack(v['rejects'] as int),
        const SizedBox(height: 6),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(6),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final s in g.seatsFromMe()) seatTile(s),
            ]),
          ),
        ),
        if (actions.isNotEmpty)
          Padding(padding: const EdgeInsets.all(6), child: Wrap(spacing: 10, runSpacing: 6, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: actions)),
        if (!wide && myRole != null) _roleCard(myRole, known, compact: true),
        if (g.over || phase == 'over') ResultBanner(status),
      ]);
      if (!wide) return main;
      return Row(children: [
        Expanded(child: main),
        SizedBox(
          width: 300,
          child: ListView(padding: const EdgeInsets.all(8), children: [
            if (myRole != null) _roleCard(myRole, known),
            const SizedBox(height: 8),
            _history(),
          ]),
        ),
      ]);
    });
  }

  Widget _badge(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.7))),
        child: Text(t, style: const TextStyle(fontSize: 11)),
      );

  Widget _questTrack(List<int> sizes, int quest) {
    final results = (v['results'] as List).map((e) => e == null ? -1 : (e as num).toInt()).toList();
    final twoFail = v['twoFail'] == true;
    return Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
      for (var i = 0; i < 5; i++)
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: results[i] == 1 ? Colors.blue : (results[i] == 0 ? Colors.red : Colors.black26),
            border: Border.all(color: i == quest && !g.over ? Colors.amber : Colors.white54, width: i == quest ? 3 : 1.5),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(results[i] == 1 ? '成功' : (results[i] == 0 ? '失败' : '${sizes[i]}人'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            if (i == 3 && twoFail) const Text('需2败', style: TextStyle(color: Colors.white70, fontSize: 9)),
          ]),
        ),
    ]);
  }

  Widget _rejectTrack(int rejects) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('否决次数：', style: TextStyle(fontSize: 12)),
        for (var i = 0; i < 5; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < rejects ? Colors.deepOrange : Colors.transparent,
              border: Border.all(color: i == 4 ? Colors.red : Colors.grey),
            ),
          ),
      ]);

  Widget _roleCard(String role, Map<int, String> known, {bool compact = false}) {
    final evil = _evil.contains(role);
    final col = evil ? Colors.red : Colors.blue;
    final info = known.entries.map((e) => '${g.name(e.key)}（${e.value}）').join('、');
    final roleList = (v['roleList'] as List).cast<String>().map((r) => _roleNames[r]).join('、');
    if (compact) {
      return InkWell(
        onTap: () => setState(() => showRole = !showRole),
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: col.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: col)),
          child: showRole
              ? Text('我的身份：${_roleNames[role]}（${evil ? '邪恶' : '正义'}）${info.isEmpty ? '' : '\n夜晚信息：$info'}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))
              : const Text('点击查看我的身份', style: TextStyle(fontSize: 12)),
        ),
      );
    }
    return Card(
      color: col.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(evil ? Icons.dangerous : Icons.shield, color: col),
            const SizedBox(width: 6),
            Text(_roleNames[role]!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: col)),
            const Spacer(),
            Text(evil ? '邪恶方' : '正义方', style: TextStyle(color: col)),
          ]),
          const SizedBox(height: 4),
          Text(_roleDesc[role] ?? '', style: const TextStyle(fontSize: 12)),
          if (info.isNotEmpty) ...[const SizedBox(height: 6), Text('夜晚信息：$info', style: const TextStyle(fontWeight: FontWeight.bold))],
          const SizedBox(height: 6),
          Text('本局角色：$roleList', style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _history() {
    final h = (v['history'] as List).cast<Map>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('任务记录', style: TextStyle(fontWeight: FontWeight.bold)),
          if (h.isEmpty) const Text('暂无', style: TextStyle(fontSize: 12)),
          for (final r in h)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '第${(r['quest'] as int) + 1}次 ${r['success'] == true ? '✅成功' : '❌失败'}（${r['fails']}张失败）\n'
                '队长 ${g.name(r['leader'] as int)}：${_ints(r['team']).map(g.name).join('、')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _confirm(String text, VoidCallback ok) async {
    final r = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (c) => AlertDialog(content: Text(text), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确定')),
      ]),
    );
    if (r == true) ok();
  }
}
