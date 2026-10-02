import '../../src/engine.dart';
import 'chess_rules.dart';

/// 国际象棋
class ChessGame extends GameEngine {
  ChessGame(super.setup);

  static const plyCap = 300;

  final ChessPos pos = ChessPos.initial();
  int whiteSeat = 0;
  List<int> legalMoves = [];
  final List<String> sanList = [];
  final Map<String, int> reps = {};
  List<int> lastMove = const [];
  int plies = 0;
  int winner = -2; // -2 playing, -1 draw, else seat
  String reason = '';
  int drawOffer = -1;
  final List<List<int>> captured = [[], []]; // captured[c] = pieces captured BY color c (0 white)

  int get turnSeat => pos.side > 0 ? whiteSeat : 1 - whiteSeat;
  int colorOf(int seat) => seat == whiteSeat ? 1 : -1;

  @override
  void start() {
    whiteSeat = rng.nextInt(2);
    legalMoves = pos.legal();
    reps[pos.key()] = 1;
    host.log('${name(whiteSeat)} 执白先行，${name(1 - whiteSeat)} 执黑');
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
    final type = asStr(a['type'], 'move');
    switch (type) {
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
    final from = asInt(a['from']), to = asInt(a['to']);
    var promo = asInt(a['promo'], 0);
    final cands = [for (final m in legalMoves) if (mFrom(m) == from && mTo(m) == to) m];
    if (cands.isEmpty) throw GameError('这步棋不合法');
    int move;
    if (cands.length > 1) {
      if (promo == 0) promo = cQ;
      move = cands.firstWhere((m) => mPromo(m) == promo, orElse: () => throw GameError('无效的升变棋子'));
    } else {
      move = cands.first;
    }
    _apply(move);
  }

  void _apply(int m) {
    final mover = pos.side;
    final san = pos.san(m, legalMoves);
    final capPiece = mFlag(m) & fEp != 0 ? cP : pos.b[mTo(m)].abs();
    if (capPiece != 0) captured[mover > 0 ? 0 : 1].add(capPiece);
    pos.make(m);
    plies++;
    sanList.add(san);
    lastMove = [mFrom(m), mTo(m)];
    if (drawOffer == turnSeat) drawOffer = -1; // offer answered by moving on (declined)
    legalMoves = pos.legal();
    final k = pos.key();
    reps[k] = (reps[k] ?? 0) + 1;
    final moverSeat = mover > 0 ? whiteSeat : 1 - whiteSeat;
    if (legalMoves.isEmpty) {
      if (pos.inCheck()) {
        _finish(moverSeat, '将杀');
      } else {
        _finish(-1, '逼和');
      }
    } else if (reps[k]! >= 3) {
      _finish(-1, '三次重复局面');
    } else if (pos.half >= 100) {
      _finish(-1, '50 回合规则');
    } else if (pos.insufficientMaterial()) {
      _finish(-1, '子力不足以将杀');
    } else if (plies >= plyCap) {
      _finish(-1, '达到 $plyCap 步上限');
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    int? checkSq;
    if (!isOver || reason == '将杀') {
      if (pos.inCheck()) checkSq = pos.kings[pos.side > 0 ? 0 : 1];
    }
    return {
      'board': List<int>.of(pos.b),
      'whiteSeat': whiteSeat,
      'turn': isOver ? -1 : turnSeat,
      'side': pos.side,
      'moves': [for (final m in legalMoves) mFrom(m) * 64 + mTo(m)],
      'last': lastMove,
      'check': checkSq,
      'san': sanList,
      'captured': captured,
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
      final ev = chessEval(pos) * colorOf(seat);
      return {'type': ev < -150 ? 'acceptDraw' : 'declineDraw'};
    }
    if (seat != turnSeat) return null;
    // 简单: often a random move, otherwise a 1-ply search; 困难: deeper, longer search
    if (botLevel <= 0 && rng.nextDouble() < 0.35) {
      final m = legalMoves[rng.nextInt(legalMoves.length)];
      return {'from': mFrom(m), 'to': mTo(m), 'promo': mPromo(m)};
    }
    final search = botLevel <= 0
        ? ChessSearch(pos, limitMs: 100, maxDepth: 1, rng: rng)
        : (botLevel >= 2 ? ChessSearch(pos, limitMs: 1000, maxDepth: 6, rng: rng) : ChessSearch(pos, limitMs: 300, maxDepth: 3, rng: rng));
    final avoid = <int>{};
    if (chessEval(pos) * colorOf(seat) > -100) {
      for (final mv in legalMoves) {
        pos.make(mv);
        if ((reps[pos.key()] ?? 0) >= 2) avoid.add(mv);
        pos.unmake();
      }
    }
    var m = search.bestMove(avoid: avoid);
    if (m < 0 || !legalMoves.contains(m)) m = legalMoves[rng.nextInt(legalMoves.length)];
    return {'from': mFrom(m), 'to': mTo(m), 'promo': mPromo(m)};
  }

  @override
  int get botDelayMs => 400;
}
