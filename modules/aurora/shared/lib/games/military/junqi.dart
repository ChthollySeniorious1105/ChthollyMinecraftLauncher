import 'dart:math';

import '../../src/engine.dart';
import 'junqi_ai.dart';
import 'junqi_geo.dart';

/// Piece ranks. 1..9 = 工兵..司令.
const kFlag = 0, kEng = 1, kCmd = 9, kBomb = 10, kMine = 11;

const junqiRankNames = {
  9: '司令', 8: '军长', 7: '师长', 6: '旅长', 5: '团长', 4: '营长',
  3: '连长', 2: '排长', 1: '工兵', 10: '炸弹', 11: '地雷', 0: '军旗',
};

/// The 25 pieces of one army.
const junqiArmy = [9, 8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 3, 3, 2, 2, 2, 1, 1, 1, 11, 11, 11, 10, 10, 0];

class JP {
  /// Seat (两国/四国) or colour 0/1 (翻翻棋).
  final int owner;
  final int rank;

  /// Publicly revealed (翻翻棋: face up; 两国/四国: flag shown after 司令 dies).
  bool up;
  bool moved = false;
  int kills = 0;
  JP(this.owner, this.rank, {this.up = false});
  JP copy() => JP(owner, rank, up: up)
    ..moved = moved
    ..kills = kills;
}

/// Combat: 1 attacker wins, -1 attacker dies, 0 both removed.
int junqiBattle(int a, int d) {
  if (d == kFlag) return 1;
  if (a == kBomb || d == kBomb) return 0;
  if (d == kMine) return a == kEng ? 1 : -1;
  if (a > d) return 1;
  if (a < d) return -1;
  return 0;
}

bool junqiMovable(int rank) => rank != kFlag && rank != kMine;

/// Legal moves on board [b]. [mine] = pieces the mover controls; [friendly] =
/// pieces that cannot be attacked (own/teammate/face-down).
Map<int, List<int>> junqiMoves(JunqiGeo geo, List<JP?> b, bool Function(JP) mine, bool Function(JP) friendly,
    {bool hqLock = true}) {
  final out = <int, List<int>>{};
  for (var from = 0; from < b.length; from++) {
    final p = b[from];
    if (p == null || !mine(p) || !junqiMovable(p.rank)) continue;
    if (hqLock && geo.nodes[from].kind == JKind.hq) continue;
    final t = junqiTargets(geo, b, from, friendly);
    if (t.isNotEmpty) out[from] = t;
  }
  return out;
}

List<int> junqiTargets(JunqiGeo geo, List<JP?> b, int from, bool Function(JP) friendly) {
  final p = b[from]!;
  final res = <int>{};
  bool consider(int n) {
    final q = b[n];
    if (q == null) {
      res.add(n);
      return true;
    }
    if (friendly(q)) return false;
    if (geo.nodes[n].kind == JKind.camp) return false;
    res.add(n);
    return false;
  }

  for (final n in geo.adj[from]) {
    consider(n);
  }
  if (geo.nodes[from].rail) {
    if (p.rank == kEng) {
      final seen = <int>{from};
      final queue = [from];
      while (queue.isNotEmpty) {
        final cur = queue.removeLast();
        for (final x in geo.railAdj[cur]) {
          if (!seen.add(x)) continue;
          if (consider(x)) queue.add(x);
        }
      }
    } else {
      for (final li in geo.linesAt[from]) {
        final line = geo.lines[li];
        final idx = line.indexOf(from);
        for (final dir in [-1, 1]) {
          for (var i = idx + dir; i >= 0 && i < line.length; i += dir) {
            if (!consider(line[i])) break;
          }
        }
      }
    }
  }
  return res.toList()..sort();
}

class Junqi extends GameEngine {
  Junqi(super.setup);

  static const cap = 1000;
  late final String mode = setup.opt<String>('mode', 'two');
  bool get four => mode == 'four';
  bool get flip => mode == 'flip';
  late final JunqiGeo geo = JunqiGeo.of(four);

  late List<JP?> b;
  int phase = 0; // 0 布阵, 1 对局, 2 结束
  late List<bool> ready;
  late List<bool> alive;
  List<int> colorOf = [-1, -1]; // 翻翻棋: seat -> colour
  int turn = 0;
  int plies = 0;
  List<int> winners = [];
  String result = '';
  Map<String, dynamic>? last;
  late List<List<int>> lost;

  /// Public event log (everything every player can observe). Bots decide only
  /// from this log, their start-of-battle view and their current view.
  final List<Map<String, dynamic>> publicLog = [];

  /// view(seat)['board'] captured when the battle phase started.
  List<List?> startViews = [];
  final Map<int, JunqiMind> _minds = {};

  int team(int seat) => four ? seat % 2 : seat;
  int seatOf(JP p) => flip ? colorOf.indexOf(p.owner) : p.owner;

  bool Function(JP) mineFn(int seat) => flip
      ? (p) => p.up && colorOf[seat] >= 0 && p.owner == colorOf[seat]
      : (p) => p.owner == seat;
  bool Function(JP) friendFn(int seat) => flip
      ? (p) => !p.up || p.owner == colorOf[seat]
      : (p) => team(p.owner) == team(seat);

  Map<int, List<int>> legalMoves(int seat) {
    final m = junqiMoves(geo, b, mineFn(seat), friendFn(seat), hqLock: !flip);
    if (!flip) return m;
    // 翻翻棋: a flag can only be taken after all of its colour's mines are gone.
    bool minesLeft(int colour) => b.any((p) => p != null && p.owner == colour && p.rank == kMine);
    final out = <int, List<int>>{};
    m.forEach((from, tos) {
      final t = [
        for (final to in tos)
          if (b[to] == null || b[to]!.rank != kFlag || !minesLeft(b[to]!.owner)) to
      ];
      if (t.isNotEmpty) out[from] = t;
    });
    return out;
  }

  @override
  void start() {
    b = List.filled(geo.nodes.length, null);
    ready = List.filled(players, false);
    alive = List.filled(players, true);
    lost = List.generate(players, (_) => <int>[]);
    if (flip) {
      final pieces = shuffled([for (var c = 0; c < 2; c++) for (final r in junqiArmy) JP(c, r)], rng);
      var i = 0;
      for (final n in geo.nodes) {
        if (n.kind != JKind.camp) b[n.id] = pieces[i++];
      }
      phase = 1;
      _captureStart();
      turn = rng.nextInt(2);
      host.log('翻翻棋开始，${name(turn)} 先翻棋');
    } else {
      for (var s = 0; s < players; s++) {
        randomLayout(s);
      }
      phase = 0;
      host.log('布阵阶段：点击两枚棋子可交换位置，完成后点“准备”');
    }
  }

  List<int> armSlots(int seat) => [for (final id in geo.armNodes[seat]) if (geo.nodes[id].kind != JKind.camp) id];

  void randomLayout(int seat) {
    final slots = armSlots(seat);
    for (final id in slots) {
      b[id] = null;
    }
    final free = List.of(slots);
    void put(int id, int rank) {
      b[id] = JP(seat, rank);
      free.remove(id);
    }

    final hqs = free.where((id) => geo.nodes[id].kind == JKind.hq).toList();
    final flagAt = hqs[rng.nextInt(hqs.length)];
    put(flagAt, kFlag);
    final mineCand = free.where((id) => geo.nodes[id].lr >= 4).toList();
    final score = {for (final id in mineCand) id: rng.nextDouble() + (geo.adj[flagAt].contains(id) ? 0.6 : 0)};
    mineCand.sort((x, y) => score[y]!.compareTo(score[x]!));
    for (final id in mineCand.take(3)) {
      put(id, kMine);
    }
    final bombCand = shuffled(free.where((id) => geo.nodes[id].lr >= 1), rng);
    for (final id in bombCand.take(2)) {
      put(id, kBomb);
    }
    final rest = shuffled(junqiArmy.where((r) => r != kFlag && r != kMine && r != kBomb), rng);
    for (final id in List.of(free)) {
      put(id, rest.removeLast());
    }
  }

  /// Returns an error message or null when the layout of [seat] is valid.
  String? layoutError(int seat) {
    for (final id in geo.armNodes[seat]) {
      final p = b[id];
      if (p == null) continue;
      final n = geo.nodes[id];
      if (p.rank == kFlag && n.kind != JKind.hq) return '军旗必须放在大本营';
      if (p.rank == kMine && n.lr < 4) return '地雷只能放在最后两排';
      if (p.rank == kBomb && n.lr == 0) return '炸弹不能放在第一排';
    }
    return null;
  }

  @override
  bool get isOver => phase == 2;

  @override
  List<int>? get placings => !isOver ? null : rankWinners(players, winners);

  @override
  bool get canResign => !isOver;

  /// 认输: two-player modes end at once; in 四国 the seat is eliminated (its
  /// pieces leave the board) and the game ends when a whole team is out.
  @override
  void resign(int seat) {
    if (phase == 2) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不是玩家');
    if (!alive[seat]) throw GameError('你已出局');
    host.log('${name(seat)} 认输');
    _resign(seat);
  }

  void _resign(int seat) {
    _eliminate(seat, '认输');
    if (phase == 0) {
      // 四国布阵中认输: the seat no longer blocks the start of the battle.
      ready[seat] = true;
      if (phase == 0 && ready.every((r) => r)) _beginBattle();
    } else if (phase == 1 && turn == seat) {
      _nextTurn();
    }
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (phase == 2) throw GameError('对局已结束');
    _end([], '双方同意和棋');
  }

  void _beginBattle() {
    phase = 1;
    _captureStart();
    turn = rng.nextInt(players);
    if (!alive[turn]) _nextTurn();
    host.log('布阵完成，${name(turn)} 先走');
    _checkTurn();
  }

  @override
  List<int> get waitingFor {
    if (phase == 0) return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    if (phase == 1) return [turn];
    return const [];
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (phase == 2) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不是玩家');
    final type = asStr(a['type']);
    if (phase == 0) {
      if (ready[seat]) throw GameError('你已准备，等待其他玩家');
      switch (type) {
        case 'swap':
          final x = asInt(a['a']), y = asInt(a['b']);
          final arm = geo.armNodes[seat];
          if (!arm.contains(x) || !arm.contains(y) || x == y) throw GameError('只能交换自己阵地的棋子');
          if (b[x] == null || b[y] == null) throw GameError('只能交换两枚棋子');
          final t = b[x];
          b[x] = b[y];
          b[y] = t;
          final err = layoutError(seat);
          if (err != null) {
            b[y] = b[x];
            b[x] = t;
            throw GameError(err);
          }
        case 'random':
          randomLayout(seat);
        case 'ready':
          ready[seat] = true;
          if (ready.every((r) => r)) _beginBattle();
        default:
          throw GameError('布阵阶段只能交换棋子或准备');
      }
      return;
    }
    if (type == 'resign') {
      if (!alive[seat]) throw GameError('你已出局');
      _resign(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'flip') {
      if (!flip) throw GameError('无效操作');
      final n = asInt(a['node']);
      if (n < 0 || n >= b.length || b[n] == null || b[n]!.up) throw GameError('只能翻开背面朝上的棋子');
      final p = b[n]!..up = true;
      if (colorOf[seat] < 0) {
        colorOf[seat] = p.owner;
        colorOf[1 - seat] = 1 - p.owner;
        host.log('${name(seat)} 执${p.owner == 0 ? "红" : "蓝"}方，${name(1 - seat)} 执${p.owner == 0 ? "蓝" : "红"}方');
      }
      last = {'seat': seat, 'from': -1, 'to': n, 'res': 'flip'};
      publicLog.add({'t': 'flip', 's': seat, 'n': n, 'o': p.owner, 'k': p.rank});
      _afterPly();
      return;
    }
    if (type != 'move') throw GameError('无效操作');
    final from = asInt(a['from']), to = asInt(a['to']);
    final moves = legalMoves(seat);
    if (!(moves[from]?.contains(to) ?? false)) throw GameError('不能这样走');
    execute(seat, from, to);
    if (phase == 1) _afterPly();
  }

  void _captureStart() {
    startViews = [for (var s = 0; s < players; s++) view(s)['board'] as List];
  }

  final List<Map<String, dynamic>> _pendingReveals = [];

  void _lose(JP p) {
    final s = seatOf(p);
    if (s >= 0) lost[s].add(p.rank);
    if (p.rank == kCmd && !flip) {
      for (var i = 0; i < b.length; i++) {
        final q = b[i];
        if (q != null && q.owner == p.owner && q.rank == kFlag && !q.up) {
          q.up = true;
          _pendingReveals.add({'t': 'flagshown', 'o': p.owner, 'n': i});
          host.log('${name(p.owner)} 的司令阵亡，亮出军旗');
        }
      }
    }
  }

  /// Applies a legal move (no turn bookkeeping). Returns the result code.
  String execute(int seat, int from, int to) {
    final p = b[from]!;
    final q = b[to];
    p.moved = true;
    String res;
    if (q == null) {
      b[to] = p;
      b[from] = null;
      res = 'move';
    } else {
      final r = junqiBattle(p.rank, q.rank);
      if (q.rank == kFlag) {
        b[to] = p;
        b[from] = null;
        res = 'flag';
      } else if (r == 1) {
        b[to] = p;
        b[from] = null;
        p.kills++;
        res = 'win';
        _lose(q);
      } else if (r == -1) {
        b[from] = null;
        q.kills++;
        res = 'lose';
        _lose(p);
      } else {
        b[from] = null;
        b[to] = null;
        res = 'tie';
        _lose(p);
        _lose(q);
      }
    }
    last = {'seat': seat, 'from': from, 'to': to, 'res': res};
    publicLog.add({'t': 'mv', 's': seat, 'f': from, 'to': to, 'r': res});
    publicLog.addAll(_pendingReveals);
    _pendingReveals.clear();
    if (res == 'flag') {
      final victim = seatOf(q!);
      host.log('${name(seat)} 夺取了 ${name(victim)} 的军旗！');
      _eliminate(victim, '军旗被夺');
    }
    return res;
  }

  void _afterPly() {
    plies++;
    if (phase != 1) return;
    if (plies >= cap) {
      _end([], '达到 $cap 步上限，和棋');
      return;
    }
    _nextTurn();
  }

  bool _hasAction(int seat) {
    if (flip && b.any((p) => p != null && !p.up)) return true;
    return legalMoves(seat).isNotEmpty;
  }

  void _nextTurn() {
    var t = turn;
    for (var guard = 0; guard < 16 && phase == 1; guard++) {
      t = (t + 1) % players;
      if (!alive[t]) continue;
      turn = t;
      if (_hasAction(t)) return;
      _eliminate(t, '无棋可走');
    }
  }

  void _checkTurn() {
    if (!_hasAction(turn)) {
      _eliminate(turn, '无棋可走');
      if (phase == 1) _nextTurn();
    }
  }

  void _eliminate(int s, String why) {
    if (!alive[s]) return;
    alive[s] = false;
    publicLog.add({'t': 'out', 's': s});
    host.log('${name(s)} $why，出局');
    if (!four) {
      _end([1 - s], '${name(1 - s)} 获胜（${name(s)} $why）');
      return;
    }
    for (var i = 0; i < b.length; i++) {
      if (b[i] != null && b[i]!.owner == s) b[i] = null;
    }
    for (var t = 0; t < 2; t++) {
      if (!alive[t] && !alive[t + 2]) {
        final w = [1 - t, 3 - t];
        _end(w, '${name(w[0])} 与 ${name(w[1])} 获胜');
        return;
      }
    }
  }

  void _end(List<int> w, String text) {
    phase = 2;
    winners = w;
    result = text;
    host.log(text);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final cells = <Map<String, dynamic>?>[];
    for (final p in b) {
      if (p == null) {
        cells.add(null);
        continue;
      }
      final bool vis;
      if (phase == 2) {
        vis = true;
      } else if (flip) {
        vis = p.up;
      } else {
        vis = p.up || (seat >= 0 && team(p.owner) == team(seat));
      }
      cells.add({
        'o': flip && !p.up && phase != 2 ? -1 : p.owner,
        'k': vis ? p.rank : -1,
        'u': p.up,
      });
    }
    final myTurn = phase == 1 && seat == turn && seat >= 0;
    return {
      'mode': mode,
      'phase': phase,
      'turn': turn,
      'ready': ready,
      'alive': alive,
      'colors': colorOf,
      'board': cells,
      'moves': myTurn ? {for (final e in legalMoves(seat).entries) '${e.key}': e.value} : <String, dynamic>{},
      'canFlip': myTurn && flip,
      'last': last,
      'plies': plies,
      'cap': cap,
      'winners': winners,
      'result': result,
      'lost': seat >= 0 && !flip ? lost[seat] : <int>[],
      'error': phase == 0 && seat >= 0 ? layoutError(seat) : null,
    };
  }

  // ---------------------------------------------------------------- bots

  @override
  Map<String, dynamic>? bot(int seat) => botWith(seat, rng);

  /// Bot decision using [r] for randomness. Only uses view(seat), [startViews]
  /// and [publicLog] — never the hidden identities on the board.
  Map<String, dynamic>? botWith(int seat, Random r) {
    if (phase == 0) return ready[seat] ? null : {'type': 'ready'};
    if (phase != 1 || seat != turn) return null;
    final v = view(seat);
    if (botLevel <= 0 && r.nextDouble() < 0.55) {
      final rnd = _randomAction(v, r);
      if (rnd != null) return rnd;
    }
    // 困难: less noise on top of the expected-value evaluation
    final noise = botLevel >= 2 ? 0.4 : 3.0;
    if (flip) return junqiFlipDecide(geo, seat, v, publicLog, r, noise: noise);
    final mind = _minds.putIfAbsent(seat, () => JunqiMind(geo, four, seat, startViews[seat]!));
    mind.update(publicLog);
    return mind.decide(v, r, noise: noise);
  }

  /// 简单: a random legal action taken from the seat's own view only.
  Map<String, dynamic>? _randomAction(Map<String, dynamic> v, Random r) {
    final board = v['board'] as List;
    final moves = (v['moves'] as Map).entries.toList();
    final downs = [
      for (var i = 0; i < board.length; i++)
        if (flip && board[i] != null && (board[i] as Map)['u'] == false) i
    ];
    if (downs.isNotEmpty && (moves.isEmpty || r.nextInt(3) == 0)) {
      return {'type': 'flip', 'node': downs[r.nextInt(downs.length)]};
    }
    if (moves.isEmpty) return null;
    final e = moves[r.nextInt(moves.length)];
    final tos = e.value as List;
    return {'type': 'move', 'from': int.parse(e.key as String), 'to': tos[r.nextInt(tos.length)]};
  }
}
