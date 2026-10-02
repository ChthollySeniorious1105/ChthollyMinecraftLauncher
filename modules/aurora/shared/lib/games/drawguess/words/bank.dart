import 'words_a.dart';
import 'words_b.dart';
import 'words_c.dart';
import 'words_d.dart';
import 'words_e.dart';

/// One drawable word with its category hint.
class DrawWord {
  final String word;
  final String category;
  const DrawWord(this.word, this.category);
}

List<DrawWord>? _bank;
Map<String, List<String>>? _byCat;

/// All words (deduplicated, first occurrence wins).
List<DrawWord> get drawWordBank {
  if (_bank != null) return _bank!;
  final seen = <String>{};
  final out = <DrawWord>[];
  for (final part in [drawWordsA, drawWordsB, drawWordsC, drawWordsD, drawWordsE]) {
    for (final e in part.entries) {
      for (final w in e.value.split(RegExp(r'\s+'))) {
        if (w.isEmpty || !seen.add(w)) continue;
        out.add(DrawWord(w, e.key));
      }
    }
  }
  return _bank = out;
}

/// Category -> words.
Map<String, List<String>> get drawWordsByCategory {
  if (_byCat != null) return _byCat!;
  final m = <String, List<String>>{};
  for (final w in drawWordBank) {
    (m[w.category] ??= []).add(w.word);
  }
  return _byCat = m;
}

/// Raw word count including duplicates (used by tests to verify uniqueness).
int get drawWordRawCount {
  var n = 0;
  for (final part in [drawWordsA, drawWordsB, drawWordsC, drawWordsD, drawWordsE]) {
    for (final v in part.values) {
      n += v.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    }
  }
  return n;
}
