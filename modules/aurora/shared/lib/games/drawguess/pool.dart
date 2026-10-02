import 'words/bank.dart';

export 'words/bank.dart' show DrawWord, drawWordBank, drawWordsByCategory;

/// Max characters of a word (built-in, custom or GM-typed).
const int kMaxWordLen = 12;
const int kMaxCatLen = 8;
const String kCustomCategory = '自定义';
const String kCustomFileHint = '服务器自定义词库不足（words/drawguess.txt），已改用内置词库';

/// Strip all whitespace inside a word.
String normWord(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// Parses the admin-supplied lines (`词语` or `词语|类别`). Invalid lines
/// (empty, longer than [kMaxWordLen]) are skipped; duplicates removed.
List<DrawWord> parseCustomWords(List<String> lines) {
  final out = <DrawWord>[];
  final seen = <String>{};
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final parts = line.split(RegExp(r'[|｜]'));
    final w = normWord(parts.first);
    if (w.isEmpty || w.length > kMaxWordLen) continue;
    var cat = parts.length > 1 ? parts[1].trim() : '';
    if (cat.isEmpty) cat = kCustomCategory;
    if (cat.length > kMaxCatLen) cat = cat.substring(0, kMaxCatLen);
    if (!seen.add(w.toLowerCase())) continue;
    out.add(DrawWord(w, cat));
  }
  return out;
}

/// Builds the word pool for a match.
///
/// [source]: 'both' (内置+自定义), 'custom' (仅自定义), 'builtin' (仅内置).
/// [log] receives a warning when 仅自定义 has fewer than 3 valid words.
List<DrawWord> buildWordPool(String source, List<String> customLines, void Function(String) log) {
  final builtIn = drawWordBank;
  if (source == 'builtin') return List.of(builtIn);
  final custom = parseCustomWords(customLines);
  if (source == 'custom') {
    if (custom.length < 3) {
      log(kCustomFileHint);
      return List.of(builtIn);
    }
    return custom;
  }
  final known = {for (final w in builtIn) w.word.toLowerCase()};
  return [
    ...builtIn,
    for (final w in custom)
      if (!known.contains(w.word.toLowerCase())) w,
  ];
}
