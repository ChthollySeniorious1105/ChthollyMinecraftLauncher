import '../../src/engine.dart';

/// 格格不入 Blokus 的 21 块多格骨牌与规则。
class BlokusPiece {
  final String id;
  final List<(int, int)> cells;

  /// All distinct orientations (rotations + mirror), each normalised to min x/y = 0.
  final List<List<(int, int)>> orients;
  BlokusPiece(this.id, this.cells) : orients = _orientations(cells);

  int get size => cells.length;

  static List<(int, int)> _norm(Iterable<(int, int)> cs) {
    var mx = 1 << 20, my = 1 << 20;
    for (final (x, y) in cs) {
      if (x < mx) mx = x;
      if (y < my) my = y;
    }
    final out = [for (final (x, y) in cs) (x - mx, y - my)];
    out.sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
    return out;
  }

  static List<List<(int, int)>> _orientations(List<(int, int)> base) {
    final out = <List<(int, int)>>[];
    final seen = <String>{};
    for (var f = 0; f < 2; f++) {
      for (var r = 0; r < 4; r++) {
        final cs = _norm(transform(base, r, f == 1));
        final k = cs.map((c) => '${c.$1},${c.$2}').join(';');
        if (seen.add(k)) out.add(cs);
      }
    }
    return out;
  }

  /// Rotate [r] times 90° clockwise, optionally mirrored first.
  static List<(int, int)> transform(List<(int, int)> cs, int r, bool flip) {
    var out = [for (final (x, y) in cs) flip ? (-x, y) : (x, y)];
    for (var i = 0; i < r; i++) {
      out = [for (final (x, y) in out) (-y, x)];
    }
    return _norm(out);
  }

  /// Orientation index for a given rotation / flip.
  int orientOf(int r, bool flip) {
    final cs = transform(cells, r, flip);
    final k = cs.map((c) => '${c.$1},${c.$2}').join(';');
    for (var i = 0; i < orients.length; i++) {
      if (orients[i].map((c) => '${c.$1},${c.$2}').join(';') == k) return i;
    }
    return 0;
  }
}

final List<BlokusPiece> blokusPieces = [
  BlokusPiece('I1', [(0, 0)]),
  BlokusPiece('I2', [(0, 0), (1, 0)]),
  BlokusPiece('I3', [(0, 0), (1, 0), (2, 0)]),
  BlokusPiece('V3', [(0, 0), (1, 0), (0, 1)]),
  BlokusPiece('I4', [(0, 0), (1, 0), (2, 0), (3, 0)]),
  BlokusPiece('L4', [(0, 0), (0, 1), (0, 2), (1, 2)]),
  BlokusPiece('T4', [(0, 0), (1, 0), (2, 0), (1, 1)]),
  BlokusPiece('O4', [(0, 0), (1, 0), (0, 1), (1, 1)]),
  BlokusPiece('S4', [(1, 0), (2, 0), (0, 1), (1, 1)]),
  BlokusPiece('F5', [(1, 0), (2, 0), (0, 1), (1, 1), (1, 2)]),
  BlokusPiece('I5', [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)]),
  BlokusPiece('L5', [(0, 0), (0, 1), (0, 2), (0, 3), (1, 3)]),
  BlokusPiece('N5', [(0, 0), (0, 1), (1, 1), (1, 2), (1, 3)]),
  BlokusPiece('P5', [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)]),
  BlokusPiece('T5', [(0, 0), (1, 0), (2, 0), (1, 1), (1, 2)]),
  BlokusPiece('U5', [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1)]),
  BlokusPiece('V5', [(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)]),
  BlokusPiece('W5', [(0, 0), (0, 1), (1, 1), (1, 2), (2, 2)]),
  BlokusPiece('X5', [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)]),
  BlokusPiece('Y5', [(1, 0), (0, 1), (1, 1), (1, 2), (1, 3)]),
  BlokusPiece('Z5', [(0, 0), (1, 0), (1, 1), (1, 2), (2, 2)]),
];

class BlokusMove {
  final int piece, orient, x, y;
  const BlokusMove(this.piece, this.orient, this.x, this.y);
  List<(int, int)> get cells => [for (final (dx, dy) in blokusPieces[piece].orients[orient]) (x + dx, y + dy)];
  @override
  bool operator ==(Object o) => o is BlokusMove && o.piece == piece && o.orient == orient && o.x == x && o.y == y;
  @override
  int get hashCode => Object.hash(piece, orient, x, y);
}

/// Pure board logic (shared with the client for ghost previews).
class BlokusBoard {
  final int n;
  final int colors;

  /// -1 empty, else color index.
  final List<int> cells;
  final List<List<bool>> used; // [color][piece]
  final List<bool> started;
  BlokusBoard(this.n, this.colors)
      : cells = List.filled(n * n, -1),
        used = [for (var c = 0; c < colors; c++) List.filled(21, false)],
        started = List.filled(colors, false);

  BlokusBoard.from(this.n, this.colors, List<int> cs, List<List<bool>> us)
      : cells = List.of(cs),
        used = [for (final u in us) List.of(u)],
        started = [for (var c = 0; c < colors; c++) cs.contains(c)];

  /// Start cells: Duo (14×14) uses the two centre-ish points, 20×20 the corners.
  List<(int, int)> startCells(int color) {
    if (n == 14) return const [(4, 4), (9, 9)];
    final m = n - 1;
    return [
      [(0, 0)],
      [(m, 0)],
      [(m, m)],
      [(0, m)]
    ][color % 4];
  }

  int at(int x, int y) => x < 0 || y < 0 || x >= n || y >= n ? -2 : cells[y * n + x];

  /// Why a placement is illegal (null = legal).
  String? check(int color, List<(int, int)> cs) {
    for (final (x, y) in cs) {
      final v = at(x, y);
      if (v == -2) return '超出棋盘';
      if (v != -1) return '与已有棋子重叠';
    }
    for (final (x, y) in cs) {
      for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        if (at(x + dx, y + dy) == color) return '不能与自己颜色的棋子边相邻';
      }
    }
    if (!started[color]) {
      final st = startCells(color);
      for (final c in cs) {
        if (st.contains(c) && at(c.$1, c.$2) == -1) return null;
      }
      return n == 14 ? '第一块必须覆盖一个起始点' : '第一块必须覆盖你的起始角';
    }
    for (final (x, y) in cs) {
      for (final (dx, dy) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
        if (at(x + dx, y + dy) == color) return null;
      }
    }
    return '必须与自己颜色的棋子角对角相接';
  }

  /// Anchor cells where [color] may cover a square next.
  List<(int, int)> anchors(int color) {
    if (!started[color]) return [for (final c in startCells(color)) if (at(c.$1, c.$2) == -1) c];
    final out = <(int, int)>[];
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (cells[y * n + x] != -1) continue;
        var edge = false, corner = false;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          if (at(x + dx, y + dy) == color) edge = true;
        }
        if (edge) continue;
        for (final (dx, dy) in const [(1, 1), (-1, 1), (1, -1), (-1, -1)]) {
          if (at(x + dx, y + dy) == color) corner = true;
        }
        if (corner) out.add((x, y));
      }
    }
    return out;
  }

  List<BlokusMove> legalMoves(int color, {int? onlyPiece, bool firstOnly = false}) {
    final out = <BlokusMove>[];
    final seen = <BlokusMove>{};
    final anc = anchors(color);
    if (anc.isEmpty) return out;
    for (var p = 20; p >= 0; p--) {
      if (used[color][p] || (onlyPiece != null && p != onlyPiece)) continue;
      final pc = blokusPieces[p];
      for (var o = 0; o < pc.orients.length; o++) {
        final cs = pc.orients[o];
        for (final (ax, ay) in anc) {
          for (final (cx, cy) in cs) {
            final m = BlokusMove(p, o, ax - cx, ay - cy);
            if (seen.contains(m)) continue;
            seen.add(m);
            if (check(color, m.cells) == null) {
              out.add(m);
              if (firstOnly) return out;
            }
          }
        }
      }
    }
    return out;
  }

  bool hasMove(int color) => legalMoves(color, firstOnly: true).isNotEmpty;

  void place(int color, BlokusMove m) {
    for (final (x, y) in m.cells) {
      cells[y * n + x] = color;
    }
    used[color][m.piece] = true;
    started[color] = true;
  }
}

class Blokus extends GameEngine {
  Blokus(super.setup);

  late BlokusBoard b;
  int turn = 0; // color to move (color == seat)
  late List<bool> done; // no more moves / resigned
  late List<bool> resigned;
  late List<int> lastPiece; // last piece index placed per color
  Map<String, dynamic>? last;
  bool over = false;
  String result = '';
  String note = '';
  List<int> placementsLog = [];

  int get n => players == 2 ? 14 : 20;

  @override
  bool get isOver => over;
  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  void start() {
    b = BlokusBoard(n, players);
    done = List.filled(players, false);
    resigned = List.filled(players, false);
    lastPiece = List.filled(players, -1);
    host.log(players == 2 ? '格格不入（双人 14×14）开始' : '格格不入（$players 人 20×20）开始');
  }

  int remaining(int c) {
    var s = 0;
    for (var p = 0; p < 21; p++) {
      if (!b.used[c][p]) s += blokusPieces[p].size;
    }
    return s;
  }

  bool allPlaced(int c) => !b.used[c].contains(false);

  /// Advanced scoring: −1 per unplaced square; +15 for placing all, +5 more if the last was the monomino.
  int score(int c) {
    if (allPlaced(c)) return 15 + (lastPiece[c] == 0 ? 5 : 0);
    return -remaining(c);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (a['type'] == 'resign') return resign(seat);
    if (seat != turn) throw GameError('还没轮到你');
    if (a['type'] == 'pass') {
      // voluntary stop: give up remaining pieces
      done[seat] = true;
      note = '${name(seat)} 放弃继续放置';
      host.log(note);
      _advance();
      return;
    }
    if (a['type'] != 'place') throw GameError('未知操作');
    final p = asInt(a['piece']), o = asInt(a['orient']), x = asInt(a['x'], -99), y = asInt(a['y'], -99);
    if (p < 0 || p > 20) throw GameError('未知棋子');
    if (b.used[seat][p]) throw GameError('这块已经用过了');
    if (o < 0 || o >= blokusPieces[p].orients.length) throw GameError('方向错误');
    if (x < -5 || y < -5 || x > n || y > n) throw GameError('超出棋盘');
    final m = BlokusMove(p, o, x, y);
    final why = b.check(seat, m.cells);
    if (why != null) throw GameError(why);
    b.place(seat, m);
    lastPiece[seat] = p;
    placementsLog.add(seat);
    last = {'color': seat, 'cells': [for (final (cx, cy) in m.cells) cy * n + cx], 'piece': blokusPieces[p].id};
    note = '${name(seat)} 放下 ${blokusPieces[p].size} 格棋子';
    if (allPlaced(seat)) {
      done[seat] = true;
      host.log('${name(seat)} 放完了全部 21 块！');
    }
    _advance();
  }

  void _advance() {
    for (var c = 0; c < players; c++) {
      if (!done[c] && !b.hasMove(c)) {
        done[c] = true;
        host.log('${name(c)} 无处可放，停止');
      }
    }
    if (!done.contains(false)) {
      _finish();
      return;
    }
    var t = turn;
    for (var i = 0; i < players; i++) {
      t = (t + 1) % players;
      if (!done[t]) break;
    }
    turn = t;
  }

  void _finish() {
    over = true;
    final sc = [for (var c = 0; c < players; c++) score(c)];
    final best = sc.reduce((a, b) => a > b ? a : b);
    final ws = [for (var c = 0; c < players; c++) if (sc[c] == best && !resigned[c]) c];
    result = ws.length == 1
        ? '${name(ws.first)} 获胜（${sc[ws.first]} 分）'
        : (ws.isEmpty ? '对局结束' : '${ws.map(name).join('、')} 并列第一（$best 分）');
    host.log('$result · ${[for (var c = 0; c < players; c++) '${name(c)} ${sc[c]}'].join('  ')}');
  }

  List<int> get _finalScores => [for (var c = 0; c < players; c++) resigned[c] ? -1000 : score(c)];

  @override
  List<int>? get placings => !over ? null : (_draw ? List.filled(players, 1) : rankByScore(_finalScores));

  @override
  bool get canResign => !over;
  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你不是玩家');
    if (resigned[seat]) throw GameError('你已经认输了');
    resigned[seat] = true;
    done[seat] = true;
    host.log('${name(seat)} 认输');
    if (players == 2 || resigned.where((r) => !r).length <= 1) {
      over = true;
      final w = [for (var c = 0; c < players; c++) if (!resigned[c]) c];
      result = w.isEmpty ? '对局结束' : '${name(w.first)} 获胜（${players == 2 ? '对手' : '其他人'}认输）';
      host.log(result);
      return;
    }
    if (!done.contains(false)) {
      _finish();
    } else if (turn == seat) {
      _advance();
    }
  }

  @override
  bool get canDraw => !over && players == 2;
  @override
  void agreeDraw() {
    if (over) throw GameError('对局已结束');
    over = true;
    _draw = true;
    result = '双方同意和棋';
    host.log(result);
  }

  bool _draw = false;

  @override
  Map<String, dynamic> view(int seat) {
    final anchors = !over && seat >= 0 && seat < players && seat == turn ? b.anchors(seat) : const <(int, int)>[];
    return {
      'n': n,
      'board': b.cells,
      'used': [for (var c = 0; c < players; c++) b.used[c]],
      'started': b.started,
      'turn': turn,
      'done': done,
      'resigned': resigned,
      'remaining': [for (var c = 0; c < players; c++) remaining(c)],
      'scores': [for (var c = 0; c < players; c++) score(c)],
      'anchors': [for (final (x, y) in anchors) y * n + x],
      'last': last,
      'note': note,
      'placed': placementsLog.length,
      'result': result,
      'draw': _draw,
      'over': over,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final ms = b.legalMoves(seat);
    if (ms.isEmpty) return {'type': 'pass'};
    final lvl = botLevel;
    BlokusMove m;
    if (lvl == 0) {
      // random but biased to bigger pieces half the time
      if (rng.nextBool()) {
        m = ms[rng.nextInt(ms.length)];
      } else {
        final big = blokusPieces[ms.first.piece].size;
        final pool = ms.where((x) => blokusPieces[x.piece].size == big).toList();
        m = pool[rng.nextInt(pool.length)];
      }
    } else {
      m = _bestGreedy(seat, ms, lvl);
    }
    return {'type': 'place', 'piece': m.piece, 'orient': m.orient, 'x': m.x, 'y': m.y};
  }

  BlokusMove _bestGreedy(int seat, List<BlokusMove> ms, int lvl) {
    final sw = Stopwatch()..start();
    final myAnc0 = b.anchors(seat).length;
    final oppAnc0 = [for (var c = 0; c < players; c++) c == seat || done[c] ? 0 : b.anchors(c).length];
    final centre = (n - 1) / 2;
    final early = placementsLog.length < players * 4;
    // keep evaluation affordable: consider the largest pieces first and cap
    var cand = ms;
    final maxEval = lvl >= 2 ? 700 : 220;
    if (cand.length > maxEval) {
      cand = List.of(ms)..shuffle(rng);
      cand.sort((a, c) => blokusPieces[c.piece].size.compareTo(blokusPieces[a.piece].size));
      cand = cand.sublist(0, maxEval);
    }
    BlokusMove best = cand.first;
    var bestV = -1e18;
    for (final m in cand) {
      if (sw.elapsedMilliseconds > (lvl >= 2 ? 1100 : 500)) break;
      final nb = BlokusBoard.from(n, players, b.cells, b.used)..place(seat, m);
      final size = blokusPieces[m.piece].size;
      var v = size * 10.0;
      if (lvl >= 1) {
        final myAnc = nb.anchors(seat).length;
        v += (myAnc - myAnc0) * 2.5;
        if (lvl >= 2) {
          for (var c = 0; c < players; c++) {
            if (c == seat || done[c]) continue;
            v += (oppAnc0[c] - nb.anchors(c).length) * 2.0;
          }
        }
        if (early) {
          // head toward the centre
          var d = 0.0;
          for (final (x, y) in m.cells) {
            d += (x - centre).abs() + (y - centre).abs();
          }
          v -= d / size * 1.5;
        }
        // save the monomino for last
        if (m.piece == 0 && remaining(seat) > 1) v -= 12;
      }
      v += rng.nextDouble();
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }
}
