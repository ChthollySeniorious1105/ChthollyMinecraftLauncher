import '../../src/engine.dart';
import 'cards.dart';
import 'pimc.dart';

/// 黑桃王 (Spades). Partners 0&2 vs 1&3. Spades are always trump.
class Spades extends GameEngine {
  Spades(super.setup);

  late final int target = setup.opt<int>('target', 500);
  late final bool blindNil = setup.opt<bool>('blindNil', false);
  late final int cap = setup.opt<int>('cap', 0);

  String phase = 'bid'; // bid | play | trickEnd | handEnd | over
  int handNo = 0;
  int dealer = 0;
  List<List<String>> hands = [];
  List<bool> looked = List.filled(4, true);
  List<int?> bids = List.filled(4, null); // 0 = nil
  List<bool> blind = List.filled(4, false);
  int turn = 0;
  List<Map<String, dynamic>> trick = [];
  List<Map<String, dynamic>> lastTrick = [];
  int lastWinner = -1;
  List<String> played = [];
  List<int> won = [0, 0, 0, 0];
  bool broken = false;
  int trickNo = 0;
  List<int> scores = [0, 0];
  List<int> bags = [0, 0];
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? result;
  List<bool> ready = List.filled(4, false);
  int winner = -1;
  List<(int, String)> playSeq = []; // public play order this hand

  @override
  void start() => _deal();

  void _deal() {
    hands = trDeal(rng);
    looked = [for (var s = 0; s < 4; s++) !(blindNil && scores[s % 2] + 100 <= scores[1 - s % 2])];
    bids = List.filled(4, null);
    blind = List.filled(4, false);
    trick = [];
    lastTrick = [];
    lastWinner = -1;
    played = [];
    playSeq = [];
    won = [0, 0, 0, 0];
    broken = false;
    trickNo = 0;
    result = null;
    phase = 'bid';
    turn = (dealer + 1) % 4;
    host.log('第 ${handNo + 1} 局 · 发牌 ${name(dealer)}');
  }

  @override
  bool get isOver => phase == 'over';

  /// 南北(0,2) vs 东西(1,3)：胜队全 1，败队全 2，平局全 1。
  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (winner != 0 && winner != 1) return List.filled(4, 1);
    return [for (var s = 0; s < 4; s++) s % 2 == winner ? 1 : 2];
  }

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'bid':
      case 'play':
        return [turn];
      case 'handEnd':
        return [for (var s = 0; s < 4; s++) if (!ready[s]) s];
    }
    return const [];
  }

  bool canBlind(int s) => blindNil && !looked[s] && scores[s % 2] + 100 <= scores[1 - s % 2];

  List<String> legal(int s) {
    if (phase != 'play' || s != turn) return const [];
    final h = hands[s];
    if (trick.isEmpty) {
      if (!broken) {
        final ns = [for (final c in h) if (trSuit(c) != 'S') c];
        if (ns.isNotEmpty) return ns;
      }
      return List.of(h);
    }
    return trFollow(h, trSuit(trick.first['card'] as String));
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    switch (phase) {
      case 'bid':
        if (seat != turn) throw GameError('还没轮到你叫墩');
        if (type == 'look') {
          looked[seat] = true;
          return;
        }
        if (type == 'blindnil') {
          if (!canBlind(seat)) throw GameError('现在不能叫盲零');
          bids[seat] = 0;
          blind[seat] = true;
          looked[seat] = true;
          host.log('${name(seat)} 叫 盲零！');
        } else {
          if (type != 'bid') throw GameError('请叫墩');
          final n = asInt(a['n']);
          if (n < 0 || n > 13) throw GameError('叫墩数必须在 0~13 之间');
          looked[seat] = true;
          bids[seat] = n;
          host.log('${name(seat)} 叫 ${n == 0 ? '零墩（Nil）' : '$n 墩'}');
        }
        if (bids.every((b) => b != null)) {
          phase = 'play';
          turn = (dealer + 1) % 4;
        } else {
          turn = (turn + 1) % 4;
        }
        return;
      case 'play':
        if (type != 'play') throw GameError('现在是出牌阶段');
        if (seat != turn) throw GameError('还没轮到你出牌');
        final card = asStr(a['card']);
        if (!hands[seat].contains(card)) throw GameError('没有这张牌');
        if (!legal(seat).contains(card)) {
          if (trick.isEmpty) throw GameError('黑桃还没破，不能首出黑桃');
          throw GameError('必须跟出${trSuitName[trSuit(trick.first['card'] as String)]}');
        }
        hands[seat].remove(card);
        trick.add({'seat': seat, 'card': card});
        playSeq.add((seat, card));
        if (trSuit(card) == 'S') broken = true;
        if (trick.length < 4) {
          turn = (turn + 1) % 4;
          return;
        }
        final cards = [for (final t in trick) t['card'] as String];
        final w = trick[trWinner(cards, 'S')]['seat'] as int;
        lastWinner = w;
        won[w]++;
        phase = 'trickEnd';
        host.schedule(1100, _collect);
        return;
      case 'handEnd':
        if (type != 'continue') throw GameError('请点击继续');
        ready[seat] = true;
        if (ready.every((r) => r)) {
          handNo++;
          dealer = (dealer + 1) % 4;
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
    final res = <String, dynamic>{'teams': []};
    for (var t = 0; t < 2; t++) {
      final r = spadesScoreTeam([for (final s in [t, t + 2]) bids[s]!], [won[t], won[t + 2]], [blind[t], blind[t + 2]], bags[t]);
      scores[t] += r.delta;
      bags[t] = r.bags;
      (res['teams'] as List).add(r.toJson());
    }
    result = res;
    history.add({'no': handNo + 1, 'bids': bids, 'won': won, 'scores': List.of(scores), 'bags': List.of(bags)});
    host.log('本局：南北 ${_signed((res['teams'] as List)[0]['delta'] as int)}，东西 ${_signed((res['teams'] as List)[1]['delta'] as int)}');
    final reach = [for (var t = 0; t < 2; t++) scores[t] >= target];
    final bust = [for (var t = 0; t < 2; t++) scores[t] <= -200];
    final capHit = cap > 0 && handNo + 1 >= cap;
    if (((reach[0] || reach[1] || bust[0] || bust[1]) && scores[0] != scores[1]) || capHit) {
      if (bust[0] != bust[1] && !(reach[0] || reach[1])) {
        winner = bust[0] ? 1 : 0;
      } else {
        winner = scores[0] == scores[1] ? 2 : (scores[0] > scores[1] ? 0 : 1);
      }
      phase = 'over';
      host.log(winner == 2 ? '比赛结束：平局' : '比赛结束：${winner == 0 ? '南北' : '东西'}队获胜');
      return;
    }
    phase = 'handEnd';
    ready = List.filled(4, false);
  }

  static String _signed(int n) => n >= 0 ? '+$n' : '$n';

  @override
  Map<String, dynamic> view(int seat) => {
        'game': 'spades',
        'phase': phase,
        'handNo': handNo,
        'dealer': dealer,
        'target': target,
        'cap': cap,
        'hand': seat >= 0 && looked[seat] ? hands[seat] : <String>[],
        'hidden': seat >= 0 && !looked[seat],
        'canBlind': seat >= 0 && phase == 'bid' && seat == turn && canBlind(seat),
        'counts': [for (final h in hands) h.length],
        'bids': bids,
        'blind': blind,
        'turn': turn,
        'trick': trick,
        'lastTrick': lastTrick,
        'lastWinner': lastWinner,
        'trickNo': trickNo,
        'broken': broken,
        'won': won,
        'scores': scores,
        'bags': bags,
        'history': history,
        'legal': seat >= 0 ? legal(seat) : <String>[],
        'played': played,
        'result': phase == 'handEnd' || phase == 'over' ? result : null,
        'ready': phase == 'handEnd' ? ready : null,
        'winner': winner,
        'over': isOver,
      };

  @override
  Map<String, dynamic>? bot(int seat) {
    switch (phase) {
      case 'bid':
        if (seat != turn) return null;
        if (!looked[seat]) return {'type': 'look'};
        final v = view(seat);
        var n = spadesBotBid(hands[seat], [for (final b in v['bids'] as List) b as int?], seat);
        if (botLevel == 0 && rng.nextDouble() < 0.5) n = (n + rng.nextInt(5) - 2).clamp(1, 13);
        return {'type': 'bid', 'n': n};
      case 'play':
        if (seat != turn) return null;
        final lg = legal(seat);
        if (botLevel == 0 && rng.nextDouble() < 0.45) return {'type': 'play', 'card': lg[rng.nextInt(lg.length)]};
        if (botLevel == 2 && lg.length > 1) return {'type': 'play', 'card': _hardPlay(seat, lg)};
        return {'type': 'play', 'card': spadesBotPlay(view(seat), seat)};
      case 'handEnd':
        return ready[seat] ? null : {'type': 'continue'};
    }
    return null;
  }
}

extension _SpadesHard on Spades {
  /// 困难：按公开信息（已出牌、缺门）抽样另外三家的手牌，用普通策略把本局打完，
  /// 选使“本队本局得分 - 对方本局得分”平均最大的一张。
  String _hardPlay(int seat, List<String> lg) {
    final r = rng;
    final mine = hands[seat].toSet();
    final gone = <String>{...played, for (final t in trick) t['card'] as String};
    final unknown = [for (final c in trDeck()) if (!gone.contains(c) && !mine.contains(c)) c];
    final need = [for (var s = 0; s < 4; s++) s == seat ? 0 : hands[s].length];
    final voids = trVoids(playSeq);
    List<List<String>>? sample() {
      final d = trSampleDeal(r, unknown, need, voids) ?? trSampleDeal(r, unknown, need, List.generate(4, (_) => <String>{}));
      if (d == null) return null;
      d[seat] = List.of(hands[seat]);
      return d;
    }

    double rollout(List<List<String>> deal, String card) {
      final h = [for (final x in deal) List.of(x)];
      final tr = <(int, String)>[for (final t in trick) (t['seat'] as int, t['card'] as String)];
      final pl = List.of(played);
      final wn = List.of(won);
      var brk = broken;
      var tn = trickNo;
      var t = seat;
      var first = true;
      while (tn < 13) {
        String c;
        if (first) {
          c = card;
          first = false;
        } else {
          List<String> lgl;
          if (tr.isEmpty) {
            final ns = [for (final x in h[t]) if (trSuit(x) != 'S') x];
            lgl = !brk && ns.isNotEmpty ? ns : List.of(h[t]);
          } else {
            lgl = trFollow(h[t], trSuit(tr.first.$2));
          }
          c = lgl.length == 1
              ? lgl.first
              : spadesBotPlay({
                  'legal': lgl,
                  'bids': bids,
                  'won': wn,
                  'trick': [for (final x in tr) {'seat': x.$1, 'card': x.$2}],
                  'played': pl,
                  'hand': h[t],
                }, t);
        }
        h[t].remove(c);
        tr.add((t, c));
        if (trSuit(c) == 'S') brk = true;
        if (tr.length < 4) {
          t = (t + 1) % 4;
          continue;
        }
        final cards = [for (final x in tr) x.$2];
        final w = tr[trWinner(cards, 'S')].$1;
        wn[w]++;
        pl.addAll(cards);
        tr.clear();
        tn++;
        t = w;
      }
      final my = seat % 2;
      double team(int tm) =>
          spadesScoreTeam([bids[tm]!, bids[tm + 2]!], [wn[tm], wn[tm + 2]], [blind[tm], blind[tm + 2]], bags[tm]).delta.toDouble();
      return team(my) - team(1 - my);
    }

    return trPimc(r, lg, sample, rollout, samples: 16, maxMs: 700);
  }
}

class SpTeamScore {
  int delta = 0;
  int bags = 0;
  int newBags = 0;
  int bid = 0;
  int tricks = 0;
  bool made = false;
  bool penalty = false;
  final List<String> notes = [];
  Map<String, dynamic> toJson() =>
      {'delta': delta, 'bags': bags, 'newBags': newBags, 'bid': bid, 'tricks': tricks, 'made': made, 'penalty': penalty, 'notes': notes};
}

/// Score a partnership. Nil bidders' tricks do not count toward the partner's bid
/// but do count as bags. Nil ±100, blind nil ±200, 10 bags = -100.
SpTeamScore spadesScoreTeam(List<int> bids, List<int> won, List<bool> blind, int prevBags) {
  final r = SpTeamScore();
  var bid = 0, tricks = 0, extra = 0;
  for (var i = 0; i < 2; i++) {
    if (bids[i] == 0) {
      final v = blind[i] ? 200 : 100;
      if (won[i] == 0) {
        r.delta += v;
        r.notes.add('${blind[i] ? '盲零' : '零墩'}成功 +$v');
      } else {
        r.delta -= v;
        r.notes.add('${blind[i] ? '盲零' : '零墩'}失败 -$v');
      }
      extra += won[i];
    } else {
      bid += bids[i];
      tricks += won[i];
    }
  }
  r.bid = bid;
  r.tricks = tricks;
  var newBags = extra;
  if (bid > 0) {
    if (tricks >= bid) {
      r.made = true;
      r.delta += 10 * bid;
      newBags += tricks - bid;
      r.notes.add('完成 $bid 墩 +${10 * bid}');
    } else {
      r.delta -= 10 * bid;
      r.notes.add('未完成 $bid 墩 -${10 * bid}');
    }
  }
  r.delta += newBags;
  if (newBags > 0) r.notes.add('超墩(袋) $newBags 个 +$newBags');
  var bags = prevBags + newBags;
  while (bags >= 10) {
    bags -= 10;
    r.delta -= 100;
    r.penalty = true;
    r.notes.add('累计 10 袋 -100');
  }
  r.bags = bags;
  r.newBags = newBags;
  return r;
}

/// Count sure-ish tricks. [bids] = bids made so far (null = not yet).
int spadesBotBid(List<String> hand, List<int?> bids, int seat) {
  final sp = trOfSuit(hand, 'S')..sort((a, b) => trRank(b).compareTo(trRank(a)));
  var t = 0.0;
  // spades
  for (final c in sp) {
    final r = trRank(c);
    if (r == 12) t += 1;
    if (r == 11 && sp.length >= 2) t += 1;
    if (r == 10 && sp.length >= 3) t += 0.7;
  }
  if (sp.length > 3) t += sp.length - 3;
  // side suits
  for (final s in ['H', 'D', 'C']) {
    final c = trOfSuit(hand, s);
    final hasA = c.any((x) => x[0] == 'A'), hasK = c.any((x) => x[0] == 'K');
    if (hasA && c.length <= 6) t += 1;
    if (hasK && c.length >= 2 && c.length <= 5) t += hasA ? 0.9 : 0.6;
    if (c.any((x) => x[0] == 'Q') && c.length >= 3 && c.length <= 4 && (hasA || hasK)) t += 0.3;
    // ruffing value with spare spades
    final spare = sp.length - 3;
    if (spare > 0) {
      if (c.isEmpty) t += spare >= 2 ? 1.5 : 1;
      if (c.length == 1) t += 0.5;
    }
  }
  final n = t.round();
  // nil: very weak hands and partner has not bid nil
  final partnerBid = bids[(seat + 2) % 4];
  final highSp = sp.where((c) => trRank(c) >= 9).length;
  final aces = hand.where((c) => c[0] == 'A' || c[0] == 'K').length;
  if (t < 0.8 && highSp == 0 && sp.length <= 3 && aces == 0 && partnerBid != 0) return 0;
  return n < 1 ? 1 : (n > 13 ? 13 : n);
}

String spadesBotPlay(Map<String, dynamic> v, int seat) {
  final legal = trStrList(v['legal']);
  if (legal.length == 1) return legal.first;
  final bids = [for (final b in v['bids'] as List) b as int?];
  final won = (v['won'] as List).cast<int>();
  final trick = [for (final t in v['trick'] as List) (t['seat'] as int, '${t['card']}')];
  final played = trStrList(v['played']).toSet();
  final hand = trStrList(v['hand']);
  final partner = (seat + 2) % 4;
  final iNil = bids[seat] == 0;
  final partnerNil = bids[partner] == 0;
  var teamBid = 0, teamWon = 0;
  for (final s in [seat, partner]) {
    if (bids[s] != 0) {
      teamBid += bids[s]!;
      teamWon += won[s];
    }
  }
  final needMore = teamBid > teamWon;
  final gone = <String>{...played, for (final t in trick) t.$2, ...hand};
  bool sure(String c) => trIsTop(c, gone.difference({c}));
  final sorted = List.of(legal)..sort((a, b) => _pw(a).compareTo(_pw(b)));

  if (trick.isEmpty) {
    if (iNil) return sorted.first;
    if (needMore) {
      final winners = [for (final c in legal) if (sure(c)) c];
      if (winners.isNotEmpty) {
        final ns = winners.where((c) => trSuit(c) != 'S').toList();
        return ns.isNotEmpty ? ns.first : winners.first;
      }
    }
    // lead low from longest non-spade suit
    final by = <String, List<String>>{};
    for (final c in legal) {
      by.putIfAbsent(trSuit(c), () => []).add(c);
    }
    String? suit;
    for (final e in by.entries) {
      if (e.key == 'S' && by.length > 1) continue;
      if (suit == null || e.value.length > by[suit]!.length) suit = e.key;
    }
    return trLowest(by[suit]!)!;
  }
  final lead = trSuit(trick.first.$2);
  final cards = [for (final t in trick) t.$2];
  final wi = trWinner(cards, 'S');
  final winCard = cards[wi];
  final winSeat = trick[wi].$1;
  final last = trick.length == 3;
  final beaters = [for (final c in sorted) if (trBeats(c, winCard, lead, 'S')) c];
  final losers = [for (final c in sorted) if (!trBeats(c, winCard, lead, 'S')) c];

  if (iNil) {
    if (losers.isNotEmpty) return losers.last; // highest card that still loses
    return sorted.first;
  }
  if (partnerNil && winSeat == partner) {
    // cover partner
    if (beaters.isNotEmpty) return beaters.first;
    return sorted.first;
  }
  final partnerWinning = winSeat == partner;
  if (partnerWinning && (last || sure(winCard))) {
    return losers.isNotEmpty ? losers.first : sorted.first;
  }
  if (!needMore) {
    // avoid bags: play highest loser
    if (losers.isNotEmpty) return losers.last;
    return beaters.first;
  }
  if (beaters.isNotEmpty) {
    if (last) return beaters.first;
    for (final b in beaters) {
      if (sure(b)) return b;
    }
    // second hand low, third hand high
    if (trick.length == 1 && trSuit(beaters.first) == lead) return losers.isNotEmpty ? losers.first : beaters.first;
    return trSuit(beaters.first) == 'S' && trSuit(winCard) != 'S' ? beaters.first : beaters.last;
  }
  return losers.first;
}

int _pw(String c) => trRank(c) + (trSuit(c) == 'S' ? 100 : 0);
