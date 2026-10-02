import '../../src/engine.dart';

/// 璀璨宝石 (Splendor). Colour indices: 0 白 1 蓝 2 绿 3 红 4 黑, 5 = 黄金.
const splendorColorNames = ['白', '蓝', '绿', '红', '黑', '黄金'];

class SplendorCard {
  final int id;
  final int tier; // 0..2
  final int color;
  final int points;
  final List<int> cost; // 5
  const SplendorCard(this.id, this.tier, this.color, this.points, this.cost);
  Map<String, dynamic> toJson() => {'id': id, 'tier': tier, 'color': color, 'points': points, 'cost': cost};
}

class SplendorNoble {
  final int id;
  final List<int> req;
  const SplendorNoble(this.id, this.req);
  Map<String, dynamic> toJson() => {'id': id, 'req': req, 'points': 3};
}

// tier, color, points, w, u, g, r, k
const List<List<int>> _cardData = [
  // ---- tier 1 ----
  // black
  [0, 4, 0, 1, 1, 1, 1, 0], [0, 4, 0, 1, 2, 1, 1, 0], [0, 4, 0, 2, 2, 0, 1, 0], [0, 4, 0, 0, 0, 1, 3, 1],
  [0, 4, 0, 0, 0, 2, 1, 0], [0, 4, 0, 2, 0, 2, 0, 0], [0, 4, 0, 0, 0, 3, 0, 0], [0, 4, 1, 0, 4, 0, 0, 0],
  // blue
  [0, 1, 0, 1, 0, 1, 1, 1], [0, 1, 0, 1, 0, 1, 2, 1], [0, 1, 0, 1, 0, 2, 2, 0], [0, 1, 0, 0, 1, 3, 1, 0],
  [0, 1, 0, 1, 0, 0, 0, 2], [0, 1, 0, 0, 0, 2, 0, 2], [0, 1, 0, 0, 0, 0, 0, 3], [0, 1, 1, 0, 0, 0, 4, 0],
  // white
  [0, 0, 0, 0, 1, 1, 1, 1], [0, 0, 0, 0, 1, 2, 1, 1], [0, 0, 0, 0, 2, 2, 0, 1], [0, 0, 0, 3, 1, 0, 0, 1],
  [0, 0, 0, 0, 0, 0, 2, 1], [0, 0, 0, 0, 2, 0, 0, 2], [0, 0, 0, 0, 3, 0, 0, 0], [0, 0, 1, 0, 0, 4, 0, 0],
  // green
  [0, 2, 0, 1, 1, 0, 1, 1], [0, 2, 0, 1, 1, 0, 1, 2], [0, 2, 0, 0, 1, 0, 2, 2], [0, 2, 0, 1, 3, 1, 0, 0],
  [0, 2, 0, 2, 1, 0, 0, 0], [0, 2, 0, 0, 2, 0, 2, 0], [0, 2, 0, 0, 0, 0, 3, 0], [0, 2, 1, 0, 0, 0, 0, 4],
  // red
  [0, 3, 0, 1, 1, 1, 0, 1], [0, 3, 0, 2, 1, 1, 0, 1], [0, 3, 0, 2, 0, 1, 0, 2], [0, 3, 0, 1, 0, 0, 1, 3],
  [0, 3, 0, 0, 2, 1, 0, 0], [0, 3, 0, 2, 0, 0, 2, 0], [0, 3, 0, 3, 0, 0, 0, 0], [0, 3, 1, 4, 0, 0, 0, 0],
  // ---- tier 2 ----
  // black
  [1, 4, 1, 3, 2, 2, 0, 0], [1, 4, 1, 3, 0, 3, 0, 2], [1, 4, 2, 0, 1, 4, 2, 0], [1, 4, 2, 0, 0, 5, 3, 0],
  [1, 4, 2, 5, 0, 0, 0, 0], [1, 4, 3, 0, 0, 0, 0, 6],
  // blue
  [1, 1, 1, 0, 2, 2, 3, 0], [1, 1, 1, 0, 2, 3, 0, 3], [1, 1, 2, 5, 3, 0, 0, 0], [1, 1, 2, 2, 0, 0, 1, 4],
  [1, 1, 2, 0, 5, 0, 0, 0], [1, 1, 3, 0, 6, 0, 0, 0],
  // white
  [1, 0, 1, 0, 0, 3, 2, 2], [1, 0, 1, 2, 3, 0, 3, 0], [1, 0, 2, 0, 0, 1, 4, 2], [1, 0, 2, 0, 0, 0, 5, 3],
  [1, 0, 2, 0, 0, 0, 5, 0], [1, 0, 3, 6, 0, 0, 0, 0],
  // green
  [1, 2, 1, 3, 0, 2, 3, 0], [1, 2, 1, 2, 3, 0, 0, 2], [1, 2, 2, 4, 2, 0, 0, 1], [1, 2, 2, 0, 5, 3, 0, 0],
  [1, 2, 2, 0, 0, 5, 0, 0], [1, 2, 3, 0, 0, 6, 0, 0],
  // red
  [1, 3, 1, 2, 0, 0, 2, 3], [1, 3, 1, 0, 3, 0, 2, 3], [1, 3, 2, 1, 4, 2, 0, 0], [1, 3, 2, 3, 0, 0, 0, 5],
  [1, 3, 2, 0, 0, 0, 0, 5], [1, 3, 3, 0, 0, 0, 6, 0],
  // ---- tier 3 ----
  [2, 4, 3, 3, 3, 5, 3, 0], [2, 4, 4, 0, 0, 0, 7, 0], [2, 4, 4, 0, 0, 3, 6, 3], [2, 4, 5, 0, 0, 0, 7, 3],
  [2, 1, 3, 3, 0, 3, 3, 5], [2, 1, 4, 7, 0, 0, 0, 0], [2, 1, 4, 6, 3, 0, 0, 3], [2, 1, 5, 7, 3, 0, 0, 0],
  [2, 0, 3, 0, 3, 3, 5, 3], [2, 0, 4, 0, 0, 0, 0, 7], [2, 0, 4, 3, 0, 0, 3, 6], [2, 0, 5, 3, 0, 0, 0, 7],
  [2, 2, 3, 5, 3, 0, 3, 3], [2, 2, 4, 0, 7, 0, 0, 0], [2, 2, 4, 3, 6, 3, 0, 0], [2, 2, 5, 0, 7, 3, 0, 0],
  [2, 3, 3, 3, 5, 3, 0, 3], [2, 3, 4, 0, 0, 7, 0, 0], [2, 3, 4, 0, 3, 6, 3, 0], [2, 3, 5, 0, 0, 7, 3, 0],
];

final List<SplendorCard> splendorCards = [
  for (var i = 0; i < _cardData.length; i++)
    SplendorCard(i, _cardData[i][0], _cardData[i][1], _cardData[i][2], _cardData[i].sublist(3)),
];

const List<SplendorNoble> splendorNobles = [
  SplendorNoble(0, [0, 0, 4, 4, 0]),
  SplendorNoble(1, [0, 4, 4, 0, 0]),
  SplendorNoble(2, [4, 4, 0, 0, 0]),
  SplendorNoble(3, [4, 0, 0, 0, 4]),
  SplendorNoble(4, [0, 0, 0, 4, 4]),
  SplendorNoble(5, [3, 3, 0, 0, 3]),
  SplendorNoble(6, [0, 3, 3, 3, 0]),
  SplendorNoble(7, [3, 3, 3, 0, 0]),
  SplendorNoble(8, [0, 0, 3, 3, 3]),
  SplendorNoble(9, [3, 0, 0, 3, 3]),
];

class SplendorPlayer {
  final List<int> tokens = List.filled(6, 0);
  final List<int> bonus = List.filled(5, 0);
  final List<int> bought = [];
  final List<int> reserved = [];
  final Set<int> reservedPublic = {};
  final List<int> nobles = [];
  int get points =>
      bought.fold(0, (a, c) => a + splendorCards[c].points) + nobles.length * 3;
  int get tokenCount => tokens.fold(0, (a, b) => a + b);
}

/// Gold needed to buy [card] with [tokens] and [bonus] (0 = affordable w/o gold).
int splendorShortfall(SplendorCard card, List<int> tokens, List<int> bonus) {
  var need = 0;
  for (var c = 0; c < 5; c++) {
    final r = card.cost[c] - bonus[c] - tokens[c];
    if (r > 0) need += r;
  }
  return need;
}

bool splendorCanAfford(SplendorCard card, List<int> tokens, List<int> bonus) =>
    splendorShortfall(card, tokens, bonus) <= tokens[5];

/// Payment (6 entries) to buy [card]; coloured gems first, then gold.
List<int> splendorPayment(SplendorCard card, List<int> tokens, List<int> bonus) {
  final pay = List.filled(6, 0);
  for (var c = 0; c < 5; c++) {
    final need = card.cost[c] - bonus[c];
    if (need <= 0) continue;
    final use = need < tokens[c] ? need : tokens[c];
    pay[c] = use;
    pay[5] += need - use;
  }
  return pay;
}

class Splendor extends GameEngine {
  Splendor(super.setup);

  final List<int> supply = List.filled(6, 0);
  final List<List<int>> decks = [[], [], []];
  final List<List<int>> board = [[], [], []];
  List<int> nobles = [];
  late final List<SplendorPlayer> ps = [for (var i = 0; i < players; i++) SplendorPlayer()];
  int turn = 0;
  int first = 0;
  String phase = 'main'; // main / return / noble / over
  List<int> nobleChoices = [];
  bool finalRound = false;
  int passStreak = 0;
  List<int> winners = [];
  String last = '';
  Map<String, dynamic>? lastAct;

  /// 认输顺序：resignOrder[s] = 第几个认输（从 1 开始），0 = 未认输。
  late List<int> resignOrder = List.filled(players, 0);
  int _resigns = 0;
  bool _active(int s) => resignOrder[s] == 0;
  int get _activeCount => resignOrder.where((r) => r == 0).length;

  @override
  void start() {
    final n = players == 2 ? 4 : (players == 3 ? 5 : 7);
    for (var c = 0; c < 5; c++) {
      supply[c] = n;
    }
    supply[5] = 5;
    for (final c in splendorCards) {
      decks[c.tier].add(c.id);
    }
    for (var t = 0; t < 3; t++) {
      decks[t].shuffle(rng);
      for (var i = 0; i < 4; i++) {
        board[t].add(decks[t].removeLast());
      }
    }
    nobles = (List.generate(10, (i) => i)..shuffle(rng)).sublist(0, players + 1);
    first = rng.nextInt(players);
    turn = first;
    host.log('璀璨宝石开始！${name(turn)} 先手，率先达到 15 分的回合结束后结算');
  }

  @override
  bool get isOver => phase == 'over';

  int _rankKey(int s) => _active(s) ? ps[s].points * 100 - ps[s].bought.length : -100000 + resignOrder[s];

  @override
  List<int>? get placings => isOver ? rankByScore([for (var s = 0; s < players; s++) _rankKey(s)]) : null;

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    if (!_active(seat)) throw GameError('你已经认输了');
    resignOrder[seat] = ++_resigns;
    final p = ps[seat];
    for (var c = 0; c < 6; c++) {
      supply[c] += p.tokens[c];
      p.tokens[c] = 0;
    }
    host.log('${name(seat)} 认输，退回所有宝石');
    if (_activeCount <= 1) {
      _finish();
      return;
    }
    if (seat == turn) {
      phase = 'main';
      nobleChoices = [];
      _advance();
    }
  }

  @override
  List<int> get waitingFor => phase == 'over' ? const [] : [turn];

  SplendorCard _card(int id) => splendorCards[id];

  (int, int)? _findOnBoard(int id) {
    for (var t = 0; t < 3; t++) {
      final i = board[t].indexOf(id);
      if (i >= 0) return (t, i);
    }
    return null;
  }

  void _refill(int t, int i) {
    if (decks[t].isNotEmpty) {
      board[t][i] = decks[t].removeLast();
    } else {
      board[t][i] = -1;
    }
  }

  bool _canAnything(int seat) {
    final p = ps[seat];
    if (supply.sublist(0, 5).any((x) => x > 0)) return true;
    if (p.reserved.length < 3 && (board.any((r) => r.any((c) => c >= 0)) || decks.any((d) => d.isNotEmpty))) {
      return true;
    }
    for (final id in [...p.reserved, for (final r in board) ...r.where((c) => c >= 0)]) {
      if (splendorCanAfford(_card(id), p.tokens, p.bonus)) return true;
    }
    return false;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 'over') throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final p = ps[seat];
    final type = asStr(a['type']);
    final who = name(seat);
    if (phase == 'return') {
      if (type != 'return') throw GameError('请先退回多余的宝石');
      final back = asIntList(a['tokens']);
      if (back.length != 6) throw GameError('参数错误');
      final excess = p.tokenCount - 10;
      if (back.fold(0, (x, y) => x + y) != excess) throw GameError('需要退回 $excess 枚宝石');
      for (var c = 0; c < 6; c++) {
        if (back[c] < 0 || back[c] > p.tokens[c]) throw GameError('宝石数量不足');
      }
      for (var c = 0; c < 6; c++) {
        p.tokens[c] -= back[c];
        supply[c] += back[c];
      }
      last += '，退回 ${_fmt(back)}';
      _afterAction(seat);
      return;
    }
    if (phase == 'noble') {
      if (type != 'noble') throw GameError('请选择来访的贵族');
      final n = asInt(a['noble']);
      if (!nobleChoices.contains(n)) throw GameError('该贵族不能来访');
      _takeNoble(seat, n);
      _endTurn();
      return;
    }
    switch (type) {
      case 'take':
        final cs = asIntList(a['colors']);
        if (cs.isEmpty || cs.any((c) => c < 0 || c > 4)) throw GameError('请选择宝石');
        if (cs.length == 2 && cs[0] == cs[1]) {
          if (supply[cs[0]] < 4) throw GameError('该颜色剩余不足 4 枚，不能拿 2 枚同色');
        } else {
          if (cs.toSet().length != cs.length) throw GameError('拿取 3 枚时颜色必须各不相同');
          if (cs.length > 3) throw GameError('最多拿 3 枚');
          if (cs.any((c) => supply[c] <= 0)) throw GameError('该颜色宝石已拿完');
          final avail = [for (var c = 0; c < 5; c++) if (supply[c] > 0) c].length;
          if (cs.length < 3 && cs.length < avail) throw GameError('请拿 3 枚不同颜色的宝石（或 2 枚同色）');
        }
        final got = List.filled(6, 0);
        for (final c in cs) {
          supply[c]--;
          p.tokens[c]++;
          got[c]++;
        }
        last = '$who 拿取了 ${_fmt(got)}';
        lastAct = {'seat': seat, 'type': 'take', 'tokens': got};
      case 'reserve':
        if (p.reserved.length >= 3) throw GameError('最多保留 3 张牌');
        final id = asInt(a['card']);
        int card;
        var public = true;
        if (id >= 0) {
          final pos = _findOnBoard(id);
          if (pos == null) throw GameError('这张牌不在桌面上');
          card = id;
          _refill(pos.$1, pos.$2);
        } else {
          final t = asInt(a['tier']);
          if (t < 0 || t > 2 || decks[t].isEmpty) throw GameError('该牌堆已空');
          card = decks[t].removeLast();
          public = false;
        }
        p.reserved.add(card);
        if (public) p.reservedPublic.add(card);
        var gold = false;
        if (supply[5] > 0) {
          supply[5]--;
          p.tokens[5]++;
          gold = true;
        }
        last = public
            ? '$who 保留了一张 ${_cardName(_card(card))}${gold ? '，拿取 1 枚黄金' : ''}'
            : '$who 从 ${card < 0 ? '' : '${_card(card).tier + 1} 级'}牌堆盲保留一张${gold ? '，拿取 1 枚黄金' : ''}';
        lastAct = {'seat': seat, 'type': 'reserve', 'card': public ? card : -1};
      case 'buy':
        final id = asInt(a['card']);
        if (id < 0 || id >= splendorCards.length) throw GameError('无效卡牌');
        final pos = _findOnBoard(id);
        final fromReserve = p.reserved.contains(id);
        if (pos == null && !fromReserve) throw GameError('只能购买桌面或自己保留的牌');
        final card = _card(id);
        if (!splendorCanAfford(card, p.tokens, p.bonus)) throw GameError('宝石不足');
        final pay = splendorPayment(card, p.tokens, p.bonus);
        for (var c = 0; c < 6; c++) {
          p.tokens[c] -= pay[c];
          supply[c] += pay[c];
        }
        if (fromReserve) {
          p.reserved.remove(id);
          p.reservedPublic.remove(id);
        } else {
          _refill(pos!.$1, pos.$2);
        }
        p.bought.add(id);
        p.bonus[card.color]++;
        last = '$who 购买了 ${_cardName(card)}${fromReserve ? '（保留牌）' : ''}';
        lastAct = {'seat': seat, 'type': 'buy', 'card': id};
      case 'pass':
        if (_canAnything(seat)) throw GameError('还有可执行的行动，不能跳过');
        last = '$who 无法行动，跳过';
        lastAct = {'seat': seat, 'type': 'pass'};
        passStreak++;
        _afterAction(seat);
        return;
      default:
        throw GameError('未知操作');
    }
    passStreak = 0;
    _afterAction(seat);
  }

  String _cardName(SplendorCard c) =>
      '${c.tier + 1}级${splendorColorNames[c.color]}卡${c.points > 0 ? '(${c.points}分)' : ''}';

  String _fmt(List<int> t) => [
        for (var c = 0; c < 6; c++)
          if (t[c] > 0) '${splendorColorNames[c]}×${t[c]}'
      ].join(' ');

  void _afterAction(int seat) {
    final p = ps[seat];
    if (p.tokenCount > 10) {
      phase = 'return';
      return;
    }
    final eligible = [
      for (final n in nobles)
        if (List.generate(5, (c) => p.bonus[c] >= splendorNobles[n].req[c]).every((x) => x)) n
    ];
    if (eligible.length > 1) {
      phase = 'noble';
      nobleChoices = eligible;
      return;
    }
    if (eligible.length == 1) _takeNoble(seat, eligible.first);
    _endTurn();
  }

  void _takeNoble(int seat, int n) {
    nobles.remove(n);
    ps[seat].nobles.add(n);
    nobleChoices = [];
    last += '，贵族来访 +3 分';
  }

  void _endTurn() {
    host.log(last);
    final p = ps[turn];
    if (p.points >= 15 && !finalRound) {
      finalRound = true;
      host.log('${name(turn)} 达到 ${p.points} 分！本轮结束后游戏结束');
    }
    phase = 'main';
    _advance();
  }

  /// Pass the turn to the next non-resigned seat (or end the game).
  void _advance() {
    var next = turn;
    var wrapped = false;
    do {
      next = (next + 1) % players;
      if (next == first) wrapped = true;
    } while (!_active(next));
    if ((finalRound && wrapped) || passStreak >= _activeCount * 2) {
      _finish();
      return;
    }
    turn = next;
  }

  void _finish() {
    phase = 'over';
    final best = List.generate(players, _rankKey).reduce((a, b) => a > b ? a : b);
    winners = [for (var s = 0; s < players; s++) if (_rankKey(s) == best) s];
    host.log('游戏结束！${winners.map(name).join('、')} 以 ${ps[winners.first].points} 分获胜');
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'players': players,
        'turn': turn,
        'first': first,
        'phase': phase,
        'supply': supply,
        'board': [
          for (final r in board) [for (final id in r) id < 0 ? null : _card(id).toJson()]
        ],
        'decks': [for (final d in decks) d.length],
        'nobles': [for (final n in nobles) splendorNobles[n].toJson()],
        'nobleChoices': seat == turn ? [for (final n in nobleChoices) splendorNobles[n].toJson()] : [],
        'ps': [
          for (var s = 0; s < players; s++)
            {
              'tokens': ps[s].tokens,
              'bonus': ps[s].bonus,
              'points': ps[s].points,
              'bought': ps[s].bought.length,
              'nobles': [for (final n in ps[s].nobles) splendorNobles[n].toJson()],
              'reserved': [
                for (final id in ps[s].reserved)
                  (s == seat || ps[s].reservedPublic.contains(id) || phase == 'over')
                      ? _card(id).toJson()
                      : {'id': -1, 'tier': _card(id).tier},
              ],
            }
        ],
        'finalRound': finalRound,
        'last': last,
        'lastAct': lastAct,
        'winners': winners,
        'resigned': [for (final r in resignOrder) r > 0],
        'over': phase == 'over',
      };

  // ---------------- bot ----------------

  double _cardValue(int seat, SplendorCard c) {
    final p = ps[seat];
    var v = c.points * 3.0 + 1.0;
    // noble progress
    for (final n in nobles) {
      final req = splendorNobles[n].req[c.color];
      if (req > p.bonus[c.color]) v += 0.8;
    }
    // early engine bonus
    if (p.points < 8) v += 0.5;
    return v;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final p = ps[seat];
    if (phase == 'return') {
      final back = List.filled(6, 0);
      var excess = p.tokenCount - 10;
      final need = _needs(seat);
      final tmp = List.of(p.tokens);
      while (excess > 0) {
        // return colour with most surplus over need (never gold unless forced)
        var bestC = -1;
        var bestS = -1 << 30;
        for (var c = 0; c < 5; c++) {
          if (tmp[c] <= 0) continue;
          final s = tmp[c] - need[c];
          if (s > bestS) {
            bestS = s;
            bestC = c;
          }
        }
        if (bestC < 0) bestC = 5;
        tmp[bestC]--;
        back[bestC]++;
        excess--;
      }
      return {'type': 'return', 'tokens': back};
    }
    if (phase == 'noble') {
      if (botLevel == 0) return {'type': 'noble', 'noble': nobleChoices[rng.nextInt(nobleChoices.length)]};
      return {'type': 'noble', 'noble': nobleChoices.first};
    }
    if (botLevel == 0 && rng.nextDouble() < 0.4) return _randomMove(seat);
    if (botLevel >= 2) {
      final h = _hardMove(seat);
      if (h != null) return h;
    }

    final visible = [for (final r in board) ...r.where((c) => c >= 0)];
    // 1. buy the best affordable card
    int? bestBuy;
    var bestBuyV = -1.0;
    for (final id in [...visible, ...p.reserved]) {
      final c = _card(id);
      if (!splendorCanAfford(c, p.tokens, p.bonus)) continue;
      final pay = splendorPayment(c, p.tokens, p.bonus);
      final v = _cardValue(seat, c) - pay[5] * 0.5 + (p.reserved.contains(id) ? 0.7 : 0);
      if (v > bestBuyV) {
        bestBuyV = v;
        bestBuy = id;
      }
    }
    if (bestBuy != null) return {'type': 'buy', 'card': bestBuy};

    // 2. collect gems towards a target
    final need = _needs(seat);
    final avail = [for (var c = 0; c < 5; c++) if (supply[c] > 0) c];
    final wanted = [for (final c in avail) if (need[c] > 0) c]..sort((a, b) => need[b].compareTo(need[a]));
    if (p.tokenCount <= 8 || wanted.isNotEmpty) {
      if (wanted.isNotEmpty && need[wanted.first] >= 2 && supply[wanted.first] >= 4 && wanted.length == 1) {
        return {'type': 'take', 'colors': [wanted.first, wanted.first]};
      }
      if (wanted.isNotEmpty || p.tokenCount <= 7) {
        final pick = <int>[...wanted.take(3)];
        final others = [for (final c in avail) if (!pick.contains(c)) c]..shuffle(rng);
        for (final c in others) {
          if (pick.length >= 3) break;
          pick.add(c);
        }
        if (pick.isNotEmpty && (pick.length == 3 || pick.length == avail.length)) {
          return {'type': 'take', 'colors': pick};
        }
      }
    }
    // 3. reserve
    if (p.reserved.length < 3) {
      final target = _target(seat);
      if (target != null && _findOnBoard(target) != null) return {'type': 'reserve', 'card': target};
      if (visible.isNotEmpty) {
        visible.sort((a, b) => _card(b).points.compareTo(_card(a).points));
        return {'type': 'reserve', 'card': visible.first};
      }
      for (var t = 2; t >= 0; t--) {
        if (decks[t].isNotEmpty) return {'type': 'reserve', 'card': -1, 'tier': t};
      }
    }
    // 4. any legal take
    if (avail.isNotEmpty) {
      return {'type': 'take', 'colors': avail.take(3).toList()};
    }
    return {'type': 'pass'};
  }

  int? _target(int seat) {
    final p = ps[seat];
    int? best;
    var bestS = 1e9;
    for (final id in [for (final r in board) ...r.where((c) => c >= 0), ...p.reserved]) {
      final c = _card(id);
      var missing = 0;
      for (var col = 0; col < 5; col++) {
        final r = c.cost[col] - p.bonus[col] - p.tokens[col];
        if (r > 0) missing += r;
      }
      missing -= p.tokens[5];
      if (missing < 0) missing = 0;
      final s = missing * 1.0 - _cardValue(seat, c) * 0.6 + (p.reserved.contains(id) ? -0.5 : 0);
      if (s < bestS) {
        bestS = s;
        best = id;
      }
    }
    return best;
  }

  /// Remaining gems per colour needed for the bot's target card.
  List<int> _needs(int seat) {
    final p = ps[seat];
    final need = List.filled(5, 0);
    final t = _target(seat);
    if (t == null) return need;
    final c = _card(t);
    for (var col = 0; col < 5; col++) {
      final r = c.cost[col] - p.bonus[col] - p.tokens[col];
      if (r > 0) need[col] = r;
    }
    return need;
  }

  /// 简单难度：随机合法行动。
  Map<String, dynamic> _randomMove(int seat) {
    final p = ps[seat];
    final moves = <Map<String, dynamic>>[];
    final visible = [for (final r in board) ...r.where((c) => c >= 0)];
    for (final id in [...visible, ...p.reserved]) {
      if (splendorCanAfford(_card(id), p.tokens, p.bonus)) moves.add({'type': 'buy', 'card': id});
    }
    final avail = [for (var c = 0; c < 5; c++) if (supply[c] > 0) c]..shuffle(rng);
    if (avail.isNotEmpty) moves.add({'type': 'take', 'colors': avail.take(3).toList()});
    for (var c = 0; c < 5; c++) {
      if (supply[c] >= 4) moves.add({'type': 'take', 'colors': [c, c]});
    }
    if (p.reserved.length < 3 && visible.isNotEmpty) {
      moves.add({'type': 'reserve', 'card': visible[rng.nextInt(visible.length)]});
    }
    if (moves.isEmpty) {
      if (p.reserved.length < 3) {
        for (var t = 0; t < 3; t++) {
          if (decks[t].isNotEmpty) return {'type': 'reserve', 'card': -1, 'tier': t};
        }
      }
      return {'type': 'pass'};
    }
    return moves[rng.nextInt(moves.length)];
  }

  /// 困难难度：先看能否直接取胜 / 阻止对手取胜，买牌时综合考虑分数、贵族与性价比。
  Map<String, dynamic>? _hardMove(int seat) {
    final p = ps[seat];
    final visible = [for (final r in board) ...r.where((c) => c >= 0)];
    int nobleGain(SplendorCard c) {
      var g = 0;
      for (final n in nobles) {
        final req = splendorNobles[n].req;
        var ok = true;
        for (var col = 0; col < 5; col++) {
          final have = p.bonus[col] + (col == c.color ? 1 : 0);
          if (have < req[col]) ok = false;
        }
        if (ok) g = 3;
      }
      return g;
    }

    int? bestBuy;
    var bestV = -1e9;
    for (final id in [...visible, ...p.reserved]) {
      final c = _card(id);
      if (!splendorCanAfford(c, p.tokens, p.bonus)) continue;
      final pay = splendorPayment(c, p.tokens, p.bonus);
      final spent = pay.fold(0, (a, b) => a + b);
      final gain = c.points + nobleGain(c);
      var v = gain * 4.0 + _cardValue(seat, c) - spent * 0.35 - pay[5] * 0.6 + (p.reserved.contains(id) ? 1.0 : 0);
      if (p.points + gain >= 15) v += 100;
      if (v > bestV) {
        bestV = v;
        bestBuy = id;
      }
    }
    // a free-ish engine card or any point card is worth buying now
    if (bestBuy != null && (bestV > 3 || p.points >= 10)) return {'type': 'buy', 'card': bestBuy};
    // block an opponent who could reach 15 with a visible card
    if (p.reserved.length < 3) {
      for (var o = 0; o < players; o++) {
        if (o == seat || !_active(o)) continue;
        final op = ps[o];
        for (final id in visible) {
          final c = _card(id);
          if (c.points > 0 && op.points + c.points >= 15 && splendorCanAfford(c, op.tokens, op.bonus)) {
            return {'type': 'reserve', 'card': id};
          }
        }
      }
    }
    if (bestBuy != null) return {'type': 'buy', 'card': bestBuy};
    return null;
  }
}
