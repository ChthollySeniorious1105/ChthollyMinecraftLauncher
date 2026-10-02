import '../../src/engine.dart';
import 'bac_rules.dart';
import 'cards.dart';

/// 百家乐：1-8 人对电脑庄家，每人 1000 筹码，押庄/闲/和/对子，
/// 八副牌牌靴（切牌到位后换靴），严格按 punto banco 补牌规则。
class Baccarat extends GameEngine {
  Baccarat(super.setup);

  static const int minBet = 10;
  static const int maxBet = 1000000;

  late int rounds;
  late bool pairs;
  int coup = 0;
  late List<int> chips;
  late List<Map<String, int>> bets;
  late List<bool> betDone;
  late List<int> lastNet;
  List<String> shoe = [];
  int cutAt = 0; // reshuffle when shoe.length <= cutAt
  bool reshuffle = false;
  String phase = 'bet'; // bet | reveal | over
  BacCoup? last;
  List<Map<String, dynamic>> road = [];
  int shoeNo = 0;
  Map<String, dynamic>? summary;

  @override
  bool get isOver => phase == 'over';

  bool broke(int s) => chips[s] < minBet;

  /// 按最终筹码排名（相同并列）。
  @override
  List<int>? get placings => isOver ? rankByScore(chips) : null;

  @override
  List<int> get waitingFor =>
      phase == 'bet' ? [for (var s = 0; s < players; s++) if (!betDone[s] && !broke(s)) s] : const [];

  @override
  int get botDelayMs => 600;

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 20);
    pairs = setup.opt<bool>('pairs', true);
    chips = List.filled(players, 1000);
    lastNet = List.filled(players, 0);
    _newShoe();
    host.log('百家乐开始：每人 1000 筹码，共 $rounds 局');
    _newCoup();
  }

  void _newShoe() {
    shoeNo++;
    shoe = c3Shuffled([for (var i = 0; i < 8; i++) ...c3Deck(jokers: false)], rng);
    // 切牌：在牌靴末端 60-90 张处放置切牌卡
    cutAt = 60 + rng.nextInt(31);
    road = [];
    reshuffle = false;
    // 首张决定烧牌数
    final first = shoe.removeLast();
    var burn = bacValue(first);
    if (burn == 0) burn = 10;
    for (var i = 0; i < burn && shoe.isNotEmpty; i++) {
      shoe.removeLast();
    }
    host.log('第 $shoeNo 靴：洗牌并烧掉 ${burn + 1} 张');
  }

  void _newCoup() {
    coup++;
    bets = List.generate(players, (_) => <String, int>{});
    betDone = List.filled(players, false);
    last = null;
    phase = 'bet';
    if (waitingFor.isEmpty) _reveal();
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    if (phase != 'bet') throw GameError('现在不能下注');
    if (betDone[seat]) throw GameError('你已经下注了');
    if (broke(seat)) throw GameError('筹码不足');
    final type = asStr(a['type']);
    if (type == 'skip') {
      betDone[seat] = true;
    } else if (type == 'bet') {
      final raw = a['bets'];
      if (raw is! Map || raw.length > 5) throw GameError('下注格式错误');
      final parsed = <String, int>{};
      var total = 0;
      for (final e in raw.entries) {
        final k = e.key;
        if (k is! String || !bacAreaName.containsKey(k)) throw GameError('未知的下注区域');
        if (!pairs && (k == 'PP' || k == 'BP')) throw GameError('本桌未开放对子下注');
        final v = e.value;
        if (v is! int || v < 0 || v > maxBet) throw GameError('下注金额无效');
        if (v == 0) continue;
        if (v < minBet) throw GameError('每个区域最少下注 $minBet');
        parsed[k] = v;
        total += v;
      }
      if (parsed.isEmpty) throw GameError('请先选择下注区域');
      if (total > chips[seat]) throw GameError('筹码不足');
      bets[seat] = parsed;
      betDone[seat] = true;
    } else {
      throw GameError('未知操作');
    }
    if (waitingFor.isEmpty) _reveal();
  }

  String _draw() {
    if (shoe.isEmpty) {
      // 理论上不会发生（切牌卡保证余量），保险起见补一靴
      shoe = c3Shuffled([for (var i = 0; i < 8; i++) ...c3Deck(jokers: false)], rng);
    }
    return shoe.removeLast();
  }

  void _reveal() {
    final c = bacDeal(_draw);
    last = c;
    if (shoe.length <= cutAt) reshuffle = true;
    road.add({'w': c.winner, 'p': c.p, 'b': c.b, 'pp': c.playerPair, 'bp': c.bankerPair});
    for (var s = 0; s < players; s++) {
      var net = 0.0;
      for (final e in bets[s].entries) {
        net += bacPayout(e.key, e.value, c);
      }
      final n = net.floor();
      chips[s] += n;
      lastNet[s] = n;
    }
    final w = {'B': '庄赢', 'P': '闲赢', 'T': '和局'}[c.winner];
    host.log('第 $coup 局：闲 ${c.p} 点，庄 ${c.b} 点，$w${c.playerPair ? '（闲对）' : ''}${c.bankerPair ? '（庄对）' : ''}');
    phase = 'reveal';
    final end = coup >= rounds || List.generate(players, broke).every((b) => b);
    host.schedule(4500, () {
      if (end) {
        _finish();
        return;
      }
      if (reshuffle) {
        host.log('切牌卡出现，换新牌靴');
        _newShoe();
      }
      _newCoup();
    });
  }

  void _finish() {
    phase = 'over';
    final order = List.generate(players, (i) => i)..sort((a, b) => chips[b] - chips[a]);
    summary = {'order': order, 'chips': List.of(chips)};
    host.log('百家乐结束：${name(order.first)} 以 ${chips[order.first]} 筹码居首');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final l = last;
    return {
      'phase': phase,
      'coup': coup,
      'rounds': rounds,
      'pairs': pairs,
      'minBet': minBet,
      'chips': chips,
      // 下注阶段只公开是否已下注，他人金额在开牌时公开
      'bets': [
        for (var s = 0; s < players; s++) phase == 'bet' && s != seat ? <String, int>{} : bets[s],
      ],
      'betDone': betDone,
      'broke': [for (var s = 0; s < players; s++) broke(s)],
      'net': phase == 'bet' ? List.filled(players, 0) : lastNet,
      'player': l?.player ?? <String>[],
      'banker': l?.banker ?? <String>[],
      'pTotal': l?.p,
      'bTotal': l?.b,
      'winner': l?.winner,
      'pp': l?.playerPair ?? false,
      'bp': l?.bankerPair ?? false,
      'road': road.length > 120 ? road.sublist(road.length - 120) : road,
      'shoeLeft': shoe.length,
      'shoeNo': shoeNo,
      'reshuffle': reshuffle,
      'summary': summary,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'bet' || betDone[seat] || broke(seat)) return null;
    final c = chips[seat];
    if (botLevel >= 2) {
      // 困难：只押庄（庄家优势最小，约 1.06%），固定押约 4% 筹码，不碰和/对子
      var amt = (c * 0.04) ~/ 10 * 10;
      if (amt < minBet) amt = minBet;
      if (amt > c) amt = c - c % 10;
      return {'type': 'bet', 'bets': {'B': amt}};
    }
    if (botLevel == 0) {
      // 简单：乱押，经常押和/对子，下注额偏大
      final areas = ['B', 'P', 'T', if (pairs) ...['PP', 'BP']];
      final area = areas[rng.nextInt(areas.length)];
      var amt = ((c * (0.1 + rng.nextDouble() * 0.25)) ~/ 10) * 10;
      if (amt < minBet) amt = minBet;
      if (amt > c) amt = c - c % 10;
      return {'type': 'bet', 'bets': {area: amt}};
    }
    if (rng.nextInt(8) == 0) return {'type': 'skip'};
    var amt = ((c * (0.05 + rng.nextDouble() * 0.1)) ~/ 10) * 10;
    if (amt < minBet) amt = minBet;
    if (amt > c) amt = c - c % 10;
    final bets = <String, int>{rng.nextInt(10) < 6 ? 'B' : 'P': amt};
    final left = c - amt;
    if (left >= minBet && rng.nextInt(6) == 0) bets['T'] = minBet;
    if (pairs && left - (bets['T'] ?? 0) >= minBet && rng.nextInt(8) == 0) bets[rng.nextBool() ? 'PP' : 'BP'] = minBet;
    return {'type': 'bet', 'bets': bets};
  }
}
