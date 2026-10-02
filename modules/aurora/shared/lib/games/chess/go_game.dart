import 'dart:math';

import '../../src/engine.dart';
import 'go_board.dart';

/// 围棋（中国规则数子法）
class GoGame extends GameEngine {
  GoGame(super.setup);

  late final int n = setup.opt<int>('size', 19);
  late final double komi = _komi(setup.opt<String>('komi', '7.5'));
  late final int handicap = setup.opt<int>('handicap', 0);
  late final GoBoard board = GoBoard(n);

  static double _komi(String s) => double.tryParse(s) ?? 7.5;

  int blackSeat = 0;
  int toMove = 1; // colour to move: 1 black, 2 white
  String phase = 'play'; // play / scoring / over
  int passes = 0;
  int moveCount = 0;
  int last = -1; // -1 none, -2 pass
  final List<int> caps = [0, 0, 0]; // caps[c] = stones captured by colour c
  final Set<String> history = {};
  Set<int> dead = {};
  final List<bool> confirmed = [false, false];
  int winner = -2; // -2 playing, -1 draw, else seat
  String result = '';
  List<int> owner = const [];
  double blackScore = 0, whiteScore = 0;

  int seatOf(int color) => color == 1 ? blackSeat : 1 - blackSeat;
  int colorOf(int seat) => seat == blackSeat ? 1 : 2;
  String _cn(int color) => color == 1 ? '黑' : '白';

  @override
  void start() {
    blackSeat = rng.nextInt(2);
    final hs = handicapPoints(n, handicap);
    for (final p in hs) {
      board.play(p, 1);
    }
    board.ko = -1;
    toMove = hs.isEmpty ? 1 : 2;
    history.add(board.key());
    host.log('${name(blackSeat)} 执黑，${name(1 - blackSeat)} 执白；$n 路，贴 $komi 目${hs.isEmpty ? '' : '，让 ${hs.length} 子'}');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    if (phase == 'play') return [seatOf(toMove)];
    if (phase == 'scoring') return [for (var s = 0; s < 2; s++) if (!confirmed[s]) s];
    return const [];
  }

  String coord(int p) {
    const letters = 'ABCDEFGHJKLMNOPQRST';
    return '${letters[p % n]}${n - p ~/ n}';
  }

  /// Checks legality incl. positional superko; returns resulting board or throws.
  GoBoard _tryMove(int p, int c) {
    if (p < 0 || p >= n * n) throw GameError('无效位置');
    if (board.col[p] != 0) throw GameError('这里已经有棋子了');
    if (p == board.ko) throw GameError('打劫：不能立即提回，请先在别处落子');
    if (!board.isLegal(p, c)) throw GameError('禁止自杀（落子后无气）');
    final nb = board.copy();
    nb.play(p, c);
    if (history.contains(nb.key())) throw GameError('全局同形重复（超级劫），不能下这里');
    return nb;
  }

  bool _canPlay(int p, int c) {
    if (board.col[p] != 0 || p == board.ko || !board.isLegal(p, c)) return false;
    final nb = board.copy();
    nb.play(p, c);
    return !history.contains(nb.key());
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('你不是对局者');
    final type = asStr(a['type']);
    if (type == 'resign') {
      _end(1 - seat, '${name(seat)} 认输');
      return;
    }
    if (phase == 'scoring') {
      switch (type) {
        case 'toggle':
          final p = asInt(a['point']);
          if (p < 0 || p >= n * n || board.col[p] == 0) throw GameError('请点击棋子来标记死活');
          final stones = board.stonesOf(board.rep[p]);
          if (dead.contains(p)) {
            dead.removeAll(stones);
          } else {
            dead.addAll(stones);
          }
          confirmed[0] = confirmed[1] = false;
          _rescore();
          return;
        case 'confirm':
          confirmed[seat] = true;
          if (confirmed[0] && confirmed[1]) _finalize();
          return;
        case 'resume':
          phase = 'play';
          passes = 0;
          dead = {};
          confirmed[0] = confirmed[1] = false;
          owner = const [];
          toMove = 3 - colorOf(seat); // opponent of the requester moves first
          host.log('${name(seat)} 对死活有异议，继续对局');
          return;
        default:
          throw GameError('数子阶段：请标记死子或确认结果');
      }
    }
    final c = colorOf(seat);
    if (c != toMove) throw GameError('还没轮到你');
    if (type == 'pass') {
      board.pass();
      passes++;
      moveCount++;
      last = -2;
      host.log('${name(seat)}（${_cn(c)}）停一手');
      toMove = 3 - c;
      if (passes >= 2) _enterScoring();
      return;
    }
    if (type != 'play') throw GameError('未知操作');
    final p = asInt(a['point']);
    final nb = _tryMove(p, c);
    final captured = board.play(p, c);
    assert(board.key() == nb.key());
    caps[c] += captured;
    history.add(board.key());
    passes = 0;
    moveCount++;
    last = p;
    toMove = 3 - c;
  }

  void _enterScoring() {
    phase = 'scoring';
    dead = estimateDead(board, toMove, rng);
    confirmed[0] = confirmed[1] = false;
    _rescore();
    host.log('双方停着，进入数子阶段：点击棋子标记死子，双方确认后结算');
  }

  void _rescore() {
    final (own, bl, wh) = areaScore(board, dead);
    owner = own;
    blackScore = bl.toDouble();
    whiteScore = wh + komi;
  }

  void _finalize() {
    _rescore();
    final diff = blackScore - whiteScore;
    final detail = '黑 ${_fmt(blackScore)} 子，白 ${_fmt(whiteScore)} 子（含贴目 $komi）';
    if (diff == 0) {
      _end(-1, '和棋：$detail');
    } else {
      final wc = diff > 0 ? 1 : 2;
      _end(seatOf(wc), '${_cn(wc)}胜 ${_fmt(diff.abs())} 子：$detail');
    }
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _end(int w, String why) {
    phase = 'over';
    winner = w;
    result = why;
    host.log(why);
  }

  @override
  List<int>? get placings => !isOver ? null : (winner < 0 ? [1, 1] : [for (var s = 0; s < 2; s++) s == winner ? 1 : 2]);

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat > 1) return;
    _end(1 - seat, '${name(seat)} 认输');
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) return;
    _end(-1, '双方同意和棋');
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'size': n,
        'board': List<int>.of(board.col),
        'blackSeat': blackSeat,
        'toMove': toMove,
        'turn': phase == 'play' ? seatOf(toMove) : -1,
        'phase': phase,
        'last': last,
        'ko': board.ko,
        'moveCount': moveCount,
        'caps': [caps[1], caps[2]],
        'komi': komi,
        'handicap': handicap,
        'dead': dead.toList(),
        'owner': phase == 'play' ? const <int>[] : owner,
        'score': [blackScore, whiteScore],
        'confirmed': confirmed,
        'winner': winner,
        'result': result,
        'over': isOver,
      };

  // ------------------------------------------------------------------ bot

  @override
  int get botDelayMs => 300;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver) return null;
    if (phase == 'scoring') return confirmed[seat] ? null : {'type': 'confirm'};
    final c = colorOf(seat);
    if (c != toMove) return null;
    if (moveCount > n * n * 2) return {'type': 'pass'};
    if (botLevel <= 0 && rng.nextDouble() < 0.3) {
      // 简单: frequently a random (non eye-filling, non suicidal) move
      final cands = [for (final q in board.emp) if (!board.isEye(q, c) && _canPlay(q, c)) q];
      if (cands.isNotEmpty) return {'type': 'play', 'point': cands[rng.nextInt(cands.length)]};
    }
    final playouts = botLevel >= 2 ? (n <= 9 ? 80 : (n <= 13 ? 24 : 0)) : (n <= 9 ? 24 : 0);
    final p = GoBot(board, c, rng,
            moveCount: moveCount, opponentPassed: last == -2, lastMove: last, playouts: playouts, sloppy: botLevel <= 0)
        .choose(_canPlay);
    if (p < 0) return {'type': 'pass'};
    return {'type': 'play', 'point': p};
  }
}

/// Fast heuristic Go bot: tactics (capture / escape / atari), eye protection,
/// influence-based positional judgement and light Monte-Carlo ownership on small boards.
class GoBot {
  final GoBoard b;
  final int c;
  final Random rng;
  final int moveCount;
  final bool opponentPassed;
  final int lastMove;
  /// Monte-Carlo ownership playouts (0 = influence map only).
  final int playouts;

  /// 简单 difficulty: large random noise in move scores.
  final bool sloppy;
  GoBot(this.b, this.c, this.rng,
      {required this.moveCount, required this.opponentPassed, required this.lastMove, int? playouts, this.sloppy = false})
      : playouts = playouts ?? (b.n <= 9 ? 24 : 0);

  int get n => b.n;

  /// Influence map: positive = our colour.
  List<double> _influence() {
    final nn = b.nn;
    final inf = List<double>.filled(nn, 0);
    const radius = 3;
    for (var p = 0; p < nn; p++) {
      final v = b.col[p];
      if (v == 0) continue;
      final s = v == c ? 1.0 : -1.0;
      final px = p % n, py = p ~/ n;
      for (var dy = -radius; dy <= radius; dy++) {
        final y = py + dy;
        if (y < 0 || y >= n) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          final x = px + dx;
          if (x < 0 || x >= n) continue;
          final d = dx.abs() + dy.abs();
          if (d > radius) continue;
          inf[y * n + x] += s * (d == 0 ? 4 : (d == 1 ? 2 : (d == 2 ? 1 : 0.5)));
        }
      }
    }
    return inf;
  }

  int _lineOf(int p) {
    final x = p % n, y = p ~/ n;
    return min(min(x, y), min(n - 1 - x, n - 1 - y)) + 1;
  }

  /// Liberties our group would have after playing at [p] (ignores captures).
  int _libsAfter(int p) {
    final libs = <int>{};
    for (final q in b.adj[p]) {
      if (b.col[q] == 0) {
        libs.add(q);
      } else if (b.col[q] == c) {
        libs.addAll(b.libsOf(b.rep[q]));
      }
    }
    libs.remove(p);
    return libs.length;
  }

  int choose(bool Function(int p, int c) canPlay) {
    final o = 3 - c;
    final nn = b.nn;
    final inf = _influence();
    List<double>? mc;
    if (playouts > 0) mc = mcOwnership(b, c, rng, playouts);

    // group liberty info
    final libCache = <int, int>{};
    int libs(int r) => libCache.putIfAbsent(r, () => b.libsOf(r).length);

    final scored = <(double, int)>[];
    final stones = nn - b.emptyCount;
    final opening = stones < nn ~/ 6;
    for (final p in b.emp) {
      if (b.isEye(p, c)) continue;
      if (!b.isLegal(p, c)) continue;
      var score = 0.0;
      var tactical = false;
      var captures = 0;
      final seenGroups = <int>{};
      for (final q in b.adj[p]) {
        if (b.col[q] == 0) continue;
        final r = b.rep[q];
        if (!seenGroups.add(r)) continue;
        final lib = libs(r);
        final size = b.gsize[r];
        if (b.col[q] == o) {
          if (lib == 1) {
            captures += size;
            score += 60 + 12 * size;
            tactical = true;
          } else if (lib == 2) {
            score += 6 + 2 * min(size, 6);
          }
        } else {
          if (lib == 1) {
            // escape: only useful if we gain liberties
            if (_libsAfter(p) >= 2) {
              score += 50 + 10 * size;
              tactical = true;
            }
          } else if (lib == 2) {
            score += 3 + size.toDouble(); // strengthen weak group
          }
        }
      }
      final after = _libsAfter(p);
      if (captures == 0 && after <= 1) {
        continue; // self-atari
      }
      if (captures == 0 && after == 2) score -= 4;
      final i = inf[p];
      if (!tactical) {
        // positional value: contested points are valuable, settled ones are not
        final settled = mc != null ? mc[p] * (c == 1 ? 1 : -1) : i / 6.0;
        final contest = mc != null ? 1 - settled.abs() : max(0.0, 1 - i.abs() / 6.0);
        if (mc != null) {
          if (settled.abs() > 0.8) continue; // owned by someone firmly
        } else {
          if (i >= 4) continue; // inside own territory
          if (i <= -5) continue; // deep in opponent's area (hopeless invasion)
        }
        score += 10 * contest;
        final line = _lineOf(p);
        if (opening) {
          if (line == 3 || line == 4) score += 6;
          if (line <= 2) score -= 6;
        } else if (line == 1) {
          score -= 2;
        }
        // stay close to the action
        if (lastMove >= 0) {
          final d = (lastMove % n - p % n).abs() + (lastMove ~/ n - p ~/ n).abs();
          if (d <= 2) score += 3;
        }
        // don't fill own nearly-eyes
        if (b.eyeish(p, c)) score -= 8;
        if (score < 3) continue;
      }
      score += rng.nextDouble() * (sloppy ? 25 : 2);
      scored.add((score, p));
    }
    if (scored.isEmpty) return -1;
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    // after an opponent pass, only continue with clearly useful moves
    if (opponentPassed && scored.first.$1 < 20) return -1;
    for (final (_, p) in scored.take(8)) {
      if (canPlay(p, c)) return p;
    }
    return -1;
  }
}
