import 'dart:math';

import '../../src/engine.dart';
import 'duel_data.dart';

class DuelSlot {
  final int card;
  final int row, x;
  bool up;
  bool taken = false;
  DuelSlot(this.card, this.row, this.x, this.up);
}

class DuelWonderState {
  final int id;
  bool built = false;
  bool out = false; // 7-wonder limit
  int age = 0;
  DuelWonderState(this.id);
}

/// 七大奇迹·对决 7 Wonders Duel.
class Duel extends GameEngine {
  Duel(super.setup);

  int age = 0;
  String phase = 'draft'; // draft / play / token / library / destroy / revive / start / over
  int turn = 0; // acting seat
  int firstPlayer = 0;
  List<DuelSlot> slots = [];
  final List<int> coins = [7, 7];
  final List<List<int>> built = [[], []];
  final List<List<DuelWonderState>> wonders = [[], []];
  final List<List<int>> tokens = [[], []];
  List<int> boardTokens = [];
  List<int> boxTokens = [];
  List<int> libraryOffer = [];
  List<int> discardPile = [];
  int military = 0; // >0 toward seat 1's capital
  final List<List<bool>> loot = [
    [true, true],
    [true, true]
  ]; // loot[victim][0]=2 coins at 3, [1]=5 coins at 6
  // wonder draft
  List<int> wonderPool = [];
  List<int> offer = [];
  List<int> draftOrder = [];
  int draftIdx = 0;
  // pending effects for the acting player
  final List<String> pending = [];
  bool extraTurn = false;
  String destroyKind = '';
  int lastActor = 0;
  Map<String, dynamic>? last;
  final List<String> recent = [];
  Map<String, dynamic>? result;
  int winner = -1; // -2 = draw
  List<int> ageDeck = [];

  void _log(String s) {
    host.log(s);
    recent.add(s);
    if (recent.length > 10) recent.removeAt(0);
  }

  @override
  void start() {
    final all = shuffled(List.generate(10, (i) => i), rng);
    boardTokens = all.sublist(0, 5)..sort();
    boxTokens = all.sublist(5);
    wonderPool = shuffled(List.generate(12, (i) => i), rng).sublist(0, 8);
    firstPlayer = rng.nextInt(2);
    _startDraftRound(0);
    _log('七大奇迹·对决：${name(firstPlayer)} 先开始挑选奇迹');
  }

  void _startDraftRound(int r) {
    offer = wonderPool.sublist(r * 4, r * 4 + 4);
    final a = r == 0 ? firstPlayer : 1 - firstPlayer;
    draftOrder = [a, 1 - a, 1 - a, a];
    draftIdx = 0;
    phase = 'draft';
    turn = a;
  }

  void _deal(int a) {
    age = a;
    final pool = [for (var i = 0; i < duelGuildStart; i++) if (duelCards[i].age == a) i];
    var deck = shuffled(pool, rng).sublist(0, a == 3 ? 17 : 20);
    if (a == 3) {
      final guilds = shuffled([for (var i = duelGuildStart; i < duelCards.length; i++) i], rng).sublist(0, 3);
      deck = shuffled([...deck, ...guilds], rng);
    }
    ageDeck = deck;
    slots = [];
    final layout = duelLayouts[a - 1];
    var k = 0;
    for (var r = 0; r < layout.length; r++) {
      for (final x in layout[r]) {
        slots.add(DuelSlot(deck[k++], r, x, !duelDownRows[a - 1].contains(r)));
      }
    }
    _log('第 ${['一', '二', '三'][a - 1]} 时代开始');
  }

  // ------------------------------------------------------------------ structure
  bool covered(int i) {
    final s = slots[i];
    for (final o in slots) {
      if (!o.taken && o.row == s.row + 1 && (o.x - s.x).abs() == 1) return true;
    }
    return false;
  }

  bool accessible(int i) => !slots[i].taken && !covered(i);

  void _flipUncovered() {
    for (var i = 0; i < slots.length; i++) {
      if (!slots[i].taken && !slots[i].up && !covered(i)) slots[i].up = true;
    }
  }

  // ------------------------------------------------------------------ economy
  int opp(int p) => 1 - p;
  List<int> fixedProd(int p) {
    final r = List.filled(5, 0);
    for (final c in built[p]) {
      final d = duelCards[c];
      for (var k = 0; k < 5; k++) {
        r[k] += d.prod[k];
      }
    }
    return r;
  }

  List<List<int>> choiceProd(int p) => [
        for (final c in built[p])
          if (duelCards[c].choice.isNotEmpty) duelCards[c].choice,
        for (final w in wonders[p])
          if (w.built && duelWonders[w.id].fx == 'choiceWCS') const [0, 1, 2],
        for (final w in wonders[p])
          if (w.built && duelWonders[w.id].fx == 'choiceGP') const [3, 4],
      ];

  bool hasFx(int p, String fx) => built[p].any((c) => duelCards[c].fx == fx);
  bool hasToken(int p, String id) => tokens[p].contains(duelTokenIndex(id));

  List<int> tradePrices(int p) {
    final op = fixedProd(opp(p));
    return [
      for (var k = 0; k < 5; k++)
        (k == 0 && hasFx(p, 'fixW')) || (k == 1 && hasFx(p, 'fixC')) || (k == 2 && hasFx(p, 'fixS')) || (k >= 3 && hasFx(p, 'fixGP'))
            ? 1
            : 2 + op[k],
    ];
  }

  /// Minimal coins spent on trading for [cost] with [discount] free units.
  int tradeCost(int p, List<int> cost, int discount) {
    final fixed = fixedProd(p);
    final need = [for (var k = 0; k < 5; k++) max(0, cost[k] - fixed[k])];
    if (need.every((n) => n == 0)) return 0;
    final prices = tradePrices(p);
    final ch = choiceProd(p);
    var best = 1 << 30;
    void rec(int i, List<int> n) {
      if (i == ch.length) {
        final units = <int>[];
        for (var k = 0; k < 5; k++) {
          for (var u = 0; u < n[k]; u++) {
            units.add(prices[k]);
          }
        }
        units.sort((a, b) => b - a);
        var s = 0;
        for (var u = discount; u < units.length; u++) {
          s += units[u];
        }
        best = min(best, s);
        return;
      }
      var used = false;
      for (final r in ch[i]) {
        if (n[r] > 0) {
          used = true;
          n[r]--;
          rec(i + 1, n);
          n[r]++;
        }
      }
      if (!used) rec(i + 1, n);
    }

    rec(0, need);
    return best;
  }

  bool chainFree(int p, int card) {
    final ch = duelCards[card].chain;
    return ch.isNotEmpty && built[p].any((c) => duelCards[c].link == ch);
  }

  /// (total coins, trading part) to build [card].
  (int, int) cardCost(int p, int card) {
    if (chainFree(p, card)) return (0, 0);
    final d = duelCards[card];
    final t = tradeCost(p, d.cost, d.kind == 'blue' && hasToken(p, 'masonry') ? 2 : 0);
    return (d.coins + t, t);
  }

  (int, int) wonderCost(int p, int w) {
    final t = tradeCost(p, duelWonders[w].cost, hasToken(p, 'architecture') ? 2 : 0);
    return (t, t);
  }

  int sellValue(int p) => 2 + built[p].where((c) => duelCards[c].kind == 'yellow').length;

  void _pay(int p, int total, int trade) {
    coins[p] -= total;
    if (trade > 0 && hasToken(opp(p), 'economy')) {
      coins[opp(p)] += trade;
      _log('${name(opp(p))} 的“经济”获得对手交易的 $trade 金币');
    }
  }

  int count(int p, String kind) => built[p].where((c) => duelCards[c].kind == kind).length;
  int wondersBuilt(int p) => wonders[p].where((w) => w.built).length;

  // ------------------------------------------------------------------ military / science
  void _shields(int p, int n) {
    if (n <= 0) return;
    final dir = p == 0 ? 1 : -1;
    military = (military + dir * n).clamp(-9, 9);
    final victim = opp(p);
    final m = military * dir; // progress toward victim capital
    for (final (idx, at, amt) in const [(0, 3, 2), (1, 6, 5)]) {
      if (m >= at && loot[victim][idx]) {
        loot[victim][idx] = false;
        final lost = min(amt, coins[victim]);
        coins[victim] -= lost;
        _log('军事标记：${name(victim)} 失去 $lost 金币');
      }
    }
    if (m >= 9) _win(p, 'military');
  }

  List<int> symbols(int p) {
    final s = <int>[
      for (final c in built[p])
        if (duelCards[c].sci >= 0) duelCards[c].sci,
    ];
    if (hasToken(p, 'law')) s.add(6);
    return s;
  }

  void _checkScience(int p) {
    if (symbols(p).toSet().length >= 6) _win(p, 'science');
  }

  // test hooks
  List<int> duelCost(String s) => [for (final ch in 'WCSGP'.split('')) s.split('').where((x) => x == ch).length];
  void testShields(int p, int n) => _shields(p, n);
  void testApply(int p, int card) => _applyCard(p, card);

  // ------------------------------------------------------------------ actions
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    switch (phase) {
      case 'draft':
        if (type != 'draft') throw GameError('请挑选一座奇迹');
        final k = asInt(a['w']);
        if (k < 0 || k >= offer.length) throw GameError('无效的奇迹');
        _takeWonder(seat, k);
        return;
      case 'start':
        if (type != 'start') throw GameError('请选择下一时代由谁先手');
        final s = asInt(a['seat']);
        if (s != 0 && s != 1) throw GameError('无效玩家');
        _log('${name(seat)} 决定由 ${name(s)} 开始第 ${['一', '二', '三'][age - 1]} 时代');
        turn = s;
        phase = 'play';
        return;
      case 'token':
      case 'library':
        if (type != 'token') throw GameError('请选择一个进步标记');
        final t = asInt(a['t']);
        final from = phase == 'token' ? boardTokens : libraryOffer;
        if (!from.contains(t)) throw GameError('不能选这个标记');
        from.remove(t);
        if (phase == 'library') {
          boxTokens.addAll(libraryOffer);
          libraryOffer = [];
        }
        _gainToken(seat, t);
        _resolve();
        return;
      case 'destroy':
        if (type != 'destroy') throw GameError('请选择要摧毁的卡');
        final c = asInt(a['card']);
        if (!built[opp(seat)].contains(c) || duelCards[c].kind != destroyKind) throw GameError('不能摧毁这张卡');
        built[opp(seat)].remove(c);
        discardPile.add(c);
        _log('${name(seat)} 摧毁了 ${name(opp(seat))} 的「${duelCards[c].name}」');
        _resolve();
        return;
      case 'revive':
        if (type != 'revive') throw GameError('请从弃牌堆选一张卡');
        final c = asInt(a['card']);
        if (!discardPile.contains(c)) throw GameError('弃牌堆里没有这张卡');
        discardPile.remove(c);
        _log('${name(seat)} 用摩索拉斯陵墓免费建造「${duelCards[c].name}」');
        _applyCard(seat, c, free: true);
        _resolve();
        return;
      case 'play':
        break;
      default:
        throw GameError('无效操作');
    }
    final i = asInt(a['slot']);
    if (i < 0 || i >= slots.length || !accessible(i)) throw GameError('这张卡现在拿不到');
    final card = slots[i].card;
    final d = duelCards[card];
    extraTurn = false;
    pending.clear();
    if (type == 'build') {
      final (total, trade) = cardCost(seat, card);
      if (coins[seat] < total) throw GameError('金币不足（需要 $total）');
      final chain = chainFree(seat, card);
      _take(i);
      _pay(seat, total, trade);
      last = {'seat': seat, 'type': 'build', 'card': card, 'paid': total, 'age': age};
      _log('${name(seat)} 建造「${d.name}」${chain ? '（连锁免费）' : (total > 0 ? '，花费 $total 金币' : '')}');
      if (chain && hasToken(seat, 'urbanism')) {
        coins[seat] += 4;
        _log('城市规划：${name(seat)} 获得 4 金币');
      }
      _applyCard(seat, card);
    } else if (type == 'discard') {
      _take(i);
      final v = sellValue(seat);
      coins[seat] += v;
      discardPile.add(card);
      last = {'seat': seat, 'type': 'discard', 'card': card, 'gain': v, 'age': age};
      _log('${name(seat)} 弃掉「${d.name}」换 $v 金币');
    } else if (type == 'wonder') {
      final w = asInt(a['w']);
      if (w < 0 || w >= wonders[seat].length) throw GameError('无效的奇迹');
      final ws = wonders[seat][w];
      if (ws.built) throw GameError('这座奇迹已经建成');
      if (ws.out) throw GameError('已建成 7 座奇迹，这座奇迹无法再建造');
      final (total, trade) = wonderCost(seat, ws.id);
      if (coins[seat] < total) throw GameError('金币不足（需要 $total）');
      _take(i);
      _pay(seat, total, trade);
      ws.built = true;
      ws.age = age;
      last = {'seat': seat, 'type': 'wonder', 'card': card, 'wonder': ws.id, 'paid': total, 'age': age};
      _log('${name(seat)} 建成奇迹「${duelWonders[ws.id].name}」${total > 0 ? '，花费 $total 金币' : ''}');
      _applyWonder(seat, ws.id);
      if (wondersBuilt(0) + wondersBuilt(1) >= 7) {
        for (final list in wonders) {
          for (final x in list) {
            if (!x.built && !x.out) {
              x.out = true;
              _log('已建成 7 座奇迹：「${duelWonders[x.id].name}」被移出游戏');
            }
          }
        }
      }
    } else {
      throw GameError('无效操作');
    }
    lastActor = seat;
    _resolve();
  }

  void _take(int i) {
    slots[i].taken = true;
    _flipUncovered();
  }

  void _takeWonder(int seat, int k) {
    final w = offer.removeAt(k);
    wonders[seat].add(DuelWonderState(w));
    _log('${name(seat)} 挑选了奇迹「${duelWonders[w].name}」');
    draftIdx++;
    if (offer.length == 1) {
      final s = draftOrder[3];
      final lw = offer.removeAt(0);
      wonders[s].add(DuelWonderState(lw));
      _log('${name(s)} 获得最后一座奇迹「${duelWonders[lw].name}」');
      if (wonders[0].length + wonders[1].length == 4) {
        _startDraftRound(1);
      } else {
        _deal(1);
        turn = firstPlayer;
        phase = 'play';
      }
      return;
    }
    turn = draftOrder[draftIdx];
  }

  void _gainToken(int p, int t) {
    tokens[p].add(t);
    final tk = duelTokens[t];
    _log('${name(p)} 获得进步标记「${tk.name}」');
    if (tk.id == 'agriculture' || tk.id == 'urbanism') coins[p] += 6;
    if (tk.id == 'law') _checkScience(p);
  }

  void _applyCard(int p, int card, {bool free = false}) {
    final d = duelCards[card];
    built[p].add(card);
    switch (d.fx) {
      case 'coins4':
        coins[p] += 4;
      case 'coins6':
        coins[p] += 6;
      case 'perGrey3':
        coins[p] += 3 * count(p, 'grey');
      case 'perBrown2':
        coins[p] += 2 * count(p, 'brown');
      case 'perRed1':
        coins[p] += count(p, 'red');
      case 'perYellow1':
        coins[p] += count(p, 'yellow');
      case 'perWonder2':
        coins[p] += 2 * wondersBuilt(p);
      case 'gYellow':
        coins[p] += max(count(0, 'yellow'), count(1, 'yellow'));
      case 'gBrownGrey':
        coins[p] += max(count(0, 'brown') + count(0, 'grey'), count(1, 'brown') + count(1, 'grey'));
      case 'gBlue':
        coins[p] += max(count(0, 'blue'), count(1, 'blue'));
      case 'gGreen':
        coins[p] += max(count(0, 'green'), count(1, 'green'));
      case 'gRed':
        coins[p] += max(count(0, 'red'), count(1, 'red'));
    }
    if (d.shields > 0) {
      _shields(p, d.shields + (d.kind == 'red' && hasToken(p, 'strategy') ? 1 : 0));
    }
    if (d.sci >= 0 && phase != 'over') {
      final n = built[p].where((c) => duelCards[c].sci == d.sci).length;
      if (n == 2 && boardTokens.isNotEmpty) pending.add('token');
      _checkScience(p);
    }
  }

  void _applyWonder(int p, int w) {
    final d = duelWonders[w];
    if (d.replay || hasToken(p, 'theology')) extraTurn = true;
    switch (d.fx) {
      case 'appian':
        coins[p] += 3;
        final lost = min(3, coins[opp(p)]);
        coins[opp(p)] -= lost;
      case 'coins6':
        coins[p] += 6;
      case 'coins12':
        coins[p] += 12;
      case 'destroyGrey':
        if (built[opp(p)].any((c) => duelCards[c].kind == 'grey')) pending.add('destroy:grey');
      case 'destroyBrown':
        if (built[opp(p)].any((c) => duelCards[c].kind == 'brown')) pending.add('destroy:brown');
      case 'library':
        if (boxTokens.isNotEmpty) pending.add('library');
      case 'mausoleum':
        if (discardPile.isNotEmpty) pending.add('revive');
    }
    _shields(p, d.shields);
  }

  /// Resolve pending sub-choices, then end the turn.
  void _resolve() {
    if (phase == 'over') return;
    while (pending.isNotEmpty) {
      final t = pending.removeAt(0);
      if (t == 'token') {
        if (boardTokens.isEmpty) continue;
        phase = 'token';
        return;
      }
      if (t == 'library') {
        final pick = shuffled(boxTokens, rng);
        libraryOffer = pick.sublist(0, min(3, pick.length));
        for (final x in libraryOffer) {
          boxTokens.remove(x);
        }
        phase = 'library';
        return;
      }
      if (t.startsWith('destroy:')) {
        destroyKind = t.substring(8);
        if (!built[opp(turn)].any((c) => duelCards[c].kind == destroyKind)) continue;
        phase = 'destroy';
        return;
      }
      if (t == 'revive') {
        if (discardPile.isEmpty) continue;
        phase = 'revive';
        return;
      }
    }
    phase = 'play';
    _endTurn();
  }

  void _endTurn() {
    if (slots.every((s) => s.taken)) {
      if (age == 3) {
        _civilEnd();
        return;
      }
      final chooser = military > 0 ? 1 : (military < 0 ? 0 : lastActor);
      _deal(age + 1);
      phase = 'start';
      turn = chooser;
      return;
    }
    if (!extraTurn) turn = opp(turn);
    extraTurn = false;
  }

  // ------------------------------------------------------------------ scoring
  int militaryVp(int p) {
    final m = p == 0 ? military : -military;
    if (m <= 0) return 0;
    if (m <= 2) return 2;
    if (m <= 5) return 5;
    return 10;
  }

  int guildVp(int p, int card) {
    int mx(int Function(int) f) => max(f(0), f(1));
    switch (duelCards[card].fx) {
      case 'gYellow':
        return mx((s) => count(s, 'yellow'));
      case 'gBrownGrey':
        return mx((s) => count(s, 'brown') + count(s, 'grey'));
      case 'gWonder':
        return 2 * mx(wondersBuilt);
      case 'gBlue':
        return mx((s) => count(s, 'blue'));
      case 'gGreen':
        return mx((s) => count(s, 'green'));
      case 'gCoins':
        return mx((s) => coins[s]) ~/ 3;
      case 'gRed':
        return mx((s) => count(s, 'red'));
    }
    return 0;
  }

  Map<String, int> breakdown(int p) {
    var blue = 0, green = 0, yellow = 0, guild = 0;
    for (final c in built[p]) {
      final d = duelCards[c];
      if (d.kind == 'blue') blue += d.vp;
      if (d.kind == 'green') green += d.vp;
      if (d.kind == 'yellow') yellow += d.vp;
      if (d.kind == 'guild') guild += guildVp(p, c);
    }
    final won = wonders[p].where((w) => w.built).fold(0, (s, w) => s + duelWonders[w.id].vp);
    var tok = 0;
    for (final t in tokens[p]) {
      final id = duelTokens[t].id;
      if (id == 'agriculture') tok += 4;
      if (id == 'philosophy') tok += 7;
      if (id == 'mathematics') tok += 3 * tokens[p].length;
    }
    final mil = militaryVp(p);
    final coin = coins[p] ~/ 3;
    return {
      'blue': blue, 'green': green, 'yellow': yellow, 'guild': guild, 'wonder': won, 'token': tok, 'military': mil, 'coins': coin,
      'total': blue + green + yellow + guild + won + tok + mil + coin,
    };
  }

  void _civilEnd() {
    final b = [breakdown(0), breakdown(1)];
    final t0 = b[0]['total']!, t1 = b[1]['total']!;
    int w;
    if (t0 != t1) {
      w = t0 > t1 ? 0 : 1;
    } else if (b[0]['blue'] != b[1]['blue']) {
      w = b[0]['blue']! > b[1]['blue']! ? 0 : 1;
    } else {
      w = -2;
    }
    winner = w;
    phase = 'over';
    result = {'type': 'civil', 'winner': w, 'rows': b};
    _log(w == -2 ? '平局！（$t0 : $t1）' : '文明胜利：${name(w)} 获胜（$t0 : $t1）');
  }

  void _win(int p, String type) {
    if (phase == 'over') return;
    winner = p;
    phase = 'over';
    pending.clear();
    result = {'type': type, 'winner': p, 'rows': [breakdown(0), breakdown(1)]};
    _log('${type == 'military' ? '军事胜利' : (type == 'science' ? '科技胜利' : '胜利')}：${name(p)} 获胜！');
  }

  // ------------------------------------------------------------------ engine api
  @override
  List<int> get waitingFor => phase == 'over' ? const [] : [turn];
  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (winner == -2) return [1, 1];
    return winner == 0 ? [1, 2] : [2, 1];
  }

  @override
  bool get canResign => phase != 'over';

  @override
  void resign(int seat) {
    if (!canResign) throw GameError('当前不能认输');
    if (seat != 0 && seat != 1) throw GameError('无效座位');
    winner = 1 - seat;
    phase = 'over';
    pending.clear();
    result = {'type': 'resign', 'winner': winner, 'rows': [breakdown(0), breakdown(1)]};
    _log('${name(seat)} 认输，${name(winner)} 获胜');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat == 0 || seat == 1 ? seat : turn;
    return {
      'phase': phase,
      'age': age,
      'turn': turn,
      'first': firstPlayer,
      'military': military,
      'loot': loot,
      'offer': phase == 'draft' ? offer : const <int>[],
      'boardTokens': boardTokens,
      'library': seat == turn && phase == 'library' ? libraryOffer : const <int>[],
      'libraryCount': libraryOffer.length,
      'discard': discardPile,
      'destroyKind': phase == 'destroy' ? destroyKind : '',
      'slots': [
        for (var i = 0; i < slots.length; i++)
          {
            'row': slots[i].row,
            'x': slots[i].x,
            'taken': slots[i].taken,
            'up': slots[i].up,
            'card': slots[i].up && !slots[i].taken ? slots[i].card : null,
            'guild': !slots[i].up && !slots[i].taken && duelCards[slots[i].card].isGuild,
            'acc': accessible(i),
            'cost': accessible(i) && slots[i].up && phase == 'play' ? cardCost(me, slots[i].card).$1 : null,
            'chain': accessible(i) && slots[i].up && phase == 'play' ? chainFree(me, slots[i].card) : false,
          }
      ],
      'rows': age == 0 ? 0 : duelLayouts[age - 1].length,
      'players': [
        for (var p = 0; p < 2; p++)
          {
            'coins': coins[p],
            'built': built[p],
            'wonders': [
              for (final w in wonders[p])
                {'id': w.id, 'built': w.built, 'out': w.out, 'age': w.age, 'cost': !w.built && !w.out && phase == 'play' ? wonderCost(p, w.id).$1 : null}
            ],
            'tokens': tokens[p],
            'prod': fixedProd(p),
            'choice': choiceProd(p),
            'prices': tradePrices(p),
            'symbols': symbols(p),
            'sell': sellValue(p),
            'vp': breakdown(p)['total'],
          }
      ],
      'last': last,
      'recent': recent,
      'result': result,
      'winner': winner,
      'placings': placings,
    };
  }

  // ------------------------------------------------------------------ bot
  static const _wonderRank = [9, 6, 7, 6, 7, 8, 6, 7, 8, 8, 6, 9];
  static const _tokenRank = {
    'law': 8, 'strategy': 7, 'theology': 7, 'agriculture': 7, 'philosophy': 7, 'urbanism': 6, 'economy': 5,
    'masonry': 5, 'architecture': 6, 'mathematics': 6,
  };

  double _coinV() => age <= 1 ? 0.45 : (age == 2 ? 0.4 : 0.34);

  /// Military value of pushing [n] shields for seat p.
  double _milV(int p, int n) {
    if (n <= 0) return 0;
    final dir = p == 0 ? 1 : -1;
    final now = military * dir;
    final after = min(9, now + n);
    if (after >= 9) return 1000;
    var v = n * (age == 3 ? 2.2 : 1.5);
    // threat: opponent close to our capital → defending is valuable
    if (now <= -5) v += n * 2.0;
    v += (militaryVp(p) == 0 && after > 0 ? 1 : 0);
    for (final at in const [3, 6]) {
      if (now < at && after >= at && loot[opp(p)][at == 3 ? 0 : 1]) v += (at == 3 ? 2 : 5) * _coinV();
    }
    if (after >= 6) v += 2;
    return v;
  }

  double cardValue(int p, int card) {
    final d = duelCards[card];
    var v = d.vp.toDouble();
    if (d.shields > 0) v += _milV(p, d.shields + (d.kind == 'red' && hasToken(p, 'strategy') ? 1 : 0));
    if (d.sci >= 0) {
      final syms = symbols(p);
      final distinct = syms.toSet();
      final isNew = !distinct.contains(d.sci);
      if (isNew && distinct.length == 5) return 1000;
      v += isNew ? 2.5 + distinct.length * 0.6 : 0;
      if (!isNew && boardTokens.isNotEmpty) v += 4.5;
    }
    final pr = d.prod.fold(0, (a, b) => a + b);
    if (pr > 0) {
      final fixed = fixedProd(p);
      var pv = 0.0;
      for (var k = 0; k < 5; k++) {
        if (d.prod[k] > 0) pv += d.prod[k] * (fixed[k] >= 2 ? 0.6 : (fixed[k] == 1 ? 1.4 : 2.4));
      }
      v += pv * (age == 1 ? 1.2 : (age == 2 ? 0.8 : 0.2));
    }
    if (d.choice.isNotEmpty) v += age == 3 ? 0.8 : 2.2;
    switch (d.fx) {
      case 'fixW' || 'fixC' || 'fixS':
        v += age == 1 ? 1.8 : 0.8;
      case 'fixGP':
        v += 2.0;
      case 'coins4':
        v += 4 * _coinV();
      case 'coins6':
        v += 6 * _coinV();
      case 'perGrey3':
        v += 3 * count(p, 'grey') * _coinV();
      case 'perBrown2':
        v += 2 * count(p, 'brown') * _coinV();
      case 'perRed1':
        v += count(p, 'red') * _coinV();
      case 'perYellow1':
        v += (count(p, 'yellow') + 1) * _coinV();
      case 'perWonder2':
        v += 2 * wondersBuilt(p) * _coinV();
    }
    if (d.isGuild) {
      built[p].add(card);
      v += guildVp(p, card) + 1;
      built[p].remove(card);
    }
    if (d.link.isNotEmpty) v += age == 3 ? 0 : 0.8;
    return v;
  }

  double wonderValue(int p, int w) {
    final d = duelWonders[w];
    var v = d.vp.toDouble() + _milV(p, d.shields);
    if (d.replay || hasToken(p, 'theology')) v += 3;
    switch (d.fx) {
      case 'appian':
        v += 3 * _coinV() + min(3, coins[opp(p)]) * _coinV();
      case 'coins6':
        v += 6 * _coinV();
      case 'coins12':
        v += 12 * _coinV();
      case 'library':
        v += 4;
      case 'mausoleum':
        v += discardPile.isEmpty ? 0 : 3;
      case 'choiceWCS' || 'choiceGP':
        v += age == 3 ? 1 : 2.5;
      case 'destroyGrey' || 'destroyBrown':
        v += built[opp(p)].any((c) => duelCards[c].kind == (d.fx == 'destroyGrey' ? 'grey' : 'brown')) ? 2 : 0;
    }
    return v;
  }

  List<Map<String, dynamic>> _playActions(int p) {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < slots.length; i++) {
      if (!accessible(i)) continue;
      out.add({'type': 'discard', 'slot': i});
      if (cardCost(p, slots[i].card).$1 <= coins[p]) out.add({'type': 'build', 'slot': i});
      for (var w = 0; w < wonders[p].length; w++) {
        final ws = wonders[p][w];
        if (!ws.built && !ws.out && wonderCost(p, ws.id).$1 <= coins[p]) out.add({'type': 'wonder', 'slot': i, 'w': w});
      }
    }
    return out;
  }

  /// Face-up cards that would become accessible after taking slot [i].
  List<int> _revealedBy(int i) {
    final s = slots[i];
    final out = <int>[];
    for (var j = 0; j < slots.length; j++) {
      final o = slots[j];
      if (o.taken || o.row != s.row - 1 || (o.x - s.x).abs() != 1) continue;
      var still = false;
      for (final c in slots) {
        if (!c.taken && !identical(c, s) && c.row == o.row + 1 && (c.x - o.x).abs() == 1) still = true;
      }
      if (!still && o.up) out.add(j);
    }
    return out;
  }

  double _actionValue(int p, Map<String, dynamic> a) {
    final i = a['slot'] as int;
    final card = slots[i].card;
    double v;
    final cv = _coinV();
    switch (a['type']) {
      case 'build':
        final (total, _) = cardCost(p, card);
        v = cardValue(p, card) - total * cv;
        if (chainFree(p, card) && hasToken(p, 'urbanism')) v += 4 * cv;
      case 'wonder':
        final ws = wonders[p][a['w'] as int];
        final (total, _) = wonderCost(p, ws.id);
        v = wonderValue(p, ws.id) - total * cv + 0.5;
      default:
        v = sellValue(p) * cv - 0.8;
    }
    if (botLevel >= 2) {
      // deny: taking a card the opponent badly wants
      final ov = cardValue(opp(p), card);
      if (ov >= 1000) v += 500;
      v += ov * 0.25;
      // don't open great cards for the opponent
      for (final j in _revealedBy(i)) {
        final rv = cardValue(opp(p), slots[j].card);
        if (rv >= 1000 && cardCost(opp(p), slots[j].card).$1 <= coins[opp(p)] + 2) v -= 400;
        v -= rv * 0.2;
      }
    } else if (botLevel == 1) {
      final ov = cardValue(opp(p), card);
      if (ov >= 1000) v += 200;
    }
    return v;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'over' || seat != turn) return null;
    switch (phase) {
      case 'draft':
        var best = 0;
        var bv = -1e9;
        for (var k = 0; k < offer.length; k++) {
          final v = _wonderRank[offer[k]] + rng.nextDouble() * (botLevel == 0 ? 8 : 1.5);
          if (v > bv) {
            bv = v;
            best = k;
          }
        }
        return {'type': 'draft', 'w': best};
      case 'start':
        return {'type': 'start', 'seat': botLevel == 0 && rng.nextBool() ? opp(seat) : seat};
      case 'token':
      case 'library':
        final from = phase == 'token' ? boardTokens : libraryOffer;
        if (from.isEmpty) return null;
        var best = from.first;
        var bv = -1e9;
        for (final t in from) {
          var v = (_tokenRank[duelTokens[t].id] ?? 5) + rng.nextDouble() * (botLevel == 0 ? 6 : 1);
          if (duelTokens[t].id == 'law' && symbols(seat).toSet().length == 5) v += 1000;
          if (v > bv) {
            bv = v;
            best = t;
          }
        }
        return {'type': 'token', 't': best};
      case 'destroy':
        final opts = [for (final c in built[opp(seat)]) if (duelCards[c].kind == destroyKind) c];
        if (opts.isEmpty) return null;
        opts.sort((a, b) => duelCards[b].prod.fold(0, (x, y) => x + y) - duelCards[a].prod.fold(0, (x, y) => x + y));
        return {'type': 'destroy', 'card': opts.first};
      case 'revive':
        if (discardPile.isEmpty) return null;
        var best = discardPile.first;
        var bv = -1e9;
        for (final c in discardPile) {
          final v = cardValue(seat, c);
          if (v > bv) {
            bv = v;
            best = c;
          }
        }
        return {'type': 'revive', 'card': best};
    }
    final acts = _playActions(seat);
    if (acts.isEmpty) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.35) {
      final nonDiscard = acts.where((a) => a['type'] != 'discard').toList();
      final pool = nonDiscard.isNotEmpty ? nonDiscard : acts;
      return pool[rng.nextInt(pool.length)];
    }
    Map<String, dynamic>? best;
    var bv = -1e9;
    for (final a in acts) {
      final v = _actionValue(seat, a) + rng.nextDouble() * (botLevel == 0 ? 3 : 0.3);
      if (v > bv) {
        bv = v;
        best = a;
      }
    }
    return best;
  }
}

const duelRules = '''
# 七大奇迹·对决 7 Wonders Duel
两名玩家各自领导一个文明，经历三个时代，建造建筑与奇迹。可以通过三种方式获胜：军事胜利、科技胜利或文明胜利（终局分数）。

# 准备与奇迹挑选
- 每人 7 金币。10 个进步标记中随机 5 个放在棋盘上。
- 从 12 座奇迹中随机 8 座分两轮挑选：第一轮翻开 4 座，先手玩家选 1，对手选 2，先手拿最后 1 座；第二轮由对手先选 1，先手选 2，对手拿最后 1 座。每人 4 座奇迹。

# 卡牌结构
- 每个时代发 20 张卡组成结构：第一时代为金字塔（2-3-4-5-6），第二时代为倒金字塔（6-5-4-3-2），第三时代为特殊形状（2-3-4-2-4-3-2，其中混入 3 张随机行会卡）。
- 部分行的卡背面朝上；只有没有被下方卡压住的卡才能拿取。当一张面朝下的卡不再被压住时立即翻开。

# 回合
轮到你时从结构中拿一张可拿取的卡，然后三选一：
- 建造：支付卡上的金币与资源。
- 弃掉换钱：获得 2 金币 + 你每张黄卡再加 1 金币，卡进入弃牌堆。
- 建造奇迹：把这张卡压在你的一座未建奇迹下，支付奇迹的资源成本并获得效果。全场最多只能建成 7 座奇迹，第 7 座建成后剩余那座移出游戏。

# 资源与交易
- 棕卡、灰卡提供固定资源；部分黄卡和奇迹每回合提供几种资源中的一种。资源不会被消耗。
- 缺少的资源向银行购买：每单位 2 金币 + 对手棕/灰卡生产该资源的数量。黄卡“储备/海关”可把某些资源的价格固定为 1。
- 连锁：如果你已拥有带有对应连锁标志的卡（例如缮写室→图书馆），可以免费建造。

# 军事
- 红卡与部分奇迹上的盾牌会把冲突标记推向对手首都。越过 3 格与 6 格时，对手分别失去 2 与 5 金币（一次性）。
- 冲突标记到达对手首都（9 格）时立即军事胜利。

# 科技
- 共 7 种科学符号（6 种在绿卡上，第 7 种“天秤”来自法律标记）。每当你第一次凑齐一对相同符号，立即从棋盘上选择一个进步标记。
- 集齐 6 种不同科学符号立即科技胜利。

# 时代结束
- 结构拿完后时代结束。军事较弱的一方（冲突标记在自己一侧）决定下一时代由谁先手；持平时由拿走最后一张卡的玩家决定。
- 奇迹或效果带来的“再行动一回合”若恰逢时代结束则作废。

# 文明胜利
第三时代结束时计分：蓝卡、绿卡、第三时代黄卡、行会、奇迹、进步标记的分数；军事区域 2/5/10 分；每 3 金币 1 分。
分高者胜；平分时蓝卡分数多者胜，再相同则平局。

# 本实现
- 使用原版全部卡牌（第一、二时代各 23 张取 20 张，第三时代 20 张取 17 张 + 7 张行会取 3 张）、12 座奇迹与 10 个进步标记。
- 可以认输。
''';
