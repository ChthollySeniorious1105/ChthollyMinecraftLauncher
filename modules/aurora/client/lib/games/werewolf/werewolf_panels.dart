part of 'werewolf_board.dart';

/// Informational panels (banner, role card, logs, vote result, end reveal).
class _WwPanels {
  final _WerewolfBoardState st;
  _WwPanels(this.st);

  GameContext get g => st.g;
  Map<String, dynamic> get v => st.g.view;

  Widget card(BuildContext context, Widget child, {Color? border, EdgeInsets? margin}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border ?? cs.outline.withValues(alpha: 0.3), width: border == null ? 1 : 2),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
      ),
      child: child,
    );
  }

  String sn(int s) => '${s + 1}号';

  // ------------------------------------------------------------ banner

  (String, String, IconData) _phaseText() {
    final round = wwInt(v['round'], 1);
    final speaker = wwInt(v['speaker']);
    final kind = v['speechKind'] as String? ?? '';
    final taskSeat = wwInt(v['taskSeat']);
    switch (v['phase']) {
      case 'night':
        return ('第 $round 夜', '天黑请闭眼，有技能的玩家请行动', Icons.nightlight_round);
      case 'sheriff_signup':
        return ('第 $round 天 · 警长竞选', '请选择是否上警', Icons.local_police);
      case 'speech':
        final what = switch (kind) {
          'sheriff' => '竞选发言',
          'sheriff_pk' => '警长PK发言',
          'pk' => 'PK 发言',
          _ => '发言',
        };
        return ('第 $round 天 · $what', '${sn(speaker)} 正在发言', Icons.record_voice_over);
      case 'sheriff_vote':
        return ('第 $round 天 · 警长投票', '警下玩家投票选出警长', Icons.how_to_vote);
      case 'direction':
        return ('第 $round 天', '警长 ${sn(wwInt(v['sheriff']))} 选择发言顺序', Icons.swap_horiz);
      case 'vote':
        return ('第 $round 天 · ${wwInts(v['pk']).isNotEmpty ? 'PK 投票' : '放逐投票'}', '请投票（可弃票）', Icons.how_to_vote);
      case 'task':
        final what = switch (v['task']) {
          'lastwords' => '发表遗言',
          'badge' => '移交警徽',
          _ => '确认是否发动技能',
        };
        return ('第 $round 天', '${sn(taskSeat)} $what', Icons.hourglass_top);
      case 'over':
        return (
          switch (v['winner']) { 'good' => '好人阵营获胜', 'wolf' => '狼人阵营获胜', 'lovers' => '情侣阵营获胜', _ => '平局' },
          v['reason'] as String? ?? '',
          Icons.emoji_events
        );
      default:
        return ('第 $round 天', '天亮了', Icons.wb_sunny);
    }
  }

  Widget banner(BuildContext context) {
    final night = v['phase'] == 'night';
    final (title, sub, icon) = _phaseText();
    final waiting = st.g.seat >= 0 && _iAmWaited();
    final fg = night ? Colors.white : const Color(0xFF3A2A00);
    final dawn = v['dawn'] as Map?;
    final dawnDeaths = wwInts(dawn?['deaths']);
    final showDawn = dawn != null && wwInt(dawn['d']) == wwInt(v['round']) && !night && v['phase'] != 'over';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: night
              ? const [Color(0xFF283593), Color(0xFF4A148C)]
              : const [Color(0xFFFFE082), Color(0xFFFFCC80)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: waiting ? Border.all(color: Colors.greenAccent, width: 2.5) : null,
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(icon, color: fg, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: fg)),
              Text(sub, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85))),
            ]),
          ),
          if (waiting)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(10)),
              child: const Text('轮到你', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
        ]),
        if (showDawn) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
            child: Text(
              dawnDeaths.isEmpty ? '☀ 昨夜是平安夜' : '☀ 昨夜死亡：${dawnDeaths.map(sn).join('、')}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF5D4037)),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('板子：${v['board']} · ${v['win'] == 'city' ? '屠城' : '屠边'}',
              style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.7))),
        ),
      ]),
    );
  }

  bool _iAmWaited() {
    final me = st.g.seat;
    final phase = v['phase'];
    final alive = (v['alive'] as List)[me] == true;
    switch (phase) {
      case 'night':
        final n = v['night'] as Map?;
        if (!alive || n == null || n['done'] == true) return false;
        if (n['duty'] == 'kill') {
          return n['kill'] == null && n['myVote'] == null || (v['myRole'] == 'wolfBeauty' && n['charmDone'] == false);
        }
        return true;
      case 'sheriff_signup':
        return alive && v['mySignup'] == null;
      case 'speech':
        return wwInt(v['speaker']) == me;
      case 'direction':
        return wwInt(v['sheriff']) == me;
      case 'vote':
      case 'sheriff_vote':
        return wwInts(v['voters']).contains(me) && v['myVote'] == null;
      case 'task':
        return wwInt(v['taskSeat']) == me;
    }
    return false;
  }

  // ------------------------------------------------------------ role card

  Widget roleCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final role = v['myRole'] as String?;
    if (role == null) {
      return card(context, Row(children: [
        Icon(Icons.visibility, color: cs.primary),
        const SizedBox(width: 8),
        const Expanded(child: Text('观战中：身份将在游戏结束时公布')),
      ]));
    }
    final hide = st.hideRole;
    final color = wwRoleColor(role);
    final mates = wwInts(v['mates']);
    final alive = (v['alive'] as List)[st.g.seat] == true;
    final me = st.g.seat;
    final lovers = wwInts(v['lovers']);
    final myLover = lovers.length == 2 && lovers.contains(me) ? lovers.firstWhere((x) => x != me) : -1;
    final third = v['loversThird'] == true;
    final turned = v['turned'] == true;
    final model = wwInt(v['model']);
    final extra = <String>[
      if (turned) '你的榜样已出局，你已变成狼人',
      if (mates.isNotEmpty) '${role == 'hiddenWolf' ? '狼队（他们不知道你）' : '狼队友'}：${mates.map(sn).join('、')}',
      if (role == 'hiddenWolf') v['hiddenActive'] == true ? '其他狼人已出局，你已变为普通狼人' : '其他狼人全部出局后你才能刀人',
      if (myLover >= 0) '💕 你的情侣：${sn(myLover)}${third ? '（人狼恋，第三方阵营）' : ''}',
      if (role == 'cupid' && lovers.length == 2) '情侣：${lovers.map(sn).join(' 和 ')}${third ? '（人狼恋，你们是第三方）' : ''}',
      if (role == 'wildChild' && model >= 0 && !turned) '你的榜样：${sn(model)}',
      if (role == 'knight') '决斗：${v['duelUsed'] == true ? '已使用' : '可用（白天发言阶段）'}',
      if (role == 'wolfBeauty' && wwInt(v['charmed']) >= 0) '当前魅惑：${sn(wwInt(v['charmed']))}',
      if (role == 'witch') '解药：${v['antidote'] == true ? '可用' : '已用'}　毒药：${v['poison'] == true ? '可用' : '已用'}',
      if (!alive) '你已出局',
    ];
    return card(
      context,
      Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hide ? cs.surfaceContainerHighest : color.withValues(alpha: 0.18),
            border: Border.all(color: hide ? cs.outline : color, width: 2),
          ),
          child: Icon(hide ? Icons.help_outline : wwRoleIcons[role], color: hide ? cs.outline : color, size: 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(hide ? '身份已隐藏' : '我的身份：${wwRoleNames[role]}${turned ? '（已变狼）' : ''}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: hide ? cs.onSurface : color)),
            if (!hide) ...[
              Text(wwRoleDesc[role] ?? '', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.75))),
              for (final e in extra)
                Text(e, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cs.onSurface)),
            ],
          ]),
        ),
        IconButton(
          tooltip: hide ? '显示身份' : '隐藏身份',
          icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
          onPressed: () => st.refresh(() => st.hideRole = !st.hideRole),
        ),
      ]),
      border: hide ? null : color.withValues(alpha: 0.7),
    );
  }

  // ------------------------------------------------------------ private info

  Widget privateInfo(BuildContext context) {
    final lines = (v['private'] as List? ?? const []).cast<String>();
    if (lines.isEmpty || st.hideRole) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final shown = lines.length > 8 ? lines.sublist(lines.length - 8) : lines;
    return card(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.lock, size: 16, color: cs.primary),
          const SizedBox(width: 4),
          Text('我的秘密信息', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
        ]),
        const SizedBox(height: 4),
        for (final l in shown) Text(l, style: const TextStyle(fontSize: 12)),
      ]),
    );
  }

  // ------------------------------------------------------------ log

  Widget logCard(BuildContext context, {int maxLines = 10}) {
    final cs = Theme.of(context).colorScheme;
    final log = [for (final e in (v['log'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];
    final shown = log.length > maxLines ? log.sublist(log.length - maxLines) : log;
    return card(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.article, size: 16, color: cs.primary),
          const SizedBox(width: 4),
          Text('法官记录', style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
        ]),
        const SizedBox(height: 4),
        for (final e in shown.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(e['n'] == true ? Icons.nightlight_round : Icons.wb_sunny,
                  size: 12, color: e['n'] == true ? Colors.indigo : Colors.orange),
              const SizedBox(width: 4),
              Expanded(child: Text('${e['t']}', style: const TextStyle(fontSize: 12))),
            ]),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------ last vote

  Widget lastVote(BuildContext context) {
    final lv = v['lastVote'] as Map?;
    if (lv == null) return const SizedBox.shrink();
    if (v['phase'] == 'vote' || v['phase'] == 'sheriff_vote') return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final out = wwInt(lv['out']);
    final tie = wwInts(lv['tie']);
    final sheriff = lv['kind'] == 'sheriff';
    final votes = [for (final p in lv['votes'] as List) wwInts(p)];
    final byTarget = <int, List<int>>{};
    for (final p in votes) {
      byTarget.putIfAbsent(p[1], () => []).add(p[0]);
    }
    final tally = {for (final t in lv['tally'] as List) wwInt((t as List)[0]): (t[1] as num)};
    final keys = byTarget.keys.toList()..sort((a, b) => (tally[b] ?? 0).compareTo(tally[a] ?? 0));
    String fmt(num n) => n == n.roundToDouble() ? '${n.toInt()}' : n.toStringAsFixed(1);
    final crow = wwInt(lv['crow']);
    if (crow >= 0 && !keys.contains(crow)) keys.add(crow);
    return card(
      context,
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('第 ${lv['d']} 天${sheriff ? '警长' : ''}${lv['pk'] == true ? 'PK' : ''}投票结果',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(
          out >= 0
              ? (sheriff ? '${sn(out)} 当选警长' : '${sn(out)} 得票最多')
              : (tie.isEmpty ? '全员弃票' : '${tie.map(sn).join('、')} 平票'),
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final k in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              k < 0
                  ? '弃票：${(byTarget[k] ?? const []).map(sn).join(' ')}'
                  : '${sn(k)}（${fmt(tally[k] ?? 0)} 票）← ${[...(byTarget[k] ?? const <int>[]).map(sn), if (k == crow) '乌鸦'].join(' ')}',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.85)),
            ),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------ end reveal

  Widget reveal(BuildContext context) {
    if (!st.g.over && v['over'] != true) return const SizedBox.shrink();
    final roles = (v['roles'] as List).cast<String?>();
    final winner = v['winner'] as String? ?? '';
    final me = st.g.seat;
    final camps = (v['camps'] as List?)?.cast<String>();
    final myCamp = me >= 0 && camps != null && me < camps.length ? camps[me] : null;
    final iWon = me >= 0 && myCamp != null && myCamp == winner;
    final lovers = wwInts(v['lovers']);
    final nights = [for (final n in (v['nights'] as List? ?? const [])) (n as Map).cast<String, dynamic>()];
    String t(Object? x) => wwInt(x) >= 0 ? sn(wwInt(x)) : '无';
    return ResultBanner(
      '${switch (winner) { 'good' => '好人阵营获胜！', 'wolf' => '狼人阵营获胜！', 'lovers' => '情侣阵营获胜！', _ => '平局' }}${me >= 0 && winner != 'draw' ? (iWon ? '（你赢了）' : '（你输了）') : ''}',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(v['reason'] as String? ?? ''),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: [
          for (var s = 0; s < roles.length; s++)
            wwBadge(
                '${sn(s)} ${st.g.name(s)}：${wwRoleNames[roles[s]] ?? '?'}'
                '${camps != null && s < camps.length && camps[s] == 'wolf' && !wwIsWolf(roles[s]) ? '（变狼）' : ''}'
                '${lovers.contains(s) ? ' 💕' : ''}',
                camps != null && s < camps.length && camps[s] == 'lovers'
                    ? Colors.pink
                    : (camps != null && s < camps.length && camps[s] == 'wolf' ? wwRoleColor('wolf') : wwRoleColor(roles[s]))),
        ]),
        if (nights.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final n in nights)
            Text(
              '第${n['n']}夜：刀 ${t(n['kill'])}${wwInt(n['guard'], -2) >= -1 ? '，守 ${t(n['guard'])}' : ''}'
              '${wwInt(n['save']) >= 0 ? '，救 ${t(n['save'])}' : ''}${wwInt(n['poison']) >= 0 ? '，毒 ${t(n['poison'])}' : ''}'
              '${wwInt(n['check']) >= 0 ? '，验 ${t(n['check'])}' : ''}'
              '${n['swap'] is List ? '，换 ${wwInts(n['swap']).map(sn).join('↔')}' : ''}'
              '${wwInt(n['charm']) >= 0 ? '，魅惑 ${t(n['charm'])}' : ''}'
              '${wwInt(n['curse']) >= 0 ? '，诅咒 ${t(n['curse'])}' : ''}'
              '${n['link'] is List ? '，情侣 ${wwInts(n['link']).map(sn).join('+')}' : ''}'
              '${wwInt(n['model']) >= 0 ? '，榜样 ${t(n['model'])}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ]),
    );
  }
}
