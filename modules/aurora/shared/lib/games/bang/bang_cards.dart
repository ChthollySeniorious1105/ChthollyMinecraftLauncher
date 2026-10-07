/// Card / character catalogue for 西部无间道 (Bang!), shared by engine and client.
class BangCard {
  final String kind;

  /// 'S' ♠ / 'H' ♥ / 'D' ♦ / 'C' ♣
  final String suit;

  /// 2..10, 11 J, 12 Q, 13 K, 14 A
  final int rank;
  const BangCard(this.kind, this.suit, this.rank);
}

List<BangCard> _build() {
  final out = <BangCard>[];
  void add(String k, String s, Iterable<int> ranks) {
    for (final r in ranks) {
      out.add(BangCard(k, s, r));
    }
  }

  Iterable<int> span(int a, int b) => [for (var r = a; r <= b; r++) r];
  // brown (63)
  add('bang', 'S', [14]);
  add('bang', 'D', span(2, 14));
  add('bang', 'C', span(2, 9));
  add('bang', 'H', [12, 13, 14]);
  add('missed', 'C', span(10, 14));
  add('missed', 'S', span(2, 8));
  add('beer', 'H', span(6, 11));
  add('saloon', 'H', [5]);
  add('stagecoach', 'S', [9, 9]);
  add('wellsfargo', 'H', [3]);
  add('store', 'C', [9]);
  add('store', 'S', [12]);
  add('duel', 'D', [12]);
  add('duel', 'S', [11]);
  add('duel', 'C', [8]);
  add('gatling', 'H', [10]);
  add('indians', 'D', [13, 14]);
  add('panic', 'H', [11, 12, 14]);
  add('panic', 'D', [8]);
  add('catbalou', 'H', [13]);
  add('catbalou', 'D', [9, 10, 11]);
  // blue (17)
  add('barrel', 'S', [12, 13]);
  add('dynamite', 'H', [2]);
  add('jail', 'S', [10, 11]);
  add('jail', 'H', [4]);
  add('mustang', 'H', [8, 9]);
  add('scope', 'S', [14]);
  add('volcanic', 'S', [10]);
  add('volcanic', 'C', [10]);
  add('schofield', 'C', [11, 12]);
  add('schofield', 'S', [13]);
  add('remington', 'C', [13]);
  add('carabine', 'C', [14]);
  add('winchester', 'S', [8]);
  return out;
}

/// The 80-card base deck; a card's id is its index.
final List<BangCard> bangDeck = _build();

const Map<String, String> bangKindName = {
  'bang': 'BANG!',
  'missed': '闪避',
  'beer': '啤酒',
  'saloon': '酒馆',
  'stagecoach': '驿站',
  'wellsfargo': '富国银行',
  'store': '杂货铺',
  'duel': '决斗',
  'gatling': '加特林',
  'indians': '印第安人',
  'panic': '惊慌',
  'catbalou': '卡特巴卢',
  'barrel': '酒桶',
  'dynamite': '炸药',
  'jail': '监狱',
  'mustang': '野马',
  'scope': '瞄准镜',
  'volcanic': '火山连发',
  'schofield': '斯科菲尔德',
  'remington': '雷明顿',
  'carabine': '卡宾枪',
  'winchester': '温彻斯特',
};

const Map<String, String> bangKindEmoji = {
  'bang': '💥',
  'missed': '💨',
  'beer': '🍺',
  'saloon': '🍻',
  'stagecoach': '🐎',
  'wellsfargo': '💰',
  'store': '🏪',
  'duel': '🤺',
  'gatling': '🔥',
  'indians': '🏹',
  'panic': '😱',
  'catbalou': '👢',
  'barrel': '🛢️',
  'dynamite': '🧨',
  'jail': '🔒',
  'mustang': '🏇',
  'scope': '🔭',
  'volcanic': '🌋',
  'schofield': '🔫',
  'remington': '🔫',
  'carabine': '🔫',
  'winchester': '🔫',
};

const Map<String, String> bangKindDesc = {
  'bang': '射击射程内一名玩家，对方需打出闪避，否则失去 1 点生命。每回合限 1 张',
  'missed': '被 BANG! 或加特林攻击时打出，抵消这次射击',
  'beer': '回复 1 点生命；濒死时自动使用。只剩 2 人时无效',
  'saloon': '所有存活玩家回复 1 点生命',
  'stagecoach': '摸 2 张牌',
  'wellsfargo': '摸 3 张牌',
  'store': '翻开存活人数张牌，从你开始每人依次挑 1 张',
  'duel': '与任意一名玩家轮流弃 BANG!，先弃不出的人失去 1 点生命',
  'gatling': '射击所有其他玩家，每人需打出闪避',
  'indians': '所有其他玩家需弃一张 BANG!，否则失去 1 点生命',
  'panic': '拿走距离 1 以内一名玩家的一张牌（手牌或装备）',
  'catbalou': '弃掉任意一名玩家的一张牌（手牌或装备）',
  'barrel': '被射击时判定，红心 ♥ 视为闪避',
  'dynamite': '放在自己面前，回合开始判定：♠2~9 爆炸失去 3 生命，否则传给下家',
  'jail': '关押警长以外的玩家：回合开始判定，红心 ♥ 越狱，否则跳过回合',
  'mustang': '别人看你的距离 +1',
  'scope': '你看别人的距离 -1',
  'volcanic': '射程 1，可以无限使用 BANG!',
  'schofield': '射程 2',
  'remington': '射程 3',
  'carabine': '射程 4',
  'winchester': '射程 5',
};

const Map<String, int> bangWeaponRange = {'volcanic': 1, 'schofield': 2, 'remington': 3, 'carabine': 4, 'winchester': 5};

const Set<String> bangBlueKinds = {
  'barrel', 'dynamite', 'jail', 'mustang', 'scope', 'volcanic', 'schofield', 'remington', 'carabine', 'winchester'
};

const Map<String, String> bangSuitSym = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

String bangRankLabel(int r) => switch (r) { 11 => 'J', 12 => 'Q', 13 => 'K', 14 => 'A', _ => '$r' };

String bangCardLabel(int id) {
  if (id < 0 || id >= bangDeck.length) return '?';
  final c = bangDeck[id];
  return '${bangKindName[c.kind]}${bangSuitSym[c.suit]}${bangRankLabel(c.rank)}';
}

class BangChar {
  final String key;
  final String name;
  final int hp;
  final String emoji;
  final String desc;
  const BangChar(this.key, this.name, this.hp, this.emoji, this.desc);
}

const List<BangChar> bangChars = [
  BangChar('bart', '巴特·卡西迪', 4, '🤠', '每失去 1 点生命，就从牌堆摸 1 张牌'),
  BangChar('blackjack', '黑杰克', 4, '🃏', '摸牌阶段亮出第 2 张牌，若是红心或方块，再摸 1 张'),
  BangChar('calamity', '灾难珍妮', 4, '👩', 'BANG! 与闪避可以互相当作对方使用'),
  BangChar('elgringo', '艾尔·格林戈', 3, '🧔', '每被其他玩家造成 1 点伤害，就从对方手牌随机抽 1 张'),
  BangChar('jesse', '杰西·琼斯', 4, '🎩', '摸牌阶段第 1 张可以改为从任意玩家手牌随机抽取'),
  BangChar('jourdonnais', '乔尔多内', 4, '🛢️', '自带一个酒桶（可与酒桶装备叠加判定）'),
  BangChar('kit', '基特·卡尔森', 4, '🔎', '摸牌阶段看牌堆顶 3 张，留下 2 张，另一张放回牌堆顶'),
  BangChar('lucky', '幸运杜克', 4, '🍀', '“拔枪！”判定时翻开 2 张，取对自己有利的一张'),
  BangChar('paul', '保罗·瑞格瑞特', 3, '🐴', '自带野马：别人看你的距离 +1'),
  BangChar('pedro', '佩德罗·拉米雷斯', 4, '🌮', '摸牌阶段第 1 张可以改为拿弃牌堆顶的牌'),
  BangChar('rose', '罗丝·杜兰', 4, '🌹', '自带瞄准镜：你看别人的距离 -1'),
  BangChar('sid', '席德·凯臣', 4, '💊', '随时可以弃 2 张手牌回复 1 点生命（濒死时自动发动）'),
  BangChar('slab', '杀手斯莱伯', 4, '💀', '他打出的 BANG! 需要 2 张闪避才能抵消'),
  BangChar('suzy', '苏西·拉法叶', 4, '💃', '手牌为空时立即摸 1 张牌'),
  BangChar('vulture', '秃鹫山姆', 4, '🦅', '有玩家死亡时，拿走他所有的手牌和装备'),
  BangChar('willy', '小子威利', 4, '🔫', '回合内可以使用任意张 BANG!'),
];

const Map<String, String> bangRoleName = {'sheriff': '警长', 'deputy': '副警长', 'outlaw': '歹徒', 'renegade': '叛徒'};
const Map<String, String> bangRoleEmoji = {'sheriff': '⭐', 'deputy': '🔰', 'outlaw': '🦹', 'renegade': '🐍'};

/// Standard role distribution for 4..7 players.
List<String> bangRolesFor(int n) => [
      'sheriff',
      'renegade',
      'outlaw',
      'outlaw',
      if (n >= 5) 'deputy',
      if (n >= 6) 'outlaw',
      if (n >= 7) 'deputy',
    ];
