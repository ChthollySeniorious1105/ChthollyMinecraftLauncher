import '../../src/engine.dart';
import 'jieqi_rules.dart';

/// 揭棋
class JieqiGame extends GameEngine {
  JieqiGame(super.setup);

  static const plyCap = 300;

  late final JqPos pos;
  int redSeat = 0;
  bool publicCaptures = false;
  List<int> legalMoves = [];
  final Map<String, int> reps = {};
  List<int> lastMove = const [];
  int plies = 0;
  int winner = -2; // -2 playing, -1 draw, else seat
  String reason = '';
  int drawOffer = -1;

  /// captured[c]: pieces captured BY color c (0 red, 1 black): (type, wasHidden).
  final List<List<(int, bool)>> captured = [[], []];
  final List<String> moveList = [];

  /// Bot search budget (tests may raise the time limit for determinism).
  int botTimeMs = 300;
  int botNodes = 30000;

  int get turnSeat => pos.side > 0 ? redSeat : 1 - redSeat;
  int colorOf(int seat) => seat == redSeat ? 1 : -1;

  @override
  void start() {
    publicCaptures = setup.opt<bool>('publicCaptures', false);
    pos = JqPos.shuffledStart(rng);
    redSeat = rng.nextInt(2);
    legalMoves = pos.legal();
    reps[pos.key()] = 1;
    host.log('${name(redSeat)} 执红先行，${name(1 - redSeat)} 执黑。除帅将外所有棋子暗置，走动后翻开');
  }

  @override
  bool get isOver => winner != -2;

  @override
  List<int> get waitingFor => isOver
      ? const []
      : (drawOffer == turnSeat ? [turnSeat, 1 - turnSeat] : [turnSeat]);

  @override
  List<int>? get placings => !isOver ? null : (winner < 0 ? const [1, 1] : [for (var i = 0; i < 2; i++) i == winner ? 1 : 2]);

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('你不是对局者');
    host.log('${name(seat)} 认输');
    _finish(1 - seat, '${name(seat)} 认输');
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) throw GameError('对局已结束');
    _finish(-1, '双方同意和棋');
  }

  void _finish(int w, String why) {
    winner = w;
    reason = why;
    drawOffer = -1;
    host.log(w == -1 ? '和棋（$why）' : '${name(w)} 获胜（$why）');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat > 1) throw GameError('你不是对局者');
    switch (asStr(a['type'], 'move')) {
      case 'resign':
        resign(seat);
        return;
      case 'offerDraw':
        if (drawOffer == 1 - seat) {
          _finish(-1, '双方同意和棋');
          return;
        }
        if (drawOffer == seat) throw GameError('已经提出过和棋');
        drawOffer = seat;
        host.log('${name(seat)} 提议和棋');
        return;
      case 'acceptDraw':
        if (drawOffer != 1 - seat) throw GameError('对方没有提议和棋');
        _finish(-1, '双方同意和棋');
        return;
      case 'declineDraw':
        if (drawOffer != 1 - seat) throw GameError('对方没有提议和棋');
        drawOffer = -1;
        host.log('${name(seat)} 拒绝和棋');
        return;
      case 'move':
        break;
      default:
        throw GameError('未知操作');
    }
    if (seat != turnSeat) throw GameError('还没轮到你');
    final from = asInt(a['from']), to = asInt(a['to']);
    if (from < 0 || from >= 90 || to < 0 || to >= 90) throw GameError('无效位置');
    final m = jMove(from, to);
    if (!legalMoves.contains(m)) {
      final ps = <int>[];
      pos.gen(ps);
      if (ps.contains(m)) throw GameError(pos.inCheck() ? '必须应将' : '不能送将（或造成将帅照面）');
      throw GameError('这步棋不合法');
    }
    _apply(m);
  }

  static const redNames = ['', '帅', '仕', '相', '马', '车', '炮', '兵'];
  static const blackNames = ['', '将', '士', '象', '马', '车', '炮', '卒'];
  static const _redNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

  String _notation(int m) {
    final f = jFrom(m), t = jTo(m);
    final p = pos.b[f];
    final red = p > 0;
    final type = pos.moveType(f);
    final hid = pos.hidden[f];
    String col(int c) => red ? _redNums[8 - c] : '${c + 1}';
    String num(int n) => red ? _redNums[n - 1] : '$n';
    final fr = f ~/ 9, fc = f % 9, tr = t ~/ 9, tc = t % 9;
    final nm = (red ? redNames : blackNames)[type];
    String act, dest;
    if (fr == tr) {
      act = '平';
      dest = col(tc);
    } else {
      final forward = red ? tr > fr : tr < fr;
      act = forward ? '进' : '退';
      final straight = type == jK || type == jR || type == jC || type == jP;
      dest = straight ? num((tr - fr).abs()) : col(tc);
    }
    final base = '${hid ? '暗' : ''}$nm${col(fc)}$act$dest';
    if (!hid) return base;
    return '$base(${(red ? redNames : blackNames)[p.abs()]})';
  }

  void _apply(int m) {
    final mover = pos.side;
    final moverSeat = turnSeat;
    final t = jTo(m);
    final wasHidden = pos.hidden[jFrom(m)];
    moveList.add(_notation(m));
    final cap = pos.b[t];
    if (cap != 0) {
      captured[mover > 0 ? 0 : 1].add((cap.abs(), pos.hidden[t]));
    }
    pos.make(m);
    plies++;
    lastMove = [jFrom(m), t];
    if (wasHidden) {
      final nm = (mover > 0 ? redNames : blackNames)[pos.b[t].abs()];
      host.log('${name(moverSeat)} 翻开：$nm');
    }
    if (drawOffer == turnSeat) drawOffer = -1;
    legalMoves = pos.legal();
    final k = pos.key();
    reps[k] = (reps[k] ?? 0) + 1;
    if (legalMoves.isEmpty) {
      _finish(moverSeat, pos.inCheck() ? '绝杀' : '困毙');
    } else if (reps[k]! >= 3) {
      _finish(-1, '三次重复局面');
    } else if (pos.onlyKings()) {
      _finish(-1, '双方仅剩将帅');
    } else if (plies >= plyCap) {
      _finish(-1, '达到 $plyCap 步上限');
    } else if (pos.inCheck()) {
      host.log('${name(moverSeat)} 将军！');
    }
  }

  /// Board as seen by players: face-down pieces are ±[jHidden].
  List<int> publicBoard() => [
        for (var i = 0; i < 90; i++) pos.hidden[i] ? (pos.b[i] > 0 ? jHidden : -jHidden) : pos.b[i],
      ];

  /// Captured piece types by color as visible to [seat] (8 = unknown).
  List<List<int>> _capturedFor(int seat) {
    final out = <List<int>>[];
    for (var c = 0; c < 2; c++) {
      final capturerSeat = c == 0 ? redSeat : 1 - redSeat;
      final sees = publicCaptures || seat == capturerSeat || isOver;
      out.add([for (final (t, h) in captured[c]) h && !sees ? jHidden : t]);
    }
    return out;
  }

  @override
  Map<String, dynamic> view(int seat) {
    int? checkSq;
    if ((!isOver || reason == '绝杀') && pos.inCheck()) checkSq = pos.kings[pos.side > 0 ? 0 : 1];
    return {
      'board': publicBoard(),
      'redSeat': redSeat,
      'turn': isOver ? -1 : turnSeat,
      'side': pos.side,
      'moves': [for (final m in legalMoves) jFrom(m) * 90 + jTo(m)],
      'last': lastMove,
      'check': checkSq,
      'captured': _capturedFor(seat),
      'notation': moveList,
      'winner': winner,
      'reason': reason,
      'drawOffer': drawOffer,
      'over': isOver,
      'plies': plies,
      'publicCaptures': publicCaptures,
    };
  }

  /// Expected value (eval units) of a face-down piece of each color, from
  /// what [seat] knows: the full piece set minus revealed pieces on board and
  /// captured pieces whose identity [seat] has seen.
  List<int> hiddenValues(int seat) {
    final res = <int>[];
    for (final s in const [1, -1]) {
      final pool = List<int>.of(jPieceSet);
      void remove(int t) => pool.remove(t);
      for (var i = 0; i < 90; i++) {
        final v = pos.b[i];
        if (v != 0 && (v > 0) == (s > 0) && !pos.hidden[i] && v.abs() != jK) remove(v.abs());
      }
      // pieces of color s were captured by the other color
      final capturerColor = s > 0 ? 1 : 0;
      final capturerSeat = capturerColor == 0 ? redSeat : 1 - redSeat;
      final known = publicCaptures || seat == capturerSeat;
      for (final (t, h) in captured[capturerColor]) {
        if (!h || known) remove(t);
      }
      if (pool.isEmpty) {
        res.add(0);
        continue;
      }
      var sum = 0;
      for (final t in pool) {
        sum += jValue[t] * 10;
      }
      res.add(sum ~/ pool.length);
    }
    return res;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver) return null;
    if (drawOffer == 1 - seat) {
      final ev = jqEval(pos.sanitized(), hiddenValues(seat)) * colorOf(seat);
      return {'type': ev < -150 ? 'acceptDraw' : 'declineDraw'};
    }
    if (seat != turnSeat) return null;
    // The bot only sees the public board: search on a sanitized copy.
    final view = pos.sanitized();
    // Repetition avoidance only for moves of already revealed pieces (a reveal
    // always creates a new position, and its key would leak the identity).
    final avoid = <int>{};
    for (final m in legalMoves) {
      if (pos.hidden[jFrom(m)]) continue;
      pos.make(m);
      if ((reps[pos.key()] ?? 0) >= 2) avoid.add(m);
      pos.unmake();
    }
    final root = List<int>.of(legalMoves)..shuffle(rng);
    // 0 简单: often a random legal move, otherwise a 1-ply look;
    // 1 普通: depth 3 within [botTimeMs]/[botNodes]; 2 困难: depth 5, 1 s.
    final lvl = botLevel;
    var m = -1;
    if (lvl <= 0 && rng.nextDouble() < 0.5) {
      m = root[rng.nextInt(root.length)];
    } else {
      final search = lvl <= 0
          ? JqSearch(view, hiddenValues(seat), limitMs: 100, maxDepth: 1, maxNodes: botNodes)
          : lvl >= 2
              ? JqSearch(view, hiddenValues(seat), limitMs: 1000, maxDepth: 5, maxNodes: botNodes * 10)
              : JqSearch(view, hiddenValues(seat), limitMs: botTimeMs, maxDepth: 3, maxNodes: botNodes);
      m = search.bestMove(root, avoid: avoid);
    }
    if (m < 0 || !legalMoves.contains(m)) m = legalMoves[rng.nextInt(legalMoves.length)];
    return {'from': jFrom(m), 'to': jTo(m)};
  }

  @override
  int get botDelayMs => 400;
}
