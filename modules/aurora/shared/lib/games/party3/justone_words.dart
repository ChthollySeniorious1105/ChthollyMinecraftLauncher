import 'justone_words_a.dart';
import 'justone_words_b.dart';
import 'justone_words_c.dart';
import 'p3_util.dart';

/// A Just One mystery word with its category and bot associations.
class JustOneWord {
  final String word;
  final String category;
  final List<String> assoc;
  const JustOneWord(this.word, this.category, this.assoc);
}

List<JustOneWord> _parseBank(String data) => [
      for (final p in p3Lines(data))
        if (p.length >= 2 && p[0].isNotEmpty)
          JustOneWord(p[0], p[1], p.length > 2 ? [for (final a in p[2].split(RegExp(r'[,，]'))) if (a.trim().isNotEmpty) a.trim()] : const []),
    ];

/// Built-in bank (≥ 800 words).
final List<JustOneWord> justOneBank = () {
  final seen = <String>{};
  return [
    for (final w in [..._parseBank(justOneWordsA), ..._parseBank(justOneWordsB), ..._parseBank(justOneWordsC)])
      if (seen.add(w.word)) w,
  ];
}();

const int kJustOneMaxWord = 10;

/// Server lines `词` / `词|类别` / `词|类别|联想1,联想2` (words/justone.txt).
List<JustOneWord> parseJustOneLines(List<String> lines) {
  final out = <JustOneWord>[];
  final seen = <String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final parts = line.split(RegExp(r'[|｜]'));
    final w = p3Norm(parts[0]);
    if (w.isEmpty || w.runes.length > kJustOneMaxWord || !seen.add(w)) continue;
    var cat = parts.length > 1 ? parts[1].trim() : '';
    if (cat.isEmpty) cat = '自定义';
    if (cat.length > 8) cat = cat.substring(0, 8);
    final assoc = parts.length > 2
        ? [
            for (final a in parts[2].split(RegExp(r'[,，、\s]+')))
              if (a.trim().isNotEmpty && !shareChar(a.trim(), w)) a.trim()
          ]
        : <String>[];
    out.add(JustOneWord(w, cat, assoc));
  }
  return out;
}
