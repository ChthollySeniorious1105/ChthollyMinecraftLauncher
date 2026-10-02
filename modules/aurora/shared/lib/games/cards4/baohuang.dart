import '../../src/engine.dart';
import 'cards.dart';
import 'sets.dart';
import 'trick.dart';

/// 保皇：5 人，四副牌（带王）+ 1 张皇帝牌共 217 张。持皇帝牌者为皇帝（公开），
/// 持侍卫牌（一张特殊大王）者为保子（隐藏），1+1 对 3。见 [baohuangRules]。
class Baohuang extends C4Trick {
  Baohuang(super.setup);

  late int rounds;
  late bool duOpt, baoOpt, bombsOn;
  int round = 0;
  late List<int> scores;
  String phase = 'play'; // declare | reveal | play | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;
  int emperor = -1;
  int guard = -1; // -1 when 独保
  bool guardKnown = false;
  bool du = false; // 独保
  bool bao = false; // 暴保（保子亮明身份）
  late List<bool> answered;
  int starter = 0;
  final List<String> log = [];

  void _log(String s) {
    log.add(s);
    if (log.length > 12) log.removeAt(0);
    host.log(s);
  }

  bool royal(int s) => s == emperor || s == guard;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'play':
        return [turn];
      case 'declare':
        return [emperor];
      case 'reveal':
      case 'roundEnd':
        return [for (var s = 0; s < players; s++) if (!(phase == 'reveal' ? answered[s] : ready[s])) s];
    }
    return const [];
  }

  @override
  List<int>? get placings => isOver ? rankByScore(scores) : null;

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 5);
    duOpt = setup.opt<bool>('du', true);
    baoOpt = setup.opt<bool>('bao', true);
    bombsOn = setup.opt<bool>('bombs', true);
    scores = List.filled(players, 0);
    starter = rng.nextInt(players);
    _log('保皇开始：5 人，四副牌 + 皇帝牌，共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final base = [for (var i = 0; i < 4; i++) ...c4Deck()];
    base.remove('RJ');
    base.add('GJ');
    base.add('EJ');
    final deck = shuffled(base, rng);
    hands = List.generate(players, (_) => <String>[]);
    for (var i = 0; i < 43 * players; i++) {
      hands[(starter + i) % players].add(deck[i]);
    }
    final rest = deck.sublist(43 * players);
    emperor = [for (var s = 0; s < players; s++) if (hands[s].contains('EJ')) s].firstOrNull ?? starter;
    hands[emperor].addAll(rest); // 皇帝拿底牌
    for (final h in hands) {
      c4Sort(h);
    }
    guard = [for (var s = 0; s < players; s++) if (hands[s].contains('GJ')) s].first;
    du = false;
    bao = false;
    guardKnown = false;
    finish = [];
    plays = 0;
    resetTrick();
    result = null;
    ready = List.filled(players, false);
    answered = List.filled(players, false);
    turn = emperor;
    _log('第 $round 局：${name(emperor)} 是皇帝，拿 ${rest.length} 张底牌');
    if (guard == emperor) {
      guard = -1;
      du = true;
      guardKnown = true;
      _log('皇帝自己拿到侍卫牌，只能独保！');
      _startPlay();
    } else if (duOpt) {
      phase = 'declare';
    } else {
      _startReveal();
    }
  }

  void _startReveal() {
    if (!baoOpt || du) {
      _startPlay();
      return;
    }
    phase = 'reveal';
    answered = List.filled(players, false);
    answered[emperor] = true;
  }

  void _startPlay() {
    phase = 'play';
    turn = emperor;
    _log('皇帝 ${name(emperor)} 先出${du ? '（独保，分数翻倍）' : ''}');
  }

  // ---------------- rules ----------------

  /// Bomb: 4+ natural cards of one rank (no wild), when enabled.
  bool _isBomb(SetCombo c) => bombsOn && c.jokers == 0 && c.size >= 4 && c.rank <= 15;

  @override
  Map<String, dynamic> checkPlay(int seat, List<String> cards) {
    final c = classifySet(cards);
    if (c == null) throw GameError('保皇只能出同点数的牌（王可以当任意点数）');
    final info = c.toJson();
    final bomb = _isBomb(c);
    info['bomb'] = bomb;
    if (bomb) info['label'] = '${c.size}张${c4ValName(c.rank)}炸弹';
    if (leading) return info;
    final t = SetCombo.fromJson(tableInfo)!;
    final tb = tableInfo!['bomb'] == true;
    if (bomb && !tb && c.size > t.size) return info; // 炸弹管张数更少的普通牌
    if (bomb && tb) {
      if (c.size > t.size || (c.size == t.size && c.rank > t.rank)) return info;
      throw GameError('炸弹要比桌上的更大');
    }
    if (c.size != t.size) throw GameError('张数必须相同（${t.size} 张）');
    if (tb && !bomb) throw GameError('只能用更大的炸弹管炸弹');
    if (c.rank <= t.rank) throw GameError('点数要比桌上的大');
    return info;
  }

  @override
  void onPlay(int seat, List<String> cards, Map<String, dynamic> info) {
    if (cards.contains('GJ') && !guardKnown && !du) {
      guardKnown = true;
      _log('${name(seat)} 打出侍卫牌，亮明保子身份！');
    }
    if (info['bomb'] == true) _log('${name(seat)} 打出${info['label']}！');
  }

  @override
  bool get roundDone {
    if (activeCount <= 1) return true;
    final royals = [emperor, if (guard >= 0) guard];
    if (royals.every((s) => !active(s))) return true;
    return [for (var s = 0; s < players; s++) if (!royals.contains(s)) s].every((s) => !active(s));
  }

  @override
  void endRound() {
    final rest = [for (var s = 0; s < players; s++) if (active(s)) s]
      ..sort((a, b) => hands[a].length != hands[b].length ? hands[a].length - hands[b].length : a - b);
    final order = [...finish, ...rest];
    final royalWin = royal(order.first);
    var mult = 1;
    final notes = <String>[];
    if (du) {
      mult *= 2;
      notes.add('独保×2');
    }
    if (bao) {
      mult *= 2;
      notes.add('暴保×2');
    }
    if (royalWin && (du || royal(order[1]))) {
      mult *= 2;
      notes.add(du ? '皇帝头科' : '皇帝方包揽前二×2');
    } else if (!royalWin && order.last == emperor) {
      mult *= 2;
      notes.add('皇帝大落×2');
    }
    final delta = List.filled(players, 0);
    final sign = royalWin ? 1 : -1;
    for (var s = 0; s < players; s++) {
      if (s == emperor) {
        delta[s] = sign * (du ? 4 : 2) * mult;
      } else if (s == guard) {
        delta[s] = sign * mult;
      } else {
        delta[s] = -sign * mult;
      }
    }
    for (var s = 0; s < players; s++) {
      scores[s] += delta[s];
    }
    guardKnown = true;
    result = {
      'order': order,
      'delta': delta,
      'royalWin': royalWin,
      'notes': notes,
      'hands': [for (final h in hands) List.of(h)],
    };
    _log('第 $round 局结束：${royalWin ? '皇帝方' : '平民方'}获胜 ${notes.join(' ')}');
    starter = (starter + 1) % players;
    phase = round >= rounds ? 'over' : 'roundEnd';
    ready = List.filled(players, false);
  }

  // ---------------- actions ----------------

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (seat < 0 || seat >= players) throw GameError('你不在座位上');
    final type = asStr(a['type']);
    switch (phase) {
      case 'roundEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) _deal();
        return;
      case 'declare':
        if (seat != emperor) throw GameError('等待皇帝决定是否独保');
        if (type != 'du') throw GameError('请选择是否独保');
        du = asBool(a['yes']);
        if (du) {
          _log('皇帝 ${name(emperor)} 选择独保！1 打 4');
          guard = -1;
          guardKnown = true;
        }
        _startReveal();
        return;
      case 'reveal':
        if (type != 'bao') throw GameError('请选择');
        if (answered[seat]) throw GameError('你已经选择过了');
        final yes = asBool(a['yes']);
        if (yes && seat != guard) throw GameError('只有保子可以暴保');
        answered[seat] = true;
        if (yes) {
          bao = true;
          guardKnown = true;
          _log('${name(seat)} 暴保！亮明保子身份，分数翻倍');
        }
        if (answered.every((x) => x)) _startPlay();
        return;
      case 'play':
        handlePlay(seat, a);
        return;
    }
    throw GameError('游戏已结束');
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      ...trickView(seat),
      'phase': phase,
      'turn': phase == 'play' ? turn : (phase == 'declare' ? emperor : -1),
      'round': round,
      'rounds': rounds,
      'scores': scores,
      'emperor': emperor,
      'guard': guardKnown || (me && seat == guard) ? guard : -2, // -2 = 未知
      'du': du,
      'bao': bao,
      'bombs': bombsOn,
      'amGuard': me && seat == guard,
      'answered': phase == 'reveal' ? answered : null,
      'log': log,
      'result': phase == 'roundEnd' || phase == 'over' ? result : null,
      'ready': phase == 'roundEnd' ? ready : null,
    };
  }

  // ---------------- bot ----------------

  bool _legal(int seat, List<String> cards) {
    try {
      checkPlay(seat, cards);
      return true;
    } on GameError {
      return false;
    }
  }

  /// Whom [seat] knows to be a partner.
  bool _friend(int seat, int other) {
    if (seat == other) return true;
    if (seat == emperor) return guardKnown && other == guard;
    if (seat == guard) return other == emperor;
    return other != emperor && guardKnown && other != guard;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'roundEnd':
        return ready[seat] ? null : {'type': 'continue'};
      case 'declare':
        if (seat != emperor) return null;
        final h = hands[seat];
        final strong = h.where((c) => c4Val(c) >= 15).length;
        return {'type': 'du', 'yes': botLevel >= 1 && strong >= 16};
      case 'reveal':
        if (answered[seat]) return null;
        final strong = hands[seat].where((c) => c4Val(c) >= 15).length;
        return {'type': 'bao', 'yes': seat == guard && botLevel >= 1 && strong >= 14};
      case 'play':
        break;
      default:
        return null;
    }
    if (seat != turn) return null;
    final hand = hands[seat];
    if (leading) {
      final g = c4Groups(hand.where((c) => !setWild(c) && c != 'EJ'));
      final keys = g.keys.toList()..sort();
      final cands = <List<String>>[for (final k in keys) g[k]!];
      if (cands.isEmpty) {
        final w = hand.where((c) => setWild(c)).toList();
        cands.add(w.isNotEmpty ? w : ['EJ']);
      }
      if (botLevel == 0) return {'type': 'play', 'cards': cands[rng.nextInt(cands.length)]};
      final whole = setCandidates(hand, size: hand.length);
      if (whole.isNotEmpty && _legal(seat, whole.first)) return {'type': 'play', 'cards': whole.first};
      // lead the smallest group; keep bombs for later unless few groups left
      final nb = cands.where((c) => !(bombsOn && c.length >= 4)).toList();
      return {'type': 'play', 'cards': (nb.isNotEmpty ? nb : cands).first};
    }
    if (_friend(seat, tableSeat)) return {'type': 'pass'};
    final t = SetCombo.fromJson(tableInfo)!;
    var cands = setCandidates(hand, size: t.size, above: t.rank).where((c) => _legal(seat, c)).toList();
    if (bombsOn) {
      final bombs = setCandidates(hand, above: 0)
          .where((c) => c.length >= 4 && c.length > (tableInfo!['bomb'] == true ? 0 : t.size) && _legal(seat, c))
          .toList()
        ..sort((a, b) => a.length - b.length);
      cands = [...cands, ...bombs];
    }
    if (cands.isEmpty) return {'type': 'pass'};
    if (botLevel == 0) return rng.nextBool() ? {'type': 'play', 'cards': cands[rng.nextInt(cands.length)]} : {'type': 'pass'};
    final whole = cands.where((c) => c.length == hand.length);
    if (whole.isNotEmpty) return {'type': 'play', 'cards': whole.first};
    final danger = hands[tableSeat].length <= (botLevel >= 2 ? 8 : 4);
    for (final c in cands) {
      final j = c.where((x) => setWild(x) || x == 'EJ').length;
      final isBomb = c.length >= 4 && c.every((x) => !setWild(x)) && c.length > t.size;
      if (isBomb && !danger) continue;
      if (j == 0) return {'type': 'play', 'cards': c};
      if (danger || hand.length <= 10) return {'type': 'play', 'cards': c};
    }
    return {'type': 'pass'};
  }
}

const String baohuangRules = '''
# 保皇
五人游戏。四副扑克（带王）共 216 张，其中一张大王换成“侍卫牌”，另加一张“皇帝牌”，共 217 张。每人 43 张，剩下 2 张底牌归皇帝。
# 身份
- 拿到皇帝牌的人是皇帝（公开）；拿到侍卫牌的人是保子（侍卫），身份隐藏，与皇帝一伙。其余三人是平民。
- 独保（可选）：发牌后皇帝可以宣布独保，1 打 4，分数翻倍。皇帝自己拿到侍卫牌时必须独保。
- 暴保（可选）：没有独保时，保子可以在开局前亮明身份“暴保”，分数翻倍。为了不暴露身份，所有平民也会被询问（只能选“不暴”）。
- 保子打出侍卫牌时身份自动公开。
# 出牌
- 只出同点数的牌：单张、对子、三张……任意张数。大小：皇帝牌 > 大王（侍卫牌同大王）> 小王 > 2 > A > … > 3。
- 大小王（含侍卫牌）可以当作任意点数配牌；皇帝牌只能单出，是最大的单张。
- 跟牌须张数相同且点数更大。其他人都不要时最后出牌者收轮再出；出完的人由下家接风。皇帝首出。
- 炸弹（可选）：4 张及以上同点数的真牌（不含王）是炸弹，可以管张数比它少的普通牌；炸弹之间张数多者大，张数相同比点数。
# 胜负与计分
- 一方全部出完（或只剩一人）时本局结束，按出完顺序排名，未出完者按剩余张数排名。
- 头科所在一方获胜。基础分：皇帝 ±2、保子 ±1、每个平民 ∓1（独保时皇帝 ±4）。
- 倍数：独保 ×2；暴保 ×2；皇帝方包揽头科二科（独保时皇帝头科）×2；平民获胜且皇帝大落 ×2。
- 打满设定局数后总分最高者获胜。
# 本实现的简化
- 没有“叫牌换保子”、革命、贡牌等地方规则；皇帝每局按发牌随机产生。
''';
