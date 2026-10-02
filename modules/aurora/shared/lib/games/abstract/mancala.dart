import '../../src/engine.dart';

/// 曼卡拉（Kalah）。坑位 pits[0..13]：0..5 为座位0 的小坑，6 为座位0 的仓；
/// 7..12 为座位1 的小坑，13 为座位1 的仓。逆时针播种。
class MancalaState {
  final List<int> pits;
  int turn;
  MancalaState(this.pits, this.turn);
  MancalaState clone() => MancalaState(List.of(pits), turn);

  static int store(int s) => s == 0 ? 6 : 13;
  static int first(int s) => s == 0 ? 0 : 7;

  bool legal(int pit) => pit >= first(turn) && pit < first(turn) + 6 && pits[pit] > 0;
  List<int> moves() => [for (var i = first(turn); i < first(turn) + 6; i++) if (pits[i] > 0) i];

  bool sideEmpty(int s) {
    for (var i = first(s); i < first(s) + 6; i++) {
      if (pits[i] > 0) return false;
    }
    return true;
  }

  bool get finished => sideEmpty(0) || sideEmpty(1);

  /// 执行一步。返回 (最后落点, 吃子数, 是否再走一次)。结束时自动清扫。
  ({int last, int captured, bool again, bool ended}) play(int pit, {bool capture = true}) {
    final s = turn;
    var n = pits[pit];
    pits[pit] = 0;
    var i = pit;
    while (n > 0) {
      i = (i + 1) % 14;
      if (i == store(1 - s)) continue;
      pits[i]++;
      n--;
    }
    var captured = 0;
    final own = i >= first(s) && i < first(s) + 6;
    if (capture && own && pits[i] == 1) {
      final opp = 12 - i;
      if (pits[opp] > 0) {
        captured = pits[opp] + 1;
        pits[store(s)] += captured;
        pits[opp] = 0;
        pits[i] = 0;
      }
    }
    final again = i == store(s);
    var ended = false;
    if (finished) {
      ended = true;
      for (final t in [0, 1]) {
        for (var k = first(t); k < first(t) + 6; k++) {
          pits[store(t)] += pits[k];
          pits[k] = 0;
        }
      }
    } else if (!again) {
      turn = 1 - s;
    }
    return (last: i, captured: captured, again: again, ended: ended);
  }
}

class Mancala extends GameEngine {
  Mancala(super.setup);

  late final int seeds = setup.opt<int>('seeds', 4);
  late final bool captureOn = setup.opt<bool>('capture', true);
  late MancalaState st;
  int last = -1;
  int lastPit = -1;
  int lastSeat = -1;
  int lastCaptured = 0;
  bool lastAgain = false;
  int winner = -1; // 0/1，2 = 平局
  bool over = false;
  String result = '';
  int moves = 0;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [st.turn];
  @override
  int get botDelayMs => 700;

  @override
  void start() {
    final p = List.filled(14, seeds);
    p[6] = 0;
    p[13] = 0;
    final first = rng.nextInt(2);
    st = MancalaState(p, first);
    host.log('曼卡拉：每坑 $seeds 颗，${name(first)} 先手');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') {
      resign(seat);
      return;
    }
    if (seat != st.turn) throw GameError('还没轮到你');
    final pit = asInt(a['pit']);
    if (!st.legal(pit)) throw GameError('只能选择自己一侧有石子的坑');
    final r = st.play(pit, capture: captureOn);
    moves++;
    lastPit = pit;
    lastSeat = seat;
    last = r.last;
    lastCaptured = r.captured;
    lastAgain = r.again && !r.ended;
    if (r.captured > 0) host.log('${name(seat)} 吃掉 ${r.captured - 1} 颗石子');
    if (r.ended) {
      final a0 = st.pits[6], a1 = st.pits[13];
      if (a0 == a1) {
        _finish(2, '平局 $a0 : $a1');
      } else {
        final w = a0 > a1 ? 0 : 1;
        _finish(w, '${st.pits[6]} : ${st.pits[13]}');
      }
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
    over = true;
    winner = w;
    result = w == 2 ? why : '${name(w)} 获胜（$why）';
    host.log(result);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'pits': st.pits,
        'turn': st.turn,
        'seeds': seeds,
        'capture': captureOn,
        'last': last,
        'lastPit': lastPit,
        'lastSeat': lastSeat,
        'lastCaptured': lastCaptured,
        'lastAgain': lastAgain,
        'moves': moves,
        'legal': over ? <int>[] : st.moves(),
        'winner': winner,
        'result': over ? result : null,
        'over': over,
      };

  // ---- AI ----
  int _eval(MancalaState s, int me) {
    final o = 1 - me;
    var v = (s.pits[MancalaState.store(me)] - s.pits[MancalaState.store(o)]) * 4;
    var mine = 0, theirs = 0;
    for (var i = 0; i < 6; i++) {
      mine += s.pits[MancalaState.first(me) + i];
      theirs += s.pits[MancalaState.first(o) + i];
    }
    return v + (mine - theirs);
  }

  Stopwatch? _deadlineSw;
  bool _aborted = false;
  static const _deepMs = 900;

  int _search(MancalaState s, int depth, int alpha, int beta, int me) {
    final sw = _deadlineSw;
    if (sw != null && (_aborted || sw.elapsedMilliseconds > _deepMs)) {
      _aborted = true;
      return 0;
    }
    if (s.finished) {
      final d = s.pits[MancalaState.store(me)] - s.pits[MancalaState.store(1 - me)];
      return d * 1000;
    }
    if (depth == 0) return _eval(s, me);
    final maxing = s.turn == me;
    final ms = s.moves();
    // 走法排序：能再走一次的优先
    ms.sort((a, b) {
      int k(int p) => (p + s.pits[p]) % 13 == MancalaState.store(s.turn) % 13 ? 0 : 1;
      return k(a).compareTo(k(b));
    });
    var best = maxing ? -1 << 30 : 1 << 30;
    for (final m in ms) {
      final c = s.clone();
      c.play(m, capture: captureOn);
      final v = _search(c, depth - 1, alpha, beta, me);
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
    // 难度：简单 = 一半概率随机坑、否则只看一步；普通 = 7 层；困难 = 限时迭代加深
    if (botLevel <= 0 && rng.nextInt(2) == 0) return {'type': 'play', 'pit': ms[rng.nextInt(ms.length)]};
    if (botLevel >= 2) return {'type': 'play', 'pit': _deepBest(seat, ms)};
    final depth = botLevel <= 0 ? 0 : 7;
    var best = ms.first, bestV = -1 << 30;
    for (final m in ms) {
      final c = st.clone();
      c.play(m, capture: captureOn);
      final v = _search(c, depth, -1 << 30, 1 << 30, seat) + rng.nextInt(2);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return {'type': 'play', 'pit': best};
  }

  int _deepBest(int seat, List<int> ms) {
    final sw = Stopwatch()..start();
    var best = ms.first;
    _aborted = false;
    _deadlineSw = sw;
    try {
      for (var depth = 7; depth <= 24; depth++) {
        var b = ms.first, bestV = -1 << 30;
        for (final m in ms) {
          final c = st.clone();
          c.play(m, capture: captureOn);
          final v = _search(c, depth, -1 << 30, 1 << 30, seat) * 2 + rng.nextInt(2);
          if (_aborted) break;
          if (v > bestV) {
            bestV = v;
            b = m;
          }
        }
        if (_aborted) break;
        best = b;
      }
    } finally {
      _deadlineSw = null;
      _aborted = false;
    }
    return best;
  }
}
