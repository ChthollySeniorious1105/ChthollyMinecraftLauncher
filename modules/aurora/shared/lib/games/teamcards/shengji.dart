import '../../src/engine.dart';
import 'shengji_rules.dart';

/// 升级（拖拉机）：四人两副牌，对家为队友，庄家方守分、闲家方抓分。
class Shengji extends GameEngine {
  Shengji(super.setup);

  late final int target = setup.opt<int>('target', 14);
  late final int cap = setup.opt<int>('cap', 0);

  List<int> levels = [2, 2];
  int banker = -1; // -1 = decided by declaration (first deal)
  int dealer = 0;
  int deal = 0;
  String phase = 'declare'; // declare / bury / play / dealEnd / over
  final List<List<String>> hands = [];
  List<String> bottom = [];
  List<String> bottomDealt = [];
  String trumpSuit = '';
  int turn = 0;

  // declaration
  int declStrength = 0;
  int declarer = -1;
  List<String> declCards = [];
  int declPasses = 0;
  List<String?> declActs = [];

  // play
  int leader = 0;
  List<String> leadCards = [];
  List<Map<String, dynamic>?> acts = [];
  int trickCount = 0;
  int points = 0; // defenders' points
  List<Map<String, dynamic>> lastTrick = [];
  int lastWinner = -1;
  Map<String, dynamic>? result;
  Map<String, dynamic>? throwFail;
  List<bool> ready = [];
  int winnerTeam = -1;
  List<String> seen = []; // cards played in finished tricks this deal (public)
  List<Set<String>> voids = List.generate(4, (_) => <String>{}); // classes a seat showed out of

  int team(int s) => s % 2;
  int get bankerTeam => banker < 0 ? -1 : team(banker);
  int get level => banker < 0 ? levels[0] : levels[bankerTeam];
  SjTrump get trump => SjTrump(level, trumpSuit);

  @override
  void start() {
    dealer = rng.nextInt(4);
    _deal();
  }

  void _deal() {
    final deck = shuffled(sjDeck(), rng);
    hands
      ..clear()
      ..addAll([for (var s = 0; s < 4; s++) deck.sublist(s * 25, (s + 1) * 25)]);
    bottom = deck.sublist(100);
    trumpSuit = '';
    declStrength = 0;
    declarer = -1;
    declCards = [];
    declPasses = 0;
    declActs = List.filled(4, null);
    acts = List.filled(4, null);
    leadCards = [];
    trickCount = 0;
    points = 0;
    lastTrick = [];
    lastWinner = -1;
    seen = [];
    voids = List.generate(4, (_) => <String>{});
    result = null;
    throwFail = null;
    _sortHands();
    phase = 'declare';
    turn = banker >= 0 ? banker : dealer;
    host.log('第 ${deal + 1} 局开始，打 ${sjRankName(level)}${banker >= 0 ? "，庄家 ${name(banker)}" : "，先亮主者坐庄"}');
  }

  void _sortHands() {
    for (var s = 0; s < hands.length; s++) {
      hands[s] = trump.sort(hands[s]);
    }
  }

  @override
  bool get isOver => phase == 'over';

  /// 胜队两人第 1，败队两人第 2；平局全部第 1。
  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (winnerTeam != 0 && winnerTeam != 1) return List.filled(4, 1);
    return [for (var s = 0; s < 4; s++) team(s) == winnerTeam ? 1 : 2];
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'declare':
      case 'play':
        return [turn];
      case 'bury':
        return [banker];
      case 'dealEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  /// Possible declarations for [seat]: list of (strength, suit, cards).
  List<(int, String, List<String>)> declOptions(int seat) {
    final h = hands[seat];
    final out = <(int, String, List<String>)>[];
    final lc = sjRankChar(level);
    for (final s in sjSuits) {
      final code = '$lc$s';
      final n = h.where((c) => c == code).length;
      if (n >= 1 && declStrength < 1) out.add((1, s, [code]));
      if (n >= 2 && declStrength < 2) out.add((2, s, [code, code]));
    }
    if (h.where((c) => c == 'BJ').length >= 2 && declStrength < 3) out.add((3, 'N', ['BJ', 'BJ']));
    if (h.where((c) => c == 'RJ').length >= 2 && declStrength < 4) out.add((4, 'N', ['RJ', 'RJ']));
    return out;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'over':
        throw GameError('对局已结束');
      case 'dealEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) {
          deal++;
          dealer = (dealer + 1) % 4;
          _deal();
        }
        return;
      case 'declare':
        if (seat != turn) throw GameError('还没轮到你');
        if (type == 'pass') {
          declActs[seat] = 'pass';
          declPasses++;
          if (declPasses >= 4) {
            _finishDeclare();
          } else {
            turn = (turn + 1) % 4;
          }
          return;
        }
        if (type != 'declare') throw GameError('现在是亮主阶段');
        final suit = asStr(a['suit']);
        final str = asInt(a['strength'], 0);
        final opt = declOptions(seat).where((o) => o.$1 == str && o.$2 == suit).toList();
        if (opt.isEmpty) throw GameError('无法这样亮主（需要比当前更大）');
        declStrength = str;
        declarer = seat;
        trumpSuit = suit;
        declCards = opt.first.$3;
        declActs[seat] = str >= 3 ? '无主' : (str == 2 ? '反${sjSuitNames[suit]}' : '亮${sjSuitNames[suit]}');
        host.log('${name(seat)} ${declActs[seat]}');
        declPasses = 0;
        _sortHands();
        if (declStrength >= 4) {
          _finishDeclare();
        } else {
          turn = (turn + 1) % 4;
        }
        return;
      case 'bury':
        if (seat != banker) throw GameError('等待庄家扣底');
        if (type != 'bury') throw GameError('请选择 8 张底牌');
        final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
        if (cards.length != 8) throw GameError('需要扣 8 张底牌');
        final rest = List.of(hands[seat]);
        for (final c in cards) {
          if (!rest.remove(c)) throw GameError('你没有这张牌');
        }
        hands[seat] = rest;
        bottom = cards;
        phase = 'play';
        turn = banker;
        leader = banker;
        host.log('${name(banker)} 扣底完成，开始出牌');
        return;
    }
    // play
    if (seat != turn) throw GameError('还没轮到你');
    if (type != 'play') throw GameError('请出牌');
    final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
    if (cards.isEmpty) throw GameError('请选择要出的牌');
    final rest = List.of(hands[seat]);
    for (final c in cards) {
      if (!rest.remove(c)) throw GameError('你没有这张牌');
    }
    final t = trump;
    if (seat == leader) {
      final cls = sjLeadClass(cards, t);
      if (cls == null) throw GameError('首家出牌必须是同一花色（或都是主牌）');
      var play = cards;
      final comps = sjDecompose(cards, t);
      throwFail = null;
      if (comps.length > 1) {
        // 甩牌：every component must be unbeatable by every other player
        SjComp? fail;
        for (final comp in comps.reversed) {
          final beatable = [for (var s = 0; s < 4; s++) if (s != seat) s].any((s) => sjCompBeatable(comp, cls, hands[s], t));
          if (beatable && (fail == null || comp.size < fail.size || (comp.size == fail.size && comp.top < fail.top))) {
            fail = comp;
          }
        }
        if (fail != null) {
          final penalty = 10 * comps.length;
          play = fail.cards;
          if (team(seat) == bankerTeam) {
            points += penalty;
          } else {
            points = (points - penalty).clamp(0, 1000);
          }
          throwFail = {'seat': seat, 'tried': t.sort(cards), 'penalty': penalty};
          host.log('${name(seat)} 甩牌失败，罚 $penalty 分，只能出 ${fail.label}');
        }
      }
      final r2 = List.of(hands[seat]);
      for (final c in play) {
        r2.remove(c);
      }
      hands[seat] = r2;
      acts = List.filled(4, null);
      leadCards = t.sort(play);
      acts[seat] = {'cards': leadCards, 'label': _leadLabel(leadCards)};
    } else {
      final err = sjFollowError(leadCards, cards, hands[seat], t);
      if (err != null) throw GameError(err);
      hands[seat] = rest;
      acts[seat] = {'cards': t.sort(cards)};
    }
    turn = (turn + 1) % 4;
    if (turn == leader) _finishTrick();
  }

  String _leadLabel(List<String> cards) {
    final comps = sjDecompose(cards, trump);
    if (comps.length > 1) return '甩牌';
    return comps.first.label;
  }

  void _finishDeclare() {
    if (declarer < 0) {
      // nobody declared: flip the bottom
      String? pick;
      for (final c in bottom) {
        if (sjNat(c) == level) {
          pick = c;
          break;
        }
      }
      if (pick == null) {
        var best = -1;
        for (final c in bottom) {
          final n = sjNat(c);
          if (n > best) {
            best = n;
            pick = c;
          }
        }
      }
      trumpSuit = sjNat(pick!) >= 16 ? 'N' : sjSuit(pick);
      host.log('无人亮主，翻底牌定主：${sjSuitNames[trumpSuit]}');
      if (banker < 0) banker = dealer;
    } else if (banker < 0) {
      banker = declarer;
    }
    host.log('主牌：${sjSuitNames[trumpSuit]}，${name(banker)} 坐庄，打 ${sjRankName(level)}');
    hands[banker] = [...hands[banker], ...bottom];
    bottomDealt = List.of(bottom);
    bottom = [];
    _sortHands();
    phase = 'bury';
    turn = banker;
  }

  void _finishTrick() {
    final t = trump;
    final cls = t.cls(leadCards.first);
    final comps = sjDecompose(leadCards, t);
    var win = leader;
    var best = sjPower(leadCards, comps, cls, t, isLead: true);
    final trick = <Map<String, dynamic>>[];
    var pts = 0;
    for (var i = 0; i < 4; i++) {
      final s = (leader + i) % 4;
      final cards = [for (final c in (acts[s]!['cards'] as List)) '$c'];
      pts += sjPointsOf(cards);
      seen.addAll(cards);
      if (i > 0 && cards.any((c) => t.cls(c) != cls)) voids[s].add(cls);
      trick.add({'seat': s, 'cards': cards});
      if (i == 0) continue;
      final p = sjPower(cards, comps, cls, t);
      if (p > best) {
        best = p;
        win = s;
      }
    }
    trickCount++;
    lastTrick = trick;
    lastWinner = win;
    if (team(win) != bankerTeam && pts > 0) {
      points += pts;
    }
    for (var s = 0; s < 4; s++) {
      acts[s] = {...acts[s]!, 'win': s == win};
    }
    if (hands[0].isEmpty) {
      _endDeal(win, comps);
      return;
    }
    leader = win;
    turn = win;
  }

  void _endDeal(int lastWin, List<SjComp> lastComps) {
    var bottomPts = sjPointsOf(bottom);
    var mult = 0;
    if (team(lastWin) != bankerTeam && bottomPts > 0) {
      final maxSize = lastComps.map((c) => c.size).reduce((a, b) => a > b ? a : b);
      mult = maxSize == 1 ? 2 : (1 << (maxSize ~/ 2 + 1));
      points += bottomPts * mult;
      host.log('${name(lastWin)} 抠底！底分 $bottomPts ×$mult');
    }
    final p = points;
    final bt = bankerTeam;
    final dt = 1 - bt;
    int up;
    int upTeam;
    if (p == 0) {
      up = 3;
      upTeam = bt;
    } else if (p < 40) {
      up = 2;
      upTeam = bt;
    } else if (p < 80) {
      up = 1;
      upTeam = bt;
    } else {
      up = (p - 80) ~/ 40;
      upTeam = dt;
    }
    final before = List.of(levels);
    var matchWin = false;
    if (upTeam == bt && levels[bt] >= target) {
      matchWin = true;
    }
    levels[upTeam] = (levels[upTeam] + up).clamp(2, target);
    final nextBanker = upTeam == bt ? (banker + 2) % 4 : (banker + 1) % 4;
    result = {
      'points': p,
      'bottom': bottom,
      'bottomPts': bottomPts,
      'mult': mult,
      'upTeam': upTeam,
      'up': up,
      'before': before,
      'levels': List.of(levels),
      'bankerTeam': bt,
      'hold': upTeam == bt,
    };
    host.log('本局闲家得 $p 分，${upTeam == bt ? "庄家方守住" : "闲家方上台"}${up > 0 ? "，升 $up 级" : ""}');
    banker = nextBanker;
    if (!matchWin && cap > 0 && deal + 1 >= cap) {
      matchWin = true;
      winnerTeam = levels[0] == levels[1] ? 2 : (levels[0] > levels[1] ? 0 : 1);
      host.log('已达局数上限');
    } else if (matchWin) {
      winnerTeam = bt;
    }
    if (matchWin) {
      phase = 'over';
      host.log(winnerTeam == 2 ? '比赛结束：平局' : '比赛结束：${winnerTeam == 0 ? "南北" : "东西"}队获胜！');
    } else {
      phase = 'dealEnd';
      ready = List.filled(4, false);
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < 4;
    return {
      'game': 'shengji',
      'phase': phase,
      'deal': deal,
      'cap': cap,
      'target': target,
      'levels': levels,
      'level': level,
      'banker': banker,
      'bankerTeam': bankerTeam,
      'trump': trumpSuit,
      'turn': turn,
      'leader': leader,
      'hand': me ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'bottom': (me && seat == banker && phase == 'bury') || phase == 'dealEnd' || phase == 'over' ? bottom : null,
      'bottomDealt': me && seat == banker && phase == 'bury' ? bottomDealt : const [],
      'declarer': declarer,
      'declStrength': declStrength,
      'declCards': declCards,
      'declActs': declActs,
      'declOptions': me && phase == 'declare' && seat == turn
          ? [for (final o in declOptions(seat)) {'strength': o.$1, 'suit': o.$2}]
          : const [],
      'acts': acts,
      'leadCards': leadCards,
      'lastTrick': lastTrick,
      'lastWinner': lastWinner,
      'trickCount': trickCount,
      'points': points,
      'throwFail': throwFail,
      'result': result,
      'ready': phase == 'dealEnd' ? ready : null,
      'winner': winnerTeam,
      'over': isOver,
    };
  }

  // ---------------- bot ----------------

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'over':
        return null;
      case 'dealEnd':
        return {'type': 'continue'};
      case 'declare':
        if (seat != turn) return null;
        return _botDeclare(seat);
      case 'bury':
        if (seat != banker) return null;
        return {'type': 'bury', 'cards': _botBury(seat)};
    }
    if (seat != turn) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.45) {
      // 简单：首家随便出一张单牌；跟牌时随便凑一手合法的牌
      final h = hands[seat];
      if (seat == leader) return {'type': 'play', 'cards': [h[rng.nextInt(h.length)]]};
      final t = trump;
      final cls = t.cls(leadCards.first);
      final comps = sjDecompose(leadCards, t);
      final c = sjBuildFollow(t, h, cls, comps, rng.nextBool(), rng.nextBool());
      if (sjFollowError(leadCards, c, h, t) == null) return {'type': 'play', 'cards': c};
    }
    if (botLevel == 2 && seat == leader) {
      final boss = _hardLead(seat);
      if (boss != null) return {'type': 'play', 'cards': boss};
    }
    return {'type': 'play', 'cards': seat == leader ? _botLead(seat) : _botFollow(seat)};
  }

  /// 困难：记牌。优先首出“已经最大”的副牌单张/对子（按公开出过的牌和自己手牌判断），
  /// 并避开对手已经断门（可以毙牌）的花色。
  List<String>? _hardLead(int seat) {
    final t = trump;
    final h = hands[seat];
    final outstanding = <String, int>{};
    for (final c in sjDeck()) {
      outstanding[c] = (outstanding[c] ?? 0) + 1;
    }
    for (final c in [...seen, ...h, if (seat == banker) ...bottom]) {
      outstanding[c] = (outstanding[c] ?? 1) - 1;
    }
    final bySuit = <String, List<String>>{};
    for (final c in h) {
      if (!t.isTrump(c)) (bySuit[t.cls(c)] ??= []).add(c);
    }
    List<String>? best;
    var bestScore = -1.0;
    for (final e in bySuit.entries) {
      final cls = e.key;
      final oppVoid = [for (var s = 0; s < 4; s++) if (team(s) != team(seat) && voids[s].contains(cls)) s].isNotEmpty;
      if (oppVoid) continue;
      for (final comp in sjDecompose(e.value, t)) {
        if (comp.size > 2) continue;
        var boss = true;
        for (final o in outstanding.entries) {
          if (o.value <= 0 || t.cls(o.key) != cls) continue;
          if (t.order(o.key) > comp.top && o.value >= comp.size) {
            boss = false;
            break;
          }
        }
        if (!boss) continue;
        final score = comp.size * 10.0 + sjPointsOf(comp.cards) + (team(seat) == bankerTeam ? 0 : 3);
        if (score > bestScore) {
          bestScore = score;
          best = comp.cards;
        }
      }
    }
    return best;
  }

  Map<String, dynamic> _botDeclare(int seat) {
    final h = hands[seat];
    final opts = declOptions(seat);
    if (declarer >= 0 && team(declarer) == team(seat)) return {'type': 'pass'};
    (int, String, List<String>)? best;
    var bestScore = 0.0;
    for (final o in opts) {
      final t = SjTrump(level, o.$2);
      final trumps = h.where(t.isTrump).length;
      final score = trumps + (o.$1 - 1) * 1.5;
      final need = declStrength == 0 ? 8.5 : 10.0;
      if (score >= need && score > bestScore) {
        bestScore = score;
        best = o;
      }
    }
    if (best == null) return {'type': 'pass'};
    return {'type': 'declare', 'strength': best.$1, 'suit': best.$2};
  }

  List<String> _botBury(int seat) {
    final t = trump;
    final h = hands[seat];
    final side = h.where((c) => !t.isTrump(c)).toList();
    final suitLen = <String, int>{};
    for (final c in side) {
      suitLen[sjSuit(c)] = (suitLen[sjSuit(c)] ?? 0) + 1;
    }
    final pairs = <String>{};
    final seen = <String>{};
    for (final c in h) {
      if (!seen.add(c)) pairs.add(c);
    }
    double cost(String c) {
      if (t.isTrump(c)) return 1000.0 + t.order(c);
      var v = t.order(c) * 3.0 + (suitLen[sjSuit(c)] ?? 0) * 1.5 + sjPoints(c) * 2.5;
      if (pairs.contains(c)) v += 20;
      if (sjNat(c) == 14) v += 30;
      return v;
    }

    final sorted = List.of(h)..sort((a, b) => cost(a).compareTo(cost(b)));
    return sorted.take(8).toList();
  }

  /// Top order among the ranks of a suit that is not the level (A=11, or 10 if level is A).
  int _topOrder() => level == 14 ? 10 : 11;

  List<String> _botLead(int seat) {
    final t = trump;
    final h = hands[seat];
    final bySuit = <String, List<String>>{};
    for (final c in h) {
      (bySuit[t.cls(c)] ??= []).add(c);
    }
    List<String>? best;
    var bestScore = -1e9;
    for (final e in bySuit.entries) {
      final comps = sjDecompose(e.value, t);
      for (final comp in comps) {
        var score = 0.0;
        final isT = e.key == 'T';
        if (comp.size >= 2) {
          score += 20 + comp.size * 4 + comp.top;
        } else if (!isT && comp.top >= _topOrder()) {
          score += 18;
        } else {
          score += 6 - comp.top * 0.5 - sjPoints(comp.cards.first) * 0.8;
        }
        if (isT) {
          final mine = e.value.length;
          score += team(seat) == bankerTeam && mine >= 8 ? 4 : -8;
          if (comp.size == 1 && comp.top >= 12) score -= 10;
        } else {
          score += (e.value.length <= 2 ? 3 : 0);
        }
        if (score > bestScore) {
          bestScore = score;
          best = comp.cards;
        }
      }
    }
    return best ?? [h.last];
  }

  List<String> _botFollow(int seat) {
    final t = trump;
    final h = hands[seat];
    final cls = t.cls(leadCards.first);
    final comps = sjDecompose(leadCards, t);
    // current winner
    var win = leader;
    var best = sjPower(leadCards, comps, cls, t, isLead: true);
    var trickPts = sjPointsOf(leadCards);
    for (var i = 1; i < 4; i++) {
      final s = (leader + i) % 4;
      if (s == seat) break;
      final cards = [for (final c in (acts[s]!['cards'] as List)) '$c'];
      trickPts += sjPointsOf(cards);
      final p = sjPower(cards, comps, cls, t);
      if (p > best) {
        best = p;
        win = s;
      }
    }
    final last = (seat + 1) % 4 == leader;
    final partnerWins = team(win) == team(seat);
    final candidates = <List<String>>[];
    final hasSuit = h.any((c) => t.cls(c) == cls);
    if (partnerWins) {
      candidates.add(sjBuildFollow(trump, h, cls, comps, false, true));
    } else {
      final hi = sjBuildFollow(trump, h, cls, comps, true, false);
      if (sjPower(hi, comps, cls, t) > best) candidates.add(hi);
      if (!hasSuit && cls != 'T') {
        // ruff with trumps
        final trumps = h.where(t.isTrump).toList();
        if (trumps.length >= leadCards.length && (trickPts > 0 || last || comps.length > 1)) {
          final ruff = sjBuildFollow(trump, trumps, 'T', comps, false, false);
          if (sjPower(ruff, comps, cls, t) > best) candidates.add(ruff);
          final ruffHi = sjBuildFollow(trump, trumps, 'T', comps, true, false);
          if (sjPower(ruffHi, comps, cls, t) > best) candidates.add(ruffHi);
        }
      }
      candidates.add(sjBuildFollow(trump, h, cls, comps, false, false));
    }
    for (final c in candidates) {
      if (sjFollowError(leadCards, c, h, t) == null) return c;
    }
    // fallback: brute force legal selection
    return _anyLegal(h, cls, comps);
  }

  List<String> _anyLegal(List<String> h, String cls, List<SjComp> comps) {
    final t = trump;
    for (final high in [false, true]) {
      for (final gp in [false, true]) {
        final c = sjBuildFollow(trump, h, cls, comps, high, gp);
        if (sjFollowError(leadCards, c, h, t) == null) return c;
      }
    }
    // last resort: all suit cards then anything
    final n = leadCards.length;
    final mine = h.where((c) => t.cls(c) == cls).toList();
    if (mine.length <= n) return [...mine, ...h.where((c) => t.cls(c) != cls).take(n - mine.length)];
    return mine.take(n).toList();
  }
}
