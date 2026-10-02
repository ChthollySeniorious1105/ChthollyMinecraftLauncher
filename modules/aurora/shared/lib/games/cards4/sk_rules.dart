/// 双扣 combo rules (两副牌 108 张，无百搭).
///
/// Values (see [c4Val]): 3..14(A), 2 = 15, 小王 16, 大王 17.
/// 单张、对子、三张、顺子(5+ 张，3..A)、连对(3+ 对)、三顺(2+ 个连续三张)、
/// 炸弹(4~8 张同点，张数多者大)、天王炸(四个王，最大)。
library;

import 'cards.dart';

class SkCombo {
  /// single | pair | triple | straight | pairs | plane | bomb | kings
  final String type;
  final int key; // highest value for sequences, rank otherwise
  final int len;
  const SkCombo(this.type, this.key, this.len);

  bool get isBomb => type == 'bomb' || type == 'kings';

  int get power => type == 'kings' ? 100000 : (type == 'bomb' ? len * 100 + key : -1);

  bool beats(SkCombo t) {
    if (isBomb) return !t.isBomb || power > t.power;
    if (t.isBomb) return false;
    return type == t.type && len == t.len && key > t.key;
  }

  String get label => switch (type) {
        'single' => '单张 ${c4ValName(key)}',
        'pair' => '对${c4ValName(key)}',
        'triple' => '三个${c4ValName(key)}',
        'straight' => '顺子 ${c4ValName(key - len + 1)}-${c4ValName(key)}',
        'pairs' => '连对 ${c4ValName(key - len ~/ 2 + 1)}-${c4ValName(key)}',
        'plane' => '三顺 ${c4ValName(key - len ~/ 3 + 1)}-${c4ValName(key)}',
        'bomb' => '$len张${c4ValName(key)}炸弹',
        _ => '天王炸',
      };

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'label': label};
  static SkCombo? fromJson(Object? j) {
    if (j is! Map || j['type'] is! String) return null;
    return SkCombo(j['type'] as String, (j['key'] as num).toInt(), (j['len'] as num).toInt());
  }

  @override
  String toString() => label;
}

SkCombo? skClassify(List<String> cards) {
  final n = cards.length;
  if (n == 0) return null;
  final jokers = cards.where(c4IsJoker).length;
  if (jokers == 4 && n == 4) return const SkCombo('kings', 99, 4);
  final vals = [for (final c in cards) c4Val(c)]..sort();
  final cnt = <int, int>{};
  for (final v in vals) {
    cnt[v] = (cnt[v] ?? 0) + 1;
  }
  final keys = cnt.keys.toList()..sort();
  if (keys.length == 1) {
    final v = keys.first;
    if (n == 1) return SkCombo('single', v, 1);
    if (n == 2) return SkCombo('pair', v, 2);
    if (n == 3) return v >= 16 ? null : SkCombo('triple', v, 3);
    if (v >= 16) return null;
    return SkCombo('bomb', v, n);
  }
  if (keys.last > 14) return null;
  for (var i = 1; i < keys.length; i++) {
    if (keys[i] != keys[i - 1] + 1) return null;
  }
  final per = cnt.values.toSet();
  if (per.length != 1) return null;
  final k = per.first;
  if (k == 1 && n >= 5) return SkCombo('straight', keys.last, n);
  if (k == 2 && keys.length >= 3) return SkCombo('pairs', keys.last, n);
  if (k == 3 && keys.length >= 2) return SkCombo('plane', keys.last, n);
  return null;
}

/// Candidate plays beating [table] (any lead when null), cheapest first.
List<List<String>> skCandidates(List<String> hand, SkCombo? table) {
  final g = c4Groups(hand);
  final out = <List<String>>[];
  final seen = <String>{};
  void add(List<String> cards) {
    final c = skClassify(cards);
    if (c == null) return;
    if (table != null && !c.beats(table)) return;
    if (!seen.add('${c.type}${c.key}/${c.len}')) return;
    out.add(cards);
  }

  int count(int v) => g[v]?.length ?? 0;
  final vals = g.keys.toList()..sort();
  final t = table?.type;
  for (final size in [1, 2, 3]) {
    if (table != null && !table.isBomb) {
      final want = {'single': 1, 'pair': 2, 'triple': 3}[t];
      if (want != size) continue;
    } else if (table != null) {
      continue;
    }
    for (final v in vals) {
      if (count(v) >= size) add(g[v]!.sublist(0, size));
    }
  }
  void seqs(int per, int minLen) {
    for (var s = 3; s <= 14; s++) {
      for (var e = s; e <= 14; e++) {
        if (count(e) < per) break;
        if (e - s + 1 < minLen) continue;
        add([for (var v = s; v <= e; v++) ...g[v]!.sublist(0, per)]);
      }
    }
  }

  if (t == null || t == 'straight') seqs(1, 5);
  if (t == null || t == 'pairs') seqs(2, 3);
  if (t == null || t == 'plane') seqs(3, 2);
  for (final v in vals) {
    if (v >= 16) continue;
    for (var k = 4; k <= count(v); k++) {
      add(g[v]!.sublist(0, k));
    }
  }
  final j = hand.where(c4IsJoker).toList();
  if (j.length == 4) add(j);
  int pw(List<String> c) {
    final x = skClassify(c)!;
    return x.isBomb ? 1000 + x.power : x.key;
  }

  out.sort((a, b) => pw(a) - pw(b));
  return out;
}
