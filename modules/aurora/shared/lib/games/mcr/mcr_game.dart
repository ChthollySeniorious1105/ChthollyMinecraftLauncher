import '../../src/engine.dart';
import 'gd_fans.dart';
import 'mcr_fans.dart';
import 'shapes.dart';
import 'tiles.dart';

part 'mcr_view.dart';
part 'mcr_bot.dart';
part 'mcr_settle.dart';

/// Pending responses to a discard (or to a 补杠 for 抢杠).
class _Claim {
  final int tile;
  final int from;
  final bool rob; // 抢杠 window (only hu)
  final Map<int, Set<String>> opts; // seat -> {'hu','peng','gang','chi'}
  final Map<int, List<int>> chis; // seat -> lowest tiles of possible chows
  final Map<int, Map<String, dynamic>> resp = {};
  _Claim(this.tile, this.from, this.rob, this.opts, this.chis);
  List<int> get pending => [for (final s in opts.keys) if (!resp.containsKey(s)) s]..sort();
}

class _Discard {
  final int tile;
  bool taken = false;
  final bool tsumogiri; // 摸切: discarded the tile just drawn
  _Discard(this.tile, {this.tsumogiri = false});
}

/// Common result of evaluating a win for either ruleset.
class _Win {
  final int fan; // MCR: total fan incl. flowers; GD: fan (99 = limit)
  final int base; // MCR: fan excluding flowers (8番起和)
  final List<List<Object>> items; // [name, value, count]
  _Win(this.fan, this.base, this.items);
}

/// 国标麻将 (rule 'mcr') and 广东推倒胡 (rule 'gd').
class McrGame extends GameEngine {
  final String rule;
  McrGame(super.setup, this.rule);

  bool get isMcr => rule == 'mcr';
  late final int totalHands = setup.opt<int>('hands', isMcr ? 4 : 8);
  late final bool withFlowers = isMcr || setup.opt<bool>('flowers', false);
  late final int minFan = isMcr ? 8 : setup.opt<int>('minFan', 0);
  late final int horses = isMcr ? 0 : setup.opt<int>('horses', 2);
  late final bool genZhuang = !isMcr && setup.opt<bool>('gen', true);
  late final bool gdSevenPairs = !isMcr && setup.opt<bool>('qidui', true);
  late final int gdCap = setup.opt<int>('cap', 16);

  // match state
  late List<int> scores = List.filled(players, 0);
  int handNo = 0;
  int dealer = 0;
  int firstDealer = 0;
  int roundWind = 0;
  bool over = false;
  List<Map<String, dynamic>> history = [];

  // hand state
  String phase = 'act'; // act, claim, settle, over (pause = claim-cover delay)

  /// Phase to show/resume while [phase] is 'pause' (claim-cover delay).
  String pausedPhase = '';
  List<List<int>> hands = [];
  List<List<int>> flowers = [];
  List<List<Meld>> melds = [];
  List<List<_Discard>> discards = [];
  List<int> drawn = [];
  List<int> wall = [];
  int turn = 0;
  bool canTsumo = false;
  bool afterKong = false;
  _Claim? claim;
  int lastDiscardSeat = -1;
  String lastAction = '';

  /// Latest public table event (discard / call / win) for client animations;
  /// [eventSeq] increments on every event so clients can replay them.
  Map<String, dynamic>? lastEvent;
  int eventSeq = 0;
  void _event(String t, int seat, [int tile = -1]) {
    lastEvent = {'t': t, 'seat': seat, if (tile >= 0) 'tile': tileCode(tile)};
    eventSeq++;
  }
  List<int> handDelta = [];
  Map<String, dynamic>? settle;
  Set<int> ready = {};
  int winner = -1;
  List<int> firstDiscards = [];
  bool anyCall = false;
  bool genPaid = false;
  bool nextDealerKeep = false;

  int seatWind(int s) => (s - dealer + players) % players;

  @override
  void start() {
    firstDealer = rng.nextInt(players);
    dealer = firstDealer;
    _startHand();
  }

  void _startHand() {
    handNo++;
    roundWind = isMcr ? ((handNo - 1) ~/ 4) % 4 : 0;
    final tiles = <int>[
      for (var t = 0; t < kKinds; t++)
        for (var k = 0; k < 4; k++) t,
      if (withFlowers)
        for (var f = 0; f < 8; f++) kFlowerBase + f,
    ]..shuffle(rng);
    wall = tiles;
    hands = List.generate(players, (_) => List.filled(kKinds, 0));
    flowers = List.generate(players, (_) => <int>[]);
    melds = List.generate(players, (_) => <Meld>[]);
    discards = List.generate(players, (_) => <_Discard>[]);
    drawn = List.filled(players, -1);
    handDelta = List.filled(players, 0);
    settle = null;
    claim = null;
    winner = -1;
    lastDiscardSeat = -1;
    firstDiscards = [];
    anyCall = false;
    genPaid = false;
    afterKong = false;
    for (var i = 0; i < 13; i++) {
      for (var s = 0; s < players; s++) {
        _give(s, wall.removeLast());
      }
    }
    // 补花 for the initial hands
    for (var i = 0; i < players; i++) {
      final s = (dealer + i) % players;
      _replaceFlowers(s);
    }
    phase = 'act';
    turn = dealer;
    host.log('第 $handNo/$totalHands 局开始，${name(dealer)} 坐庄'
        '${isMcr ? '（${windNames[roundWind]}圈）' : ''}');
    _draw(dealer);
    lastAction = '${name(dealer)} 庄家出牌';
  }

  void _give(int s, int t) {
    if (isFlower(t)) {
      flowers[s].add(t);
    } else {
      hands[s][t]++;
    }
  }

  /// Initial 补花: draw replacements from the back of the wall until no flowers remain.
  void _replaceFlowers(int s) {
    var need = flowers[s].length;
    while (need > 0 && wall.isNotEmpty) {
      final t = wall.removeAt(0);
      need--;
      if (isFlower(t)) {
        flowers[s].add(t);
        need++;
      } else {
        hands[s][t]++;
      }
    }
    if (flowers[s].isNotEmpty) host.log('${name(s)} 补花 ${flowers[s].length} 张');
  }

  /// Normal draw (or kong replacement) for [s]. Ends the hand if the wall is empty.
  bool _draw(int s, {bool kong = false}) {
    turn = s;
    while (true) {
      if (wall.isEmpty) {
        _drawnGame();
        return false;
      }
      final t = kong ? wall.removeAt(0) : wall.removeLast();
      if (isFlower(t)) {
        flowers[s].add(t);
        host.log('${name(s)} 补花 ${tileName(t)}');
        _event('buhua', s, t);
        kong = true; // replacement comes from the back end
        continue;
      }
      hands[s][t]++;
      drawn[s] = t;
      break;
    }
    phase = 'act';
    canTsumo = true;
    afterKong = afterKongFlag;
    afterKongFlag = false;
    return true;
  }

  bool afterKongFlag = false;

  // ------------------------------------------------------------------ evaluation

  int _visibleCopies(int t) {
    var n = 0;
    for (var s = 0; s < players; s++) {
      for (final d in discards[s]) {
        if (d.tile == t && !d.taken) n++;
      }
      for (final m in melds[s]) {
        if (m.kind == 'agang') continue;
        for (final x in m.tiles) {
          if (x == t) n++;
        }
      }
    }
    return n;
  }

  _Win? evalWin(int s, int tile, {required bool tsumo, bool rob = false}) {
    final c = List.of(hands[s]);
    if (!tsumo) c[tile]++;
    if (!isWinShape(c, melds[s].length)) return null;
    final last = wall.isEmpty;
    if (isMcr) {
      final ctx = WinCtx(tile,
          selfDrawn: tsumo,
          seatWind: seatWind(s),
          roundWind: roundWind,
          lastTile: last && !rob,
          kongDraw: tsumo && afterKong,
          robKong: rob,
          lastCopy: !rob && _lastCopy(s, tile, tsumo),
          flowers: flowers[s].length);
      final r = evaluateMcr(c, melds[s], ctx);
      if (r == null) return null;
      return _Win(r.total, r.base, [for (final e in r.items) e.toJson()]);
    }
    final r = evaluateGd(c, melds[s],
        GdCtx(
            selfDrawn: tsumo,
            kongDraw: tsumo && afterKong,
            robKong: rob,
            lastTile: last && tsumo,
            sevenPairs: gdSevenPairs,
            flowers: withFlowers ? flowers[s].length : 0));
    if (r == null) return null;
    return _Win(r.fan, r.fan, [for (final (n, f) in r.items) [n, f >= gdLimit ? '满' : f, 1]]);
  }

  /// 和绝张: the winning tile is the 4th copy and the other three are on the table.
  bool _lastCopy(int s, int tile, bool tsumo) {
    final onTable = _visibleCopies(tile);
    // for a discard win the claimed tile itself is still counted among discards
    final others = tsumo ? onTable : onTable - 1;
    return others >= 3;
  }

  bool canWin(int s, int tile, {required bool tsumo, bool rob = false}) {
    final w = evalWin(s, tile, tsumo: tsumo, rob: rob);
    return w != null && w.base >= minFan;
  }

  bool get canSelfWin => phase == 'act' && canTsumo && drawn[turn] >= 0 && canWin(turn, drawn[turn], tsumo: true);

  List<(int, bool)> selfKongs() {
    if (phase != 'act' || wall.isEmpty) return const [];
    final s = turn;
    final out = <(int, bool)>[];
    for (var t = 0; t < kKinds; t++) {
      if (hands[s][t] == 4) out.add((t, false));
      if (hands[s][t] >= 1 && melds[s].any((m) => m.kind == 'peng' && m.tile == t)) out.add((t, true));
    }
    return out;
  }

  List<int> chiOptions(int s, int t) {
    if (t >= 27) return const [];
    final h = hands[s];
    final r = rankOf(t);
    final out = <int>[];
    for (var lo = t - 2; lo <= t; lo++) {
      final lr = r - (t - lo);
      if (lr < 1 || lr > 7) continue;
      var ok = true;
      for (var k = lo; k < lo + 3; k++) {
        if (k != t && h[k] == 0) ok = false;
      }
      if (ok) out.add(lo);
    }
    return out;
  }

  // ------------------------------------------------------------------ engine API

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? rankByScore(scores) : null;
  @override
  Map<String, dynamic> view(int seat) => buildView(seat);
  @override
  Map<String, dynamic>? bot(int seat) => botAction(seat);
  @override
  int get botDelayMs => phase == 'claim' ? 500 : 700;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'act':
        return [turn];
      case 'claim':
        return claim!.pending;
      case 'settle':
        return [for (var s = 0; s < players; s++) if (!ready.contains(s)) s];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    switch (phase) {
      case 'act':
        if (seat != turn) throw GameError('还没轮到你');
        _handleAct(seat, type, a);
        return;
      case 'claim':
        _handleClaim(seat, type, a);
        return;
      case 'settle':
        if (type != 'next') throw GameError('请等待下一局');
        ready.add(seat);
        if (ready.length >= players) _nextHand();
        return;
    }
    throw GameError('现在不能操作');
  }

  void _handleAct(int s, String type, Map<String, dynamic> a) {
    if (type == 'hu') {
      if (!canSelfWin) {
        throw GameError(isMcr ? '不能和牌（需满 8 番，花牌不计）' : '不能胡牌');
      }
      _win(s, -1, drawn[s]);
      return;
    }
    if (type == 'gang') {
      final t = tileFromCode(a['tile']);
      final k = selfKongs().where((e) => e.$1 == t).toList();
      if (k.isEmpty) throw GameError('不能杠这张牌');
      _selfKong(s, t, k.first.$2);
      return;
    }
    if (type == 'discard') {
      final t = tileFromCode(a['tile']);
      if (t < 0 || t >= kKinds || hands[s][t] == 0) throw GameError('你没有这张牌');
      _discard(s, t);
      return;
    }
    throw GameError('请出牌');
  }

  void _discard(int s, int t) {
    hands[s][t]--;
    final giri = drawn[s] == t;
    drawn[s] = -1;
    discards[s].add(_Discard(t, tsumogiri: giri));
    canTsumo = false;
    afterKong = false;
    lastDiscardSeat = s;
    lastAction = '${name(s)} 打出 ${tileName(t)}';
    _event('discard', s, t);
    if (genZhuang && !anyCall && firstDiscards.length < players) {
      firstDiscards.add(t);
      if (firstDiscards.length == players && firstDiscards.every((x) => x == firstDiscards.first)) {
        genPaid = true;
        for (var o = 0; o < players; o++) {
          if (o == dealer) continue;
          _pay(dealer, o, 1);
        }
        host.log('跟庄！${name(dealer)} 向每家支付 1 分');
      }
    }
    final opts = <int, Set<String>>{};
    final chis = <int, List<int>>{};
    for (var o = 0; o < players; o++) {
      if (o == s) continue;
      final set = <String>{};
      if (canWin(o, t, tsumo: false)) set.add('hu');
      if (wall.isNotEmpty) {
        if (hands[o][t] >= 2) set.add('peng');
        if (hands[o][t] >= 3) set.add('gang');
        if (o == (s + 1) % players) {
          final c = chiOptions(o, t);
          if (c.isNotEmpty) {
            set.add('chi');
            chis[o] = c;
          }
        }
      }
      if (set.isNotEmpty) opts[o] = set;
    }
    if (opts.isEmpty) {
      _coverPause(() => _nextDraw(s));
    } else {
      claim = _Claim(t, s, false, opts, chis);
      phase = 'claim';
    }
  }

  /// Nobody can claim: sometimes pause 0.5–1 s anyway (雀魂-style) so timing
  /// doesn't reveal whether anyone could have called.
  void _coverPause(void Function() next) {
    final ms = claimCoverDelayMs(rng);
    if (ms == 0) {
      next();
      return;
    }
    pausedPhase = phase;
    phase = 'pause';
    host.schedule(ms, () {
      if (phase != 'pause') return;
      phase = pausedPhase;
      next();
    });
  }

  void _nextDraw(int from) {
    claim = null;
    _draw((from + 1) % players);
  }

  int _prio(int from, int s, String type) {
    final dist = (s - from + players) % players; // 1..3, nearer first
    switch (type) {
      case 'hu':
        return 30 - dist;
      case 'gang':
      case 'peng':
        return 20;
      case 'chi':
        return 10;
    }
    return 0;
  }

  int _maxPrio(_Claim c, int s) {
    var best = 0;
    for (final o in c.opts[s]!) {
      final p = _prio(c.from, s, o);
      if (p > best) best = p;
    }
    return best;
  }

  void _handleClaim(int s, String type, Map<String, dynamic> a) {
    final c = claim!;
    final o = c.opts[s];
    if (o == null) throw GameError('你没有可执行的操作');
    if (c.resp.containsKey(s)) throw GameError('你已经选择了');
    if (type != 'pass' && !o.contains(type)) throw GameError('不能执行该操作');
    final r = <String, dynamic>{'type': type};
    if (type == 'chi') {
      final lo = tileFromCode(a['tile']);
      final list = c.chis[s] ?? const [];
      r['lo'] = list.contains(lo) ? lo : list.first;
    }
    c.resp[s] = r;
    // resolve once nobody pending could beat the best response so far
    var best = 0;
    for (final e in c.resp.entries) {
      final p = _prio(c.from, e.key, e.value['type'] as String);
      if (p > best) best = p;
    }
    final pend = c.pending;
    if (pend.any((p) => _maxPrio(c, p) > best)) return;
    _resolveClaim();
  }

  void _resolveClaim() {
    final c = claim!;
    claim = null;
    var bestSeat = -1, best = 0;
    for (final e in c.resp.entries) {
      final p = _prio(c.from, e.key, e.value['type'] as String);
      if (p > best) {
        best = p;
        bestSeat = e.key;
      }
    }
    if (bestSeat < 0) {
      if (c.rob) {
        _finishBuGang(c.from, c.tile);
      } else {
        _nextDraw(c.from);
      }
      return;
    }
    final r = c.resp[bestSeat]!;
    final type = r['type'] as String;
    final s = bestSeat;
    if (type == 'hu') {
      _win(s, c.from, c.tile, rob: c.rob);
      return;
    }
    discards[c.from].last.taken = true;
    anyCall = true;
    if (type == 'gang') {
      hands[s][c.tile] -= 3;
      melds[s].add(Meld('mgang', c.tile, claimed: c.tile, from: c.from));
      if (!isMcr) _pay(c.from, s, 3);
      lastAction = '${name(s)} 明杠 ${tileName(c.tile)}';
      _event('gang', s, c.tile);
      afterKongFlag = true;
      _draw(s, kong: true);
      return;
    }
    if (type == 'peng') {
      hands[s][c.tile] -= 2;
      melds[s].add(Meld('peng', c.tile, claimed: c.tile, from: c.from));
      lastAction = '${name(s)} 碰 ${tileName(c.tile)}';
      _event('peng', s, c.tile);
    } else {
      final lo = r['lo'] as int;
      for (var k = lo; k < lo + 3; k++) {
        if (k != c.tile) hands[s][k]--;
      }
      melds[s].add(Meld('chi', lo, claimed: c.tile, from: c.from));
      lastAction = '${name(s)} 吃 ${tileName(c.tile)}';
      _event('chi', s, c.tile);
    }
    turn = s;
    phase = 'act';
    canTsumo = false;
    afterKong = false;
    drawn[s] = -1;
  }

  void _selfKong(int s, int t, bool bu) {
    anyCall = true;
    if (bu) {
      _event('bugang', s, t);
    } else {
      _event('angang', s);
    }
    if (bu) {
      final opts = <int, Set<String>>{};
      for (var o = 0; o < players; o++) {
        if (o != s && canWin(o, t, tsumo: false, rob: true)) opts[o] = {'hu'};
      }
      if (opts.isNotEmpty) {
        claim = _Claim(t, s, true, opts, const {});
        phase = 'claim';
        lastAction = '${name(s)} 补杠 ${tileName(t)}';
        return;
      }
      _finishBuGang(s, t);
      return;
    }
    hands[s][t] -= 4;
    melds[s].add(Meld('agang', t));
    if (!isMcr) {
      for (var o = 0; o < players; o++) {
        if (o != s) _pay(o, s, 2);
      }
    }
    lastAction = '${name(s)} 暗杠';
    host.log('${name(s)} 暗杠');
    afterKongFlag = true;
    _draw(s, kong: true);
  }

  void _finishBuGang(int s, int t) {
    hands[s][t]--;
    final m = melds[s].firstWhere((m) => m.kind == 'peng' && m.tile == t);
    m.kind = 'bgang';
    if (!isMcr) {
      for (var o = 0; o < players; o++) {
        if (o != s) _pay(o, s, 1);
      }
    }
    lastAction = '${name(s)} 补杠 ${tileName(t)}';
    host.log(lastAction);
    afterKongFlag = true;
    _draw(s, kong: true);
  }

  void _pay(int from, int to, int amt) {
    scores[from] -= amt;
    scores[to] += amt;
    handDelta[from] -= amt;
    handDelta[to] += amt;
  }
}
