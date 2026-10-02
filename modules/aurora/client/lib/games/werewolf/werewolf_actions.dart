part of 'werewolf_board.dart';

/// The "what can I do now" panel.
extension _WwActions on _WwPanels {
  Widget _hint(BuildContext context, String t) =>
      Text(t, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface));

  Widget _selHint(BuildContext context, String what) {
    final s = st.sel;
    return Text(s == null ? '点击座位选择$what' : '已选择：${sn(s)} ${g.name(s)}',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: s == null ? null : Colors.redAccent));
  }

  Widget _row(List<Widget> children) =>
      Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: children);

  void _act(Map<String, dynamic> a) {
    g.act(a);
    st.refresh(() => st.sel = null);
  }

  Widget actionPanel(BuildContext context) {
    final me = g.seat;
    if (me < 0 || g.over || v['phase'] == 'over') return const SizedBox.shrink();
    final child = _panelBody(context);
    final take = v['explodeTake'] == true;
    final sel = st.sel;
    final skills = <Widget>[
      if (v['canExplode'] == true)
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          icon: const Icon(Icons.local_fire_department, size: 18),
          label: Text(take ? (sel == null ? '自爆带人（先选人）' : '自爆带走 ${sn(sel)}') : '自爆'),
          onPressed: take && sel == null ? null : () => _confirmExplode(context, take ? sel : null),
        ),
      if (v['canDuel'] == true)
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.blueGrey.shade800),
          icon: const Icon(Icons.security, size: 18),
          label: Text(sel == null ? '骑士决斗（先选人）' : '与 ${sn(sel)} 决斗'),
          onPressed: sel == null ? null : () => _confirmDuel(context, sel),
        ),
    ];
    final extra = skills.isEmpty
        ? null
        : Padding(padding: const EdgeInsets.only(top: 6), child: _row(skills));
    if (child == null && extra == null) return const SizedBox.shrink();
    return card(
      context,
      Column(mainAxisSize: MainAxisSize.min, children: [?child, ?extra]),
      border: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
    );
  }

  Future<bool> _confirm(BuildContext context, String title, String body, String ok) async {
    final r = await showDialog<bool>(useRootNavigator: false, 
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _confirmExplode(BuildContext context, int? take) async {
    final ok = await _confirm(
        context,
        take == null ? '确认自爆？' : '确认自爆并带走 ${sn(take)}？',
        '自爆将公开你的狼人身份并立即出局，今天直接结束进入黑夜。${take == null ? '' : '\n${sn(take)} 将被你带走。'}',
        '自爆');
    if (ok) _act({'type': 'explode', 'target': ?take});
  }

  Future<void> _confirmDuel(BuildContext context, int t) async {
    final ok = await _confirm(context, '确认与 ${sn(t)} 决斗？',
        '你将翻牌亮出骑士身份（每局一次）。\n若 ${sn(t)} 是狼人，他立即出局并直接进入黑夜；\n若 ${sn(t)} 是好人，你将以死谢罪。', '决斗');
    if (ok) _act({'type': 'duel', 'target': t});
  }

  Widget _twoPick(BuildContext context, String what) {
    final a = st.sel, b = st.sel2;
    final t = a == null ? '点击座位选择$what（两人）' : (b == null ? '已选 ${sn(a)}，再选一人' : '已选择：${sn(a)} 和 ${sn(b)}');
    return Text(t,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: a == null ? null : Colors.redAccent));
  }

  Widget _col(List<Widget> c) => Column(mainAxisSize: MainAxisSize.min, children: c);

  Widget? _panelBody(BuildContext context) {
    final me = g.seat;
    final alive = (v['alive'] as List)[me] == true;
    final role = v['myRole'] as String?;
    final sel = st.sel;
    switch (v['phase']) {
      case 'night':
        final n = v['night'] as Map?;
        if (!alive) return _hint(context, '你已出局，请安静观看');
        if (n == null) return null;
        final duty = n['duty'] as String? ?? 'sleep';
        if (n['done'] == true && duty != 'kill') return _hint(context, '你今晚的行动已完成，等待天亮…');
        if (n['magicPending'] == true) return _hint(context, '魔术师正在行动，请稍候再查验…');
        final sel2 = st.sel2;
        switch (duty) {
          case 'magic':
            final used = wwInts(n['swapped']);
            return _col([
              _twoPick(context, '要交换号码的玩家'),
              if (used.isNotEmpty) Text('已被交换过：${used.map(sn).join('、')}', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              _row([
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('交换'),
                  onPressed: sel == null || sel2 == null ? null : () => _act({'type': 'magic', 'a': sel, 'b': sel2}),
                ),
                OutlinedButton(onPressed: () => _act({'type': 'magic', 'a': -1, 'b': -1}), child: const Text('不交换')),
              ]),
            ]);
          case 'link':
            return _col([
              _twoPick(context, '要连为情侣的玩家'),
              const SizedBox(height: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.pink),
                icon: const Icon(Icons.favorite),
                label: const Text('连成情侣'),
                onPressed: sel == null || sel2 == null ? null : () => _act({'type': 'link', 'a': sel, 'b': sel2}),
              ),
            ]);
          case 'model':
            return _col([
              _selHint(context, '你的榜样'),
              const SizedBox(height: 6),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.brown),
                icon: const Icon(Icons.child_care),
                label: const Text('选为榜样'),
                onPressed: sel == null ? null : () => _act({'type': 'model', 'target': sel}),
              ),
            ]);
          case 'curse':
            return _col([
              _selHint(context, '要诅咒的玩家（明天放逐投票 +1 票）'),
              const SizedBox(height: 6),
              _row([
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.blueGrey.shade700),
                  icon: const Icon(Icons.flutter_dash),
                  label: const Text('诅咒'),
                  onPressed: sel == null ? null : () => _act({'type': 'curse', 'target': sel}),
                ),
                OutlinedButton(onPressed: () => _act({'type': 'curse', 'target': -1}), child: const Text('不诅咒')),
              ]),
            ]);
        }
        if (duty == 'kill' && role == 'wolfBeauty' && n['charmDone'] == false) {
          return _col([
            _selHint(context, '今晚要魅惑的玩家'),
            const SizedBox(height: 6),
            _row([
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade700),
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('魅惑'),
                onPressed: sel == null ? null : () => _act({'type': 'charm', 'target': sel}),
              ),
              OutlinedButton(onPressed: () => _act({'type': 'charm', 'target': -1}), child: const Text('不魅惑')),
            ]),
          ]);
        }
        if (duty == 'kill') {
          final kill = n['kill'];
          if (kill != null) return _hint(context, wwInt(kill) < 0 ? '狼队今晚空刀' : '狼队今晚击杀 ${sn(wwInt(kill))}');
          if (n['myVote'] != null) {
            final mv = wwInt(n['myVote']);
            return _hint(context, '你选择了${mv < 0 ? '空刀' : '击杀 ${sn(mv)}'}，等待队友…（队友的选择显示在座位上）');
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            _selHint(context, '今晚要击杀的玩家'),
            const SizedBox(height: 6),
            _row([
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                icon: const Icon(Icons.pets),
                label: const Text('确认击杀'),
                onPressed: sel == null ? null : () => _act({'type': 'kill', 'target': sel}),
              ),
              OutlinedButton(onPressed: () => _act({'type': 'kill', 'target': -1}), child: const Text('空刀')),
            ]),
          ]);
        }
        switch (duty) {
          case 'check':
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _selHint(context, '要查验的玩家'),
              const SizedBox(height: 6),
              FilledButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('查验'),
                onPressed: sel == null ? null : () => _act({'type': 'check', 'target': sel}),
              ),
            ]);
          case 'guard':
            final lg = wwInt(n['lastGuard']);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _selHint(context, '要守护的玩家'),
              if (lg >= 0) Text('昨晚守护了 ${sn(lg)}，今晚不能再守', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              _row([
                FilledButton.icon(
                  icon: const Icon(Icons.shield),
                  label: const Text('守护'),
                  onPressed: sel == null ? null : () => _act({'type': 'guard', 'target': sel}),
                ),
                OutlinedButton(onPressed: () => _act({'type': 'guard', 'target': -1}), child: const Text('空守')),
              ]),
            ]);
          case 'witch':
            if (n['ready'] != true) return _hint(context, '等待狼人行动…');
            final victim = n['victim'];
            final anti = v['antidote'] == true;
            final poison = v['poison'] == true;
            final canSave = anti && victim != null && wwInt(victim) >= 0 && (wwInt(victim) != me || n['canSelfSave'] == true);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                !anti
                    ? '解药已用完，你无法得知今晚的刀口'
                    : (victim == null || wwInt(victim) < 0 ? '今晚是空刀' : '今晚 ${sn(wwInt(victim))} 被狼人击杀'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (poison) _selHint(context, '要毒的玩家（可选）'),
              const SizedBox(height: 6),
              _row([
                if (canSave)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.healing),
                    label: const Text('使用解药'),
                    onPressed: () => _act({'type': 'witch', 'save': true, 'poison': -1}),
                  ),
                if (poison)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.purple),
                    icon: const Icon(Icons.science),
                    label: const Text('使用毒药'),
                    onPressed: sel == null ? null : () => _act({'type': 'witch', 'save': false, 'poison': sel}),
                  ),
                OutlinedButton(
                    onPressed: () => _act({'type': 'witch', 'save': false, 'poison': -1}), child: const Text('不用药')),
              ]),
            ]);
          default:
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _hint(
                  context,
                  role == 'hiddenWolf'
                      ? '你是隐狼：不与狼队睁眼，请闭眼'
                      : (role == 'cupid' || role == 'wildChild' ? '你的首夜技能已使用，请闭眼' : '你今晚没有行动，请闭眼')),
              const SizedBox(height: 6),
              FilledButton.icon(
                icon: const Icon(Icons.bedtime),
                label: const Text('确认闭眼'),
                onPressed: () => _act({'type': 'sleep'}),
              ),
            ]);
        }
      case 'sheriff_signup':
        if (!alive) return null;
        if (v['mySignup'] != null) return _hint(context, v['mySignup'] == true ? '你已上警，等待其他人…' : '你选择不上警，等待其他人…');
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _hint(context, '是否竞选警长？警长投票计 1.5 票'),
          const SizedBox(height: 6),
          _row([
            FilledButton.icon(
                icon: const Icon(Icons.local_police), label: const Text('上警'), onPressed: () => _act({'type': 'run', 'run': true})),
            OutlinedButton(onPressed: () => _act({'type': 'run', 'run': false}), child: const Text('不上警')),
          ]),
        ]);
      case 'speech':
        if (wwInt(v['speaker']) != me) return _hint(context, '请听 ${sn(wwInt(v['speaker']))} 发言（语音/文字聊天）');
        return _speechPanel(context, lastWords: false);
      case 'direction':
        if (wwInt(v['sheriff']) != me) return null;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _hint(context, '请选择发言顺序（警长最后发言归票）'),
          const SizedBox(height: 6),
          _row([
            FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: const Text('顺序（号码递增）'),
                onPressed: () => _act({'type': 'direction', 'dir': 1})),
            FilledButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('逆序（号码递减）'),
                onPressed: () => _act({'type': 'direction', 'dir': -1})),
          ]),
        ]);
      case 'vote':
      case 'sheriff_vote':
        final voters = wwInts(v['voters']);
        if (!voters.contains(me)) {
          return _hint(context, wwInts(v['idiot']).contains(me) ? '你已翻牌为白痴，不能投票' : '你没有投票权，等待投票结束');
        }
        if (v['myVote'] != null) {
          final mv = wwInt(v['myVote']);
          return _hint(context, mv < 0 ? '你已弃票，等待其他人…' : '你投给了 ${sn(mv)}，等待其他人…');
        }
        final crow = wwInt(v['crow']);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (crow >= 0)
            Text('🐦 ${sn(crow)} 被乌鸦诅咒，本轮额外计 1 票',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
          _selHint(context, v['phase'] == 'sheriff_vote' ? '支持的警长候选人' : '要放逐的玩家'),
          const SizedBox(height: 6),
          _row([
            FilledButton.icon(
              icon: const Icon(Icons.how_to_vote),
              label: const Text('投票'),
              onPressed: sel == null ? null : () => _act({'type': 'vote', 'target': sel}),
            ),
            OutlinedButton(onPressed: () => _act({'type': 'vote', 'target': -1}), child: const Text('弃票')),
          ]),
        ]);
      case 'task':
        if (wwInt(v['taskSeat']) != me) return null;
        switch (v['task']) {
          case 'lastwords':
            return _speechPanel(context, lastWords: true);
          case 'badge':
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _selHint(context, '警徽移交对象'),
              const SizedBox(height: 6),
              _row([
                FilledButton.icon(
                  icon: const Icon(Icons.local_police),
                  label: const Text('移交警徽'),
                  onPressed: sel == null ? null : () => _act({'type': 'badge', 'target': sel}),
                ),
                OutlinedButton(onPressed: () => _act({'type': 'badge', 'target': -1}), child: const Text('撕毁警徽')),
              ]),
            ]);
          default:
            if (v['canShoot'] != true) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                _hint(context, '你已出局，没有可以发动的技能'),
                const SizedBox(height: 6),
                FilledButton(onPressed: () => _act({'type': 'shoot', 'target': -1}), child: const Text('确认')),
              ]);
            }
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _hint(context, role == 'wolfking' ? '狼王：你可以带走一名玩家' : '猎人：你可以开枪带走一名玩家'),
              _selHint(context, '要带走的玩家'),
              const SizedBox(height: 6),
              _row([
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('发动技能'),
                  onPressed: sel == null ? null : () => _act({'type': 'shoot', 'target': sel}),
                ),
                OutlinedButton(onPressed: () => _act({'type': 'shoot', 'target': -1}), child: const Text('不发动')),
              ]),
            ]);
        }
    }
    return null;
  }

  Widget _speechPanel(BuildContext context, {required bool lastWords}) {
    final sel = st.sel;
    final canWithdraw = !lastWords && v['speechKind'] == 'sheriff';
    void send() {
      final a = <String, dynamic>{'type': 'end', 'text': st.text.text};
      if (sel != null) a['claim'] = {'target': sel, 'wolf': st.claimWolf};
      st.text.clear();
      _act(a);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(lastWords ? '请发表遗言（语音或文字），说完点击结束' : '轮到你发言了！用语音或文字发言，说完点击结束',
          textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      TextField(
        controller: st.text,
        maxLength: 60,
        decoration: const InputDecoration(isDense: true, labelText: '发言摘要（可选，会写入记录）'),
      ),
      Text(
        sel == null ? '（可选）点击座位公开报查验结果' : '报 ${sn(sel)} 为：',
        style: const TextStyle(fontSize: 12),
      ),
      if (sel != null)
        _row([
          ChoiceChip(label: const Text('金水（好人）'), selected: !st.claimWolf, onSelected: (_) => st.refresh(() => st.claimWolf = false)),
          ChoiceChip(label: const Text('查杀（狼人）'), selected: st.claimWolf, onSelected: (_) => st.refresh(() => st.claimWolf = true)),
        ]),
      const SizedBox(height: 6),
      _row([
        FilledButton.icon(icon: const Icon(Icons.check), label: Text(lastWords ? '结束遗言' : '结束发言'), onPressed: send),
        if (canWithdraw) OutlinedButton(onPressed: () => _act({'type': 'withdraw'}), child: const Text('退水')),
      ]),
    ]);
  }
}
