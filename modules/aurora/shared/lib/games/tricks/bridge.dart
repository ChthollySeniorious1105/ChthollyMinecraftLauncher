import '../../src/engine.dart';
import 'bridge_ai.dart';
import 'bridge_rules.dart';
import 'cards.dart';
import 'pimc.dart';

/// 桥牌（盘式 / 芝加哥）. Seats 0..3 = 北 东 南 西; 南北(0,2) vs 东西(1,3).
class Bridge extends GameEngine {
  Bridge(super.setup);

  late final String mode = setup.opt<String>('scoring', 'rubber');
  late final int cap = setup.opt<int>('cap', 0);

  String phase = 'auction'; // auction | play | trickEnd | dealEnd | over
  int dealer = 0;
  int dealNo = 0; // deals actually played / attempted (for cap)
  int chicagoIndex = 0; // 0..3 deals completed in chicago
  List<List<String>> hands = [];
  List<List<String>> orig = [];
  late BrAuction auction;
  BrContract? contract;
  int turn = 0;
  List<Map<String, dynamic>> trick = [];
  List<Map<String, dynamic>> lastTrick = [];
  int lastWinner = -1;
  List<String> played = [];
  List<int> tricksWon = [0, 0];
  bool dummyShown = false;

  // scoring
  List<int> gamesWon = [0, 0];
  List<int> belowCur = [0, 0]; // below-the-line points of the current game
  int gameIdx = 0;
  final List<Map<String, dynamic>> sheet = []; // {side, line, pts, game, label}
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? result;
  List<bool> ready = List.filled(4, false);
  int winner = -1; // 0 / 1 / 2 = tie
  List<(int, String)> playSeq = []; // public play order this deal

  int get declarer => contract!.declarer;
  int get dummy => (declarer + 2) % 4;

  List<bool> get vul => mode == 'chicago'
      ? brChicagoVul(chicagoIndex, dealer)
      : [gamesWon[0] > 0, gamesWon[1] > 0];

  List<int> get totals {
    final t = [0, 0];
    for (final e in sheet) {
      t[e['side'] as int] += e['pts'] as int;
    }
    return t;
  }

  @override
  void start() {
    dealer = 0;
    _deal();
  }

  void _deal() {
    hands = trDeal(rng);
    orig = [for (final h in hands) List.of(h)];
    auction = BrAuction(dealer);
    contract = null;
    turn = dealer;
    trick = [];
    lastTrick = [];
    lastWinner = -1;
    played = [];
    playSeq = [];
    tricksWon = [0, 0];
    dummyShown = false;
    result = null;
    phase = 'auction';
    host.log('第 ${dealNo + 1} 副 · 发牌人 ${brSeatNames[dealer]}（${name(dealer)}）');
  }

  @override
  bool get isOver => phase == 'over';

  /// 南北(0,2) vs 东西(1,3)：胜方全 1，败方全 2，平局全 1。
  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (winner != 0 && winner != 1) return List.filled(4, 1);
    return [for (var s = 0; s < 4; s++) brSide(s) == winner ? 1 : 2];
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'auction':
        return [turn];
      case 'play':
        return [turn == dummy ? declarer : turn];
      case 'dealEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'auction':
        if (type != 'call') throw GameError('现在是叫牌阶段');
        final call = asStr(a['call']);
        final err = auction.illegal(seat, call);
        if (err != null) throw GameError(err);
        auction.add(seat, call);
        host.log('${name(seat)}：${brCallName(call)}');
        if (auction.isOver) {
          _endAuction();
        } else {
          turn = auction.turn;
        }
        return;
      case 'play':
        if (type != 'play') throw GameError('现在是打牌阶段');
        final actor = turn == dummy ? declarer : turn;
        if (seat != actor) {
          if (seat == dummy) throw GameError('你是明手，由庄家代打');
          throw GameError('还没轮到你出牌');
        }
        _play(asStr(a['card']));
        return;
      case 'dealEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) _next();
        return;
    }
    throw GameError('现在不能操作');
  }

  void _endAuction() {
    if (auction.passedOut) {
      host.log('四家都不叫，重新发牌');
      result = {'passedOut': true};
      _toDealEnd();
      return;
    }
    final lb = auction.lastBid!;
    contract = BrContract(int.parse(lb.call[0]), lb.call[1], auction.doubled, auction.declarer!);
    host.log('定约 ${contract!.label}，庄家 ${brSeatNames[declarer]}（${name(declarer)}）');
    phase = 'play';
    turn = (declarer + 1) % 4;
  }

  void _play(String card) {
    final hand = hands[turn];
    if (!hand.contains(card)) throw GameError('没有这张牌');
    final lead = trick.isEmpty ? null : trSuit(trick.first['card'] as String);
    if (!trFollow(hand, lead).contains(card)) throw GameError('必须跟出${trSuitName[lead]}');
    hand.remove(card);
    trick.add({'seat': turn, 'card': card});
    playSeq.add((turn, card));
    dummyShown = true;
    if (trick.length < 4) {
      turn = (turn + 1) % 4;
      return;
    }
    final w = trWinner([for (final t in trick) t['card'] as String], contract!.trump);
    final ws = trick[w]['seat'] as int;
    tricksWon[brSide(ws)]++;
    lastWinner = ws;
    phase = 'trickEnd';
    host.schedule(1200, _collect);
  }

  void _collect() {
    if (phase != 'trickEnd') return;
    played.addAll([for (final t in trick) t['card'] as String]);
    lastTrick = trick;
    trick = [];
    turn = lastWinner;
    if (played.length == 52) {
      _scoreDeal();
    } else {
      phase = 'play';
    }
  }

  void _add(int side, String line, int pts, String label) {
    if (pts == 0) return;
    sheet.add({'side': side, 'line': line, 'pts': pts, 'game': gameIdx, 'label': label});
  }

  void _scoreDeal() {
    final c = contract!;
    final side = brSide(c.declarer);
    final tricks = tricksWon[side];
    final v = vul[side];
    final s = brScore(c, v, tricks);
    final need = c.level + 6;
    final diff = tricks - need;
    final res = <String, dynamic>{
      'contract': c.label,
      'declarer': c.declarer,
      'tricks': tricks,
      'diff': diff,
      'vul': v,
    };
    var ns = 0, ew = 0;
    void credit(int sd, int p) => sd == 0 ? ns += p : ew += p;
    if (mode == 'chicago') {
      final t = s.duplicateTotal(v);
      if (t >= 0) {
        _add(side, 'above', t, c.label);
        credit(side, t);
      } else {
        _add(1 - side, 'above', -t, '${c.label} 宕');
        credit(1 - side, -t);
      }
    } else {
      final lines = <String>[];
      if (s.made) {
        _add(side, 'below', s.below, c.label);
        credit(side, s.below);
        belowCur[side] += s.below;
        _add(side, 'above', s.overtricks, '超墩');
        _add(side, 'above', s.slam, '满贯');
        _add(side, 'above', s.insult, '加倍奖');
        credit(side, s.declAbove);
      } else {
        _add(1 - side, 'above', s.undertricks, '宕墩');
        credit(1 - side, s.undertricks);
      }
      final (hs, hp) = brHonours(orig, c.strain);
      if (hp > 0) {
        _add(brSide(hs), 'above', hp, '大牌分');
        credit(brSide(hs), hp);
        lines.add('${brSideName(brSide(hs))} 大牌分 $hp');
      }
      if (belowCur[side] >= 100) {
        gamesWon[side]++;
        lines.add('${brSideName(side)} 完成一局');
        belowCur = [0, 0];
        gameIdx++;
        if (gamesWon[side] == 2) {
          final bonus = gamesWon[1 - side] == 0 ? 700 : 500;
          _add(side, 'above', bonus, '盘奖');
          credit(side, bonus);
          lines.add('${brSideName(side)} 赢得一盘 +$bonus');
        }
      }
      res['notes'] = lines;
    }
    res['ns'] = ns;
    res['ew'] = ew;
    result = res;
    history.add({
      'no': dealNo + 1,
      'contract': c.label,
      'declarer': c.declarer,
      'diff': diff,
      'ns': ns,
      'ew': ew,
    });
    final how = diff >= 0 ? (diff == 0 ? '刚好完成' : '超 $diff 墩完成') : '宕 ${-diff} 墩';
    host.log('${c.label} ${how}：南北 +$ns，东西 +$ew');
    if (mode == 'chicago') chicagoIndex++;
    dealNo++;
    _toDealEnd();
  }

  void _toDealEnd() {
    if (result?['passedOut'] == true) dealNo++;
    bool over;
    if (mode == 'chicago') {
      over = chicagoIndex >= 4;
    } else {
      over = gamesWon[0] == 2 || gamesWon[1] == 2;
      if (!over && cap > 0 && dealNo >= cap) {
        // unfinished rubber
        for (var sd = 0; sd < 2; sd++) {
          if (gamesWon[sd] == 1 && gamesWon[1 - sd] == 0) _add(sd, 'above', 300, '未完成盘·一局');
          if (belowCur[sd] > 0) _add(sd, 'above', 100, '未完成局·部分分');
        }
        over = true;
      }
    }
    if (over) {
      final t = totals;
      winner = t[0] == t[1] ? 2 : (t[0] > t[1] ? 0 : 1);
      phase = 'over';
      host.log(winner == 2 ? '比赛结束：平局' : '比赛结束：${brSideName(winner)}获胜（${t[0]} : ${t[1]}）');
      return;
    }
    phase = 'dealEnd';
    ready = [for (var s = 0; s < 4; s++) false];
  }

  void _next() {
    // chicago: a passed-out deal is redealt by the same dealer
    if (!(mode == 'chicago' && result?['passedOut'] == true)) dealer = (dealer + 1) % 4;
    _deal();
  }

  List<String> _legalFor(int seat) {
    if (phase != 'play') return const [];
    final actor = turn == dummy ? declarer : turn;
    if (seat != actor) return const [];
    final lead = trick.isEmpty ? null : trSuit(trick.first['card'] as String);
    return trFollow(hands[turn], lead);
  }

  @override
  Map<String, dynamic> view(int seat) {
    final inPlay = phase == 'play' || phase == 'trickEnd';
    final showAll = phase == 'dealEnd' || phase == 'over';
    final c = contract;
    return {
      'game': 'bridge',
      'mode': mode,
      'phase': phase,
      'dealer': dealer,
      'dealNo': dealNo,
      'chicagoIndex': chicagoIndex,
      'cap': cap,
      'vul': vul,
      'hand': seat >= 0 ? hands[seat] : <String>[],
      'counts': [for (final h in hands) h.length],
      'calls': [for (final x in auction.calls) x.toJson()],
      'legalCalls': phase == 'auction' && seat == turn ? auction.legalCalls(seat) : <String>[],
      'turn': turn,
      'actor': phase == 'play' ? (c != null && turn == (c.declarer + 2) % 4 ? c.declarer : turn) : (phase == 'auction' ? turn : -1),
      'contract': c?.toJson(),
      'declarer': c?.declarer ?? -1,
      'dummy': c == null ? -1 : (c.declarer + 2) % 4,
      'dummyHand': c != null && inPlay && dummyShown ? hands[(c.declarer + 2) % 4] : null,
      'trick': trick,
      'lastTrick': lastTrick,
      'lastWinner': lastWinner,
      'played': played,
      'tricks': tricksWon,
      'legal': seat >= 0 ? _legalFor(seat) : <String>[],
      'gamesWon': gamesWon,
      'belowCur': belowCur,
      'sheet': sheet,
      'totals': totals,
      'history': history,
      'result': showAll ? result : null,
      'allHands': showAll ? orig : null,
      'ready': phase == 'dealEnd' ? ready : null,
      'winner': winner,
      'over': isOver,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'dealEnd') return ready[seat] ? null : {'type': 'continue'};
    if (!waitingFor.contains(seat)) return null;
    final v = view(seat);
    if (phase == 'auction') {
      final legal = auction.legalCalls(seat);
      // 简单：有时乱叫（只在不会把叫牌抬得太高时），更多时候直接不叫
      if (botLevel == 0 && rng.nextDouble() < 0.35) {
        final low = [for (final c in legal) if (c != 'X' && c != 'XX' && (c == 'P' || int.parse(c[0]) <= 3)) c];
        if (low.isNotEmpty) return {'type': 'call', 'call': low[rng.nextInt(low.length)]};
      }
      return {'type': 'call', 'call': brBotCall(v, seat)};
    }
    if (phase == 'play') {
      final lg = _legalFor(seat);
      if (botLevel == 0 && lg.isNotEmpty && rng.nextDouble() < 0.45) {
        return {'type': 'play', 'card': lg[rng.nextInt(lg.length)]};
      }
      if (botLevel == 2 && lg.length > 1) return {'type': 'play', 'card': _hardPlay(seat, lg)};
      return {'type': 'play', 'card': brBotPlay(v, seat)};
    }
    return null;
  }

  /// 困难：按 [seat] 能看到的信息（自己的牌、明手、已出牌、缺门）抽样暗手，
  /// 用普通策略打完本副，选本方平均赢墩最多的牌。
  String _hardPlay(int seat, List<String> lg) {
    final r = rng;
    final c = contract!;
    final trump = c.trump;
    final visible = <int>{seat, if (dummyShown) dummy};
    final gone = <String>{...played, for (final t in trick) t['card'] as String};
    for (final s in visible) {
      gone.addAll(hands[s]);
    }
    final unknown = [for (final x in trDeck()) if (!gone.contains(x)) x];
    final need = [for (var s = 0; s < 4; s++) visible.contains(s) ? 0 : hands[s].length];
    final voids = trVoids(playSeq);
    List<List<String>>? sample() {
      final d = trSampleDeal(r, unknown, need, voids) ?? trSampleDeal(r, unknown, need, List.generate(4, (_) => <String>{}));
      if (d == null) return null;
      for (final s in visible) {
        d[s] = List.of(hands[s]);
      }
      return d;
    }

    final mySide = brSide(seat);
    double rollout(List<List<String>> deal, String card) {
      final h = [for (final x in deal) List.of(x)];
      final tr = <(int, String)>[for (final t in trick) (t['seat'] as int, t['card'] as String)];
      final pl = List.of(played);
      final won = List.of(tricksWon);
      var t = turn;
      var first = true;
      while (pl.length + tr.length < 52) {
        String x;
        final lgl = trFollow(h[t], tr.isEmpty ? null : trSuit(tr.first.$2));
        if (first) {
          x = card;
          first = false;
        } else if (lgl.length == 1) {
          x = lgl.first;
        } else {
          final actor = t == dummy ? declarer : t;
          x = brBotPlay({
            'legal': lgl,
            'contract': c.toJson(),
            'declarer': declarer,
            'dummy': dummy,
            'turn': t,
            'hand': h[actor],
            'dummyHand': h[dummy],
            'trick': [for (final y in tr) {'seat': y.$1, 'card': y.$2}],
            'played': pl,
          }, actor);
        }
        h[t].remove(x);
        tr.add((t, x));
        if (tr.length < 4) {
          t = (t + 1) % 4;
          continue;
        }
        final w = tr[trWinner([for (final y in tr) y.$2], trump)].$1;
        won[brSide(w)]++;
        pl.addAll([for (final y in tr) y.$2]);
        tr.clear();
        t = w;
      }
      return won[mySide].toDouble();
    }

    return trPimc(r, lg, sample, rollout, samples: 14, maxMs: 800);
  }
}
