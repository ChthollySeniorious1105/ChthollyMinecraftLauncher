import '../../src/engine.dart';

/// 爆炸猫（原创卡面，规则参照基础版）。
///
/// 牌：bomb 爆炸猫, defuse 拆除, skip 跳过, attack 攻击, shuffle 洗牌,
/// future 先知, favor 索要, nope 不要, cat1..cat5 五种猫牌。
class ExplodingKittens extends GameEngine {
  ExplodingKittens(super.setup);

  static const cardNames = {
    'bomb': '爆炸猫',
    'defuse': '拆除',
    'skip': '跳过',
    'attack': '攻击',
    'shuffle': '洗牌',
    'future': '先知',
    'favor': '索要',
    'nope': '不要',
    'cat1': '彩虹猫',
    'cat2': '西瓜猫',
    'cat3': '胡子猫',
    'cat4': '土豆猫',
    'cat5': '章鱼猫',
  };
  static const actionCards = {'skip', 'attack', 'shuffle', 'future', 'favor'};
  static bool isCat(String c) => c.startsWith('cat');

  late final int handSize = setup.opt<int>('hand', 7);

  List<List<String>> hands = [];
  List<String> deck = []; // last = top
  List<String> discard = [];
  List<bool> alive = [];
  int turn = 0;
  int turnsLeft = 1;
  String phase = 'turn'; // turn / nope / favor / defuse / over
  int winner = -1;
  int actionsThisTurn = 0;

  /// Seats in elimination order (first out first).
  List<int> outOrder = [];

  /// Pending action waiting for the nope window.
  Map<String, dynamic>? pending;
  int nopeCount = 0;
  int lastNoper = -1;
  Set<int> passed = {};
  int _timerToken = 0;

  int favorFrom = -1; // target giving a card
  int favorTo = -1;
  List<List<String>?> future = [];
  String lastEvent = '';
  List<String> events = [];

  String cn(String c) => cardNames[c] ?? c;

  void _event(String s) {
    lastEvent = s;
    events.add(s);
    if (events.length > 30) events.removeAt(0);
    host.log(s);
  }

  @override
  void start() {
    final base = <String>[
      for (var i = 0; i < 4; i++) 'attack',
      for (var i = 0; i < 4; i++) 'skip',
      for (var i = 0; i < 4; i++) 'favor',
      for (var i = 0; i < 4; i++) 'shuffle',
      for (var i = 0; i < 5; i++) 'future',
      for (var i = 0; i < 5; i++) 'nope',
      for (var k = 1; k <= 5; k++)
        for (var i = 0; i < 4; i++) 'cat$k',
    ];
    deck = shuffled(base, rng);
    hands = [
      for (var s = 0; s < players; s++) ['defuse', for (var i = 0; i < handSize; i++) deck.removeLast()],
    ];
    final extraDefuse = players <= 3 ? 2 : 6 - players;
    deck.addAll([for (var i = 0; i < extraDefuse; i++) 'defuse']);
    deck.addAll([for (var i = 0; i < players - 1; i++) 'bomb']);
    deck.shuffle(rng);
    alive = List.filled(players, true);
    future = List.filled(players, null);
    turn = rng.nextInt(players);
    turnsLeft = 1;
    _event('游戏开始！牌堆中有 ${players - 1} 只爆炸猫，${name(turn)} 先手');
  }

  @override
  bool get isOver => phase == 'over';

  /// Winner 1st, then by elimination order (later out = better).
  @override
  List<int>? get placings {
    if (!isOver) return null;
    final r = List.filled(players, 1);
    for (var i = 0; i < outOrder.length; i++) {
      r[outOrder[i]] = players - i;
    }
    for (var s = 0; s < players; s++) {
      if (!outOrder.contains(s)) r[s] = 1;
    }
    return r;
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    _timerToken++;
    pending = null;
    alive[seat] = false;
    outOrder.add(seat);
    winner = 1 - seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
    _event('${name(winner)} 获胜！');
  }

  List<int> get _nopers => [
        for (var s = 0; s < players; s++)
          if (alive[s] && s != lastNoper && !passed.contains(s) && hands[s].contains('nope')) s,
      ];

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'turn':
      case 'defuse':
        return [turn];
      case 'nope':
        return _nopers;
      case 'favor':
        return [favorFrom];
    }
    return const [];
  }

  int _next(int s) {
    var n = s;
    do {
      n = (n + 1) % players;
    } while (!alive[n]);
    return n;
  }

  void _endTurn() {
    turnsLeft--;
    if (turnsLeft <= 0) {
      turn = _next(turn);
      turnsLeft = 1;
      actionsThisTurn = 0;
    }
  }

  void _remove(int seat, String card, [int n = 1]) {
    for (var i = 0; i < n; i++) {
      if (!hands[seat].remove(card)) throw GameError('你没有「${cn(card)}」');
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('游戏已结束');
    final type = asStr(a['type']);
    switch (phase) {
      case 'nope':
        if (type == 'nope') {
          if (!_nopers.contains(seat)) throw GameError('你不能出不要');
          _remove(seat, 'nope');
          discard.add('nope');
          nopeCount++;
          lastNoper = seat;
          passed = {};
          _event('${name(seat)} 打出「不要」！${nopeCount.isOdd ? "行动被阻止" : "行动恢复"}');
          _openWindow();
          return;
        }
        if (type == 'pass') {
          if (!_nopers.contains(seat)) throw GameError('你不能出不要');
          passed.add(seat);
          if (_nopers.isEmpty) _resolve();
          return;
        }
        throw GameError('等待其他玩家响应「不要」');
      case 'favor':
        if (seat != favorFrom) throw GameError('等待 ${name(favorFrom)} 给牌');
        if (type != 'give') throw GameError('请选择一张牌交给对方');
        final c = asStr(a['card']);
        _remove(seat, c);
        hands[favorTo].add(c);
        _event('${name(seat)} 给了 ${name(favorTo)} 一张牌');
        phase = 'turn';
        return;
      case 'defuse':
        if (seat != turn) throw GameError('还没轮到你');
        if (type != 'place') throw GameError('请选择放回爆炸猫的位置');
        final pos = asInt(a['pos'], 0).clamp(0, deck.length); // 0 = top
        deck.insert(deck.length - pos, 'bomb');
        _event('${name(seat)} 把爆炸猫悄悄放回了牌堆');
        for (var s = 0; s < players; s++) {
          future[s] = null;
        }
        phase = 'turn';
        _endTurn();
        return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'draw') {
      future[seat] = null;
      _draw(seat);
      return;
    }
    if (type != 'play') throw GameError('无效操作');
    final card = asStr(a['card']);
    final target = asInt(a['target']);
    final count = asInt(a['count'], 1);
    if (!hands[seat].contains(card)) throw GameError('你没有这张牌');
    Map<String, dynamic> p;
    if (actionCards.contains(card)) {
      if (card == 'favor') _checkTarget(seat, target);
      future[seat] = null;
      _remove(seat, card);
      discard.add(card);
      p = {'seat': seat, 'card': card, 'target': card == 'favor' ? target : -1};
      if (card == 'attack') p['target'] = _next(seat);
      _event('${name(seat)} 打出「${cn(card)}」${card == 'favor' ? '，向 ${name(target)} 索要一张牌' : ''}');
    } else if (isCat(card)) {
      if (count != 2 && count != 3) throw GameError('猫牌需两张或三张一起出');
      if (hands[seat].where((c) => c == card).length < count) throw GameError('同种猫牌不够');
      _checkTarget(seat, target);
      final named = asStr(a['named']);
      if (count == 3 && !cardNames.containsKey(named)) throw GameError('请指定要索取的牌');
      future[seat] = null;
      _remove(seat, card, count);
      for (var i = 0; i < count; i++) {
        discard.add(card);
      }
      p = {'seat': seat, 'card': card, 'count': count, 'target': target, 'named': count == 3 ? named : null};
      _event(count == 2
          ? '${name(seat)} 打出一对「${cn(card)}」，要随机抽 ${name(target)} 一张牌'
          : '${name(seat)} 打出三张「${cn(card)}」，向 ${name(target)} 索要「${cn(named)}」');
    } else {
      throw GameError('这张牌不能主动打出');
    }
    actionsThisTurn++;
    pending = p;
    nopeCount = 0;
    lastNoper = seat;
    passed = {};
    phase = 'nope';
    _openWindow();
  }

  void _checkTarget(int seat, int target) {
    if (target < 0 || target >= players || target == seat || !alive[target]) throw GameError('请选择一名存活的对手');
    if (hands[target].isEmpty) throw GameError('对方没有手牌');
  }

  void _openWindow() {
    if (_nopers.isEmpty) {
      _resolve();
      return;
    }
    final token = ++_timerToken;
    host.schedule(4000, () {
      if (phase == 'nope' && token == _timerToken) _resolve();
    });
  }

  void _resolve() {
    _timerToken++;
    final p = pending!;
    pending = null;
    phase = 'turn';
    if (nopeCount.isOdd) {
      _event('「${cn(p['card'] as String)}」被阻止了');
      return;
    }
    final seat = p['seat'] as int;
    final card = p['card'] as String;
    final target = p['target'] as int;
    switch (card) {
      case 'skip':
        _endTurn();
        break;
      case 'attack':
        final extra = turnsLeft > 1 ? turnsLeft : 0;
        turn = _next(seat);
        turnsLeft = extra + 2;
        actionsThisTurn = 0;
        _event('${name(turn)} 需要连续进行 $turnsLeft 个回合');
        break;
      case 'shuffle':
        deck.shuffle(rng);
        for (var s = 0; s < players; s++) {
          future[s] = null;
        }
        break;
      case 'future':
        future[seat] = [for (var i = 0; i < 3 && i < deck.length; i++) deck[deck.length - 1 - i]];
        break;
      case 'favor':
        if (hands[target].isEmpty) break;
        favorFrom = target;
        favorTo = seat;
        phase = 'favor';
        break;
      default:
        if (hands[target].isEmpty) break;
        if (p['count'] == 2) {
          final i = rng.nextInt(hands[target].length);
          final c = hands[target].removeAt(i);
          hands[seat].add(c);
          _event('${name(seat)} 从 ${name(target)} 手中抽走了一张牌');
        } else {
          final named = p['named'] as String;
          if (hands[target].remove(named)) {
            hands[seat].add(named);
            _event('${name(seat)} 拿走了 ${name(target)} 的「${cn(named)}」');
          } else {
            _event('${name(target)} 没有「${cn(named)}」');
          }
        }
    }
  }

  void _draw(int seat) {
    final c = deck.removeLast();
    for (var s = 0; s < players; s++) {
      final f = future[s];
      if (f != null && f.isNotEmpty) f.removeAt(0);
    }
    if (c != 'bomb') {
      hands[seat].add(c);
      _event('${name(seat)} 摸了一张牌');
      _endTurn();
      return;
    }
    if (hands[seat].remove('defuse')) {
      discard.add('defuse');
      _event('${name(seat)} 摸到了爆炸猫！使用「拆除」化险为夷');
      phase = 'defuse';
      return;
    }
    _event('💥 ${name(seat)} 摸到了爆炸猫，爆炸出局！');
    alive[seat] = false;
    outOrder.add(seat);
    discard.addAll(hands[seat]);
    discard.add('bomb');
    hands[seat] = [];
    final left = [for (var s = 0; s < players; s++) if (alive[s]) s];
    if (left.length == 1) {
      winner = left.first;
      phase = 'over';
      _event('${name(winner)} 是最后的幸存者，获胜！');
      return;
    }
    turn = _next(seat);
    turnsLeft = 1;
    actionsThisTurn = 0;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'phase': phase,
      'turn': turn,
      'turnsLeft': turnsLeft,
      'hand': me ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'alive': alive,
      'deck': deck.length,
      'discard': discard.length > 8 ? discard.sublist(discard.length - 8) : discard,
      'pending': pending,
      'nopeCount': nopeCount,
      // Only reveal whether *this* seat may Nope: the full list would expose who holds a Nope card.
      'nopers': phase == 'nope' && me && _nopers.contains(seat) ? [seat] : <int>[],
      'favorFrom': phase == 'favor' ? favorFrom : -1,
      'favorTo': phase == 'favor' ? favorTo : -1,
      'future': me ? future[seat] : null,
      'kittens': deck.where((c) => c == 'bomb').length,
      'event': lastEvent,
      'events': events.length > 6 ? events.sublist(events.length - 6) : events,
      'winner': winner,
      'hands': phase == 'over' ? hands : null,
      'over': isOver,
    };
  }

  // ---------------- bot ----------------
  @override
  Map<String, dynamic>? bot(int seat) {
    final hand = hands[seat];
    switch (phase) {
      case 'nope':
        final p = pending!;
        final againstMe = p['target'] == seat;
        final mine = p['seat'] == seat;
        final wantBlock = (againstMe && nopeCount.isEven) || (mine && nopeCount.isOdd);
        final p0 = botLevel == 0 ? 0.3 : (botLevel >= 2 ? 1.0 : 0.75);
        if (wantBlock && hand.contains('nope') && rng.nextDouble() < p0) return {'type': 'nope'};
        return {'type': 'pass'};
      case 'favor':
        if (botLevel == 0) return {'type': 'give', 'card': hand[rng.nextInt(hand.length)]};
        final order = [
          for (final c in hand)
            (c, isCat(c) ? 0 : (c == 'shuffle' || c == 'future' ? 1 : (c == 'defuse' ? 9 : 3))),
        ]..sort((x, y) => x.$2 - y.$2);
        return {'type': 'give', 'card': order.first.$1};
      case 'defuse':
        if (botLevel == 0) return {'type': 'place', 'pos': rng.nextInt(deck.length + 1)};
        if (botLevel >= 2) {
          // 放在下家要摸的位置：下家通常只摸一张 → 顶部；被攻击时放第二张
          final pos = turnsLeft > 1 ? 1 : 0;
          return {'type': 'place', 'pos': pos.clamp(0, deck.length)};
        }
        final r = rng.nextDouble();
        final pos = r < 0.4 ? 0 : (r < 0.6 ? 1 : rng.nextInt(deck.length + 1));
        return {'type': 'place', 'pos': pos};
      case 'turn':
        break;
      default:
        return null;
    }
    if (seat != turn) return null;
    if (botLevel == 0) return _easyTurn(seat, hand);
    final f = future[seat];
    final hasDefuse = hand.contains('defuse');
    final opponents = [for (var s = 0; s < players; s++) if (s != seat && alive[s] && hands[s].isNotEmpty) s];
    int richest() => (opponents..sort((a, b) => hands[b].length - hands[a].length)).first;
    if (actionsThisTurn < 4) {
      final danger = f != null && f.isNotEmpty && f.first == 'bomb';
      final safe = f != null && f.isNotEmpty && f.first != 'bomb';
      if (danger) {
        for (final c in ['skip', 'attack', 'shuffle']) {
          if (hand.contains(c)) return {'type': 'play', 'card': c};
        }
      }
      if (!safe) {
        // kittens left is public (shown in view)
        final risk = deck.isEmpty ? 1.0 : deck.where((c) => c == 'bomb').length / deck.length;
        if (botLevel >= 2) {
          if (hand.contains('future') && risk > 0.12) return {'type': 'play', 'card': 'future'};
          if (!hasDefuse && risk > 0.15) {
            for (final c in ['skip', 'attack']) {
              if (hand.contains(c)) return {'type': 'play', 'card': c};
            }
          }
        }
        if (!hasDefuse && risk > 0.2) {
          for (final c in ['future', 'skip', 'attack']) {
            if (hand.contains(c)) return {'type': 'play', 'card': c};
          }
        }
        if (risk > 0.34 && hand.contains('attack')) return {'type': 'play', 'card': 'attack'};
        if (hand.contains('future') && rng.nextDouble() < 0.3) return {'type': 'play', 'card': 'future'};
      }
      if (opponents.isNotEmpty) {
        for (var k = 1; k <= 5; k++) {
          final n = hand.where((c) => c == 'cat$k').length;
          if (n >= 3 && rng.nextDouble() < 0.7) {
            return {'type': 'play', 'card': 'cat$k', 'count': 3, 'target': richest(), 'named': 'defuse'};
          }
          if (n >= 2 && rng.nextDouble() < 0.6) {
            return {'type': 'play', 'card': 'cat$k', 'count': 2, 'target': richest()};
          }
        }
        if (hand.contains('favor') && rng.nextDouble() < 0.4) {
          return {'type': 'play', 'card': 'favor', 'target': richest()};
        }
      }
    }
    return {'type': 'draw'};
  }

  /// 简单：随手出牌，不看风险。
  Map<String, dynamic> _easyTurn(int seat, List<String> hand) {
    if (actionsThisTurn < 2 && rng.nextDouble() < 0.35) {
      final acts = [for (final c in hand) if (actionCards.contains(c) && c != 'favor') c];
      if (acts.isNotEmpty) return {'type': 'play', 'card': acts[rng.nextInt(acts.length)]};
    }
    return {'type': 'draw'};
  }

  @override
  int get botDelayMs => 900;
}
