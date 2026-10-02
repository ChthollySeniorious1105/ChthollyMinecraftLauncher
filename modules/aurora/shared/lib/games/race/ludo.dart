import '../../src/engine.dart';

/// 飞行棋 board geometry (shared with the client).
///
/// 15×15 grid, cross-shaped. 52 track squares; square g has colour (g-1)%4.
/// Colour c enters the track at global 13c+1 (relative 0), travels relative
/// 0..50 on the track, 51..55 in its home column, 56 = 到达终点.
class LudoGeo {
  static const int track = 52;
  static const int lastTrack = 50;
  static const int finish = 56;
  static const int flyFrom = 20;
  static const int flyTo = 28;

  static const List<(int, int)> _quarter = [
    (6, 0), (6, 1), (6, 2), (6, 3), (6, 4), (6, 5),
    (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6), (0, 7),
  ];

  static (int, int) _rot((int, int) p, int times) {
    var (r, c) = p;
    for (var i = 0; i < times % 4; i++) {
      final nr = c, nc = 14 - r;
      r = nr;
      c = nc;
    }
    return (r, c);
  }

  /// Grid cell (row, col) of global track square g.
  static (int, int) trackCell(int g) {
    g %= track;
    return _rot(_quarter[g % 13], g ~/ 13);
  }

  static int squareColor(int g) => (g - 1) % 4;

  static int global(int color, int rel) => (13 * color + 1 + rel) % track;

  /// Grid cell (row, col) — may be fractional for the center — of a plane of
  /// [color] at relative position [rel] (0..56). Hangar = -1 handled by UI.
  static (double, double) cell(int color, int rel) {
    if (rel <= lastTrack) {
      final (r, c) = trackCell(global(color, rel));
      return (r.toDouble(), c.toDouble());
    }
    if (rel >= finish) {
      final (r, c) = _rot((7, 6), color);
      return (r.toDouble(), c.toDouble());
    }
    final (r, c) = _rot((7, rel - 50), color);
    return (r.toDouble(), c.toDouble());
  }

  /// Home-column cells for colour c.
  static List<(int, int)> homeColumn(int c) => [for (var k = 1; k <= 5; k++) _rot((7, k), c)];

  /// Hangar (corner) top-left cell for colour c — the 6×6 corner area.
  /// Colour 0 is the top-left corner (enters from the left arm going up).
  static (int, int) hangarCorner(int c) => const [(0, 0), (0, 9), (9, 9), (9, 0)][c % 4];

  /// Start (take-off) square for colour c.
  static (int, int) startCell(int c) => trackCell(global(c, 0));
}

class Ludo extends GameEngine {
  Ludo(super.setup);

  late final int launchMin = setup.opt<int>('launch', 6);
  late final bool bounce = setup.opt<bool>('bounce', true);
  late final bool triple6 = setup.opt<bool>('triple6', true);

  late final List<int> colors = [for (var s = 0; s < players; s++) players == 2 ? s * 2 : s];
  late final List<List<int>> pos = [for (var s = 0; s < players; s++) List.filled(4, -1)];
  int turn = 0;
  String phase = 'roll'; // roll | move | over
  int die = 0;
  int sixes = 0;
  List<int> movable = [];
  Map<String, dynamic>? last;
  int winner = -1;
  int moves = 0;
  int rolls = 0;

  /// Seats that resigned (in order); their planes are removed and turns skipped.
  final List<int> resigned = [];

  bool active(int s) => !resigned.contains(s);

  int _progress(int s) => pos[s].fold(0, (a, p) => a + (p < 0 ? 0 : p + 1));

  @override
  List<int>? get placings {
    if (!isOver) return null;
    final score = <num>[
      for (var s = 0; s < players; s++)
        s == winner
            ? 1 << 30
            : resigned.contains(s)
                ? -(1 << 20) + resigned.indexOf(s)
                : _progress(s),
    ];
    return rankByScore(score);
  }

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat >= players || !active(seat)) return;
    resigned.add(seat);
    for (var i = 0; i < 4; i++) {
      pos[seat][i] = -1;
    }
    host.log('${name(seat)} 认输');
    final left = [for (var s = 0; s < players; s++) if (active(s)) s];
    if (left.length == 1) {
      winner = left.first;
      phase = 'over';
      movable = [];
      host.log('${name(winner)} 获胜！');
      return;
    }
    if (turn == seat) _nextTurn();
  }

  @override
  void start() {
    turn = rng.nextInt(players);
    host.log('${name(turn)} 先掷骰子');
  }

  @override
  bool get isOver => winner >= 0;

  @override
  List<int> get waitingFor => isOver ? const [] : [turn];

  /// Result of moving plane [i] of [seat] by [d]: list of stops (rel), or null if illegal.
  List<int>? path(int seat, int i, int d) {
    final p = pos[seat][i];
    if (p >= LudoGeo.finish) return null;
    if (p < 0) return d >= launchMin ? [0] : null;
    var t = p + d;
    if (t > LudoGeo.finish) {
      if (!bounce) {
        t = LudoGeo.finish;
      } else {
        t = 2 * LudoGeo.finish - t;
      }
    }
    final stops = [t];
    bool own(int r) => r <= LudoGeo.lastTrack && r % 4 == 0;
    if (own(t)) {
      if (t == LudoGeo.flyFrom) {
        t = LudoGeo.flyTo;
        stops.add(t);
      } else if (t + 4 <= LudoGeo.lastTrack) {
        t += 4;
        stops.add(t);
        if (t == LudoGeo.flyFrom) {
          t = LudoGeo.flyTo;
          stops.add(t);
        }
      }
    }
    return stops;
  }

  List<int> movableFor(int seat, int d) =>
      [for (var i = 0; i < 4; i++) if (path(seat, i, d) != null) i];

  /// Opponent planes that would be captured at track stop [rel] of [seat].
  List<(int, int)> victims(int seat, int rel) {
    if (rel > LudoGeo.lastTrack) return const [];
    final g = LudoGeo.global(colors[seat], rel);
    final out = <(int, int)>[];
    for (var s = 0; s < players; s++) {
      if (s == seat || !active(s)) continue;
      for (var j = 0; j < 4; j++) {
        final q = pos[s][j];
        if (q >= 0 && q <= LudoGeo.lastTrack && LudoGeo.global(colors[s], q) == g) out.add((s, j));
      }
    }
    return out;
  }

  void _nextTurn() {
    sixes = 0;
    do {
      turn = (turn + 1) % players;
    } while (!active(turn));
    phase = 'roll';
    movable = [];
  }

  void _afterMove() {
    if (isOver) return;
    if (die == 6) {
      phase = 'roll';
      movable = [];
    } else {
      _nextTurn();
    }
  }

  void _apply(int seat, int i) {
    final stops = path(seat, i, die)!;
    final from = pos[seat][i];
    final captured = <List<int>>[];
    for (final st in stops) {
      for (final (s, j) in victims(seat, st)) {
        pos[s][j] = -1;
        captured.add([s, j]);
      }
    }
    pos[seat][i] = stops.last;
    moves++;
    last = {'seat': seat, 'plane': i, 'from': from, 'stops': stops, 'captured': captured, 'die': die};
    final parts = <String>[];
    if (from < 0) parts.add('起飞');
    if (stops.length > 1) {
      parts.add(stops.contains(LudoGeo.flyTo) ? '飞越' : '跳跃');
    }
    if (captured.isNotEmpty) {
      parts.add('击落 ${captured.map((c) => name(c[0])).toSet().join('、')} 的 ${captured.length} 架飞机');
    }
    if (stops.last == LudoGeo.finish) parts.add('到达终点');
    if (parts.isNotEmpty) host.log('${name(seat)} ${parts.join('，')}');
    if (pos[seat].every((p) => p == LudoGeo.finish)) {
      winner = seat;
      phase = 'over';
      host.log('${name(seat)} 四架飞机全部到达，获胜！');
      return;
    }
    _afterMove();
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final t = asStr(a['t']);
    if (t == 'roll') {
      if (phase != 'roll') throw GameError('请先选择要移动的飞机');
      die = rng.nextInt(6) + 1;
      rolls++;
      if (die == 6) sixes++;
      last = {'seat': seat, 'roll': die};
      if (triple6 && sixes >= 3) {
        host.log('${name(seat)} 连续三次掷出 6，本轮作废');
        last = {'seat': seat, 'roll': die, 'void': true};
        _nextTurn();
        return;
      }
      final m = movableFor(seat, die);
      if (m.isEmpty) {
        last = {'seat': seat, 'roll': die, 'none': true};
        _afterMove();
        return;
      }
      // auto-move when there is only one real choice (identical planes count as one)
      final distinct = {for (final i in m) pos[seat][i]};
      if (distinct.length == 1) {
        _apply(seat, m.first);
        return;
      }
      movable = m;
      phase = 'move';
      return;
    }
    if (t == 'move') {
      if (phase != 'move') throw GameError('请先掷骰子');
      final i = asInt(a['plane']);
      if (!movable.contains(i)) throw GameError('这架飞机不能移动');
      movable = [];
      _apply(seat, i);
      return;
    }
    throw GameError('未知操作');
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'colors': colors,
        'pos': pos,
        'turn': turn,
        'phase': phase,
        'die': die,
        'movable': movable,
        'last': last,
        'winner': winner,
        'launch': launchMin,
        'bounce': bounce,
        'rolls': rolls,
        'resigned': resigned,
      };

  @override
  int get botDelayMs => 600;

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roll') return {'t': 'roll'};
    if (movable.isEmpty) return {'t': 'roll'};
    // 简单: frequently moves a random plane
    if (botLevel <= 0 && rng.nextDouble() < 0.5) return {'t': 'move', 'plane': movable[rng.nextInt(movable.length)]};
    final hard = botLevel >= 2;
    var best = movable.first;
    var bestScore = -1e9;
    for (final i in movable) {
      final stops = path(seat, i, die)!;
      final from = pos[seat][i];
      final to = stops.last;
      var sc = 0.0;
      for (final st in stops) {
        sc += victims(seat, st).length * 120;
      }
      if (to == LudoGeo.finish) sc += 100;
      if (from < 0) sc += 60;
      sc += (to - (from < 0 ? -6 : from)) * 1.5;
      if (from >= 0 && from <= LudoGeo.lastTrack && _threat(seat, from) > 0) sc += 40;
      if (to <= LudoGeo.lastTrack) sc -= _threat(seat, to) * 35;
      if (to > LudoGeo.lastTrack && from <= LudoGeo.lastTrack) sc += 30;
      if (hard) {
        // 困难: avoid breaking up; prefer landing where more of my planes can later capture
        if (to <= LudoGeo.lastTrack) sc -= _threat(seat, to) * 25;
        if (from >= 0 && from <= LudoGeo.lastTrack) sc += _threat(seat, from) * 20;
        if (to == LudoGeo.finish && pos[seat].where((p) => p != LudoGeo.finish).length == 1) sc += 500;
      }
      sc += rng.nextDouble();
      if (sc > bestScore) {
        bestScore = sc;
        best = i;
      }
    }
    return {'t': 'move', 'plane': best};
  }

  /// Number of opponent planes within 1..6 squares behind track square [rel].
  int _threat(int seat, int rel) {
    final g = LudoGeo.global(colors[seat], rel);
    var n = 0;
    for (var s = 0; s < players; s++) {
      if (s == seat || !active(s)) continue;
      for (final q in pos[s]) {
        if (q < 0 || q > LudoGeo.lastTrack) continue;
        final og = LudoGeo.global(colors[s], q);
        final dist = (g - og) % LudoGeo.track;
        if (dist >= 1 && dist <= 6 && q + dist <= LudoGeo.lastTrack) n++;
      }
    }
    return n;
  }
}
