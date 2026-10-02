import '../../src/engine.dart';
import 'cards.dart';
import 'pimc.dart';

/// 红心大战. 4 players, no partners. Lowest score wins when someone reaches the target.
class Hearts extends GameEngine {
  Hearts(super.setup);

  late final int target = setup.opt<int>('target', 100);
  late final bool moon = setup.opt<bool>('moon', true);
  late final bool firstTrickClean = setup.opt<bool>('firstClean', true);
  late final int cap = setup.opt<int>('cap', 0);

  String phase = 'pass'; // pass | play | trickEnd | handEnd | over
  int handNo = 0;
  List<List<String>> hands = [];
  List<List<String>?> passSel = List.filled(4, null);
  List<List<String>> received = List.generate(4, (_) => []);
  int turn = 0;
  List<Map<String, dynamic>> trick = [];
  List<Map<String, dynamic>> lastTrick = [];
  int lastWinner = -1;
  List<String> played = [];
  List<int> taken = [0, 0, 0, 0]; // points this hand
  List<List<String>> takenCards = List.generate(4, (_) => []);
  List<int> scores = [0, 0, 0, 0];
  bool heartsBroken = false;
  int trickNo = 0;
  final List<List<int>> history = [];
  Map<String, dynamic>? result;
  List<bool> ready = List.filled(4, false);
  List<int> winners = [];
  List<(int, String)> playSeq = []; // public: who played what this hand

  /// 0 left, 1 right, 2 across, 3 hold.
  int get passDir => handNo % 4;
  static const dirNames = ['向左传', '向右传', '向对家传', '不传牌'];
  int passTarget(int s) => switch (passDir) { 0 => (s + 1) % 4, 1 => (s + 3) % 4, _ => (s + 2) % 4 };

  @override
  void start() => _deal();

  void _deal() {
    hands = trDeal(rng);
    passSel = List.filled(4, null);
    received = List.generate(4, (_) => []);
    trick = [];
    lastTrick = [];
    lastWinner = -1;
    played = [];
    playSeq = [];
    taken = [0, 0, 0, 0];
    takenCards = List.generate(4, (_) => []);
    heartsBroken = false;
    trickNo = 0;
    result = null;
    host.log('第 ${handNo + 1} 局 · ${dirNames[passDir]}');
    if (passDir == 3) {
      _beginPlay();
    } else {
      phase = 'pass';
    }
  }

  void _beginPlay() {
    phase = 'play';
    turn = [for (var s = 0; s < 4; s++) if (hands[s].contains('2C')) s].first;
  }

  @override
  bool get isOver => phase == 'over';

  /// 分数低者名次高；并列同名次。
  @override
  List<int>? get placings => isOver ? rankByScore(scores, lowWins: true) : null;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'pass':
        return [for (var s = 0; s < 4; s++) if (passSel[s] == null) s];
      case 'play':
        return [turn];
      case 'handEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  static int points(String c) => c == 'QS' ? 13 : (trSuit(c) == 'H' ? 1 : 0);

  List<String> legal(int s) {
    if (phase != 'play' || s != turn) return const [];
    final h = hands[s];
    if (trick.isEmpty) {
      if (trickNo == 0) return h.contains('2C') ? ['2C'] : List.of(h);
      if (!heartsBroken) {
        final nonH = [for (final c in h) if (trSuit(c) != 'H') c];
        if (nonH.isNotEmpty) return nonH;
      }
      return List.of(h);
    }
    final f = trFollow(h, trSuit(trick.first['card'] as String));
    if (trickNo == 0 && firstTrickClean) {
      final clean = [for (final c in f) if (points(c) == 0) c];
      if (clean.isNotEmpty) return clean;
    }
    return f;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'pass':
        if (type != 'pass') throw GameError('请选择 3 张牌传出');
        if (passSel[seat] != null) throw GameError('你已经传过牌了');
        final cards = [for (final c in (a['cards'] is List ? a['cards'] as List : const [])) '$c'];
        if (cards.length != 3 || cards.toSet().length != 3) throw GameError('必须选择 3 张牌');
        if (!cards.every(hands[seat].contains)) throw GameError('没有这些牌');
        passSel[seat] = cards;
        if (passSel.every((p) => p != null)) {
          for (var s = 0; s < 4; s++) {
            hands[s].removeWhere(passSel[s]!.contains);
          }
          for (var s = 0; s < 4; s++) {
            final t = passTarget(s);
            received[t] = List.of(passSel[s]!);
            hands[t].addAll(passSel[s]!);
          }
          for (var s = 0; s < 4; s++) {
            hands[s] = trSort(hands[s]);
          }
          host.log('传牌完成');
          _beginPlay();
        }
        return;
      case 'play':
        if (type != 'play') throw GameError('现在是出牌阶段');
        if (seat != turn) throw GameError('还没轮到你出牌');
        final card = asStr(a['card']);
        if (!hands[seat].contains(card)) throw GameError('没有这张牌');
        if (!legal(seat).contains(card)) {
          if (trickNo == 0 && trick.isEmpty) throw GameError('第一墩必须由梅花 2 首出');
          if (trick.isEmpty) throw GameError('红心还没破，不能首出红心');
          final lead = trSuit(trick.first['card'] as String);
          if (trOfSuit(hands[seat], lead).isNotEmpty) throw GameError('必须跟出${trSuitName[lead]}');
          throw GameError('第一墩不能出分牌');
        }
        hands[seat].remove(card);
        trick.add({'seat': seat, 'card': card});
        playSeq.add((seat, card));
        if (trSuit(card) == 'H') heartsBroken = true;
        if (trick.length < 4) {
          turn = (turn + 1) % 4;
          return;
        }
        final cards = [for (final t in trick) t['card'] as String];
        final w = trick[trWinner(cards, null)]['seat'] as int;
        lastWinner = w;
        taken[w] += cards.fold(0, (s, c) => s + points(c));
        takenCards[w].addAll([for (final c in cards) if (points(c) > 0) c]);
        phase = 'trickEnd';
        host.schedule(1100, _collect);
        return;
      case 'handEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) {
          handNo++;
          _deal();
        }
        return;
    }
    throw GameError('现在不能操作');
  }

  void _collect() {
    if (phase != 'trickEnd') return;
    played.addAll([for (final t in trick) t['card'] as String]);
    lastTrick = trick;
    trick = [];
    trickNo++;
    turn = lastWinner;
    if (trickNo < 13) {
      phase = 'play';
      return;
    }
    // hand over
    final (add, shooter) = heartsHandScore(taken, moon);
    if (shooter >= 0) host.log('${name(shooter)} 全收（射月）！其他人各 +26');
    for (var s = 0; s < 4; s++) {
      scores[s] += add[s];
    }
    history.add(add);
    result = {'taken': taken, 'add': add, 'moon': shooter, 'cards': takenCards};
    host.log('本局得分：${[for (var s = 0; s < 4; s++) '${name(s)} +${add[s]}'].join('，')}');
    if (scores.any((x) => x >= target) || (cap > 0 && handNo + 1 >= cap)) {
      final lo = scores.reduce((a, b) => a < b ? a : b);
      winners = [for (var s = 0; s < 4; s++) if (scores[s] == lo) s];
      phase = 'over';
      host.log('比赛结束：${winners.map(name).join('、')} 获胜（$lo 分）');
      return;
    }
    phase = 'handEnd';
    ready = List.filled(4, false);
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'game': 'hearts',
        'phase': phase,
        'handNo': handNo,
        'target': target,
        'cap': cap,
        'passDir': passDir,
        'hand': seat >= 0 ? hands[seat] : <String>[],
        'counts': [for (final h in hands) h.length],
        'passed': [for (final p in passSel) p != null],
        'myPass': seat >= 0 ? passSel[seat] : null,
        'received': seat >= 0 && phase != 'pass' ? received[seat] : <String>[],
        'turn': turn,
        'trick': trick,
        'lastTrick': lastTrick,
        'lastWinner': lastWinner,
        'trickNo': trickNo,
        'played': played,
        'heartsBroken': heartsBroken,
        'taken': taken,
        'takenCards': takenCards,
        'scores': scores,
        'history': history,
        'legal': seat >= 0 ? legal(seat) : <String>[],
        'result': phase == 'handEnd' || phase == 'over' ? result : null,
        'ready': phase == 'handEnd' ? ready : null,
        'winners': winners,
        'over': isOver,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'pass':
        if (passSel[seat] != null) return null;
        if (botLevel == 0 && rng.nextBool()) return {'type': 'pass', 'cards': (List.of(hands[seat])..shuffle(rng)).take(3).toList()};
        return {'type': 'pass', 'cards': heartsBotPass(hands[seat])};
      case 'play':
        if (seat != turn) return null;
        final lg = legal(seat);
        if (botLevel == 0 && rng.nextDouble() < 0.45) return {'type': 'play', 'card': lg[rng.nextInt(lg.length)]};
        if (botLevel == 2 && lg.length > 1) return {'type': 'play', 'card': _hardPlay(seat, lg)};
        return {'type': 'play', 'card': heartsBotPlay(view(seat))};
      case 'handEnd':
        return ready[seat] ? null : {'type': 'continue'};
    }
    return null;
  }
}

extension _HeartsHard on Hearts {
  /// 困难：按公开信息（已出的牌、谁垫过哪门、自己传出的牌去向）抽样其余三家的手牌，
  /// 每张候选牌用普通电脑的策略把本局打完，选平均罚分最少的一张。
  String _hardPlay(int seat, List<String> lg) {
    final r = rng;
    final mine = hands[seat].toSet();
    final gone = <String>{...played, for (final t in trick) t['card'] as String};
    final unknown = [for (final c in trDeck()) if (!gone.contains(c) && !mine.contains(c)) c];
    final need = [for (var s = 0; s < 4; s++) s == seat ? 0 : hands[s].length];
    final voids = trVoids(playSeq);
    final fixed = <int, List<String>>{};
    if (passDir != 3 && passSel[seat] != null) {
      final t = passTarget(seat);
      fixed[t] = [for (final c in passSel[seat]!) if (unknown.contains(c)) c];
    }
    List<List<String>>? sample() {
      final d = trSampleDeal(r, unknown, need, voids, fixed: fixed) ??
          trSampleDeal(r, unknown, need, List.generate(4, (_) => <String>{}), fixed: fixed);
      if (d == null) return null;
      d[seat] = List.of(hands[seat]);
      return d;
    }

    double rollout(List<List<String>> deal, String card) {
      final h = [for (final x in deal) List.of(x)];
      final tr = <(int, String)>[for (final t in trick) (t['seat'] as int, t['card'] as String)];
      final pl = List.of(played);
      final tk = List.of(taken);
      var broken = heartsBroken;
      var tn = trickNo;
      var t = seat;
      var first = true;
      while (tn < 13) {
        String c;
        if (first) {
          c = card;
          first = false;
        } else {
          final lgl = _legalSim(h[t], tr, tn, broken);
          c = lgl.length == 1
              ? lgl.first
              : heartsBotPlay({
                  'legal': lgl,
                  'trick': [for (final x in tr) {'seat': x.$1, 'card': x.$2}],
                  'played': pl,
                  'hand': h[t],
                });
        }
        h[t].remove(c);
        tr.add((t, c));
        if (trSuit(c) == 'H') broken = true;
        if (tr.length < 4) {
          t = (t + 1) % 4;
          continue;
        }
        final cards = [for (final x in tr) x.$2];
        final w = tr[trWinner(cards, null)].$1;
        tk[w] += cards.fold(0, (a, x) => a + Hearts.points(x));
        pl.addAll(cards);
        tr.clear();
        tn++;
        t = w;
      }
      final (add, _) = heartsHandScore(tk, moon);
      // relative: my penalty vs the average of the others
      final others = (add.fold<int>(0, (a, b) => a + b) - add[seat]) / 3;
      return others - add[seat] * 1.5;
    }

    return trPimc(r, lg, sample, rollout, samples: 16, maxMs: 700);
  }

  List<String> _legalSim(List<String> h, List<(int, String)> tr, int tn, bool broken) {
    if (tr.isEmpty) {
      if (tn == 0 && h.contains('2C')) return ['2C'];
      if (!broken) {
        final nonH = [for (final c in h) if (trSuit(c) != 'H') c];
        if (nonH.isNotEmpty) return nonH;
      }
      return List.of(h);
    }
    final f = trFollow(h, trSuit(tr.first.$2));
    if (tn == 0 && firstTrickClean) {
      final clean = [for (final c in f) if (Hearts.points(c) == 0) c];
      if (clean.isNotEmpty) return clean;
    }
    return f;
  }
}

/// Points added this hand and the moon shooter (-1 if none).
(List<int>, int) heartsHandScore(List<int> taken, bool moon) {
  if (moon) {
    for (var s = 0; s < 4; s++) {
      if (taken[s] == 26) return ([for (var i = 0; i < 4; i++) i == s ? 0 : 26], s);
    }
  }
  return (List.of(taken), -1);
}

/// Pass: dump Q♠/K♠/A♠ (unless well guarded), high hearts, and try to void a short suit.
List<String> heartsBotPass(List<String> hand) {
  final h = List.of(hand);
  final out = <String>[];
  final spades = trOfSuit(h, 'S');
  final lowSpades = spades.where((c) => trRank(c) < 10).length;
  double danger(String c) {
    final s = trSuit(c);
    final r = trRank(c).toDouble();
    if (c == 'QS' || c == 'KS' || c == 'AS') return lowSpades >= 4 ? 0 : 40 + r;
    if (s == 'S') return r * 0.3;
    final len = trOfSuit(h, s).length;
    var d = r + (s == 'H' ? 4 : 0);
    if (len <= 3) d += (4 - len) * 3; // voiding bonus
    if (c == '2C') d -= 5;
    return d;
  }

  while (out.length < 3) {
    h.sort((a, b) => danger(b).compareTo(danger(a)));
    out.add(h.removeAt(0));
  }
  return out;
}

String heartsBotPlay(Map<String, dynamic> v) {
  final legal = trStrList(v['legal']);
  if (legal.length == 1) return legal.first;
  final trick = [for (final t in v['trick'] as List) '${t['card']}'];
  final played = trStrList(v['played']).toSet();
  final hand = trStrList(v['hand']);
  final qsOut = !played.contains('QS') && !trick.contains('QS') && !hand.contains('QS');
  if (trick.isEmpty) {
    // lead the lowest card from a safe suit; avoid leading spades high when Q♠ is out
    String? best;
    var bestScore = 1e9;
    for (final c in legal) {
      var sc = trRank(c).toDouble();
      final s = trSuit(c);
      if (s == 'S' && qsOut && trRank(c) >= 10) sc += 30;
      if (c == 'QS') sc += 50;
      if (s == 'H') sc += 3;
      // prefer suits where we hold few cards (to get void)
      sc += trOfSuit(hand, s).length * 0.5;
      if (sc < bestScore) {
        bestScore = sc;
        best = c;
      }
    }
    return best!;
  }
  final lead = trSuit(trick.first);
  final following = legal.every((c) => trSuit(c) == lead);
  final winCard = trick[trWinner(trick, null)];
  final pts = trick.fold<int>(0, (s, c) => s + Hearts.points(c));
  final last = trick.length == 3;
  if (following) {
    final under = [for (final c in legal) if (trRank(c) < trRank(winCard)) c];
    if (legal.contains('QS') && trRank(winCard) > trRank('QS')) return 'QS';
    if (under.isNotEmpty) return trHighest(under)!;
    // must win: if last and no points, win with highest (but not Q♠)
    if (last && pts == 0) {
      final noQ = legal.where((c) => c != 'QS').toList();
      return trHighest(noQ.isEmpty ? legal : noQ)!;
    }
    if (lead == 'S' && qsOut) {
      final noHigh = legal.where((c) => trRank(c) < trRank('QS')).toList();
      if (noHigh.isNotEmpty) return trLowest(noHigh)!;
    }
    return trLowest(legal)!;
  }
  // void: dump Q♠, then high spades, then high hearts, then highest card
  if (legal.contains('QS')) return 'QS';
  for (final c in ['AS', 'KS']) {
    if (legal.contains(c) && qsOut) return c;
  }
  final hearts = trOfSuit(legal, 'H');
  if (hearts.isNotEmpty) return trHighest(hearts)!;
  return trHighest(legal)!;
}
