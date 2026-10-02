import 'dart:math';

import '../../src/engine.dart';

/// 骗子酒馆 (Liar's Bar). Modes:
///  deck   骗子牌桌   devil 恶魔牌   chaos 混沌模式
///  dice   骗子骰子（输家开枪）   classic 经典吹牛骰（输家减骰）
const liarsModes = {
  'deck': '骗子牌桌',
  'dice': '骗子骰子',
  'devil': '恶魔牌',
  'chaos': '混沌模式',
  'classic': '经典吹牛骰',
};

const liarsCardNames = {'Q': 'Q', 'K': 'K', 'A': 'A', 'J': '王牌', 'D': '恶魔牌', 'C': '混沌牌'};

class LiarsBar extends GameEngine {
  LiarsBar(super.setup);

  late final String mode = setup.opt<String>('mode', 'deck');
  late final bool wildOnes = setup.opt<bool>('wild', true);
  bool get isDice => mode == 'dice' || mode == 'classic';

  late List<bool> alive = List.filled(players, true);
  late List<int> bullet = List.filled(players, 0);
  late List<int> shots = List.filled(players, 0);
  String phase = 'play'; // play / reveal / over
  int turn = 0;
  int roundNo = 0;
  List<String> logs = [];
  int winner = -1;
  Map<String, dynamic>? reveal;

  /// Elimination event index per seat (0 = still alive). Same event = tie.
  late List<int> outAt = List.filled(players, 0);
  int _outEvent = 0;
  late List<bool> resigned = List.filled(players, false);

  // ---- card state ----
  String tableCard = 'Q';
  late List<List<String>> hands = [for (var i = 0; i < players; i++) <String>[]];
  List<String> pile = []; // face-down played cards this round (count only public)
  List<String> lastCards = [];
  int lastPlayer = -1;
  late List<List<String>> myPlayed = [for (var i = 0; i < players; i++) <String>[]];
  int deckSize = 0;
  int truthTotal = 0;

  // ---- dice state ----
  late List<List<int>> dice = [for (var i = 0; i < players; i++) <int>[]];
  late List<int> diceCount = List.filled(players, 5);
  int bidQty = 0, bidFace = 0, bidder = -1;

  void _log(String s) {
    logs.add(s);
    if (logs.length > 30) logs.removeAt(0);
    host.log(s);
  }

  @override
  void start() {
    for (var i = 0; i < players; i++) {
      bullet[i] = rng.nextInt(6);
    }
    host.log('骗子酒馆 · ${liarsModes[mode]} 开始！${isDice && mode == 'classic' ? '失去所有骰子者出局' : '每把左轮 6 个弹膛只有 1 发子弹'}');
    _newRound(rng.nextInt(players));
  }

  int _nextAlive(int s, {bool Function(int)? where}) {
    for (var k = 1; k <= players; k++) {
      final t = (s + k) % players;
      if (alive[t] && (where == null || where(t))) return t;
    }
    return -1;
  }

  List<int> get aliveSeats => [for (var i = 0; i < players; i++) if (alive[i]) i];

  void _newRound(int starter) {
    roundNo++;
    reveal = null;
    phase = 'play';
    var s = starter % players;
    if (!alive[s]) s = _nextAlive(s);
    turn = s;
    if (isDice) {
      for (var i = 0; i < players; i++) {
        dice[i] = alive[i] ? [for (var k = 0; k < diceCount[i]; k++) rng.nextInt(6) + 1] : [];
      }
      bidQty = 0;
      bidFace = 0;
      bidder = -1;
      _log('—— 第 $roundNo 轮：所有人摇骰，${name(turn)} 先叫 ——');
      return;
    }
    // Build deck.
    final copies = players > 4 ? 2 : 1;
    final deck = <String>[];
    for (var c = 0; c < copies; c++) {
      for (final r in ['Q', 'K', 'A']) {
        for (var k = 0; k < 6; k++) {
          deck.add(r);
        }
      }
      deck.addAll(['J', 'J']);
    }
    tableCard = ['Q', 'K', 'A'][rng.nextInt(3)];
    if (mode == 'devil') {
      // replace one non-table card with the devil card
      deck.shuffle(rng);
      final i = deck.indexWhere((c) => c != tableCard && c != 'J');
      deck[i] = 'D';
    } else if (mode == 'chaos') {
      deck.shuffle(rng);
      for (var n = 0; n < 2; n++) {
        final i = deck.indexWhere((c) => c != tableCard && c != 'J' && c != 'C');
        deck[i] = 'C';
      }
    }
    deck.shuffle(rng);
    deckSize = aliveSeats.length * 5;
    truthTotal = 0;
    for (var i = 0; i < players; i++) {
      hands[i] = alive[i] ? [for (var k = 0; k < 5; k++) deck.removeLast()] : [];
      hands[i].sort();
      myPlayed[i] = [];
      truthTotal += hands[i].where(_truthful).length;
    }
    pile = [];
    lastCards = [];
    lastPlayer = -1;
    _log('—— 第 $roundNo 轮：本轮桌牌是 $tableCard，${name(turn)} 先出 ——');
  }

  bool _truthful(String c) => c == tableCard || c == 'J' || c == 'D' || c == 'C';

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    return rankByScore([for (var i = 0; i < players; i++) alive[i] ? 1 << 30 : outAt[i]]);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    if (!alive[seat]) throw GameError('你已经出局了');
    alive[seat] = false;
    resigned[seat] = true;
    outAt[seat] = ++_outEvent;
    _log('${name(seat)} 认输');
    final al = aliveSeats;
    if (al.length <= 1) {
      winner = al.isEmpty ? -1 : al.first;
      phase = 'over';
      _log(winner >= 0 ? '游戏结束！${name(winner)} 是最后的幸存者' : '游戏结束！');
      return;
    }
    if (phase == 'play') {
      _log('本轮作废，重新开始');
      _newRound(alive[turn] ? turn : _nextAlive(turn));
    }
    // phase 'reveal': the scheduled new round skips the resigned seat.
  }

  @override
  List<int> get waitingFor => phase == 'play' ? [turn] : const [];

  /// Card mode: can the current player only challenge?
  bool get _mustChallenge => !isDice && lastPlayer >= 0 && hands[turn].isEmpty;

  int get _totalDice => aliveSeats.fold(0, (a, s) => a + dice[s].length);

  /// Ordering rank of a bid face (1 is highest when wild).
  int _faceRank(int f) => wildOnes && f == 1 ? 7 : f;

  bool _higher(int q, int f) =>
      q > bidQty || (q == bidQty && _faceRank(f) > _faceRank(bidFace));

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    if (phase != 'play' || seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (isDice) {
      _handleDice(seat, type, a);
    } else {
      _handleCards(seat, type, a);
    }
  }

  void _handleCards(int seat, String type, Map<String, dynamic> a) {
    if (type == 'play') {
      if (_mustChallenge) throw GameError('你没有手牌了，只能喊骗子');
      final idx = asIntList(a['cards']).toSet().toList()..sort();
      if (idx.isEmpty || idx.length > 3) throw GameError('请选择 1~3 张牌');
      if (idx.any((i) => i < 0 || i >= hands[seat].length)) throw GameError('无效的牌');
      final cards = [for (final i in idx) hands[seat][i]];
      for (final i in idx.reversed) {
        hands[seat].removeAt(i);
      }
      pile.addAll(cards);
      myPlayed[seat].addAll(cards);
      lastCards = cards;
      lastPlayer = seat;
      _log('${name(seat)} 打出 ${cards.length} 张牌，声称都是 $tableCard');
      // next responder: next alive player with cards, else next alive (forced to challenge)
      var nx = _nextAlive(seat, where: (t) => hands[t].isNotEmpty);
      if (nx < 0 || nx == seat) nx = _nextAlive(seat);
      turn = nx;
      return;
    }
    if (type == 'challenge') {
      if (lastPlayer < 0) throw GameError('还没有人出牌，不能喊骗子');
      final liar = lastPlayer;
      final lie = lastCards.any((c) => !_truthful(c));
      _log('${name(seat)} 喊：骗子！翻开 ${name(liar)} 的牌：${lastCards.map((c) => liarsCardNames[c]).join(' ')}');
      List<int> shooters;
      String why;
      if (mode == 'chaos' && lastCards.contains('C')) {
        shooters = [liar, seat];
        why = '混沌牌现身！双方都要开枪';
      } else if (lie) {
        shooters = [liar];
        why = '${name(liar)} 撒谎了';
      } else if (mode == 'devil' && lastCards.contains('D')) {
        shooters = [for (final s in aliveSeats) if (s != liar) s];
        why = '恶魔牌现身！除 ${name(liar)} 外所有人开枪';
      } else {
        shooters = [seat];
        why = '${name(liar)} 说的是实话';
      }
      _log(why);
      _resolve(shooters, {'cards': lastCards, 'liar': liar, 'challenger': seat, 'lie': lie, 'why': why},
          starterHint: shooters.first);
      return;
    }
    throw GameError('未知操作');
  }

  void _handleDice(int seat, String type, Map<String, dynamic> a) {
    if (type == 'bid') {
      final q = asInt(a['qty']);
      final f = asInt(a['face']);
      if (f < 1 || f > 6) throw GameError('点数须为 1~6');
      if (q < 1 || q > _totalDice) throw GameError('数量须在 1~$_totalDice 之间');
      if (bidder >= 0 && !_higher(q, f)) throw GameError('叫价必须比上家更高');
      bidQty = q;
      bidFace = f;
      bidder = seat;
      _log('${name(seat)} 叫：$q 个 $f');
      turn = _nextAlive(seat);
      return;
    }
    if (type == 'challenge') {
      if (bidder < 0) throw GameError('还没有人叫价');
      var count = 0;
      for (final s in aliveSeats) {
        for (final d in dice[s]) {
          if (d == bidFace || (wildOnes && bidFace != 1 && d == 1)) count++;
        }
      }
      final truth = count >= bidQty;
      final loser = truth ? seat : bidder;
      final why = '开骰！共有 $count 个 $bidFace${wildOnes && bidFace != 1 ? '（含 1 点万能）' : ''}，'
          '${truth ? '${name(bidder)} 的叫价成立，${name(seat)} 输' : '${name(bidder)} 吹牛了，${name(bidder)} 输'}';
      _log('${name(seat)} 喊：骗子！');
      _log(why);
      final rv = {
        'dice': [for (var s = 0; s < players; s++) dice[s]],
        'bidder': bidder,
        'challenger': seat,
        'qty': bidQty,
        'face': bidFace,
        'count': count,
        'lie': !truth,
        'why': why,
      };
      if (mode == 'classic') {
        diceCount[loser]--;
        rv['loser'] = loser;
        if (diceCount[loser] <= 0) {
          alive[loser] = false;
          outAt[loser] = ++_outEvent;
          _log('${name(loser)} 失去了最后一颗骰子，出局！');
        } else {
          _log('${name(loser)} 失去一颗骰子，剩 ${diceCount[loser]} 颗');
        }
        _afterReveal(rv, loser);
        return;
      }
      _resolve([loser], rv, starterHint: loser);
      return;
    }
    throw GameError('未知操作');
  }

  /// Each seat in [shooters] pulls the trigger of their own revolver.
  void _resolve(List<int> shooters, Map<String, dynamic> rv, {required int starterHint}) {
    final shotsRes = <Map<String, dynamic>>[];
    final ev = ++_outEvent;
    for (final s in shooters) {
      if (!alive[s]) continue;
      final dead = shots[s] == bullet[s];
      shots[s]++;
      if (dead) {
        alive[s] = false;
        outAt[s] = ev;
        _log('${name(s)} 扣动扳机…… 砰！${name(s)} 倒下了（第 ${shots[s]}/6 发）');
      } else {
        _log('${name(s)} 扣动扳机…… 咔哒，空枪（${shots[s]}/6）');
      }
      shotsRes.add({'seat': s, 'dead': dead, 'shot': shots[s]});
    }
    rv['shots'] = shotsRes;
    _afterReveal(rv, starterHint);
  }

  void _afterReveal(Map<String, dynamic> rv, int starter) {
    reveal = rv;
    final al = aliveSeats;
    if (al.length <= 1) {
      winner = al.isEmpty ? -1 : al.first;
      phase = 'over';
      _log(winner >= 0 ? '游戏结束！${name(winner)} 是最后的幸存者' : '游戏结束！无人生还');
      return;
    }
    phase = 'reveal';
    var st = starter;
    if (!alive[st]) st = _nextAlive(st);
    host.schedule(3500, () {
      if (phase == 'reveal') _newRound(st);
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final showAll = phase != 'play';
    return {
      'players': players,
      'mode': mode,
      'modeName': liarsModes[mode],
      'wild': wildOnes,
      'phase': phase,
      'turn': turn,
      'round': roundNo,
      'alive': alive,
      'shots': shots,
      'log': logs.length > 12 ? logs.sublist(logs.length - 12) : logs,
      'reveal': reveal,
      'winner': winner,
      'resigned': resigned,
      'over': phase == 'over',
      if (!isDice) ...{
        'tableCard': tableCard,
        'hand': me ? hands[seat] : <String>[],
        'handCounts': [for (final h in hands) h.length],
        'pile': pile.length,
        'lastCount': lastCards.length,
        'lastPlayer': lastPlayer,
        'mustChallenge': phase == 'play' && seat == turn && _mustChallenge,
        'canChallenge': phase == 'play' && lastPlayer >= 0,
      },
      if (isDice) ...{
        'dice': me ? dice[seat] : <int>[],
        'allDice': showAll && reveal != null ? reveal!['dice'] : null,
        'diceCounts': [for (var s = 0; s < players; s++) alive[s] ? dice[s].length : 0],
        'totalDice': _totalDice,
        'bidQty': bidQty,
        'bidFace': bidFace,
        'bidder': bidder,
      },
    };
  }

  // ---------------- bot ----------------

  static double _binomAtLeast(int n, int k, double p) {
    if (k <= 0) return 1;
    if (k > n) return 0;
    var total = 0.0;
    for (var i = k; i <= n; i++) {
      var c = 1.0;
      for (var j = 0; j < i; j++) {
        c = c * (n - j) / (j + 1);
      }
      total += c * pow(p, i) * pow(1 - p, n - i);
    }
    return total;
  }

  double _bidProb(int seat, int q, int f) {
    final mine = dice[seat].where((d) => d == f || (wildOnes && f != 1 && d == 1)).length;
    final unknown = _totalDice - dice[seat].length;
    final p = (wildOnes && f != 1) ? 1 / 3 : 1 / 6;
    return _binomAtLeast(unknown, q - mine, p);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play') return null;
    return isDice ? _botDice(seat) : _botCards(seat);
  }

  Map<String, dynamic> _botDice(int seat) {
    final total = _totalDice;
    if (botLevel == 0) {
      if (bidder >= 0 && rng.nextDouble() < 0.3) return {'type': 'challenge'};
      final opts = <(int, int)>[];
      for (var f = 1; f <= 6; f++) {
        for (var q = bidder < 0 ? 1 : bidQty; q <= total && q <= (bidder < 0 ? 1 : bidQty) + 1; q++) {
          if (bidder < 0 || _higher(q, f)) opts.add((q, f));
        }
      }
      if (opts.isEmpty) return {'type': 'challenge'};
      final (q, f) = opts[rng.nextInt(opts.length)];
      return {'type': 'bid', 'qty': q, 'face': f};
    }
    final hard = botLevel >= 2;
    if (bidder >= 0) {
      final pTrue = _bidProb(seat, bidQty, bidFace);
      if (pTrue < (hard ? 0.45 + rng.nextDouble() * 0.05 : 0.35 + rng.nextDouble() * 0.15)) return {'type': 'challenge'};
    }
    // choose best raise
    (int, int)? best;
    var bestP = -1.0;
    for (var f = 1; f <= 6; f++) {
      var q = bidder < 0 ? 1 : bidQty;
      while (q <= total && bidder >= 0 && !_higher(q, f)) {
        q++;
      }
      if (q > total) continue;
      // bump opening bids to something sensible
      while (q < total && _bidProb(seat, q + 1, f) > 0.6) {
        q++;
      }
      final p = _bidProb(seat, q, f) + rng.nextDouble() * (hard ? 0.02 : 0.08);
      if (p > bestP) {
        bestP = p;
        best = (q, f);
      }
    }
    if (best == null) return {'type': 'challenge'};
    if (bidder >= 0 && bestP < 0.25) return {'type': 'challenge'};
    return {'type': 'bid', 'qty': best.$1, 'face': best.$2};
  }

  Map<String, dynamic> _botCards(int seat) {
    final hand = hands[seat];
    if (botLevel == 0) {
      if (lastPlayer >= 0 && (hand.isEmpty || rng.nextDouble() < 0.3)) return {'type': 'challenge'};
      final idx = [for (var i = 0; i < hand.length; i++) i]..shuffle(rng);
      return {'type': 'play', 'cards': idx.take(1 + rng.nextInt(min(3, hand.length))).toList()};
    }
    final hard = botLevel >= 2;
    if (lastPlayer >= 0) {
      if (hand.isEmpty) return {'type': 'challenge'};
      final myTruth = hand.where(_truthful).length + myPlayed[seat].where(_truthful).length;
      final pool = deckSize - hand.length - myPlayed[seat].length;
      final truthPool = truthTotal - myTruth;
      final n = lastCards.length;
      double pTruth;
      if (truthPool < n || pool <= 0) {
        pTruth = 0;
      } else {
        pTruth = 1;
        for (var i = 0; i < n; i++) {
          pTruth *= (truthPool - i) / (pool - i);
        }
        // players tend to play true cards more often than random
        pTruth = pTruth * 0.5 + 0.35;
      }
      final forcedLie = !hand.any(_truthful);
      var threshold = 0.45;
      if (forcedLie) threshold = 0.65;
      if (hands[lastPlayer].isEmpty) threshold += 0.1;
      if (pTruth < threshold + (rng.nextDouble() - 0.5) * (hard ? 0.06 : 0.2)) return {'type': 'challenge'};
    }
    final truthIdx = [for (var i = 0; i < hand.length; i++) if (_truthful(hand[i])) i];
    final lieIdx = [for (var i = 0; i < hand.length; i++) if (!_truthful(hand[i])) i];
    // 困难：下家已没有手牌（只能喊骗子）时只出真话牌
    var nextForced = false;
    if (hard) {
      var nx = _nextAlive(seat, where: (t) => hands[t].isNotEmpty);
      if (nx < 0 || nx == seat) nx = _nextAlive(seat);
      nextForced = nx >= 0 && hands[nx].isEmpty;
    }
    List<int> pick;
    if (truthIdx.isNotEmpty && (lieIdx.isEmpty || nextForced || rng.nextDouble() < 0.8)) {
      // play plain table cards first, keep jokers for later
      truthIdx.sort((a, b) => (hand[a] == tableCard ? 0 : 1).compareTo(hand[b] == tableCard ? 0 : 1));
      final n = 1 + rng.nextInt(min(truthIdx.length, lieIdx.isEmpty ? 3 : 2));
      pick = truthIdx.take(n).toList();
    } else {
      lieIdx.shuffle(rng);
      pick = lieIdx.take(1).toList();
    }
    return {'type': 'play', 'cards': pick};
  }
}
