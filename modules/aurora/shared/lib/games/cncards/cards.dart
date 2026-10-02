/// Card helpers shared by 锄大地 / 炸金花 / 斗牛 / 十三水.
///
/// Codes follow PlayingCard: rank in "23456789TJQKA" + suit in "SHDC", e.g. 'TH' = ♥10.
library;

const String cnRanks = '23456789TJQKA';
const String cnSuits = 'SHDC';

/// Natural rank 2..14 (A = 14).
int cnRank(String code) => cnRanks.indexOf(code[0]) + 2;
String cnSuit(String code) => code[code.length - 1];

List<String> cnDeck() => [for (final r in cnRanks.split('')) for (final s in cnSuits.split('')) '$r$s'];

const Map<String, String> cnSuitSym = {'S': '♠', 'H': '♥', 'D': '♦', 'C': '♣'};

String cnRankName(int r) => switch (r) {
      14 || 1 => 'A',
      13 => 'K',
      12 => 'Q',
      11 => 'J',
      10 => '10',
      _ => '$r',
    };

/// Human readable card, e.g. '♥10'.
String cnCardName(String code) => '${cnSuitSym[cnSuit(code)] ?? ''}${cnRankName(cnRank(code))}';

/// All k-subsets of indices 0..n-1 (lexicographic).
Iterable<List<int>> cnCombos(int n, int k) sync* {
  if (k > n || k < 0) return;
  final idx = List<int>.generate(k, (i) => i);
  while (true) {
    yield List<int>.of(idx);
    var i = k - 1;
    while (i >= 0 && idx[i] == n - k + i) {
      i--;
    }
    if (i < 0) return;
    idx[i]++;
    for (var j = i + 1; j < k; j++) {
      idx[j] = idx[j - 1] + 1;
    }
  }
}

/// Packs a category and up to 5 rank keys (each < 16) into one comparable int.
int cnPack(int cat, List<int> ks) {
  var v = cat;
  for (var i = 0; i < 5; i++) {
    v = (v << 4) | (i < ks.length ? ks[i] : 0);
  }
  return v;
}

int cnCategory(int packed) => packed >> 20;
