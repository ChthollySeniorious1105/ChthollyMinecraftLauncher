/// 国际跳棋 / 英式跳棋 规则核心。
///
/// board[r*n+c]: 0 空, 1 先手兵, 2 先手王, -1 后手兵, -2 后手王。
/// 先手（side 1）在下方向上走（行号减小），后手（side -1）在上方向下走。
/// 只有深色格 (r+c) 奇数 可放棋子。
library;

class DMove {
  final List<int> path;
  final List<int> caps;
  const DMove(this.path, this.caps);
  int get from => path.first;
  int get to => path.last;
  bool get isCapture => caps.isNotEmpty;
  @override
  String toString() => '${path.join(caps.isEmpty ? '-' : 'x')}';
}

class DraughtsRules {
  final int n;
  final bool intl;
  const DraughtsRules(this.n, this.intl);

  static const dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)];

  List<int> initial() {
    final b = List.filled(n * n, 0);
    final rowsEach = intl ? 4 : 3;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if ((r + c) % 2 == 0) continue;
        if (r < rowsEach) b[r * n + c] = -1;
        if (r >= n - rowsEach) b[r * n + c] = 1;
      }
    }
    return b;
  }

  bool _in(int r, int c) => r >= 0 && c >= 0 && r < n && c < n;

  bool promotes(int side, int p) => side > 0 ? p ~/ n == 0 : p ~/ n == n - 1;

  /// All legal moves for [side] (1 / -1), mandatory-capture rules applied.
  List<DMove> legal(List<int> b, int side) {
    final caps = <DMove>[];
    for (var p = 0; p < n * n; p++) {
      if (b[p] * side > 0) _captures(b, p, side, caps);
    }
    if (caps.isNotEmpty) {
      if (!intl) return caps;
      var mx = 0;
      for (final m in caps) {
        if (m.caps.length > mx) mx = m.caps.length;
      }
      // dedupe identical paths
      final seen = <String>{};
      return [
        for (final m in caps)
          if (m.caps.length == mx && seen.add(m.path.join(','))) m
      ];
    }
    final out = <DMove>[];
    for (var p = 0; p < n * n; p++) {
      final v = b[p] * side;
      if (v <= 0) continue;
      final r0 = p ~/ n, c0 = p % n;
      for (final (dr, dc) in dirs) {
        if (v == 1 && dr != -side) continue; // men step forward only
        var r = r0 + dr, c = c0 + dc;
        while (_in(r, c) && b[r * n + c] == 0) {
          out.add(DMove([p, r * n + c], const []));
          if (v == 1 || !intl) break; // English kings and all men step 1
          r += dr;
          c += dc;
        }
      }
    }
    return out;
  }

  void _captures(List<int> b, int from, int side, List<DMove> out) {
    final king = b[from].abs() == 2;
    final saved = b[from];
    b[from] = 0; // lifted while moving
    _dfs(b, from, side, king, [from], <int>[], out);
    b[from] = saved;
  }

  void _dfs(List<int> b, int pos, int side, bool king, List<int> path, List<int> caps, List<DMove> out) {
    final r0 = pos ~/ n, c0 = pos % n;
    var extended = false;
    for (final (dr, dc) in dirs) {
      if (!king && !intl && dr != -side) continue; // English men capture forward only
      if (king && intl) {
        // flying king
        var r = r0 + dr, c = c0 + dc;
        while (_in(r, c) && b[r * n + c] == 0) {
          r += dr;
          c += dc;
        }
        if (!_in(r, c)) continue;
        final mid = r * n + c;
        if (b[mid] * side >= 0 || caps.contains(mid)) continue;
        r += dr;
        c += dc;
        while (_in(r, c) && b[r * n + c] == 0) {
          final land = r * n + c;
          extended = true;
          path.add(land);
          caps.add(mid);
          _dfs(b, land, side, true, path, caps, out);
          path.removeLast();
          caps.removeLast();
          r += dr;
          c += dc;
        }
      } else {
        final mr = r0 + dr, mc = c0 + dc, lr = r0 + 2 * dr, lc = c0 + 2 * dc;
        if (!_in(lr, lc)) continue;
        final mid = mr * n + mc, land = lr * n + lc;
        if (b[mid] * side >= 0 || caps.contains(mid) || b[land] != 0) continue;
        extended = true;
        path.add(land);
        caps.add(mid);
        if (!intl && !king && promotes(side, land)) {
          // English: crowning ends the move
          out.add(DMove(List.of(path), List.of(caps)));
        } else {
          _dfs(b, land, side, king, path, caps, out);
        }
        path.removeLast();
        caps.removeLast();
      }
    }
    if (!extended && caps.isNotEmpty) out.add(DMove(List.of(path), List.of(caps)));
  }

  /// Applies [m] in place. Returns true if the piece was crowned.
  bool apply(List<int> b, DMove m) {
    final v = b[m.from];
    b[m.from] = 0;
    for (final c in m.caps) {
      b[c] = 0;
    }
    final side = v > 0 ? 1 : -1;
    if (v.abs() == 1 && promotes(side, m.to)) {
      b[m.to] = 2 * side;
      return true;
    }
    b[m.to] = v;
    return false;
  }

  /// Square number in standard notation (1-based dark squares from the top-left).
  int notation(int p) {
    final r = p ~/ n, c = p % n;
    return r * (n ~/ 2) + c ~/ 2 + 1;
  }
}
