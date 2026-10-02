import '../../src/engine.dart';
import 'shapes.dart';
import 'tai.dart';
import 'tiles.dart';

part 'taiwan_view.dart';
part 'taiwan_bot.dart';
part 'taiwan_settle.dart';

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

/// 台湾十六张麻将.
class TaiwanGame extends GameEngine {
  TaiwanGame(super.setup);

  /// Tiles left undrawn at the end of the wall (留尾 8 墩).
  static const int reserve = 16;

  late final int totalRounds = setup.opt<int>('rounds', 4);
  late final int di = _stake().$1;
  late final int perTai = _stake().$2;

  (int, int) _stake() {
    final s = setup.opt<String>('stake', '100/20').split('/');
    return (int.tryParse(s[0]) ?? 100, int.tryParse(s.length > 1 ? s[1] : '') ?? 20);
  }

  // match state
  late List<int> scores = List.filled(players, 0);
  int handNo = 0;
  int dealer = 0;
  int firstDealer = 0;
  int dealerPasses = 0; // how many times the deal moved on
  int lian = 0; // 连庄 count (0 = first hand of this dealer)
  bool over = false;
  List<Map<String, dynamic>> history = [];

  int get roundWind => (dealerPasses ~/ players) % 4;

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
  bool afterKongFlag = false;
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
  bool anyCall = false;
  bool dealing = false;
  bool handEnded = false;
  List<int> drawCount = [];

  int seatWind(int s) => (s - dealer + players) % players;
  int get drawable => wall.length - reserve;

  @override
  void start() {
    firstDealer = rng.nextInt(players);
    dealer = firstDealer;
    _startHand();
  }

  void _startHand() {
    handNo++;
    wall = <int>[
      for (var t = 0; t < kKinds; t++)
        for (var k = 0; k < 4; k++) t,
      for (var f = 0; f < 8; f++) kFlowerBase + f,
    ]..shuffle(rng);
    hands = List.generate(players, (_) => List.filled(kKinds, 0));
    flowers = List.generate(players, (_) => <int>[]);
    melds = List.generate(players, (_) => <Meld>[]);
    discards = List.generate(players, (_) => <_Discard>[]);
    drawn = List.filled(players, -1);
    drawCount = List.filled(players, 0);
    handDelta = List.filled(players, 0);
    settle = null;
    claim = null;
    lastDiscardSeat = -1;
    anyCall = false;
    afterKong = false;
    afterKongFlag = false;
    handEnded = false;
    phase = 'act';
    turn = dealer;
    host.log('${windNames[roundWind]}风${windNames[(dealerPasses) % players]}局'
        '${lian > 0 ? ' 连$lian' : ''}：${name(dealer)} 坐庄');
    dealing = true;
    for (var i = 0; i < 16; i++) {
      for (var k = 0; k < players; k++) {
        final s = (dealer + k) % players;
        final t = wall.removeLast();
        if (isFlower(t)) {
          flowers[s].add(t);
        } else {
          hands[s][t]++;
        }
      }
    }
    // 补花 for the initial hands, dealer first
    for (var k = 0; k < players; k++) {
      final s = (dealer + k) % players;
      var need = flowers[s].length;
      while (need > 0) {
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
    dealing = false;
    // 八仙过海 / 七抢一 straight from the deal
    for (var s = 0; s < players; s++) {
      if (_checkFlowers(s)) return;
    }
    lastAction = '${name(dealer)} 庄家摸牌';
    _draw(dealer);
  }

  /// After [s] received a flower: 八仙过海 (all 8) or 七抢一 (someone else holds 7). Returns true if the hand ended.
  bool _checkFlowers(int s) {
    if (flowers[s].length == 8) {
      _flowerWin(s, -1);
      return true;
    }
    for (var o = 0; o < players; o++) {
      if (o == s) continue;
      if (flowers[s].length == 7 && flowers[o].length == 1) {
        _flowerWin(s, o);
        return true;
      }
      if (flowers[o].length == 7 && flowers[s].length == 1) {
        _flowerWin(o, s);
        return true;
      }
    }
    return false;
  }

  /// Normal draw (or kong / flower replacement) for [s]. Ends the hand on 流局.
  bool _draw(int s, {bool kong = false}) {
    turn = s;
    while (true) {
      if (drawable <= 0) {
        _drawnGame();
        return false;
      }
      final t = kong ? wall.removeAt(0) : wall.removeLast();
      if (isFlower(t)) {
        flowers[s].add(t);
        host.log('${name(s)} 补花 ${tileName(t)}');
        _event('buhua', s, t);
        lastAction = '${name(s)} 补花 ${tileName(t)}';
        if (_checkFlowers(s)) return false;
        kong = true; // replacement comes from the back end
        continue;
      }
      hands[s][t]++;
      drawn[s] = t;
      drawCount[s]++;
      break;
    }
    phase = 'act';
    canTsumo = true;
    afterKong = afterKongFlag;
    afterKongFlag = false;
    return true;
  }

  /// Test hook: perform a normal draw for [s].
  void drawnForTest(int s) => _draw(s);

  // ------------------------------------------------------------------ evaluation

  /// Context flags for a win by [s] on [tile].
  TaiCtx _ctx(int s, int tile, {required bool tsumo, bool rob = false}) {
    final firstGo = !anyCall && discards[s].isEmpty;
    final isDealer = s == dealer;
    return TaiCtx(tile,
        tsumo: tsumo,
        seatWind: seatWind(s),
        roundWind: roundWind,
        lastTile: drawable <= 0 && !rob,
        kongDraw: tsumo && afterKong,
        robKong: rob,
        tian: tsumo && isDealer && firstGo && drawCount[s] == 1,
        di: tsumo && !isDealer && firstGo && drawCount[s] == 1,
        ren: !tsumo && !isDealer && firstGo && drawCount[s] == 0,
        flowers: flowers[s]);
  }

  TaiResult? evalWin(int s, int tile, {required bool tsumo, bool rob = false}) {
    final c = List.of(hands[s]);
    if (!tsumo) c[tile]++;
    if (!isWinShape(c)) return null;
    return evaluateTai(c, melds[s], _ctx(s, tile, tsumo: tsumo, rob: rob));
  }

  bool canWin(int s, int tile, {required bool tsumo, bool rob = false}) {
    final c = List.of(hands[s]);
    if (!tsumo) c[tile]++;
    return isWinShape(c);
  }

  bool get canSelfWin => phase == 'act' && canTsumo && drawn[turn] >= 0 && canWin(turn, drawn[turn], tsumo: true);

  List<(int, bool)> selfKongs() {
    if (phase != 'act' || drawable <= 0) return const [];
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
      if (!canSelfWin) throw GameError('不能自摸');
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
    final opts = <int, Set<String>>{};
    final chis = <int, List<int>>{};
    for (var o = 0; o < players; o++) {
      if (o == s) continue;
      final set = <String>{};
      if (canWin(o, t, tsumo: false)) set.add('hu');
      if (drawable > 0) {
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
    final dist = (s - from + players) % players; // 1..3, nearer first (截胡)
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
    var best = 0;
    for (final e in c.resp.entries) {
      final p = _prio(c.from, e.key, e.value['type'] as String);
      if (p > best) best = p;
    }
    if (c.pending.any((p) => _maxPrio(c, p) > best)) return;
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
    lastAction = '${name(s)} 暗杠';
    host.log('${name(s)} 暗杠');
    afterKongFlag = true;
    _draw(s, kong: true);
  }

  void _finishBuGang(int s, int t) {
    hands[s][t]--;
    final m = melds[s].firstWhere((m) => m.kind == 'peng' && m.tile == t);
    m.kind = 'bgang';
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
