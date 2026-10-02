/// Contract-bridge rules: auction legality, declarer, scoring.
///
/// Calls: 'P' (pass), 'X' (double), 'XX' (redouble), or a bid '1C'..'7N'
/// (strain C D H S N). Seats 0..3 = 北 东 南 西, partners 0&2 (南北) and 1&3 (东西).
library;

const String brStrains = 'CDHSN';
const List<String> brSeatNames = ['北', '东', '南', '西'];

int brSide(int seat) => seat % 2;
String brSideName(int side) => side == 0 ? '南北' : '东西';

bool brIsBid(String call) => call.length == 2 && '1234567'.contains(call[0]) && brStrains.contains(call[1]);

/// 0..34 bid rank (1C = 0, 7N = 34).
int brBidRank(String bid) => (int.parse(bid[0]) - 1) * 5 + brStrains.indexOf(bid[1]);
String brBidFromRank(int r) => '${r ~/ 5 + 1}${brStrains[r % 5]}';

String brStrainSym(String s) => const {'C': '♣', 'D': '♦', 'H': '♥', 'S': '♠', 'N': 'NT'}[s] ?? s;

/// Human readable call, e.g. "1♠", "3NT", "不叫", "加倍", "再加倍".
String brCallName(String call) {
  if (call == 'P') return '不叫';
  if (call == 'X') return '加倍';
  if (call == 'XX') return '再加倍';
  return '${call[0]}${brStrainSym(call[1])}';
}

class BrCall {
  final int seat;
  final String call;
  const BrCall(this.seat, this.call);
  Map<String, dynamic> toJson() => {'seat': seat, 'call': call};
}

/// Auction state derived from the call list.
class BrAuction {
  final int dealer;
  final List<BrCall> calls;
  BrAuction(this.dealer, [List<BrCall>? calls]) : calls = calls ?? [];

  int get turn => (dealer + calls.length) % 4;

  /// Last bid (not pass/double) or null.
  BrCall? get lastBid {
    for (var i = calls.length - 1; i >= 0; i--) {
      if (brIsBid(calls[i].call)) return calls[i];
    }
    return null;
  }

  /// 0 = undoubled, 1 = doubled, 2 = redoubled (for the current last bid).
  int get doubled {
    var d = 0;
    for (var i = calls.length - 1; i >= 0; i--) {
      final c = calls[i].call;
      if (brIsBid(c)) break;
      if (c == 'X' && d == 0) d = 1;
      if (c == 'XX') d = 2;
    }
    return d;
  }

  /// Last call that is not a pass.
  BrCall? get lastAction {
    for (var i = calls.length - 1; i >= 0; i--) {
      if (calls[i].call != 'P') return calls[i];
    }
    return null;
  }

  bool get isOver {
    if (calls.length < 4) return false;
    if (lastBid == null) return true; // four passes
    return calls.length >= 4 &&
        calls[calls.length - 1].call == 'P' &&
        calls[calls.length - 2].call == 'P' &&
        calls[calls.length - 3].call == 'P';
  }

  bool get passedOut => isOver && lastBid == null;

  /// Null when legal, else a Chinese error message.
  String? illegal(int seat, String call) {
    if (isOver) return '叫牌已结束';
    if (seat != turn) return '还没轮到你叫牌';
    if (call == 'P') return null;
    final lb = lastBid;
    if (call == 'X') {
      final la = lastAction;
      if (la == null || !brIsBid(la.call)) return '现在不能加倍';
      if (brSide(la.seat) == brSide(seat)) return '不能对己方的叫品加倍';
      return null;
    }
    if (call == 'XX') {
      final la = lastAction;
      if (la == null || la.call != 'X') return '现在不能再加倍';
      if (brSide(la.seat) == brSide(seat)) return '只能对对方的加倍再加倍';
      return null;
    }
    if (!brIsBid(call)) return '无效的叫品';
    if (lb != null && brBidRank(call) <= brBidRank(lb.call)) return '叫品必须高于 ${brCallName(lb.call)}';
    return null;
  }

  List<String> legalCalls(int seat) {
    final out = <String>[];
    for (final c in ['P', 'X', 'XX']) {
      if (illegal(seat, c) == null) out.add(c);
    }
    final lb = lastBid;
    final from = lb == null ? 0 : brBidRank(lb.call) + 1;
    if (turn == seat && !isOver) {
      for (var r = from; r < 35; r++) {
        out.add(brBidFromRank(r));
      }
    }
    return out;
  }

  void add(int seat, String call) {
    final e = illegal(seat, call);
    if (e != null) throw ArgumentError(e);
    calls.add(BrCall(seat, call));
  }

  /// Declarer: first player of the contracting side to have named the final strain.
  int? get declarer {
    final lb = lastBid;
    if (lb == null) return null;
    final strain = lb.call[1];
    final side = brSide(lb.seat);
    for (final c in calls) {
      if (brIsBid(c.call) && c.call[1] == strain && brSide(c.seat) == side) return c.seat;
    }
    return lb.seat;
  }
}

class BrContract {
  final int level;
  final String strain;
  final int doubled; // 0 / 1 / 2
  final int declarer;
  const BrContract(this.level, this.strain, this.doubled, this.declarer);

  String get label => '$level${brStrainSym(strain)}${doubled == 1 ? ' X' : doubled == 2 ? ' XX' : ''}';
  String? get trump => strain == 'N' ? null : strain;
  Map<String, dynamic> toJson() => {'level': level, 'strain': strain, 'doubled': doubled, 'declarer': declarer, 'label': label};
}

/// Detailed score of one deal. All values are positive and belong either to the
/// declaring side ([below] + [declAbove]) or to the defenders ([defAbove]).
class BrScore {
  /// Contract trick points (count towards game in rubber bridge).
  int below = 0;
  int overtricks = 0;
  int slam = 0;
  int insult = 0;
  int undertricks = 0; // goes to defenders

  int get declAbove => overtricks + slam + insult;
  int get defAbove => undertricks;
  bool get made => undertricks == 0;

  /// Duplicate / Chicago total from the declaring side's point of view
  /// (adds the game / partscore bonus).
  int duplicateTotal(bool vul) {
    if (!made) return -undertricks;
    final bonus = below >= 100 ? (vul ? 500 : 300) : 50;
    return below + declAbove + bonus;
  }
}

int brTrickValue(String strain, int n) {
  if (n <= 0) return 0;
  if (strain == 'N') return 40 + 30 * (n - 1);
  if (strain == 'H' || strain == 'S') return 30 * n;
  return 20 * n;
}

/// Score a played contract. [tricks] = tricks taken by declarer (0..13).
BrScore brScore(BrContract c, bool vul, int tricks) {
  final s = BrScore();
  final need = c.level + 6;
  final mult = c.doubled == 0 ? 1 : (c.doubled == 1 ? 2 : 4);
  if (tricks >= need) {
    s.below = brTrickValue(c.strain, c.level) * mult;
    final over = tricks - need;
    if (c.doubled == 0) {
      s.overtricks = over * (c.strain == 'C' || c.strain == 'D' ? 20 : 30);
    } else {
      s.overtricks = over * (vul ? 200 : 100) * (c.doubled == 2 ? 2 : 1);
    }
    if (c.level == 6) s.slam = vul ? 750 : 500;
    if (c.level == 7) s.slam = vul ? 1500 : 1000;
    s.insult = c.doubled == 1 ? 50 : (c.doubled == 2 ? 100 : 0);
  } else {
    final down = need - tricks;
    if (c.doubled == 0) {
      s.undertricks = down * (vul ? 100 : 50);
    } else {
      var u = 0;
      for (var i = 1; i <= down; i++) {
        if (vul) {
          u += i == 1 ? 200 : 300;
        } else {
          u += i == 1 ? 100 : (i <= 3 ? 200 : 300);
        }
      }
      s.undertricks = u * (c.doubled == 2 ? 2 : 1);
    }
  }
  return s;
}

/// Rubber-bridge honours held in one hand (100 / 150), or 0.
/// [hands] are the original 13-card hands.
(int seat, int points) brHonours(List<List<String>> hands, String strain) {
  for (var s = 0; s < 4; s++) {
    final h = hands[s];
    if (strain == 'N') {
      if (h.where((c) => c[0] == 'A').length == 4) return (s, 150);
    } else {
      final n = h.where((c) => c[1] == strain && 'TJQKA'.contains(c[0])).length;
      if (n == 5) return (s, 150);
      if (n == 4) return (s, 100);
    }
  }
  return (-1, 0);
}

/// Chicago vulnerability for deal index 0..3 (dealer rotates N,E,S,W):
/// 1: none, 2 & 3: dealer's side, 4: both. Returns [nsVul, ewVul].
List<bool> brChicagoVul(int dealIndex, int dealer) {
  switch (dealIndex % 4) {
    case 0:
      return [false, false];
    case 3:
      return [true, true];
    default:
      return [brSide(dealer) == 0, brSide(dealer) == 1];
  }
}

/// High-card points (A4 K3 Q2 J1).
int brHcp(Iterable<String> hand) {
  var p = 0;
  for (final c in hand) {
    p += const {'A': 4, 'K': 3, 'Q': 2, 'J': 1}[c[0]] ?? 0;
  }
  return p;
}
