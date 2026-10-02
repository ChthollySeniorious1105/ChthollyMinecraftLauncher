import '../../src/engine.dart';
import 'cs_rules.dart';
import 'tiles.dart';

part 'cs_bot.dart';
part 'cs_view.dart';

/// Pending responses to a discard, a 补杠 (抢杠胡) or a 开杠 flip (杠上炮).
class _Claim {
  final List<int> tiles; // discard / rob: one tile; flip: the 1-2 flipped tiles
  final int from;
  final String kind; // 'discard', 'rob', 'flip'
  final Map<int, Set<String>> opts; // seat -> {'hu','peng','gang','chi'}
  final Map<int, List<int>> chis; // seat -> lowest tiles of possible chows
  final Map<int, (int, CsResult)> hu; // seat -> (winning tile, result)
  final Map<int, Map<String, dynamic>> resp = {};
  _Claim(this.tiles, this.from, this.kind, this.opts, {this.chis = const {}, this.hu = const {}});
  int get tile => tiles.first;
  List<int> get pending => [for (final s in opts.keys) if (!resp.containsKey(s)) s]..sort();
}

class _Discard {
  final int tile;
  bool taken = false;
  final bool tsumogiri; // 摸切
  final bool flip; // 开杠翻出的牌
  _Discard(this.tile, {this.tsumogiri = false, this.flip = false});
}

/// 长沙麻将
class ChangshaGame extends GameEngine {
  ChangshaGame(super.setup);

  late final int totalHands = setup.opt<int>('hands', 8);
  late final int birdN = setup.opt<int>('birds', 2);
  late final bool allowPao = setup.opt<String>('pao', 'dian') == 'dian';
  late final bool qishouOn = setup.opt<bool>('qishou', true);

  // match
  late List<int> scores = List.filled(players, 0);
  int handNo = 0;
  int dealer = 0;
  bool over = false;
  List<Map<String, dynamic>> history = [];

  // hand
  String phase = 'act'; // qishou, act, claim, settle, over (pause = claim-cover delay)
  String pausedPhase = '';
  List<List<int>> hands = [];
  List<List<Meld>> melds = [];
  List<List<_Discard>> discards = [];
  List<int> drawn = [];
  List<bool> locked = []; // 开杠后锁牌
  List<int> wall = [];
  int turn = 0;
  bool canZimo = false;
  bool anyCall = false;
  int discardCount = 0;
  _Claim? claim;
  String pendingKongMode = 'bu';
  int lastDiscardSeat = -1;
  String lastAction = '';
  Map<String, dynamic>? lastEvent;
  int eventSeq = 0;
  List<int> handDelta = [];
  List<Map<String, dynamic>> events = [];
  Map<String, dynamic>? settle;
  Set<int> ready = {};
  int nextDealer = -1;

  // 起手胡
  Map<int, List<(String, int)>> qishouOpts = {};
  Set<int> qishouDone = {};
  List<List<Map<String, dynamic>>> qishouShown = [];

  void _event(String t, int seat, [List<int> tiles = const []]) {
    lastEvent = {'t': t, 'seat': seat, if (tiles.isNotEmpty) 'tile': tileCode(tiles.first), if (tiles.length > 1) 'tiles': [for (final x in tiles) tileCode(x)]};
    eventSeq++;
  }

  int seatWind(int s) => (s - dealer + players) % players;

  // ------------------------------------------------------------------ flow

  @override
  void start() {
    dealer = rng.nextInt(players);
    _startHand();
  }

  void _startHand() {
    handNo++;
    wall = <int>[for (var t = 0; t < 27; t++) for (var k = 0; k < 4; k++) t]..shuffle(rng);
    hands = List.generate(players, (_) => List.filled(kKinds, 0));
    melds = List.generate(players, (_) => <Meld>[]);
    discards = List.generate(players, (_) => <_Discard>[]);
    drawn = List.filled(players, -1);
    locked = List.filled(players, false);
    handDelta = List.filled(players, 0);
    events = [];
    settle = null;
    claim = null;
    anyCall = false;
    discardCount = 0;
    lastDiscardSeat = -1;
    nextDealer = -1;
    qishouOpts = {};
    qishouDone = {};
    qishouShown = List.generate(players, (_) => <Map<String, dynamic>>[]);
    for (var i = 0; i < 13; i++) {
      for (var s = 0; s < players; s++) {
        hands[s][wall.removeLast()]++;
      }
    }
    final extra = wall.removeLast();
    hands[dealer][extra]++;
    drawn[dealer] = extra;
    turn = dealer;
    host.log('第 $handNo/$totalHands 局开始，${name(dealer)} 坐庄');
    if (qishouOn) {
      for (var s = 0; s < players; s++) {
        final q = csQishou(hands[s]);
        if (q.isNotEmpty) qishouOpts[s] = q;
      }
    }
    if (qishouOpts.isNotEmpty) {
      phase = 'qishou';
      lastAction = '起手胡：等待玩家选择是否亮牌';
    } else {
      _beginPlay();
    }
  }

  void _beginPlay() {
    phase = 'act';
    turn = dealer;
    canZimo = true;
    lastAction = '${name(dealer)} 庄家出牌';
  }

  void _qishou(int s, bool declare) {
    qishouDone.add(s);
    if (declare) {
      final list = qishouOpts[s]!;
      var n = 0;
      for (final (kind, k) in list) {
        n += k;
        qishouShown[s].add({'name': kind, 'count': k, 'tiles': [for (final t in csQishouShow(hands[s], kind)) tileCode(t)]});
      }
      final pay = <String, int>{};
      for (var o = 0; o < players; o++) {
        if (o == s) continue;
        final amt = 2 * n;
        _pay(o, s, amt);
        pay['$o'] = amt;
      }
      final label = [for (final (kind, k) in list) k > 1 ? '$kind×$k' : kind].join(' ');
      events.add({'kind': 'qishou', 'seat': s, 'text': label, 'pay': pay});
      host.log('${name(s)} 起手胡：$label，每家付 ${2 * n} 分');
      lastAction = '${name(s)} 起手胡 $label';
      _event('qishou', s);
    }
    if (qishouOpts.keys.every(qishouDone.contains)) _beginPlay();
  }

  bool _draw(int s, {bool back = false}) {
    turn = s;
    if (wall.isEmpty) {
      _drawnGame();
      return false;
    }
    final t = back ? wall.removeAt(0) : wall.removeLast();
    hands[s][t]++;
    drawn[s] = t;
    phase = 'act';
    canZimo = true;
    return true;
  }

  void _nextDraw(int from) {
    claim = null;
    _draw((from + 1) % players);
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

  // ------------------------------------------------------------------ evaluation

  CsResult? selfEval(int s) => csEvaluate(
      hands[s],
      melds[s],
      CsCtx(
        selfDrawn: true,
        haidi: wall.isEmpty,
        tian: s == dealer && discardCount == 0 && !anyCall,
      ));

  CsResult? ronEval(int o, int t, int from, {bool rob = false, bool gangPao = false}) {
    final c = List.of(hands[o]);
    c[t]++;
    return csEvaluate(
        c,
        melds[o],
        CsCtx(
          haidi: wall.isEmpty && !rob && !gangPao,
          rob: rob,
          gangPao: gangPao,
          di: !anyCall && discardCount == 1 && from == dealer && o != dealer && !rob && !gangPao,
        ));
  }

  bool get canSelfHu => phase == 'act' && canZimo && selfEval(turn) != null;

  /// (tile, isBuGang) kongs available to the turn player.
  List<(int, bool)> selfKongs() {
    if (phase != 'act' || wall.isEmpty || locked[turn]) return const [];
    final s = turn;
    final out = <(int, bool)>[];
    for (var t = 0; t < 27; t++) {
      if (hands[s][t] == 4) out.add((t, false));
      if (hands[s][t] >= 1 && melds[s].any((m) => m.kind == 'peng' && m.tile == t)) out.add((t, true));
    }
    return out;
  }

  /// 开杠 requires 听牌 after the kong (any 胡 shape, since 杠上开花 is a 大胡).
  bool kaiOk(int s, int t, int remove, {bool fromPeng = false}) {
    if (wall.isEmpty) return false;
    final h = List.of(hands[s]);
    h[t] -= remove;
    if (h[t] < 0) return false;
    final ms = [
      for (final m in melds[s])
        if (!(fromPeng && m.kind == 'peng' && m.tile == t)) m,
      Meld('agang', t),
    ];
    return csWaits(h, ms, anyShape: true).isNotEmpty;
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

  List<int> legalDiscards(int s) {
    if (locked[s] && drawn[s] >= 0 && hands[s][drawn[s]] > 0) return [drawn[s]];
    return [for (var t = 0; t < 27; t++) if (hands[s][t] > 0) t];
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
  List<int>? get placings => over ? rankByScore(scores) : null;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'qishou':
        return [for (final s in qishouOpts.keys) if (!qishouDone.contains(s)) s]..sort();
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
      case 'qishou':
        if (!qishouOpts.containsKey(seat) || qishouDone.contains(seat)) throw GameError('请等待其他玩家选择起手胡');
        if (type != 'qishou' && type != 'pass') throw GameError('请选择是否起手胡');
        _qishou(seat, type == 'qishou');
        return;
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
      final r = canZimo ? selfEval(s) : null;
      if (r == null) throw GameError('现在不能胡（小胡需要 2、5、8 作将）');
      final t = drawn[s] >= 0 && hands[s][drawn[s]] > 0 ? drawn[s] : _anyTile(s);
      _settleWin({s: (t, r)}, -1);
      return;
    }
    if (type == 'gang') {
      if (locked[s]) throw GameError('开杠后不能再杠');
      final t = tileFromCode(a['tile']);
      final k = selfKongs().where((e) => e.$1 == t).toList();
      if (k.isEmpty) throw GameError('不能杠这张牌');
      final bu = k.first.$2;
      final mode = asStr(a['mode'], 'bu') == 'kai' ? 'kai' : 'bu';
      if (mode == 'kai' && !kaiOk(s, t, bu ? 1 : 4, fromPeng: bu)) throw GameError('开杠需要杠后听牌');
      _selfKong(s, t, bu, mode);
      return;
    }
    if (type == 'discard') {
      final t = tileFromCode(a['tile']);
      if (t < 0 || t >= 27 || hands[s][t] == 0) throw GameError('你没有这张牌');
      if (!legalDiscards(s).contains(t)) throw GameError('开杠后只能打出摸到的牌');
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
    discards[s].add(_Discard(t, tsumogiri: giri));
    discardCount++;
    canZimo = false;
    lastDiscardSeat = s;
    lastAction = '${name(s)} 打出 ${tileName(t)}';
    _event('discard', s, [t]);
    final opts = <int, Set<String>>{};
    final chis = <int, List<int>>{};
    final hu = <int, (int, CsResult)>{};
    for (var o = 0; o < players; o++) {
      if (o == s) continue;
      final set = <String>{};
      if (allowPao) {
        final r = ronEval(o, t, s);
        if (r != null) {
          set.add('hu');
          hu[o] = (t, r);
        }
      }
      if (wall.isNotEmpty && !locked[o]) {
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
      claim = _Claim([t], s, 'discard', opts, chis: chis, hu: hu);
      phase = 'claim';
    }
  }

  int _prio(String type) => switch (type) { 'hu' => 30, 'gang' || 'peng' => 20, 'chi' => 10, _ => 0 };

  int _maxPrio(_Claim c, int s) {
    var best = 0;
    for (final o in c.opts[s]!) {
      final p = _prio(o);
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
    if (type == 'gang') {
      final kai = asStr(a['mode'], 'bu') == 'kai';
      if (kai && !kaiOk(s, c.tile, 3)) throw GameError('开杠需要杠后听牌');
      r['mode'] = kai ? 'kai' : 'bu';
    }
    c.resp[s] = r;
    final pend = c.pending;
    final huDeclared = c.resp.values.any((e) => e['type'] == 'hu');
    if (huDeclared) {
      // 一炮多响: wait for everyone else who could also 胡
      if (pend.any((p) => c.opts[p]!.contains('hu'))) return;
    } else {
      var best = 0;
      for (final e in c.resp.values) {
        final p = _prio(e['type'] as String);
        if (p > best) best = p;
      }
      if (pend.any((p) => _maxPrio(c, p) > best)) return;
    }
    _resolveClaim();
  }

  void _resolveClaim() {
    final c = claim!;
    claim = null;
    final hus = [
      for (var i = 1; i < players; i++)
        if (c.resp[(c.from + i) % players]?['type'] == 'hu') (c.from + i) % players
    ];
    if (hus.isNotEmpty) {
      final wins = {for (final h in hus) h: c.hu[h]!};
      if (c.kind == 'rob') {
        hands[c.from][c.tile]--;
      } else if (c.kind == 'discard') {
        discards[c.from].last.taken = true;
      } else {
        for (final h in hus) {
          final t = c.hu[h]!.$1;
          for (final d in discards[c.from].reversed) {
            if (d.flip && d.tile == t && !d.taken) {
              d.taken = true;
              break;
            }
          }
        }
      }
      if (hus.length > 1) host.log('一炮多响！');
      _settleWin(wins, c.from, rob: c.kind == 'rob');
      return;
    }
    if (c.kind == 'rob') {
      _finishBuGang(c.from, c.tile, pendingKongMode);
      return;
    }
    if (c.kind == 'flip') {
      _nextDraw(c.from);
      return;
    }
    var bestSeat = -1, best = 0;
    for (final e in c.resp.entries) {
      final p = _prio(e.value['type'] as String);
      if (p > best) {
        best = p;
        bestSeat = e.key;
      }
    }
    if (bestSeat < 0) {
      _nextDraw(c.from);
      return;
    }
    final r = c.resp[bestSeat]!;
    final type = r['type'] as String;
    final s = bestSeat;
    discards[c.from].last.taken = true;
    anyCall = true;
    if (type == 'gang') {
      hands[s][c.tile] -= 3;
      final m = Meld('mgang', c.tile, claimed: c.tile, from: c.from);
      melds[s].add(m);
      lastAction = '${name(s)} ${r['mode'] == 'kai' ? '开杠' : '补张'} ${tileName(c.tile)}';
      _afterKong(s, m, r['mode'] as String);
      return;
    }
    if (type == 'peng') {
      hands[s][c.tile] -= 2;
      melds[s].add(Meld('peng', c.tile, claimed: c.tile, from: c.from));
      lastAction = '${name(s)} 碰 ${tileName(c.tile)}';
      _event('peng', s, [c.tile]);
    } else {
      final lo = r['lo'] as int;
      for (var k = lo; k < lo + 3; k++) {
        if (k != c.tile) hands[s][k]--;
      }
      melds[s].add(Meld('chi', lo, claimed: c.tile, from: c.from));
      lastAction = '${name(s)} 吃 ${tileName(c.tile)}';
      _event('chi', s, [c.tile]);
    }
    turn = s;
    phase = 'act';
    canZimo = false;
    drawn[s] = -1;
  }

  void _selfKong(int s, int t, bool bu, String mode) {
    anyCall = true;
    if (bu) {
      if (allowPao) {
        final opts = <int, Set<String>>{};
        final hu = <int, (int, CsResult)>{};
        for (var o = 0; o < players; o++) {
          if (o == s) continue;
          final r = ronEval(o, t, s, rob: true);
          if (r != null) {
            opts[o] = {'hu'};
            hu[o] = (t, r);
          }
        }
        if (opts.isNotEmpty) {
          pendingKongMode = mode;
          claim = _Claim([t], s, 'rob', opts, hu: hu);
          phase = 'claim';
          lastAction = '${name(s)} 补杠 ${tileName(t)}';
          _event('bugang', s, [t]);
          return;
        }
      }
      _finishBuGang(s, t, mode);
      return;
    }
    hands[s][t] -= 4;
    final m = Meld('agang', t);
    melds[s].add(m);
    lastAction = '${name(s)} 暗杠${mode == 'kai' ? '（开杠）' : '（补张）'}';
    _afterKong(s, m, mode);
  }

  void _finishBuGang(int s, int t, String mode) {
    hands[s][t]--;
    final m = melds[s].firstWhere((m) => m.kind == 'peng' && m.tile == t);
    m.kind = 'bgang';
    lastAction = '${name(s)} ${mode == 'kai' ? '开杠' : '补张'} ${tileName(t)}';
    _afterKong(s, m, mode);
  }

  /// 补张: draw a replacement. 开杠: lock the hand and flip two tiles.
  void _afterKong(int s, Meld m, String mode) {
    drawn[s] = -1;
    if (mode != 'kai' || wall.isEmpty) {
      _event('gang', s, m.kind == 'agang' ? const [] : [m.tile]);
      host.log(lastAction);
      _draw(s, back: true);
      return;
    }
    m.open = true;
    locked[s] = true;
    final flip = <int>[];
    for (var i = 0; i < 2 && wall.isNotEmpty; i++) {
      flip.add(wall.removeAt(0));
    }
    _event('kaigang', s, flip);
    host.log('${name(s)} 开杠，翻出 ${flip.map(tileName).join('、')}');
    lastAction = '${name(s)} 开杠 翻出 ${flip.map(tileName).join(' ')}';
    // 杠上开花: take the best flipped tile that completes the hand
    (int, CsResult)? best;
    for (final t in flip) {
      hands[s][t]++;
      final r = csEvaluate(hands[s], melds[s], CsCtx(selfDrawn: true, kaiGang: true, haidi: wall.isEmpty));
      hands[s][t]--;
      if (r != null && (best == null || r.bigCount > best.$2.bigCount)) best = (t, r);
    }
    if (best != null) {
      final win = best.$1;
      var used = false;
      for (final t in flip) {
        if (t == win && !used) {
          used = true;
          continue;
        }
        discards[s].add(_Discard(t, flip: true));
      }
      hands[s][win]++;
      _settleWin({s: best}, -1);
      return;
    }
    for (final t in flip) {
      discards[s].add(_Discard(t, flip: true));
    }
    lastDiscardSeat = s;
    canZimo = false;
    final opts = <int, Set<String>>{};
    final hu = <int, (int, CsResult)>{};
    if (allowPao) {
      for (var o = 0; o < players; o++) {
        if (o == s) continue;
        (int, CsResult)? b;
        for (final t in flip) {
          final r = ronEval(o, t, s, gangPao: true);
          if (r != null && (b == null || r.bigCount > b.$2.bigCount)) b = (t, r);
        }
        if (b != null) {
          opts[o] = {'hu'};
          hu[o] = b;
        }
      }
    }
    if (opts.isEmpty) {
      _coverPause(() => _nextDraw(s));
    } else {
      claim = _Claim(flip, s, 'flip', opts, hu: hu);
      phase = 'claim';
    }
  }

  void _pay(int from, int to, int amt) {
    scores[from] -= amt;
    scores[to] += amt;
    handDelta[from] -= amt;
    handDelta[to] += amt;
  }

  // ------------------------------------------------------------------ settlement

  int birdSeat(int t) => (dealer + (rankOf(t) - 1)) % players;

  void _settleWin(Map<int, (int, CsResult)> wins, int from, {bool rob = false}) {
    final zimo = from < 0;
    // 扎鸟
    final birds = <int>[];
    for (var i = 0; i < birdN && wall.isNotEmpty; i++) {
      birds.add(wall.removeLast());
    }
    final birdSeats = [for (final b in birds) birdSeat(b)];
    for (final e in wins.entries) {
      final w = e.key;
      final (tile, res) = e.value;
      if (zimo) hands[w][tile]--; // the winning tile is shown separately
      drawn[w] = -1;
      final payers = zimo ? [for (var o = 0; o < players; o++) if (o != w) o] : [from];
      final pay = <String, int>{};
      for (final p in payers) {
        var base = res.isBig ? 6 * res.bigCount : (zimo ? 2 : 1);
        if (p == dealer || w == dealer) base += 1; // 庄闲
        final hits = birdSeats.where((b) => b == w || b == p).length;
        final amt = base * (1 + hits);
        _pay(p, w, amt);
        pay['$p'] = amt;
      }
      events.add({
        'kind': 'hu',
        'seat': w,
        'from': from,
        'tile': tileCode(tile),
        'zimo': zimo,
        'rob': rob,
        'big': res.isBig,
        'items': res.toJson(),
        'pay': pay,
        'hand': [for (final c in codesOfCounts(hands[w])) c],
      });
      host.log(zimo
          ? '${name(w)} 自摸 ${tileName(tile)}！${res.label}'
          : '${name(w)} 胡 ${name(from)} 的 ${tileName(tile)}${rob ? '（抢杠）' : ''}！${res.label}');
      _event(zimo ? 'zimo' : 'hu', w, [tile]);
    }
    lastAction = zimo ? '${name(wins.keys.first)} 自摸' : '${wins.keys.map(name).join('、')} 胡牌（${name(from)} 点炮）';
    nextDealer = wins.length == 1 ? wins.keys.first : from;
    _endHand(birds: birds, birdSeats: birdSeats);
  }

  void _drawnGame() {
    host.log('海底摸完，流局');
    lastAction = '流局';
    nextDealer = dealer;
    _endHand();
  }

  void _endHand({List<int> birds = const [], List<int> birdSeats = const []}) {
    claim = null;
    settle = {
      'hand': handNo,
      'events': events,
      'win': events.any((e) => e['kind'] == 'hu'),
      'birds': [for (final b in birds) tileCode(b)],
      'birdSeats': birdSeats,
      'delta': List.of(handDelta),
      'dealer': dealer,
    };
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

  List<int> ranking() => List.generate(players, (i) => i)..sort((a, b) => scores[b].compareTo(scores[a]));

  void _nextHand() {
    if (nextDealer >= 0) dealer = nextDealer;
    _startHand();
  }
}
