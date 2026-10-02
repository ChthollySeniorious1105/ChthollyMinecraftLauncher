/// 狼人杀 roles & boards.
library;

const werewolfRoleNames = {
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

const werewolfRoleDesc = {
  'wolf': '每晚与同伴商量击杀一名玩家；白天可自爆直接进入黑夜',
  'wolfking': '狼人阵营。白天自爆时可带走一名玩家；被放逐、被决斗或被猎人带走时（非毒杀）也可带走一人',
  'whiteWolfKing': '狼人阵营。白天可以自爆并带走一名玩家，随后直接进入黑夜；其他方式出局不能带人',
  'wolfBeauty': '狼人阵营，与狼人一起刀人。每晚额外魅惑一名玩家；狼美人出局时，被魅惑者随她殉情（不能发动技能）',
  'hiddenWolf': '狼人阵营。知道狼人是谁，但不与狼人一起睁眼、不能刀人，被预言家查验为好人；其他狼人全部出局后变为普通狼人可以刀人',
  'seer': '每晚查验一名玩家是好人还是狼人',
  'witch': '一瓶解药、一瓶毒药，同一晚不能同时使用',
  'hunter': '出局时可开枪带走一名玩家（被毒杀、殉情时不能开枪）',
  'guard': '每晚守护一名玩家免于狼刀，不能连续两晚守同一人；同守同救则死亡',
  'idiot': '被放逐时翻牌免死，但此后失去投票权',
  'knight': '神职。白天放逐投票前可翻牌与一名玩家决斗（每局一次）：对方是狼人则对方出局并立即入夜；否则骑士以死谢罪',
  'crow': '神职。每晚诅咒一名玩家，次日放逐投票时该玩家额外被计 1 票',
  'magician': '神职，夜里最先行动。每晚可交换两名玩家的号码，当晚所有技能作用于交换后的玩家；每名玩家整局只能被交换一次',
  'cupid': '首夜连接两名玩家成为情侣，情侣一方出局另一方殉情。若情侣是一狼一好人，情侣与丘比特组成第三方，需其他人全部出局才获胜',
  'wildChild': '平民阵营。首夜选择一名玩家作为榜样；榜样出局后野孩子变成狼人，从下一晚开始与狼人一起行动',
  'villager': '没有技能，靠发言和投票找出狼人',
};

/// Roles that belong to the wolf camp from the start (the wild child may join later).
bool werewolfIsWolf(String r) => const {'wolf', 'wolfking', 'whiteWolfKing', 'wolfBeauty', 'hiddenWolf'}.contains(r);
bool werewolfIsGod(String r) =>
    const {'seer', 'witch', 'hunter', 'guard', 'idiot', 'knight', 'crow', 'magician', 'cupid'}.contains(r);

/// Board option values.
const werewolfBoards = {
  'auto': '自动（按人数）',
  'ylbai12': '预女猎白 12人',
  'ylshou12': '预女猎守 12人',
  'wkguard12': '狼王守卫 12人',
  'wwkKnight12': '白狼王骑士 12人',
  'beautyKnight12': '狼美人骑士 12人',
  'magicCrow12': '魔术师乌鸦 12人',
  'cupid10': '丘比特情侣 10人',
  'hiddenWild10': '隐狼野孩子 10人',
  'nine': '9人局',
  'six': '6人局',
};

(int, int) werewolfRange(String board) => switch (board) {
      'ylbai12' || 'ylshou12' || 'wkguard12' || 'wwkKnight12' || 'beautyKnight12' || 'magicCrow12' => (12, 12),
      'cupid10' || 'hiddenWild10' => (10, 10),
      'nine' => (9, 9),
      'six' => (6, 6),
      _ => (6, 12),
    };

List<String> _mk(int wolves, List<String> gods, int villagers, {List<String> special = const []}) => [
      ...special,
      for (var i = 0; i < wolves - special.length; i++) 'wolf',
      ...gods,
      for (var i = 0; i < villagers; i++) 'villager',
    ];

/// Unshuffled role list for [board] with [n] players.
List<String> werewolfRoles(String board, int n) {
  switch (board) {
    case 'ylbai12':
      return _mk(4, ['seer', 'witch', 'hunter', 'idiot'], 4);
    case 'ylshou12':
      return _mk(4, ['seer', 'witch', 'hunter', 'guard'], 4);
    case 'wkguard12':
      return _mk(4, ['seer', 'witch', 'hunter', 'guard'], 4, special: ['wolfking']);
    case 'wwkKnight12':
      return _mk(4, ['seer', 'witch', 'hunter', 'knight'], 4, special: ['whiteWolfKing']);
    case 'beautyKnight12':
      return _mk(4, ['seer', 'witch', 'guard', 'knight'], 4, special: ['wolfBeauty']);
    case 'magicCrow12':
      return _mk(4, ['magician', 'seer', 'witch', 'crow'], 4);
    case 'cupid10':
      return _mk(3, ['cupid', 'seer', 'witch', 'hunter'], 3);
    case 'hiddenWild10':
      return [..._mk(3, ['seer', 'witch', 'hunter'], 3, special: ['hiddenWolf']), 'wildChild'];
    case 'nine':
      return _mk(3, ['seer', 'witch', 'hunter'], 3);
    case 'six':
      return _mk(2, ['seer', 'witch'], 2);
  }
  return switch (n) {
    <= 6 => _mk(2, ['seer', 'witch'], 2),
    7 => _mk(2, ['seer', 'witch', 'hunter'], 2),
    8 => _mk(3, ['seer', 'witch', 'hunter'], 2),
    9 => _mk(3, ['seer', 'witch', 'hunter'], 3),
    10 => _mk(3, ['seer', 'witch', 'hunter', 'idiot'], 3),
    11 => _mk(4, ['seer', 'witch', 'hunter', 'idiot'], 3),
    _ => _mk(4, ['seer', 'witch', 'hunter', 'idiot'], 4),
  };
}

/// "4狼 预女猎白 4民" style summary.
String werewolfBoardSummary(List<String> roles) {
  final wolves = roles.where(werewolfIsWolf).length;
  final special = [
    for (final r in ['wolfking', 'whiteWolfKing', 'wolfBeauty', 'hiddenWolf'])
      if (roles.contains(r)) werewolfRoleNames[r]!
  ];
  const godShort = {
    'magician': '魔术师',
    'cupid': '丘比特',
    'seer': '预',
    'witch': '女',
    'hunter': '猎',
    'idiot': '白',
    'guard': '守',
    'knight': '骑',
    'crow': '乌鸦',
  };
  final gods = [
    for (final e in godShort.entries)
      if (roles.contains(e.key)) e.value
  ].join();
  final v = roles.where((r) => r == 'villager').length;
  final wild = roles.contains('wildChild') ? ' 野孩子' : '';
  return '$wolves狼${special.isEmpty ? '' : '(含${special.join('、')})'} $gods $v民$wild';
}
