/// 大富翁 static board data (shared by the engine and the client UI).
library;

enum SqType { go, street, station, utility, tax, chance, chest, jail, parking, goToJail }

class Sq {
  final String name;
  final SqType type;

  /// Colour group 0..7 for streets, -1 otherwise.
  final int group;
  final int price;

  /// Streets: [base, 1 house, 2, 3, 4, hotel]. Tax squares: [amount].
  final List<int> rents;
  final int houseCost;
  const Sq(this.name, this.type, {this.group = -1, this.price = 0, this.rents = const [], this.houseCost = 0});

  bool get ownable => type == SqType.street || type == SqType.station || type == SqType.utility;
  int get mortgage => price ~/ 2;
  int get unmortgageCost => (mortgage * 11 + 9) ~/ 10;
}

const List<String> mGroupNames = ['棕色', '浅蓝', '粉色', '橙色', '红色', '黄色', '绿色', '深蓝'];

const List<Sq> mBoard = [
  Sq('起点', SqType.go),
  Sq('银川', SqType.street, group: 0, price: 60, rents: [2, 10, 30, 90, 160, 250], houseCost: 50),
  Sq('命运', SqType.chest),
  Sq('西宁', SqType.street, group: 0, price: 60, rents: [4, 20, 60, 180, 320, 450], houseCost: 50),
  Sq('所得税', SqType.tax, rents: [200]),
  Sq('东站', SqType.station, price: 200),
  Sq('南宁', SqType.street, group: 1, price: 100, rents: [6, 30, 90, 270, 400, 550], houseCost: 50),
  Sq('机会', SqType.chance),
  Sq('昆明', SqType.street, group: 1, price: 100, rents: [6, 30, 90, 270, 400, 550], houseCost: 50),
  Sq('贵阳', SqType.street, group: 1, price: 120, rents: [8, 40, 100, 300, 450, 600], houseCost: 50),
  Sq('监狱', SqType.jail),
  Sq('长沙', SqType.street, group: 2, price: 140, rents: [10, 50, 150, 450, 625, 750], houseCost: 100),
  Sq('电力公司', SqType.utility, price: 150),
  Sq('南昌', SqType.street, group: 2, price: 140, rents: [10, 50, 150, 450, 625, 750], houseCost: 100),
  Sq('福州', SqType.street, group: 2, price: 160, rents: [12, 60, 180, 500, 700, 900], houseCost: 100),
  Sq('南站', SqType.station, price: 200),
  Sq('武汉', SqType.street, group: 3, price: 180, rents: [14, 70, 200, 550, 750, 950], houseCost: 100),
  Sq('命运', SqType.chest),
  Sq('郑州', SqType.street, group: 3, price: 180, rents: [14, 70, 200, 550, 750, 950], houseCost: 100),
  Sq('合肥', SqType.street, group: 3, price: 200, rents: [16, 80, 220, 600, 800, 1000], houseCost: 100),
  Sq('免费停车', SqType.parking),
  Sq('西安', SqType.street, group: 4, price: 220, rents: [18, 90, 250, 700, 875, 1050], houseCost: 150),
  Sq('机会', SqType.chance),
  Sq('成都', SqType.street, group: 4, price: 220, rents: [18, 90, 250, 700, 875, 1050], houseCost: 150),
  Sq('重庆', SqType.street, group: 4, price: 240, rents: [20, 100, 300, 750, 925, 1100], houseCost: 150),
  Sq('西站', SqType.station, price: 200),
  Sq('天津', SqType.street, group: 5, price: 260, rents: [22, 110, 330, 800, 975, 1150], houseCost: 150),
  Sq('南京', SqType.street, group: 5, price: 260, rents: [22, 110, 330, 800, 975, 1150], houseCost: 150),
  Sq('自来水厂', SqType.utility, price: 150),
  Sq('苏州', SqType.street, group: 5, price: 280, rents: [24, 120, 360, 850, 1025, 1200], houseCost: 150),
  Sq('入狱', SqType.goToJail),
  Sq('广州', SqType.street, group: 6, price: 300, rents: [26, 130, 390, 900, 1100, 1275], houseCost: 200),
  Sq('深圳', SqType.street, group: 6, price: 300, rents: [26, 130, 390, 900, 1100, 1275], houseCost: 200),
  Sq('命运', SqType.chest),
  Sq('杭州', SqType.street, group: 6, price: 320, rents: [28, 150, 450, 1000, 1200, 1400], houseCost: 200),
  Sq('北站', SqType.station, price: 200),
  Sq('机会', SqType.chance),
  Sq('上海', SqType.street, group: 7, price: 350, rents: [35, 175, 500, 1100, 1300, 1500], houseCost: 200),
  Sq('奢侈税', SqType.tax, rents: [100]),
  Sq('北京', SqType.street, group: 7, price: 400, rents: [50, 200, 600, 1400, 1700, 2000], houseCost: 200),
];

const int mJailSq = 10;
const List<int> mStations = [5, 15, 25, 35];
const List<int> mUtilities = [12, 28];

/// Squares of each colour group.
final List<List<int>> mGroups = [
  for (var gi = 0; gi < 8; gi++) [for (var i = 0; i < 40; i++) if (mBoard[i].group == gi) i],
];

/// A 机会/命运 card.
///  kind: move (to=target square), back (n steps), nearStation, nearUtility,
///        jail, jailFree, money (amount, +collect / -pay), each (amount per
///        other player, +collect / -pay), repairs (house, hotel)
class MCard {
  final String text;
  final String kind;
  final int a;
  final int b;
  const MCard(this.text, this.kind, [this.a = 0, this.b = 0]);
}

const List<MCard> mChanceCards = [
  MCard('前进到起点，领取 ¥200', 'move', 0),
  MCard('前往重庆观光，经过起点可领取 ¥200', 'move', 24),
  MCard('前往长沙参加展会，经过起点可领取 ¥200', 'move', 11),
  MCard('前往最近的车站；若已有主人，支付双倍租金', 'nearStation'),
  MCard('前往最近的车站；若已有主人，支付双倍租金', 'nearStation'),
  MCard('前往最近的公用事业；若已有主人，支付骰子点数×10', 'nearUtility'),
  MCard('银行发放分红 ¥50', 'money', 50),
  MCard('获得「出狱许可证」一张，可保留或交易', 'jailFree'),
  MCard('迷路了，后退三步', 'back', 3),
  MCard('违规经营，直接入狱，不经过起点', 'jail'),
  MCard('房屋年检：每栋房屋支付 ¥25，每座酒店支付 ¥100', 'repairs', 25, 100),
  MCard('超速罚款 ¥15', 'money', -15),
  MCard('乘高铁前往东站，经过起点可领取 ¥200', 'move', 5),
  MCard('前往北京参加峰会', 'move', 39),
  MCard('当选商会会长，支付每位玩家 ¥50', 'each', -50),
  MCard('建筑贷款到期返还，领取 ¥150', 'money', 150),
];

const List<MCard> mChestCards = [
  MCard('前进到起点，领取 ¥200', 'move', 0),
  MCard('银行计算失误，你获得 ¥200', 'money', 200),
  MCard('看病花费 ¥50', 'money', -50),
  MCard('出售股票获利 ¥50', 'money', 50),
  MCard('获得「出狱许可证」一张，可保留或交易', 'jailFree'),
  MCard('偷税漏税被查，直接入狱，不经过起点', 'jail'),
  MCard('节日基金到期，领取 ¥100', 'money', 100),
  MCard('个税退税 ¥20', 'money', 20),
  MCard('今天是你的生日！每位玩家送你 ¥10', 'each', 10),
  MCard('人寿保险到期，领取 ¥100', 'money', 100),
  MCard('住院费用 ¥100', 'money', -100),
  MCard('缴纳学费 ¥50', 'money', -50),
  MCard('提供咨询服务，获得 ¥25', 'money', 25),
  MCard('街道翻修：每栋房屋支付 ¥40，每座酒店支付 ¥115', 'repairs', 40, 115),
  MCard('城市形象大赛二等奖，获得 ¥10', 'money', 10),
  MCard('继承远房亲戚遗产 ¥100', 'money', 100),
];
