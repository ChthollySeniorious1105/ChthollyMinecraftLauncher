/// 七大奇迹·对决 card / wonder / progress-token data.
///
/// Resources: 0 木 W, 1 砖 C (clay), 2 石 S, 3 玻璃 G, 4 纸 P (papyrus).
/// Science symbols: 0 浑天仪 1 车轮 2 日晷 3 研钵 4 矩尺 5 羽笔 6 天秤(法律，仅进步标记).
library;

const duelResNames = ['木材', '黏土', '石料', '玻璃', '莎草纸'];
const duelResShort = ['木', '土', '石', '玻', '纸'];
const duelSciNames = ['浑天仪', '车轮', '日晷', '研钵', '矩尺', '羽笔', '天秤'];
const duelSciShort = ['仪', '轮', '晷', '钵', '尺', '笔', '律'];

/// Card kinds.
const duelKinds = ['brown', 'grey', 'blue', 'green', 'yellow', 'red', 'guild'];
const duelKindNames = {
  'brown': '原料', 'grey': '加工品', 'blue': '市政', 'green': '科技', 'yellow': '商业', 'red': '军事', 'guild': '行会',
};

List<int> _res(String s) {
  final r = List.filled(5, 0);
  for (final ch in s.split('')) {
    final i = 'WCSGP'.indexOf(ch);
    if (i >= 0) r[i]++;
  }
  return r;
}

class DuelCard {
  final String name;
  final int age; // 1..3 (guilds: 3)
  final String kind;
  final int coins; // coin cost
  final List<int> cost;
  final List<int> prod; // fixed production
  final List<int> choice; // one-of production (yellow)
  final int vp;
  final int shields;
  final int sci; // -1 none
  final String link; // chain symbol this card provides
  final String chain; // chain symbol that makes it free
  final String fx; // special effect id
  final String text; // effect description
  DuelCard(this.name, this.age, this.kind,
      {this.coins = 0,
      String cost = '',
      String prod = '',
      this.choice = const [],
      this.vp = 0,
      this.shields = 0,
      this.sci = -1,
      this.link = '',
      this.chain = '',
      this.fx = '',
      this.text = ''})
      : cost = _res(cost),
        prod = _res(prod);

  bool get isGuild => kind == 'guild';
}

final List<DuelCard> duelCards = [
  // ---------------------------------------------------------------- Age I (0..22)
  DuelCard('伐木场', 1, 'brown', prod: 'W'),
  DuelCard('伐木营地', 1, 'brown', coins: 1, prod: 'W'),
  DuelCard('黏土池', 1, 'brown', prod: 'C'),
  DuelCard('黏土坑', 1, 'brown', coins: 1, prod: 'C'),
  DuelCard('采石场', 1, 'brown', prod: 'S'),
  DuelCard('石坑', 1, 'brown', coins: 1, prod: 'S'),
  DuelCard('玻璃工坊', 1, 'grey', coins: 1, prod: 'G'),
  DuelCard('造纸坊', 1, 'grey', coins: 1, prod: 'P'),
  DuelCard('瞭望塔', 1, 'red', shields: 1),
  DuelCard('马厩', 1, 'red', cost: 'W', shields: 1, link: '马蹄'),
  DuelCard('驻军', 1, 'red', cost: 'C', shields: 1, link: '剑'),
  DuelCard('栅栏', 1, 'red', coins: 2, shields: 1, link: '塔'),
  DuelCard('作坊', 1, 'green', cost: 'P', vp: 1, sci: 4),
  DuelCard('药剂坊', 1, 'green', cost: 'G', vp: 1, sci: 1),
  DuelCard('缮写室', 1, 'green', coins: 2, sci: 5, link: '书'),
  DuelCard('药房', 1, 'green', coins: 2, sci: 3, link: '齿轮'),
  DuelCard('剧场', 1, 'blue', vp: 3, link: '面具'),
  DuelCard('祭坛', 1, 'blue', vp: 3, link: '月'),
  DuelCard('浴场', 1, 'blue', cost: 'S', vp: 3, link: '水滴'),
  DuelCard('石料储备', 1, 'yellow', coins: 3, fx: 'fixS', text: '石料交易价固定为 1'),
  DuelCard('黏土储备', 1, 'yellow', coins: 3, fx: 'fixC', text: '黏土交易价固定为 1'),
  DuelCard('木材储备', 1, 'yellow', coins: 3, fx: 'fixW', text: '木材交易价固定为 1'),
  DuelCard('酒馆', 1, 'yellow', fx: 'coins4', link: '酒壶', text: '获得 4 金币'),
  // ---------------------------------------------------------------- Age II (23..45)
  DuelCard('锯木厂', 2, 'brown', coins: 2, prod: 'WW'),
  DuelCard('砖厂', 2, 'brown', coins: 2, prod: 'CC'),
  DuelCard('层岩采石场', 2, 'brown', coins: 2, prod: 'SS'),
  DuelCard('吹玻璃坊', 2, 'grey', prod: 'G'),
  DuelCard('晾纸房', 2, 'grey', prod: 'P'),
  DuelCard('法院', 2, 'blue', cost: 'WWG', vp: 5),
  DuelCard('雕像', 2, 'blue', cost: 'CC', vp: 4, chain: '面具', link: '石柱'),
  DuelCard('神庙', 2, 'blue', cost: 'WP', vp: 4, chain: '月', link: '太阳'),
  DuelCard('引水渠', 2, 'blue', cost: 'SSS', vp: 5, chain: '水滴'),
  DuelCard('讲坛', 2, 'blue', cost: 'SW', vp: 4, link: '殿堂'),
  DuelCard('城墙', 2, 'red', cost: 'SS', shields: 2),
  DuelCard('养马场', 2, 'red', cost: 'CW', shields: 1, chain: '马蹄'),
  DuelCard('兵营', 2, 'red', coins: 3, shields: 1, chain: '剑'),
  DuelCard('靶场', 2, 'red', cost: 'SWP', shields: 2, link: '箭靶'),
  DuelCard('阅兵场', 2, 'red', cost: 'CCG', shields: 2, link: '头盔'),
  DuelCard('图书馆', 2, 'green', cost: 'SWG', vp: 2, sci: 5, chain: '书'),
  DuelCard('诊所', 2, 'green', cost: 'CCS', vp: 2, sci: 3, chain: '齿轮'),
  DuelCard('学校', 2, 'green', cost: 'WPP', vp: 1, sci: 1, link: '竖琴'),
  DuelCard('实验室', 2, 'green', cost: 'WGG', vp: 1, sci: 4, link: '油灯'),
  DuelCard('广场', 2, 'yellow', coins: 3, cost: 'C', choice: [3, 4], text: '每回合产出 玻璃/纸 之一'),
  DuelCard('商队旅馆', 2, 'yellow', coins: 2, cost: 'GP', choice: [0, 1, 2], text: '每回合产出 木/土/石 之一'),
  DuelCard('海关', 2, 'yellow', coins: 4, fx: 'fixGP', text: '玻璃与纸交易价固定为 1'),
  DuelCard('酿酒厂', 2, 'yellow', fx: 'coins6', link: '酒桶', text: '获得 6 金币'),
  // ---------------------------------------------------------------- Age III (46..65)
  DuelCard('元老院', 3, 'blue', cost: 'CCSP', vp: 5, chain: '殿堂'),
  DuelCard('市政厅', 3, 'blue', cost: 'SSSWW', vp: 7),
  DuelCard('方尖碑', 3, 'blue', cost: 'SSG', vp: 5),
  DuelCard('花园', 3, 'blue', cost: 'CCWW', vp: 6, chain: '石柱'),
  DuelCard('万神殿', 3, 'blue', cost: 'CWPP', vp: 6, chain: '太阳'),
  DuelCard('宫殿', 3, 'blue', cost: 'CSWGG', vp: 7),
  DuelCard('军械库', 3, 'red', cost: 'CCCWW', shields: 3),
  DuelCard('禁卫军营', 3, 'red', coins: 8, shields: 3),
  DuelCard('要塞', 3, 'red', cost: 'SSCP', shields: 2, chain: '塔'),
  DuelCard('攻城工坊', 3, 'red', cost: 'WWWG', shields: 2, chain: '箭靶'),
  DuelCard('竞技场', 3, 'red', cost: 'CCSS', shields: 2, chain: '头盔'),
  DuelCard('学院', 3, 'green', cost: 'SWGG', vp: 3, sci: 2),
  DuelCard('书房', 3, 'green', cost: 'WWGP', vp: 3, sci: 2),
  DuelCard('大学', 3, 'green', cost: 'CGP', vp: 2, sci: 0, chain: '竖琴'),
  DuelCard('天文台', 3, 'green', cost: 'SPP', vp: 2, sci: 0, chain: '油灯'),
  DuelCard('商会', 3, 'yellow', cost: 'PP', vp: 3, fx: 'perGrey3', text: '每张灰卡获得 3 金币'),
  DuelCard('港口', 3, 'yellow', cost: 'WGP', vp: 3, fx: 'perBrown2', text: '每张棕卡获得 2 金币'),
  DuelCard('兵工厂', 3, 'yellow', cost: 'SSG', vp: 3, fx: 'perRed1', text: '每张红卡获得 1 金币'),
  DuelCard('灯塔', 3, 'yellow', cost: 'CCG', vp: 3, fx: 'perYellow1', chain: '酒壶', text: '每张黄卡获得 1 金币'),
  DuelCard('角斗场', 3, 'yellow', cost: 'CSW', vp: 3, fx: 'perWonder2', chain: '酒桶', text: '每座奇迹获得 2 金币'),
  // ---------------------------------------------------------------- Guilds (66..72)
  DuelCard('商人行会', 3, 'guild', cost: 'CWGP', fx: 'gYellow', text: '黄卡最多的城市：每张黄卡 1 金币（建造时）与 1 分（终局）'),
  DuelCard('船主行会', 3, 'guild', cost: 'CSGP', fx: 'gBrownGrey', text: '棕+灰卡最多的城市：每张 1 金币与 1 分'),
  DuelCard('建筑师行会', 3, 'guild', cost: 'SSCWG', fx: 'gWonder', text: '奇迹最多的城市：每座奇迹 2 分'),
  DuelCard('执政官行会', 3, 'guild', cost: 'WWCP', fx: 'gBlue', text: '蓝卡最多的城市：每张蓝卡 1 金币与 1 分'),
  DuelCard('学者行会', 3, 'guild', cost: 'CCWW', fx: 'gGreen', text: '绿卡最多的城市：每张绿卡 1 金币与 1 分'),
  DuelCard('放贷人行会', 3, 'guild', cost: 'SSWW', fx: 'gCoins', text: '金币最多的城市：每 3 金币 1 分'),
  DuelCard('战术家行会', 3, 'guild', cost: 'SSCP', fx: 'gRed', text: '红卡最多的城市：每张红卡 1 金币与 1 分'),
];

const int duelGuildStart = 66;

class DuelWonder {
  final String name;
  final List<int> cost;
  final int vp;
  final int shields;
  final bool replay;
  final String fx;
  final String text;
  DuelWonder(this.name, String cost, {this.vp = 0, this.shields = 0, this.replay = false, this.fx = '', this.text = ''})
      : cost = _res(cost);
}

final List<DuelWonder> duelWonders = [
  DuelWonder('亚壁古道', 'PPCCSSS', vp: 3, replay: true, fx: 'appian', text: '获得 3 金币，对手失去 3 金币；再行动一回合'),
  DuelWonder('大竞技场', 'GWSS', vp: 3, shields: 1, fx: 'destroyGrey', text: '摧毁对手一张灰卡；1 盾'),
  DuelWonder('罗德岛巨像', 'GCCC', vp: 3, shields: 2, text: '2 盾'),
  DuelWonder('亚历山大图书馆', 'PGWWW', vp: 4, fx: 'library', text: '从未使用的进步标记中随机抽 3 个，选 1 个'),
  DuelWonder('亚历山大灯塔', 'PPSW', vp: 4, fx: 'choiceWCS', text: '每回合产出 木/土/石 之一'),
  DuelWonder('空中花园', 'PGWW', vp: 3, replay: true, fx: 'coins6', text: '获得 6 金币；再行动一回合'),
  DuelWonder('摩索拉斯陵墓', 'GGCCP', vp: 2, fx: 'mausoleum', text: '从弃牌堆免费建造一张卡'),
  DuelWonder('比雷埃夫斯港', 'WWSC', vp: 2, replay: true, fx: 'choiceGP', text: '每回合产出 玻璃/纸 之一；再行动一回合'),
  DuelWonder('金字塔', 'PSSS', vp: 9, text: '9 分'),
  DuelWonder('狮身人面像', 'GGCS', vp: 6, replay: true, text: '再行动一回合'),
  DuelWonder('宙斯神像', 'PPCWS', vp: 3, shields: 1, fx: 'destroyBrown', text: '摧毁对手一张棕卡；1 盾'),
  DuelWonder('阿尔忒弥斯神庙', 'PGSW', replay: true, fx: 'coins12', text: '获得 12 金币；再行动一回合'),
];

class DuelToken {
  final String id, name, text;
  const DuelToken(this.id, this.name, this.text);
}

const List<DuelToken> duelTokens = [
  DuelToken('agriculture', '农业', '获得 6 金币；4 分'),
  DuelToken('architecture', '建筑学', '之后建造奇迹少付 2 个资源'),
  DuelToken('economy', '经济', '对手交易付给银行的金币归你'),
  DuelToken('law', '法律', '一个科学符号（天秤）'),
  DuelToken('masonry', '石工', '之后建造蓝卡少付 2 个资源'),
  DuelToken('mathematics', '数学', '终局每个进步标记 3 分（含本标记）'),
  DuelToken('philosophy', '哲学', '7 分'),
  DuelToken('strategy', '战略', '之后每张红卡额外 +1 盾'),
  DuelToken('theology', '神学', '之后建造的奇迹都有“再行动一回合”'),
  DuelToken('urbanism', '城市规划', '获得 6 金币；之后每次连锁免费建造获得 4 金币'),
];

int duelTokenIndex(String id) => duelTokens.indexWhere((t) => t.id == id);

/// Structure layouts: per row (from the top / back of the pyramid) the card
/// centre x positions (cards are 2 units wide; |dx| == 1 overlaps).
const List<List<List<int>>> duelLayouts = [
  [
    [4, 6], [3, 5, 7], [2, 4, 6, 8], [1, 3, 5, 7, 9], [0, 2, 4, 6, 8, 10],
  ],
  [
    [0, 2, 4, 6, 8, 10], [1, 3, 5, 7, 9], [2, 4, 6, 8], [3, 5, 7], [4, 6],
  ],
  [
    [2, 4], [1, 3, 5], [0, 2, 4, 6], [1, 5], [0, 2, 4, 6], [1, 3, 5], [2, 4],
  ],
];

/// Rows dealt face-down per age.
const List<Set<int>> duelDownRows = [
  {1, 3},
  {1, 3},
  {1, 3, 5},
];
