import '../../src/engine.dart';

/// 六子棋：19×19，黑方第一手下 1 子，之后双方每回合下 2 子，先连成六子者胜。
/// cells[y*19+x]：0 空，1 黑，2 白。
class Connect6 extends GameEngine {
  Connect6(super.setup);

  static const n = 19;
  static const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];

  final List<int> cells = List.filled(n * n, 0);
  int blackSeat = 0;
  int turn = 0;
  int stonesLeft = 1; // 本回合还需下几子
  List<int> lastTurn = []; // 对手上一回合落下的子
  List<int> thisTurn = []; // 本回合已落下的子
  int moves = 0;
  int winner = -1; // 0/1，2 = 和棋
  List<int> winLine = [];
  String result = '';
  bool get over => winner != -1;

  int colorOf(int seat) => seat == blackSeat ? 1 : 2;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];
  @override
  int get botDelayMs => 500;

  @override
  void start() {
    blackSeat = rng.nextInt(2);
    turn = blackSeat;
    host.log('六子棋：${name(blackSeat)} 执黑先行（首手一子，此后每回合两子）');
  }

  static List<int>? lineAt(List<int> cells, int p) {
    final color = cells[p];
    if (color == 0) return null;
    final x0 = p % n, y0 = p ~/ n;
    for (final (dx, dy) in dirs) {
      final pts = [p];
      for (final sg in const [1, -1]) {
        var x = x0 + dx * sg, y = y0 + dy * sg;
        while (x >= 0 && y >= 0 && x < n && y < n && cells[y * n + x] == color) {
          pts.add(y * n + x);
          x += dx * sg;
          y += dy * sg;
        }
      }
      if (pts.length >= 6) return pts..sort();
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') {
      resign(seat);
      return;
    }
    if (seat != turn) throw GameError('还没轮到你');
    final p = asInt(a['point']);
    if (p < 0 || p >= n * n) throw GameError('无效的位置');
    if (cells[p] != 0) throw GameError('这里已经有棋子了');
    cells[p] = colorOf(seat);
    thisTurn.add(p);
    moves++;
    stonesLeft--;
    final l = lineAt(cells, p);
    if (l != null) {
      winner = seat;
      winLine = l;
      result = '${name(seat)}（${colorOf(seat) == 1 ? '黑' : '白'}）六子连珠获胜';
      host.log(result);
      return;
    }
    if (moves == n * n) {
      winner = 2;
      result = '棋盘已满，和棋';
      host.log(result);
      return;
    }
    if (stonesLeft == 0) {
      lastTurn = thisTurn;
      thisTurn = [];
      turn = 1 - turn;
      stonesLeft = 2;
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
        'board': cells,
        'blackSeat': blackSeat,
        'turn': turn,
        'stonesLeft': stonesLeft,
        'lastTurn': lastTurn,
        'thisTurn': thisTurn,
        'moves': moves,
        'winner': winner,
        'winLine': winLine,
        'result': over ? result : null,
        'over': over,
      };

  // ---------------- AI ----------------
  static List<List<int>>? _windows;
  static List<List<int>> get windows {
    if (_windows != null) return _windows!;
    final w = <List<int>>[];
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        for (final (dx, dy) in dirs) {
          final ex = x + dx * 5, ey = y + dy * 5;
          if (ex < 0 || ey < 0 || ex >= n || ey >= n) continue;
          w.add([for (var k = 0; k < 6; k++) (y + dy * k) * n + x + dx * k]);
        }
      }
    }
    return _windows = w;
  }

  static const _atk = [0, 2, 30, 400, 400, 1200, 0];
  static const _def = [0, 1, 6, 30, 900, 3000, 0];

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final me = colorOf(seat);
    if (botLevel <= 0 && rng.nextInt(100) < 45) {
      // 简单：经常随手落在已有棋子附近
      final near = <int>[];
      for (var p = 0; p < n * n; p++) {
        if (cells[p] != 0) continue;
        final x = p % n, y = p ~/ n;
        var ok = false;
        for (var dy = -2; dy <= 2 && !ok; dy++) {
          for (var dx = -2; dx <= 2 && !ok; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx >= 0 && yy >= 0 && xx < n && yy < n && cells[yy * n + xx] != 0) ok = true;
          }
        }
        if (ok) near.add(p);
      }
      if (near.isNotEmpty) return {'type': 'play', 'point': near[rng.nextInt(near.length)]};
    }
    if (botLevel >= 2) return {'type': 'play', 'point': chooseStoneHard(cells, me, stonesLeft, rng.nextInt(1 << 30))};
    return {'type': 'play', 'point': chooseStone(cells, me, stonesLeft, rng.nextInt(1 << 30))};
  }

  /// 选择下一颗子（每次只决定一颗，本回合第二子会基于新局面再算）。
  static int chooseStone(List<int> cells, int me, int stonesLeft, int salt) {
    final opp = 3 - me;
    if (cells.every((c) => c == 0)) return (n ~/ 2) * n + n ~/ 2;
    // 1) 能赢则赢
    for (final w in windows) {
      var mine = 0, bad = false, empty = -1;
      for (final p in w) {
        if (cells[p] == me) {
          mine++;
        } else if (cells[p] == opp) {
          bad = true;
          break;
        } else {
          empty = p;
        }
      }
      if (!bad && mine >= 6 - stonesLeft && empty >= 0) return empty;
    }
    // 2) 统计每个空点的攻防分，以及对手威胁（≥4 子且无我子的窗口）
    final score = List.filled(n * n, 0);
    final threatHits = List.filled(n * n, 0);
    var threats = 0;
    for (final w in windows) {
      var mine = 0, theirs = 0;
      for (final p in w) {
        final c = cells[p];
        if (c == me) {
          mine++;
        } else if (c == opp) {
          theirs++;
        }
      }
      if (mine > 0 && theirs > 0) continue;
      final v = theirs == 0 ? _atk[mine] : _def[theirs];
      if (theirs >= 4) threats++;
      for (final p in w) {
        if (cells[p] != 0) continue;
        score[p] += v;
        if (theirs >= 4) threatHits[p]++;
      }
    }
    var best = -1, bestV = -1;
    for (var p = 0; p < n * n; p++) {
      if (cells[p] != 0) continue;
      var v = score[p];
      if (threats > 0) v += threatHits[p] * 100000;
      // 靠近中心略加分，打破平局
      final x = p % n, y = p ~/ n;
      v = v * 4 + (18 - (x - 9).abs() - (y - 9).abs()) ~/ 6;
      v = v * 8 + ((p * 2654435761 + salt) & 7);
      if (v > bestV) {
        bestV = v;
        best = p;
      }
    }
    return best;
  }

  /// 困难：枚举本回合两子的组合（启发式前若干候选），按“对方下回合能否连六 /
  /// 我方威胁能否被两子挡住 / 窗口价值”评估，选最好的一对并先下其中一子。
  static int chooseStoneHard(List<int> cells, int me, int stonesLeft, int salt) {
    if (cells.every((c) => c == 0)) return (n ~/ 2) * n + n ~/ 2;
    final base = chooseStone(cells, me, stonesLeft, salt);
    final c = List.of(cells);
    c[base] = me;
    if (lineAt(c, base) != null) return base;
    c[base] = 0;
    final firsts = _topCandidates(cells, me, 12, salt);
    if (!firsts.contains(base)) firsts.insert(0, base);
    var best = base;
    var bestV = -double.maxFinite;
    for (final p in firsts) {
      c[p] = me;
      if (lineAt(c, p) != null) return p;
      double v;
      if (stonesLeft == 2) {
        v = -double.maxFinite;
        final seconds = _topCandidates(c, me, 8, salt);
        final g = chooseStone(c, me, 1, salt);
        if (!seconds.contains(g)) seconds.insert(0, g);
        for (final q in seconds) {
          if (c[q] != 0) continue;
          c[q] = me;
          final w = lineAt(c, q) != null ? 1e12 : _evalBoard(c, me);
          c[q] = 0;
          if (w > v) v = w;
        }
      } else {
        v = _evalBoard(c, me);
      }
      c[p] = 0;
      if (p == base) v += 0.5;
      if (v > bestV) {
        bestV = v;
        best = p;
      }
    }
    return best;
  }

  static const _evAtk = [0.0, 1.0, 6.0, 40.0, 150.0, 200.0, 0.0];

  /// 对方即将行棋（两子）时的局面评估（me 视角）。
  static double _evalBoard(List<int> cells, int me) {
    final opp = 3 - me;
    var v = 0.0;
    final threats = <List<int>>[]; // 我方 ≥4 子窗口的空点
    for (final w in windows) {
      var a = 0, b = 0;
      for (final p in w) {
        final x = cells[p];
        if (x == me) {
          a++;
        } else if (x == opp) {
          b++;
        }
      }
      if (a > 0 && b > 0) continue;
      if (b == 0 && a > 0) {
        if (a >= 4) threats.add([for (final p in w) if (cells[p] == 0) p]);
        v += _evAtk[a];
      } else if (a == 0 && b > 0) {
        if (b >= 4) return -1e10; // 对方下回合直接连六
        v -= _evAtk[b] * 1.6;
      }
    }
    if (threats.isNotEmpty) {
      // 对方能否用两子挡住全部威胁？
      final pts = <int>{for (final t in threats) ...t}.toList();
      var blockable = false;
      for (var i = 0; i < pts.length && !blockable; i++) {
        for (var j = i; j < pts.length && !blockable; j++) {
          if (threats.every((t) => t.contains(pts[i]) || t.contains(pts[j]))) blockable = true;
        }
      }
      if (!blockable) return 1e9;
      v += threats.length * 30;
    }
    return v;
  }
  static List<int> _topCandidates(List<int> cells, int me, int k, int salt) {
    final opp = 3 - me;
    final score = List.filled(n * n, 0);
    for (final w in windows) {
      var mine = 0, theirs = 0;
      for (final p in w) {
        final c = cells[p];
        if (c == me) {
          mine++;
        } else if (c == opp) {
          theirs++;
        }
      }
      if (mine > 0 && theirs > 0) continue;
      if (mine == 0 && theirs == 0) continue;
      final v = theirs == 0 ? _atk[mine] : _def[theirs];
      for (final p in w) {
        if (cells[p] == 0) score[p] += v;
      }
    }
    final idx = [for (var p = 0; p < n * n; p++) if (cells[p] == 0 && score[p] > 0) p];
    idx.sort((a, b) {
      final d = score[b].compareTo(score[a]);
      return d != 0 ? d : ((a * 2654435761 + salt) & 7).compareTo((b * 2654435761 + salt) & 7);
    });
    return idx.take(k).toList();
  }
}
