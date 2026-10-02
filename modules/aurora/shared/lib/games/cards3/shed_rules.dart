/// Shedding-combo rules shared by 五十K and 争上游.
///
/// Values (see [c3Val]): 3..14(A), 2 = 15, 小王 16, 大王 17.
/// Combos: 单张、对子、三张、顺子(5+，3..A)、连对(2+ 对)、飞机(2+ 连续三张)、
/// 炸弹(4+ 同点)、510K（可选）、王炸（全部王）。
library;

import 'cards.dart';

class ShedRules {
  /// 510K 为特殊炸弹（五十K）。
  final bool k510;

  /// 王炸所需张数（=牌堆中王的数量，一副牌 2，两副牌 4）。
  final int rocketLen;

  /// 是否允许飞机（连续三张）。
  final bool planes;
  const ShedRules({this.k510 = false, this.rocketLen = 2, this.planes = true});
}

class ShedCombo {
  /// single | pair | triple | straight | pairs | plane | k510 | bomb | rocket
  final String type;

  /// Highest value for sequences, rank for same-value combos.
  /// For k510: 0 = 杂 510K, 1..4 = 纯 510K (♦ ♣ ♥ ♠).
  final int key;
  final int len;
  const ShedCombo(this.type, this.key, this.len);

  bool get isBomb => type == 'bomb' || type == 'k510' || type == 'rocket';

  /// Bomb power tier: 杂510K < 纯510K(by suit) < 4炸 < 5炸 < ... < 王炸.
  int get _power {
    switch (type) {
      case 'k510':
        return key; // 0..4
      case 'bomb':
        return 100 + len * 20 + key;
      case 'rocket':
        return 10000;
      default:
        return -1;
    }
  }

  bool beats(ShedCombo t) {
    if (isBomb) {
      if (!t.isBomb) return true;
      return _power > t._power;
    }
    if (t.isBomb) return false;
    return type == t.type && len == t.len && key > t.key;
  }

  static const _pureName = ['杂', '纯♦', '纯♣', '纯♥', '纯♠'];

  String get label {
    switch (type) {
      case 'single':
        return '单张 ${c3ValName(key)}';
      case 'pair':
        return '对${c3ValName(key)}';
      case 'triple':
        return '三个${c3ValName(key)}';
      case 'straight':
        return '顺子 ${c3ValName(key - len + 1)}-${c3ValName(key)}';
      case 'pairs':
        return '连对 ${c3ValName(key - len ~/ 2 + 1)}-${c3ValName(key)}';
      case 'plane':
        return '飞机 ${c3ValName(key - len ~/ 3 + 1)}-${c3ValName(key)}';
      case 'k510':
        return '${_pureName[key.clamp(0, 4)]}510K';
      case 'bomb':
        return '$len个${c3ValName(key)}炸弹';
      default:
        return '王炸';
    }
  }

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'label': label};
  static ShedCombo? fromJson(Object? j) {
    if (j is! Map) return null;
    return ShedCombo('${j['type']}', (j['key'] as num).toInt(), (j['len'] as num).toInt());
  }

  @override
  bool operator ==(Object o) => o is ShedCombo && o.type == type && o.key == key && o.len == len;
  @override
  int get hashCode => Object.hash(type, key, len);
  @override
  String toString() => label;
}

bool _consecutive(List<int> sortedDistinct) {
  for (var i = 1; i < sortedDistinct.length; i++) {
    if (sortedDistinct[i] != sortedDistinct[i - 1] + 1) return false;
  }
  return true;
}

/// Classifies [cards] or returns null.
ShedCombo? shedClassify(List<String> cards, ShedRules r) {
  final n = cards.length;
  if (n == 0) return null;
  final jokers = cards.where(c3IsJoker).length;
  if (jokers == n && n == r.rocketLen && n >= 2) {
    // 一副牌：大小王；两副牌：四个王
    if (r.rocketLen == 2 ? cards.toSet().length == 2 : true) return const ShedCombo('rocket', 99, 0);
  }
  final vals = [for (final c in cards) c3Val(c)]..sort();
  if (r.k510 && n == 3 && vals[0] == 5 && vals[1] == 10 && vals[2] == 13) {
    final suits = cards.map(c3Suit).toSet();
    return ShedCombo('k510', suits.length == 1 ? c3SuitRank(suits.first) : 0, 3);
  }
  final cnt = <int, int>{};
  for (final v in vals) {
    cnt[v] = (cnt[v] ?? 0) + 1;
  }
  final keys = cnt.keys.toList()..sort();
  if (keys.length == 1) {
    final v = keys.first;
    if (n == 1) return ShedCombo('single', v, 1);
    if (n == 2) return ShedCombo('pair', v, 2);
    if (n == 3) return ShedCombo('triple', v, 3);
    if (v >= 16) return null; // 同名王多张不成炸
    return ShedCombo('bomb', v, n);
  }
  if (keys.last > 14 || !_consecutive(keys)) return null;
  final per = cnt.values.toSet();
  if (per.length != 1) return null;
  final k = per.first;
  if (k == 1 && n >= 5) return ShedCombo('straight', keys.last, n);
  if (k == 2 && keys.length >= 2) return ShedCombo('pairs', keys.last, n);
  if (k == 3 && keys.length >= 2 && r.planes) return ShedCombo('plane', keys.last, n);
  return null;
}

/// Candidate plays from [hand] that beat [table] (or any lead when null),
/// ordered roughly cheapest first (non-bombs by key, then bombs by power).
List<List<String>> shedCandidates(List<String> hand, ShedCombo? table, ShedRules r) {
  final g = c3Groups(hand);
  for (final l in g.values) {
    l.sort((a, b) => c3SuitRank(c3Suit(a)) - c3SuitRank(c3Suit(b)));
  }
  final out = <List<String>>[];
  final seen = <String>{};
  void add(List<String> cards) {
    final c = shedClassify(cards, r);
    if (c == null) return;
    if (table != null && !c.beats(table)) return;
    if (!seen.add('${c.type}${c.key}/${c.len}')) return;
    out.add(cards);
  }

  int count(int v) => g[v]?.length ?? 0;
  final vals = g.keys.toList()..sort();
  // same-value combos (without breaking bombs where possible is left to the bot)
  for (final size in [1, 2, 3]) {
    if (table != null && !table.isBomb) {
      final want = {'single': 1, 'pair': 2, 'triple': 3}[table.type];
      if (want != size) continue;
    }
    for (final v in vals) {
      if (count(v) >= size) add(g[v]!.sublist(0, size));
    }
  }
  // sequences
  void seqs(int per, int minLen) {
    for (var s = 3; s <= 14; s++) {
      for (var e = s; e <= 14; e++) {
        if (count(e) < per) break;
        final len = e - s + 1;
        if (len < minLen) continue;
        add([for (var v = s; v <= e; v++) ...g[v]!.sublist(0, per)]);
      }
    }
  }

  final t = table?.type;
  if (t == null || t == 'straight') seqs(1, 5);
  if (t == null || t == 'pairs') seqs(2, 2);
  if (r.planes && (t == null || t == 'plane')) seqs(3, 2);
  // bombs
  if (r.k510) {
    final fives = g[5] ?? const [], tens = g[10] ?? const [], ks = g[13] ?? const [];
    if (fives.isNotEmpty && tens.isNotEmpty && ks.isNotEmpty) {
      // one mixed (if possible) and every pure suit
      for (final a in fives) {
        for (final b in tens) {
          for (final c in ks) {
            add([a, b, c]);
          }
        }
      }
    }
  }
  for (final v in vals) {
    if (v >= 16) continue;
    for (var k = 4; k <= count(v); k++) {
      add(g[v]!.sublist(0, k));
    }
  }
  final jokers = hand.where(c3IsJoker).toList();
  if (jokers.length >= r.rocketLen) add(jokers.sublist(0, r.rocketLen));
  // order: non-bombs by (len desc on lead? no) key asc; bombs by power
  int power(List<String> c) {
    final x = shedClassify(c, r)!;
    if (!x.isBomb) return x.key;
    return 1000 + (x.type == 'k510' ? x.key : (x.type == 'bomb' ? 100 + x.len * 20 + x.key : 10000));
  }

  out.sort((a, b) => power(a) - power(b));
  return out;
}

/// Simple bot choice shared by 五十K / 争上游.
/// [lead]: prefer long low combos; follow: cheapest beater, bombs only if [urgent].
List<String>? shedBotPick(List<String> hand, ShedCombo? table, ShedRules r, {bool urgent = false}) {
  final cands = shedCandidates(hand, table, r);
  if (cands.isEmpty) return null;
  final whole = cands.where((c) => c.length == hand.length);
  if (whole.isNotEmpty) return whole.first;
  final g = c3Groups(hand);
  bool breaksBomb(List<String> c) {
    final x = shedClassify(c, r)!;
    if (x.isBomb) return false;
    return c.any((card) => (g[c3Val(card)]?.length ?? 0) >= 4);
  }

  if (table == null) {
    final nb = cands.where((c) => !shedClassify(c, r)!.isBomb && !breaksBomb(c)).toList();
    if (nb.isEmpty) return cands.first;
    // lowest starting value, then longest
    int low(List<String> c) => c.map(c3Val).reduce((a, b) => a < b ? a : b);
    nb.sort((a, b) {
      final d = low(a) - low(b);
      if (d != 0) return d;
      return b.length - a.length;
    });
    return nb.first;
  }
  final plain = cands.where((c) => !shedClassify(c, r)!.isBomb && !breaksBomb(c)).toList();
  if (plain.isNotEmpty) {
    final p = plain.first;
    // 不轻易用 2/王 压小牌
    final big = p.any((c) => c3Val(c) >= 15);
    if (big && !urgent && hand.length > 5 && (table.key < 11)) return null;
    return p;
  }
  if (urgent) return cands.firstWhere((c) => shedClassify(c, r)!.isBomb, orElse: () => cands.first);
  return null;
}
