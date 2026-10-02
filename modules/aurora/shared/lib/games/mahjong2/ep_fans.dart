/// 二人麻将 (国标二人麻将风格) fan evaluation.
///
/// Tiles: 万子 36 + 字牌 28 (+ 8 花). A simplified 国标 fan table; see the
/// rules text in defs.dart for the list and the 不重复 (exclusion) rules used.
library;

import 'tiles.dart';

class EpCtx {
  final int winTile;
  final bool selfDrawn;
  final int seatWind; // 0 东 .. 3 北
  final int roundWind;
  final bool lastTile; // 妙手回春 / 海底捞月
  final bool kongDraw; // 杠上开花
  final bool robKong; // 抢杠和
  final bool lastCopy; // 和绝张
  final int flowers;
  final int waitCount; // number of distinct waits before winning (边坎钓 need 1)
  const EpCtx(this.winTile,
      {this.selfDrawn = false,
      this.seatWind = 0,
      this.roundWind = 0,
      this.lastTile = false,
      this.kongDraw = false,
      this.robKong = false,
      this.lastCopy = false,
      this.flowers = 0,
      this.waitCount = 1});
}

class EpResult {
  /// (name, fan each, count)
  final List<(String, int, int)> items;
  const EpResult(this.items);
  int get total => items.fold(0, (a, e) => a + e.$2 * e.$3);
  int get base => items.where((e) => e.$1 != '花牌').fold(0, (a, e) => a + e.$2 * e.$3);
  List<List<Object>> toJson() => [for (final (n, f, k) in items) [n, f, k]];
  String get label => [for (final (n, f, k) in items) '$n$f${k > 1 ? '×$k' : ''}'].join(' ');
}

class _Fans {
  final List<(String, int, int)> items = [];
  void add(String n, int f, [int k = 1]) {
    if (k > 0) items.add((n, f, k));
  }

  int get base => items.where((e) => e.$1 != '花牌').fold(0, (a, e) => a + e.$2 * e.$3);
}

bool _allOf(List<int> all, bool Function(int) f) {
  for (var t = 0; t < kKinds; t++) {
    if (all[t] > 0 && !f(t)) return false;
  }
  return true;
}

/// Common hand-wide fans (flush, 断幺, 四归一, situational, flowers).
void _common(_Fans f, List<int> all, List<int> concealed, List<Meld> melds, EpCtx ctx,
    {required bool menqing, bool skipFlush = false, bool skipMenqing = false, bool skipYaojiuHand = false}) {
  final hasHonor = _allOf(all, isHonor);
  final numSuits = <int>{for (var t = 0; t < 27; t++) if (all[t] > 0) suitOf(t)};
  final anyHonor = [for (var t = 27; t < 34; t++) all[t]].any((x) => x > 0);
  if (!skipYaojiuHand && !hasHonor) {
    if (!skipFlush && numSuits.length == 1 && !anyHonor) f.add('清一色', 24);
    if (!skipFlush && numSuits.length == 1 && anyHonor) f.add('混一色', 6);
  }
  if (_allOf(all, (t) => !isYaojiu(t))) f.add('断幺', 2);
  // 四归一: four of a tile without it being a kong
  var guiyi = 0;
  for (var t = 0; t < kKinds; t++) {
    if (all[t] == 4 && !melds.any((m) => m.isKong && m.tile == t)) guiyi++;
  }
  f.add('四归一', 2, guiyi);
  // situational
  if (ctx.kongDraw) {
    f.add('杠上开花', 8);
  } else if (ctx.lastTile) {
    f.add(ctx.selfDrawn ? '妙手回春' : '海底捞月', 8);
  }
  if (ctx.robKong) f.add('抢杠和', 8);
  if (ctx.lastCopy && !ctx.robKong) f.add('和绝张', 4);
  final noCalls = melds.every((m) => m.kind == 'agang');
  final zimoCounted = ctx.selfDrawn && !ctx.kongDraw && !(ctx.lastTile && ctx.selfDrawn);
  if (!skipMenqing && noCalls && ctx.selfDrawn) {
    f.add('不求人', 4);
  } else {
    if (!skipMenqing && menqing && !ctx.selfDrawn) f.add('门前清', 2);
    if (zimoCounted) f.add('自摸', 1);
  }
  if (ctx.flowers > 0) f.add('花牌', 1, ctx.flowers);
}

_Fans? _sevenPairs(List<int> c, List<int> all, List<Meld> melds, EpCtx ctx) {
  if (melds.isNotEmpty || !isSevenPairs(c)) return null;
  final f = _Fans();
  // 连七对: seven consecutive pairs of one suit
  final kinds = [for (var t = 0; t < kKinds; t++) if (c[t] > 0) t];
  final lian = kinds.length == 7 &&
      kinds.every((t) => t < 27 && c[t] == 2) &&
      kinds.last - kinds.first == 6 &&
      suitOf(kinds.first) == suitOf(kinds.last);
  if (lian) {
    f.add('连七对', 88);
    _common(f, all, c, melds, ctx, menqing: false, skipFlush: true, skipMenqing: true);
    return f;
  }
  f.add('七对', 24);
  if (_allOf(all, isHonor)) {
    f.add('字一色', 64);
  } else if (_allOf(all, isYaojiu)) {
    f.add('混幺九', 32);
  }
  // 七对 excludes 不求人 / 门前清 but keeps 自摸 (added by _common)
  _common(f, all, c, melds, ctx, menqing: false, skipMenqing: true, skipYaojiuHand: _allOf(all, isHonor));
  return f;
}

bool _nineGates(List<int> c, List<Meld> melds, int win) {
  if (melds.isNotEmpty) return false;
  final h = List.of(c);
  h[win]--;
  for (var s = 0; s < 3; s++) {
    var ok = true;
    for (var r = 0; r < 9; r++) {
      final need = (r == 0 || r == 8) ? 3 : 1;
      if (h[s * 9 + r] != need) ok = false;
    }
    if (ok && countTotal(h) == 13) return true;
  }
  return false;
}

_Fans _standard(int pair, List<MSet> sets, List<int> all, List<int> concealed, List<Meld> melds, EpCtx ctx,
    {required String wait}) {
  final f = _Fans();
  final pungs = sets.where((s) => s.pung).toList();
  final chows = sets.where((s) => s.chow).toList();
  final kongs = sets.where((s) => s.kong).toList();
  final winds = pungs.where((s) => isWind(s.tile)).length;
  final dragons = pungs.where((s) => isDragon(s.tile)).length;
  final menqing = melds.every((m) => m.kind == 'agang');

  var exPengpeng = false, exWindYaojiu = false, exAllYaojiu = false, exFlush = false;
  var exMenqing = false, exDanDiao = false, exDragonPung = false, exSeatRound = false;
  var exChowSmall = false;

  // 九莲宝灯
  if (_nineGates(concealed, melds, ctx.winTile)) {
    f.add('九莲宝灯', 88);
    exFlush = true;
    exMenqing = true;
    exAllYaojiu = true;
  }
  // winds
  if (winds == 4) {
    f.add('大四喜', 88);
    exPengpeng = true;
    exWindYaojiu = true;
    exSeatRound = true;
  } else if (winds == 3 && isWind(pair)) {
    f.add('小四喜', 64);
    exWindYaojiu = true;
  } else if (winds == 3) {
    f.add('大三风', 12);
    exWindYaojiu = true;
  }
  // dragons
  if (dragons == 3) {
    f.add('大三元', 88);
    exDragonPung = true;
  } else if (dragons == 2 && isDragon(pair)) {
    f.add('小三元', 64);
    exDragonPung = true;
  } else if (dragons == 2) {
    f.add('双箭刻', 6);
    exDragonPung = true;
  }
  if (!exDragonPung) f.add('箭刻', 2, dragons);
  // honours / terminals
  if (_allOf(all, isHonor)) {
    f.add('字一色', 64);
    exPengpeng = true;
    exAllYaojiu = true;
    exFlush = true;
  } else if (_allOf(all, isYaojiu)) {
    f.add('混幺九', 32);
    exPengpeng = true;
    exAllYaojiu = true;
  }
  // kongs
  final ak = kongs.where((s) => s.concealed).length;
  if (kongs.length == 4) {
    f.add('四杠', 88);
    exPengpeng = true;
    exDanDiao = true;
  } else if (kongs.length == 3) {
    f.add('三杠', 32);
  } else if (kongs.length == 2) {
    if (ak == 2) {
      f.add('双暗杠', 6);
    } else if (ak == 1) {
      f.add('明暗杠', 5);
    } else {
      f.add('双明杠', 4);
    }
  } else if (kongs.length == 1) {
    f.add(ak == 1 ? '暗杠' : '明杠', ak == 1 ? 2 : 1);
  }
  // concealed pungs
  final cp = pungs.where((s) => s.concealed).length;
  if (cp == 4) {
    f.add('四暗刻', 64);
    exPengpeng = true;
    exMenqing = true;
  } else if (cp == 3) {
    f.add('三暗刻', 16);
  } else if (cp == 2) {
    f.add('双暗刻', 2);
  }
  // pung sequences (节高)
  final numPungs = [for (final s in pungs) if (s.tile < 27) s.tile]..sort();
  var jiegao = 0;
  for (var i = 0; i < numPungs.length; i++) {
    var run = 1;
    for (var j = i + 1; j < numPungs.length; j++) {
      if (numPungs[j] == numPungs[j - 1] + 1 && suitOf(numPungs[j]) == suitOf(numPungs[i])) {
        run++;
      } else {
        break;
      }
    }
    if (run > jiegao) jiegao = run;
  }
  if (jiegao >= 4) {
    f.add('一色四节高', 48);
    exPengpeng = true;
  } else if (jiegao == 3) {
    f.add('一色三节高', 24);
  }
  // chow combos
  final lows = [for (final s in chows) s.tile]..sort();
  if (lows.length == 4 &&
      lows[0] == lows[1] &&
      lows[2] == lows[3] &&
      rankOf(lows[0]) == 1 &&
      lows[2] == lows[0] + 6 &&
      pair == lows[0] + 4) {
    f.add('一色双龙会', 64);
    exFlush = true;
    exChowSmall = true;
  } else {
    final big = _bigChowCombo(lows);
    if (big != null) {
      f.add(big.$1, big.$2);
      exChowSmall = true;
    }
  }
  if (!exChowSmall) {
    final groups = <int, int>{};
    for (final l in lows) {
      groups[l] = (groups[l] ?? 0) + 1;
    }
    var yiban = 0;
    for (final n in groups.values) {
      yiban += n ~/ 2;
    }
    f.add('一般高', 1, yiban);
    final set = lows.toSet();
    if (set.any((l) => set.contains(l + 3) && rankOf(l) <= 4 && suitOf(l) == suitOf(l + 3))) f.add('连六', 1);
    if (set.any((l) => rankOf(l) == 1 && set.contains(l + 6))) f.add('老少副', 1);
  }
  // 碰碰和
  if (pungs.length == 4 && !exPengpeng) f.add('碰碰和', 6);
  // seat / round wind pungs & 幺九刻
  var yaojiuKe = 0;
  for (final s in pungs) {
    final t = s.tile;
    if (isWind(t)) {
      final seat = t - 27 == ctx.seatWind, round = t - 27 == ctx.roundWind;
      if (!exSeatRound && seat) f.add('门风刻', 2);
      if (!exSeatRound && round) f.add('圈风刻', 2);
      if (!seat && !round && !exWindYaojiu && !exAllYaojiu) yaojiuKe++;
    } else if (isTerminal(t) && !exAllYaojiu) {
      yaojiuKe++;
    }
  }
  f.add('幺九刻', 1, yaojiuKe);
  // 全求人: four called melds, won by a discard on a single wait
  final allCalled = melds.length == 4 && melds.every((m) => m.kind != 'agang');
  if (allCalled && !ctx.selfDrawn) {
    f.add('全求人', 6);
    exDanDiao = true;
  }
  // wait
  if (ctx.waitCount == 1) {
    if (wait == 'dan' && !exDanDiao) f.add('单钓将', 1);
    if (wait == 'bian') f.add('边张', 1);
    if (wait == 'kan') f.add('坎张', 1);
  }
  _common(f, all, concealed, melds, ctx,
      menqing: menqing && !allCalled, skipFlush: exFlush, skipMenqing: exMenqing || allCalled, skipYaojiuHand: false);
  return f;
}

/// Largest same-suit chow combination: (name, fan) or null.
(String, int)? _bigChowCombo(List<int> lows) {
  (String, int)? best;
  void consider(String n, int v) {
    if (best == null || v > best!.$2) best = (n, v);
  }

  final n = lows.length;
  // identical chows
  final cnt = <int, int>{};
  for (final l in lows) {
    cnt[l] = (cnt[l] ?? 0) + 1;
  }
  for (final e in cnt.values) {
    if (e == 4) consider('一色四同顺', 48);
    if (e == 3) consider('一色三同顺', 24);
  }
  final set = lows.toSet();
  bool same(int a, int b) => suitOf(a) == suitOf(b);
  for (final l in set) {
    for (final d in const [1, 2]) {
      if (set.contains(l + d) && set.contains(l + 2 * d) && same(l, l + 2 * d) && rankOf(l) + 2 * d <= 7) {
        if (n >= 4 && set.contains(l + 3 * d) && same(l, l + 3 * d) && rankOf(l) + 3 * d <= 7) {
          consider('一色四步高', 32);
        }
        consider('一色三步高', 16);
      }
    }
    if (rankOf(l) == 1 && set.contains(l + 3) && set.contains(l + 6)) consider('清龙', 16);
  }
  return best;
}

/// Evaluate a complete hand ([concealed] includes the winning tile). Returns the
/// best-scoring interpretation, or null when the tiles don't form a winning shape.
EpResult? evaluate2p(List<int> concealed, List<Meld> melds, EpCtx ctx) {
  final total = countTotal(concealed);
  if (total % 3 != 2) return null;
  final all = List.of(concealed);
  for (final m in melds) {
    for (final t in m.tiles) {
      all[t]++;
    }
  }
  _Fans? best;
  void consider(_Fans f) {
    if (best == null || f.base > best!.base) best = f;
  }

  final sp = _sevenPairs(concealed, all, melds, ctx);
  if (sp != null) consider(sp);
  final win = ctx.winTile;
  for (final (pair, hs) in standardDecomps(concealed)) {
    // try every set (or the pair) as the place the winning tile went
    final slots = <int>[if (pair == win) -1, for (var i = 0; i < hs.length; i++) if (hs[i].contains(win)) i];
    for (final slot in slots) {
      var wait = 'other';
      final sets = <MSet>[];
      for (var i = 0; i < hs.length; i++) {
        var s = hs[i];
        if (i == slot) {
          if (s.pung && !ctx.selfDrawn) s = s.withConcealed(false);
          if (s.chow) {
            final r = rankOf(s.tile);
            if (win == s.tile + 1) {
              wait = 'kan';
            } else if ((win == s.tile + 2 && r == 1) || (win == s.tile && r == 7)) {
              wait = 'bian';
            }
          }
        }
        sets.add(s);
      }
      if (slot == -1) wait = 'dan';
      for (final m in melds) {
        sets.add(setFromMeld(m));
      }
      consider(_standard(pair, sets, all, concealed, melds, ctx, wait: wait));
    }
  }
  final b = best;
  if (b == null) return null;
  return EpResult(b.items);
}

bool isWinShape2p(List<int> c, int meldCount) =>
    isStandardWin(c) || (meldCount == 0 && isSevenPairs(c));

List<int> waits2p(List<int> c, int meldCount, List<int> kinds) {
  final out = <int>[];
  for (final k in kinds) {
    if (c[k] >= 4) continue;
    c[k]++;
    if (isWinShape2p(c, meldCount)) out.add(k);
    c[k]--;
  }
  return out;
}
