import '../../src/engine.dart';
import 'guandan_rules.dart';

/// 掼蛋：四人两副牌，对家为队友（0&2 对 1&3），按出完顺序升级，打过 A（或目标级）获胜。
class Guandan extends GameEngine {
  Guandan(super.setup);

  late final int target = setup.opt<int>('target', 14);
  late final int cap = setup.opt<int>('cap', 0);

  List<int> levels = [2, 2];
  List<int> aFails = [0, 0];
  int levelTeam = 0; // team whose level is being played
  int deal = 0;
  String phase = 'play'; // tribute / return / play / dealEnd / over
  final List<List<String>> hands = [];
  int turn = 0;
  GdCombo? table;
  List<String> tableCards = [];
  int tableSeat = -1;
  int passes = 0;
  List<Map<String, dynamic>?> acts = [];
  List<int> finish = [];
  List<int> lastFinish = [];
  int winnerTeam = -1;
  Map<String, dynamic>? result;
  List<bool> ready = [];

  // tribute
  List<int> payers = [];
  List<int> receivers = [];
  Map<int, String> paid = {}; // payer -> card
  Map<int, int> pairTo = {}; // receiver -> payer
  Map<int, String> returned = {}; // receiver -> card
  Map<String, dynamic>? tributeInfo;
  int _leadAfterTribute = 0;

  int get level => levels[levelTeam];
  int team(int s) => s % 2;
  int partner(int s) => (s + 2) % 4;

  @override
  void start() {
    levelTeam = 0;
    _deal(first: true);
  }

  void _deal({bool first = false}) {
    final deck = shuffled(gdDeck(), rng);
    hands
      ..clear()
      ..addAll([for (var s = 0; s < 4; s++) gdSort(deck.sublist(s * 27, (s + 1) * 27), level)]);
    table = null;
    tableCards = [];
    tableSeat = -1;
    passes = 0;
    acts = List.filled(4, null);
    finish = [];
    result = null;
    tributeInfo = null;
    paid = {};
    returned = {};
    pairTo = {};
    payers = [];
    receivers = [];
    host.log('第 ${deal + 1} 局开始，打 ${gdRankName(level)}（${levelTeam == 0 ? "南北" : "东西"}队的级）');
    if (first || lastFinish.length < 4) {
      turn = rng.nextInt(4);
      phase = 'play';
      host.log('${name(turn)} 先出牌');
      return;
    }
    // 进贡
    final first1 = lastFinish[0], second = lastFinish[1];
    final last = lastFinish[3], third = lastFinish[2];
    final doubleDown = team(third) == team(last);
    payers = doubleDown ? [third, last] : [last];
    receivers = doubleDown ? [first1, second] : [first1];
    final redJokers = payers.fold<int>(0, (a, p) => a + hands[p].where((c) => c == 'RJ').length);
    if (redJokers >= 2) {
      host.log('${payers.map(name).join('、')} 持有两张大王，抗贡！${name(first1)} 先出牌');
      tributeInfo = {'resist': true, 'payers': payers, 'receivers': receivers};
      turn = first1;
      phase = 'play';
      payers = [];
      receivers = [];
      return;
    }
    phase = 'tribute';
    host.log('${payers.map(name).join('、')} 需要进贡');
  }

  @override
  bool get isOver => phase == 'over';

  /// 胜队两人第 1，败队两人第 2；平局（局数上限时级数相同）全部第 1。
  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (winnerTeam != 0 && winnerTeam != 1) return List.filled(4, 1);
    return [for (var s = 0; s < 4; s++) team(s) == winnerTeam ? 1 : 2];
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'play':
        return [turn];
      case 'tribute':
        return [for (final p in payers) if (!paid.containsKey(p)) p];
      case 'return':
        return [for (final r in receivers) if (!returned.containsKey(r)) r];
      case 'dealEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  int _maxTributeValue(int s) {
    var best = -1;
    for (final c in hands[s]) {
      if (gdIsWild(c, level)) continue;
      final v = gdValue(c, level);
      if (v > best) best = v;
    }
    return best;
  }

  List<String> _returnable(int s) {
    final h = hands[s];
    final small = h.where((c) => gdNat(c) <= 10).toList();
    return small.isEmpty ? h : small;
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
        if (ready.every((r) => r)) _deal();
        return;
      case 'tribute':
        if (!payers.contains(seat) || paid.containsKey(seat)) throw GameError('现在不需要你进贡');
        final c = asStr(a['card']);
        if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
        if (gdIsWild(c, level) || gdValue(c, level) != _maxTributeValue(seat)) {
          throw GameError('必须进贡最大的一张牌（红桃级牌除外）');
        }
        paid[seat] = c;
        if (paid.length == payers.length) _resolveTribute();
        return;
      case 'return':
        if (!receivers.contains(seat) || returned.containsKey(seat)) throw GameError('现在不需要你还贡');
        final c = asStr(a['card']);
        if (!hands[seat].contains(c)) throw GameError('你没有这张牌');
        if (!_returnable(seat).contains(c)) throw GameError('还贡的牌必须不大于 10');
        returned[seat] = c;
        if (returned.length == receivers.length) {
          for (final e in returned.entries) {
            final to = pairTo[e.key]!;
            hands[e.key].remove(e.value);
            hands[to] = gdSort([...hands[to], e.value], level);
          }
          tributeInfo = {...?tributeInfo, 'returns': {for (final e in returned.entries) '${e.key}': e.value}};
          host.log('还贡完成，${name(_leadAfterTribute)} 先出牌');
          phase = 'play';
          turn = _leadAfterTribute;
        }
        return;
    }
    // play
    if (seat != turn) throw GameError('还没轮到你');
    final lead = table == null;
    if (type == 'pass') {
      if (lead) throw GameError('你必须出牌');
      acts[seat] = {'pass': true};
      passes++;
      _advance();
      return;
    }
    if (type != 'play') throw GameError('无效操作');
    final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
    if (cards.isEmpty) throw GameError('请选择要出的牌');
    final rest = List.of(hands[seat]);
    for (final c in cards) {
      if (!rest.remove(c)) throw GameError('你没有这张牌');
    }
    final combo = gdPick(cards, table, level, as: asStr(a['as']));
    if (combo == null) {
      throw GameError(gdAnalyze(cards, level).isEmpty ? '不是有效的牌型' : '管不上上家的牌');
    }
    if (lead) acts = List.filled(4, null);
    hands[seat] = rest;
    table = combo;
    tableCards = gdSort(cards, level);
    tableSeat = seat;
    passes = 0;
    acts[seat] = {'cards': tableCards, 'label': combo.label, 'type': combo.type};
    if (combo.isBomb) host.log('${name(seat)} 打出${combo.label}！');
    if (rest.isEmpty) {
      finish.add(seat);
      host.log('${name(seat)} 出完了！第 ${finish.length} 名');
      final done = finish.where((s) => team(s) == team(seat)).length == 2;
      if (done) {
        for (var s = 0; s < 4; s++) {
          if (!finish.contains(s)) finish.add(s);
        }
        // the 3rd/4th of the remaining team: whoever has fewer cards ranks higher
        if (finish.length == 4 && hands[finish[2]].length > hands[finish[3]].length) {
          final t = finish[2];
          finish[2] = finish[3];
          finish[3] = t;
        }
        _endDeal();
        return;
      }
    } else if (rest.length <= 10 && hands[seat].length + cards.length > 10) {
      host.log('${name(seat)} 报牌：剩 ${rest.length} 张');
    }
    _advance();
  }

  List<int> get _active => [for (var s = 0; s < 4; s++) if (!finish.contains(s)) s];

  void _advance() {
    final active = _active;
    final need = active.where((s) => s != tableSeat).length;
    if (passes >= need) {
      // trick over
      final leader = finish.contains(tableSeat) ? partner(tableSeat) : tableSeat;
      if (finish.contains(tableSeat)) host.log('${name(leader)} 接风');
      table = null;
      tableCards = [];
      passes = 0;
      acts = List.filled(4, null);
      turn = leader;
      if (finish.contains(turn)) turn = _nextActive(turn);
      return;
    }
    turn = _nextActive(turn);
  }

  int _nextActive(int from) {
    var t = from;
    for (var i = 0; i < 4; i++) {
      t = (t + 1) % 4;
      if (!finish.contains(t)) return t;
    }
    return from;
  }

  void _resolveTribute() {
    final list = [for (final p in payers) (p, paid[p]!)];
    list.sort((x, y) => gdValue(y.$2, level) - gdValue(x.$2, level));
    final info = <String, dynamic>{'resist': false, 'pay': <Map<String, dynamic>>[]};
    for (var i = 0; i < list.length; i++) {
      final (p, c) = list[i];
      final r = receivers[i];
      hands[p].remove(c);
      hands[r] = gdSort([...hands[r], c], level);
      pairTo[r] = p;
      (info['pay'] as List).add({'from': p, 'to': r, 'card': c});
      host.log('${name(p)} 向 ${name(r)} 进贡 ${gdRankName(gdNat(c))}');
    }
    _leadAfterTribute = list.first.$1;
    tributeInfo = info;
    phase = 'return';
  }

  void _endDeal() {
    deal++;
    lastFinish = List.of(finish);
    final w = team(finish[0]);
    final partnerPos = finish.indexOf(partner(finish[0]));
    final up = partnerPos == 1 ? 3 : (partnerPos == 2 ? 2 : 1);
    final before = List.of(levels);
    var matchWin = false;
    final atTop = levels[w] >= target;
    final lt = levelTeam;
    if (levels[lt] >= target && (w != lt || partnerPos == 3)) {
      aFails[lt]++;
      if (aFails[lt] >= 3) {
        host.log('${lt == 0 ? "南北" : "东西"}队冲 ${gdRankName(target)} 失败三次，回到 2');
        levels[lt] = 2;
        aFails[lt] = 0;
      }
    }
    if (atTop && levelTeam == w) {
      if (partnerPos <= 2) matchWin = true;
    } else {
      levels[w] = (levels[w] + up).clamp(2, target);
    }
    levelTeam = w;
    winnerTeam = matchWin ? w : -1;
    result = {
      'finish': finish,
      'winTeam': w,
      'up': atTop ? 0 : up,
      'before': before,
      'levels': List.of(levels),
      'matchWin': matchWin,
      'hands': [for (final h in hands) h],
    };
    host.log('本局结束：${finish.map(name).join(' > ')}，${w == 0 ? "南北" : "东西"}队${atTop ? "" : "升 $up 级"}');
    if (!matchWin && cap > 0 && deal >= cap) {
      winnerTeam = levels[0] == levels[1] ? 2 : (levels[0] > levels[1] ? 0 : 1);
      matchWin = true;
      host.log('已达局数上限');
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
    final showAll = phase == 'dealEnd' || phase == 'over';
    return {
      'game': 'guandan',
      'phase': phase,
      'deal': deal,
      'cap': cap,
      'target': target,
      'levels': levels,
      'levelTeam': levelTeam,
      'level': level,
      'wild': '${gdRankChar(level)}H',
      'turn': turn,
      'hand': seat >= 0 && seat < 4 ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'hands': showAll ? [for (final h in hands) h] : null,
      'table': table?.toJson(),
      'tableSeat': tableSeat,
      'lead': phase == 'play' && table == null,
      'acts': acts,
      'finish': finish,
      'payers': payers,
      'receivers': receivers,
      'paid': [for (final p in payers) paid.containsKey(p)],
      'tribute': tributeInfo,
      'maxTribute': seat >= 0 && payers.contains(seat) ? _maxTributeValue(seat) : null,
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
      case 'dealEnd':
        return {'type': 'continue'};
      case 'over':
        return null;
      case 'tribute':
        final mv = _maxTributeValue(seat);
        final c = hands[seat].firstWhere((c) => !gdIsWild(c, level) && gdValue(c, level) == mv);
        return {'type': 'tribute', 'card': c};
      case 'return':
        final opts = List.of(_returnable(seat));
        // return a small card that is alone in its rank
        opts.sort((x, y) {
          int alone(String c) => hands[seat].where((d) => gdNat(d) == gdNat(c)).length;
          final d = alone(x) - alone(y);
          return d != 0 ? d : gdValue(x, level) - gdValue(y, level);
        });
        return {'type': 'return', 'card': opts.first};
    }
    if (seat != turn) return null;
    if (botLevel == 0 && rng.nextDouble() < 0.45) {
      // 简单：随手出一手能出的牌（不轻易拆炸弹），跟牌时也常常直接不要
      final cands = gdCandidates(hands[seat], table, level);
      final soft = [for (final p in cands) if (!p.combo.isBomb) p];
      if (table != null && (soft.isEmpty || rng.nextBool())) return {'type': 'pass'};
      final pool = soft.isNotEmpty ? soft : cands;
      if (pool.isNotEmpty) {
        final p = pool[rng.nextInt(pool.length)];
        return {'type': 'play', 'cards': p.cards, 'as': p.combo.type};
      }
    }
    return _botPlay(seat);
  }

  Map<String, dynamic> _botPlay(int seat) {
    final hand = hands[seat];
    final cands = gdCandidates(hand, table, level);
    Map<String, dynamic> play(GdPlay p) => {'type': 'play', 'cards': p.cards, 'as': p.combo.type};
    for (final p in cands) {
      if (p.cards.length == hand.length) return play(p);
    }
    final baseCost = gdHandCost(hand, level);
    double restCost(GdPlay p) {
      final rest = List.of(hand);
      for (final c in p.cards) {
        rest.remove(c);
      }
      return gdHandCost(rest, level);
    }

    final counts = [for (final h in hands) h.length];
    final opp = [for (var s = 0; s < 4; s++) if (team(s) != team(seat) && !finish.contains(s)) s];
    final oppMin = opp.isEmpty ? 99 : opp.map((s) => counts[s]).reduce((a, b) => a < b ? a : b);
    final pt = partner(seat);
    final partnerActive = !finish.contains(pt);
    final hard = botLevel == 2;
    final nextOpp = _nextActive(seat);
    final nextOppCount = team(nextOpp) != team(seat) ? counts[nextOpp] : 99;

    if (table == null) {
      GdPlay? best;
      var bestScore = double.infinity;
      for (final p in cands) {
        if (p.combo.isBomb && cands.any((q) => !q.combo.isBomb)) continue;
        var score = restCost(p) + p.combo.key * 0.4 + p.wilds(level) * 4;
        // opponents close to finishing: avoid leading what they can easily beat
        if (oppMin <= 2 && p.cards.length <= oppMin) score += 15 - p.combo.key;
        // help partner who is close to finishing: lead small singles/pairs
        if (partnerActive && counts[pt] <= 3 && p.cards.length <= counts[pt]) score -= 6;
        if (hard) {
          // 困难：下家对手只剩 1~2 张时绝不出同张数的小牌；出完这手后只剩一手就优先
          if (p.cards.length == nextOppCount) score += 25 - p.combo.key;
          final rest = List.of(hand);
          for (final c in p.cards) {
            rest.remove(c);
          }
          if (rest.isNotEmpty && gdAnalyze(rest, level).isNotEmpty) score -= 30;
        }
        if (score < bestScore) {
          bestScore = score;
          best = p;
        }
      }
      best ??= cands.first;
      return play(best);
    }

    final partnerLeads = team(tableSeat) == team(seat);
    GdPlay? best;
    var bestScore = double.infinity;
    for (final p in cands) {
      var score = restCost(p) - baseCost + p.wilds(level) * 3.5;
      if (p.combo.isBomb) {
        final urgent = oppMin <= 6 || hand.length - p.cards.length <= 6;
        score += urgent ? 6 : 22;
        score += p.combo.power * 0.1;
      }
      score += p.combo.key * 0.3;
      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best == null) return {'type': 'pass'};
    if (partnerLeads) {
      // only overtake partner cheaply, never with bombs
      if (hard && partnerActive && counts[pt] <= 4) return {'type': 'pass'}; // 队友快走了，别挡
      if (best.combo.isBomb || bestScore > -2 || table!.key >= 13) return {'type': 'pass'};
      return play(best);
    }
    if (hard) {
      // 困难：出牌的对手快出完时不惜代价压住
      final leaderCount = finish.contains(tableSeat) ? 99 : counts[tableSeat];
      if (leaderCount <= 4 || oppMin <= 3) return play(best);
      // 压得住又不拆牌就压，免得对手顺走
      if (!best.combo.isBomb && bestScore <= 4) return play(best);
    }
    final threshold = oppMin <= 5 ? 30.0 : (table!.key >= 14 ? 6.0 : 10.0);
    if (bestScore > threshold) return {'type': 'pass'};
    return play(best);
  }
}
