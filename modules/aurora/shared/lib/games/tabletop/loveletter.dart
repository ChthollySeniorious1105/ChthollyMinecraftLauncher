import '../../src/engine.dart';

/// 情书 (Love Letter, 2019 edition, 21 cards).
const loveLetterNames = ['间谍', '卫兵', '牧师', '男爵', '侍女', '王子', '大臣', '国王', '伯爵夫人', '公主'];
const loveLetterCounts = [2, 6, 2, 2, 2, 2, 2, 1, 1, 1];
const loveLetterText = [
  '回合结束时，若你是唯一打出或弃置过间谍的存活玩家，获得 1 枚好感标记。',
  '猜一名其他玩家的手牌（不能猜卫兵），猜中则其出局。',
  '秘密查看一名其他玩家的手牌。',
  '与一名其他玩家秘密比较手牌，点数小者出局。',
  '直到你的下个回合，你不会成为其他卡牌效果的目标。',
  '令一名玩家（可以是自己）弃掉手牌并重新摸一张。弃掉公主者出局。',
  '摸两张牌，从三张中保留一张，其余按任意顺序置于牌库底。',
  '与一名其他玩家交换手牌。',
  '若你手中另一张是国王或王子，必须打出伯爵夫人。',
  '若你打出或弃掉公主，你立即出局。',
];

int loveLetterTarget(int players) => switch (players) { 2 => 6, 3 => 5, 4 => 4, _ => 3 };

String _cn(int c) => '${loveLetterNames[c]}($c)';

class LoveLetter extends GameEngine {
  LoveLetter(super.setup);

  List<int> deck = [];
  int setAside = -1;
  List<int> faceUp = [];
  late List<List<int>> hands = [for (var i = 0; i < players; i++) <int>[]];
  late List<List<int>> discards = [for (var i = 0; i < players; i++) <int>[]];
  late List<bool> alive = List.filled(players, true);
  late List<bool> protectedS = List.filled(players, false);
  late List<int> tokens = List.filled(players, 0);
  late List<List<String>> priv = [for (var i = 0; i < players; i++) <String>[]];

  /// Bot memory: known[a][b] = card that a knows b holds (or -1).
  late List<List<int>> known = [for (var i = 0; i < players; i++) List.filled(players, -1)];
  List<String> logs = [];
  int turn = 0;
  int roundNo = 0;
  String phase = 'play'; // play / chancellor / roundEnd / over
  Map<String, dynamic>? roundResult;
  List<int> winners = [];
  Map<String, dynamic>? lastPlay;

  /// 认输顺序：resignOrder[s] = 第几个认输（从 1 开始），0 = 未认输。
  late List<int> resignOrder = List.filled(players, 0);
  int _resigns = 0;

  int get target => loveLetterTarget(players);

  void _log(String s) {
    logs.add(s);
    if (logs.length > 30) logs.removeAt(0);
    host.log(s);
  }

  void _priv(int seat, String s) {
    if (seat < 0) return;
    priv[seat].add(s);
    if (priv[seat].length > 8) priv[seat].removeAt(0);
  }

  @override
  void start() {
    host.log('情书开始！率先获得 $target 枚好感标记者获胜');
    _newRound(rng.nextInt(players));
  }

  void _newRound(int first) {
    roundNo++;
    deck = [];
    for (var c = 0; c < 10; c++) {
      for (var k = 0; k < loveLetterCounts[c]; k++) {
        deck.add(c);
      }
    }
    deck.shuffle(rng);
    setAside = deck.removeLast();
    faceUp = [];
    if (players == 2) {
      for (var i = 0; i < 3; i++) {
        faceUp.add(deck.removeLast());
      }
    }
    for (var i = 0; i < players; i++) {
      final active = resignOrder[i] == 0;
      hands[i] = active ? [deck.removeLast()] : <int>[];
      discards[i] = [];
      alive[i] = active;
      protectedS[i] = false;
      priv[i] = [];
      for (var j = 0; j < players; j++) {
        known[i][j] = -1;
      }
    }
    roundResult = null;
    lastPlay = null;
    _log('—— 第 $roundNo 局开始 ——');
    _beginTurn(first);
  }

  void _beginTurn(int seat) {
    var s = seat % players;
    while (!alive[s]) {
      s = (s + 1) % players;
    }
    turn = s;
    protectedS[s] = false;
    hands[s].add(deck.removeLast());
    phase = 'play';
  }

  int _draw() {
    if (deck.isNotEmpty) return deck.removeLast();
    final c = setAside;
    setAside = -1;
    return c;
  }

  void _eliminate(int s, String why) {
    alive[s] = false;
    protectedS[s] = false;
    discards[s].addAll(hands[s]);
    hands[s] = [];
    _log('${name(s)} 出局（$why）');
  }

  void _forget(int target) {
    for (var i = 0; i < players; i++) {
      known[i][target] = -1;
    }
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    return rankByScore([
      for (var i = 0; i < players; i++)
        resignOrder[i] != 0 ? -1000 + resignOrder[i] : (winners.contains(i) ? 1000 : tokens[i]),
    ]);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    if (resignOrder[seat] != 0) throw GameError('你已经认输了');
    resignOrder[seat] = ++_resigns;
    host.log('${name(seat)} 认输');
    final wasTurn = seat == turn && (phase == 'play' || phase == 'chancellor');
    if (alive[seat]) _eliminate(seat, '认输');
    final left = [for (var i = 0; i < players; i++) if (resignOrder[i] == 0) i];
    if (left.length <= 1) {
      winners = left;
      phase = 'over';
      _log('游戏结束！${left.map(name).join('、')} 赢得了公主的芳心');
      return;
    }
    if (phase != 'play' && phase != 'chancellor') return; // roundEnd: next round skips this seat
    final aliveSeats = [for (var i = 0; i < players; i++) if (alive[i]) i];
    if (aliveSeats.length <= 1) {
      phase = 'play';
      _endRound();
    } else if (wasTurn) {
      phase = 'play';
      _endTurn();
    }
  }

  @override
  List<int> get waitingFor => (phase == 'play' || phase == 'chancellor') ? [turn] : const [];

  List<int> _targets(int seat, {bool self = false}) => [
        for (var i = 0; i < players; i++)
          if (alive[i] && !protectedS[i] && (i != seat || self)) i
      ];

  bool _mustCountess(List<int> hand) => hand.contains(8) && (hand.contains(7) || hand.contains(5));

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != turn || !(phase == 'play' || phase == 'chancellor')) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (phase == 'chancellor') {
      if (type != 'keep') throw GameError('请选择要保留的牌');
      _chancellor(seat, asInt(a['card']), asIntList(a['bottom']));
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final card = asInt(a['card']);
    final hand = hands[seat];
    if (!hand.contains(card)) throw GameError('你没有这张牌');
    if (_mustCountess(hand) && card != 8) throw GameError('手中有国王或王子时必须打出伯爵夫人');
    var t = asInt(a['target']);
    final needsTarget = [1, 2, 3, 5, 7].contains(card);
    if (needsTarget) {
      final legal = _targets(seat, self: card == 5);
      if (legal.isEmpty) {
        t = -1;
      } else if (!legal.contains(t)) {
        throw GameError(card == 5 ? '请选择一名未受保护的玩家（可以是自己）' : '请选择一名未受保护的其他玩家');
      }
    } else {
      t = -1;
    }
    final guess = asInt(a['guess']);
    if (card == 1 && t >= 0 && (guess < 0 || guess > 9 || guess == 1)) throw GameError('请猜一张非卫兵的牌');

    hand.remove(card);
    discards[seat].add(card);
    // someone who knew this seat's card can no longer be sure
    for (var i = 0; i < players; i++) {
      if (known[i][seat] == card || i == seat) known[i][seat] = -1;
    }
    lastPlay = {'seat': seat, 'card': card, 'target': t, 'guess': card == 1 ? guess : -1};
    final who = name(seat);
    final tn = t >= 0 ? name(t) : '';
    switch (card) {
      case 0:
        _log('$who 打出 间谍');
      case 1:
        if (t < 0) {
          _log('$who 打出 卫兵，但没有可选目标');
        } else if (hands[t].first == guess) {
          _log('$who 打出 卫兵，猜 $tn 是 ${_cn(guess)} —— 猜中了！');
          _eliminate(t, '被卫兵猜中');
        } else {
          _log('$who 打出 卫兵，猜 $tn 是 ${_cn(guess)} —— 没猜中');
        }
      case 2:
        if (t < 0) {
          _log('$who 打出 牧师，但没有可选目标');
        } else {
          _log('$who 打出 牧师，查看了 $tn 的手牌');
          _priv(seat, '牧师：$tn 的手牌是 ${_cn(hands[t].first)}');
          _priv(t, '$who 用牧师看到了你的手牌');
          known[seat][t] = hands[t].first;
        }
      case 3:
        if (t < 0) {
          _log('$who 打出 男爵，但没有可选目标');
        } else {
          final mine = hand.first, theirs = hands[t].first;
          _log('$who 打出 男爵，与 $tn 比较手牌');
          _priv(seat, '男爵：你的 ${_cn(mine)} 对 $tn 的 ${_cn(theirs)}');
          _priv(t, '男爵：你的 ${_cn(theirs)} 对 $who 的 ${_cn(mine)}');
          if (mine > theirs) {
            _eliminate(t, '男爵比较点数较小');
          } else if (theirs > mine) {
            _eliminate(seat, '男爵比较点数较小');
          } else {
            _log('男爵比较结果：平局');
            known[seat][t] = theirs;
            known[t][seat] = mine;
          }
        }
      case 4:
        protectedS[seat] = true;
        _log('$who 打出 侍女，直到下回合前受到保护');
      case 5:
        final target = t < 0 ? seat : t;
        final tn2 = name(target);
        final dropped = hands[target].removeLast();
        discards[target].add(dropped);
        _forget(target);
        if (dropped == 9) {
          _log('$who 打出 王子，令 $tn2 弃掉了 ${_cn(dropped)}');
          _eliminate(target, '弃掉公主');
        } else {
          final nc = _draw();
          hands[target].add(nc);
          _log('$who 打出 王子，令 $tn2 弃掉 ${_cn(dropped)} 并重新摸牌');
        }
      case 6:
        final n = deck.length < 2 ? deck.length : 2;
        if (n == 0) {
          _log('$who 打出 大臣，但牌库已空');
        } else {
          for (var i = 0; i < n; i++) {
            hand.add(deck.removeLast());
          }
          _log('$who 打出 大臣，摸了 $n 张牌并挑选');
          phase = 'chancellor';
          return;
        }
      case 7:
        if (t < 0) {
          _log('$who 打出 国王，但没有可选目标');
        } else {
          final tmp = hands[seat];
          hands[seat] = hands[t];
          hands[t] = tmp;
          _forget(seat);
          _forget(t);
          known[seat][t] = hands[t].first;
          known[t][seat] = hands[seat].first;
          _log('$who 打出 国王，与 $tn 交换了手牌');
          _priv(seat, '国王：你从 $tn 换来了 ${_cn(hands[seat].first)}');
          _priv(t, '国王：$who 与你交换，你得到了 ${_cn(hands[t].first)}');
        }
      case 8:
        _log('$who 打出 伯爵夫人');
      case 9:
        _log('$who 打出 公主');
        _eliminate(seat, '打出公主');
    }
    _endTurn();
  }

  void _chancellor(int seat, int keep, List<int> bottom) {
    final hand = hands[seat];
    if (!hand.contains(keep)) throw GameError('你没有这张牌');
    final rest = List.of(hand)..remove(keep);
    final sortedRest = List.of(rest)..sort();
    final sortedBottom = List.of(bottom)..sort();
    List<int> order;
    if (sortedBottom.join(',') == sortedRest.join(',')) {
      order = bottom;
    } else {
      order = rest;
    }
    // first in [order] goes to the very bottom first
    for (final c in order) {
      deck.insert(0, c);
    }
    hands[seat] = [keep];
    _log('${name(seat)} 保留一张牌，将 ${order.length} 张牌放回牌库底');
    _priv(seat, '大臣：你保留了 ${_cn(keep)}，放回 ${order.map(_cn).join('、')}');
    phase = 'play';
    _endTurn();
  }

  void _endTurn() {
    final aliveSeats = [for (var i = 0; i < players; i++) if (alive[i]) i];
    if (aliveSeats.length <= 1 || deck.isEmpty) {
      _endRound();
      return;
    }
    _beginTurn(turn + 1);
  }

  void _endRound() {
    final aliveSeats = [for (var i = 0; i < players; i++) if (alive[i]) i];
    List<int> win;
    String why;
    if (aliveSeats.length == 1) {
      win = aliveSeats;
      why = '其他人都已出局';
    } else {
      final best = aliveSeats.map((s) => hands[s].first).reduce((a, b) => a > b ? a : b);
      var cand = aliveSeats.where((s) => hands[s].first == best).toList();
      why = '牌库耗尽，手牌 ${_cn(best)} 最大';
      if (cand.length > 1) {
        int sum(int s) => discards[s].fold(0, (a, b) => a + b);
        final bs = cand.map(sum).reduce((a, b) => a > b ? a : b);
        cand = cand.where((s) => sum(s) == bs).toList();
        why = '牌库耗尽，手牌同为 ${_cn(best)}，弃牌点数和较大';
      }
      win = cand;
    }
    for (final w in win) {
      tokens[w]++;
    }
    final spies = aliveSeats.where((s) => discards[s].contains(0)).toList();
    int spy = -1;
    if (spies.length == 1) {
      spy = spies.first;
      tokens[spy]++;
    }
    _log('本局 ${win.map(name).join('、')} 获胜（$why），获得好感标记');
    if (spy >= 0) _log('${name(spy)} 是唯一打出间谍的存活玩家，额外获得 1 枚好感标记');
    roundResult = {
      'winners': win,
      'why': why,
      'spy': spy,
      'hands': [for (var i = 0; i < players; i++) hands[i].isEmpty ? -1 : hands[i].first],
      'setAside': setAside,
    };
    final champs = [for (var i = 0; i < players; i++) if (tokens[i] >= target) i];
    if (champs.isNotEmpty) {
      winners = champs;
      phase = 'over';
      _log('游戏结束！${champs.map(name).join('、')} 赢得了公主的芳心');
      return;
    }
    phase = 'roundEnd';
    final next = win.first;
    host.schedule(4500, () {
      if (phase == 'roundEnd') _newRound(next);
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final reveal = phase == 'roundEnd' || phase == 'over';
    return {
      'players': players,
      'turn': turn,
      'phase': phase,
      'round': roundNo,
      'target': target,
      'deck': deck.length,
      'setAsideHidden': setAside >= 0,
      'faceUp': faceUp,
      'hand': seat >= 0 && seat < players ? hands[seat] : <int>[],
      'handCounts': [for (final h in hands) h.length],
      'discards': discards,
      'alive': alive,
      'protected': protectedS,
      'tokens': tokens,
      'log': logs.length > 12 ? logs.sublist(logs.length - 12) : logs,
      'priv': seat >= 0 && seat < players ? priv[seat] : <String>[],
      'lastPlay': lastPlay,
      'mustCountess': seat == turn && phase == 'play' && _mustCountess(hands[turn]),
      'roundResult': reveal ? roundResult : null,
      'winners': winners,
      'resigned': [for (final r in resignOrder) r > 0],
      'over': phase == 'over',
    };
  }

  // ---------------- bot ----------------

  /// Cards whose location is unknown to [seat].
  List<int> _unseen(int seat) {
    final cnt = List.of(loveLetterCounts);
    for (final d in discards) {
      for (final c in d) {
        cnt[c]--;
      }
    }
    for (final c in faceUp) {
      cnt[c]--;
    }
    for (final c in hands[seat]) {
      cnt[c]--;
    }
    return [for (var c = 0; c < 10; c++) for (var k = 0; k < cnt[c]; k++) c];
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final hand = hands[seat];
    if (botLevel == 0 && rng.nextDouble() < 0.45) return _randomMove(seat);
    if (phase == 'chancellor') {
      final sorted = List.of(hand)..sort();
      final keep = sorted.contains(9) ? 9 : sorted.last;
      final rest = List.of(hand)..remove(keep);
      return {'type': 'keep', 'card': keep, 'bottom': rest};
    }
    if (_mustCountess(hand)) return {'type': 'play', 'card': 8};
    final unseen = _unseen(seat);
    final others = _targets(seat);
    int pickTarget(bool Function(int)? pref) {
      if (others.isEmpty) return -1;
      if (pref != null) {
        for (final o in others) {
          if (pref(o)) return o;
        }
      }
      final sorted = List.of(others)..sort((a, b) => tokens[b].compareTo(tokens[a]));
      return sorted.first;
    }

    int guessFor(int t) {
      if (t >= 0 && known[seat][t] > 1) return known[seat][t];
      final cnt = List.filled(10, 0);
      for (final c in unseen) {
        cnt[c]++;
      }
      var best = 2;
      var bestScore = -1.0;
      for (var c = 0; c < 10; c++) {
        if (c == 1) continue;
        final sc = cnt[c] + c * 0.01;
        if (sc > bestScore) {
          bestScore = sc;
          best = c;
        }
      }
      return best;
    }

    final hard = botLevel >= 2;
    Map<String, dynamic>? bestA;
    var bestScore = -1e9;
    final avgUnseen = unseen.isEmpty ? 4.0 : unseen.fold(0, (a, b) => a + b) / unseen.length;
    for (final card in hand.toSet()) {
      final keepList = List.of(hand)..remove(card);
      final keep = keepList.first;
      var score = keep * 0.4;
      var t = -1;
      var guess = -1;
      switch (card) {
        case 0:
          score += 2.5;
        case 1:
          t = pickTarget((o) => known[seat][o] > 1);
          guess = guessFor(t);
          score += t >= 0 && known[seat][t] > 1 ? 12 : 2.2;
        case 2:
          t = pickTarget((o) => known[seat][o] < 0);
          score += 1.8;
        case 3:
          t = pickTarget((o) => known[seat][o] >= 0 && known[seat][o] < keep);
          if (t >= 0 && known[seat][t] >= 0) {
            score += known[seat][t] < keep ? 12 : (known[seat][t] > keep ? -12 : -1);
          } else if (hard && unseen.isNotEmpty) {
            // exact odds against a random unseen card
            final win = unseen.where((c) => c < keep).length, lose = unseen.where((c) => c > keep).length;
            score += (win - lose) / unseen.length * 8;
          } else {
            score += (keep - avgUnseen) * 2;
          }
        case 4:
          score += 2.6;
        case 5:
          t = pickTarget((o) => known[seat][o] == 9);
          if (t >= 0 && known[seat][t] == 9) {
            score += 15;
          } else if (t < 0) {
            t = seat;
            score += keep == 9 ? -100 : (keep <= 2 ? 1 : -3);
          } else {
            score += 1.2;
          }
        case 6:
          score += 1.5;
        case 7:
          t = pickTarget(null);
          score += keep <= 3 ? 1.5 : -(keep - 3).toDouble();
        case 8:
          score += 0.5;
        case 9:
          score -= 100;
      }
      if (hard) {
        // an opponent knows the card we'd keep: prefer getting rid of it
        final exposed = [for (var o = 0; o < players; o++) if (o != seat && alive[o] && known[o][seat] >= 0) known[o][seat]];
        if (exposed.contains(card) && card != 9) score += 3;
        if (exposed.contains(keep) && card != 4) score -= 2;
        // late in the round a high kept card wins the showdown
        if (deck.length <= 2) score += keep * 0.5;
      } else {
        score += rng.nextDouble() * 0.3;
      }
      if (score > bestScore) {
        bestScore = score;
        bestA = {'type': 'play', 'card': card, 'target': t, if (card == 1) 'guess': guess};
      }
    }
    return bestA;
  }

  /// 简单难度：随机合法步（尽量不自爆公主）。
  Map<String, dynamic> _randomMove(int seat) {
    final hand = hands[seat];
    if (phase == 'chancellor') {
      final keep = hand[rng.nextInt(hand.length)];
      return {'type': 'keep', 'card': keep, 'bottom': List.of(hand)..remove(keep)};
    }
    if (_mustCountess(hand)) return {'type': 'play', 'card': 8};
    final choices = hand.where((c) => c != 9).toList();
    final card = choices.isEmpty ? hand.first : choices[rng.nextInt(choices.length)];
    var legal = _targets(seat, self: card == 5);
    if (card == 5 && hand.contains(9) && legal.length > 1) legal = legal.where((x) => x != seat).toList();
    final t = legal.isEmpty ? -1 : legal[rng.nextInt(legal.length)];
    const guesses = [0, 2, 3, 4, 5, 6, 7, 8, 9];
    return {'type': 'play', 'card': card, 'target': t, if (card == 1) 'guess': guesses[rng.nextInt(guesses.length)]};
  }
}
