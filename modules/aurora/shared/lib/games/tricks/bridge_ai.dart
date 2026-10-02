import 'bridge_rules.dart';
import 'cards.dart';

/// Bridge bot. Uses ONLY the seat's own view: own hand, public auction,
/// dummy's hand after the opening lead, cards played so far.

Map<String, int> _lens(List<String> h) => {for (final s in 'CDHS'.split('')) s: trOfSuit(h, s).length};

bool _balanced(Map<String, int> l) {
  final v = l.values.toList()..sort();
  return v[0] >= 2 && v[1] >= 3;
}

class _Info {
  int minPts = 0;
  final Map<String, int> len = {'C': 0, 'D': 0, 'H': 0, 'S': 0};
  bool bid = false;
  bool balanced = false;
}

/// What the auction tells us about a seat's hand (very rough).
_Info _describe(List<BrCall> calls, int seat) {
  final inf = _Info();
  var opened = false; // someone had bid before this seat's first bid
  var first = true;
  for (var i = 0; i < calls.length; i++) {
    final c = calls[i];
    final prevBid = calls.take(i).any((x) => brIsBid(x.call));
    if (c.seat != seat) continue;
    if (!brIsBid(c.call)) {
      if (c.call == 'X' && first) inf.minPts = inf.minPts < 12 ? 12 : inf.minPts;
      continue;
    }
    final lvl = int.parse(c.call[0]);
    final st = c.call[1];
    final partnerBids = calls.take(i).where((x) => x.seat == (seat + 2) % 4 && brIsBid(x.call)).toList();
    if (first) {
      opened = !prevBid;
      if (opened) {
        if (c.call == '1N') {
          inf.minPts = 15;
          inf.balanced = true;
        } else if (c.call == '2N') {
          inf.minPts = 20;
          inf.balanced = true;
        } else if (c.call == '2C') {
          inf.minPts = 22;
        } else {
          inf.minPts = 12;
        }
      } else if (partnerBids.isNotEmpty) {
        final raise = partnerBids.any((x) => x.call[1] == st);
        inf.minPts = raise ? (lvl <= 2 ? 6 : (lvl == 3 ? 10 : 12)) : (st == 'N' ? (lvl == 1 ? 6 : 12) : (lvl == 1 ? 6 : 10));
        if (lvl >= 4 && st != 'N' && !raise) inf.minPts = 12;
        if (st == 'N' && lvl == 3) inf.minPts = 10;
        if (c.call == '2D' && partnerBids.length == 1 && partnerBids.first.call == '2C') inf.minPts = 0;
      } else {
        inf.minPts = st == 'N' ? 15 : 9; // overcall
      }
      first = false;
    }
    if (st != 'N') {
      final partnerNamed = partnerBids.any((x) => x.call[1] == st);
      final base = partnerNamed ? 3 : (opened && inf.len[st] == 0 ? (st == 'H' || st == 'S' || c.call == '2C' ? 5 : 3) : 4);
      if (c.call == '2C' && opened && inf.minPts == 22) continue;
      if (c.call == '2D' && partnerBids.any((x) => x.call == '2C') && partnerBids.length == 1) continue;
      inf.len[st] = inf.len[st]! == 0 ? base : inf.len[st]! + 1;
      if (inf.len[st]! > 6) inf.len[st] = 6;
    }
    inf.bid = true;
  }
  return inf;
}

String brBotCall(Map<String, dynamic> v, int seat) {
  final hand = trStrList(v['hand']);
  final calls = [for (final c in v['calls'] as List) BrCall(c['seat'] as int, '${c['call']}')];
  final legal = trStrList(v['legalCalls']);
  if (legal.isEmpty) return 'P';
  final a = BrAuction(v['dealer'] as int, calls);
  String ok(String c) => legal.contains(c) ? c : 'P';

  final hcp = brHcp(hand);
  final l = _lens(hand);
  final bal = _balanced(l);
  final dist = l.values.fold<int>(0, (s, n) => s + (n > 4 ? n - 4 : 0));
  final pts = hcp + dist;
  final partner = (seat + 2) % 4;
  final me = _describe(calls, seat);
  final pa = _describe(calls, partner);
  final lho = _describe(calls, (seat + 1) % 4), rho = _describe(calls, (seat + 3) % 4);
  final oppBid = lho.bid || rho.bid;
  final lb = a.lastBid;
  final ourContract = lb != null && brSide(lb.seat) == brSide(seat);

  String? cheapest(String strain, {int maxLevel = 7}) {
    final from = lb == null ? 0 : brBidRank(lb.call) + 1;
    for (var r = from; r < 35; r++) {
      final b = brBidFromRank(r);
      if (b[1] == strain) return int.parse(b[0]) <= maxLevel ? b : null;
    }
    return null;
  }

  String longest({bool majorsFirst = true}) {
    var best = 'C';
    for (final s in ['C', 'D', 'H', 'S']) {
      if (l[s]! > l[best]! || (l[s]! == l[best]! && majorsFirst)) best = s;
    }
    return best;
  }

  // ---------------- opening ----------------
  if (!me.bid && !pa.bid && !oppBid) {
    if (bal && hcp >= 15 && hcp <= 17) return ok('1N');
    if (bal && hcp >= 20 && hcp <= 21) return ok('2N');
    if (hcp >= 22) return ok('2C');
    if (hcp >= 12 || (hcp >= 11 && pts >= 13)) {
      if (l['S']! >= 5 && l['S']! >= l['H']!) return ok('1S');
      if (l['H']! >= 5) return ok('1H');
      if (l['D']! >= 4 && l['D']! >= l['C']!) return ok('1D');
      return ok('1C');
    }
    if (hcp >= 5 && hcp <= 10) {
      for (final s in ['S', 'H', 'D']) {
        if (l[s]! >= 6 && trOfSuit(hand, s).where((c) => 'AKQ'.contains(c[0])).length >= 2) return ok('2$s');
      }
    }
    return 'P';
  }

  // ---------------- competitive: opponents bid first, we have not ----------------
  if (!me.bid && !pa.bid && oppBid) {
    final theirs = lb!.call[1];
    if (ourContract) return 'P';
    if (bal && hcp >= 15 && hcp <= 18 && theirs != 'N' && l[theirs]! >= 2) {
      final nt = cheapest('N', maxLevel: 1);
      if (nt != null) return ok(nt);
    }
    for (final s in ['S', 'H', 'D', 'C']) {
      if (s == theirs || l[s]! < 5) continue;
      final b = cheapest(s, maxLevel: 2);
      if (b == null) continue;
      final need = b[0] == '1' ? 8 : 11;
      if (hcp >= need && hcp <= 17) return ok(b);
    }
    if (hcp >= 13 && theirs != 'N' && l[theirs]! <= 1 && legal.contains('X')) return 'X';
    if (hcp >= 17 && legal.contains('X')) return 'X';
    return 'P';
  }

  // ---------------- partner opened / bid, our side constructive ----------------
  final combined = pts + pa.minPts;
  // choose strain
  String strain = 'N';
  var bestFit = 0;
  for (final s in ['S', 'H', 'D', 'C']) {
    final f = l[s]! + pa.len[s]!;
    if (f >= 8 && (f > bestFit || (f == bestFit && (s == 'H' || s == 'S')))) {
      if (bestFit > 0 && (strain == 'H' || strain == 'S') && !(s == 'H' || s == 'S')) continue;
      strain = s;
      bestFit = f;
    }
  }
  if (!pa.bid) {
    // I bid before, partner silent: rebid my suit if long, otherwise pass
    if (ourContract || lb == null) return 'P';
    final s = longest();
    if (l[s]! >= 6 && hcp >= 12) {
      final b = cheapest(s, maxLevel: 3);
      if (b != null) return ok(b);
    }
    return 'P';
  }

  // Partner's special opening responses
  final paFirst = calls.firstWhere((c) => c.seat == partner && brIsBid(c.call));
  final partnerOpened = !calls.take(calls.indexOf(paFirst)).any((c) => brIsBid(c.call));
  if (!me.bid && partnerOpened && paFirst.call == '2C' && lb!.call == '2C') return ok('2D');
  if (!me.bid) {
    // first response
    if (hcp < 6 && !(paFirst.call == '2C')) {
      return 'P';
    }
    if (paFirst.call == '1N' || paFirst.call == '2N') {
      final add = paFirst.call == '1N' ? 16 : 21;
      final t = hcp + add;
      for (final s in ['S', 'H']) {
        if (l[s]! >= 6 && t >= 25) return ok(cheapest(s, maxLevel: 4) ?? 'P');
      }
      if (t >= 33) return ok(cheapest('N', maxLevel: 6) ?? 'P');
      if (t >= 25) return ok(cheapest('N', maxLevel: 3) ?? 'P');
      if (t >= 23 && paFirst.call == '1N') return ok(cheapest('N', maxLevel: 2) ?? 'P');
      for (final s in ['S', 'H', 'D']) {
        if (l[s]! >= 6 && paFirst.call == '1N') return ok(cheapest(s, maxLevel: 2) ?? 'P');
      }
      return 'P';
    }
    final ps = paFirst.call[1];
    if (ps != 'N' && l[ps]! >= (ps == 'H' || ps == 'S' ? 3 : 5)) {
      final lvl = pts >= 13 ? ((ps == 'H' || ps == 'S') ? 4 : 3) : (pts >= 10 ? 3 : 2);
      final target = '$lvl$ps';
      if (legal.contains(target)) return target;
      return ok(cheapest(ps, maxLevel: lvl) ?? 'P');
    }
    for (final s in ['S', 'H', 'D', 'C']) {
      if (s == ps || l[s]! < 4) continue;
      final b = cheapest(s, maxLevel: 2);
      if (b == null) continue;
      if (b[0] == '1' || hcp >= 10) return ok(b);
    }
    if (hcp >= 13 && bal) return ok(cheapest('N', maxLevel: hcp >= 16 ? 3 : 2) ?? 'P');
    return ok(cheapest('N', maxLevel: hcp >= 10 ? 2 : 1) ?? 'P');
  }

  // ---------------- later rounds: place the contract ----------------
  int targetLevel(String st) {
    final c = strain == st ? combined + (bestFit >= 9 ? 1 : 0) : combined;
    if (c >= 37) return 7;
    if (c >= 33) return 6;
    if (c >= 26 && (st == 'C' || st == 'D')) return 5;
    if (c >= 25) return st == 'N' ? 3 : 4;
    if (c >= 22) return st == 'N' ? 2 : 3;
    return st == 'N' ? 1 : 2;
  }

  final tl = targetLevel(strain);
  if (lb != null) {
    final curLvl = int.parse(lb.call[0]);
    if (ourContract) {
      if (lb.call[1] == strain && curLvl >= tl) return 'P';
      if (curLvl >= tl && combined < 25) return 'P';
    } else {
      // opponents hold the contract
      final theirLvl = curLvl + 6;
      if (combined >= 23 && theirLvl >= 9 && legal.contains('X') && lb.call[1] != strain) return 'X';
      if (combined < 20) return 'P';
    }
  }
  final target = '$tl$strain';
  if (legal.contains(target)) return target;
  // can't reach target in chosen strain: try NT at game if strong, else pass
  if (combined >= 25 && strain != 'N' && targetLevel('N') >= 3) {
    final b = cheapest('N', maxLevel: 3);
    if (b != null && !ourContract) return ok(b);
  }
  return 'P';
}

// =====================================================================
// Card play
// =====================================================================

String brBotPlay(Map<String, dynamic> v, int seat) {
  final legal = trStrList(v['legal']);
  if (legal.length == 1) return legal.first;
  final c = v['contract'] as Map;
  final trump = '${c['strain']}' == 'N' ? null : '${c['strain']}';
  final declarer = v['declarer'] as int;
  final dummy = v['dummy'] as int;
  final player = v['turn'] as int; // whose card is being played (may be dummy)
  final playingDummy = player == dummy;
  final myHand = playingDummy ? trStrList(v['dummyHand']) : trStrList(v['hand']);
  final dummyHand = trStrList(v['dummyHand']);
  final isDecl = seat == declarer;
  final trick = [for (final t in v['trick'] as List) (t['seat'] as int, '${t['card']}')];
  final played = trStrList(v['played']).toSet();

  // cards whose location is known to be "ours" (not with the opponents)
  final known = <String>{...played, for (final t in trick) t.$2, ...myHand};
  if (isDecl) {
    known.addAll(trStrList(v['hand']));
    known.addAll(dummyHand);
  }
  // for defenders, dummy's cards are visible: they are not "outstanding" in the hidden hands,
  // but dummy may still beat us, so they only count as gone when already played.
  final gone = <String>{...played, for (final t in trick) t.$2};
  final oursTop = <String>{...known};

  bool sure(String card) => trIsTop(card, oursTop.difference({card}).union(gone));

  if (trick.isEmpty) return _lead(legal, myHand, trump, isDecl, played, known, sure, v, seat, player);

  final lead = trSuit(trick.first.$2);
  final cards = [for (final t in trick) t.$2];
  final wIdx = trWinner(cards, trump);
  final winCard = cards[wIdx];
  final winSeat = trick[wIdx].$1;
  final partnerWinning = brSide(winSeat) == brSide(player);
  final last = trick.length == 3;
  final following = trSuit(legal.first) == lead && legal.every((x) => trSuit(x) == lead);
  final beaters = [for (final x in legal) if (trBeats(x, winCard, lead, trump)) x]..sort((a, b) => _power(a, trump).compareTo(_power(b, trump)));

  // partner's card is safe if we're last, or it is the top card outstanding
  final partnerSafe = partnerWinning && (last || (trSuit(winCard) == lead && sure(winCard) && trump == null) || (trSuit(winCard) == lead && sure(winCard) && !_oppMayRuff(played, known, trump, lead)));

  if (following) {
    if (partnerSafe) return trLowest(legal)!;
    if (trick.length == 1) {
      // second hand low, unless we hold a sure winner and it's the last card we'd keep
      if (beaters.isNotEmpty && sure(beaters.last) && trSuit(winCard) == lead && trRank(beaters.last) >= 11) {
        // cover honours only with a sure winner
        if (trRank(winCard) >= 9) return beaters.last;
      }
      return trLowest(legal)!;
    }
    if (beaters.isEmpty) return trLowest(legal)!;
    if (last) return beaters.first;
    // third hand high (but the cheapest of equals): cheapest sure winner else highest
    for (final b in beaters) {
      if (sure(b)) return b;
    }
    return trHighest(beaters)!;
  }
  // void in led suit
  final myTrumps = trump == null ? <String>[] : trOfSuit(legal, trump);
  if (!partnerSafe && myTrumps.isNotEmpty) {
    final r = [for (final x in beaters) if (trSuit(x) == trump) x];
    if (r.isNotEmpty) return r.first;
  }
  return _discard(legal, trump);
}

int _power(String c, String? trump) => trRank(c) + (trump != null && trSuit(c) == trump ? 100 : 0);

bool _oppMayRuff(Set<String> played, Set<String> known, String? trump, String suit) {
  if (trump == null) return false;
  var ofSuit = 0;
  for (final c in known) {
    if (trSuit(c) == suit) ofSuit++;
  }
  return ofSuit >= 8; // few left -> someone may be void
}

String _discard(List<String> legal, String? trump) {
  final nonTrump = [for (final c in legal) if (trSuit(c) != trump) c];
  final pool = nonTrump.isEmpty ? legal : nonTrump;
  // discard lowest card from the longest weak suit
  final by = <String, List<String>>{};
  for (final c in pool) {
    by.putIfAbsent(trSuit(c), () => []).add(c);
  }
  String? best;
  var bestScore = -999;
  for (final e in by.entries) {
    final low = trLowest(e.value)!;
    final score = e.value.length * 2 - trRank(low);
    if (score > bestScore) {
      bestScore = score;
      best = low;
    }
  }
  return best ?? legal.first;
}

String _lead(List<String> legal, List<String> hand, String? trump, bool isDecl, Set<String> played, Set<String> known,
    bool Function(String) sure, Map<String, dynamic> v, int seat, int player) {
  if (isDecl && trump != null) {
    // draw trumps while opponents may hold some
    var ours = 0;
    for (final c in known) {
      if (trSuit(c) == trump) ours++;
    }
    final oppTrumps = 13 - ours;
    final t = trOfSuit(legal, trump);
    if (oppTrumps > 0 && t.isNotEmpty) {
      final top = trHighest(t)!;
      if (sure(top)) return top;
      if (t.length >= 3) return trLowest(t)!;
    }
  }
  // cash a sure winner in a side suit
  for (final c in legal) {
    if (trSuit(c) != trump && sure(c)) return c;
  }
  final by = <String, List<String>>{};
  for (final c in legal) {
    by.putIfAbsent(trSuit(c), () => []).add(c);
  }
  // top of a sequence (KQ, QJ ...) is a good lead
  for (final e in by.entries) {
    if (e.key == trump && !isDecl) continue;
    final s = List.of(e.value)..sort((a, b) => trRank(b).compareTo(trRank(a)));
    if (s.length >= 2 && trRank(s[0]) >= 10 && trRank(s[0]) - trRank(s[1]) == 1) return s[0];
  }
  // lead low (4th best) from the longest non-trump suit
  String? suit;
  for (final e in by.entries) {
    if (e.key == trump && by.length > 1) continue;
    if (suit == null || e.value.length > by[suit]!.length) suit = e.key;
  }
  final s = List.of(by[suit]!)..sort((a, b) => trRank(b).compareTo(trRank(a)));
  return s.length >= 4 ? s[3] : s.last;
}
