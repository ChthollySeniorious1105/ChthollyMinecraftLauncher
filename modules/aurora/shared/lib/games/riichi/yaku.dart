/// Hand decomposition, yaku and fu evaluation for riichi mahjong.
library;

import 'tiles.dart';

/// A finished group used for evaluation.
class Group {
  /// 0 = sequence (kind = lowest tile), 1 = triplet, 2 = kan.
  final int type;
  final int kind;

  /// Open (called) — also true for a triplet completed by ron (minko).
  final bool open;
  const Group(this.type, this.kind, this.open);
  bool get isSeq => type == 0;
  bool get isTrip => type >= 1;
  bool get isKan => type == 2;
  bool get hasYaochu => isSeq ? (kind % 9 == 0 || kind % 9 == 6) : isYaochu(kind);
  bool get allTerminalOrHonor => !isSeq && isYaochu(kind);
}

/// Everything about a finished hand except the concrete tile ids.
class WinContext {
  /// Concealed counts including the winning tile (wildcard already substituted).
  final List<int> counts;
  final int winKind;

  /// Declared melds (chi/pon/kan incl. ankan).
  final List<Group> melds;
  final bool tsumo;
  final bool riichi;
  final bool doubleRiichi;
  final bool ippatsu;
  final bool rinshan;
  final bool chankan;
  final bool haitei;
  final bool houtei;
  final bool tenhou;
  final bool chiihou;
  final int seatWind; // kind 27..30
  final int roundWind; // kind 27..30
  final bool kuitan;
  final int dora;
  final int ura;
  final int aka;
  final int kita;

  const WinContext({
    required this.counts,
    required this.winKind,
    this.melds = const [],
    this.tsumo = false,
    this.riichi = false,
    this.doubleRiichi = false,
    this.ippatsu = false,
    this.rinshan = false,
    this.chankan = false,
    this.haitei = false,
    this.houtei = false,
    this.tenhou = false,
    this.chiihou = false,
    this.seatWind = kEast,
    this.roundWind = kEast,
    this.kuitan = true,
    this.dora = 0,
    this.ura = 0,
    this.aka = 0,
    this.kita = 0,
  });

  bool get menzen => melds.every((m) => !m.open);
}

class YakuItem {
  final String name;
  final int han; // for yakuman: multiples of yakuman (1 or 2)
  const YakuItem(this.name, this.han);
  Map<String, dynamic> toJson() => {'name': name, 'han': han};
}

/// Evaluated value of a winning hand.
class HandValue {
  final List<YakuItem> yaku; // yaku (+ dora items when not yakuman)
  final int han;
  final int fu;
  final int yakuman; // 0 = not yakuman; else multiplier
  const HandValue(this.yaku, this.han, this.fu, this.yakuman);

  /// Base points (before multipliers).
  int get basePoints {
    if (yakuman > 0) return 8000 * yakuman;
    if (han >= 13) return 8000;
    if (han >= 11) return 6000;
    if (han >= 8) return 4000;
    if (han >= 6) return 3000;
    if (han >= 5) return 2000;
    final b = fu * (1 << (han + 2));
    return b > 2000 ? 2000 : b;
  }

  String get limitName {
    if (yakuman > 0) return yakuman >= 2 ? '$yakuman倍役满' : '役满';
    if (han >= 13) return '累计役满';
    if (han >= 11) return '三倍满';
    if (han >= 8) return '倍满';
    if (han >= 6) return '跳满';
    if (basePoints >= 2000) return '满贯';
    return '';
  }
}

/// Enumerate standard decompositions of [c] into one pair + [need] groups.
/// Each result: first element is the pair kind (as Group(1, pairKind, false) with
/// type = -1 marker avoided: we return (pair, groups)).
List<(int, List<Group>)> decompose(List<int> c, int need) {
  final out = <(int, List<Group>)>[];
  final a = List<int>.of(c);
  final groups = <Group>[];
  void rec(int pair) {
    var i = 0;
    while (i < 34 && a[i] == 0) {
      i++;
    }
    if (i == 34) {
      if (groups.length == need) out.add((pair, List.of(groups)));
      return;
    }
    if (groups.length >= need) return;
    if (a[i] >= 3) {
      a[i] -= 3;
      groups.add(Group(1, i, false));
      rec(pair);
      groups.removeLast();
      a[i] += 3;
    }
    if (i < 27 && i % 9 <= 6 && a[i + 1] > 0 && a[i + 2] > 0) {
      a[i]--;
      a[i + 1]--;
      a[i + 2]--;
      groups.add(Group(0, i, false));
      rec(pair);
      groups.removeLast();
      a[i]++;
      a[i + 1]++;
      a[i + 2]++;
    }
  }

  for (var p = 0; p < 34; p++) {
    if (a[p] >= 2) {
      a[p] -= 2;
      rec(p);
      a[p] += 2;
    }
  }
  return out;
}

bool _isKokushi(List<int> c) {
  var total = 0, pair = 0;
  for (var k = 0; k < 34; k++) {
    total += c[k];
  }
  if (total != 14) return false;
  for (final k in yaochuKinds) {
    if (c[k] == 0) return false;
    if (c[k] == 2) pair++;
  }
  return pair == 1;
}

bool _isChiitoi(List<int> c) {
  var pairs = 0;
  for (var k = 0; k < 34; k++) {
    if (c[k] == 2) {
      pairs++;
    } else if (c[k] != 0) {
      return false;
    }
  }
  return pairs == 7;
}

int _yakuhaiValue(WinContext x, int k) {
  var v = 0;
  if (isDragon(k)) v++;
  if (k == x.seatWind) v++;
  if (k == x.roundWind) v++;
  return v;
}

/// Situational yaku shared by every shape (not yakuman).
void _situational(WinContext x, List<YakuItem> y) {
  if (x.doubleRiichi) {
    y.add(const YakuItem('双立直', 2));
  } else if (x.riichi) {
    y.add(const YakuItem('立直', 1));
  }
  if (x.ippatsu && (x.riichi || x.doubleRiichi)) y.add(const YakuItem('一发', 1));
  if (x.tsumo && x.menzen) y.add(const YakuItem('门前清自摸和', 1));
  if (x.rinshan) y.add(const YakuItem('岭上开花', 1));
  if (x.chankan) y.add(const YakuItem('抢杠', 1));
  if (x.haitei && x.tsumo && !x.rinshan) y.add(const YakuItem('海底捞月', 1));
  if (x.houtei && !x.tsumo) y.add(const YakuItem('河底捞鱼', 1));
}

List<YakuItem> _situationalYakuman(WinContext x) => [
      if (x.tenhou) const YakuItem('天和', 1),
      if (x.chiihou) const YakuItem('地和', 1),
    ];

/// All kinds in the whole hand (concealed + melds) as counts.
List<int> _allCounts(WinContext x) {
  final c = List<int>.of(x.counts);
  for (final m in x.melds) {
    if (m.isSeq) {
      c[m.kind]++;
      c[m.kind + 1]++;
      c[m.kind + 2]++;
    } else {
      c[m.kind] += 3; // kan's 4th tile irrelevant for colour/terminal checks
    }
  }
  return c;
}

void _colourYaku(WinContext x, List<int> all, List<YakuItem> y, bool closed) {
  final suits = <int>{};
  var honors = false;
  for (var k = 0; k < 34; k++) {
    if (all[k] == 0) continue;
    if (k >= 27) {
      honors = true;
    } else {
      suits.add(k ~/ 9);
    }
  }
  if (suits.length == 1) {
    if (honors) {
      y.add(YakuItem('混一色', closed ? 3 : 2));
    } else {
      y.add(YakuItem('清一色', closed ? 6 : 5));
    }
  }
}

bool _allSimple(List<int> all) {
  for (var k = 0; k < 34; k++) {
    if (all[k] > 0 && isYaochu(k)) return false;
  }
  return true;
}

bool _allYaochu(List<int> all) {
  for (var k = 0; k < 34; k++) {
    if (all[k] > 0 && !isYaochu(k)) return false;
  }
  return true;
}

List<YakuItem> _shapeYakuman(WinContext x, List<int> all, {int pair = -1, List<Group>? groups, bool tanki = false}) {
  final y = <YakuItem>[];
  var honorsOnly = true, greenOnly = true, termOnly = true;
  const greens = {19, 20, 21, 23, 25, kHatsu};
  for (var k = 0; k < 34; k++) {
    if (all[k] == 0) continue;
    if (k < 27) honorsOnly = false;
    if (!greens.contains(k)) greenOnly = false;
    if (!isTerminal(k)) termOnly = false;
  }
  if (honorsOnly) y.add(const YakuItem('字一色', 1));
  if (greenOnly) y.add(const YakuItem('绿一色', 1));
  if (termOnly) y.add(const YakuItem('清老头', 1));
  if (groups != null) {
    final trips = [for (final g in groups) if (g.isTrip) g.kind];
    final dragons = trips.where(isDragon).length;
    if (dragons == 3) y.add(const YakuItem('大三元', 1));
    final winds = trips.where(isWind).length;
    if (winds == 4) {
      y.add(const YakuItem('大四喜', 2));
    } else if (winds == 3 && isWind(pair)) {
      y.add(const YakuItem('小四喜', 1));
    }
    final ankou = groups.where((g) => g.isTrip && !g.open).length;
    if (ankou == 4) {
      y.add(tanki ? const YakuItem('四暗刻单骑', 2) : const YakuItem('四暗刻', 1));
    }
    if (groups.where((g) => g.isKan).length == 4) y.add(const YakuItem('四杠子', 1));
    // chuuren
    if (x.melds.isEmpty) {
      final c = x.counts;
      final s = x.winKind < 27 ? x.winKind ~/ 9 : -1;
      if (s >= 0) {
        var ok = true;
        for (var k = 0; k < 34; k++) {
          if (c[k] > 0 && (k >= 27 || k ~/ 9 != s)) ok = false;
        }
        if (ok) {
          const need = [3, 1, 1, 1, 1, 1, 1, 1, 3];
          for (var i = 0; i < 9; i++) {
            if (c[s * 9 + i] < need[i]) ok = false;
          }
          if (ok) {
            final before = [for (var i = 0; i < 9; i++) c[s * 9 + i] - (s * 9 + i == x.winKind ? 1 : 0)];
            var junsei = true;
            for (var i = 0; i < 9; i++) {
              if (before[i] != need[i]) junsei = false;
            }
            y.add(junsei ? const YakuItem('纯正九莲宝灯', 2) : const YakuItem('九莲宝灯', 1));
          }
        }
      }
    }
  }
  return y;
}

HandValue _finish(WinContext x, List<YakuItem> yaku, int fu) {
  var han = 0;
  for (final y in yaku) {
    han += y.han;
  }
  final items = List<YakuItem>.of(yaku);
  if (x.dora > 0) items.add(YakuItem('宝牌', x.dora));
  if (x.aka > 0) items.add(YakuItem('赤宝牌', x.aka));
  if (x.kita > 0) items.add(YakuItem('拔北宝牌', x.kita));
  if ((x.riichi || x.doubleRiichi) && x.ura > 0) items.add(YakuItem('里宝牌', x.ura));
  han += x.dora + x.aka + x.kita + ((x.riichi || x.doubleRiichi) ? x.ura : 0);
  return HandValue(items, han, fu, 0);
}

int compareValue(HandValue a, HandValue b) {
  if (a.basePoints != b.basePoints) return a.basePoints - b.basePoints;
  if (a.han != b.han) return a.han - b.han;
  return a.fu - b.fu;
}

/// Evaluate a complete hand. Returns null when the shape is not a win or it has
/// no yaku (dora alone is not enough).
HandValue? evaluateHand(WinContext x) {
  final c = x.counts;
  final all = _allCounts(x);
  final closed = x.menzen;
  HandValue? best;
  void consider(HandValue? v) {
    if (v == null) return;
    if (best == null || compareValue(v, best!) > 0) best = v;
  }

  // Kokushi
  if (x.melds.isEmpty && _isKokushi(c)) {
    final y = _situationalYakuman(x);
    y.add(c[x.winKind] == 2 ? const YakuItem('国士无双十三面', 2) : const YakuItem('国士无双', 1));
    return HandValue(y, 0, 0, y.fold(0, (s, e) => s + e.han));
  }

  // Standard shapes
  final need = 4 - x.melds.length;
  for (final (pair, groups) in decompose(c, need)) {
    // Choose where the winning tile sits.
    final placements = <int>[]; // -1 = pair (tanki), else group index
    if (pair == x.winKind) placements.add(-1);
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      if (g.isSeq ? (x.winKind >= g.kind && x.winKind <= g.kind + 2 && x.winKind < 27 && x.winKind ~/ 9 == g.kind ~/ 9) : g.kind == x.winKind) {
        if (!placements.contains(i) &&
            !placements.any((p) => p >= 0 && groups[p].type == g.type && groups[p].kind == g.kind)) {
          placements.add(i);
        }
      }
    }
    for (final pl in placements) {
      final gs = <Group>[];
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        // Ron completing a triplet makes it open (minko).
        gs.add(i == pl && g.isTrip && !x.tsumo ? Group(1, g.kind, true) : g);
      }
      gs.addAll(x.melds);
      // wait type: 0 ryanmen, 1 kanchan, 2 penchan, 3 tanki, 4 shanpon
      int wait;
      if (pl == -1) {
        wait = 3;
      } else {
        final g = groups[pl];
        if (g.isTrip) {
          wait = 4;
        } else if (x.winKind == g.kind + 1) {
          wait = 1;
        } else if ((x.winKind == g.kind + 2 && g.kind % 9 == 0) || (x.winKind == g.kind && g.kind % 9 == 6)) {
          wait = 2;
        } else {
          wait = 0;
        }
      }
      consider(_evalStandard(x, all, closed, pair, gs, wait));
    }
  }

  // Chiitoitsu
  if (x.melds.isEmpty && _isChiitoi(c)) {
    final ym = [..._situationalYakuman(x), ..._shapeYakuman(x, all)];
    if (ym.isNotEmpty) {
      consider(HandValue(ym, 0, 0, ym.fold(0, (s, e) => s + e.han)));
    } else {
      final y = <YakuItem>[];
      _situational(x, y);
      y.add(const YakuItem('七对子', 2));
      if (_allSimple(all) && (closed || x.kuitan)) y.add(const YakuItem('断幺九', 1));
      if (_allYaochu(all)) y.add(const YakuItem('混老头', 2));
      _colourYaku(x, all, y, true);
      consider(_finish(x, y, 25));
    }
  }
  return best;
}

HandValue? _evalStandard(WinContext x, List<int> all, bool closed, int pair, List<Group> gs, int wait) {
  // Yakuman first
  final ym = [
    ..._situationalYakuman(x),
    ..._shapeYakuman(x, all, pair: pair, groups: gs, tanki: wait == 3),
  ];
  if (ym.isNotEmpty) return HandValue(ym, 0, 0, ym.fold(0, (s, e) => s + e.han));

  final y = <YakuItem>[];
  _situational(x, y);
  final seqs = [for (final g in gs) if (g.isSeq) g.kind];
  final trips = [for (final g in gs) if (g.isTrip) g];
  final pairYakuhai = _yakuhaiValue(x, pair);
  final pinfu = closed && seqs.length == 4 && pairYakuhai == 0 && wait == 0;
  if (pinfu) y.add(const YakuItem('平和', 1));
  if (_allSimple(all) && (closed || x.kuitan)) y.add(const YakuItem('断幺九', 1));
  if (closed) {
    // peikou
    final cnt = <int, int>{};
    for (final s in seqs) {
      cnt[s] = (cnt[s] ?? 0) + 1;
    }
    var pk = 0;
    for (final v in cnt.values) {
      pk += v ~/ 2;
    }
    if (pk >= 2) {
      y.add(const YakuItem('二杯口', 3));
    } else if (pk == 1) {
      y.add(const YakuItem('一杯口', 1));
    }
  }
  // yakuhai
  for (final t in trips) {
    if (t.kind == kHaku) y.add(const YakuItem('役牌 白', 1));
    if (t.kind == kHatsu) y.add(const YakuItem('役牌 发', 1));
    if (t.kind == kChun) y.add(const YakuItem('役牌 中', 1));
    if (t.kind == x.seatWind) y.add(YakuItem('自风 ${windNames[t.kind - 27]}', 1));
    if (t.kind == x.roundWind) y.add(YakuItem('场风 ${windNames[t.kind - 27]}', 1));
  }
  // sanshoku doujun / ittsu
  final seqSet = seqs.toSet();
  for (var n = 0; n < 7; n++) {
    if (seqSet.contains(n) && seqSet.contains(n + 9) && seqSet.contains(n + 18)) {
      y.add(YakuItem('三色同顺', closed ? 2 : 1));
      break;
    }
  }
  for (var s = 0; s < 3; s++) {
    if (seqSet.contains(s * 9) && seqSet.contains(s * 9 + 3) && seqSet.contains(s * 9 + 6)) {
      y.add(YakuItem('一气通贯', closed ? 2 : 1));
    }
  }
  // chanta / junchan / honroutou
  final allGroupsYaochu = gs.every((g) => g.hasYaochu) && isYaochu(pair);
  if (allGroupsYaochu && seqs.isNotEmpty) {
    final hasHonor = isHonor(pair) || trips.any((t) => isHonor(t.kind));
    y.add(hasHonor ? YakuItem('混全带幺九', closed ? 2 : 1) : YakuItem('纯全带幺九', closed ? 3 : 2));
  }
  if (_allYaochu(all)) y.add(const YakuItem('混老头', 2));
  if (trips.length == 4) y.add(const YakuItem('对对和', 2));
  final ankou = trips.where((t) => !t.open).length;
  if (ankou == 3) y.add(const YakuItem('三暗刻', 2));
  if (gs.where((g) => g.isKan).length == 3) y.add(const YakuItem('三杠子', 2));
  for (var n = 0; n < 9; n++) {
    if (trips.any((t) => t.kind == n) && trips.any((t) => t.kind == n + 9) && trips.any((t) => t.kind == n + 18)) {
      y.add(const YakuItem('三色同刻', 2));
    }
  }
  if (isDragon(pair) && trips.where((t) => isDragon(t.kind)).length == 2) y.add(const YakuItem('小三元', 2));
  _colourYaku(x, all, y, closed);
  if (y.isEmpty) return null;

  // Fu
  int fu;
  if (pinfu) {
    fu = x.tsumo ? 20 : 30;
  } else {
    fu = 20;
    if (closed && !x.tsumo) fu += 10;
    if (x.tsumo) fu += 2;
    if (wait == 1 || wait == 2 || wait == 3) fu += 2;
    fu += pairYakuhai * 2;
    for (final t in trips) {
      var f = 2;
      if (isYaochu(t.kind)) f *= 2;
      if (!t.open) f *= 2;
      if (t.isKan) f *= 4;
      fu += f;
    }
    fu = (fu + 9) ~/ 10 * 10;
    if (fu == 20) fu = 30; // open pinfu shape
  }
  return _finish(x, y, fu);
}
