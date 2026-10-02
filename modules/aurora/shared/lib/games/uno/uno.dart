import '../../src/engine.dart';

/// Card face codes: first char = colour, rest = kind.
///   colours: light r y g b / dark p t o v / w = wild (black)
///   kinds: '0'..'9', 'S' skip, 'R' reverse, '+1' '+2' '+4' '+5' '+6' '+10' draw,
///          'F' flip, 'SA' skip everyone, 'DA' discard all of colour,
///          'W' wild, 'R4' wild reverse draw 4, 'C' wild draw colour, 'RL' colour roulette.
const unoLightColors = ['r', 'y', 'g', 'b'];
const unoDarkColors = ['p', 't', 'o', 'v'];
const unoColorNames = {
  'r': '红',
  'y': '黄',
  'g': '绿',
  'b': '蓝',
  'p': '粉',
  't': '青',
  'o': '橙',
  'v': '紫',
  'w': '万能',
};

String unoColor(String f) => f[0];
String unoKind(String f) => f.substring(1);
bool unoIsWild(String f) => f[0] == 'w';
bool unoIsNumber(String f) => RegExp(r'^[0-9]$').hasMatch(unoKind(f));

/// Draw value of a stackable draw card (0 = not a draw card).
int unoDrawValue(String f) {
  final k = unoKind(f);
  if (k == 'R4') return 4;
  if (k.startsWith('+')) return int.parse(k.substring(1));
  return 0;
}

String unoDesc(String f) {
  final c = unoIsWild(f) ? '' : unoColorNames[unoColor(f)] ?? '';
  final k = unoKind(f);
  const names = {
    'S': '禁止',
    'R': '反转',
    'F': '翻转',
    'SA': '全体禁止',
    'DA': '全弃同色',
    'W': '万能牌',
    'R4': '万能反转+4',
    'C': '万能抽色',
    'RL': '颜色轮盘',
  };
  if (unoIsWild(f) && k.startsWith('+')) return '万能$k';
  return '$c${names[k] ?? k}';
}

class UnoCardDef {
  final String light;
  final String? dark;
  const UnoCardDef(this.light, [this.dark]);
}

List<UnoCardDef> buildUnoDeck(String mode, [List<String> Function(List<String>)? shuffleDark]) {
  final out = <UnoCardDef>[];
  void rep(List<String> list, String f, int n) {
    for (var i = 0; i < n; i++) {
      list.add(f);
    }
  }

  if (mode == 'flip') {
    final light = <String>[], dark = <String>[];
    for (final c in unoLightColors) {
      for (var n = 1; n <= 9; n++) {
        rep(light, '$c$n', 2);
      }
      for (final k in ['+1', 'R', 'S', 'F']) {
        rep(light, '$c$k', 2);
      }
    }
    rep(light, 'wW', 4);
    rep(light, 'w+2', 4);
    for (final c in unoDarkColors) {
      for (var n = 1; n <= 9; n++) {
        rep(dark, '$c$n', 2);
      }
      for (final k in ['+5', 'R', 'SA', 'F']) {
        rep(dark, '$c$k', 2);
      }
    }
    rep(dark, 'wW', 4);
    rep(dark, 'wC', 4);
    final d = shuffleDark == null ? dark : shuffleDark(dark);
    for (var i = 0; i < light.length; i++) {
      out.add(UnoCardDef(light[i], d[i]));
    }
    return out;
  }
  final list = <String>[];
  if (mode == 'nomercy') {
    for (final c in unoLightColors) {
      for (var n = 0; n <= 9; n++) {
        rep(list, '$c$n', 2);
      }
      rep(list, '${c}S', 3);
      rep(list, '${c}R', 3);
      rep(list, '$c+2', 3);
      rep(list, '$c+4', 2);
      rep(list, '${c}DA', 3);
      rep(list, '${c}SA', 2);
    }
    rep(list, 'wR4', 8);
    rep(list, 'w+6', 4);
    rep(list, 'w+10', 4);
    rep(list, 'wRL', 8);
  } else {
    for (final c in unoLightColors) {
      list.add('${c}0');
      for (var n = 1; n <= 9; n++) {
        rep(list, '$c$n', 2);
      }
      rep(list, '${c}S', 2);
      rep(list, '${c}R', 2);
      rep(list, '$c+2', 2);
    }
    rep(list, 'wW', 4);
    rep(list, 'w+4', 4);
  }
  for (final f in list) {
    out.add(UnoCardDef(f));
  }
  return out;
}

/// Card points for round scoring.
int unoPoints(String f, String mode, bool dark) {
  if (unoIsNumber(f)) return int.parse(unoKind(f));
  final k = unoKind(f);
  if (mode == 'flip') {
    if (!dark) {
      if (k == '+1') return 10;
      if (k == 'W') return 40;
      if (k == '+2') return 50;
      return 20;
    }
    if (k == 'W') return 40;
    if (k == 'C') return 60;
    if (k == 'SA') return 30;
    return 20;
  }
  return unoIsWild(f) ? 50 : 20;
}

class UnoGame extends GameEngine {
  UnoGame(super.setup);

  late final String mode = setup.opt<String>('mode', 'classic');
  late final bool stacking = mode == 'nomercy' || setup.opt<bool>('stack', false);
  late final int target = mode == 'nomercy' ? 0 : setup.opt<int>('target', 0);
  bool get nm => mode == 'nomercy';
  bool get flip => mode == 'flip';

  late List<UnoCardDef> deck;
  List<List<int>> hands = [];
  List<int> drawPile = [];
  List<int> discard = [];
  bool dark = false;
  int dir = 1;
  int turn = 0;
  int starter = 0;
  String phase = 'play'; // play / drawn / roulette / roundEnd / over
  String? curColor;
  int pending = 0;
  int pendingMin = 0;
  bool pendingColor = false;
  int challengeFrom = -1;
  bool challengeGuilty = false;
  String challengeCard = '';
  int drawnId = -1;
  int vulnerable = -1;
  List<bool> unoCalled = [];
  List<bool> out = [];
  List<int> scores = [];
  int winner = -1;
  int resigned = -1;
  List<int> outOrder = []; // NO MERCY eliminations, in order
  int roundWinner = -1;
  int round = 0;
  int stall = 0;
  String last = '';
  List<Map<String, dynamic>> roundResult = [];

  List<String> get colors => dark ? unoDarkColors : unoLightColors;
  String face(int id) => dark ? deck[id].dark! : deck[id].light;
  String? backFace(int id) => !flip ? null : (dark ? deck[id].light : deck[id].dark);
  String get top => face(discard.last);
  int get activeCount => out.where((o) => !o).length;

  @override
  void start() {
    scores = List.filled(players, 0);
    out = List.filled(players, false);
    starter = rng.nextInt(players);
    _newRound();
  }

  void _newRound() {
    round++;
    deck = buildUnoDeck(mode, (l) => shuffled(l, rng));
    dark = false;
    dir = 1;
    hands = [for (var i = 0; i < players; i++) <int>[]];
    unoCalled = List.filled(players, false);
    drawPile = shuffled(List.generate(deck.length, (i) => i), rng);
    discard = [];
    for (var r = 0; r < 7; r++) {
      for (var s = 0; s < players; s++) {
        hands[s].add(drawPile.removeLast());
      }
    }
    // Starting card: first number card (simplification: action cards are buried).
    while (true) {
      final c = drawPile.removeLast();
      if (unoIsNumber(face(c))) {
        discard.add(c);
        break;
      }
      drawPile.insert(0, c);
    }
    curColor = unoColor(top);
    pending = 0;
    pendingMin = 0;
    pendingColor = false;
    challengeFrom = -1;
    drawnId = -1;
    vulnerable = -1;
    stall = 0;
    roundWinner = -1;
    roundResult = [];
    turn = starter;
    starter = (starter + 1) % players;
    phase = 'play';
    last = '第 $round 局开始，起始牌 ${unoDesc(top)}';
    host.log('UNO 第 $round 局开始，${name(turn)} 先出');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (phase != 'over') return null;
    if (resigned >= 0) return rankWinners(players, [winner]);
    if (target > 0) {
      // 多局累计：分数高者名次高；最终胜者一定第一
      return rankByScore([for (var s = 0; s < players; s++) s == winner ? scores[s] + 1000000 : scores[s]]);
    }
    // 单局：胜者第一，其余按剩余手牌（NO MERCY 按张数，否则按点数）从少到多；
    // NO MERCY 被淘汰者排在最后，越晚淘汰名次越好。
    final keys = <num>[];
    for (var s = 0; s < players; s++) {
      if (s == winner) {
        keys.add(-1);
      } else if (out[s]) {
        keys.add(100000 + (players - outOrder.indexOf(s)));
      } else {
        keys.add(nm ? hands[s].length : hands[s].fold<int>(0, (a, c) => a + unoPoints(face(c), mode, dark)));
      }
    }
    return rankByScore(keys, lowWins: true);
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    winner = 1 - seat;
    roundWinner = winner;
    vulnerable = -1;
    phase = 'over';
    last = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log('${name(seat)} 认输');
  }

  @override
  List<int> get waitingFor => (phase == 'over' || phase == 'roundEnd') ? const [] : [turn];

  int nextActive(int s) {
    var t = s;
    for (var i = 0; i < players; i++) {
      t = (t + dir + players) % players;
      if (!out[t]) return t;
    }
    return s;
  }

  void advance(int k) {
    for (var i = 0; i < k; i++) {
      turn = nextActive(turn);
    }
    if (out[turn]) turn = nextActive(turn);
    phase = 'play';
    drawnId = -1;
  }

  bool canPlay(String f) {
    if (pendingColor) return false;
    if (pending > 0) {
      final v = unoDrawValue(f);
      return stacking && v > 0 && v >= pendingMin;
    }
    if (unoIsWild(f) || curColor == null) return true;
    if (unoColor(f) == curColor) return true;
    final t = top;
    return !unoIsWild(t) && unoKind(t) == unoKind(f);
  }

  List<int> playableFor(int seat) {
    if (seat != turn) return const [];
    if (phase == 'drawn') return [drawnId];
    if (phase != 'play') return const [];
    return [for (final c in hands[seat]) if (canPlay(face(c))) c];
  }

  int? _takeTop() {
    if (drawPile.isEmpty) {
      if (discard.length <= 1) return null;
      final topCard = discard.removeLast();
      drawPile = shuffled(discard, rng);
      discard = [topCard];
      host.log('摸牌堆已空，重新洗牌');
    }
    return drawPile.isEmpty ? null : drawPile.removeLast();
  }

  /// Returns number of cards drawn. Applies the Mercy rule.
  int drawCards(int seat, int n) {
    var got = 0;
    for (var i = 0; i < n; i++) {
      final c = _takeTop();
      if (c == null) break;
      hands[seat].add(c);
      got++;
    }
    _afterDraw(seat);
    return got;
  }

  int drawUntilColor(int seat, String? color, [int extra = 0]) {
    var got = 0;
    while (true) {
      final c = _takeTop();
      if (c == null) break;
      hands[seat].add(c);
      got++;
      if (color == null || unoColor(face(c)) == color) break;
    }
    return got + drawCards(seat, extra);
  }

  void _afterDraw(int seat) {
    if (hands[seat].length > 1) unoCalled[seat] = false;
    if (vulnerable == seat && hands[seat].length != 1) vulnerable = -1;
    if (nm && !out[seat] && hands[seat].length >= 25) {
      out[seat] = true;
      outOrder.add(seat);
      drawPile.addAll(hands[seat]);
      drawPile.shuffle(rng);
      hands[seat].clear();
      host.log('${name(seat)} 手牌达到 25 张，被仁慈规则淘汰！');
      last = '${name(seat)} 手牌达到 25 张，被淘汰';
      if (activeCount == 1) {
        _endGameNm(out.indexOf(false));
      }
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    final t = asStr(a['type']);
    if (t == 'catch') return _catch(seat);
    if (t == 'uno') return _callUno(seat);
    if (phase == 'roundEnd') throw GameError('本局已结束，请稍候');
    if (seat != turn) throw GameError('还没轮到你');
    final prevVul = vulnerable;
    vulnerable = -1;
    try {
      _act(seat, t, a);
    } on GameError {
      vulnerable = prevVul;
      rethrow;
    }
  }

  void _catch(int seat) {
    if (seat < 0 || seat >= players || out[seat]) throw GameError('无法抓 UNO');
    if (vulnerable < 0 || vulnerable == seat || hands[vulnerable].length != 1) {
      throw GameError('现在没有可以抓的人');
    }
    final v = vulnerable;
    vulnerable = -1;
    drawCards(v, 2);
    if (phase == 'over') return;
    last = '${name(seat)} 抓到 ${name(v)} 没喊 UNO，罚摸 2 张';
    host.log(last);
    if (out[turn]) advance(1);
  }

  void _callUno(int seat) {
    if (seat != vulnerable) throw GameError('现在不需要喊 UNO');
    vulnerable = -1;
    unoCalled[seat] = true;
    last = '${name(seat)} 喊出 UNO！';
    host.log(last);
  }

  void _act(int seat, String t, Map<String, dynamic> a) {
    final hand = hands[seat];
    if (phase == 'roulette') {
      if (t != 'roulette') throw GameError('请选择轮盘颜色');
      final c = asStr(a['color']);
      if (!colors.contains(c)) throw GameError('无效颜色');
      final n = drawUntilColor(seat, c);
      curColor = c;
      last = '${name(seat)} 颜色轮盘选 ${unoColorNames[c]}，翻出 $n 张全部收下';
      host.log(last);
      if (phase == 'over') return;
      advance(1);
      return;
    }
    if (phase == 'drawn') {
      if (t == 'pass') {
        last = '${name(seat)} 摸牌后不出';
        advance(1);
        return;
      }
      if (t != 'play' || asInt(a['card']) != drawnId) throw GameError('只能打出刚摸到的牌或选择不出');
      _playCard(seat, drawnId, a);
      return;
    }
    // phase play
    switch (t) {
      case 'play':
        final id = asInt(a['card']);
        if (!hand.contains(id)) throw GameError('你没有这张牌');
        if (!canPlay(face(id))) {
          throw GameError(pending > 0 || pendingColor ? '只能叠加同等或更大的加牌，或接受罚牌' : '这张牌不能出');
        }
        _playCard(seat, id, a);
        return;
      case 'draw':
        if (pending > 0 || pendingColor) {
          final n = pending;
          final col = pendingColor;
          pending = 0;
          pendingMin = 0;
          pendingColor = false;
          challengeFrom = -1;
          final got = col ? drawUntilColor(seat, curColor) : drawCards(seat, n);
          last = '${name(seat)} 被罚摸 $got 张';
          host.log(last);
          if (phase == 'over') return;
          advance(1);
          return;
        }
        if (nm) {
          var got = 0;
          while (true) {
            final c = _takeTop();
            if (c == null) break;
            hand.add(c);
            got++;
            _afterDraw(seat);
            if (phase == 'over') return;
            if (out[seat]) {
              advance(1);
              return;
            }
            if (canPlay(face(c))) {
              drawnId = c;
              phase = 'drawn';
              last = '${name(seat)} 连摸 $got 张';
              return;
            }
          }
          last = '${name(seat)} 摸了 $got 张，无牌可出';
          if (got == 0) stall++;
          _checkStall();
          if (phase == 'roundEnd' || phase == 'over') return;
          advance(1);
          return;
        }
        final c = _takeTop();
        if (c == null) {
          stall++;
          last = '${name(seat)} 无牌可摸，跳过';
          _checkStall();
          if (phase == 'roundEnd' || phase == 'over') return;
          advance(1);
          return;
        }
        hand.add(c);
        _afterDraw(seat);
        if (canPlay(face(c))) {
          drawnId = c;
          phase = 'drawn';
          last = '${name(seat)} 摸了 1 张';
        } else {
          last = '${name(seat)} 摸了 1 张，不能出';
          advance(1);
        }
        return;
      case 'challenge':
        if (challengeFrom < 0 || pending == 0 && !pendingColor) throw GameError('现在不能质疑');
        _challenge(seat);
        return;
      default:
        throw GameError('未知操作');
    }
  }

  void _challenge(int seat) {
    final off = challengeFrom;
    final k = unoKind(challengeCard);
    pending = 0;
    pendingMin = 0;
    pendingColor = false;
    challengeFrom = -1;
    if (challengeGuilty) {
      final n = k == 'C' ? drawUntilColor(off, curColor) : drawCards(off, k == '+2' ? 2 : 4);
      last = '${name(seat)} 质疑成功！${name(off)} 手里有同色牌，罚摸 $n 张';
      host.log(last);
      if (phase == 'over') return;
      phase = 'play'; // challenger plays normally
    } else {
      final n = k == 'C' ? drawUntilColor(seat, curColor, 2) : drawCards(seat, k == '+2' ? 4 : 6);
      last = '${name(seat)} 质疑失败，罚摸 $n 张';
      host.log(last);
      if (phase == 'over') return;
      advance(1);
    }
  }

  void _checkStall() {
    if (stall >= activeCount * 2) {
      // Nobody can play and nothing to draw: lowest hand wins.
      var best = -1, bestPts = 1 << 30;
      for (var s = 0; s < players; s++) {
        if (out[s]) continue;
        final p = nm ? hands[s].length : hands[s].fold<int>(0, (a, c) => a + unoPoints(face(c), mode, dark));
        if (p < bestPts) {
          bestPts = p;
          best = s;
        }
      }
      host.log('无人能出牌且牌堆耗尽，手牌最少者获胜');
      _roundWon(best);
    }
  }

  void _playCard(int seat, int id, Map<String, dynamic> a) {
    final f = face(id);
    final hand = hands[seat];
    final k = unoKind(f);
    String? chosen;
    if (unoIsWild(f) && k != 'RL') {
      chosen = asStr(a['color']);
      if (!colors.contains(chosen)) throw GameError('请选择颜色');
    }
    var tgt = -1;
    final willEmpty = hand.length == 1 || (k == 'DA' && hand.every((c) => unoColor(face(c)) == unoColor(f)));
    if (nm && k == '7' && !willEmpty) {
      tgt = asInt(a['target']);
      if (activeCount == 2 && (tgt < 0 || tgt == seat)) tgt = nextActive(seat);
      if (tgt < 0 || tgt >= players || tgt == seat || out[tgt]) throw GameError('请选择要交换手牌的玩家');
    }
    final prevColor = curColor;
    hand.remove(id);
    final guilty = prevColor != null && hand.any((c) => unoColor(face(c)) == prevColor);
    discard.add(id);
    stall = 0;
    drawnId = -1;
    curColor = unoIsWild(f) ? chosen : unoColor(f);
    last = '${name(seat)} 打出 ${unoDesc(f)}${chosen != null ? '，指定${unoColorNames[chosen]}色' : ''}';
    if (k == 'DA') {
      final same = [for (final c in hand) if (unoColor(face(c)) == unoColor(f)) c];
      hand.removeWhere(same.contains);
      discard.insertAll(discard.length - 1, same);
      if (same.isNotEmpty) last += '，并弃掉 ${same.length} 张同色牌';
    }
    if (hand.length == 1) {
      if (asBool(a['uno'])) {
        unoCalled[seat] = true;
        host.log('${name(seat)} 喊出 UNO！');
        last += '（UNO！）';
      } else {
        unoCalled[seat] = false;
        vulnerable = seat;
      }
    } else {
      unoCalled[seat] = false;
    }
    if (hand.isEmpty) {
      if (!nm) {
        final v = unoDrawValue(f);
        final nx = nextActive(seat);
        if (v > 0) drawCards(nx, pending + v);
        if (k == 'C') drawUntilColor(nx, curColor);
      }
      pending = 0;
      pendingColor = false;
      _roundWon(seat);
      return;
    }
    if (nm && k == '7') {
      final tmp = hands[seat];
      hands[seat] = hands[tgt];
      hands[tgt] = tmp;
      last += '，与 ${name(tgt)} 交换手牌';
      _resetUnoFlags();
    } else if (nm && k == '0') {
      final act = [for (var i = 0; i < players; i++) if (!out[i]) i];
      final old = [for (final s in act) hands[s]];
      for (var i = 0; i < act.length; i++) {
        // each player passes hand to the next player in direction
        final to = (i + dir + act.length) % act.length;
        hands[act[to]] = old[i];
      }
      last += '，所有人按方向传递手牌';
      _resetUnoFlags();
    }
    final v = unoDrawValue(f);
    if (k == 'S') {
      advance(2);
    } else if (k == 'R') {
      if (activeCount == 2) {
        advance(2);
      } else {
        dir = -dir;
        advance(1);
      }
    } else if (k == 'SA') {
      advance(0);
    } else if (k == 'F') {
      _flipAll();
      last += '，全场翻面！';
      advance(1);
    } else if (v > 0) {
      if (k == 'R4') dir = -dir;
      final first = pending == 0;
      pending += v;
      pendingMin = v;
      final chal = first && ((mode == 'classic' && f == 'w+4') || (flip && f == 'w+2'));
      challengeFrom = chal ? seat : -1;
      challengeGuilty = guilty;
      challengeCard = f;
      advance(1);
      if (!stacking && !chal) {
        final victim = turn;
        final n = pending;
        pending = 0;
        pendingMin = 0;
        drawCards(victim, n);
        last += '，${name(victim)} 摸 $n 张并跳过';
        advance(1);
      }
    } else if (k == 'C') {
      pendingColor = true;
      challengeFrom = seat;
      challengeGuilty = guilty;
      challengeCard = f;
      advance(1);
    } else if (k == 'RL') {
      advance(1);
      phase = 'roulette';
    } else {
      advance(1);
    }
    host.log(last);
  }

  void _resetUnoFlags() {
    vulnerable = -1;
    for (var s = 0; s < players; s++) {
      unoCalled[s] = hands[s].length == 1;
    }
  }

  void _flipAll() {
    dark = !dark;
    drawPile = drawPile.reversed.toList();
    final t = top;
    curColor = unoIsWild(t) ? null : unoColor(t);
  }

  void _roundWon(int w) {
    if (nm) {
      _endGameNm(w);
      return;
    }
    var pts = 0;
    roundResult = [];
    for (var s = 0; s < players; s++) {
      final p = hands[s].fold<int>(0, (a, c) => a + unoPoints(face(c), mode, dark));
      if (s != w) pts += p;
      roundResult.add({'seat': s, 'cards': [for (final c in hands[s]) face(c)], 'points': p});
    }
    scores[w] += pts;
    roundWinner = w;
    vulnerable = -1;
    host.log('${name(w)} 赢得第 $round 局，得 $pts 分');
    last = '${name(w)} 赢得本局，得 $pts 分';
    if (target <= 0 || scores[w] >= target) {
      winner = w;
      phase = 'over';
      host.log('${name(w)} 获得最终胜利！');
    } else {
      phase = 'roundEnd';
      host.schedule(4000, () {
        if (phase == 'roundEnd') _newRound();
      });
    }
  }

  void _endGameNm(int w) {
    winner = w;
    roundWinner = w;
    phase = 'over';
    vulnerable = -1;
    roundResult = [
      for (var s = 0; s < players; s++)
        {'seat': s, 'cards': [for (final c in hands[s]) face(c)], 'points': hands[s].length, 'out': out[s]}
    ];
    last = '${name(w)} 获胜！';
    host.log('${name(w)} 获得 NO MERCY 胜利！');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'mode': mode,
      'stacking': stacking,
      'target': target,
      'round': round,
      'dark': dark,
      'dir': dir,
      'turn': turn,
      'phase': phase,
      'color': curColor,
      'top': discard.isEmpty ? null : top,
      'discardCount': discard.length,
      'drawCount': drawPile.length,
      'drawBack': flip && drawPile.isNotEmpty ? backFace(drawPile.last) : null,
      'pending': pending,
      'pendingColor': pendingColor,
      'challengeFrom': (pending > 0 || pendingColor) ? challengeFrom : -1,
      'vulnerable': vulnerable,
      'last': last,
      'winner': winner,
      'roundWinner': roundWinner,
      'over': phase == 'over',
      'players': [
        for (var s = 0; s < players; s++)
          {
            'count': hands[s].length,
            'score': scores[s],
            'out': out[s],
            'uno': unoCalled[s] && hands[s].length == 1,
            if (flip && s != seat) 'backs': [for (final c in hands[s]) backFace(c)],
          }
      ],
      'hand': me ? [for (final c in hands[seat]) {'id': c, 'f': face(c)}] : [],
      'playable': me ? playableFor(seat) : [],
      'drawn': me && seat == turn ? drawnId : -1,
      'result': (phase == 'roundEnd' || phase == 'over') ? roundResult : [],
    };
  }

  // ---------------- bot ----------------

  String _bestColor(int seat, [int? exclude]) {
    final cnt = {for (final c in colors) c: 0};
    for (final c in hands[seat]) {
      if (c == exclude) continue;
      final col = unoColor(face(c));
      if (cnt.containsKey(col)) cnt[col] = cnt[col]! + 1;
    }
    var best = colors[rng.nextInt(colors.length)];
    for (final e in cnt.entries) {
      if (e.value > cnt[best]!) best = e.key;
    }
    return best;
  }

  Map<String, dynamic> _playAction(int seat, int id) {
    final f = face(id);
    final easy = botLevel == 0;
    // 简单电脑偶尔忘记喊 UNO、随便选颜色
    final a = <String, dynamic>{'type': 'play', 'card': id, 'uno': !easy || rng.nextDouble() < 0.6};
    if (unoIsWild(f) && unoKind(f) != 'RL') {
      a['color'] = easy && rng.nextBool() ? colors[rng.nextInt(colors.length)] : _bestColor(seat, id);
    }
    if (nm && unoKind(f) == '7') {
      var best = -1;
      for (var s = 0; s < players; s++) {
        if (s == seat || out[s]) continue;
        if (best < 0 || hands[s].length < hands[best].length) best = s;
      }
      a['target'] = best;
    }
    return a;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'over' || phase == 'roundEnd' || seat != turn) return null;
    final lvl = botLevel;
    final catchP = lvl == 0 ? 0.2 : (lvl == 2 ? 1.0 : 0.7);
    if (vulnerable >= 0 && vulnerable != seat && hands[vulnerable].length == 1 && rng.nextDouble() < catchP) {
      return {'type': 'catch'};
    }
    if (phase == 'roulette') {
      return {'type': 'roulette', 'color': lvl == 0 ? colors[rng.nextInt(colors.length)] : _bestColor(seat)};
    }
    if (phase == 'drawn') {
      return canPlay(face(drawnId)) ? _playAction(seat, drawnId) : {'type': 'pass'};
    }
    final pl = playableFor(seat);
    if (lvl == 0 && pl.isNotEmpty && rng.nextDouble() < 0.5) {
      // 简单：一半概率随便出一张能出的牌
      return _playAction(seat, pl[rng.nextInt(pl.length)]);
    }
    if (lvl == 2) {
      final h = _hardPlay(seat, pl);
      if (h != null) return h;
    }
    if (pending > 0 || pendingColor) {
      if (pl.isNotEmpty) {
        pl.sort((x, y) => unoDrawValue(face(x)).compareTo(unoDrawValue(face(y))));
        return _playAction(seat, pl.first);
      }
      if (challengeFrom >= 0 && rng.nextDouble() < 0.3) return {'type': 'challenge'};
      return {'type': 'draw'};
    }
    if (pl.isEmpty) return {'type': 'draw'};
    int rank(int c) {
      final f = face(c);
      final k = unoKind(f);
      if (unoIsWild(f)) return 0;
      if (k == 'DA') {
        return 3 + hands[seat].where((x) => unoColor(face(x)) == unoColor(f)).length;
      }
      if (unoIsNumber(f)) return 2;
      return 3;
    }

    pl.shuffle(rng);
    pl.sort((x, y) => rank(y).compareTo(rank(x)));
    return _playAction(seat, pl.first);
  }

  /// 困难：保留万能牌、下家快出完时优先攻击、同色长的优先、质疑更有依据。
  Map<String, dynamic>? _hardPlay(int seat, List<int> pl) {
    final hand = hands[seat];
    final nx = nextActive(seat);
    final nxCount = hands[nx].length;
    if (pending > 0 || pendingColor) {
      if (pl.isNotEmpty) {
        pl.sort((x, y) => unoDrawValue(face(x)).compareTo(unoDrawValue(face(y))));
        return _playAction(seat, pl.first);
      }
      // 只根据公开信息质疑：质疑方刚出牌前手上的牌多 → 更可能有同色牌
      if (challengeFrom >= 0) {
        final n = hands[challengeFrom].length;
        if (n >= 5 && rng.nextDouble() < 0.5) return {'type': 'challenge'};
      }
      return {'type': 'draw'};
    }
    if (pl.isEmpty) return {'type': 'draw'};
    final colorCount = <String, int>{};
    for (final c in hand) {
      final col = unoColor(face(c));
      colorCount[col] = (colorCount[col] ?? 0) + 1;
    }
    double score(int c) {
      final f = face(c);
      final k = unoKind(f);
      var v = 0.0;
      final attack = unoDrawValue(f) > 0 || k == 'S' || k == 'SA' || k == 'C' || (k == 'R' && activeCount == 2);
      if (unoIsWild(f)) {
        // 万能牌留到关键时刻
        v -= hand.length > 2 ? 30 : 0;
        if (attack && nxCount <= 2) v += 60;
      } else {
        v += (colorCount[unoColor(f)] ?? 0) * 3;
        if (unoIsNumber(f)) v += int.parse(k) * 0.5; // 先丢大点数
        if (attack) v += nxCount <= 2 ? 40 : -4; // 攻击留给快出完的下家
        if (k == 'DA') v += 4 * (colorCount[unoColor(f)] ?? 0);
      }
      if (nm && k == '7') {
        var minCnt = 999;
        for (var s = 0; s < players; s++) {
          if (s != seat && !out[s] && hands[s].length < minCnt) minCnt = hands[s].length;
        }
        v += minCnt < hand.length - 1 ? 25 : -25;
      }
      return v + rng.nextDouble();
    }

    pl.sort((x, y) => score(y).compareTo(score(x)));
    return _playAction(seat, pl.first);
  }
}
