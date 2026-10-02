/// 五子棋规则核心：连五判定与连珠（Renju）禁手判定。
///
/// cells: 0 空, 1 黑, 2 白。坐标 p = y * n + x。
library;

const gomokuDirs = [(1, 0), (0, 1), (1, 1), (1, -1)];

enum GomokuRule { free, standard, renju }

GomokuRule gomokuRuleOf(String s) => switch (s) {
      'standard' => GomokuRule.standard,
      'renju' => GomokuRule.renju,
      _ => GomokuRule.free,
    };

class GomokuBoard {
  final int n;
  final List<int> cells;
  GomokuBoard(this.n) : cells = List.filled(n * n, 0);
  GomokuBoard.from(this.n, List<int> c) : cells = List.of(c);

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < n && y < n;
  int at(int x, int y) => inside(x, y) ? cells[y * n + x] : -1;

  /// Length of the contiguous run of [color] through p along (dx,dy), p included
  /// (p is treated as [color] regardless of its content).
  int run(int p, int dx, int dy, int color) {
    final x0 = p % n, y0 = p ~/ n;
    var len = 1;
    for (var s = 1;; s++) {
      if (at(x0 + dx * s, y0 + dy * s) != color) break;
      len++;
    }
    for (var s = 1;; s++) {
      if (at(x0 - dx * s, y0 - dy * s) != color) break;
      len++;
    }
    return len;
  }

  /// The winning line (points) through p for [color] in any direction, or null.
  /// [exact]: only exactly five counts.
  List<int>? fiveLine(int p, int color, {required bool exact}) {
    final x0 = p % n, y0 = p ~/ n;
    for (final (dx, dy) in gomokuDirs) {
      final len = run(p, dx, dy, color);
      if (exact ? len == 5 : len >= 5) {
        var s = 0;
        while (at(x0 - dx * (s + 1), y0 - dy * (s + 1)) == color) {
          s++;
        }
        return [for (var k = -s; k < len - s; k++) (y0 + dy * k) * n + (x0 + dx * k)];
      }
    }
    return null;
  }

  bool hasExactFive(int p, int color) {
    for (final (dx, dy) in gomokuDirs) {
      if (run(p, dx, dy, color) == 5) return true;
    }
    return false;
  }

  bool hasOverline(int p, int color) {
    for (final (dx, dy) in gomokuDirs) {
      if (run(p, dx, dy, color) >= 6) return true;
    }
    return false;
  }

  /// Keys identifying the distinct black fours through p in direction d
  /// (black stone already on p). A four = 4 black stones that one more stone
  /// turns into exactly five. Open four ".XXXX." yields one key; "X.XXX.X" two.
  Set<String> _fourKeys(int p, int dx, int dy) {
    final keys = <String>{};
    final x0 = p % n, y0 = p ~/ n;
    for (var s = -4; s <= 4; s++) {
      if (s == 0) continue;
      final x = x0 + dx * s, y = y0 + dy * s;
      if (!inside(x, y) || cells[y * n + x] != 0) continue;
      final q = y * n + x;
      cells[q] = 1;
      if (run(p, dx, dy, 1) == 5) {
        // stones of the five minus q
        var b = 0;
        while (at(x0 - dx * (b + 1), y0 - dy * (b + 1)) == 1) {
          b++;
        }
        final pts = <int>[];
        for (var k = -b; k < 5 - b; k++) {
          final r = (y0 + dy * k) * n + (x0 + dx * k);
          if (r != q) pts.add(r);
        }
        keys.add(pts.join(','));
      }
      cells[q] = 0;
    }
    return keys;
  }

  /// True if black at p (already placed) has a "straight four" (open four whose
  /// both completion points make exactly five) in direction d.
  bool _straightFour(int p, int dx, int dy) {
    final x0 = p % n, y0 = p ~/ n;
    var count = 0;
    String? key;
    for (var s = -4; s <= 4; s++) {
      if (s == 0) continue;
      final x = x0 + dx * s, y = y0 + dy * s;
      if (!inside(x, y) || cells[y * n + x] != 0) continue;
      final q = y * n + x;
      cells[q] = 1;
      if (run(p, dx, dy, 1) == 5) {
        var b = 0;
        while (at(x0 - dx * (b + 1), y0 - dy * (b + 1)) == 1) {
          b++;
        }
        final pts = <int>[];
        for (var k = -b; k < 5 - b; k++) {
          final r = (y0 + dy * k) * n + (x0 + dx * k);
          if (r != q) pts.add(r);
        }
        final k = pts.join(',');
        if (key == null || key == k) {
          key = k;
          count++;
        }
      }
      cells[q] = 0;
    }
    return count >= 2;
  }

  /// Whether black at p forms a real three in direction d: some empty q on the
  /// line turns it into a straight four containing p, and q itself is not a
  /// forbidden point.
  bool _threeIn(int p, int dx, int dy, int depth) {
    final x0 = p % n, y0 = p ~/ n;
    for (var s = -3; s <= 3; s++) {
      if (s == 0) continue;
      final x = x0 + dx * s, y = y0 + dy * s;
      if (!inside(x, y) || cells[y * n + x] != 0) continue;
      final q = y * n + x;
      cells[q] = 1;
      var ok = _straightFour(p, dx, dy);
      cells[q] = 0;
      if (ok && depth < 6) {
        ok = !isForbidden(q, depth: depth + 1);
      }
      if (ok) return true;
    }
    return false;
  }

  /// Renju forbidden-point test for black at empty point p:
  /// overline, double four (4-4) or double three (3-3). Making exactly five
  /// is never forbidden.
  bool isForbidden(int p, {int depth = 0}) => forbiddenType(p, depth: depth) != null;

  /// '长连' / '四四' / '三三' if black at empty p is forbidden, else null.
  String? forbiddenType(int p, {int depth = 0}) {
    if (cells[p] != 0) return null;
    cells[p] = 1;
    try {
      if (hasExactFive(p, 1)) return null;
      if (hasOverline(p, 1)) return '长连';
      var fours = 0;
      final fourDir = List.filled(4, false);
      for (var d = 0; d < 4; d++) {
        final (dx, dy) = gomokuDirs[d];
        final k = _fourKeys(p, dx, dy).length;
        if (k > 0) fourDir[d] = true;
        fours += k;
      }
      if (fours >= 2) return '四四';
      var threes = 0;
      for (var d = 0; d < 4; d++) {
        if (fourDir[d]) continue;
        final (dx, dy) = gomokuDirs[d];
        if (_threeIn(p, dx, dy, depth)) {
          threes++;
          if (threes >= 2) return '三三';
        }
      }
      return null;
    } finally {
      cells[p] = 0;
    }
  }

  /// Result of [color] playing p under [rule]: 'win', 'forbidden' or 'none'.
  String outcome(int p, int color, GomokuRule rule) {
    if (rule == GomokuRule.renju && color == 1) {
      if (isForbidden(p)) return 'forbidden';
      cells[p] = 1;
      final w = hasExactFive(p, 1);
      cells[p] = 0;
      return w ? 'win' : 'none';
    }
    cells[p] = color;
    final w = rule == GomokuRule.standard ? hasExactFive(p, color) : fiveLine(p, color, exact: false) != null;
    cells[p] = 0;
    return w ? 'win' : 'none';
  }
}
