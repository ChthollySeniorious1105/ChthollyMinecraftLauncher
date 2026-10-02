import '../../src/engine.dart';

/// 六角棋（Hex）。cells[r*n+c]：0 空，1 红（连接上下两边），2 蓝（连接左右两边）。
/// 红方先行。可选交换规则：红方第一手后，蓝方可选择“交换”，双方互换颜色。
class HexBoard {
  final int n;
  final List<int> cells;
  HexBoard(this.n) : cells = List.filled(n * n, 0);
  HexBoard.of(this.n, List<int> c) : cells = List.of(c);

  static const _nb = [(-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0)];

  Iterable<int> neighbors(int p) sync* {
    final r = p ~/ n, c = p % n;
    for (final (dr, dc) in _nb) {
      final rr = r + dr, cc = c + dc;
      if (rr >= 0 && cc >= 0 && rr < n && cc < n) yield rr * n + cc;
    }
  }

  bool _startEdge(int color, int p) => color == 1 ? p ~/ n == 0 : p % n == 0;
  bool _endEdge(int color, int p) => color == 1 ? p ~/ n == n - 1 : p % n == n - 1;

  /// 若 color 已连通，返回连接路径（棋子集合）。
  List<int>? winPath(int color) {
    final prev = List.filled(n * n, -2);
    final q = <int>[];
    for (var p = 0; p < n * n; p++) {
      if (cells[p] == color && _startEdge(color, p)) {
        prev[p] = -1;
        q.add(p);
      }
    }
    for (var i = 0; i < q.length; i++) {
      final p = q[i];
      if (_endEdge(color, p)) {
        final path = <int>[];
        for (var x = p; x != -1; x = prev[x]) {
          path.add(x);
        }
        return path;
      }
      for (final m in neighbors(p)) {
        if (prev[m] == -2 && cells[m] == color) {
          prev[m] = p;
          q.add(m);
        }
      }
    }
    return null;
  }

  static const _inf = 1 << 20;

  /// 双距离（two-distance）势场：从 color 的起始边(fromStart)或终止边出发。
  List<int> twoDistance(int color, bool fromStart) {
    final opp = 3 - color;
    final d = List.filled(n * n, _inf);
    var changed = true;
    var iter = 0;
    while (changed && iter < n * n) {
      changed = false;
      iter++;
      for (var p = 0; p < n * n; p++) {
        if (cells[p] == opp) continue;
        var m1 = _inf, m2 = _inf;
        void offer(int v) {
          if (v < m1) {
            m2 = m1;
            m1 = v;
          } else if (v < m2) {
            m2 = v;
          }
        }

        final edge = fromStart ? _startEdge(color, p) : _endEdge(color, p);
        if (edge) {
          offer(0);
          offer(0);
        }
        for (final q in neighbors(p)) {
          offer(d[q]);
        }
        int nv;
        if (cells[p] == color) {
          nv = m1;
        } else {
          nv = m2 >= _inf ? _inf : m2 + 1;
        }
        if (nv < d[p]) {
          d[p] = nv;
          changed = true;
        }
      }
    }
    return d;
  }

  /// 势能：越小越接近连通。返回 (最小势能, 达到最小势能的格子数)。
  (int, int) potential(int color) {
    final a = twoDistance(color, true), b = twoDistance(color, false);
    var best = _inf, cnt = 0;
    for (var p = 0; p < n * n; p++) {
      if (cells[p] != 0) continue;
      final v = a[p] + b[p];
      if (v < best) {
        best = v;
        cnt = 1;
      } else if (v == best) {
        cnt++;
      }
    }
    return (best, cnt);
  }

  double evaluate(int color) {
    if (winPath(color) != null) return 1e6;
    if (winPath(3 - color) != null) return -1e6;
    final (pm, cm) = potential(color);
    final (po, co) = potential(3 - color);
    return (po - pm) * 100.0 + (cm - co);
  }
}

class Hex extends GameEngine {
  Hex(super.setup);

  late final int n = setup.opt<int>('size', 11);
  late final bool swapRule = setup.opt<bool>('swap', true);
  late HexBoard board = HexBoard(n);
  int redSeat = 0;
  int turn = 0;
  int moves = 0;
  int last = -1;
  bool swapped = false;
  int winner = -1;
  List<int> winPath = [];
  String result = '';
  bool get over => winner != -1;

  int colorOf(int seat) => seat == redSeat ? 1 : 2;
  bool get canSwap => swapRule && moves == 1 && !swapped && !over;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];
  @override
  int get botDelayMs => 500;

  @override
  void start() {
    redSeat = rng.nextInt(2);
    turn = redSeat;
    host.log('六角棋 $n×$n：${name(redSeat)} 执红先行（连接上下），${name(1 - redSeat)} 执蓝（连接左右）'
        '${swapRule ? '；启用交换规则' : ''}');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (type == 'resign') {
      resign(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    if (type == 'swap') {
      if (!canSwap) throw GameError('现在不能交换');
      swapped = true;
      redSeat = seat;
      turn = 1 - seat;
      host.log('${name(seat)} 选择交换，改为执红；${name(turn)} 改执蓝');
      return;
    }
    final p = asInt(a['point']);
    if (p < 0 || p >= n * n) throw GameError('无效的位置');
    if (board.cells[p] != 0) throw GameError('这里已经有棋子了');
    final color = colorOf(seat);
    board.cells[p] = color;
    moves++;
    last = p;
    final path = board.winPath(color);
    if (path != null) {
      winner = seat;
      winPath = path;
      result = '${name(seat)}（${color == 1 ? '红' : '蓝'}）连通两边获胜';
      host.log(result);
      return;
    }
    turn = 1 - turn;
  }

  @override
  List<int>? get placings => !over ? null : (winner == 2 ? [1, 1] : [winner == 0 ? 1 : 2, winner == 1 ? 1 : 2]);

  @override
  bool get canResign => !over;
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat != 0 && seat != 1) throw GameError('你不是棋手');
    host.log('${name(seat)} 认输');
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
        'size': n,
        'board': board.cells,
        'redSeat': redSeat,
        'turn': turn,
        'moves': moves,
        'last': last,
        'swapRule': swapRule,
        'canSwap': canSwap,
        'swapped': swapped,
        'winner': winner,
        'winPath': winPath,
        'result': over ? result : null,
        'over': over,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final color = colorOf(seat);
    final c = n ~/ 2;
    if (moves == 0) {
      // 有交换规则时不下天元，下一个中等强度的点
      final p = swapRule ? (1 + rng.nextInt(2)) * n + (n - 2 - rng.nextInt(2)) : c * n + c;
      return {'type': 'play', 'point': p};
    }
    if (canSwap) {
      final r = last ~/ n, col = last % n;
      final central = (r - c).abs() + (col - c).abs() <= n ~/ 3 + 1;
      if (central) return {'type': 'swap'};
    }
    if (botLevel <= 0 && rng.nextInt(100) < 50) {
      // 简单：一半概率随手下在已有棋子附近
      final near = <int>[];
      for (var p = 0; p < n * n; p++) {
        if (board.cells[p] == 0 && board.neighbors(p).any((q) => board.cells[q] != 0)) near.add(p);
      }
      if (near.isNotEmpty) return {'type': 'play', 'point': near[rng.nextInt(near.length)]};
    }
    if (botLevel >= 2) return {'type': 'play', 'point': chooseHard(board, color, rng.nextInt(1 << 30))};
    return {'type': 'play', 'point': choose(board, color, rng.nextInt(1 << 30))};
  }

  static int choose(HexBoard b, int color, int salt, {int timeMs = 1500}) {
    final n = b.n;
    final sw = Stopwatch()..start();
    // 立即获胜
    for (var p = 0; p < n * n; p++) {
      if (b.cells[p] != 0) continue;
      b.cells[p] = color;
      final w = b.winPath(color) != null;
      b.cells[p] = 0;
      if (w) return p;
    }
    // 候选点：已有棋子附近 2 格 + 中心区域
    final cand = <int>{};
    var any = false;
    for (var p = 0; p < n * n; p++) {
      if (b.cells[p] == 0) continue;
      any = true;
      for (final q in b.neighbors(p)) {
        if (b.cells[q] == 0) cand.add(q);
        for (final r in b.neighbors(q)) {
          if (b.cells[r] == 0) cand.add(r);
        }
      }
    }
    if (!any) return (n ~/ 2) * n + n ~/ 2;
    final cands = cand.toList()..sort();
    var best = cands.first;
    var bestV = double.negativeInfinity;
    for (final p in cands) {
      b.cells[p] = color;
      final v = b.evaluate(color) + ((p * 2654435761 + salt) & 15) / 100.0;
      b.cells[p] = 0;
      if (v > bestV) {
        bestV = v;
        best = p;
      }
      if (sw.elapsedMilliseconds > timeMs) break;
    }
    return best;
  }

  /// 困难：对启发式最好的若干候选做 2 层极小极大（考虑对手最佳回应）。
  /// 在棋盘副本上计算，不改动真实棋盘。
  static int chooseHard(HexBoard real, int color, int salt, {int timeMs = 1200}) {
    final b = HexBoard.of(real.n, real.cells);
    final n = b.n;
    final sw = Stopwatch()..start();
    final opp = 3 - color;
    // 立即获胜
    for (var p = 0; p < n * n; p++) {
      if (b.cells[p] != 0) continue;
      b.cells[p] = color;
      final w = b.winPath(color) != null;
      b.cells[p] = 0;
      if (w) return p;
    }
    final cands = _ranked(b, color, salt, 8);
    if (cands.isEmpty) return choose(b, color, salt);
    var best = cands.first;
    var bestV = double.negativeInfinity;
    for (final p in cands) {
      b.cells[p] = color;
      var worst = double.infinity;
      if (b.winPath(color) != null) {
        worst = 1e7;
      } else {
        for (final q in _ranked(b, opp, salt, 5)) {
          b.cells[q] = opp;
          final v = b.evaluate(color);
          b.cells[q] = 0;
          if (v < worst) worst = v;
          if (worst <= bestV) break; // alpha 剪枝
        }
        if (worst == double.infinity) worst = b.evaluate(color);
      }
      b.cells[p] = 0;
      if (worst > bestV) {
        bestV = worst;
        best = p;
      }
      if (sw.elapsedMilliseconds > timeMs) break;
    }
    return best;
  }

  /// 按一步评估排序的前 k 个候选点（color 视角）。
  static List<int> _ranked(HexBoard b, int color, int salt, int k) {
    final n = b.n;
    final cand = <int>{};
    for (var p = 0; p < n * n; p++) {
      if (b.cells[p] == 0) continue;
      for (final q in b.neighbors(p)) {
        if (b.cells[q] == 0) cand.add(q);
        for (final r in b.neighbors(q)) {
          if (b.cells[r] == 0) cand.add(r);
        }
      }
    }
    final scored = <(int, double)>[];
    for (final p in cand.toList()..sort()) {
      b.cells[p] = color;
      scored.add((p, b.evaluate(color) + ((p * 2654435761 + salt) & 15) / 100.0));
      b.cells[p] = 0;
    }
    scored.sort((x, y) => y.$2.compareTo(x.$2));
    return [for (final e in scored.take(k)) e.$1];
  }
}
