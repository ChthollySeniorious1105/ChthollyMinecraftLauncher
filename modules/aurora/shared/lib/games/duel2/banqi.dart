import 'dart:math';

import '../../src/engine.dart';

/// Piece codes as in xiangqi: sign = colour (+ red, − black), abs:
/// 1 帅/将, 2 仕/士, 3 相/象, 4 马, 5 车, 6 炮, 7 兵/卒.
const List<int> bqCountPerSide = [0, 1, 2, 2, 2, 2, 2, 5];

/// Banqi rank (higher captures lower): 帅7 仕6 相5 车4 马3 炮2 兵1.
const List<int> bqRank = [0, 7, 6, 5, 3, 4, 2, 1];
const List<String> bqRedNames = ['', '帅', '仕', '相', '马', '车', '炮', '兵'];
const List<String> bqBlackNames = ['', '将', '士', '象', '马', '车', '炮', '卒'];
String bqName(int p) => (p > 0 ? bqRedNames : bqBlackNames)[p.abs()];

/// Material values used by the bot.
const List<double> bqValue = [0, 38, 22, 14, 7, 10, 12, 4];

const int bqRows = 4, bqCols = 8, bqSize = 32;

List<int> bqNeighbors(int s) {
  final r = s ~/ bqCols, c = s % bqCols;
  return [
    if (r > 0) s - bqCols,
    if (r < bqRows - 1) s + bqCols,
    if (c > 0) s - 1,
    if (c < bqCols - 1) s + 1,
  ];
}

/// Whether piece [a] may capture piece [t] (ignoring geometry / cannon).
bool bqCanTake(int a, int t) {
  final x = a.abs(), y = t.abs();
  if (x == 7) return y == 7 || y == 1;
  if (x == 1) return y != 7;
  return bqRank[x] >= bqRank[y];
}

/// Pure position used by both the engine and the bot search.
class BqPos {
  final List<int> board; // 0 empty
  final List<bool> hidden;
  BqPos(this.board, this.hidden);
  BqPos copy() => BqPos(List.of(board), List.of(hidden));

  /// All non-flip moves for [color] as from*32+to.
  List<int> moves(int color) {
    final out = <int>[];
    for (var s = 0; s < bqSize; s++) {
      final p = board[s];
      if (p == 0 || hidden[s] || (p > 0 ? 1 : -1) != color) continue;
      if (p.abs() == 6) {
        for (final n in bqNeighbors(s)) {
          if (board[n] == 0) out.add(s * bqSize + n);
        }
        // jumps
        for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          var r = s ~/ bqCols + dr, c = s % bqCols + dc;
          var screens = 0;
          while (r >= 0 && r < bqRows && c >= 0 && c < bqCols) {
            final t = r * bqCols + c;
            if (board[t] != 0) {
              if (screens == 1) {
                if (!hidden[t] && (board[t] > 0 ? 1 : -1) != color) out.add(s * bqSize + t);
                break;
              }
              screens++;
            }
            r += dr;
            c += dc;
          }
        }
      } else {
        for (final n in bqNeighbors(s)) {
          final t = board[n];
          if (t == 0) {
            out.add(s * bqSize + n);
          } else if (!hidden[n] && (t > 0 ? 1 : -1) != color && bqCanTake(p, t)) {
            out.add(s * bqSize + n);
          }
        }
      }
    }
    return out;
  }

  bool get anyHidden => hidden.contains(true);

  /// Best immediate capture value available to [color] (0 if none).
  double bestCapture(int color) {
    var best = 0.0;
    for (final m in moves(color)) {
      final t = board[m % bqSize];
      if (t != 0) best = max(best, bqValue[t.abs()]);
    }
    return best;
  }
}

class Banqi extends GameEngine {
  Banqi(super.setup);

  int get drawLimit => setup.opt<int>('drawRule', 50);

  late BqPos pos;
  int turn = 0;
  /// Colour of seat 0 (1 red / −1 black), 0 = not decided yet.
  int color0 = 0;
  int quiet = 0;
  int plies = 0;
  bool over = false;
  int winnerSeat = -1; // -2 draw
  String reason = '';
  List<int> last = [];
  final List<List<int>> captured = [[], []]; // [red pieces lost, black pieces lost]
  final List<String> notation = [];
  final List<int> _lastOwn = [-1, -1]; // last move (from*32+to) per seat

  int colorOf(int seat) => color0 == 0 ? 0 : (seat == 0 ? color0 : -color0);
  int seatOfColor(int c) => color0 == 0 ? -1 : (c == color0 ? 0 : 1);

  @override
  void start() {
    final pieces = <int>[
      for (var k = 1; k <= 7; k++)
        for (var i = 0; i < bqCountPerSide[k]; i++) ...[k, -k],
    ];
    pos = BqPos(shuffled(pieces, rng), List.filled(bqSize, true));
    turn = rng.nextInt(2);
    host.log('暗棋开始，${name(turn)} 先手翻棋');
  }

  String _sq(int s) => '${String.fromCharCode(97 + s % bqCols)}${s ~/ bqCols + 1}';

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('游戏已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'flip') {
      final s = asInt(a['sq']);
      if (s < 0 || s >= bqSize || !pos.hidden[s]) throw GameError('这里没有暗棋');
      pos.hidden[s] = false;
      final p = pos.board[s];
      if (color0 == 0) {
        final c = p > 0 ? 1 : -1;
        color0 = seat == 0 ? c : -c;
        host.log('${name(seat)} 翻出${bqName(p)}，执${c > 0 ? '红' : '黑'}方');
      }
      quiet = 0;
      last = [s];
      notation.add('翻${_sq(s)}=${bqName(p)}');
    } else if (type == 'move') {
      final from = asInt(a['from']), to = asInt(a['to']);
      if (color0 == 0) throw GameError('请先翻棋');
      if (from < 0 || from >= bqSize || to < 0 || to >= bqSize) throw GameError('无效位置');
      if (!pos.moves(colorOf(seat)).contains(from * bqSize + to)) throw GameError('不合法的走法');
      final p = pos.board[from];
      final t = pos.board[to];
      if (t != 0) {
        captured[t > 0 ? 0 : 1].add(t);
        quiet = 0;
        notation.add('${bqName(p)}${_sq(from)}吃${bqName(t)}${_sq(to)}');
      } else {
        quiet++;
        notation.add('${bqName(p)}${_sq(from)}-${_sq(to)}');
      }
      pos.board[to] = p;
      pos.board[from] = 0;
      last = [from, to];
      _lastOwn[seat] = from * bqSize + to;
    } else {
      throw GameError('未知操作');
    }
    plies++;
    turn = 1 - turn;
    _checkEnd();
  }

  bool hasPieces(int seat) {
    final c = colorOf(seat);
    for (var s = 0; s < bqSize; s++) {
      final p = pos.board[s];
      if (p != 0 && (p > 0 ? 1 : -1) == c) return true;
    }
    return false;
  }

  bool hasMove(int seat) => pos.anyHidden || pos.moves(colorOf(seat)).isNotEmpty;

  void _checkEnd() {
    if (color0 == 0) return;
    if (!hasPieces(turn)) {
      _finish(1 - turn, '${name(turn)} 的棋子被吃光');
    } else if (!hasMove(turn)) {
      _finish(1 - turn, '${name(turn)} 无子可动');
    } else if (drawLimit > 0 && quiet >= drawLimit) {
      _finish(-2, '连续 $drawLimit 步无吃子、无翻棋');
    }
  }

  void _finish(int w, String why) {
    over = true;
    winnerSeat = w;
    reason = why;
    for (var s = 0; s < bqSize; s++) {
      pos.hidden[s] = false;
    }
    host.log(w == -2 ? '和棋：$why' : '${name(w)} 获胜（$why）');
  }

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => !over ? null : (winnerSeat == -2 ? [1, 1] : rankWinners(2, [winnerSeat]));

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('游戏已结束');
    if (seat < 0 || seat > 1) throw GameError('无效座位');
    _finish(1 - seat, '${name(seat)} 认输');
  }

  @override
  bool get canDraw => !over;

  @override
  void agreeDraw() {
    if (over) throw GameError('游戏已结束');
    _finish(-2, '双方同意和棋');
  }

  /// Pieces still face-down (composition is public knowledge).
  List<int> hiddenPool() {
    final pool = <int>[
      for (var k = 1; k <= 7; k++)
        for (var i = 0; i < bqCountPerSide[k]; i++) ...[k, -k],
    ];
    for (var s = 0; s < bqSize; s++) {
      if (pos.board[s] != 0 && !pos.hidden[s]) pool.remove(pos.board[s]);
    }
    for (final l in captured) {
      for (final p in l) {
        pool.remove(p);
      }
    }
    return pool;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'board': [for (var s = 0; s < bqSize; s++) pos.hidden[s] ? 99 : pos.board[s]],
        'turn': turn,
        'color0': color0,
        'quiet': quiet,
        'drawLimit': drawLimit,
        'plies': plies,
        'last': last,
        'captured': captured,
        'hiddenPool': over ? <int>[] : hiddenPool(),
        'notation': notation,
        'winner': over ? winnerSeat : -1,
        'reason': reason,
        'placings': placings,
      };

  // ------------------------------------------------------------------ bot
  // The bot sees the board with hidden squares unknown; it reasons about a
  // flip as the average over the public pool of face-down pieces.

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat != turn) return null;
    final hiddenSq = [for (var s = 0; s < bqSize; s++) if (pos.hidden[s]) s];
    if (color0 == 0) {
      // opening flip: prefer squares away from edges? any is fine
      return {'type': 'flip', 'sq': hiddenSq[rng.nextInt(hiddenSq.length)]};
    }
    final me = colorOf(seat);
    // the bot's own knowledge: board with hidden squares masked
    final known = BqPos([for (var s = 0; s < bqSize; s++) pos.hidden[s] ? 0 : pos.board[s]], List.filled(bqSize, false));
    for (var s = 0; s < bqSize; s++) {
      if (pos.hidden[s]) {
        known.board[s] = 99; // placeholder blocker: occupied, unknown
        known.hidden[s] = true;
      }
    }
    final pool = hiddenPool();
    final moves = known.moves(me);
    final noise = botLevel == 0 ? 8.0 : (botLevel == 1 ? 2.0 : 0.4);

    if (botLevel == 0 && rng.nextDouble() < 0.4) {
      final opts = [for (final m in moves) {'type': 'move', 'from': m ~/ bqSize, 'to': m % bqSize}, for (final s in hiddenSq) {'type': 'flip', 'sq': s}];
      return opts[rng.nextInt(opts.length)];
    }

    double evalAfter(BqPos p) {
      // material on board (revealed) + threat of best opponent reply
      var m = 0.0;
      for (var s = 0; s < bqSize; s++) {
        final x = p.board[s];
        if (x == 0 || p.hidden[s]) continue;
        m += (x > 0 ? 1 : -1) == me ? bqValue[x.abs()] : -bqValue[x.abs()];
      }
      final threat = p.bestCapture(-me);
      var v = m - threat * (botLevel >= 2 ? 0.9 : 0.7);
      if (botLevel >= 2) {
        v += p.bestCapture(me) * 0.25;
        // hunt: bring pieces closer to enemy pieces they can capture
        for (var s = 0; s < bqSize; s++) {
          final x = p.board[s];
          if (x == 0 || p.hidden[s] || (x > 0 ? 1 : -1) != me || x.abs() == 6) continue;
          var dmin = 99;
          for (var t = 0; t < bqSize; t++) {
            final y = p.board[t];
            if (y == 0 || p.hidden[t] || (y > 0 ? 1 : -1) == me || !bqCanTake(x, y)) continue;
            final d = (s ~/ bqCols - t ~/ bqCols).abs() + (s % bqCols - t % bqCols).abs();
            if (d < dmin) dmin = d;
          }
          if (dmin < 99) v -= dmin * 0.12;
        }
      }
      return v;
    }

    Map<String, dynamic>? best;
    var bv = -double.infinity;
    for (final mv in moves) {
      final f = mv ~/ bqSize, t = mv % bqSize;
      final np = known.copy();
      np.board[t] = np.board[f];
      np.board[f] = 0;
      var v = evalAfter(np);
      // avoid pointless shuffling when nothing happens
      if (known.board[t] == 0) v -= 0.3;
      // don't undo the previous own move (back-and-forth shuffling)
      if (_lastOwn[seat] == t * bqSize + f) v -= 0.6;
      if (botLevel >= 1 && quiet >= drawLimit - 4 && drawLimit > 0 && known.board[t] == 0) v -= 2;
      v += rng.nextDouble() * noise;
      if (v > bv) {
        bv = v;
        best = {'type': 'move', 'from': f, 'to': t};
      }
    }
    if (hiddenSq.isNotEmpty && pool.isNotEmpty) {
      final counts = <int, int>{};
      for (final p in pool) {
        counts[p] = (counts[p] ?? 0) + 1;
      }
      // sample a subset of squares for speed
      final squares = botLevel >= 2 ? hiddenSq : (shuffled(hiddenSq, rng).take(6).toList());
      for (final s in squares) {
        var ev = 0.0;
        for (final e in counts.entries) {
          final np = known.copy();
          np.board[s] = e.key;
          np.hidden[s] = false;
          ev += evalAfter(np) * e.value / pool.length;
        }
        var v = ev + 0.2 + rng.nextDouble() * noise;
        if (botLevel >= 1 && quiet >= drawLimit - 4 && drawLimit > 0) v += 2;
        if (v > bv) {
          bv = v;
          best = {'type': 'flip', 'sq': s};
        }
      }
    }
    return best;
  }
}

const String banqiRules = '''
# 概述
暗棋（台湾暗棋、翻翻棋）使用一副象棋的 32 枚棋子，在半张棋盘的 4×8 = 32 个格子上进行。开局所有棋子背面朝上随机摆放，谁也不知道下面是什么，双方轮流翻棋、走棋和吃子，运气与计算并重。

# 决定颜色
先手方第一步必须翻开一枚棋子：翻出红棋就执红，翻出黑棋就执黑，对手执另一种颜色。之后翻出的棋子无论颜色都归各自所属的一方。

# 回合
每回合做下面三件事之一：
- 翻棋：翻开任意一枚暗棋。
- 走棋：把自己一枚已翻开的棋子向上下左右移动一格到空格。
- 吃子：把自己的棋子移动到相邻（上下左右一格）的已翻开敌方棋子上将其吃掉。暗棋不能被吃。

# 大小等级
帅（将）> 仕（士）> 相（象）> 车 > 马 > 炮 > 兵（卒）。大的可以吃小的，同级可以互吃。特例：
- 兵（卒）可以吃帅（将），而帅（将）不能吃兵（卒）。兵只能吃兵和帅。
- 炮的吃法特殊：必须沿直线隔着恰好一枚棋子（明暗、敌我都可以当炮架）跳吃，距离不限；炮可以吃任何等级的敌方明子，但不能吃相邻的棋子。炮平时走法与其他棋子相同（一格）。

# 胜负
- 一方的棋子全部被吃光，或轮到他时无棋可走（没有暗棋可翻、所有明子都无法移动），则判负。
- 和棋：连续若干步（选项，默认 50 步）双方都没有吃子也没有翻棋，判为和棋；也可以双方同意和棋。
- 可以认输。

# 隐藏信息
暗棋背面朝上，任何人（包括电脑玩家）都看不到；界面会显示尚未翻开的棋子还剩哪些，帮助你计算翻棋的风险。由于开局是随机暗棋，本游戏不支持悔棋。
''';
