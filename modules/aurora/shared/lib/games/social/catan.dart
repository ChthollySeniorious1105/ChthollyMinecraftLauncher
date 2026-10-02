import 'dart:math';

import '../../src/engine.dart';
import 'catan_geo.dart';

const catanResNames = ['木材', '砖块', '羊毛', '小麦', '矿石'];
const catanDevNames = {
  'knight': '骑士',
  'vp': '胜利点',
  'road': '道路建设',
  'plenty': '丰收之年',
  'mono': '垄断',
};

const _costRoad = [1, 1, 0, 0, 0];
const _costSettle = [1, 1, 1, 1, 0];
const _costCity = [0, 0, 0, 2, 3];
const _costDev = [0, 0, 1, 1, 1];

/// 卡坦岛 base game.
class Catan extends GameEngine {
  Catan(super.setup);

  static const maxTurns = 500;
  final geo = CatanGeo.instance;

  late int target;
  // board
  final List<int> tileRes = []; // -1 desert
  final List<int> tileNum = []; // 0 desert
  final List<int> harborType = []; // per harbor (geo.harborEdges order): -1 = 3:1, else resource
  final Map<int, int> vertHarbor = {};
  int robber = 0;

  late List<int> vertOwner = List.filled(geo.nVert, -1);
  late List<int> vertLevel = List.filled(geo.nVert, 0); // 1 settlement, 2 city
  late List<int> edgeOwner = List.filled(geo.nEdge, -1);

  late List<List<int>> hands;
  final List<int> bank = List.filled(5, 19);
  final List<String> devDeck = [];
  late List<List<String>> devCards; // playable (bought before this turn)
  late List<List<String>> devNew; // bought this turn
  late List<List<String>> devPlayed; // publicly played cards
  late List<int> knights;
  late List<int> roadLen;
  late List<int> roadsLeft, settlementsLeft, citiesLeft;
  int largestArmy = -1, longestRoad = -1;

  // flow
  String phase = 'setup'; // setup roll discard robber main roads over
  List<int> setupOrder = [];
  int setupIdx = 0;
  String setupStep = 'settle';
  int setupVertex = -1;
  int turn = 0;
  int turnCount = 0;
  List<int> dice = [];
  bool playedDev = false;
  String robberReturn = 'main';
  int freeRoads = 0;
  String roadsReturn = 'main';
  Map<int, int> discardNeed = {};
  int winner = -1;
  String lastEvent = '';
  int lastBuiltV = -1, lastBuiltE = -1;

  // trade offer
  Map<String, dynamic>? offer; // {id, from, to, give, get}
  Map<int, String> responses = {}; // seat -> pending/accept/decline
  int offerSeq = 0;
  int offersThisTurn = 0; // anti-spam: offers are broadcast to chat
  static const maxOffersPerTurn = 20;

  // bot bookkeeping
  int botBankTrades = 0;
  bool botOffered = false;

  bool get isOverFlag => phase == 'over';

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    final r = rankByScore([for (var s = 0; s < players; s++) totalVp(s) + (s == winner ? 100 : 0)]);
    return r;
  }

  @override
  int get botDelayMs => 700;

  // ---------------------------------------------------------------- setup
  @override
  void start() {
    target = setup.opt<int>('vp', 10);
    final random = setup.opt<String>('map', 'fixed') == 'random';
    _makeBoard(random);
    hands = [for (var i = 0; i < players; i++) List.filled(5, 0)];
    devCards = [for (var i = 0; i < players; i++) <String>[]];
    devNew = [for (var i = 0; i < players; i++) <String>[]];
    devPlayed = [for (var i = 0; i < players; i++) <String>[]];
    knights = List.filled(players, 0);
    roadLen = List.filled(players, 0);
    roadsLeft = List.filled(players, 15);
    settlementsLeft = List.filled(players, 5);
    citiesLeft = List.filled(players, 4);
    devDeck
      ..addAll(List.filled(14, 'knight'))
      ..addAll(List.filled(5, 'vp'))
      ..addAll(List.filled(2, 'road'))
      ..addAll(List.filled(2, 'plenty'))
      ..addAll(List.filled(2, 'mono'))
      ..shuffle(rng);
    final first = rng.nextInt(players);
    final order = [for (var i = 0; i < players; i++) (first + i) % players];
    setupOrder = [...order, ...order.reversed];
    turn = setupOrder[0];
    host.log('卡坦岛开始！${name(turn)} 先放置。目标 $target 分');
  }

  void _makeBoard(bool random) {
    const fixedRes = [4, 2, 0, 3, 1, 2, 1, 3, 0, -1, 0, 4, 0, 4, 3, 2, 1, 3, 2];
    const fixedNum = [10, 2, 9, 12, 6, 4, 10, 9, 11, 0, 3, 8, 8, 3, 4, 5, 5, 6, 11];
    const fixedHarbor = [-1, 2, -1, -1, 1, 0, -1, 3, 4];
    if (!random) {
      tileRes.addAll(fixedRes);
      tileNum.addAll(fixedNum);
      harborType.addAll(fixedHarbor);
    } else {
      final res = shuffled([...fixedRes], rng);
      tileRes.addAll(res);
      final nums = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12];
      for (var tries = 0; tries < 2000; tries++) {
        final s = shuffled(nums, rng);
        final out = <int>[];
        var k = 0;
        for (var h = 0; h < geo.nHex; h++) {
          out.add(res[h] < 0 ? 0 : s[k++]);
        }
        var ok = true;
        for (var h = 0; h < geo.nHex && ok; h++) {
          if (out[h] != 6 && out[h] != 8) continue;
          for (final n in geo.hexNeighbors[h]) {
            if (out[n] == 6 || out[n] == 8) ok = false;
          }
        }
        if (ok || tries == 1999) {
          tileNum.addAll(out);
          break;
        }
      }
      harborType.addAll(shuffled(fixedHarbor, rng));
    }
    for (var i = 0; i < geo.harborEdges.length; i++) {
      for (final v in geo.edgeVerts[geo.harborEdges[i]]) {
        vertHarbor[v] = harborType[i];
      }
    }
    robber = tileRes.indexOf(-1);
  }

  // --------------------------------------------------------------- helpers
  int handSize(int s) => hands[s].fold(0, (a, b) => a + b);
  bool canAfford(int s, List<int> cost) => [for (var r = 0; r < 5; r++) hands[s][r] >= cost[r]].every((b) => b);
  void pay(int s, List<int> cost) {
    for (var r = 0; r < 5; r++) {
      hands[s][r] -= cost[r];
      bank[r] += cost[r];
    }
  }

  void give(int s, int r, int n) {
    final k = min(n, bank[r]);
    hands[s][r] += k;
    bank[r] -= k;
  }

  int ratio(int s, int r) {
    var best = 4;
    vertHarbor.forEach((v, t) {
      if (vertOwner[v] != s) return;
      if (t == r) best = min(best, 2);
      if (t == -1) best = min(best, 3);
    });
    return best;
  }

  int publicVp(int s) {
    var vp = 0;
    for (var v = 0; v < geo.nVert; v++) {
      if (vertOwner[v] == s) vp += vertLevel[v];
    }
    if (longestRoad == s) vp += 2;
    if (largestArmy == s) vp += 2;
    return vp;
  }

  int totalVp(int s) =>
      publicVp(s) + devCards[s].where((c) => c == 'vp').length + devNew[s].where((c) => c == 'vp').length;

  bool distanceOk(int v) => vertOwner[v] < 0 && geo.vertNeighbors[v].every((n) => vertOwner[n] < 0);

  bool _touchesOwnRoad(int s, int v) => geo.vertEdges[v].any((e) => edgeOwner[e] == s);

  bool canSettle(int s, int v) => distanceOk(v) && _touchesOwnRoad(s, v);

  bool canRoad(int s, int e) {
    if (edgeOwner[e] >= 0) return false;
    for (final v in geo.edgeVerts[e]) {
      if (vertOwner[v] == s) return true;
      if (vertOwner[v] >= 0) continue; // blocked by opponent building
      if (geo.vertEdges[v].any((x) => x != e && edgeOwner[x] == s)) return true;
    }
    return false;
  }

  List<int> legalSettle(int s) => [for (var v = 0; v < geo.nVert; v++) if (canSettle(s, v)) v];
  List<int> legalCity(int s) => [for (var v = 0; v < geo.nVert; v++) if (vertOwner[v] == s && vertLevel[v] == 1) v];
  List<int> legalRoad(int s) => [for (var e = 0; e < geo.nEdge; e++) if (canRoad(s, e)) e];
  List<int> setupSettleSpots() => [for (var v = 0; v < geo.nVert; v++) if (distanceOk(v)) v];
  List<int> setupRoadSpots() =>
      setupVertex < 0 ? [] : [for (final e in geo.vertEdges[setupVertex]) if (edgeOwner[e] < 0) e];

  /// Longest continuous road of [s] (edges not reused, not passing through
  /// vertices owned by opponents).
  int longestRoadOf(int s) {
    final mine = [for (var e = 0; e < geo.nEdge; e++) if (edgeOwner[e] == s) e];
    if (mine.isEmpty) return 0;
    var best = 0;
    final used = <int>{};
    void dfs(int v, int len) {
      if (len > best) best = len;
      if (len > 0 && vertOwner[v] >= 0 && vertOwner[v] != s) return;
      for (final e in geo.vertEdges[v]) {
        if (edgeOwner[e] != s || used.contains(e)) continue;
        used.add(e);
        final [a, b] = geo.edgeVerts[e];
        dfs(a == v ? b : a, len + 1);
        used.remove(e);
      }
    }

    final starts = <int>{for (final e in mine) ...geo.edgeVerts[e]};
    for (final v in starts) {
      dfs(v, 0);
    }
    return best;
  }

  void updateLongest() {
    for (var s = 0; s < players; s++) {
      roadLen[s] = longestRoadOf(s);
    }
    final old = longestRoad;
    if (longestRoad >= 0 &&
        roadLen[longestRoad] >= 5 &&
        [for (var s = 0; s < players; s++) if (s != longestRoad) roadLen[s]].every((l) => l <= roadLen[longestRoad])) {
      return;
    }
    final mx = roadLen.reduce(max);
    final top = [for (var s = 0; s < players; s++) if (roadLen[s] == mx) s];
    longestRoad = mx >= 5 && top.length == 1 ? top.first : -1;
    if (longestRoad != old && longestRoad >= 0) host.log('${name(longestRoad)} 获得最长道路（$mx）');
    if (longestRoad < 0 && old >= 0) host.log('最长道路奖励被收回');
  }

  void updateArmy(int s) {
    if (knights[s] >= 3 && (largestArmy < 0 || knights[s] > knights[largestArmy]) && largestArmy != s) {
      largestArmy = s;
      host.log('${name(s)} 获得最大骑士团（${knights[s]}）');
    }
  }

  void _checkWin() {
    if (phase == 'over' || phase == 'setup') return;
    if (totalVp(turn) >= target) {
      winner = turn;
      phase = 'over';
      offer = null;
      host.log('${name(turn)} 达到 ${totalVp(turn)} 分，获胜！');
    }
  }

  void _endByCap() {
    var best = 0;
    for (var s = 1; s < players; s++) {
      if (totalVp(s) > totalVp(best)) best = s;
    }
    winner = best;
    phase = 'over';
    offer = null;
    host.log('回合数达到上限，${name(best)} 以 ${totalVp(best)} 分获胜');
  }

  // ---------------------------------------------------------------- flow
  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'over':
        return const [];
      case 'discard':
        return discardNeed.keys.toList()..sort();
      case 'main':
        if (offer != null) {
          final pending = [for (final e in responses.entries) if (e.value == 'pending') e.key]..sort();
          if (pending.isNotEmpty) return pending;
        }
        return [turn];
      default:
        return [turn];
    }
  }

  void _nextTurn() {
    for (final c in devNew[turn]) {
      devCards[turn].add(c);
    }
    devNew[turn].clear();
    offer = null;
    responses = {};
    offersThisTurn = 0;
    turnCount++;
    if (turnCount >= maxTurns) {
      _endByCap();
      return;
    }
    turn = (turn + 1) % players;
    phase = 'roll';
    playedDev = false;
    dice = [];
    botBankTrades = 0;
    botOffered = false;
    _checkWin();
  }

  void _roll() {
    final a = rng.nextInt(6) + 1, b = rng.nextInt(6) + 1;
    dice = [a, b];
    final sum = a + b;
    lastEvent = '${name(turn)} 掷出 $sum';
    host.log(lastEvent);
    if (sum == 7) {
      discardNeed = {};
      for (var s = 0; s < players; s++) {
        final n = handSize(s);
        if (n > 7) discardNeed[s] = n ~/ 2;
      }
      robberReturn = 'main';
      phase = discardNeed.isEmpty ? 'robber' : 'discard';
      return;
    }
    // production
    final gain = [for (var s = 0; s < players; s++) List.filled(5, 0)];
    for (var h = 0; h < geo.nHex; h++) {
      if (tileNum[h] != sum || h == robber) continue;
      for (final v in geo.hexVerts[h]) {
        if (vertOwner[v] >= 0) gain[vertOwner[v]][tileRes[h]] += vertLevel[v];
      }
    }
    for (var r = 0; r < 5; r++) {
      final takers = [for (var s = 0; s < players; s++) if (gain[s][r] > 0) s];
      final total = takers.fold(0, (a, s) => a + gain[s][r]);
      if (total == 0) continue;
      if (total > bank[r] && takers.length > 1) {
        host.log('银行${catanResNames[r]}不足，本次无人获得');
        continue;
      }
      for (final s in takers) {
        give(s, r, gain[s][r]);
      }
    }
    phase = 'main';
  }

  List<int> stealCandidates(int h, int thief) {
    final out = <int>{};
    for (final v in geo.hexVerts[h]) {
      final o = vertOwner[v];
      if (o >= 0 && o != thief && handSize(o) > 0) out.add(o);
    }
    return out.toList()..sort();
  }

  void _steal(int thief, int victim) {
    final pool = <int>[];
    for (var r = 0; r < 5; r++) {
      for (var i = 0; i < hands[victim][r]; i++) {
        pool.add(r);
      }
    }
    if (pool.isEmpty) return;
    final r = pool[rng.nextInt(pool.length)];
    hands[victim][r]--;
    hands[thief][r]++;
  }

  List<int> _cards(Object? v) {
    final l = asIntList(v);
    if (l.length != 5 || l.any((x) => x < 0 || x > 19)) throw GameError('资源格式错误');
    return l;
  }

  // ---------------------------------------------------------------- handle
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    final type = asStr(a['type']);
    switch (phase) {
      case 'setup':
        _handleSetup(seat, type, a);
        return;
      case 'discard':
        if (type != 'discard') throw GameError('请先弃牌');
        final need = discardNeed[seat];
        if (need == null) throw GameError('你不需要弃牌');
        final c = _cards(a['cards']);
        if (c.fold(0, (x, y) => x + y) != need) throw GameError('需要弃掉 $need 张');
        for (var r = 0; r < 5; r++) {
          if (c[r] > hands[seat][r]) throw GameError('资源不足');
        }
        pay(seat, c);
        discardNeed.remove(seat);
        host.log('${name(seat)} 弃掉 $need 张牌');
        if (discardNeed.isEmpty) phase = 'robber';
        return;
    }
    // respond to offers can come from anyone
    if (type == 'respond') {
      _respond(seat, asBool(a['accept']));
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    switch (phase) {
      case 'roll':
        if (type == 'roll') {
          _roll();
        } else if (type == 'playDev') {
          _playDev(seat, a);
        } else {
          throw GameError('请先掷骰子');
        }
        break;
      case 'robber':
        if (type != 'robber') throw GameError('请移动强盗');
        final h = asInt(a['hex']);
        if (h < 0 || h >= geo.nHex || h == robber) throw GameError('必须把强盗移到其他地块');
        final cands = stealCandidates(h, seat);
        var victim = asInt(a['target']);
        if (cands.isNotEmpty && !cands.contains(victim)) {
          if (cands.length == 1) {
            victim = cands.first;
          } else {
            throw GameError('请选择要抢夺的玩家');
          }
        }
        robber = h;
        if (cands.isNotEmpty) {
          _steal(seat, victim);
          lastEvent = '${name(seat)} 移动强盗并抢夺了 ${name(victim)}';
        } else {
          lastEvent = '${name(seat)} 移动了强盗';
        }
        host.log(lastEvent);
        phase = robberReturn;
        break;
      case 'roads':
        if (type == 'road') {
          final e = asInt(a['e']);
          if (e < 0 || e >= geo.nEdge || !canRoad(seat, e)) throw GameError('这里不能修路');
          edgeOwner[e] = seat;
          roadsLeft[seat]--;
          lastBuiltE = e;
          freeRoads--;
          updateLongest();
        } else if (type == 'end') {
          freeRoads = 0;
        } else {
          throw GameError('请放置免费道路');
        }
        if (freeRoads <= 0 || roadsLeft[seat] <= 0 || legalRoad(seat).isEmpty) phase = roadsReturn;
        break;
      case 'main':
        _handleMain(seat, type, a);
        break;
    }
    _checkWin();
  }

  void _handleSetup(int seat, String type, Map<String, dynamic> a) {
    if (seat != turn) throw GameError('还没轮到你');
    if (setupStep == 'settle') {
      if (type != 'settle') throw GameError('请放置村庄');
      final v = asInt(a['v']);
      if (v < 0 || v >= geo.nVert || !distanceOk(v)) throw GameError('这里不能建村庄（距离规则）');
      vertOwner[v] = seat;
      vertLevel[v] = 1;
      settlementsLeft[seat]--;
      setupVertex = v;
      lastBuiltV = v;
      if (setupIdx >= players) {
        for (final h in geo.vertHexes[v]) {
          if (tileRes[h] >= 0) give(seat, tileRes[h], 1);
        }
      }
      setupStep = 'road';
    } else {
      if (type != 'road') throw GameError('请放置道路');
      final e = asInt(a['e']);
      if (!setupRoadSpots().contains(e)) throw GameError('道路必须连接刚放的村庄');
      edgeOwner[e] = seat;
      roadsLeft[seat]--;
      lastBuiltE = e;
      setupStep = 'settle';
      setupVertex = -1;
      setupIdx++;
      if (setupIdx >= setupOrder.length) {
        updateLongest();
        turn = setupOrder.first;
        phase = 'roll';
        host.log('初始布置完成，${name(turn)} 开始第一回合');
      } else {
        turn = setupOrder[setupIdx];
      }
    }
  }

  void _handleMain(int seat, String type, Map<String, dynamic> a) {
    if (offer != null && !const {'cancelOffer', 'confirmTrade'}.contains(type)) {
      throw GameError('请先处理当前交易');
    }
    switch (type) {
      case 'road':
        final e = asInt(a['e']);
        if (e < 0 || e >= geo.nEdge || !canRoad(seat, e)) throw GameError('这里不能修路');
        if (roadsLeft[seat] <= 0) throw GameError('道路已用完');
        if (!canAfford(seat, _costRoad)) throw GameError('资源不足（木材+砖块）');
        pay(seat, _costRoad);
        edgeOwner[e] = seat;
        roadsLeft[seat]--;
        lastBuiltE = e;
        lastEvent = '${name(seat)} 修建了道路';
        updateLongest();
        break;
      case 'settle':
        final v = asInt(a['v']);
        if (v < 0 || v >= geo.nVert || !canSettle(seat, v)) throw GameError('这里不能建村庄');
        if (settlementsLeft[seat] <= 0) throw GameError('村庄已用完');
        if (!canAfford(seat, _costSettle)) throw GameError('资源不足（木材+砖块+羊毛+小麦）');
        pay(seat, _costSettle);
        vertOwner[v] = seat;
        vertLevel[v] = 1;
        settlementsLeft[seat]--;
        lastBuiltV = v;
        lastEvent = '${name(seat)} 建造了村庄';
        host.log(lastEvent);
        updateLongest();
        break;
      case 'city':
        final v = asInt(a['v']);
        if (v < 0 || v >= geo.nVert || vertOwner[v] != seat || vertLevel[v] != 1) throw GameError('只能把自己的村庄升级为城市');
        if (citiesLeft[seat] <= 0) throw GameError('城市已用完');
        if (!canAfford(seat, _costCity)) throw GameError('资源不足（2小麦+3矿石）');
        pay(seat, _costCity);
        vertLevel[v] = 2;
        citiesLeft[seat]--;
        settlementsLeft[seat]++;
        lastBuiltV = v;
        lastEvent = '${name(seat)} 建造了城市';
        host.log(lastEvent);
        break;
      case 'buyDev':
        if (devDeck.isEmpty) throw GameError('发展卡已售罄');
        if (!canAfford(seat, _costDev)) throw GameError('资源不足（羊毛+小麦+矿石）');
        pay(seat, _costDev);
        devNew[seat].add(devDeck.removeLast());
        lastEvent = '${name(seat)} 购买了发展卡';
        host.log(lastEvent);
        break;
      case 'playDev':
        _playDev(seat, a);
        break;
      case 'bank':
        final g = asInt(a['give']), t = asInt(a['get']);
        if (g < 0 || g > 4 || t < 0 || t > 4 || g == t) throw GameError('无效交易');
        final k = ratio(seat, g);
        if (hands[seat][g] < k) throw GameError('需要 $k 张${catanResNames[g]}');
        if (bank[t] <= 0) throw GameError('银行没有${catanResNames[t]}了');
        hands[seat][g] -= k;
        bank[g] += k;
        give(seat, t, 1);
        lastEvent = '${name(seat)} 与银行 $k:1 交易：${catanResNames[g]}→${catanResNames[t]}';
        host.log(lastEvent);
        break;
      case 'offer':
        final gv = _cards(a['give']), gt = _cards(a['get']);
        final to = asInt(a['to'], -1);
        if (gv.every((x) => x == 0) || gt.every((x) => x == 0)) throw GameError('双方都需要至少一张牌');
        for (var r = 0; r < 5; r++) {
          if (gv[r] > hands[seat][r]) throw GameError('你的资源不足');
          if (gv[r] > 0 && gt[r] > 0) throw GameError('不能交换同种资源');
        }
        if (to != -1 && (to < 0 || to >= players || to == seat)) throw GameError('交易对象无效');
        if (offersThisTurn >= maxOffersPerTurn) throw GameError('本回合发起交易次数过多');
        offersThisTurn++;
        offer = {'id': ++offerSeq, 'from': seat, 'to': to, 'give': gv, 'get': gt};
        responses = {
          for (var s = 0; s < players; s++)
            if (s != seat && (to == -1 || to == s)) s: 'pending',
        };
        host.log('${name(seat)} 发起交易：${_fmt(gv)} 换 ${_fmt(gt)}${to >= 0 ? '（对 ${name(to)}）' : ''}');
        final id = offerSeq;
        host.schedule(30000, () {
          if (offer == null || offer!['id'] != id) return;
          responses.forEach((s, st) {
            if (st == 'pending' && !isBot(s)) responses[s] = 'decline';
          });
          _afterResponse();
        });
        break;
      case 'cancelOffer':
        if (offer == null) throw GameError('没有进行中的交易');
        offer = null;
        responses = {};
        host.log('${name(seat)} 取消了交易');
        break;
      case 'confirmTrade':
        if (offer == null) throw GameError('没有进行中的交易');
        final w = asInt(a['with']);
        if (responses[w] != 'accept') throw GameError('对方没有接受交易');
        final gv = (offer!['give'] as List).cast<int>(), gt = (offer!['get'] as List).cast<int>();
        for (var r = 0; r < 5; r++) {
          if (hands[seat][r] < gv[r] || hands[w][r] < gt[r]) throw GameError('资源已变化，交易失败');
        }
        for (var r = 0; r < 5; r++) {
          hands[seat][r] += gt[r] - gv[r];
          hands[w][r] += gv[r] - gt[r];
        }
        lastEvent = '${name(seat)} 与 ${name(w)} 完成交易：${_fmt(gv)} 换 ${_fmt(gt)}';
        host.log(lastEvent);
        offer = null;
        responses = {};
        break;
      case 'end':
        _nextTurn();
        break;
      default:
        throw GameError('未知操作');
    }
  }

  String _fmt(List<int> c) =>
      [for (var r = 0; r < 5; r++) if (c[r] > 0) '${catanResNames[r]}×${c[r]}'].join(' ');

  void _respond(int seat, bool accept) {
    if (offer == null || responses[seat] == null) throw GameError('没有需要回应的交易');
    if (accept) {
      final gt = (offer!['get'] as List).cast<int>();
      for (var r = 0; r < 5; r++) {
        if (hands[seat][r] < gt[r]) throw GameError('你的资源不足以接受');
      }
    }
    responses[seat] = accept ? 'accept' : 'decline';
    host.log('${name(seat)} ${accept ? '接受' : '拒绝'}了交易');
    _afterResponse();
  }

  void _afterResponse() {
    if (offer == null) return;
    if (responses.values.every((v) => v == 'decline')) {
      host.log('无人接受，交易取消');
      offer = null;
      responses = {};
    }
  }

  void _playDev(int seat, Map<String, dynamic> a) {
    final card = asStr(a['card']);
    if (playedDev) throw GameError('每回合只能打出一张发展卡');
    if (card == 'vp' || !catanDevNames.containsKey(card)) throw GameError('无效的发展卡');
    if (!devCards[seat].contains(card)) {
      throw GameError(devNew[seat].contains(card) ? '本回合购买的发展卡不能立即使用' : '你没有这张卡');
    }
    final back = phase;
    switch (card) {
      case 'knight':
        knights[seat]++;
        updateArmy(seat);
        robberReturn = back;
        phase = 'robber';
        break;
      case 'road':
        if (roadsLeft[seat] <= 0 || legalRoad(seat).isEmpty) throw GameError('没有可修路的位置');
        freeRoads = 2;
        roadsReturn = back;
        phase = 'roads';
        break;
      case 'plenty':
        final rs = asIntList(a['res']);
        if (rs.length != 2 || rs.any((r) => r < 0 || r > 4)) throw GameError('请选择两种资源');
        for (final r in rs) {
          if (bank[r] <= 0) throw GameError('银行没有${catanResNames[r]}了');
        }
        if (rs[0] == rs[1] && bank[rs[0]] < 2) throw GameError('银行${catanResNames[rs[0]]}不足');
        for (final r in rs) {
          give(seat, r, 1);
        }
        break;
      case 'mono':
        final r = asInt(a['res']);
        if (r < 0 || r > 4) throw GameError('请选择资源');
        var n = 0;
        for (var s = 0; s < players; s++) {
          if (s == seat) continue;
          n += hands[s][r];
          hands[seat][r] += hands[s][r];
          hands[s][r] = 0;
        }
        host.log('${name(seat)} 垄断了${catanResNames[r]}，获得 $n 张');
        break;
    }
    devCards[seat].remove(card);
    devPlayed[seat].add(card);
    playedDev = true;
    lastEvent = '${name(seat)} 打出了${catanDevNames[card]}';
    host.log(lastEvent);
  }

  // ---------------------------------------------------------------- view
  @override
  Map<String, dynamic> view(int seat) {
    final over = phase == 'over';
    final me = seat >= 0 && seat < players;
    final legal = <String, dynamic>{};
    if (me && seat == turn) {
      if (phase == 'setup') {
        legal[setupStep] = setupStep == 'settle' ? setupSettleSpots() : setupRoadSpots();
      } else if (phase == 'main' && offer == null) {
        legal['settle'] = legalSettle(seat);
        legal['city'] = legalCity(seat);
        legal['road'] = legalRoad(seat);
      } else if (phase == 'roads') {
        legal['road'] = legalRoad(seat);
      }
    }
    return {
      'phase': phase,
      'setupStep': setupStep,
      'turn': turn,
      'turnCount': turnCount,
      'maxTurns': maxTurns,
      'target': target,
      'dice': dice,
      'tileRes': tileRes,
      'tileNum': tileNum,
      'harbors': [
        for (var i = 0; i < harborType.length; i++) {'e': geo.harborEdges[i], 't': harborType[i]}
      ],
      'robber': robber,
      'vertOwner': vertOwner,
      'vertLevel': vertLevel,
      'edgeOwner': edgeOwner,
      'lastV': lastBuiltV,
      'lastE': lastBuiltE,
      'bank': bank,
      'devLeft': devDeck.length,
      'largestArmy': largestArmy,
      'longestRoad': longestRoad,
      'winner': winner,
      'event': lastEvent,
      'playedDev': playedDev,
      'freeRoads': freeRoads,
      'players': [
        for (var s = 0; s < players; s++)
          {
            'cards': handSize(s),
            'devCount': devCards[s].length + devNew[s].length,
            'knights': knights[s],
            'road': roadLen[s],
            'vp': (over || s == seat) ? totalVp(s) : publicVp(s),
            'roads': roadsLeft[s],
            'settlements': settlementsLeft[s],
            'cities': citiesLeft[s],
            'discard': discardNeed[s] ?? 0,
            if (over) 'hand': hands[s],
            if (over) 'dev': [...devCards[s], ...devNew[s]],
          }
      ],
      'hand': me ? hands[seat] : null,
      'dev': me ? devCards[seat] : const [],
      'devNew': me ? devNew[seat] : const [],
      'ratios': me ? [for (var r = 0; r < 5; r++) ratio(seat, r)] : const [4, 4, 4, 4, 4],
      'legal': legal,
      'offer': offer == null
          ? null
          : {
              ...offer!,
              'responses': {for (final e in responses.entries) '${e.key}': e.value},
            },
    };
  }

  // ---------------------------------------------------------------- bot
  double _vertScore(int s, int v) {
    var sc = 0.0;
    final have = <int>{};
    for (var x = 0; x < geo.nVert; x++) {
      if (vertOwner[x] != s) continue;
      for (final h in geo.vertHexes[x]) {
        if (tileRes[h] >= 0) have.add(tileRes[h]);
      }
    }
    final here = <int>{};
    for (final h in geo.vertHexes[v]) {
      if (tileRes[h] < 0) continue;
      final p = CatanGeo.pips(tileNum[h]).toDouble();
      sc += h == robber ? p * 0.4 : p;
      if (!have.contains(tileRes[h]) && here.add(tileRes[h])) sc += 1.5;
      if (tileRes[h] == 0 || tileRes[h] == 1) sc += 0.4;
    }
    if (vertHarbor.containsKey(v)) sc += 0.8;
    return sc;
  }

  List<int> _deficit(int s, List<int> cost) => [for (var r = 0; r < 5; r++) max(0, cost[r] - hands[s][r])];

  List<int>? _goal(int s) {
    if (citiesLeft[s] > 0 && legalCity(s).isNotEmpty) return _costCity;
    if (settlementsLeft[s] > 0 && legalSettle(s).isNotEmpty) return _costSettle;
    if (roadsLeft[s] > 0 && legalRoad(s).isNotEmpty) return _costRoad;
    if (devDeck.isNotEmpty) return _costDev;
    return null;
  }

  double _resWeight(int s, int r) {
    final goal = _goal(s);
    var w = 1.0;
    if (goal != null && _deficit(s, goal)[r] > 0) w += 1.5;
    if (hands[s][r] >= 3) w -= 0.5;
    return w;
  }

  int _bestRoad(int s, List<int> edges) {
    var best = edges.first;
    var bestSc = -1e9;
    for (final e in edges) {
      var sc = rng.nextDouble() * 0.5;
      for (final v in geo.edgeVerts[e]) {
        if (distanceOk(v)) sc = max(sc, _vertScore(s, v) + rng.nextDouble() * 0.5);
        for (final n in geo.vertNeighbors[v]) {
          if (distanceOk(n)) sc = max(sc, _vertScore(s, n) * 0.6);
        }
      }
      if (sc > bestSc) {
        bestSc = sc;
        best = e;
      }
    }
    return best;
  }

  Map<String, dynamic> _robberMove(int s) {
    var bestH = -1, bestT = -1;
    var bestSc = -1e9;
    for (var h = 0; h < geo.nHex; h++) {
      if (h == robber) continue;
      var sc = rng.nextDouble() * 0.1;
      var t = -1, tv = -1;
      for (final v in geo.hexVerts[h]) {
        final o = vertOwner[v];
        if (o < 0) continue;
        final p = CatanGeo.pips(tileNum[h]) * vertLevel[v].toDouble();
        if (o == s) {
          sc -= p * 3;
        } else {
          sc += p * (1 + publicVp(o) / 4);
          if (handSize(o) > 0 && publicVp(o) > tv) {
            tv = publicVp(o);
            t = o;
          }
        }
      }
      if (t >= 0) sc += 1;
      if (sc > bestSc) {
        bestSc = sc;
        bestH = h;
        bestT = t;
      }
    }
    return {'type': 'robber', 'hex': bestH, 'target': bestT};
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'over':
        return null;
      case 'setup':
        if (setupStep == 'settle') {
          final spots = setupSettleSpots();
          var best = spots.first;
          var bs = -1e9;
          for (final v in spots) {
            final sc = _vertScore(seat, v) + rng.nextDouble() * switch (botLevel) { 0 => 4.0, 2 => 0.05, _ => 0.3 };
            if (sc > bs) {
              bs = sc;
              best = v;
            }
          }
          return {'type': 'settle', 'v': best};
        }
        return {'type': 'road', 'e': _bestRoad(seat, setupRoadSpots())};
      case 'discard':
        final need = discardNeed[seat];
        if (need == null) return null;
        final h = [...hands[seat]];
        final out = List.filled(5, 0);
        for (var i = 0; i < need; i++) {
          var r = 0;
          for (var k = 1; k < 5; k++) {
            if (h[k] > h[r]) r = k;
          }
          h[r]--;
          out[r]++;
        }
        return {'type': 'discard', 'cards': out};
      case 'robber':
        return _robberMove(seat);
      case 'roads':
        final rs = legalRoad(seat);
        if (rs.isEmpty) return {'type': 'end'};
        return {'type': 'road', 'e': _bestRoad(seat, rs)};
    }
    // trade responses
    if (seat != turn) {
      if (offer == null || responses[seat] != 'pending') return null;
      final gv = (offer!['give'] as List).cast<int>(), gt = (offer!['get'] as List).cast<int>();
      final from = offer!['from'] as int;
      var ok = true;
      for (var r = 0; r < 5; r++) {
        if (hands[seat][r] < gt[r]) ok = false;
      }
      var gain = 0.0, loss = 0.0;
      for (var r = 0; r < 5; r++) {
        gain += gv[r] * _resWeight(seat, r);
        loss += gt[r] * _resWeight(seat, r);
      }
      final accept = ok && gain > loss && totalVp(from) < target - 2;
      return {'type': 'respond', 'accept': accept};
    }
    if (phase == 'roll') {
      if (!playedDev && devCards[seat].contains('knight')) {
        final threatened = geo.hexVerts[robber].any((v) => vertOwner[v] == seat);
        if (threatened) return {'type': 'playDev', 'card': 'knight'};
      }
      return {'type': 'roll'};
    }
    // main
    if (offer != null) {
      final acc = [for (final e in responses.entries) if (e.value == 'accept') e.key];
      if (acc.isNotEmpty) return {'type': 'confirmTrade', 'with': acc.first};
      return {'type': 'cancelOffer'};
    }
    final h = hands[seat];
    // development cards
    if (!playedDev) {
      final dc = devCards[seat];
      if (dc.contains('knight')) {
        final threatened = geo.hexVerts[robber].any((v) => vertOwner[v] == seat);
        final army = knights[seat] + 1 >= 3 && (largestArmy < 0 || knights[seat] + 1 > knights[largestArmy]) && largestArmy != seat;
        if (threatened || army || rng.nextInt(3) == 0) return {'type': 'playDev', 'card': 'knight'};
      }
      if (dc.contains('road') && roadsLeft[seat] > 0 && legalRoad(seat).isNotEmpty) {
        return {'type': 'playDev', 'card': 'road'};
      }
      if (dc.contains('plenty')) {
        final goal = _goal(seat) ?? _costCity;
        final d = _deficit(seat, goal);
        final picks = <int>[];
        for (var r = 0; r < 5 && picks.length < 2; r++) {
          for (var k = 0; k < d[r] && picks.length < 2; k++) {
            if (bank[r] > picks.where((x) => x == r).length) picks.add(r);
          }
        }
        for (var r = 0; picks.length < 2 && r < 5; r++) {
          if (bank[r] > picks.where((x) => x == r).length + 1) picks.add(r);
        }
        if (picks.length == 2) return {'type': 'playDev', 'card': 'plenty', 'res': picks};
      }
      if (dc.contains('mono')) {
        var br = 0, bn = 0;
        for (var r = 0; r < 5; r++) {
          // Derived from public info only: 19 of each resource exist, the bank
          // count is public, so the rest are in opponents' hands.
          final n = 19 - bank[r] - hands[seat][r];
          if (n > bn) {
            bn = n;
            br = r;
          }
        }
        if (bn >= 3) return {'type': 'playDev', 'card': 'mono', 'res': br};
      }
    }
    // 简单: frequently hesitates and ends the turn without building
    if (botLevel == 0 && rng.nextInt(3) == 0) return {'type': 'end'};
    // building
    final cities = legalCity(seat);
    if (cities.isNotEmpty && citiesLeft[seat] > 0 && canAfford(seat, _costCity)) {
      cities.sort((a, b) => _vertScore(seat, b).compareTo(_vertScore(seat, a)));
      return {'type': 'city', 'v': cities.first};
    }
    final settles = legalSettle(seat);
    if (settles.isNotEmpty && settlementsLeft[seat] > 0 && canAfford(seat, _costSettle)) {
      settles.sort((a, b) => _vertScore(seat, b).compareTo(_vertScore(seat, a)));
      return {'type': 'settle', 'v': settles.first};
    }
    final roads = roadsLeft[seat] > 0 ? legalRoad(seat) : <int>[];
    if (settles.isEmpty && roads.isNotEmpty && canAfford(seat, _costRoad) && settlementsLeft[seat] > 0) {
      return {'type': 'road', 'e': _bestRoad(seat, roads)};
    }
    if (devDeck.isNotEmpty && canAfford(seat, _costDev) && (cities.isEmpty || h[4] > 3 || h[3] > 2)) {
      return {'type': 'buyDev'};
    }
    if (roads.isNotEmpty && canAfford(seat, _costRoad) && handSize(seat) >= 6) {
      return {'type': 'road', 'e': _bestRoad(seat, roads)};
    }
    // bank trade toward a goal
    if (botBankTrades < 4) {
      final goals = <List<int>>[
        if (cities.isNotEmpty && citiesLeft[seat] > 0) _costCity,
        if (settles.isNotEmpty && settlementsLeft[seat] > 0) _costSettle,
        if (settles.isEmpty && roads.isNotEmpty) _costRoad,
        if (devDeck.isNotEmpty) _costDev,
      ];
      for (final goal in goals) {
        final d = _deficit(seat, goal);
        final need = d.fold(0, (a, b) => a + b);
        if (need == 0) continue;
        var can = 0;
        int? giveR;
        for (var r = 0; r < 5; r++) {
          final sur = h[r] - goal[r];
          final k = ratio(seat, r);
          if (sur >= k) {
            can += sur ~/ k;
            giveR ??= r;
          }
        }
        if (can >= need && giveR != null) {
          final getR = [for (var r = 0; r < 5; r++) if (d[r] > 0 && bank[r] > 0) r];
          if (getR.isEmpty) continue;
          botBankTrades++;
          return {'type': 'bank', 'give': giveR, 'get': getR.first};
        }
      }
    }
    // player trade offer
    if (!botOffered) {
      botOffered = true;
      final goal = _goal(seat);
      if (goal != null) {
        final d = _deficit(seat, goal);
        if (d.fold(0, (a, b) => a + b) == 1) {
          final want = d.indexWhere((x) => x > 0);
          var giveR = -1;
          for (var r = 0; r < 5; r++) {
            if (r != want && h[r] - goal[r] >= 1 && (giveR < 0 || h[r] - goal[r] > h[giveR] - goal[giveR])) giveR = r;
          }
          if (giveR >= 0) {
            final gv = List.filled(5, 0), gt = List.filled(5, 0);
            gv[giveR] = 1;
            gt[want] = 1;
            return {'type': 'offer', 'give': gv, 'get': gt, 'to': -1};
          }
        }
      }
    }
    return {'type': 'end'};
  }
}
