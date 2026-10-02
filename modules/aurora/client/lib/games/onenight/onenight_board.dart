import 'package:flutter/material.dart';

import '../../widgets/common.dart';
import 'on_common.dart';

const onRoleNames = {
  'werewolf': '狼人',
  'minion': '爪牙',
  'seer': '预言家',
  'robber': '强盗',
  'troublemaker': '捣蛋鬼',
  'drunk': '酒鬼',
  'insomniac': '失眠者',
  'hunter': '猎人',
  'tanner': '皮匠',
  'villager': '村民',
};

const onRoleDesc = {
  'werewolf': '狼人阵营。夜里与同伴互相确认；若你是唯一的狼人，可以查看中间一张牌。白天不要被投出！',
  'minion': '狼人阵营。夜里知道谁是狼人，但狼人不知道你。你被投出狼人仍然获胜。',
  'seer': '好人阵营。夜里查看一名玩家的牌，或中间的两张牌。',
  'robber': '好人阵营。夜里与一名玩家交换牌并查看你的新身份（你将属于新身份的阵营）。',
  'troublemaker': '好人阵营。夜里交换另外两名玩家的牌（你不能看）。',
  'drunk': '好人阵营。夜里必须把自己的牌与中间一张交换，但不能查看新身份。',
  'insomniac': '好人阵营。天亮前查看自己最终的牌，知道自己有没有被换。',
  'hunter': '好人阵营。如果你被投出，你投票的那个人也会一起出局。',
  'tanner': '独立阵营。你讨厌自己的工作——只有你被投出时你才获胜！',
  'villager': '好人阵营。没有技能，靠推理找出狼人。',
};

const onRoleIcons = {
  'werewolf': Icons.pets,
  'minion': Icons.visibility_off,
  'seer': Icons.visibility,
  'robber': Icons.swap_horizontal_circle,
  'troublemaker': Icons.shuffle,
  'drunk': Icons.local_bar,
  'insomniac': Icons.bedtime,
  'hunter': Icons.gps_fixed,
  'tanner': Icons.handyman,
  'villager': Icons.person,
};

Color onRoleColor(String? r) => switch (r) {
      'werewolf' => const Color(0xFFC62828),
      'minion' => const Color(0xFF8E244D),
      'seer' => const Color(0xFF6A1B9A),
      'robber' => const Color(0xFF37474F),
      'troublemaker' => const Color(0xFFEF6C00),
      'drunk' => const Color(0xFF00838F),
      'insomniac' => const Color(0xFF283593),
      'hunter' => const Color(0xFF2E7D32),
      'tanner' => const Color(0xFF6D4C41),
      'villager' => const Color(0xFF558B2F),
      _ => Colors.blueGrey,
    };

/// Small card face (or back when [role] is null).
class OnCard extends StatelessWidget {
  final String? role;
  final String label;
  final bool selected;
  final bool selectable;
  final VoidCallback? onTap;
  final double width;
  const OnCard({super.key, this.role, this.label = '', this.selected = false, this.selectable = false, this.onTap, this.width = 64});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = role == null ? const Color(0xFF263159) : onRoleColor(role);
    return GestureDetector(
      onTap: selectable ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: width,
        height: width * 1.4,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(c, Colors.white, 0.18)!, c],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? Colors.amberAccent : (selectable ? cs.primary : Colors.white24),
              width: selected ? 3 : (selectable ? 2 : 1)),
          boxShadow: [
            if (selected) const BoxShadow(color: Colors.amberAccent, blurRadius: 10),
            const BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(role == null ? Icons.nights_stay : onRoleIcons[role] ?? Icons.help, color: Colors.white, size: width * 0.38),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(role == null ? '?' : onRoleNames[role] ?? role!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          if (label.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ),
        ]),
      ),
    );
  }
}

class OneNightBoard extends StatefulWidget {
  final GameContext g;
  const OneNightBoard(this.g, {super.key});
  @override
  State<OneNightBoard> createState() => _OneNightBoardState();
}

class _OneNightBoardState extends State<OneNightBoard> {
  final Set<int> selP = {};
  final Set<int> selC = {};
  bool hide = false;
  String _key = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;
  String get phase => v['phase'] as String? ?? 'night';
  String? get myCard => v['myCard'] as String?;
  bool get me => g.seat >= 0;

  void _sync() {
    final k = '$phase|${v['myActed']}|${v['myVote']}';
    if (k != _key) {
      _key = k;
      selP.clear();
      selC.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    _sync();
    final night = phase == 'night';
    final bg = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: night
            ? const [Color(0xFF0B1030), Color(0xFF1B1F4B), Color(0xFF2A1E3F)]
            : [Color.alphaBlend(const Color(0x33FFD180), g.table), g.table],
      ),
    );
    return onLayout(bg: bg, main: [
      _banner(),
      _seats(),
      const SizedBox(height: 8),
      _center(),
      if (_talk.isNotEmpty) _talkFeed(),
      if (phase == 'over') _reveal(),
    ], side: [
      if (me) _roleCard(),
      if (me) _action(),
      if (me) _info(),
      _deckInfo(),
    ]);
  }

  List<Map> get _talk => [for (final e in (v['talk'] as List? ?? const [])) if (e is Map) e];

  /// Statements made with the `say` action (AI players speak this way).
  Widget _talkFeed() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(12)),
      child: ListView(shrinkWrap: true, reverse: true, children: [
        for (final e in _talk.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${g.name(onInt(e['s'], -1))}：', style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: '${e['t']}'),
            ]), style: const TextStyle(fontSize: 13)),
          ),
      ]),
    );
  }

  // ------------------------------------------------------------ banner
  Widget _banner() {
    final n = g.players;
    switch (phase) {
      case 'night':
        return OnBanner(
          title: '夜晚',
          sub: '所有人同时秘密行动（${onInt(v['nightCount'], 0)}/$n 已完成），结算按角色顺序进行',
          icon: Icons.nightlight_round,
          colors: const [Color(0xFF283593), Color(0xFF4A148C)],
          myTurn: me && v['myActed'] != true,
        );
      case 'day':
        final ready = onBools(v['ready']).where((x) => x).length;
        return OnBanner(
          title: '白天讨论',
          sub: '用语音/文字讨论，时间到或全员同意后投票（$ready/$n 同意提前投票）',
          icon: Icons.wb_sunny,
          colors: const [Color(0xFFFFB74D), Color(0xFFFF8A65)],
          fg: const Color(0xFF3A2000),
          trailing: OnCountdown(
              endsAt: onInt(v['endsAt'], 0),
              serverNow: onInt(v['now'], 0),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF3A2000))),
        );
      case 'vote':
        return OnBanner(
          title: '投票',
          sub: '所有人同时投票，票数最多者出局（每人都只有一票时无人出局）',
          icon: Icons.how_to_vote,
          colors: const [Color(0xFFE53935), Color(0xFF8E24AA)],
          myTurn: me && v['myVote'] == null,
        );
      default:
        final winners = onBools(v['winners']);
        final iWon = me && g.seat < winners.length && winners[g.seat];
        return OnBanner(
          title: me ? (iWon ? '你获胜了！' : '你输了') : '游戏结束',
          sub: v['reason'] as String? ?? '',
          icon: Icons.emoji_events,
          colors: iWon ? const [Color(0xFF43A047), Color(0xFF00897B)] : const [Color(0xFF546E7A), Color(0xFF37474F)],
        );
    }
  }

  // ------------------------------------------------------------ seats
  Set<int> _selectablePlayers() {
    if (!me) return const {};
    final others = {for (var s = 0; s < g.players; s++) if (s != g.seat) s};
    if (phase == 'vote') return v['myVote'] == null ? others : const {};
    if (phase != 'night' || v['myActed'] == true) return const {};
    return switch (myCard) {
      'seer' => selC.isEmpty ? others : const {},
      'robber' || 'troublemaker' => others,
      _ => const {},
    };
  }

  void _tapPlayer(int s) {
    setState(() {
      if (selP.contains(s)) {
        selP.remove(s);
        return;
      }
      final max = phase == 'night' && myCard == 'troublemaker' ? 2 : 1;
      if (selP.length >= max) selP.remove(selP.first);
      selP.add(s);
    });
  }

  Widget _seats() {
    final over = phase == 'over';
    final fin = (v['final'] as List?)?.cast<String>();
    final dealt = (v['dealt'] as List?)?.cast<String>();
    final deaths = onInts(v['deaths']).toSet();
    final votes = onInts(v['votes']);
    final winners = onBools(v['winners']);
    final ready = onBools(v['ready']);
    final voted = onBools(v['voted']);
    final wolves = onInts(v['wolves']).toSet();
    final hunter = onInts(v['hunterShots']).toSet();
    final myVote = v['myVote'];
    final seenP = {
      for (final x in (v['seen'] as List? ?? const []).cast<Map>())
        if (x['k'] == 'p') onInt(x['i']): x['role'] as String
    };
    final can = _selectablePlayers();
    return OnSeatGrid(
      g: g,
      selectable: can,
      selected: selP,
      onTap: _tapPlayer,
      badges: (s) => [
        if (over && fin != null) onBadge(onRoleNames[fin[s]] ?? '', onRoleColor(fin[s])),
        if (over && dealt != null && dealt[s] != fin?[s]) onBadge('原${onRoleNames[dealt[s]]}', Colors.grey.shade700),
        if (over && deaths.contains(s)) onBadge('出局', Colors.red.shade800, icon: Icons.close),
        if (over && hunter.contains(s)) onBadge('猎人开枪', Colors.green.shade800, icon: Icons.gps_fixed),
        if (over && s < winners.length && winners[s]) onBadge('胜', Colors.amber.shade800, icon: Icons.emoji_events),
        if (over && s < votes.length && votes[s] >= 0) onBadge('投${votes[s] + 1}号', Colors.blueGrey),
        if (!over && wolves.contains(s) && s != g.seat) onBadge('狼人', onRoleColor('werewolf')),
        if (!over && seenP[s] != null)
          onBadge(s == g.seat ? '现为${onRoleNames[seenP[s]]}' : '看到:${onRoleNames[seenP[s]]}', onRoleColor(seenP[s])),
        if (phase == 'day' && s < ready.length && ready[s]) onBadge('同意投票', Colors.teal),
        if (phase == 'vote' && s < voted.length && voted[s]) onBadge('已投票', Colors.teal),
        if (phase == 'vote' && myVote == s) onBadge('我的票', Colors.deepPurple),
      ],
    );
  }

  // ------------------------------------------------------------ center
  bool get _centerSelectable {
    if (!me || phase != 'night' || v['myActed'] == true) return false;
    return myCard == 'drunk' || (myCard == 'werewolf' && v['lone'] == true) || (myCard == 'seer' && selP.isEmpty);
  }

  Widget _center() {
    final fin = (v['final'] as List?)?.cast<String>();
    final seen = (v['seen'] as List? ?? const []).cast<Map>();
    final can = _centerSelectable;
    final n = g.players;
    return OnPanel(
      title: '中间的三张牌',
      icon: Icons.style,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          OnCard(
            role: fin != null
                ? fin[n + i]
                : seen.where((x) => x['k'] == 'c' && x['i'] == i).map((x) => x['role'] as String?).firstOrNull,
            label: '中间${i + 1}',
            selectable: can,
            selected: selC.contains(i),
            onTap: () => setState(() {
              if (selC.contains(i)) {
                selC.remove(i);
                return;
              }
              final max = myCard == 'seer' ? 2 : 1;
              if (selC.length >= max) selC.remove(selC.first);
              selC.add(i);
            }),
          ),
        ],
      ]),
    );
  }

  // ------------------------------------------------------------ role card
  Widget _roleCard() {
    final r = myCard;
    final cs = Theme.of(context).colorScheme;
    return OnPanel(
      title: '我的初始身份',
      icon: Icons.badge,
      border: hide ? null : onRoleColor(r),
      trailing: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: hide ? '显示身份' : '隐藏身份',
        icon: Icon(hide ? Icons.visibility : Icons.visibility_off, size: 20),
        onPressed: () => setState(() => hide = !hide),
      ),
      child: hide
          ? Text('身份已隐藏（点击右上角显示）', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OnCard(role: r, width: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(onRoleNames[r] ?? '', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: onRoleColor(r))),
                  const SizedBox(height: 2),
                  Text(onRoleDesc[r] ?? '', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text('注意：你的牌可能在夜里被别人换走', style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6))),
                ]),
              ),
            ]),
    );
  }

  // ------------------------------------------------------------ action
  Widget _action() {
    switch (phase) {
      case 'night':
        if (v['myActed'] == true) {
          return const OnPanel(child: Text('你已完成夜间行动，等待其他人……'));
        }
        return _nightPanel();
      case 'day':
        final mine = onBools(v['ready']);
        final r = g.seat < mine.length && mine[g.seat];
        return OnPanel(
          title: '讨论中（${onInt(v['dayMin'], 5)} 分钟）',
          icon: Icons.forum,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('说出（或隐瞒）你的身份和夜里得知的信息。所有人都同意后可以提前投票。', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 8),
            r
                ? OutlinedButton.icon(
                    onPressed: () => g.act({'type': 'ready', 'ready': false}),
                    icon: const Icon(Icons.undo),
                    label: const Text('取消提前投票'))
                : FilledButton.icon(
                    onPressed: () => g.act({'type': 'ready'}),
                    icon: const Icon(Icons.how_to_vote),
                    label: const Text('提前投票')),
          ]),
        );
      case 'vote':
        final mv = v['myVote'];
        if (mv != null) return OnPanel(child: Text('你投给了 ${onInt(mv) + 1}号 ${g.name(onInt(mv))}，等待其他人……'));
        return OnPanel(
          title: '投票',
          icon: Icons.how_to_vote,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(selP.isEmpty ? '点选一名玩家作为你的投票对象' : '投给 ${selP.first + 1}号 ${g.name(selP.first)}'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: selP.length == 1 ? () => g.act({'type': 'vote', 'target': selP.first}) : null,
              child: const Text('确认投票'),
            ),
          ]),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _nightPanel() {
    final r = myCard;
    String hint;
    Map<String, dynamic>? act;
    var canSkip = false;
    switch (r) {
      case 'werewolf':
        if (v['lone'] == true) {
          hint = '你是唯一的狼人，可以查看中间的一张牌';
          if (selC.length == 1) act = {'type': 'night', 'center': selC.first};
          canSkip = true;
        } else {
          hint = '睁眼确认你的狼人同伴';
          act = {'type': 'night'};
        }
      case 'minion':
        hint = '狼人请竖起大拇指……确认谁是狼人';
        act = {'type': 'night'};
      case 'seer':
        hint = '选择一名玩家，或中间的两张牌查看';
        if (selP.length == 1) act = {'type': 'night', 'target': selP.first};
        if (selC.length == 2) act = {'type': 'night', 'center': selC.toList()};
        canSkip = true;
      case 'robber':
        hint = '选择一名玩家交换牌，并查看你的新身份';
        if (selP.length == 1) act = {'type': 'night', 'target': selP.first};
        canSkip = true;
      case 'troublemaker':
        hint = '选择另外两名玩家，交换他们的牌';
        if (selP.length == 2) act = {'type': 'night', 'targets': selP.toList()};
        canSkip = true;
      case 'drunk':
        hint = '选择中间的一张牌与自己交换（看不到新身份）';
        if (selC.length == 1) act = {'type': 'night', 'center': selC.first};
      case 'insomniac':
        hint = '天亮前你会看到自己最终的牌';
        act = {'type': 'night'};
      default:
        hint = '你夜里没有行动，确认后继续';
        act = {'type': 'night'};
    }
    return OnPanel(
      title: '夜间行动',
      icon: Icons.nights_stay,
      border: Colors.indigoAccent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(hint, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: act == null ? null : () => g.act(act!),
              child: const Text('确认'),
            ),
          ),
          if (canSkip) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => g.act({'type': 'night', 'skip': true}), child: const Text('跳过')),
          ],
        ]),
      ]),
    );
  }

  Widget _info() {
    final info = (v['info'] as List? ?? const []).cast<String>();
    if (info.isEmpty) return const SizedBox.shrink();
    return OnPanel(
      title: '夜里我得知的信息',
      icon: Icons.lock,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final t in info) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $t', style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  Widget _deckInfo() {
    final deck = (v['deck'] as List? ?? const []).cast<String>();
    final counts = <String, int>{};
    for (final r in deck) {
      counts[r] = (counts[r] ?? 0) + 1;
    }
    return OnPanel(
      title: '本局角色（${deck.length} 张）',
      icon: Icons.list_alt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final e in counts.entries) onBadge('${onRoleNames[e.key]}${e.value > 1 ? '×${e.value}' : ''}', onRoleColor(e.key)),
        ]),
        const SizedBox(height: 6),
        const Text('夜间顺序：狼人 → 爪牙 → 预言家 → 强盗 → 捣蛋鬼 → 酒鬼 → 失眠者', style: TextStyle(fontSize: 11.5)),
      ]),
    );
  }

  // ------------------------------------------------------------ reveal
  Widget _reveal() {
    final log = (v['nightLog'] as List? ?? const []).cast<String>();
    final teams = (v['winTeams'] as List? ?? const []).cast<String>();
    const tn = {'village': '好人阵营', 'wolf': '狼人阵营', 'tanner': '皮匠'};
    return ResultBanner(
      teams.isEmpty ? '无人获胜' : '${teams.map((t) => tn[t]).join('、')} 获胜',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(v['reason'] as String? ?? '', style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 6),
        const Text('夜晚回放', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final t in log) Text('• $t', style: const TextStyle(fontSize: 12.5)),
      ]),
    );
  }
}
