import '../../src/engine.dart';

/// 九子棋（Nine Men's Morris）。24 个点位编号如下：
///  0-----------1-----------2
///  |   3-------4-------5   |
///  |   |   6---7---8   |   |
///  9--10--11       12-13--14
///  |   |  15--16--17   |   |
///  |  18------19------20   |
/// 21----------22----------23
const morrisAdj = <List<int>>[
  [1, 9], [0, 2, 4], [1, 14], [4, 10], [1, 3, 5, 7], [4, 13], [7, 11], [4, 6, 8], [7, 12], //
  [0, 10, 21], [3, 9, 11, 18], [6, 10, 15], [8, 13, 17], [5, 12, 14, 20], [2, 13, 23], //
  [11, 16], [15, 17, 19], [12, 16], [10, 19], [16, 18, 20, 22], [13, 19], [9, 22], [19, 21, 23], [14, 22],
];

const morrisMills = <List<int>>[
  [0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], //
  [0, 9, 21], [3, 10, 18], [6, 11, 15], [1, 4, 7], [16, 19, 22], [8, 12, 17], [5, 13, 20], [2, 14, 23],
];

/// 纯局面（供 AI 搜索使用）。cells: 0 空，1/2 = 座位0/1 的棋子。
class MorrisState {
  final List<int> cells;
  final List<int> inHand; // 尚未放置
  final List<int> onBoard;
  int turn;
  bool removing;
  final bool flying;
  MorrisState(this.cells, this.inHand, this.onBoard, this.turn, this.removing, this.flying);

  MorrisState clone() =>
      MorrisState(List.of(cells), List.of(inHand), List.of(onBoard), turn, removing, flying);

  int color(int s) => s + 1;
  bool placing(int s) => inHand[s] > 0;
  bool canFly(int s) => flying && inHand[s] == 0 && onBoard[s] == 3;

  bool inMill(int p) {
    final c = cells[p];
    if (c == 0) return false;
    for (final m in morrisMills) {
      if (m.contains(p) && cells[m[0]] == c && cells[m[1]] == c && cells[m[2]] == c) return true;
    }
    return false;
  }

  List<int> removable(int s) {
    final oc = color(1 - s);
    final all = [for (var p = 0; p < 24; p++) if (cells[p] == oc) p];
    final free = [for (final p in all) if (!inMill(p)) p];
    return free.isEmpty ? all : free;
  }

  /// 走法编码：放置 to；移动 from*100+to（from ≥ 0）。移除时为 5000+p。
  List<int> moves() {
    final s = turn;
    if (removing) return [for (final p in removable(s)) 5000 + p];
    final c = color(s);
    if (placing(s)) return [for (var p = 0; p < 24; p++) if (cells[p] == 0) 100 * 24 + p];
    final out = <int>[];
    final fly = canFly(s);
    for (var f = 0; f < 24; f++) {
      if (cells[f] != c) continue;
      if (fly) {
        for (var t = 0; t < 24; t++) {
          if (cells[t] == 0) out.add(f * 100 + t);
        }
      } else {
        for (final t in morrisAdj[f]) {
          if (cells[t] == 0) out.add(f * 100 + t);
        }
      }
    }
    return out;
  }

  /// 执行走法，返回是否形成新的三连（需要移除）。
  bool apply(int m) {
    final s = turn;
    if (m >= 5000) {
      cells[m - 5000] = 0;
      onBoard[1 - s]--;
      removing = false;
      turn = 1 - s;
      return false;
    }
    final from = m ~/ 100, to = m % 100;
    if (from == 24) {
      inHand[s]--;
      onBoard[s]++;
    } else {
      cells[from] = 0;
    }
    cells[to] = color(s);
    if (inMill(to)) {
      removing = true;
      return true;
    }
    turn = 1 - s;
    return false;
  }

  /// 当前行动方是否已输（棋子 < 3 或无路可走）。
  bool lost(int s) {
    if (inHand[s] + onBoard[s] < 3) return true;
    if (turn == s && !removing && !placing(s) && moves().isEmpty) return true;
    return false;
  }

  String key() => '${cells.join()}$turn${inHand[0]},${inHand[1]}$removing';
}

int morrisEval(MorrisState st, int me) {
  final o = 1 - me;
  var v = (st.onBoard[me] + st.inHand[me] - st.onBoard[o] - st.inHand[o]) * 100;
  var mobMe = 0, mobO = 0;
  for (var p = 0; p < 24; p++) {
    final c = st.cells[p];
    if (c == 0) continue;
    for (final q in morrisAdj[p]) {
      if (st.cells[q] == 0) {
        if (c == me + 1) {
          mobMe++;
        } else {
          mobO++;
        }
      }
    }
  }
  v += (mobMe - mobO) * 3;
  for (final m in morrisMills) {
    var a = 0, b = 0, e = 0;
    for (final p in m) {
      final c = st.cells[p];
      if (c == me + 1) {
        a++;
      } else if (c == o + 1) {
        b++;
      } else {
        e++;
      }
    }
    if (a == 3) v += 20;
    if (b == 3) v -= 20;
    if (a == 2 && e == 1) v += 12;
    if (b == 2 && e == 1) v -= 14;
  }
  return v;
}

class NineMensMorris extends GameEngine {
  NineMensMorris(super.setup);

  late final bool flying = setup.opt<bool>('flying', true);
  late MorrisState st;
  int firstSeat = 0;
  int lastFrom = -1, lastTo = -1, lastRemoved = -1;
  int ply = 0;
  int sinceCapture = 0;
  final Map<String, int> seen = {};
  int winner = -1;
  String result = '';
  bool get over => winner != -1;

  static const plyCap = 200;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [st.turn];
  @override
  int get botDelayMs => 600;

  @override
  void start() {
    firstSeat = rng.nextInt(2);
    st = MorrisState(List.filled(24, 0), [9, 9], [0, 0], firstSeat, false, flying);
    host.log('九子棋：${name(firstSeat)} 先手${flying ? '（剩3子可飞）' : ''}');
  }

  String phaseOf(int s) {
    if (st.removing && st.turn == s) return 'remove';
    if (st.placing(s)) return 'place';
    if (st.canFly(s)) return 'fly';
    return 'move';
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    final type = asStr(a['type']);
    if (type == 'resign') {
      resign(seat);
      return;
    }
    if (seat != st.turn) throw GameError('还没轮到你');
    int m;
    if (st.removing) {
      final p = asInt(a['point']);
      if (p < 0 || p >= 24 || st.cells[p] != 2 - seat) throw GameError('请选择对方的一枚棋子移除');
      if (!st.removable(seat).contains(p)) throw GameError('不能移除三连中的棋子（除非对方全部棋子都在三连中）');
      m = 5000 + p;
    } else if (st.placing(seat)) {
      final p = asInt(a['point']);
      if (p < 0 || p >= 24 || st.cells[p] != 0) throw GameError('请选择一个空位放置');
      m = 2400 + p;
    } else {
      final f = asInt(a['from']), t = asInt(a['to']);
      if (f < 0 || f >= 24 || st.cells[f] != seat + 1) throw GameError('请先选择自己的棋子');
      if (t < 0 || t >= 24 || st.cells[t] != 0) throw GameError('目标必须是空位');
      if (!st.canFly(seat) && !morrisAdj[f].contains(t)) throw GameError('只能沿线移动到相邻空位');
      m = f * 100 + t;
    }
    _apply(seat, m);
  }

  void _apply(int seat, int m) {
    if (m >= 5000) {
      lastRemoved = m - 5000;
      sinceCapture = 0;
      seen.clear();
    } else {
      lastFrom = m ~/ 100 == 24 ? -1 : m ~/ 100;
      lastTo = m % 100;
      lastRemoved = -1;
      sinceCapture++;
    }
    final mill = st.apply(m);
    ply++;
    if (mill) host.log('${name(seat)} 形成三连，移除对方一子');
    if (st.removing) return;
    final o = st.turn;
    if (st.lost(o)) {
      final why = st.inHand[o] + st.onBoard[o] < 3 ? '${name(o)} 只剩两子' : '${name(o)} 无子可动';
      _finish(1 - o, why);
      return;
    }
    if (st.inHand[0] == 0 && st.inHand[1] == 0) {
      final k = st.key();
      final c = (seen[k] ?? 0) + 1;
      seen[k] = c;
      if (c >= 3) {
        _finish(2, '同一局面重复三次，和棋');
        return;
      }
    }
    if (ply >= plyCap) {
      _finish(2, '已达 $plyCap 手，和棋');
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
    _finish(1 - seat, '${name(seat)} 认输');
  }

  @override
  bool get canDraw => !over;
  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    _finish(2, '双方同意和棋');
  }

  void _finish(int w, String why) {
    winner = w;
    result = w == 2 ? why : '${name(w)} 获胜（$why）';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final moves = over ? <int>[] : st.moves();
    return {
      'board': st.cells,
      'inHand': st.inHand,
      'onBoard': st.onBoard,
      'turn': st.turn,
      'firstSeat': firstSeat,
      'phase': over ? 'over' : phaseOf(st.turn),
      'flying': flying,
      'removable': st.removing ? [for (final m in moves) m - 5000] : <int>[],
      'moves': [
        if (!st.removing && !st.placing(st.turn))
          for (final m in moves) [m ~/ 100, m % 100]
      ],
      'lastFrom': lastFrom,
      'lastTo': lastTo,
      'lastRemoved': lastRemoved,
      'ply': ply,
      'plyCap': plyCap,
      'winner': winner,
      'result': over ? result : null,
      'over': over,
    };
  }

  // ---------------- AI ----------------
  Stopwatch? _sw;
  bool _aborted = false;

  int? _bestAt(int seat, List<int> ms, int depth) {
    var best = ms.first, bestV = -1 << 30;
    for (final m in ms) {
      final c = st.clone();
      final mill = c.apply(m);
      final v = _search(c, mill ? depth : depth - 1, -1 << 30, 1 << 30, seat) + rng.nextInt(3);
      if (_aborted) return null;
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }

  /// 困难：限时迭代加深（不超过约 1 秒）。
  int _deepBest(int seat, List<int> ms, int start) {
    _sw = Stopwatch()..start();
    _aborted = false;
    try {
      var best = _bestAt(seat, ms, start - 1) ?? ms.first;
      for (var d = start; d <= start + 4; d++) {
        final b = _bestAt(seat, ms, d);
        if (b == null) break;
        best = b;
        if (_sw!.elapsedMilliseconds > 350) break;
      }
      return best;
    } finally {
      _sw = null;
      _aborted = false;
    }
  }

  int _search(MorrisState s, int depth, int alpha, int beta, int me) {
    final sw = _sw;
    if (sw != null && (_aborted || sw.elapsedMilliseconds > 1000)) {
      _aborted = true;
      return 0;
    }
    if (!s.removing) {
      final t = s.turn;
      if (s.lost(t)) return t == me ? -500000 - depth : 500000 + depth;
    }
    if (depth <= 0) return morrisEval(s, me);
    final maxing = s.turn == me;
    var best = maxing ? -1 << 30 : 1 << 30;
    final ms = s.moves();
    for (final m in ms) {
      final c = s.clone();
      final mill = c.apply(m);
      // 移除一步不消耗深度
      final v = _search(c, mill ? depth : depth - 1, alpha, beta, me);
      if (maxing) {
        if (v > best) best = v;
        if (best > alpha) alpha = best;
      } else {
        if (v < best) best = v;
        if (best < beta) beta = best;
      }
      if (alpha >= beta) break;
    }
    return best;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != st.turn) return null;
    final ms = st.moves();
    if (ms.isEmpty) return null;
    final fly = st.canFly(seat) || st.canFly(1 - seat);
    int best;
    if (botLevel <= 0 && rng.nextInt(100) < 45) {
      // 简单：接近一半概率随手走
      best = ms[rng.nextInt(ms.length)];
    } else if (botLevel >= 2) {
      best = _deepBest(seat, ms, fly ? 4 : 5);
    } else {
      best = _bestAt(seat, ms, botLevel <= 0 ? 1 : (fly ? 3 : 4))!;
    }
    if (best >= 5000) return {'type': 'remove', 'point': best - 5000};
    if (best ~/ 100 == 24) return {'type': 'place', 'point': best % 100};
    return {'type': 'move', 'from': best ~/ 100, 'to': best % 100};
  }
}
