import '../../src/engine.dart';
import 'shogi_rules.dart';

/// 将棋
class ShogiGame extends GameEngine {
  ShogiGame(super.setup);

  static const plyCap = 400;

  late final ShogiPos pos;
  int senteSeat = 0;
  int handicap = 0;
  List<int> legalMoves = [];
  final Map<String, List<int>> occurrences = {}; // key -> history indices
  final List<bool> checkHist = []; // checkHist[i]: side to move in position i is in check
  final List<int> sideHist = []; // side to move in position i
  List<int> lastMove = const [];
  int plies = 0;
  int winner = -2; // -2 playing, -1 draw, else seat
  String reason = '';
  int drawOffer = -1;
  final List<String> moveList = [];

  int get turnSeat => pos.side > 0 ? senteSeat : 1 - senteSeat;
  int colorOf(int seat) => seat == senteSeat ? 1 : -1;

  static const handicapNames = ['平手', '让香', '让角', '让飞', '让二枚'];

  @override
  void start() {
    handicap = setup.opt<int>('handicap', 0).clamp(0, 4);
    pos = ShogiPos.initial(handicap);
    senteSeat = rng.nextInt(2);
    legalMoves = pos.legal();
    _record();
    if (handicap == 0) {
      host.log('${name(senteSeat)} 先手（☗），${name(1 - senteSeat)} 后手（☖）');
    } else {
      host.log('${handicapNames[handicap]}：${name(1 - senteSeat)} 为上手（☖，先走），${name(senteSeat)} 为下手（☗）');
    }
  }

  void _record() {
    final k = pos.key();
    (occurrences[k] ??= []).add(checkHist.length);
    checkHist.add(pos.inCheck());
    sideHist.add(pos.side);
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
      case 'drop':
        break;
      default:
        throw GameError('未知操作');
    }
    if (seat != turnSeat) throw GameError('还没轮到你');
    final int m;
    final to = asInt(a['to']);
    if (to < 0 || to >= 81) throw GameError('无效位置');
    if (asStr(a['type'], 'move') == 'drop') {
      final t = asInt(a['piece']);
      if (t < 1 || t > 7) throw GameError('无效棋子');
      m = sgMove(81 + t, to);
    } else {
      final from = asInt(a['from']);
      if (from < 0 || from >= 81) throw GameError('无效位置');
      m = sgMove(from, to, asBool(a['promote']));
    }
    if (!legalMoves.contains(m)) throw GameError(_illegalReason(m));
    _apply(m);
  }

  String _illegalReason(int m) {
    final ps = <int>[];
    pos.gen(ps);
    if (ps.contains(m)) {
      if (sgIsDrop(m) && sgDropType(m) == sgP) {
        final me = pos.side;
        pos.make(m);
        final selfCheck = pos.kingAttacked(me);
        pos.unmake();
        if (!selfCheck) return '打步诘：不能用打入的步将死对方';
      }
      return pos.inCheck() ? '必须应将' : '不能送将';
    }
    if (sgIsDrop(m)) {
      final t = sgDropType(m);
      final hand = pos.hands[pos.side > 0 ? 0 : 1];
      if (hand[t] == 0) return '驹台上没有这个棋子';
      if (pos.b[sgTo(m)] != 0) return '只能打在空格上';
      if (t == sgP) {
        final c = sgTo(m) % 9;
        for (var r = 0; r < 9; r++) {
          if (pos.b[r * 9 + c] == sgP * pos.side) return '二步：同一纵列不能有两个未升变的步';
        }
      }
      if (ShogiPos.deadEnd(t, sgTo(m) ~/ 9, pos.side)) return '不能打在无法再走的位置';
      return '这步棋不合法';
    }
    if (ps.contains(m ^ (1 << 14))) {
      return sgIsPromo(m) ? '这步不能升变' : '此处必须升变（否则无法再走）';
    }
    return '这步棋不合法';
  }

  static const kanji = ['', '歩', '香', '桂', '銀', '金', '角', '飛', '玉', 'と', '成香', '成桂', '成銀', '', '馬', '龍'];
  static const _files = ['１', '２', '３', '４', '５', '６', '７', '８', '９'];
  static const _ranks = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];

  /// Japanese-style notation, e.g. ☗７六歩 / ☖同　角成 / ☗５五角打.
  String notation(int m) {
    final to = sgTo(m);
    final mark = pos.side > 0 ? '☗' : '☖';
    final dest = lastMove.length == 2 && lastMove[1] == to
        ? '同'
        : '${_files[8 - to % 9]}${_ranks[to ~/ 9]}';
    if (sgIsDrop(m)) {
      final t = sgDropType(m);
      // 打 is only required when a board piece could also reach; keep it simple and always write it
      return '$mark$dest${kanji[t]}打';
    }
    final from = sgFrom(m);
    final p = pos.b[from].abs();
    var s = '$mark$dest${p == sgK && pos.side < 0 ? '王' : kanji[p]}';
    if (sgIsPromo(m)) {
      s += '成';
    } else if (sgCanPromote(p)) {
      final inZone = pos.side > 0 ? (from < 27 || to < 27) : (from >= 54 || to >= 54);
      if (inZone) s += '不成';
    }
    return s;
  }

  void _apply(int m) {
    final mover = pos.side;
    final moverSeat = turnSeat;
    moveList.add(notation(m));
    pos.make(m);
    plies++;
    lastMove = sgIsDrop(m) ? [sgTo(m)] : [sgFrom(m), sgTo(m)];
    if (drawOffer == turnSeat) drawOffer = -1;
    legalMoves = pos.legal();
    _record();
    final k = pos.key();
    final occ = occurrences[k]!;
    if (legalMoves.isEmpty) {
      _finish(moverSeat, pos.inCheck() ? '将死' : '对方无子可动');
      return;
    }
    if (occ.length >= 4) {
      // 千日手: check whether one side checked continuously since the first occurrence
      final first = occ.first, now = occ.last;
      bool perpetual(int side) {
        var any = false;
        for (var i = first + 1; i <= now; i++) {
          if (sideHist[i] == -side) {
            any = true;
            if (!checkHist[i]) return false;
          }
        }
        return any;
      }

      if (perpetual(mover)) {
        _finish(1 - moverSeat, '连续将军的千日手，${name(moverSeat)} 判负');
      } else if (perpetual(-mover)) {
        _finish(moverSeat, '连续将军的千日手，${name(1 - moverSeat)} 判负');
      } else {
        _finish(-1, '千日手');
      }
      return;
    }
    if (plies >= plyCap) {
      _finish(-1, '持将棋（达到 $plyCap 手上限）');
    } else if (pos.inCheck()) {
      host.log('${name(moverSeat)} 王手！');
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    int? checkSq;
    if ((!isOver || reason.startsWith('将死')) && pos.inCheck()) checkSq = pos.kings[pos.side > 0 ? 0 : 1];
    // moves: from*1000 + to*10 + flag (0 不成 only, 1 必成, 2 可选); drops: from = 81 + piece
    final enc = <int, int>{};
    for (final m in legalMoves) {
      final key = sgFrom(m) * 1000 + sgTo(m) * 10;
      final prev = enc[key];
      final f = sgIsPromo(m) ? 1 : 0;
      enc[key] = prev == null ? f : 2;
    }
    return {
      'board': List<int>.of(pos.b),
      'hands': [List<int>.of(pos.hands[0]), List<int>.of(pos.hands[1])],
      'senteSeat': senteSeat,
      'handicap': handicap,
      'turn': isOver ? -1 : turnSeat,
      'side': pos.side,
      'moves': [for (final e in enc.entries) e.key + e.value],
      'last': lastMove,
      'check': checkSq,
      'notation': moveList,
      'winner': winner,
      'reason': reason,
      'drawOffer': drawOffer,
      'over': isOver,
      'plies': plies,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (isOver) return null;
    if (drawOffer == 1 - seat) {
      final ev = shogiEval(pos) * colorOf(seat);
      return {'type': ev < -600 ? 'acceptDraw' : 'declineDraw'};
    }
    if (seat != turnSeat) return null;
    final avoid = <int>{};
    for (final m in legalMoves) {
      pos.make(m);
      if ((occurrences[pos.key()]?.length ?? 0) >= 2) avoid.add(m);
      pos.unmake();
    }
    // 0 简单: often a random legal move, otherwise a 1-ply look;
    // 1 普通: 300 ms / depth 3; 2 困难: 1 s / depth 5.
    final lvl = botLevel;
    var m = -1;
    if (lvl <= 0 && rng.nextDouble() < 0.5) {
      m = legalMoves[rng.nextInt(legalMoves.length)];
    } else {
      final search = lvl <= 0
          ? ShogiSearch(pos, limitMs: 100, maxDepth: 1, rng: rng)
          : lvl >= 2
              ? ShogiSearch(pos, limitMs: 1000, maxDepth: 5, rng: rng)
              : ShogiSearch(pos, limitMs: 300, maxDepth: 3, rng: rng);
      m = search.bestMove(legalMoves, avoid: avoid);
    }
    if (m < 0 || !legalMoves.contains(m)) m = legalMoves[rng.nextInt(legalMoves.length)];
    if (sgIsDrop(m)) return {'type': 'drop', 'piece': sgDropType(m), 'to': sgTo(m)};
    return {'type': 'move', 'from': sgFrom(m), 'to': sgTo(m), 'promote': sgIsPromo(m)};
  }

  @override
  int get botDelayMs => 400;
}
