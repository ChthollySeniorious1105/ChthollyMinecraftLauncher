import '../../src/engine.dart';

/// 斗兽棋: 7 columns × 9 rows. Seat 0 starts at the bottom (rows 6..8), seat 1 at the top.
const animalNames = {8: '象', 7: '狮', 6: '虎', 5: '豹', 4: '狼', 3: '狗', 2: '猫', 1: '鼠'};

class AnimalChess extends GameEngine {
  AnimalChess(super.setup);

  static const w = 7, h = 9, cap = 300;
  static int idx(int r, int c) => r * w + c;

  static bool isWater(int i) {
    final r = i ~/ w, c = i % w;
    return r >= 3 && r <= 5 && (c == 1 || c == 2 || c == 4 || c == 5);
  }

  /// Den of [seat].
  static int den(int seat) => seat == 0 ? idx(8, 3) : idx(0, 3);

  /// Traps owned by [seat] (around its den).
  static List<int> traps(int seat) =>
      seat == 0 ? [idx(8, 2), idx(8, 4), idx(7, 3)] : [idx(0, 2), idx(0, 4), idx(1, 3)];

  /// cells: -1 empty, else owner*10 + rank.
  final List<int> cells = List.filled(w * h, -1);
  int turn = 0;
  int plies = 0;
  int winner = -1; // -1 none, 0/1 seat, 2 draw
  String result = '';
  Map<String, dynamic>? last;

  static List<int> initial() {
    final c = List.filled(w * h, -1);
    const top = {
      (0, 0): 7, (0, 6): 6, (1, 1): 3, (1, 5): 2,
      (2, 0): 1, (2, 2): 5, (2, 4): 4, (2, 6): 8,
    };
    top.forEach((pos, rank) {
      c[idx(pos.$1, pos.$2)] = 10 + rank;
      c[idx(8 - pos.$1, 6 - pos.$2)] = rank;
    });
    return c;
  }

  @override
  void start() {
    cells.setAll(0, initial());
    turn = 0;
    host.log('${name(0)} 执红（下方）先走，${name(1)} 执蓝（上方）');
  }

  @override
  bool get isOver => winner != -1;

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  @override
  List<int>? get placings => !isOver ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('你不是玩家');
    host.log('${name(seat)} 认输');
    _end(1 - seat, '${name(1 - seat)} 获胜（${name(seat)} 认输）');
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) throw GameError('对局已结束');
    _end(2, '双方同意和棋');
  }

  /// Effective rank of a piece standing on [at] (0 in an enemy trap).
  static int power(List<int> b, int at) {
    final p = b[at];
    final owner = p ~/ 10;
    if (traps(1 - owner).contains(at)) return 0;
    return p % 10;
  }

  static bool canCapture(List<int> b, int from, int to) {
    final a = b[from] % 10, d = b[to] % 10;
    if (isWater(from) != isWater(to)) return false; // no capture across water edge
    final pd = power(b, to);
    if (a == 1 && d == 8) return !isWater(from);
    if (a == 8 && d == 1) return false;
    return a >= pd;
  }

  static List<int> targets(List<int> b, int from) {
    final p = b[from];
    if (p < 0) return const [];
    final owner = p ~/ 10, rank = p % 10;
    final out = <int>[];
    final r0 = from ~/ w, c0 = from % w;
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      var r = r0 + dr, c = c0 + dc;
      if (r < 0 || r >= h || c < 0 || c >= w) continue;
      var to = idx(r, c);
      if (isWater(to)) {
        if (rank == 1) {
          // rat swims
        } else if (rank == 6 || rank == 7) {
          var blocked = false;
          while (r >= 0 && r < h && c >= 0 && c < w && isWater(idx(r, c))) {
            if (b[idx(r, c)] >= 0) blocked = true;
            r += dr;
            c += dc;
          }
          if (blocked) continue;
          to = idx(r, c);
        } else {
          continue;
        }
      }
      if (to == den(owner)) continue;
      final q = b[to];
      if (q >= 0) {
        if (q ~/ 10 == owner) continue;
        if (!canCapture(b, from, to)) continue;
      }
      out.add(to);
    }
    return out;
  }

  static Map<int, List<int>> legal(List<int> b, int seat) {
    final m = <int, List<int>>{};
    for (var i = 0; i < b.length; i++) {
      if (b[i] >= 0 && b[i] ~/ 10 == seat) {
        final t = targets(b, i);
        if (t.isNotEmpty) m[i] = t;
      }
    }
    return m;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    if (asStr(a['type']) == 'resign') {
      _end(1 - seat, '${name(seat)} 认输，${name(1 - seat)} 获胜');
      return;
    }
    final from = asInt(a['from']), to = asInt(a['to']);
    if (from < 0 || from >= cells.length || cells[from] < 0 || cells[from] ~/ 10 != seat) {
      throw GameError('请选择自己的棋子');
    }
    if (!targets(cells, from).contains(to)) throw GameError('不能这样走');
    final cap = cells[to];
    final mover = cells[from];
    cells[to] = mover;
    cells[from] = -1;
    last = {'from': from, 'to': to, 'cap': cap < 0 ? -1 : cap};
    if (cap >= 0) host.log('${name(seat)} 的${animalNames[mover % 10]} 吃掉了${animalNames[cap % 10]}');
    plies++;
    if (to == den(1 - seat)) {
      _end(seat, '${name(seat)} 攻入兽穴，获胜！');
      return;
    }
    final opp = 1 - seat;
    if (legal(cells, opp).isEmpty) {
      _end(seat, '${name(opp)} 无子可走，${name(seat)} 获胜！');
      return;
    }
    if (plies >= AnimalChess.cap) {
      _end(2, '达到 ${AnimalChess.cap} 步上限，和棋');
      return;
    }
    turn = opp;
  }

  void _end(int w, String text) {
    winner = w;
    result = text;
    host.log(text);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'cells': cells,
        'turn': turn,
        'winner': winner,
        'result': result,
        'last': last,
        'plies': plies,
        'cap': cap,
        'moves': !isOver && seat == turn
            ? {for (final e in legal(cells, seat).entries) '${e.key}': e.value}
            : <String, dynamic>{},
      };

  // ---------------------------------------------------------------- bot

  static const _val = {8: 100, 7: 90, 6: 80, 5: 45, 4: 35, 3: 30, 2: 25, 1: 40};

  static int _distDen(int at, int seat) {
    final d = den(1 - seat);
    return (at ~/ w - d ~/ w).abs() + (at % w - d % w).abs();
  }

  double _eval(List<int> b, int seat) {
    var s = 0.0;
    for (var i = 0; i < b.length; i++) {
      final p = b[i];
      if (p < 0) continue;
      final o = p ~/ 10;
      final v = _val[p % 10]! + (12 - _distDen(i, o)) * 1.5;
      s += o == seat ? v : -v;
    }
    return s;
  }

  /// Best score for [seat] after making the move, looking one reply ahead.
  double _score(List<int> b, int seat, int from, int to) {
    final nb = List.of(b);
    nb[to] = nb[from];
    nb[from] = -1;
    if (to == den(1 - seat)) return 1e6;
    final opp = 1 - seat;
    final replies = legal(nb, opp);
    if (replies.isEmpty) return 1e5;
    var worst = 1e9;
    replies.forEach((f, ts) {
      for (final t in ts) {
        if (t == den(seat)) {
          worst = -1e6;
          continue;
        }
        final rb = List.of(nb);
        rb[t] = rb[f];
        rb[f] = -1;
        final e = _eval(rb, seat);
        if (e < worst) worst = e;
      }
    });
    return worst;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver || seat != turn) return null;
    final moves = legal(cells, seat);
    if (moves.isEmpty) return {'type': 'resign'};
    if (botLevel <= 0 && rng.nextDouble() < 0.6) {
      // 简单: mostly random legal moves, but still grabs an open den
      final all = [for (final e in moves.entries) for (final t in e.value) (e.key, t)];
      for (final (f, t) in all) {
        if (t == den(1 - seat)) return {'from': f, 'to': t};
      }
      final (f, t) = all[rng.nextInt(all.length)];
      return {'from': f, 'to': t};
    }
    if (botLevel >= 2) return _searchMove(seat, moves);
    var best = -1e18;
    Map<String, dynamic>? pick;
    moves.forEach((f, ts) {
      for (final t in ts) {
        final s = _score(cells, seat, f, t) + rng.nextDouble() * 2;
        if (s > best) {
          best = s;
          pick = {'from': f, 'to': t};
        }
      }
    });
    return pick;
  }

  // 困难: iterative-deepening alpha-beta, < ~1 s per move.
  static const _win = 1e7;

  Map<String, dynamic>? _searchMove(int seat, Map<int, List<int>> moves) {
    final sw = Stopwatch()..start();
    const budgetMs = 700;
    final root = [for (final e in moves.entries) for (final t in e.value) (e.key, t)]..shuffle(rng);
    var bestMove = root.first;
    var timeUp = false;

    double search(List<int> b, int side, int depth, double alpha, double beta) {
      if (sw.elapsedMilliseconds > budgetMs) {
        timeUp = true;
        return 0;
      }
      if (depth == 0) return _eval(b, side);
      final ms = legal(b, side);
      if (ms.isEmpty) return -_win;
      // captures and den-ward moves first
      final list = [for (final e in ms.entries) for (final t in e.value) (e.key, t)];
      list.sort((x, y) => (b[y.$2] >= 0 ? b[y.$2] % 10 : 0).compareTo(b[x.$2] >= 0 ? b[x.$2] % 10 : 0));
      var best = -1e18;
      for (final (f, t) in list) {
        if (t == den(1 - side)) return _win + depth;
        final nb = List.of(b);
        nb[t] = nb[f];
        nb[f] = -1;
        final v = -search(nb, 1 - side, depth - 1, -beta, -alpha);
        if (timeUp) return 0;
        if (v > best) best = v;
        if (v > alpha) alpha = v;
        if (alpha >= beta) break;
      }
      return best;
    }

    for (var depth = 1; depth <= 8; depth++) {
      // a deeper iteration costs several times the previous one: don't start it late
      if (depth > 2 && sw.elapsedMilliseconds * 5 > budgetMs) break;
      var best = -1e18;
      (int, int)? pick;
      // search the previous best first
      final order = [bestMove, ...root.where((m) => m != bestMove)];
      for (final (f, t) in order) {
        double v;
        if (t == den(1 - seat)) {
          v = _win * 2;
        } else {
          final nb = List.of(cells);
          nb[t] = nb[f];
          nb[f] = -1;
          v = -search(nb, 1 - seat, depth - 1, -1e18, -best);
        }
        if (timeUp) break;
        if (v > best) {
          best = v;
          pick = (f, t);
        }
      }
      if (timeUp) {
        // the previous best is searched first, so a partial result is never worse
        if (pick != null) bestMove = pick;
        break;
      }
      if (pick != null) bestMove = pick;
      if (best >= _win) break;
    }
    return {'from': bestMove.$1, 'to': bestMove.$2};
  }
}
