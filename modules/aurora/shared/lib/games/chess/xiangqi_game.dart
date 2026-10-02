import '../../src/engine.dart';
import 'xiangqi_rules.dart';

/// 中国象棋
class XiangqiGame extends GameEngine {
  XiangqiGame(super.setup);

  static const plyCap = 300;

  final XqPos pos = XqPos.initial();
  int redSeat = 0;
  List<int> legalMoves = [];
  final Map<String, int> reps = {};
  List<int> lastMove = const [];
  int plies = 0;
  int winner = -2; // -2 playing, -1 draw, else seat
  String reason = '';
  int drawOffer = -1;
  final List<List<int>> captured = [[], []]; // captured[c]: piece types captured BY color c (0 red)
  final List<String> moveList = [];

  int get turnSeat => pos.side > 0 ? redSeat : 1 - redSeat;
  int colorOf(int seat) => seat == redSeat ? 1 : -1;

  @override
  void start() {
    redSeat = rng.nextInt(2);
    legalMoves = pos.legal();
    reps[pos.key()] = 1;
    host.log('${name(redSeat)} 执红先行，${name(1 - redSeat)} 执黑');
  }

  @override
  bool get isOver => winner != -2;

  @override
  List<int> get waitingFor => isOver
      ? const []
      : (drawOffer == turnSeat ? [turnSeat, 1 - turnSeat] : [turnSeat]);

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
        _finish(1 - seat, '${name(seat)} 认输');
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
    final m = xMove(asInt(a['from']), asInt(a['to']));
    if (!legalMoves.contains(m)) {
      throw GameError(_illegalReason(asInt(a['from']), asInt(a['to'])));
    }
    _apply(m);
  }

  String _illegalReason(int from, int to) {
    if (from < 0 || from >= 90 || to < 0 || to >= 90) return '无效位置';
    final ps = <int>[];
    pos.gen(ps);
    if (ps.contains(xMove(from, to))) return pos.inCheck() ? '必须应将' : '不能送将（或造成将帅照面）';
    return '这步棋不合法';
  }

  static const _redNames = ['', '帅', '仕', '相', '马', '车', '炮', '兵'];
  static const _blackNames = ['', '将', '士', '象', '马', '车', '炮', '卒'];
  static const _redNums = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

  /// Simplified move notation, e.g. 炮二平五 / 马8进7.
  String notation(int m) {
    final f = xFrom(m), t = xTo(m);
    final p = pos.b[f];
    final red = p > 0;
    final type = p.abs();
    String col(int c) => red ? _redNums[8 - c] : '${c + 1}';
    String num(int n) => red ? _redNums[n - 1] : '$n';
    final fr = f ~/ 9, fc = f % 9, tr = t ~/ 9, tc = t % 9;
    final nm = red ? _redNames[type] : _blackNames[type];
    String act;
    String dest;
    if (fr == tr) {
      act = '平';
      dest = col(tc);
    } else {
      final forward = red ? tr > fr : tr < fr;
      act = forward ? '进' : '退';
      final straight = type == xK || type == xR || type == xC || type == xP;
      dest = straight ? num((tr - fr).abs()) : col(tc);
    }
    return '$nm${col(fc)}$act$dest';
  }

  void _apply(int m) {
    final mover = pos.side;
    moveList.add(notation(m));
    final cap = pos.b[xTo(m)].abs();
    if (cap != 0) captured[mover > 0 ? 0 : 1].add(cap);
    pos.make(m);
    plies++;
    lastMove = [xFrom(m), xTo(m)];
    if (drawOffer == turnSeat) drawOffer = -1;
    legalMoves = pos.legal();
    final k = pos.key();
    reps[k] = (reps[k] ?? 0) + 1;
    final moverSeat = mover > 0 ? redSeat : 1 - redSeat;
    if (legalMoves.isEmpty) {
      _finish(moverSeat, pos.inCheck() ? '绝杀' : '困毙');
    } else if (reps[k]! >= 3) {
      _finish(-1, '三次重复局面');
    } else if (pos.noAttackers()) {
      _finish(-1, '双方均无过河子力');
    } else if (plies >= plyCap) {
      _finish(-1, '达到 $plyCap 步上限');
    } else if (pos.inCheck()) {
      host.log('${name(moverSeat)} 将军！');
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    int? checkSq;
    if ((!isOver || reason == '绝杀') && pos.inCheck()) checkSq = pos.kings[pos.side > 0 ? 0 : 1];
    return {
      'board': List<int>.of(pos.b),
      'redSeat': redSeat,
      'turn': isOver ? -1 : turnSeat,
      'side': pos.side,
      'moves': [for (final m in legalMoves) xFrom(m) * 90 + xTo(m)],
      'last': lastMove,
      'check': checkSq,
      'captured': captured,
      'notation': moveList,
      'winner': winner,
      'reason': reason,
      'drawOffer': drawOffer,
      'over': isOver,
      'plies': plies,
    };
  }

  @override
  List<int>? get placings => !isOver ? null : (winner < 0 ? [1, 1] : [for (var s = 0; s < 2; s++) s == winner ? 1 : 2]);

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver || seat < 0 || seat > 1) return;
    host.log('${name(seat)} 认输');
    _finish(1 - seat, '${name(seat)} 认输');
  }

  @override
  bool get canDraw => !isOver;

  @override
  void agreeDraw() {
    if (isOver) return;
    _finish(-1, '双方同意和棋');
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver) return null;
    if (drawOffer == 1 - seat) {
      final ev = xqEval(pos) * colorOf(seat);
      return {'type': ev < -150 ? 'acceptDraw' : 'declineDraw'};
    }
    if (seat != turnSeat) return null;
    // avoid moves that would repeat a position already seen twice (unless forced)
    final avoid = <int>{};
    for (final m in legalMoves) {
      pos.make(m);
      if ((reps[pos.key()] ?? 0) >= 2) avoid.add(m);
      pos.unmake();
    }
    // 简单: often a random move, otherwise a 1-ply search; 困难: deeper, longer search
    if (botLevel <= 0 && rng.nextDouble() < 0.35) {
      final m = legalMoves[rng.nextInt(legalMoves.length)];
      return {'from': xFrom(m), 'to': xTo(m)};
    }
    final search = botLevel <= 0
        ? XqSearch(pos, limitMs: 100, maxDepth: 1, rng: rng)
        : (botLevel >= 2 ? XqSearch(pos, limitMs: 1000, maxDepth: 6, rng: rng) : XqSearch(pos, limitMs: 300, maxDepth: 3, rng: rng));
    var m = search.bestMove(avoid: avoid);
    if (m < 0 || !legalMoves.contains(m)) m = legalMoves[rng.nextInt(legalMoves.length)];
    return {'from': xFrom(m), 'to': xTo(m)};
  }

  @override
  int get botDelayMs => 400;
}
