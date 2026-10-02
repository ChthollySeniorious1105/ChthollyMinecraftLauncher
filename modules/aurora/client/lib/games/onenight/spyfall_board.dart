import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'on_common.dart';

class SpyfallBoard extends StatefulWidget {
  final GameContext g;
  const SpyfallBoard(this.g, {super.key});
  @override
  State<SpyfallBoard> createState() => _SpyfallBoardState();
}

class _SpyfallBoardState extends State<SpyfallBoard> {
  final text = TextEditingController();
  int? sel;
  String? guess;
  bool hide = false;
  bool accuseMode = false;
  final Set<String> crossed = {};
  String _key = '';
  int _round = -1;

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  String get phase => v['phase'] as String? ?? '';
  bool get me => g.seat >= 0;
  bool get amSpy => v['amSpy'] == true;
  int get asker => onInt(v['asker'], 0);
  int get answerer => onInt(v['answerer']);

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void _sync() {
    final k = '$phase|$asker|$answerer|${v['round']}';
    if (k != _key) {
      _key = k;
      sel = null;
      accuseMode = false;
    }
    final r = onInt(v['round'], 0);
    if (r != _round) {
      _round = r;
      crossed.clear();
      guess = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final bg = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(const Color(0x22303F9F), g.table), g.table],
      ),
    );
    return onLayout(bg: bg, main: [
      _banner(),
      _seats(),
      const SizedBox(height: 8),
      if (phase == 'roundEnd' || phase == 'over') _result(),
      _feed(),
      _locations(),
    ], side: [
      if (me) _roleCard(),
      if (me) _action(),
      _scores(),
    ]);
  }

  bool get _myTurn {
    if (!me) return false;
    return switch (phase) {
      'play' => answerer >= 0 ? answerer == g.seat : asker == g.seat,
      'accuse' => onInt(v['accused']) != g.seat && v['myAccVote'] == null,
      'final' => v['myFinalVote'] == null,
      'roundEnd' => !(onBools(v['cont']).elementAtOrNull(g.seat) ?? true),
      _ => false,
    };
  }

  Widget _banner() {
    final round = onInt(v['round'], 1), total = onInt(v['totalRounds'], 1);
    final (title, sub) = switch (phase) {
      'play' => (
          '第 $round/$total 轮 · 问答',
          answerer >= 0 ? '${g.name(asker)} 问 ${g.name(answerer)}' : '${g.name(asker)} 正在选择提问对象'
        ),
      'accuse' => ('指认！', '${g.name(onInt(v['accuser']))} 指认 ${g.name(onInt(v['accused']))} 是间谍，需全票通过'),
      'final' => ('时间到', '所有人投票指认间谍'),
      'roundEnd' => ('第 $round 轮结束', (v['result'] as Map?)?['text'] as String? ?? ''),
      _ => ('游戏结束', '最终得分见右侧'),
    };
    return OnBanner(
      title: title,
      sub: sub,
      icon: phase == 'accuse' ? Icons.gavel : Icons.travel_explore,
      colors: phase == 'accuse' ? const [Color(0xFFD84315), Color(0xFF6A1B9A)] : const [Color(0xFF283593), Color(0xFF00838F)],
      myTurn: _myTurn,
      trailing: phase == 'play'
          ? OnCountdown(
              endsAt: onInt(v['endsAt'], 0),
              serverNow: onInt(v['now'], 0),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Colors.white))
          : null,
    );
  }

  Set<int> get _selectable {
    if (!me) return const {};
    final others = {for (var s = 0; s < g.players; s++) if (s != g.seat) s};
    if (phase == 'play' && (accuseMode || (asker == g.seat && answerer < 0))) {
      if (accuseMode) return others;
      final la = onInt(v['lastAsker']);
      return g.players > 2 ? others.difference({la}) : others;
    }
    if (phase == 'final' && v['myFinalVote'] == null) return others;
    return const {};
  }

  Widget _seats() {
    final scores = onInts(v['scores']);
    final res = v['result'] as Map?;
    final accused = onInt(v['accused']);
    final accVoted = onBools(v['accVoted']);
    final finalVoted = onBools(v['finalVoted']);
    final usedAcc = onBools(v['accusedBy']);
    final roles = (res?['roles'] as List?)?.cast<String>();
    final active = <int>{if (phase == 'play') answerer >= 0 ? answerer : asker};
    return OnSeatGrid(
      g: g,
      selectable: _selectable,
      selected: {?sel},
      active: active,
      onTap: (s) => setState(() => sel = sel == s ? null : s),
      badges: (s) => [
        onBadge('${s < scores.length ? scores[s] : 0}分', Colors.amber.shade800),
        if (phase == 'play' && s == asker) onBadge('提问', Colors.indigo),
        if (phase == 'play' && s == answerer) onBadge('回答', Colors.teal),
        if (phase == 'accuse' && s == accused) onBadge('被指认', Colors.red.shade800, icon: Icons.gavel),
        if (phase == 'accuse' && s != accused && s < accVoted.length && accVoted[s]) onBadge('已表决', Colors.teal),
        if (phase == 'final' && s < finalVoted.length && finalVoted[s]) onBadge('已投', Colors.teal),
        if (phase == 'play' && s < usedAcc.length && usedAcc[s]) onBadge('已指认过', Colors.grey),
        if (roles != null && s < roles.length)
          onBadge(roles[s], roles[s] == '间谍' ? Colors.red.shade700 : Colors.blueGrey.shade700),
      ],
    );
  }

  /// 地点 / 食物 / … (generic 词条 in mixed games).
  String get noun => v['noun'] as String? ?? '地点';

  Widget _roleCard() {
    final loc = v['location'] as String?;
    final role = v['myRole'] as String? ?? '';
    final c = amSpy ? Colors.red.shade700 : Colors.indigo;
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
              Icon(amSpy ? Icons.person_search : (noun == '地点' ? Icons.place : Icons.style), color: c, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(amSpy ? '你是间谍！' : '$noun：${loc ?? '?'}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: c)),
                  Text(amSpy ? '你不知道$noun。从别人的问答中推理，随时可以亮明身份猜$noun。' : '你的角色：$role',
                      style: const TextStyle(fontSize: 12.5)),
                ]),
              ),
            ]),
    );
  }

  Widget _action() {
    switch (phase) {
      case 'play':
        return _playPanel();
      case 'accuse':
        final accused = onInt(v['accused']);
        if (accused == g.seat) return const OnPanel(child: Text('你被指认了！等待其他人表决……'));
        if (v['myAccVote'] != null) return const OnPanel(child: Text('你已表决，等待其他人……'));
        return OnPanel(
          title: '${g.name(accused)} 是间谍吗？',
          icon: Icons.gavel,
          border: Colors.deepOrange,
          child: Row(children: [
            Expanded(
                child: FilledButton(
                    onPressed: () => g.act({'type': 'accuseVote', 'agree': true}), child: const Text('同意'))),
            const SizedBox(width: 8),
            Expanded(
                child: OutlinedButton(
                    onPressed: () => g.act({'type': 'accuseVote', 'agree': false}), child: const Text('反对'))),
          ]),
        );
      case 'final':
        if (v['myFinalVote'] != null) return const OnPanel(child: Text('你已投票，等待其他人……'));
        return OnPanel(
          title: '投票：谁是间谍？',
          icon: Icons.how_to_vote,
          child: FilledButton(
            onPressed: sel == null ? null : () => g.act({'type': 'finalVote', 'target': sel}),
            child: Text(sel == null ? '点选一名玩家' : '投给 ${g.name(sel!)}'),
          ),
        );
      case 'roundEnd':
        final done = onBools(v['cont']).elementAtOrNull(g.seat) ?? true;
        return OnPanel(
          child: FilledButton(
            onPressed: done ? null : () => g.act({'type': 'continue'}),
            child: Text(done ? '等待其他人……' : (onInt(v['round']) >= onInt(v['totalRounds']) ? '查看最终结果' : '下一轮')),
          ),
        );
    }
    return const SizedBox.shrink();
  }

  Widget _playPanel() {
    final myAsk = asker == g.seat && answerer < 0;
    final myAnswer = answerer == g.seat;
    final usedAcc = onBools(v['accusedBy']).elementAtOrNull(g.seat) ?? true;
    final children = <Widget>[];
    if (accuseMode) {
      children.addAll([
        const Text('点选你怀疑的玩家发起指认（每轮只能发起一次，需其他人全票同意）', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              onPressed: sel == null ? null : () => g.act({'type': 'accuse', 'target': sel}),
              child: Text(sel == null ? '选择玩家' : '指认 ${g.name(sel!)}'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => setState(() => accuseMode = false), child: const Text('取消')),
        ]),
      ]);
    } else if (myAsk || myAnswer) {
      children.addAll([
        Text(myAsk ? (sel == null ? '点选一名玩家，然后输入问题' : '向 ${g.name(sel!)} 提问：') : '${g.name(asker)} 问你：${v['pendingQ']}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: text,
          maxLength: 80,
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            border: const OutlineInputBorder(),
            hintText: myAsk ? '输入问题（也可以用语音问）' : '输入回答',
          ),
          onSubmitted: (_) => _send(myAsk),
        ),
        const SizedBox(height: 6),
        FilledButton(onPressed: myAsk && sel == null ? null : () => _send(myAsk), child: Text(myAsk ? '提问' : '回答')),
      ]);
    } else {
      children.add(Text(answerer >= 0 ? '等待 ${g.name(answerer)} 回答……' : '等待 ${g.name(asker)} 提问……'));
    }
    if (!accuseMode) {
      children.addAll([
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (!usedAcc)
            OutlinedButton.icon(
              onPressed: () => setState(() {
                accuseMode = true;
                sel = null;
              }),
              icon: const Icon(Icons.gavel, size: 18),
              label: const Text('发起指认'),
            ),
          if (amSpy)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: guess == null ? null : () => g.act({'type': 'guess', 'location': guess}),
              icon: const Icon(Icons.flag, size: 18),
              label: Text(guess == null ? '在下方$noun表中选择后猜$noun' : '亮明身份：猜「$guess」'),
            ),
        ]),
      ]);
    }
    return OnPanel(
      title: '我的行动',
      icon: Icons.question_answer,
      border: myAsk || myAnswer ? Colors.greenAccent.shade700 : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  void _send(bool ask) {
    final t = text.text.trim();
    if (t.isEmpty) return;
    if (ask) {
      if (sel == null) return;
      g.act({'type': 'ask', 'target': sel, 'text': t});
    } else {
      g.act({'type': 'answer', 'text': t});
    }
    text.clear();
  }

  Widget _feed() {
    final feed = (v['feed'] as List? ?? const []).cast<Map>();
    final cs = Theme.of(context).colorScheme;
    final last = feed.length > 12 ? feed.sublist(feed.length - 12) : feed;
    return OnPanel(
      title: '问答记录',
      icon: Icons.forum,
      child: last.isEmpty
          ? Text('还没有提问', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final e in last.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5), children: [
                    TextSpan(
                        text: '${g.name(onInt(e['from']))} → ${g.name(onInt(e['to']))}：',
                        style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
                    TextSpan(text: '${e['q']}'),
                    if ('${e['a']}'.isNotEmpty) ...[
                      const TextSpan(text: '\n    答：', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: '${e['a']}'),
                    ],
                  ])),
                ),
            ]),
    );
  }

  Widget _locations() {
    final locs = (v['locations'] as List? ?? const []).cast<String>();
    final mine = v['location'] as String?;
    final canGuess = amSpy && phase == 'play';
    final cs = Theme.of(context).colorScheme;
    return OnPanel(
      title: canGuess ? '$noun表（点选要猜的$noun，长按划掉）' : '$noun表（长按可划掉排除）',
      icon: Icons.map,
      child: Wrap(spacing: 5, runSpacing: 5, children: [
        for (final l in locs)
          GestureDetector(
            onTap: canGuess ? () => setState(() => guess = guess == l ? null : l) : null,
            onLongPress: () => setState(() => crossed.contains(l) ? crossed.remove(l) : crossed.add(l)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: guess == l
                    ? Colors.red.shade700
                    : l == mine
                        ? cs.primary.withValues(alpha: 0.25)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: l == mine ? cs.primary : cs.outline.withValues(alpha: 0.3)),
              ),
              child: Text(l,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: guess == l ? Colors.white : cs.onSurface.withValues(alpha: crossed.contains(l) ? 0.35 : 1),
                    decoration: crossed.contains(l) ? TextDecoration.lineThrough : null,
                    fontWeight: l == mine ? FontWeight.bold : null,
                  )),
            ),
          ),
      ]),
    );
  }

  Widget _scores() {
    final hist = (v['history'] as List? ?? const []).cast<Map>();
    if (hist.isEmpty) return const SizedBox.shrink();
    return OnPanel(
      title: '历史',
      icon: Icons.history,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final h in hist)
          Text('第${h['round']}轮：${h['location']} · 间谍 ${g.name(onInt(h['spy']))} ${h['spyWins'] == true ? '胜' : '负'}',
              style: const TextStyle(fontSize: 12.5)),
      ]),
    );
  }

  Widget _result() {
    final res = v['result'] as Map?;
    final scores = onInts(v['scores']);
    if (phase == 'over') {
      final best = scores.isEmpty ? 0 : scores.reduce((a, b) => a > b ? a : b);
      return ResultBanner(
        '最终赢家：${[for (var s = 0; s < scores.length; s++) if (scores[s] == best) g.name(s)].join('、')}',
        child: Text('最高 $best 分'),
      );
    }
    if (res == null) return const SizedBox.shrink();
    final gain = onInts(res['gain']);
    return ResultBanner(
      res['text'] as String? ?? '',
      child: Text(
        '${res['noun'] ?? noun}：${res['location']} · 间谍：${g.name(onInt(res['spy']))}\n'
        '${[for (var s = 0; s < gain.length; s++) if (gain[s] > 0) '${g.name(s)} +${gain[s]}'].join('  ')}',
        textAlign: TextAlign.center,
      ),
    );
  }
}
