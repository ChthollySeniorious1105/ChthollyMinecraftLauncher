/// 干瞪眼 rules: combos with wild jokers and the "exactly one higher" follow rule.
library;

import 'cards.dart';

/// A 干瞪眼 combination. [key] = top rank (straight: highest rank), bombs: rank
/// (王炸 key 99). [len] = number of cards.
class GdyCombo {
  final String type; // single | pair | straight | pairs | bomb
  final int key;
  final int len;
  const GdyCombo(this.type, this.key, this.len);

  bool get isBomb => type == 'bomb';
  bool get isRocket => type == 'bomb' && key == 99;

  String get label {
    switch (type) {
      case 'single':
        return '单张 ${c3ValName(key)}';
      case 'pair':
        return '对${c3ValName(key)}';
      case 'straight':
        return '顺子 ${c3ValName(key - len + 1)}-${c3ValName(key)}';
      case 'pairs':
        return '连对 ${c3ValName(key - len ~/ 2 + 1)}-${c3ValName(key)}';
      default:
        return isRocket ? '王炸' : '$len个${c3ValName(key)}炸弹';
    }
  }

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'label': label};
  static GdyCombo? fromJson(Object? j) {
    if (j is! Map) return null;
    return GdyCombo('${j['type']}', (j['key'] as num).toInt(), (j['len'] as num).toInt());
  }

  /// Whether this combo may be played on top of [t].
  bool beats(GdyCombo t) {
    if (isBomb) {
      if (!t.isBomb) return true;
      if (isRocket) return !t.isRocket;
      if (t.isRocket) return false;
      if (len != t.len) return len > t.len;
      return key > t.key;
    }
    if (t.isBomb) return false;
    if (type != t.type || len != t.len) return false;
    if (type == 'single' || type == 'pair') {
      if (key == 15) return t.key != 15; // 2 管任何同型牌
      return key == t.key + 1 && t.key < 15;
    }
    return key == t.key + 1; // 顺子/连对: 恰好大一级
  }

  @override
  bool operator ==(Object o) => o is GdyCombo && o.type == type && o.key == key && o.len == len;
  @override
  int get hashCode => Object.hash(type, key, len);
  @override
  String toString() => label;
}

/// Every way [cards] can be read (jokers are wild). Empty list = not a combo.
List<GdyCombo> gdyInterpret(List<String> cards) {
  final out = <GdyCombo>[];
  final j = cards.where(c3IsJoker).length;
  final nat = [for (final c in cards) if (!c3IsJoker(c)) c3Val(c)]..sort();
  final n = cards.length;
  if (n == 0) return out;
  if (nat.isEmpty) {
    // 单独的王可当任意单张（不含王本身），两张王为王炸
    if (j == 1) {
      for (var v = 3; v <= 15; v++) {
        out.add(GdyCombo('single', v, 1));
      }
    }
    if (j == 2) out.add(const GdyCombo('bomb', 99, 2));
    return out;
  }
  // same rank: single / pair / bomb
  if (nat.every((v) => v == nat.first)) {
    final v = nat.first;
    if (n == 1) out.add(GdyCombo('single', v, 1));
    if (n == 2) out.add(GdyCombo('pair', v, 2));
    if (n >= 3) out.add(GdyCombo('bomb', v, n));
  }
  if (nat.every((v) => v <= 14)) {
    // straight 3+
    if (n >= 3 && nat.toSet().length == nat.length) {
      for (var s = 3; s + n - 1 <= 14; s++) {
        if (nat.first >= s && nat.last <= s + n - 1) out.add(GdyCombo('straight', s + n - 1, n));
      }
    }
    // consecutive pairs (2+ pairs)
    if (n >= 4 && n.isEven) {
      final cnt = <int, int>{};
      for (final v in nat) {
        cnt[v] = (cnt[v] ?? 0) + 1;
      }
      if (cnt.values.every((c) => c <= 2)) {
        final p = n ~/ 2;
        for (var s = 3; s + p - 1 <= 14; s++) {
          if (nat.first >= s && nat.last <= s + p - 1) out.add(GdyCombo('pairs', s + p - 1, n));
        }
      }
    }
  }
  return out;
}

/// Best reading for a lead: bombs first, then the highest key.
GdyCombo? gdyBestLead(List<String> cards) {
  final l = gdyInterpret(cards);
  if (l.isEmpty) return null;
  l.sort((a, b) {
    if (a.isBomb != b.isBomb) return a.isBomb ? -1 : 1;
    return b.key - a.key;
  });
  return l.first;
}

/// The reading used to follow [table] (the lowest one that beats it), or null.
GdyCombo? gdyFollowAs(List<String> cards, GdyCombo table) {
  final l = gdyInterpret(cards).where((c) => c.beats(table)).toList();
  if (l.isEmpty) return null;
  l.sort((a, b) {
    if (a.isBomb != b.isBomb) return a.isBomb ? 1 : -1;
    if (a.len != b.len) return a.len - b.len;
    return a.key - b.key;
  });
  return l.first;
}

/// Heuristic "cost" of spending [cards] (lower = cheaper to play).
int gdyCost(List<String> cards, GdyCombo c) {
  var cost = c.isBomb ? 60 + c.len * 5 : 0;
  for (final x in cards) {
    if (c3IsJoker(x)) cost += 25;
    if (c3Val(x) == 15) cost += 15;
  }
  cost += c.key == 99 ? 40 : c.key;
  return cost - (c.isBomb ? 0 : cards.length * 3);
}

/// All legal plays from [hand] (lead if [table] null) with their readings,
/// cheapest first.
List<(List<String>, GdyCombo)> gdyPlays(List<String> hand, GdyCombo? table) {
  final h = List.of(hand)..sort((a, b) => c3Val(a) - c3Val(b));
  final n = h.length > 16 ? 16 : h.length;
  final seen = <String>{};
  final out = <(List<String>, GdyCombo)>[];
  for (var mask = 1; mask < (1 << n); mask++) {
    final cards = [for (var i = 0; i < n; i++) if (mask & (1 << i) != 0) h[i]];
    final c = table == null ? gdyBestLead(cards) : gdyFollowAs(cards, table);
    if (c == null) continue;
    final sig = '${[for (final x in cards) c3IsJoker(x) ? x : c3Val(x)].join(',')}|${c.type}${c.key}';
    if (!seen.add(sig)) continue;
    out.add((cards, c));
  }
  out.sort((a, b) => gdyCost(a.$1, a.$2) - gdyCost(b.$1, b.$2));
  return out;
}

/// Minimum number of plays needed to empty [hand] (partition into legal lead
/// combos). Exact for up to 12 cards, else a rough estimate. Used by bots.
int gdyMinPlays(List<String> hand) {
  final n = hand.length;
  if (n == 0) return 0;
  if (n > 12) return (n + 1) ~/ 2;
  final full = (1 << n) - 1;
  final ok = List.filled(1 << n, false);
  for (var m = 1; m <= full; m++) {
    ok[m] = gdyInterpret([for (var i = 0; i < n; i++) if (m & (1 << i) != 0) hand[i]]).isNotEmpty;
  }
  final best = List.filled(1 << n, 99);
  best[0] = 0;
  for (var m = 1; m <= full; m++) {
    final low = m & -m; // the lowest card must be in some part
    for (var sub = m; sub > 0; sub = (sub - 1) & m) {
      if (sub & low == 0 || !ok[sub]) continue;
      final v = best[m ^ sub] + 1;
      if (v < best[m]) best[m] = v;
    }
  }
  return best[full];
}
