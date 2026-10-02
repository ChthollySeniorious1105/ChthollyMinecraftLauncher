import '../../src/engine.dart';
import 'tiles.dart';

part 'sichuan_bot.dart';
part 'sichuan_view.dart';

/// Pending responses to a discard (or to a 补杠 for 抢杠胡).
class _Claim {
  final int tile;
  final int from;
  final bool qiang; // 抢杠 window (only hu allowed)
  final Map<int, Set<String>> opts; // seat -> {'hu','peng','gang'}
  final Map<int, String> resp = {};
  _Claim(this.tile, this.from, this.qiang, this.opts);
  List<int> get pending => [for (final s in opts.keys) if (!resp.containsKey(s)) s]..sort();
}

class _Discard {
  final int tile;
  bool taken = false;
  bool afterKong;
  final bool tsumogiri; // 摸切: discarded the tile just drawn
  _Discard(this.tile, this.afterKong, {this.tsumogiri = false});
}

/// 四川麻将 · 血战到底
class SichuanGame extends GameEngine {
  SichuanGame(super.setup);

  // options
  late final int totalHands = setup.opt<int>('hands', 8);
  late final bool swapOn = setup.opt<bool>('swap', true);
  late final int cap = setup.opt<int>('cap', 4);
  late final bool zimoFan = setup.opt<String>('zimo', 'di') == 'fan';

  // match state
  late List<int> scores = List.filled(players, 0);
  int handNo = 0; // 1-based once started
  int dealer = 0;
  bool over = false;
  List<Map<String, dynamic>> history = [];

  // hand state
  String phase = 'swap'; // swap, que, act, claim, settle, over (pause = claim-cover delay)

  /// Phase to show/resume while [phase] is 'pause' (claim-cover delay).
  String pausedPhase = '';
  List<List<int>> hands = []; // counts[27]
  List<List<Meld>> melds = [];
  List<List<_Discard>> discards = [];
  List<int> que = [];
  List<int> wonOrder = []; // 0 = still playing
  List<int> winTile = [];
  List<int> drawn = []; // last drawn tile per seat (-1 none)
  List<int> wall = [];
  int turn = 0;
  bool canZimo = false;
  bool afterKong = false; // turn player just drew a kong replacement
  bool anyCall = false;
  List<bool> firstTurn = [];
  _Claim? claim;
  int? pendingBuGang; // tile of a 补杠 waiting for 抢杠 responses
  int lastDiscardSeat = -1;

  // swap / que
  List<List<int>?> swapPick = [];
  List<List<int>> swapGot = [];
  int swapDir = 1; // 1 下家, 2 对家, 3 上家
  List<int?> quePick = [];

  // settlement bookkeeping
  List<int> handDelta = [];
  List<Map<String, dynamic>> events = [];
  List<(int owner, int payer, int amount)> kongMoney = [];
  Map<String, dynamic>? settle;
  Set<int> ready = {};
  int nextDealer = -1;
  int winCount = 0;
  String lastAction = '';

  /// Latest public table event (discard / call / win) for client animations;
  /// [eventSeq] increments on every event so clients can replay them.
  Map<String, dynamic>? lastEvent;
  int eventSeq = 0;
  void _event(String t, int seat, [int tile = -1]) {
    lastEvent = {'t': t, 'seat': seat, if (tile >= 0) 'tile': tileCode(tile)};
    eventSeq++;
  }

  int get _capPts => 1 << cap;

  // ------------------------------------------------------------------ flow

  @override
  void start() {
    dealer = rng.nextInt(players);
    _startHand();
  }

  void _startHand() {
    handNo++;
    final tiles = <int>[for (var t = 0; t < 27; t++) for (var k = 0; k < 4; k++) t]..shuffle(rng);
    wall = tiles;
    hands = List.generate(players, (_) => List.filled(27, 0));
    melds = List.generate(players, (_) => <Meld>[]);
    discards = List.generate(players, (_) => <_Discard>[]);
    que = List.filled(players, -1);
    wonOrder = List.filled(players, 0);
    winTile = List.filled(players, -1);
    drawn = List.filled(players, -1);
    firstTurn = List.filled(players, true);
    handDelta = List.filled(players, 0);
    events = [];
    kongMoney = [];
    settle = null;
    claim = null;
    pendingBuGang = null;
    anyCall = false;
    afterKong = false;
    nextDealer = -1;
    winCount = 0;
    lastDiscardSeat = -1;
    for (var i = 0; i < 13; i++) {
      for (var s = 0; s < players; s++) {
        hands[s][wall.removeLast()]++;
      }
    }
    final extra = wall.removeLast();
    hands[dealer][extra]++;
    drawn[dealer] = extra;
    turn = dealer;
    swapPick = List.filled(players, null);
    swapGot = List.generate(players, (_) => <int>[]);
    quePick = List.filled(players, null);
    host.log('第 $handNo/$totalHands 局开始，${name(dealer)} 坐庄');
    if (swapOn) {
      phase = 'swap';
      swapDir = const [1, 2, 3][rng.nextInt(3)];
      lastAction = '请选择三张同花色的牌进行交换';
    } else {
      _enterQue();
    }
  }

  void _enterQue() {
    phase = 'que';
    lastAction = '请选择定缺花色';
  }

  static const _dirNames = {1: '换给下家', 2: '换给对家', 3: '换给上家'};

  void _doSwap() {
    for (var s = 0; s < players; s++) {
      for (final t in swapPick[s]!) {
        hands[s][t]--;
      }
    }
    for (var s = 0; s < players; s++) {
      final to = (s + swapDir) % players;
      for (final t in swapPick[s]!) {
        hands[to][t]++;
      }
      swapGot[to] = List.of(swapPick[s]!);
    }
    // dealer's "drawn" tile may have been swapped away
    if (hands[dealer][drawn[dealer]] == 0) drawn[dealer] = -1;
    host.log('换三张：${_dirNames[swapDir]}');
    _enterQue();
  }

  void _startPlay() {
    for (var s = 0; s < players; s++) {
      que[s] = quePick[s]!;
    }
    host.log('定缺：${[for (var s = 0; s < players; s++) '${name(s)}缺${suitNames[que[s]]}'].join('，')}');
    phase = 'act';
    turn = dealer;
    canZimo = true;
    afterKong = false;
    lastAction = '${name(dealer)} 庄家出牌';
  }

  bool _active(int s) => wonOrder[s] == 0;
  int get _activeCount => [for (var s = 0; s < players; s++) if (_active(s)) s].length;

  int _nextActive(int from) {
    for (var i = 1; i <= players; i++) {
      final s = (from + i) % players;
      if (_active(s)) return s;
    }
    return from;
  }

  bool _hasQue(int s) {
    final q = que[s];
    if (q < 0) return false;
    for (var r = 0; r < 9; r++) {
      if (hands[s][q * 9 + r] > 0) return true;
    }
    return false;
  }

  /// Draw for [s]. Returns false if wall is empty (hand ends).
  bool _draw(int s, {bool kong = false}) {
    if (wall.isEmpty) {
      _endHand();
      return false;
    }
    final t = wall.removeLast();
    hands[s][t]++;
    drawn[s] = t;
    turn = s;
    phase = 'act';
    canZimo = true;
    afterKong = kong;
    return true;
  }

  // ------------------------------------------------------------------ legality helpers

  bool canHuWith(int s, int t) {
    if (suitOf(t) == que[s]) return false;
    hands[s][t]++;
    final ok = isWinningCounts(hands[s], melds[s].length, que: que[s]);
    hands[s][t]--;
    return ok;
  }

  bool get canSelfHu => phase == 'act' && canZimo && isWinningCounts(hands[turn], melds[turn].length, que: que[turn]);

  /// Tiles the turn player may kong now: (tile, isBuGang).
  List<(int, bool)> selfKongs() {
    if (phase != 'act' || wall.isEmpty) return const [];
    final s = turn;
    final out = <(int, bool)>[];
    for (var t = 0; t < 27; t++) {
      if (suitOf(t) == que[s]) continue;
      if (hands[s][t] == 4) out.add((t, false));
      if (hands[s][t] >= 1 && melds[s].any((m) => m.kind == 'peng' && m.tile == t)) out.add((t, true));
    }
    return out;
  }

  /// Tiles the turn player may discard.
  List<int> legalDiscards() {
    final s = turn;
    final q = _hasQue(s);
    return [
      for (var t = 0; t < 27; t++)
        if (hands[s][t] > 0 && (!q || suitOf(t) == que[s])) t
    ];
  }

  // ------------------------------------------------------------------ actions

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
      case 'swap':
        return [for (var s = 0; s < players; s++) if (swapPick[s] == null) s];
      case 'que':
        return [for (var s = 0; s < players; s++) if (quePick[s] == null) s];
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
      case 'swap':
        if (type != 'swap') throw GameError('请先换三张');
        if (swapPick[seat] != null) throw GameError('你已经选好了');
        final ts = [for (final c in (a['tiles'] is List ? a['tiles'] as List : const [])) tileFromCode(c)];
        if (ts.length != 3 || ts.any((t) => t < 0)) throw GameError('请选择三张牌');
        if (ts.map(suitOf).toSet().length != 1) throw GameError('三张牌必须是同一花色');
        final c = countsOf(ts);
        for (var t = 0; t < 27; t++) {
          if (c[t] > hands[seat][t]) throw GameError('你没有这些牌');
        }
        swapPick[seat] = ts;
        if (swapPick.every((p) => p != null)) _doSwap();
        return;
      case 'que':
        if (type != 'que') throw GameError('请先定缺');
        if (quePick[seat] != null) throw GameError('你已经定缺了');
        final su = asInt(a['suit']);
        if (su < 0 || su > 2) throw GameError('无效花色');
        quePick[seat] = su;
        if (quePick.every((p) => p != null)) _startPlay();
        return;
      case 'act':
        if (seat != turn) throw GameError('还没轮到你');
        _handleAct(seat, type, a);
        return;
      case 'claim':
        _handleClaim(seat, type);
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
      if (!canSelfHu) throw GameError('现在不能胡');
      _win(s, -1, drawn[s] >= 0 && hands[s][drawn[s]] > 0 ? drawn[s] : _anyTile(s));
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
      if (t < 0 || hands[s][t] == 0) throw GameError('你没有这张牌');
      if (_hasQue(s) && suitOf(t) != que[s]) throw GameError('必须先打完缺门（${suitNames[que[s]]}）');
      _discard(s, t);
      return;
    }
    throw GameError('请出牌');
  }

  int _anyTile(int s) {
    for (var t = 26; t >= 0; t--) {
      if (hands[s][t] > 0) return t;
    }
    return 0;
  }

  void _discard(int s, int t) {
    hands[s][t]--;
    final giri = drawn[s] == t;
    drawn[s] = -1;
    final d = _Discard(t, afterKong, tsumogiri: giri);
    discards[s].add(d);
    firstTurn[s] = false;
    canZimo = false;
    afterKong = false;
    lastDiscardSeat = s;
    lastAction = '${name(s)} 打出 ${tileName(t)}';
    _event('discard', s, t);
    final opts = <int, Set<String>>{};
    for (var o = 0; o < players; o++) {
      if (o == s || !_active(o)) continue;
      final set = <String>{};
      if (canHuWith(o, t)) set.add('hu');
      if (wall.isNotEmpty && suitOf(t) != que[o]) {
        if (hands[o][t] >= 2) set.add('peng');
        if (hands[o][t] >= 3) set.add('gang');
      }
      if (set.isNotEmpty) opts[o] = set;
    }
    if (opts.isEmpty) {
      _coverPause(() => _afterNoClaim(s));
    } else {
      claim = _Claim(t, s, false, opts);
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

  void _afterNoClaim(int from) {
    claim = null;
    if (wall.isEmpty) {
      _endHand();
      return;
    }
    _draw(_nextActive(from));
  }

  void _handleClaim(int s, String type) {
    final c = claim!;
    final o = c.opts[s];
    if (o == null) throw GameError('你没有可执行的操作');
    if (c.resp.containsKey(s)) throw GameError('你已经选择了');
    if (type != 'pass' && !o.contains(type)) throw GameError('不能执行该操作');
    c.resp[s] = type;
    // early resolution: nobody pending who could hu
    final pend = c.pending;
    final huDeclared = c.resp.values.contains('hu');
    if (pend.isNotEmpty) {
      final pendCanHu = pend.any((p) => c.opts[p]!.contains('hu'));
      if (pendCanHu) return;
      if (!huDeclared) return; // someone may still peng/gang
    }
    _resolveClaim();
  }

  void _resolveClaim() {
    final c = claim!;
    claim = null;
    final hus = [
      for (var i = 1; i < players; i++)
        if (c.resp[(c.from + i) % players] == 'hu') (c.from + i) % players
    ];
    if (hus.isNotEmpty) {
      if (c.qiang) {
        // 抢杠: tile leaves the konger's hand, the peng stays a peng
        hands[c.from][c.tile]--;
        pendingBuGang = null;
      } else {
        discards[c.from].last.taken = true;
      }
      final multi = hus.length > 1;
      if (multi) host.log('一炮多响！');
      for (final h in hus) {
        if (!_active(h)) continue;
        _win(h, c.from, c.tile, qiang: c.qiang, multi: multi, continueFlow: false);
      }
      if (phase == 'settle' || phase == 'over') return;
      if (_activeCount <= 1) {
        _endHand();
        return;
      }
      if (wall.isEmpty) {
        _endHand();
        return;
      }
      _draw(_nextActive(hus.last));
      return;
    }
    if (c.qiang) {
      _finishBuGang(c.from, c.tile);
      return;
    }
    for (final e in c.resp.entries) {
      if (e.value == 'gang' || e.value == 'peng') {
        final s = e.key;
        discards[c.from].last.taken = true;
        anyCall = true;
        if (e.value == 'gang') {
          hands[s][c.tile] -= 3;
          melds[s].add(Meld('mgang', c.tile, c.from));
          _payKong(s, [(c.from, 2)]);
          host.log('${name(s)} 杠 ${tileName(c.tile)}（刮风下雨）');
          lastAction = '${name(s)} 明杠 ${tileName(c.tile)}';
          _event('gang', s, c.tile);
          _draw(s, kong: true);
        } else {
          hands[s][c.tile] -= 2;
          melds[s].add(Meld('peng', c.tile, c.from));
          turn = s;
          phase = 'act';
          canZimo = false;
          afterKong = false;
          drawn[s] = -1;
          lastAction = '${name(s)} 碰 ${tileName(c.tile)}';
          _event('peng', s, c.tile);
        }
        return;
      }
    }
    _afterNoClaim(c.from);
  }

  void _selfKong(int s, int t, bool bu) {
    anyCall = true;
    if (bu) {
      _event('bugang', s, t);
    } else {
      _event('angang', s);
    }
    if (bu) {
      // 抢杠胡 window
      final opts = <int, Set<String>>{};
      for (var o = 0; o < players; o++) {
        if (o != s && _active(o) && canHuWith(o, t)) opts[o] = {'hu'};
      }
      if (opts.isNotEmpty) {
        pendingBuGang = t;
        claim = _Claim(t, s, true, opts);
        phase = 'claim';
        lastAction = '${name(s)} 补杠 ${tileName(t)}';
        return;
      }
      _finishBuGang(s, t);
      return;
    }
    hands[s][t] -= 4;
    melds[s].add(Meld('agang', t, -1));
    _payKong(s, [for (var o = 0; o < players; o++) if (o != s && _active(o)) (o, 2)]);
    host.log('${name(s)} 暗杠（下雨）');
    lastAction = '${name(s)} 暗杠';
    _draw(s, kong: true);
  }

  void _finishBuGang(int s, int t) {
    pendingBuGang = null;
    hands[s][t]--;
    melds[s].firstWhere((m) => m.kind == 'peng' && m.tile == t).kind = 'bgang';
    _payKong(s, [for (var o = 0; o < players; o++) if (o != s && _active(o)) (o, 1)]);
    host.log('${name(s)} 补杠 ${tileName(t)}（刮风）');
    lastAction = '${name(s)} 补杠 ${tileName(t)}';
    _draw(s, kong: true);
  }

  void _payKong(int owner, List<(int, int)> payers) {
    var total = 0;
    for (final (p, amt) in payers) {
      handDelta[p] -= amt;
      scores[p] -= amt;
      kongMoney.add((owner, p, amt));
      total += amt;
    }
    handDelta[owner] += total;
    scores[owner] += total;
    events.add({
      'kind': 'gang',
      'seat': owner,
      'text': '${name(owner)} 杠牌 +$total',
      'pay': {for (final (p, amt) in payers) '$p': amt},
    });
  }

  void _win(int s, int from, int tile,
      {bool qiang = false, bool multi = false, bool continueFlow = true}) {
    final zimo = from < 0;
    final c = List.of(hands[s]);
    if (!zimo) c[tile]++;
    final pat = evaluateHand(c, melds[s], que: que[s]);
    if (pat == null) throw GameError('不能胡');
    final items = <(String, int)>[...pat.items];
    var fan = pat.fan;
    var special = '';
    if (zimo && firstTurn[s] && !anyCall && s == dealer) special = '天胡';
    if (zimo && firstTurn[s] && !anyCall && s != dealer && discards[s].isEmpty) special = '地胡';
    if (zimo && afterKong) items.add(('杠上开花', 1));
    if (!zimo && !qiang && discards[from].isNotEmpty && discards[from].last.afterKong) items.add(('杠上炮', 1));
    if (qiang) items.add(('抢杠胡', 1));
    if (zimo && wall.isEmpty) items.add(('海底捞月', 1));
    if (zimo && zimoFan) items.add(('自摸加番', 1));
    fan = items.fold(0, (a, e) => a + e.$2);
    if (special.isNotEmpty) {
      items.insert(0, (special, cap));
      fan = cap;
    }
    final capped = fan > cap ? cap : fan;
    var pts = 1 << capped;
    if (zimo && !zimoFan) pts += 1;
    final payers = zimo ? [for (var o = 0; o < players; o++) if (o != s && _active(o)) o] : [from];
    for (final p in payers) {
      handDelta[p] -= pts;
      scores[p] -= pts;
    }
    handDelta[s] += pts * payers.length;
    scores[s] += pts * payers.length;
    winCount++;
    wonOrder[s] = winCount;
    winTile[s] = tile;
    if (zimo) hands[s][tile]--; // winning tile is shown separately
    drawn[s] = -1;
    if (nextDealer < 0) nextDealer = (multi && !zimo) ? from : s;
    final fanNames = [for (final (n, f) in items) f > 0 && n != '平胡' ? '$n$f番' : n].join(' ');
    events.add({
      'kind': 'hu',
      'seat': s,
      'from': from,
      'tile': tileCode(tile),
      'zimo': zimo,
      'order': winCount,
      'fan': fan,
      'capped': fan > cap,
      'items': [for (final (n, f) in items) [n, f]],
      'points': pts,
      'total': pts * payers.length,
      'pay': {for (final p in payers) '$p': pts},
    });
    host.log(zimo
        ? '${name(s)} 自摸 ${tileName(tile)}！$fanNames，每家 $pts 分'
        : '${name(s)} 胡 ${name(from)} 的 ${tileName(tile)}！$fanNames，$pts 分');
    lastAction = zimo ? '${name(s)} 自摸' : '${name(s)} 胡牌（${name(from)} 点炮）';
    _event(zimo ? 'zimo' : 'hu', s, tile);
    if (!continueFlow) {
      if (winCount >= players - 1) _endHand();
      return;
    }
    if (winCount >= players - 1 || wall.isEmpty) {
      _endHand();
      return;
    }
    _draw(_nextActive(s));
  }

  // ------------------------------------------------------------------ hand end

  void _endHand() {
    if (phase == 'settle' || phase == 'over') return;
    claim = null;
    final exhausted = winCount < players - 1;
    final chajiao = <Map<String, dynamic>>[];
    if (exhausted) {
      final act = [for (var s = 0; s < players; s++) if (_active(s)) s];
      final hz = {for (final s in act) if (_hasQue(s)) s};
      final tenFan = <int, int>{};
      for (final s in act) {
        if (hz.contains(s)) continue;
        final f = _tenpaiFan(s);
        if (f >= 0) tenFan[s] = f;
      }
      void pay(int from, int to, int amt, String why) {
        handDelta[from] -= amt;
        scores[from] -= amt;
        handDelta[to] += amt;
        scores[to] += amt;
        chajiao.add({'from': from, 'to': to, 'amount': amt, 'why': why});
      }

      // 查花猪
      for (final h in hz) {
        for (final o in act) {
          if (!hz.contains(o)) pay(h, o, _capPts, '花猪');
        }
      }
      // 查大叫
      for (final s in act) {
        if (hz.contains(s) || tenFan.containsKey(s)) continue;
        for (final e in tenFan.entries) {
          pay(s, e.key, 1 << (e.value > cap ? cap : e.value), '查大叫');
        }
      }
      // 退税: noten players refund kong money
      for (final s in act) {
        if (tenFan.containsKey(s)) continue;
        for (final (owner, payer, amt) in kongMoney) {
          if (owner == s) pay(s, payer, amt, '退税');
        }
      }
      host.log(winCount == 0 ? '流局' : '牌墙摸完，本局结束');
    }
    settle = {
      'hand': handNo,
      'exhausted': exhausted,
      'events': events,
      'chajiao': chajiao,
      'delta': List.of(handDelta),
      'tenpai': [for (var s = 0; s < players; s++) _active(s) && !_hasQue(s) && _tenpaiFan(s) >= 0],
      'huazhu': [for (var s = 0; s < players; s++) _active(s) && _hasQue(s)],
    };
    history.add({'hand': handNo, 'delta': List.of(handDelta)});
    ready = {};
    if (handNo >= totalHands) {
      phase = 'over';
      over = true;
      final order = List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));
      host.log('全部 $totalHands 局结束！${[for (var i = 0; i < order.length; i++) '第${i + 1} ${name(order[i])} ${scores[order[i]]}'].join('，')}');
    } else {
      phase = 'settle';
    }
  }

  int _tenpaiFan(int s) {
    final c = hands[s];
    final w = waitingTiles(c, melds[s], que: que[s]);
    var best = -1;
    for (final t in w) {
      var own = c[t];
      for (final m in melds[s]) {
        if (m.tile == t) own += m.size;
      }
      if (own >= 4) continue;
      c[t]++;
      final r = evaluateHand(c, melds[s], que: que[s]);
      c[t]--;
      if (r != null && r.fan > best) best = r.fan;
    }
    return best;
  }

  void _nextHand() {
    if (nextDealer >= 0) dealer = nextDealer;
    _startHand();
  }
}
