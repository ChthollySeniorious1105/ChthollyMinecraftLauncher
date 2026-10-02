/// 斗地主牌型识别与比较（一副牌 / 两副牌）。
///
/// 点数编码：3..14 = 3..A，15 = 2，16 = 小王，17 = 大王。
library;

const _rankChars = '3456789TJQKA2';

int ddzRank(String code) {
  if (code == 'BJ') return 16;
  if (code == 'RJ') return 17;
  return _rankChars.indexOf(code[0]) + 3;
}

String ddzRankName(int r) {
  if (r == 16) return '小王';
  if (r == 17) return '大王';
  if (r == 15) return '2';
  if (r == 14) return 'A';
  if (r == 13) return 'K';
  if (r == 12) return 'Q';
  if (r == 11) return 'J';
  return '$r';
}

int _suitOrder(String c) => c.length < 2 ? 0 : 'DCHS'.indexOf(c[c.length - 1]);

/// Sort cards from big to small (display order).
List<String> ddzSort(Iterable<String> cards) {
  final l = List<String>.of(cards);
  l.sort((a, b) {
    final d = ddzRank(b) - ddzRank(a);
    return d != 0 ? d : _suitOrder(b) - _suitOrder(a);
  });
  return l;
}

List<String> ddzDeck(int decks) {
  final out = <String>[];
  for (var d = 0; d < decks; d++) {
    for (final r in _rankChars.split('')) {
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

class Combo {
  /// single pair triple triple1 triple2 straight pairs plane plane1 plane2 four2 four22 bomb rocket
  final String type;
  final int key;

  /// number of cards
  final int len;
  const Combo(this.type, this.key, this.len);

  bool get isBomb => type == 'bomb' || type == 'rocket';

  String get label {
    switch (type) {
      case 'single':
        return '单张';
      case 'pair':
        return '对子';
      case 'triple':
        return '三张';
      case 'triple1':
        return '三带一';
      case 'triple2':
        return '三带二';
      case 'straight':
        return '顺子';
      case 'pairs':
        return '连对';
      case 'plane':
        return '飞机';
      case 'plane1':
      case 'plane2':
        return '飞机带翅膀';
      case 'four2':
      case 'four22':
        return '四带二';
      case 'bomb':
        return len > 4 ? '$len张炸弹' : '炸弹';
      case 'rocket':
        return len == 4 ? '天王炸' : '王炸';
    }
    return type;
  }

  Map<String, dynamic> toJson() => {'type': type, 'key': key, 'len': len, 'label': label};

  @override
  String toString() => '$type($key,$len)';
}

Map<int, int> _count(Iterable<int> ranks) {
  final m = <int, int>{};
  for (final r in ranks) {
    m[r] = (m[r] ?? 0) + 1;
  }
  return m;
}

bool _consecutive(List<int> sortedDistinct) {
  for (var i = 1; i < sortedDistinct.length; i++) {
    if (sortedDistinct[i] != sortedDistinct[i - 1] + 1) return false;
  }
  return sortedDistinct.last <= 14;
}

/// All valid interpretations of a set of cards (by rank). Empty = invalid.
List<Combo> ddzAnalyze(List<int> ranks, bool two) {
  final total = ranks.length;
  if (total == 0) return const [];
  final cnt = _count(ranks);
  final distinct = cnt.keys.toList()..sort();
  if (!two && total == 2 && cnt[16] == 1 && cnt[17] == 1) return const [Combo('rocket', 17, 2)];
  if (two && total == 4 && cnt[16] == 2 && cnt[17] == 2) return const [Combo('rocket', 17, 4)];
  if (distinct.length == 1) {
    final r = distinct.first;
    if (total == 1) return [Combo('single', r, 1)];
    if (total == 2) return [Combo('pair', r, 2)];
    if (total == 3) return [Combo('triple', r, 3)];
    if (r <= 15 && ((!two && total == 4) || (two && total >= 4 && total <= 8))) {
      return [Combo('bomb', r, total)];
    }
    return const [];
  }
  final res = <Combo>[];
  final counts = cnt.values.toSet();
  if (counts.length == 1) {
    final c = counts.first;
    if (_consecutive(distinct)) {
      if (c == 1 && total >= 5) res.add(Combo('straight', distinct.first, total));
      if (c == 2 && distinct.length >= 3) res.add(Combo('pairs', distinct.first, total));
      if (c == 3 && distinct.length >= 2) res.add(Combo('plane', distinct.first, total));
    }
  }
  // 三带一 / 三带二
  if (total == 4) {
    for (final r in distinct) {
      if (cnt[r] == 3) res.add(Combo('triple1', r, 4));
    }
  }
  if (total == 5 && distinct.length == 2) {
    for (final r in distinct) {
      final other = distinct.firstWhere((x) => x != r);
      if (cnt[r] == 3 && cnt[other] == 2) res.add(Combo('triple2', r, 5));
    }
  }
  // 四带二（仅一副牌）
  if (!two) {
    for (final r in distinct) {
      if (cnt[r] != 4 || r > 15) continue;
      final rest = Map.of(cnt)..remove(r);
      if (total == 6 && !(rest[16] == 1 && rest[17] == 1)) res.add(Combo('four2', r, 6));
      if (total == 8 && rest.values.every((v) => v.isEven)) res.add(Combo('four22', r, 8));
    }
  }
  // 飞机带翅膀
  for (var n = 2; n * 4 <= total; n++) {
    final single = total == n * 4;
    final pair = total == n * 5;
    if (!single && !pair) continue;
    for (var s = 3; s + n - 1 <= 14; s++) {
      var ok = true;
      for (var r = s; r < s + n; r++) {
        if ((cnt[r] ?? 0) < 3) {
          ok = false;
          break;
        }
      }
      if (!ok) continue;
      final rest = Map.of(cnt);
      for (var r = s; r < s + n; r++) {
        rest[r] = rest[r]! - 3;
        if (rest[r] == 0) rest.remove(r);
      }
      if (single) {
        if (!two && rest[16] == 1 && rest[17] == 1) continue;
        res.add(Combo('plane1', s, total));
      } else if (rest.values.every((v) => v.isEven)) {
        res.add(Combo('plane2', s, total));
      }
    }
  }
  return res;
}

bool ddzBeats(Combo a, Combo b, bool two) {
  if (a.type == 'rocket') return b.type != 'rocket';
  if (b.type == 'rocket') return false;
  if (a.type == 'bomb') {
    if (b.type != 'bomb') return true;
    if (two && a.len != b.len) return a.len > b.len;
    return a.key > b.key;
  }
  if (b.type == 'bomb') return false;
  return a.type == b.type && a.len == b.len && a.key > b.key;
}

/// Picks the interpretation used for [ranks] when played on top of [table] (null = leading).
Combo? ddzPick(List<int> ranks, Combo? table, bool two) {
  final all = List.of(ddzAnalyze(ranks, two));
  if (all.isEmpty) return null;
  if (table == null) {
    // prefer bombs, then "pure" shapes, then the highest key
    const pure = {'straight', 'pairs', 'plane'};
    all.sort((x, y) {
      if (x.isBomb != y.isBomb) return x.isBomb ? -1 : 1;
      final px = pure.contains(x.type), py = pure.contains(y.type);
      if (px != py) return px ? -1 : 1;
      return y.key - x.key;
    });
    return all.first;
  }
  final ok = all.where((c) => ddzBeats(c, table, two)).toList()..sort((x, y) => x.key - y.key);
  return ok.isEmpty ? null : ok.first;
}

/// Candidate plays (as rank lists) from a hand that are legal on [table] (null = leading).
/// Sorted small to big; bombs last.
List<List<int>> ddzCandidates(List<int> hand, Combo? table, bool two) {
  final cnt = _count(hand);
  final ranks = cnt.keys.toList()..sort();
  final rocket = two ? (cnt[16] == 2 && cnt[17] == 2) : (cnt[16] == 1 && cnt[17] == 1);
  bool isBombRank(int r) => r <= 15 && (cnt[r] ?? 0) >= 4;
  int prio(int r) {
    var p = r;
    if (isBombRank(r) || (rocket && r >= 16)) p += 1000;
    final c = cnt[r] ?? 0;
    p += c == 1 ? 0 : (c == 2 ? 100 : 200);
    return p;
  }

  List<int>? singles(Set<int> ex, int k) {
    final order = ranks.where((r) => !ex.contains(r)).toList()..sort((a, b) => prio(a) - prio(b));
    final out = <int>[];
    final used = <int, int>{};
    for (var pass = 0; pass < 8 && out.length < k; pass++) {
      for (final r in order) {
        if (out.length >= k) break;
        if ((used[r] ?? 0) < (cnt[r] ?? 0) && (used[r] ?? 0) == pass) {
          used[r] = (used[r] ?? 0) + 1;
          out.add(r);
        }
      }
    }
    return out.length == k ? out : null;
  }

  List<int>? pairs(Set<int> ex, int k) {
    final order = ranks.where((r) => !ex.contains(r) && (cnt[r] ?? 0) >= 2).toList()
      ..sort((a, b) => prio(a) - prio(b));
    final out = <int>[];
    for (final r in order) {
      if (out.length >= k * 2) break;
      out
        ..add(r)
        ..add(r);
    }
    return out.length == k * 2 ? out : null;
  }

  final out = <List<int>>[];
  void add(List<int>? c) {
    if (c != null) out.add(c);
  }

  bool want(String type) => table == null || table.type == type;
  final tl = table?.len ?? 0;

  if (want('single')) {
    for (final r in ranks) {
      add([r]);
    }
  }
  if (want('pair')) {
    for (final r in ranks) {
      if (cnt[r]! >= 2) add([r, r]);
    }
  }
  if (want('triple')) {
    for (final r in ranks) {
      if (cnt[r]! >= 3) add([r, r, r]);
    }
  }
  if (want('triple1')) {
    for (final r in ranks) {
      if (cnt[r]! >= 3) {
        final k = singles({r}, 1);
        if (k != null) add([r, r, r, ...k]);
      }
    }
  }
  if (want('triple2')) {
    for (final r in ranks) {
      if (cnt[r]! >= 3) {
        final k = pairs({r}, 1);
        if (k != null) add([r, r, r, ...k]);
      }
    }
  }
  List<int>? run(int s, int n, int each) {
    if (s + n - 1 > 14) return null;
    final l = <int>[];
    for (var r = s; r < s + n; r++) {
      if ((cnt[r] ?? 0) < each) return null;
      for (var i = 0; i < each; i++) {
        l.add(r);
      }
    }
    return l;
  }

  if (want('straight')) {
    for (var n = 5; n <= 12; n++) {
      if (table != null && n != tl) continue;
      for (var s = 3; s + n - 1 <= 14; s++) {
        add(run(s, n, 1));
      }
    }
  }
  if (want('pairs')) {
    for (var n = 3; n <= 12; n++) {
      if (table != null && n * 2 != tl) continue;
      for (var s = 3; s + n - 1 <= 14; s++) {
        add(run(s, n, 2));
      }
    }
  }
  for (final (type, per) in [('plane', 3), ('plane1', 4), ('plane2', 5)]) {
    if (!want(type)) continue;
    for (var n = 2; n <= 12; n++) {
      if (table != null && n * per != tl) continue;
      for (var s = 3; s + n - 1 <= 14; s++) {
        final base = run(s, n, 3);
        if (base == null) continue;
        final ex = {for (var r = s; r < s + n; r++) r};
        if (type == 'plane') {
          add(base);
        } else if (type == 'plane1') {
          final k = singles(ex, n);
          if (k != null) add([...base, ...k]);
        } else {
          final k = pairs(ex, n);
          if (k != null) add([...base, ...k]);
        }
      }
    }
  }
  if (!two) {
    for (final r in ranks) {
      if (cnt[r] != 4 || r > 15) continue;
      if (want('four2')) {
        final k = singles({r}, 2);
        if (k != null) add([r, r, r, r, ...k]);
      }
      if (want('four22')) {
        final k = pairs({r}, 2);
        if (k != null) add([r, r, r, r, ...k]);
      }
    }
  }
  // bombs
  final bombs = <List<int>>[];
  for (final r in ranks) {
    if (r > 15) continue;
    final c = cnt[r]!;
    if (!two) {
      if (c == 4) bombs.add([r, r, r, r]);
    } else {
      for (var k = 4; k <= c && k <= 8; k++) {
        bombs.add(List.filled(k, r));
      }
    }
  }
  bombs.sort((a, b) => a.length != b.length && two ? a.length - b.length : a.first - b.first);
  out.addAll(bombs);
  if (rocket) out.add(two ? [16, 16, 17, 17] : [16, 17]);

  // validate & dedupe
  final seen = <String>{};
  final res = <List<int>>[];
  for (final c in out) {
    final sorted = List.of(c)..sort();
    final k = sorted.join(',');
    if (seen.contains(k)) continue;
    final combo = ddzPick(sorted, table, two);
    if (combo == null) continue;
    seen.add(k);
    res.add(c);
  }
  return res;
}
