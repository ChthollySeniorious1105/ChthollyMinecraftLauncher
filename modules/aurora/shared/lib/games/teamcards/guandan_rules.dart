/// 掼蛋牌型识别、比较与候选出牌生成（两副牌，红桃级牌为逢人配）。
///
/// 自然点数：2..14 = 2..A，16 = 小王，17 = 大王。
/// 比较点数（value）：级牌 = 15（大于 A），其余同自然点数。顺子类牌型使用自然点数（A 可作 1）。
library;

const _gdRankChars = '23456789TJQKA';

/// Natural rank: 2..14, jokers 16 / 17.
int gdNat(String c) {
  if (c == 'BJ') return 16;
  if (c == 'RJ') return 17;
  return _gdRankChars.indexOf(c[0]) + 2;
}

String gdSuit(String c) => (c == 'BJ' || c == 'RJ' || c.length < 2) ? 'J' : c[1];

String gdRankChar(int r) => _gdRankChars[r - 2];

/// 红桃级牌（逢人配）。
bool gdIsWild(String c, int level) => c == '${gdRankChar(level)}H';

/// Comparison value for single/pair/triple/bomb: level rank -> 15.
int gdValue(String c, int level) {
  final n = gdNat(c);
  if (n >= 16) return n;
  return n == level ? 15 : n;
}

String gdRankName(int r) {
  if (r == 16) return '小王';
  if (r == 17) return '大王';
  if (r == 14 || r == 1) return 'A';
  if (r == 13) return 'K';
  if (r == 12) return 'Q';
  if (r == 11) return 'J';
  return '$r';
}

String gdValueName(int v, int level) => v == 15 ? gdRankName(level) : gdRankName(v);

int _suitOrder(String c) => 'DCHS'.indexOf(gdSuit(c));

/// Display order: wild cards first, then big to small by value.
List<String> gdSort(Iterable<String> cards, int level) {
  final l = List<String>.of(cards);
  l.sort((a, b) {
    final wa = gdIsWild(a, level), wb = gdIsWild(b, level);
    if (wa != wb) return wa ? -1 : 1;
    final d = gdValue(b, level) - gdValue(a, level);
    return d != 0 ? d : _suitOrder(b) - _suitOrder(a);
  });
  return l;
}

List<String> gdDeck() {
  final out = <String>[];
  for (var d = 0; d < 2; d++) {
    for (final r in _gdRankChars.split('')) {
      for (final s in 'SHDC'.split('')) {
        out.add('$r$s');
      }
    }
    out
      ..add('BJ')
      ..add('RJ');
  }
  return out;
}

class GdCombo {
  /// single pair triple full straight tube plate bomb sf jokers
  final String type;
  final int key;
  final int len;
  const GdCombo(this.type, this.key, this.len);

  /// Bomb class strength: 4炸 40, 5炸 50, 同花顺 55, 6炸 60 ... 10炸 100, 天王炸 1000.
  int get power {
    switch (type) {
      case 'bomb':
        return len * 10;
      case 'sf':
        return 55;
      case 'jokers':
        return 1000;
    }
    return 0;
  }

  bool get isBomb => power > 0;

  String get label {
    switch (type) {
      case 'single':
        return '单张';
      case 'pair':
        return '对子';
      case 'triple':
        return '三同张';
      case 'full':
        return '三带二';
      case 'straight':
        return '顺子';
      case 'tube':
        return '三连对';
      case 'plate':
        return '钢板';
      case 'bomb':
        return '$len炸';
      case 'sf':
        return '同花顺';
      case 'jokers':
        return '天王炸';
    }
    return type;
  }

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'label': label};

  static GdCombo? fromJson(Object? j) {
    if (j is! Map) return null;
    return GdCombo('${j['type']}', (j['key'] as num).toInt(), (j['len'] as num).toInt());
  }

  @override
  bool operator ==(Object other) => other is GdCombo && other.type == type && other.key == key && other.len == len;
  @override
  int get hashCode => Object.hash(type, key, len);
  @override
  String toString() => '$type($key,$len)';
}

bool gdBeats(GdCombo a, GdCombo b) {
  if (a.isBomb || b.isBomb) {
    if (a.power != b.power) return a.power > b.power;
    return a.key > b.key;
  }
  return a.type == b.type && a.len == b.len && a.key > b.key;
}

/// Strength order used to pick the "best" interpretation.
int _strength(GdCombo c) => c.power * 1000 + c.key;

/// All interpretations of [cards]; empty = not a valid combo.
List<GdCombo> gdAnalyze(List<String> cards, int level) {
  final n = cards.length;
  if (n == 0) return const [];
  var wild = 0;
  final nat = <String>[];
  for (final c in cards) {
    if (gdIsWild(c, level)) {
      wild++;
    } else {
      nat.add(c);
    }
  }
  final res = <GdCombo>[];
  final vals = [for (final c in nat) gdValue(c, level)];
  final cnt = <int, int>{};
  for (final v in vals) {
    cnt[v] = (cnt[v] ?? 0) + 1;
  }
  final jokerCount = vals.where((v) => v >= 16).length;
  if (n == 4 && jokerCount == 4) return const [GdCombo('jokers', 17, 4)];

  // same value groups
  if (cnt.length <= 1) {
    final v = cnt.isEmpty ? 15 : cnt.keys.first;
    if (v >= 16) {
      if (wild == 0) {
        if (n == 1) res.add(GdCombo('single', v, 1));
        if (n == 2) res.add(GdCombo('pair', v, 2));
      }
    } else {
      if (n == 1) res.add(GdCombo('single', v, 1));
      if (n == 2) res.add(GdCombo('pair', v, 2));
      if (n == 3) res.add(GdCombo('triple', v, 3));
      if (n >= 4 && n <= 10) res.add(GdCombo('bomb', v, n));
    }
  }

  // 三带二
  if (n == 5 && cnt.length <= 2) {
    var best = -1;
    for (var t = 2; t <= 15; t++) {
      for (var p = 2; p <= 17; p++) {
        if (p == t) continue;
        if (cnt.keys.any((k) => k != t && k != p)) continue;
        final ct = cnt[t] ?? 0, cp = cnt[p] ?? 0;
        if (ct > 3 || cp > 2) continue;
        if (p >= 16 && cp != 2) continue;
        if (3 - ct + 2 - cp != wild) continue;
        if (t > best) best = t;
      }
    }
    if (best > 0) res.add(GdCombo('full', best, 5));
  }

  // sequences
  if (jokerCount == 0) {
    final ranks = [for (final c in nat) gdNat(c)];
    int? seq(int k, int len) {
      int? top;
      for (var s = 1; s + len - 1 <= 14; s++) {
        final e = s + len - 1;
        final per = <int, int>{};
        var ok = true;
        for (final r in ranks) {
          int pos;
          if (r >= s && r <= e) {
            pos = r;
          } else if (r == 14 && s == 1) {
            pos = 1;
          } else {
            ok = false;
            break;
          }
          per[pos] = (per[pos] ?? 0) + 1;
          if (per[pos]! > k) {
            ok = false;
            break;
          }
        }
        if (!ok) continue;
        final missing = k * len - ranks.length;
        if (missing == wild) top = e;
      }
      return top;
    }

    if (n == 5) {
      final t = seq(1, 5);
      if (t != null) {
        res.add(GdCombo('straight', t, 5));
        final suits = nat.map(gdSuit).toSet();
        if (suits.length <= 1) res.add(GdCombo('sf', t, 5));
      }
    }
    if (n == 6) {
      final t = seq(2, 3);
      if (t != null) res.add(GdCombo('tube', t, 6));
      final p = seq(3, 2);
      if (p != null) res.add(GdCombo('plate', p, 6));
    }
  }
  return res;
}

/// Interpretation used when playing [cards] on [table] (null = leading).
/// [as] restricts to a specific type (bombs are always allowed when following).
GdCombo? gdPick(List<String> cards, GdCombo? table, int level, {String? as}) {
  var all = List.of(gdAnalyze(cards, level));
  if (as != null && as.isNotEmpty) {
    final f = all.where((c) => c.type == as).toList();
    if (f.isNotEmpty) all = f;
  }
  if (table != null) all = all.where((c) => gdBeats(c, table)).toList();
  if (all.isEmpty) return null;
  all.sort((a, b) => _strength(b) - _strength(a));
  return all.first;
}

class GdPlay {
  final List<String> cards;
  final GdCombo combo;
  const GdPlay(this.cards, this.combo);
  int wilds(int level) => cards.where((c) => gdIsWild(c, level)).length;
}

/// Candidate plays from [hand] that are legal on [table] (null = leading).
List<GdPlay> gdCandidates(List<String> hand, GdCombo? table, int level) {
  final wilds = <String>[];
  final byVal = <int, List<String>>{};
  final byRank = <int, List<String>>{};
  for (final c in hand) {
    if (gdIsWild(c, level)) {
      wilds.add(c);
      continue;
    }
    (byVal[gdValue(c, level)] ??= []).add(c);
    final r = gdNat(c);
    if (r <= 14) (byRank[r] ??= []).add(c);
  }
  final raw = <(List<String>, String)>[];
  bool want(String t) => table == null || table.type == t || (t == 'bomb' || t == 'sf' || t == 'jokers');

  final vals = {...byVal.keys, if (wilds.isNotEmpty) 15}.toList()..sort();

  /// take k cards of value v using naturals first then wilds; tracks used wilds.
  List<String>? take(int v, int k, List<int> wildUsed) {
    final nat = byVal[v] ?? const <String>[];
    final out = <String>[];
    for (var i = 0; i < nat.length && out.length < k; i++) {
      out.add(nat[i]);
    }
    if (out.length < k) {
      if (v >= 16) return null;
      final need = k - out.length;
      if (wildUsed[0] + need > wilds.length) return null;
      for (var i = 0; i < need; i++) {
        out.add(wilds[wildUsed[0] + i]);
      }
      wildUsed[0] += need;
    }
    return out;
  }

  for (final (t, k) in [('single', 1), ('pair', 2), ('triple', 3)]) {
    if (!want(t)) continue;
    for (final v in vals) {
      final c = take(v, k, [0]);
      if (c != null) raw.add((c, t));
    }
  }
  if (want('full')) {
    for (final t in vals) {
      if (t >= 16) continue;
      for (final p in vals) {
        if (p == t) continue;
        final used = [0];
        final a = take(t, 3, used);
        if (a == null) continue;
        final b = take(p, 2, used);
        if (b == null) continue;
        raw.add(([...a, ...b], 'full'));
      }
    }
  }
  void seqs(String type, int k, int len, {String? suit}) {
    for (var s = 1; s + len - 1 <= 14; s++) {
      final out = <String>[];
      var w = 0;
      var ok = true;
      for (var p = s; p < s + len; p++) {
        final r = p == 1 ? 14 : p;
        var avail = byRank[r] ?? const <String>[];
        if (suit != null) avail = avail.where((c) => gdSuit(c) == suit).toList();
        final use = avail.length >= k ? k : avail.length;
        out.addAll(avail.take(use));
        w += k - use;
        if (w > wilds.length) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      out.addAll(wilds.take(w));
      raw.add((out, type));
    }
  }

  if (want('straight')) seqs('straight', 1, 5);
  if (want('tube')) seqs('tube', 2, 3);
  if (want('plate')) seqs('plate', 3, 2);
  for (final s in 'SHDC'.split('')) {
    seqs('sf', 1, 5, suit: s);
  }
  for (final v in vals) {
    if (v >= 16) continue;
    final c = (byVal[v] ?? const []).length;
    for (var size = 4; size <= 10 && size <= c + wilds.length; size++) {
      final t = take(v, size, [0]);
      if (t != null) raw.add((t, 'bomb'));
    }
  }
  if ((byVal[16]?.length ?? 0) == 2 && (byVal[17]?.length ?? 0) == 2) {
    raw.add(([...byVal[16]!, ...byVal[17]!], 'jokers'));
  }

  final seen = <String>{};
  final res = <GdPlay>[];
  for (final (cards, type) in raw) {
    final combo = gdPick(cards, table, level, as: type);
    if (combo == null) continue;
    if (combo.type != type) continue;
    final key = '${(List.of(cards)..sort()).join(',')}|${combo.type}';
    if (!seen.add(key)) continue;
    res.add(GdPlay(cards, combo));
  }
  return res;
}

/// Heuristic cost of holding [hand] (lower = easier to play out).
double gdHandCost(List<String> hand, int level) {
  var wild = 0;
  final cnt = List.filled(18, 0); // natural ranks 2..14, jokers 16/17
  for (final c in hand) {
    if (gdIsWild(c, level)) {
      wild++;
    } else {
      cnt[gdNat(c)]++;
    }
  }
  double base(List<int> k) {
    var cost = 0.0;
    var singles = 0, pairs = 0, triples = 0;
    for (var r = 2; r <= 17; r++) {
      final c = k[r];
      if (c == 0) continue;
      final v = r >= 16 ? r : (r == level ? 15 : r);
      final high = v >= 14;
      if (r >= 16) {
        // jokers: handled after
        continue;
      }
      if (c >= 4) {
        cost -= 4 + (c - 4) * 1.5;
        continue;
      }
      final g = high ? 5.0 : 10.0 - (v - 2) * 0.35;
      cost += g;
      if (c == 1) singles++;
      if (c == 2) pairs++;
      if (c == 3) triples++;
    }
    // triples carry a pair (三带二)
    cost -= 8.0 * (triples < pairs ? triples : pairs);
    final j = k[16] + k[17];
    if (j == 4) {
      cost -= 12;
    } else {
      cost += (k[16] > 0 ? 3 : 0) + (k[17] > 0 ? 2 : 0);
    }
    return cost + singles * 0.5;
  }

  double best(List<int> k, int depth) {
    var b = base(k);
    if (depth <= 0) return b;
    for (final (per, len) in [(1, 5), (2, 3), (3, 2)]) {
      for (var s = 1; s + len - 1 <= 14; s++) {
        var ok = true;
        var loose = 0;
        for (var p = s; p < s + len; p++) {
          final r = p == 1 ? 14 : p;
          final c = k[r];
          if (c < per || c >= 4) {
            ok = false;
            break;
          }
          if (c == per) loose++;
        }
        if (!ok || loose < (per == 1 ? 3 : 2)) continue;
        final k2 = List.of(k);
        for (var p = s; p < s + len; p++) {
          k2[p == 1 ? 14 : p] -= per;
        }
        final top = s + len - 1;
        final v = 8.0 - top * 0.3 + best(k2, depth - 1);
        if (v < b) b = v;
      }
    }
    return b;
  }

  return best(cnt, 2) - wild * 6.0;
}
