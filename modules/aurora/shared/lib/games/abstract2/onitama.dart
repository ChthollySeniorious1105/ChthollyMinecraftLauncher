import '../../src/engine.dart';

/// 师徒棋 Onitama 的 16 张招式卡。偏移以“持卡方视角”表示：dx 向右、dy 向前（远离自己）。
class OniCard {
  final String id;
  final String name;
  final List<(int, int)> moves;

  /// 0 = 红（下方先手色）印章, 1 = 蓝 —— 决定谁先手。
  final int stamp;
  const OniCard(this.id, this.name, this.moves, this.stamp);
}

const oniCards = [
  OniCard('tiger', '虎', [(0, 2), (0, -1)], 1),
  OniCard('crab', '蟹', [(-2, 0), (2, 0), (0, 1)], 1),
  OniCard('monkey', '猴', [(-1, 1), (1, 1), (-1, -1), (1, -1)], 1),
  OniCard('crane', '鹤', [(0, 1), (-1, -1), (1, -1)], 1),
  OniCard('dragon', '龙', [(-2, 1), (2, 1), (-1, -1), (1, -1)], 0),
  OniCard('elephant', '象', [(-1, 1), (1, 1), (-1, 0), (1, 0)], 0),
  OniCard('mantis', '螳螂', [(-1, 1), (1, 1), (0, -1)], 0),
  OniCard('boar', '野猪', [(-1, 0), (1, 0), (0, 1)], 0),
  OniCard('frog', '蛙', [(-2, 0), (-1, 1), (1, -1)], 0),
  OniCard('goose', '鹅', [(-1, 0), (-1, 1), (1, 0), (1, -1)], 1),
  OniCard('horse', '马', [(-1, 0), (0, 1), (0, -1)], 0),
  OniCard('eel', '鳗', [(-1, 1), (-1, -1), (1, 0)], 1),
  OniCard('rabbit', '兔', [(2, 0), (1, 1), (-1, -1)], 1),
  OniCard('rooster', '公鸡', [(1, 0), (1, 1), (-1, 0), (-1, -1)], 0),
  OniCard('ox', '牛', [(1, 0), (0, 1), (0, -1)], 1),
  OniCard('cobra', '眼镜蛇', [(-1, 0), (1, 1), (1, -1)], 0),
];

int oniCardIndex(String id) => oniCards.indexWhere((c) => c.id == id);

/// Board: 25 cells, index = y*5+x, y = 0 is color 0's home row (bottom).
/// Cell values: 0 empty, 1 student c0, 2 master c0, 3 student c1, 4 master c1.
class OniState {
  final List<int> b;
  final List<List<int>> hands; // card indices per color
  int side; // card index waiting on the side
  int toMove;

  OniState(this.b, this.hands, this.side, this.toMove);
  OniState clone() => OniState(List.of(b), [List.of(hands[0]), List.of(hands[1])], side, toMove);

  static int colorAt(int v) => v == 0 ? -1 : (v <= 2 ? 0 : 1);
  static bool isMaster(int v) => v == 2 || v == 4;
  static const temple = [2, 22]; // c0 temple (at y=0) / c1 temple (y=4)

  /// (card, from, to) moves for color c.
  List<(int, int, int)> moves() {
    final c = toMove;
    final out = <(int, int, int)>[];
    for (final ci in hands[c]) {
      for (var p = 0; p < 25; p++) {
        if (colorAt(b[p]) != c) continue;
        final x = p % 5, y = p ~/ 5;
        for (final (dx, dy) in oniCards[ci].moves) {
          final nx = c == 0 ? x + dx : x - dx, ny = c == 0 ? y + dy : y - dy;
          if (nx < 0 || ny < 0 || nx > 4 || ny > 4) continue;
          final t = ny * 5 + nx;
          if (colorAt(b[t]) == c) continue;
          out.add((ci, p, t));
        }
      }
    }
    return out;
  }

  /// Returns the captured value.
  int apply((int, int, int) m) {
    final (ci, f, t) = m;
    final cap = b[t];
    b[t] = b[f];
    b[f] = 0;
    final h = hands[toMove];
    h[h.indexOf(ci)] = side;
    side = ci;
    toMove = 1 - toMove;
    return cap;
  }

  /// Winner color or -1.
  int winnerColor() {
    var m0 = -1, m1 = -1;
    for (var p = 0; p < 25; p++) {
      if (b[p] == 2) m0 = p;
      if (b[p] == 4) m1 = p;
    }
    if (m1 < 0 || m0 == temple[1]) return 0;
    if (m0 < 0 || m1 == temple[0]) return 1;
    return -1;
  }
}

class OniAI {
  final Stopwatch _sw = Stopwatch();
  int _limit = 300;
  bool _timeout = false;
  static const _win = 100000;

  int eval(OniState s, int me) {
    var v = 0;
    int m0 = -1, m1 = -1;
    for (var p = 0; p < 25; p++) {
      final x = s.b[p];
      if (x == 0) continue;
      final c = OniState.colorAt(x);
      final sign = c == me ? 1 : -1;
      if (OniState.isMaster(x)) {
        if (c == 0) {
          m0 = p;
        } else {
          m1 = p;
        }
      } else {
        v += sign * 100;
        final y = p ~/ 5, xx = p % 5;
        final adv = c == 0 ? y : 4 - y;
        v += sign * (adv * 3 + (2 - (xx - 2).abs()) * 2);
      }
    }
    // master progress toward enemy temple
    if (m0 >= 0) v += (me == 0 ? 1 : -1) * ((m0 ~/ 5) * 4 - ((m0 % 5) - 2).abs() * 3);
    if (m1 >= 0) v += (me == 1 ? 1 : -1) * ((4 - m1 ~/ 5) * 4 - ((m1 % 5) - 2).abs() * 3);
    // mobility
    final t = s.toMove;
    s.toMove = me;
    final myMob = s.moves().length;
    s.toMove = 1 - me;
    final opMob = s.moves().length;
    s.toMove = t;
    return v + (myMob - opMob) * 2;
  }

  int _search(OniState s, int depth, int alpha, int beta, int ply) {
    if (_sw.elapsedMilliseconds > _limit) {
      _timeout = true;
      return 0;
    }
    final w = s.winnerColor();
    if (w >= 0) return w == s.toMove ? _win - ply : -_win + ply;
    if (depth <= 0) return eval(s, s.toMove);
    final ms = s.moves();
    if (ms.isEmpty) {
      // must pass a card: modelled as using any card without moving (rare)
      final n = s.clone();
      final ci = n.hands[n.toMove].first;
      n.hands[n.toMove][0] = n.side;
      n.side = ci;
      n.toMove = 1 - n.toMove;
      return -_search(n, depth - 1, -beta, -alpha, ply + 1);
    }
    ms.sort((a, b) => _gain(s, b).compareTo(_gain(s, a)));
    var best = -_win * 2;
    for (final m in ms) {
      final n = s.clone()..apply(m);
      final v = -_search(n, depth - 1, -beta, -alpha, ply + 1);
      if (_timeout) return 0;
      if (v > best) best = v;
      if (v > alpha) alpha = v;
      if (alpha >= beta) break;
    }
    return best;
  }

  static int _gain(OniState s, (int, int, int) m) {
    final v = s.b[m.$3];
    if (OniState.isMaster(v)) return 1000;
    if (OniState.isMaster(s.b[m.$2]) && m.$3 == OniState.temple[1 - s.toMove]) return 1000;
    return v == 0 ? 0 : 100;
  }

  (int, int, int) best(OniState root, {int maxDepth = 6, int limitMs = 300}) {
    final ms = root.moves();
    _sw
      ..reset()
      ..start();
    _limit = limitMs;
    ms.sort((a, b) => _gain(root, b).compareTo(_gain(root, a)));
    var bestMove = ms.first;
    for (var d = 1; d <= maxDepth; d++) {
      _timeout = false;
      var alpha = -_win * 2;
      (int, int, int)? bm;
      for (final m in [bestMove, ...ms.where((x) => x != bestMove)]) {
        final n = root.clone()..apply(m);
        final v = -_search(n, d - 1, -_win * 2, -alpha, 1);
        if (_timeout) break;
        if (v > alpha || bm == null) {
          alpha = v;
          bm = m;
        }
      }
      if (_timeout) break;
      if (bm != null) bestMove = bm;
      if (alpha > _win ~/ 2) break;
    }
    return bestMove;
  }
}

class Onitama extends GameEngine {
  Onitama(super.setup);

  late OniState s;
  int redSeat = 0; // color 0 (bottom in its own view) = 红
  int winner = -1; // seat, 2 = draw
  String result = '';
  String note = '';
  Map<String, dynamic>? last;
  int plies = 0;
  final Map<String, int> _reps = {};
  static const maxPlies = 300;

  bool get over => winner != -1;
  int seatOf(int color) => color == 0 ? redSeat : 1 - redSeat;
  int colorOf(int seat) => seat == redSeat ? 0 : 1;
  int get turnSeat => seatOf(s.toMove);

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turnSeat];

  @override
  void start() {
    final deck = shuffled(List.generate(oniCards.length, (i) => i), rng);
    final b = List.filled(25, 0);
    for (var x = 0; x < 5; x++) {
      b[x] = x == 2 ? 2 : 1;
      b[20 + x] = x == 2 ? 4 : 3;
    }
    final side = deck[4];
    s = OniState(b, [
      [deck[0], deck[1]],
      [deck[2], deck[3]]
    ], side, oniCards[side].stamp);
    redSeat = rng.nextInt(2);
    _reps[_key()] = 1;
    host.log('师徒棋：${name(redSeat)} 执红，${name(1 - redSeat)} 执蓝；侧卡「${oniCards[side].name}」决定 ${name(turnSeat)} 先行');
  }

  String _key() => '${s.b.join()}|${(List.of(s.hands[0])..sort()).join(',')}|${(List.of(s.hands[1])..sort()).join(',')}|${s.side}|${s.toMove}';

  bool get _stuck => s.moves().isEmpty;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') return resign(seat);
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    if (seat != turnSeat) throw GameError('还没轮到你');
    final ci = oniCardIndex(asStr(a['card']));
    final c = s.toMove;
    if (ci < 0 || !s.hands[c].contains(ci)) throw GameError('你没有这张卡');
    if (a['type'] == 'pass') {
      if (!_stuck) throw GameError('还有可走的棋，不能只换卡');
      final h = s.hands[c];
      h[h.indexOf(ci)] = s.side;
      s.side = ci;
      s.toMove = 1 - c;
      note = '${name(seat)} 无棋可走，交出「${oniCards[ci].name}」';
      last = {'card': oniCards[ci].id, 'from': -1, 'to': -1, 'color': c};
      _after();
      return;
    }
    final f = asInt(a['from']), t = asInt(a['to']);
    final m = (ci, f, t);
    if (!s.moves().contains(m)) throw GameError('这张卡不能这样走');
    final mover = s.b[f];
    final cap = s.apply(m);
    plies++;
    last = {'card': oniCards[ci].id, 'from': f, 'to': t, 'color': c, 'cap': cap};
    note = '${name(seat)} 用「${oniCards[ci].name}」${OniState.isMaster(mover) ? '师父' : '弟子'} ${_cell(f, c)}→${_cell(t, c)}'
        '${cap == 0 ? '' : '，吃掉${OniState.isMaster(cap) ? '师父' : '弟子'}'}';
    _after();
  }

  String _cell(int p, int c) => '${String.fromCharCode(97 + p % 5)}${p ~/ 5 + 1}';

  void _after() {
    final w = s.winnerColor();
    if (w >= 0) {
      winner = seatOf(w);
      final cap = !s.b.contains(w == 0 ? 4 : 2);
      result = '${name(winner)} ${cap ? '擒获对方师父' : '师父攻入对方神殿'}，获胜';
      host.log(result);
      return;
    }
    final k = _key();
    final n = (_reps[k] ?? 0) + 1;
    _reps[k] = n;
    if (n >= 3) {
      winner = 2;
      result = '同一局面第三次出现，和棋';
      host.log(result);
    } else if (plies >= maxPlies) {
      winner = 2;
      result = '达到 $maxPlies 手上限，和棋';
      host.log(result);
    }
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    winner = 1 - seat;
    result = '${name(seat)} 认输，${name(winner)} 获胜';
    host.log(result);
  }

  @override
  bool get canDraw => !over;
  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    winner = 2;
    result = '双方同意和棋';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'board': s.b,
        'hands': [
          [for (final c in s.hands[0]) oniCards[c].id],
          [for (final c in s.hands[1]) oniCards[c].id],
        ],
        'side': oniCards[s.side].id,
        'redSeat': redSeat,
        'toMove': s.toMove,
        'turn': turnSeat,
        'moves': over ? const [] : [for (final (c, f, t) in s.moves()) [oniCards[c].id, f, t]],
        'stuck': !over && _stuck,
        'last': last,
        'note': note,
        'plies': plies,
        'winner': winner,
        'result': result,
        'over': over,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turnSeat) return null;
    if (_stuck) return {'type': 'pass', 'card': oniCards[s.hands[s.toMove].first].id};
    final ms = s.moves();
    final lvl = botLevel;
    (int, int, int) m;
    if (lvl == 0 && rng.nextDouble() < 0.5) {
      m = ms[rng.nextInt(ms.length)];
    } else {
      m = OniAI().best(s.clone(), maxDepth: lvl == 0 ? 1 : (lvl == 1 ? 4 : 8), limitMs: lvl >= 2 ? 1000 : 250);
    }
    return {'type': 'move', 'card': oniCards[m.$1].id, 'from': m.$2, 'to': m.$3};
  }
}
