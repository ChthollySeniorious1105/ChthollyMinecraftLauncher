import 'package:flutter/material.dart';

import '../../widgets/common.dart';

part 'werewolf_panels.dart';
part 'werewolf_actions.dart';

const wwRoleNames = {
  'wolf': '狼人',
  'wolfking': '狼王',
  'whiteWolfKing': '白狼王',
  'wolfBeauty': '狼美人',
  'hiddenWolf': '隐狼',
  'seer': '预言家',
  'witch': '女巫',
  'hunter': '猎人',
  'guard': '守卫',
  'idiot': '白痴',
  'knight': '骑士',
  'crow': '乌鸦',
  'magician': '魔术师',
  'cupid': '丘比特',
  'wildChild': '野孩子',
  'villager': '平民',
};

const wwRoleDesc = {
  'wolf': '每晚与同伴一起刀人；白天可以自爆，直接进入黑夜',
  'wolfking': '狼人阵营。自爆、被放逐或被决斗时可带走一名玩家（被刀、被毒不能）',
  'whiteWolfKing': '狼人阵营。白天可以自爆并带走一名玩家，随后直接进入黑夜',
  'wolfBeauty': '狼人阵营，与狼队一起刀人，每晚再魅惑一名玩家；你出局时被魅惑者随你殉情。不能自爆',
  'hiddenWolf': '狼人阵营。知道狼队是谁但不与他们睁眼、不能刀人，预言家查验为好人；其他狼人全部出局后变为普通狼人',
  'seer': '每晚查验一名玩家是好人还是狼人',
  'witch': '一瓶解药、一瓶毒药，同一晚只能用一瓶',
  'hunter': '出局时可开枪带走一人（被毒杀、殉情不能开枪）',
  'guard': '每晚守护一人免受狼刀，不能连续守同一人；同守同救会死亡',
  'idiot': '被放逐时翻牌免死，但之后不能投票',
  'knight': '白天发言阶段可翻牌与一人决斗（每局一次）：对方是狼人则对方出局并立即入夜，否则你以死谢罪',
  'crow': '每晚诅咒一名玩家，次日放逐投票时该玩家额外被计 1 票',
  'magician': '夜里最先行动，可交换两名玩家的号码，当晚所有技能作用于交换后的玩家；每人整局只能被交换一次',
  'cupid': '首夜连接两名玩家为情侣，一方出局另一方殉情；若是一狼一好人，你们三人组成第三方',
  'wildChild': '首夜选择一名榜样；榜样出局后你变成狼人，从下一晚起与狼人一起行动',
  'villager': '没有技能，靠推理和投票找出狼人',
};

const wwRoleIcons = {
  'wolf': Icons.pets,
  'wolfking': Icons.whatshot,
  'whiteWolfKing': Icons.local_fire_department,
  'wolfBeauty': Icons.face_retouching_natural,
  'hiddenWolf': Icons.visibility_off,
  'seer': Icons.visibility,
  'witch': Icons.science,
  'hunter': Icons.gps_fixed,
  'guard': Icons.shield,
  'idiot': Icons.sentiment_very_satisfied,
  'knight': Icons.security,
  'crow': Icons.flutter_dash,
  'magician': Icons.auto_fix_high,
  'cupid': Icons.favorite,
  'wildChild': Icons.child_care,
  'villager': Icons.person,
};

bool wwIsWolf(String? r) => const {'wolf', 'wolfking', 'whiteWolfKing', 'wolfBeauty', 'hiddenWolf'}.contains(r);

Color wwRoleColor(String? r) => switch (r) {
      'wolf' || 'wolfking' || 'whiteWolfKing' || 'wolfBeauty' || 'hiddenWolf' => const Color(0xFFD32F2F),
      'seer' => const Color(0xFF7B1FA2),
      'witch' => const Color(0xFF00897B),
      'hunter' => const Color(0xFFE65100),
      'guard' => const Color(0xFF1565C0),
      'idiot' => const Color(0xFFF9A825),
      'knight' => const Color(0xFF455A64),
      'crow' => const Color(0xFF37474F),
      'magician' => const Color(0xFF6A1B9A),
      'cupid' => const Color(0xFFD81B60),
      'wildChild' => const Color(0xFF8D6E63),
      'villager' => const Color(0xFF558B2F),
      _ => Colors.blueGrey,
    };

/// Night duties that pick two players.
const wwTwoPick = {'magic', 'link'};

List<int> wwInts(Object? o) => o is List ? [for (final e in o) (e as num).toInt()] : <int>[];
int wwInt(Object? o, [int d = -1]) => o is num ? o.toInt() : d;

class WerewolfBoard extends StatefulWidget {
  final GameContext g;
  const WerewolfBoard(this.g, {super.key});
  @override
  State<WerewolfBoard> createState() => _WerewolfBoardState();
}

class _WerewolfBoardState extends State<WerewolfBoard> {
  int? sel;
  int? sel2; // second pick (魔术师 / 丘比特)
  bool hideRole = false;
  final text = TextEditingController();
  // speech claim (for seers or anyone who wants to claim)
  bool claimWolf = false;
  String _selKey = '';

  GameContext get g => widget.g;
  Map<String, dynamic> get v => g.view;

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  /// Reset the selection whenever the situation changes.
  void _syncSel() {
    final n = v['night'] as Map?;
    final key = '${v['phase']}|${v['round']}|${v['task']}|${v['speaker']}|${v['speechKind']}|${n?['duty']}|${n?['charmDone']}|${n?['magicPending']}';
    if (key != _selKey) {
      _selKey = key;
      sel = null;
      sel2 = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncSel();
    final night = v['phase'] == 'night';
    final panels = _WwPanels(this);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final bg = BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: night
              ? const [Color(0xFF0B1030), Color(0xFF1B1F4B), Color(0xFF2A1E3F)]
              : const [Color(0xFFBFE3FF), Color(0xFFE9F5FF), Color(0xFFFFF4DC)],
        ),
      );
      final seats = _seatGrid(context, night);
      Widget body;
      if (wide) {
        body = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                panels.banner(context),
                const SizedBox(height: 10),
                seats,
                const SizedBox(height: 10),
                panels.lastVote(context),
                panels.reveal(context),
              ]),
            ),
          ),
          SizedBox(
            width: 360,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
              child: Column(children: [
                panels.roleCard(context),
                const SizedBox(height: 8),
                panels.actionPanel(context),
                panels.privateInfo(context),
                panels.logCard(context, maxLines: 14),
              ]),
            ),
          ),
        ]);
      } else {
        body = SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(children: [
            panels.banner(context),
            const SizedBox(height: 8),
            panels.roleCard(context),
            const SizedBox(height: 8),
            panels.actionPanel(context),
            seats,
            const SizedBox(height: 8),
            panels.lastVote(context),
            panels.reveal(context),
            panels.privateInfo(context),
            panels.logCard(context, maxLines: 8),
          ]),
        );
      }
      return AnimatedContainer(duration: const Duration(milliseconds: 600), decoration: bg, child: body);
    });
  }

  // ------------------------------------------------------------ seats

  /// Which seats can be tapped right now (target selection).
  Set<int> selectable() {
    final me = g.seat;
    if (me < 0 || g.over) return const {};
    final phase = v['phase'];
    final alive = (v['alive'] as List).cast<bool>();
    final aliveSet = {for (var s = 0; s < alive.length; s++) if (alive[s]) s};
    final night = v['night'] as Map?;
    final myRole = v['myRole'] as String?;
    switch (phase) {
      case 'night':
        if (night == null || night['done'] == true || !alive[me]) return const {};
        if (night['magicPending'] == true) return const {};
        switch (night['duty']) {
          case 'kill':
            if (myRole == 'wolfBeauty' && night['charmDone'] == false) return aliveSet.difference({me});
            return night['myVote'] == null && night['kill'] == null ? aliveSet : const {};
          case 'check':
          case 'model':
          case 'curse':
            return aliveSet.difference({me});
          case 'guard':
            return aliveSet.difference({wwInt(night['lastGuard'])});
          case 'witch':
            return v['poison'] == true && night['ready'] == true ? aliveSet.difference({me}) : const {};
          case 'magic':
            return aliveSet.difference(wwInts(night['swapped']).toSet());
          case 'link':
            return aliveSet;
        }
        return const {};
      case 'vote':
      case 'sheriff_vote':
        if (!wwInts(v['voters']).contains(me) || v['myVote'] != null) {
          return v['canExplode'] == true ? aliveSet.difference({me}) : const {};
        }
        return wwInts(v['voteCands']).toSet().difference({me});
      case 'task':
        if (wwInt(v['taskSeat']) != me) return const {};
        if (v['task'] == 'badge') return aliveSet;
        if (v['task'] == 'skill' && v['canShoot'] == true) return aliveSet.difference({me});
        return const {};
      case 'speech':
        if (wwInt(v['speaker']) == me) return {for (var s = 0; s < alive.length; s++) if (s != me) s};
        if (v['canDuel'] == true || v['canExplode'] == true) return aliveSet.difference({me});
        return const {};
      case 'direction':
      case 'sheriff_signup':
        if (v['canDuel'] == true || v['canExplode'] == true) return aliveSet.difference({me});
        return const {};
    }
    return const {};
  }

  Widget _seatGrid(BuildContext context, bool night) {
    final n = g.players;
    final can = selectable();
    final two = v['phase'] == 'night' && wwTwoPick.contains((v['night'] as Map?)?['duty']);
    void tap(int s) => setState(() {
          if (!two) {
            sel = sel == s ? null : s;
          } else if (sel == s) {
            sel = sel2;
            sel2 = null;
          } else if (sel2 == s) {
            sel2 = null;
          } else if (sel == null) {
            sel = s;
          } else {
            sel2 = s;
          }
        });
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 420 ? 3 : (c.maxWidth < 640 ? 4 : (n <= 8 ? 4 : 6));
      final w = ((c.maxWidth - (cols - 1) * 8) / cols).floorToDouble();
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (var s = 0; s < n; s++)
          SizedBox(
            width: w,
            child: _WwSeat(
              state: this,
              seat: s,
              night: night,
              selectable: can.contains(s),
              selected: sel == s || sel2 == s,
              onTap: can.contains(s) ? () => tap(s) : null,
            ),
          ),
      ]);
    });
  }

  void refresh(VoidCallback f) => setState(f);
}

/// One seat tile.
class _WwSeat extends StatelessWidget {
  final _WerewolfBoardState state;
  final int seat;
  final bool night;
  final bool selectable;
  final bool selected;
  final VoidCallback? onTap;
  const _WwSeat(
      {
      required this.state,
      required this.seat,
      required this.night,
      required this.selectable,
      required this.selected,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = state.g;
    final v = g.view;
    final cs = Theme.of(context).colorScheme;
    final s = seat;
    final alive = (v['alive'] as List)[s] == true;
    final role = (v['roles'] as List)[s] as String?;
    final sheriff = wwInt(v['sheriff']) == s;
    final speaking = wwInt(v['speaker']) == s || (v['phase'] == 'task' && wwInt(v['taskSeat']) == s);
    final me = g.seat == s;
    final phase = v['phase'];
    final voted = wwInts(v['voted']).contains(s);
    final voter = wwInts(v['voters']).contains(s);
    final cand = wwInts(v['candidates']).contains(s);
    final pk = wwInts(v['pk']).contains(s);
    final idiot = wwInts(v['idiot']).contains(s);
    final signed = wwInts(v['signed']).contains(s);
    final cause = (v['cause'] as List)[s] as String;
    final nightInfo = v['night'] as Map?;
    final wolfVoters = [
      for (final p in (nightInfo?['wolfVotes'] as List? ?? const []))
        if (wwInt((p as List)[1]) == s) wwInt(p[0])
    ];
    final wolfKill = nightInfo?['kill'];
    final checks = wwInts(v['checks']);
    bool? checked;
    for (var i = 0; i + 1 < checks.length; i += 2) {
      if (checks[i] == s) checked = checks[i + 1] == 1;
    }
    final victim = nightInfo?['victim'];
    final lover = wwInts(v['lovers']).contains(s);
    final crow = wwInt(v['crow']) == s || wwInt(v['myCurse']) == s;
    final charm = nightInfo?['charm'];
    final charmed = wwInt(v['charmed']) == s || (charm != null && wwInt(charm) == s);
    final model = wwInt(v['model']) == s;
    final swappedSeat = wwInts(v['swapped']).contains(s);

    final border = selected
        ? Colors.redAccent
        : (speaking ? Colors.greenAccent : (selectable ? cs.primary.withValues(alpha: 0.8) : cs.outline.withValues(alpha: 0.35)));
    final showRole = role != null && (!me || !state.hideRole);
    final bg = cs.surface.withValues(alpha: alive ? (night ? 0.82 : 0.92) : 0.5);

    final badges = <Widget>[
      if (sheriff) wwBadge('警长', Colors.amber.shade800, icon: Icons.local_police),
      if (showRole) wwBadge(wwRoleNames[role] ?? '', wwRoleColor(role)),
      if (!alive) wwBadge(_causeText(cause), Colors.grey.shade600),
      if (idiot) wwBadge('无投票权', Colors.grey.shade700),
      if (checked != null) wwBadge(checked ? '查杀' : '金水', checked ? Colors.red : Colors.green),
      if (lover) wwBadge('情侣', Colors.pink, icon: Icons.favorite),
      if (crow) wwBadge('乌鸦 +1票', Colors.blueGrey.shade700, icon: Icons.flutter_dash),
      if (charmed) wwBadge('魅惑', Colors.pink.shade700),
      if (model) wwBadge('榜样', Colors.brown),
      if (swappedSeat) wwBadge('已交换', Colors.purple),
      if (phase == 'sheriff_signup' && signed) wwBadge('已选择', Colors.teal),
      if (cand && (phase == 'speech' || phase == 'sheriff_vote')) wwBadge('警上', Colors.indigo),
      if (pk && alive) wwBadge('PK', Colors.deepOrange),
      if ((phase == 'vote' || phase == 'sheriff_vote') && voter && voted) wwBadge('已投', Colors.teal),
      if (wolfVoters.isNotEmpty) wwBadge('刀 ${wolfVoters.map((w) => w + 1).join(',')}号', Colors.red.shade700),
      if (wolfKill == s) wwBadge('今晚目标', Colors.red.shade900),
      if (victim == s) wwBadge('被刀', Colors.red.shade900),
      if (speaking) wwBadge(phase == 'task' ? '操作中' : '发言中', Colors.green.shade700, icon: Icons.mic),
    ];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected ? Color.alphaBlend(Colors.redAccent.withValues(alpha: 0.18), bg) : bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border, width: selected || speaking ? 2.5 : (selectable ? 1.8 : 1)),
          boxShadow: [
            if (speaking) const BoxShadow(color: Colors.greenAccent, blurRadius: 10),
            if (!speaking) BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Avatar(g.avatar(s), size: 34, bot: g.bot(s), dim: !alive, speaking: speaking),
              Positioned(
                left: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: me ? cs.primary : Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${s + 1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: me ? cs.onPrimary : Colors.white)),
                ),
              ),
              if (!alive)
                const Positioned.fill(child: Center(child: Icon(Icons.close, color: Colors.redAccent, size: 30))),
            ]),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${s + 1}号${me ? '（我）' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cs.onSurface)),
                Text(g.name(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.7),
                        decoration: alive ? null : TextDecoration.lineThrough)),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 18),
            child: Wrap(spacing: 3, runSpacing: 3, children: badges),
          ),
        ]),
      ),
    );
  }

  static String _causeText(String c) => switch (c) {
        'night' => '夜里出局',
        'wolf' => '被狼刀',
        'poison' => '被毒杀',
        'exile' => '被放逐',
        'shot' => '被带走',
        'explode' => '自爆',
        'duel' => '被决斗',
        'knight' => '决斗失败',
        'love' => '殉情',
        'charm' => '魅惑殉情',
        _ => '出局',
      };
}

Widget wwBadge(String t, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.75)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) Icon(icon, size: 11, color: c),
        Flexible(
          child: Text(t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: 10.5, color: c, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
