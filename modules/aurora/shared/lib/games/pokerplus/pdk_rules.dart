/// 跑得快 牌型规则。
///
/// 点数：3..14(A), 15(2)。
library;

import 'cards.dart';

int pdkRank(String code) {
  final r = cardRank(code);
  return r == 2 ? 15 : r;
}

class PdkCombo {
  /// single / pair / pairs / straight / triple / plane / bomb
  final String type;
  final int key; // top rank of the main part
  final int len; // units: pairs count, straight length, triples count; 1 otherwise
  final int n; // card count
  const PdkCombo(this.type, this.key, this.len, this.n);

  String get label => switch (type) {
        'single' => '单张',
        'pair' => '对子',
        'pairs' => '连对',
        'straight' => '顺子',
        'triple' => n == 5 ? '三带二' : (n == 4 ? '三带一' : '三张'),
        'plane' => '飞机',
        'bomb' => '炸弹',
        _ => type,
      };

  /// Whether this combo beats [other] (which is on the table).
  bool beats(PdkCombo other) {
    if (type == 'bomb') return other.type != 'bomb' || key > other.key;
    if (other.type == 'bomb') return false;
    if (type != other.type || len != other.len) return false;
    return key > other.key;
  }

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'n': n, 'label': label};

  @override
  String toString() => '$label($key×$len)';
}

Map<int, int> _counts(List<int> ranks) {
  final m = <int, int>{};
  for (final r in ranks) {
    m[r] = (m[r] ?? 0) + 1;
  }
  return m;
}

/// All interpretations of [ranks] as a combo. [isAll] = these are the
/// player's last cards (allows 三带一 / 三张 / 飞机缺翅膀).
List<PdkCombo> pdkParseAll(List<int> ranks, {bool isAll = false}) {
  final n = ranks.length;
  final out = <PdkCombo>[];
  if (n == 0) return out;
  final c = _counts(ranks);
  final keys = c.keys.toList()..sort();
  if (n == 1) out.add(PdkCombo('single', ranks[0], 1, 1));
  if (n == 2 && keys.length == 1) out.add(PdkCombo('pair', keys[0], 1, 2));
  if (n == 4 && keys.length == 1) out.add(PdkCombo('bomb', keys[0], 1, 4));
  // consecutive pairs
  if (n >= 4 && n.isEven && keys.every((k) => c[k] == 2) && _consecutive(keys) && keys.last <= 14) {
    out.add(PdkCombo('pairs', keys.last, keys.length, n));
  }
  // straight
  if (n >= 5 && keys.length == n && _consecutive(keys) && keys.last <= 14) {
    out.add(PdkCombo('straight', keys.last, n, n));
  }
  // triples / planes (with wings)
  final trip = [for (final k in keys) if (c[k]! >= 3) k];
  for (var l = trip.length; l >= 1; l--) {
    for (var i = 0; i + l <= trip.length; i++) {
      final seq = trip.sublist(i, i + l);
      if (l > 1 && (!_consecutive(seq) || seq.last > 14)) continue;
      final full = n == 5 * l;
      final short = isAll && n >= 3 * l && n < 5 * l;
      if (full || short) {
        final p = PdkCombo(l == 1 ? 'triple' : 'plane', seq.last, l, n);
        if (!out.any((o) => o.type == p.type && o.key == p.key && o.len == p.len)) out.add(p);
      }
    }
  }
  return out;
}

bool _consecutive(List<int> sorted) {
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] != sorted[i - 1] + 1) return false;
  }
  return true;
}

/// Best interpretation: one that beats [table] if given, else the first
/// (preferring full combos).
PdkCombo? pdkParse(List<int> ranks, {bool isAll = false, PdkCombo? table}) {
  final all = pdkParseAll(ranks, isAll: isAll);
  if (all.isEmpty) return null;
  if (table == null) return all.first;
  for (final c in all) {
    if (c.beats(table)) return c;
  }
  return null;
}

/// Candidate plays (as rank lists) from [hand]. If [table] is given, only
/// candidates that beat it. [singleMax] = 报单 rule (singles must be the max).
/// Candidates are ordered roughly from "cheapest" to "most expensive".
List<List<int>> pdkCandidates(List<int> hand, PdkCombo? table, {bool singleMax = false}) {
  final c = _counts(hand);
  final keys = c.keys.toList()..sort();
  final res = <List<int>>[];
  final isAllN = hand.length;
  void add(List<int> cand) {
    final isAll = cand.length == isAllN;
    final p = pdkParse(cand, isAll: isAll, table: table);
    if (p == null) return;
    if (table == null && pdkParse(cand, isAll: isAll) == null) return;
    res.add(cand);
  }

  List<int> wings(List<int> exclude, int need) {
    // smallest leftover cards, preferring singles that aren't part of pairs/bombs
    final left = <int>[];
    final cc = Map<int, int>.of(c);
    for (final e in exclude) {
      cc[e] = cc[e]! - 1;
    }
    final order = cc.keys.where((k) => cc[k]! > 0).toList()
      ..sort((a, b) {
        final ca = cc[a]!, cb = cc[b]!;
        if (ca != cb) return ca - cb;
        return a - b;
      });
    for (final k in order) {
      for (var i = 0; i < cc[k]! && left.length < need; i++) {
        left.add(k);
      }
    }
    return left;
  }

  final want = table?.type;
  final bombTable = want == 'bomb';
  if (!bombTable) {
    if (want == null || want == 'single') {
      if (singleMax) {
        add([keys.last]);
      } else {
        for (final k in keys) {
          add([k]);
        }
      }
    }
    if (want == null || want == 'pair') {
      for (final k in keys) {
        if (c[k]! >= 2) add([k, k]);
      }
    }
    if (want == null || want == 'pairs') {
      for (var l = 2; l <= 8; l++) {
        if (want != null && l != table!.len) continue;
        for (var s = 3; s + l - 1 <= 14; s++) {
          if (List.generate(l, (i) => s + i).every((r) => (c[r] ?? 0) >= 2)) {
            add([for (var i = 0; i < l; i++) ...[s + i, s + i]]);
          }
        }
      }
    }
    if (want == null || want == 'straight') {
      for (var l = 5; l <= 12; l++) {
        if (want != null && l != table!.len) continue;
        for (var s = 3; s + l - 1 <= 14; s++) {
          if (List.generate(l, (i) => s + i).every((r) => (c[r] ?? 0) >= 1)) {
            add([for (var i = 0; i < l; i++) s + i]);
          }
        }
      }
    }
    if (want == null || want == 'triple' || want == 'plane') {
      for (var l = 1; l <= 5; l++) {
        if (want != null && l != table!.len) continue;
        for (var s = 3; s + l - 1 <= (l == 1 ? 15 : 14); s++) {
          final seq = List.generate(l, (i) => s + i);
          if (!seq.every((r) => (c[r] ?? 0) >= 3)) continue;
          final body = [for (final r in seq) ...[r, r, r]];
          if (hand.length <= 5 * l) {
            add(List.of(hand)); // take everything (short wings allowed as last cards)
          } else {
            add([...body, ...wings(body, 2 * l)]);
          }
        }
      }
    }
  }
  for (final k in keys) {
    if (c[k] == 4) add([k, k, k, k]);
  }
  // de-duplicate
  final seen = <String>{};
  return [
    for (final r in res)
      if (seen.add((List.of(r)..sort()).join(','))) r
  ];
}

/// Picks concrete card codes from [hand] matching [ranks].
List<String> pdkPick(List<String> hand, List<int> ranks) {
  final used = <int>{};
  final out = <String>[];
  for (final r in ranks) {
    for (var i = 0; i < hand.length; i++) {
      if (!used.contains(i) && pdkRank(hand[i]) == r) {
        used.add(i);
        out.add(hand[i]);
        break;
      }
    }
  }
  return out;
}

/// Deck for 跑得快: no jokers, only ♥2, no ♠A (48 cards, 16 each).
/// 15-card mode: only ♥A kept, ♠K removed (45 cards, 15 each).
List<String> pdkDeck(int perHand) {
  bool keep(String c) {
    if (c[0] == '2') return c == '2H';
    if (perHand == 15) {
      if (c[0] == 'A') return c == 'AH';
      if (c == 'KS') return false;
    } else if (c == 'AS') {
      return false;
    }
    return true;
  }

  return [for (final c in fullDeck()) if (keep(c)) c];
}

int pdkSortKey(String c) => pdkRank(c) * 4 + 'DCHS'.indexOf(c[1]);

/// Rough number of plays needed to empty [hand] (greedy decomposition into
/// bombs, straights, consecutive pairs, triples with wings, pairs and
/// singles). Used by the hard 跑得快 bot.
int pdkTurns(List<int> hand) {
  final c = <int, int>{};
  for (final r in hand) {
    c[r] = (c[r] ?? 0) + 1;
  }
  int cnt(int r) => c[r] ?? 0;
  var turns = 0;
  for (final r in c.keys.toList()) {
    if (c[r] == 4) {
      turns++;
      c[r] = 0;
    }
  }
  // straights over mostly-single ranks
  var changed = true;
  while (changed) {
    changed = false;
    for (var len = 12; len >= 5 && !changed; len--) {
      for (var lo = 3; lo + len - 1 <= 14; lo++) {
        final run = List.generate(len, (i) => lo + i);
        if (!run.every((r) => cnt(r) >= 1)) continue;
        final singles = run.where((r) => cnt(r) == 1).length;
        if (singles * 2 < len) continue;
        for (final r in run) {
          c[r] = cnt(r) - 1;
        }
        turns++;
        changed = true;
        break;
      }
    }
  }
  // consecutive pairs
  for (var lo = 3; lo <= 13; lo++) {
    var len = 0;
    while (lo + len <= 14 && cnt(lo + len) == 2) {
      len++;
    }
    if (len >= 2) {
      for (var i = 0; i < len; i++) {
        c[lo + i] = 0;
      }
      turns++;
    }
  }
  // triples take up to two low singles (or one pair) as wings
  final triples = [for (final r in c.keys) if (cnt(r) == 3) r]..sort();
  for (final t in triples) {
    c[t] = 0;
    turns++;
    var wings = 2;
    final singles = [for (final r in c.keys) if (cnt(r) == 1) r]..sort();
    for (final s in singles) {
      if (wings == 0) break;
      c[s] = 0;
      wings--;
    }
    if (wings == 2) {
      final pairs = [for (final r in c.keys) if (cnt(r) == 2) r]..sort();
      if (pairs.isNotEmpty) c[pairs.first] = 0;
    }
  }
  for (final v in c.values) {
    if (v == 2 || v == 1) turns++;
  }
  return turns;
}
