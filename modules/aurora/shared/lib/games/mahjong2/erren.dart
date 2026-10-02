import '../../src/engine.dart';
import 'ep_fans.dart';
import 'tiles.dart';

part 'ep_bot.dart';

/// Tile kinds used by 二人麻将: 1-9万 + 东南西北白发中.
const List<int> epKinds = [0, 1, 2, 3, 4, 5, 6, 7, 8, 27, 28, 29, 30, 31, 32, 33];

class _Claim {
  final int tile;
  final int from;
  final bool rob;
  final Map<int, Set<String>> opts;
  final Map<int, List<int>> chis;
  final Map<int, Map<String, dynamic>> resp = {};
  _Claim(this.tile, this.from, this.rob, this.opts, this.chis);
  List<int> get pending => [for (final s in opts.keys) if (!resp.containsKey(s)) s]..sort();
}

class _Discard {
  final int tile;
  bool taken = false;
  final bool tsumogiri;
  _Discard(this.tile, {this.tsumogiri = false});
}

/// 二人麻将（国标二人麻将风格）
class ErrenGame extends GameEngine {
  ErrenGame(super.setup);

  late final int totalHands = setup.opt<int>('hands', 8);
  late final bool withFlowers = setup.opt<bool>('flowers', true);
  late final int minFan = setup.opt<int>('minFan', 8);

  late List<int> scores = List.filled(players, 0);
  int handNo = 0;
  int dealer = 0;
  int roundWind = 0;
  bool over = false;
  List<Map<String, dynamic>> history = [];
  int resigned = -1;

  String phase = 'act'; // act, claim, settle, over (pause)
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
  Map<String, dynamic>? lastEvent;
  int eventSeq = 0;
  List<int> handDelta = [];
  Map<String, dynamic>? settle;
  Set<int> ready = {};

  void _event(String t, int seat, [int tile = -1]) {
    lastEvent = {'t': t, 'seat': seat, if (tile >= 0) 'tile': tileCode(tile)};
    eventSeq++;
  }

  int seatWind(int s) => (s - dealer + players) % players;

  @override
  void start() {
    dealer = rng.nextInt(players);
    _startHand();
  }

  void _startHand() {
    handNo++;
    roundWind = handNo <= (totalHands + 1) ~/ 2 ? 0 : 1;
    wall = <int>[
      for (final t in epKinds)
        for (var k = 0; k < 4; k++) t,
      if (withFlowers)
        for (var f = 0; f < 8; f++) kFlowerBase + f,
    ]..shuffle(rng);
    hands = List.generate(players, (_) => List.filled(kKinds, 0));
    flowers = List.generate(players, (_) => <int>[]);
    melds = List.generate(players, (_) => <Meld>[]);
    discards = List.generate(players, (_) => <_Discard>[]);
    drawn = List.filled(players, -1);
    handDelta = List.filled(players, 0);
    settle = null;
    claim = null;
    lastDiscardSeat = -1;
    afterKong = false;
    afterKongFlag = false;
    for (var i = 0; i < 13; i++) {
      for (var s = 0; s < players; s++) {
        _give(s, wall.removeLast());
      }
    }
    for (var i = 0; i < players; i++) {
      _replaceFlowers((dealer + i) % players);
    }
    host.log('第 $handNo/$totalHands 局开始，${name(dealer)} 坐庄（${windNames[roundWind]}圈）');
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
        kong = true;
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

  EpResult? evalWin(int s, int tile, {required bool tsumo, bool rob = false}) {
    final c = List.of(hands[s]);
    if (!tsumo) c[tile]++;
    if (!isWinShape2p(c, melds[s].length)) return null;
    final before = List.of(c);
    before[tile]--;
    final wc = waits2p(before, melds[s].length, epKinds).length;
    final onTable = _visibleCopies(tile);
    return evaluate2p(
        c,
        melds[s],
        EpCtx(tile,
            selfDrawn: tsumo,
            seatWind: seatWind(s),
            roundWind: roundWind,
            lastTile: wall.isEmpty && !rob,
            kongDraw: tsumo && afterKong,
            robKong: rob,
            lastCopy: !rob && (tsumo ? onTable : onTable - 1) >= 3,
            flowers: flowers[s].length,
            waitCount: wc));
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
    for (final t in epKinds) {
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
  Map<String, dynamic> view(int seat) => buildView(seat);
  @override
  Map<String, dynamic>? bot(int seat) => botAction(seat);
  @override
  int get botDelayMs => phase == 'claim' ? 500 : 700;

  @override
  List<int>? get placings {
    if (!over) return null;
    if (resigned >= 0) return [for (var s = 0; s < players; s++) s == resigned ? 2 : 1];
    return rankByScore(scores);
  }

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) return;
    resigned = seat;
    over = true;
    phase = 'over';
    claim = null;
    settle ??= {'hand': handNo, 'kind': 'resign', 'delta': List.of(handDelta), 'dealer': dealer};
    settle!['resigned'] = seat;
    lastAction = '${name(seat)} 认输';
    host.log('${name(seat)} 认输，${name((seat + 1) % players)} 获胜');
  }

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
      if (!canSelfWin) throw GameError('不能和牌（需满 $minFan 番，花牌不计）');
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
      if (wall.isNotEmpty) {
        if (hands[o][t] >= 2) set.add('peng');
        if (hands[o][t] >= 3) set.add('gang');
        final c = chiOptions(o, t);
        if (c.isNotEmpty) {
          set.add('chi');
          chis[o] = c;
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
    if (c.pending.isNotEmpty) return;
    _resolveClaim();
  }

  void _resolveClaim() {
    final c = claim!;
    claim = null;
    int prio(String t) => switch (t) { 'hu' => 30, 'gang' || 'peng' => 20, 'chi' => 10, _ => 0 };
    var bestSeat = -1, best = 0;
    for (final e in c.resp.entries) {
      final p = prio(e.value['type'] as String);
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
    if (bu) {
      _event('bugang', s, t);
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
    _event('angang', s);
    hands[s][t] -= 4;
    melds[s].add(Meld('agang', t));
    lastAction = '${name(s)} 暗杠';
    host.log(lastAction);
    afterKongFlag = true;
    _draw(s, kong: true);
  }

  void _finishBuGang(int s, int t) {
    hands[s][t]--;
    melds[s].firstWhere((m) => m.kind == 'peng' && m.tile == t).kind = 'bgang';
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

  // ------------------------------------------------------------------ settlement

  void _win(int s, int from, int tile, {bool rob = false}) {
    final tsumo = from < 0;
    final w = evalWin(s, tile, tsumo: tsumo, rob: rob);
    if (w == null) throw GameError('不能和牌');
    if (rob) {
      hands[from][tile]--;
    } else if (!tsumo) {
      discards[from].last.taken = true;
    }
    if (tsumo) hands[s][tile]--;
    drawn[s] = -1;
    final loser = (s + 1) % players;
    final amt = (tsumo ? 16 : 8) + w.total;
    _pay(loser, s, amt);
    host.log(tsumo
        ? '${name(s)} 自摸 ${tileName(tile)}！${w.label}，共 ${w.total} 番'
        : '${name(s)} 和 ${name(from)} 的 ${tileName(tile)}${rob ? '（抢杠）' : ''}！${w.label}，共 ${w.total} 番');
    lastAction = tsumo ? '${name(s)} 自摸' : '${name(s)} 和牌（${name(from)} 点和）';
    _event(tsumo ? 'zimo' : 'hu', s, tile);
    _endHand({
      'kind': 'win',
      'winner': s,
      'from': from,
      'tile': tileCode(tile),
      'tsumo': tsumo,
      'rob': rob,
      'fan': w.total,
      'items': w.toJson(),
      'points': amt,
    });
  }

  void _drawnGame() {
    host.log('荒庄（流局）');
    lastAction = '荒庄';
    _endHand({'kind': 'draw'});
  }

  void _endHand(Map<String, dynamic> result) {
    claim = null;
    result['hand'] = handNo;
    result['delta'] = List.of(handDelta);
    result['dealer'] = dealer;
    settle = result;
    history.add({'hand': handNo, 'delta': List.of(handDelta)});
    ready = {};
    if (handNo >= totalHands) {
      phase = 'over';
      over = true;
      final order = ranking();
      host.log('全部 $totalHands 局结束！${[
        for (var i = 0; i < order.length; i++) '第${i + 1} ${name(order[i])} ${scores[order[i]]}'
      ].join('，')}');
    } else {
      phase = 'settle';
    }
  }

  List<int> ranking() {
    final order = List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
    if (resigned >= 0) {
      order
        ..remove(resigned)
        ..add(resigned);
    }
    return order;
  }

  void _nextHand() {
    dealer = (dealer + 1) % players;
    _startHand();
  }

  // ------------------------------------------------------------------ view

  Map<String, dynamic> buildView(int me) {
    final reveal = phase == 'settle' || phase == 'over';
    final seats = <Map<String, dynamic>>[];
    for (var s = 0; s < players; s++) {
      final hasDrawn = phase == 'act' && turn == s && drawn[s] >= 0 && hands[s][drawn[s]] > 0;
      seats.add({
        'count': countTotal(hands[s]),
        'drawn': hasDrawn,
        'hand': s == me || reveal ? codesOfCounts(hands[s]) : null,
        'melds': [for (final m in melds[s]) m.toJson(hide: m.kind == 'agang' && s != me && !reveal)],
        'flowers': [for (final f in flowers[s]) tileCode(f)],
        'discards': [
          for (final d in discards[s]) {'t': tileCode(d.tile), 'taken': d.taken, 'tg': d.tsumogiri}
        ],
        'wind': seatWind(s),
        'score': scores[s],
        'delta': handDelta[s],
      });
    }
    final v = <String, dynamic>{
      'rule': 'erren',
      'phase': (phase == 'pause' ? 'claim' : phase),
      'hand': handNo,
      'hands': totalHands,
      'dealer': dealer,
      'roundWind': roundWind,
      'turn': turn,
      'wall': wall.length,
      'minFan': minFan,
      'seats': seats,
      'last': lastAction,
      'lastDiscard': lastDiscardSeat,
      'event': lastEvent == null ? null : {...lastEvent!, 'seq': eventSeq},
      'waiting': phase == 'claim' ? [for (final s in waitingFor) if (s == me) s] : waitingFor,
      'over': over,
      'settle': settle,
      'history': history,
    };
    if (claim != null) {
      v['claimTile'] = tileCode(claim!.tile);
      v['claimFrom'] = claim!.from;
      v['claimRob'] = claim!.rob;
    } else if (phase == 'pause' && lastDiscardSeat >= 0 && discards[lastDiscardSeat].isNotEmpty) {
      v['claimTile'] = tileCode(discards[lastDiscardSeat].last.tile);
      v['claimFrom'] = lastDiscardSeat;
      v['claimRob'] = false;
    }
    if (over) v['ranking'] = ranking();
    if (me >= 0 && me < players) {
      final my = <String, dynamic>{
        'drawn': phase == 'act' && turn == me && drawn[me] >= 0 && hands[me][drawn[me]] > 0 ? tileCode(drawn[me]) : null,
      };
      if (phase == 'act' && turn == me) {
        my['canHu'] = canSelfWin;
        my['kongs'] = [for (final (t, _) in selfKongs()) tileCode(t)];
      }
      if (phase == 'claim' && claim!.opts.containsKey(me) && !claim!.resp.containsKey(me)) {
        my['claim'] = claim!.opts[me]!.toList();
        my['chis'] = [
          for (final lo in claim!.chis[me] ?? const <int>[]) [for (var k = lo; k < lo + 3; k++) tileCode(k)]
        ];
      }
      final n = countTotal(hands[me]);
      if (n % 3 == 1 && (phase == 'act' || phase == 'claim' || phase == 'pause')) {
        my['waits'] = [for (final t in waits2p(hands[me], melds[me].length, epKinds)) tileCode(t)];
      }
      v['me'] = my;
    }
    return v;
  }
}
