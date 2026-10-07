import '../../src/engine.dart';
import 'handle_data.dart';
import 'race.dart';

/// One idiom with its pinyin split into initial / final / tone per character.
class HandleIdiom {
  final String word;
  final List<String> ini; // '' for zero-initial syllables
  final List<String> fin; // ü written as v
  final List<String> tone; // '1'..'4', '5' = neutral
  const HandleIdiom(this.word, this.ini, this.fin, this.tone);

  List<List<String>> get py => [for (var i = 0; i < 4; i++) [ini[i], fin[i], tone[i]]];
}

/// Parsed 汉兜 dictionary (lazy: parsed on first use, not at app start).
class HandleDict {
  static late final List<HandleIdiom> all = _parse();
  static late final Map<String, HandleIdiom> byWord = {for (final i in all) i.word: i};
  static late final List<String> common = [for (var i = 0; i < kHandleCommonCount && i < all.length; i++) all[i].word];

  static List<HandleIdiom> _parse() {
    final out = <HandleIdiom>[];
    for (final item in handleData.split(RegExp(r'\s+'))) {
      final p = item.split('|');
      if (p.length != 2 || p[0].runes.length != 4) continue;
      final syl = p[1].split(',');
      if (syl.length != 4) continue;
      final ini = <String>[], fin = <String>[], tone = <String>[];
      var ok = true;
      for (final s in syl) {
        final q = s.split('-');
        if (q.length != 3) {
          ok = false;
          break;
        }
        ini.add(q[0]);
        fin.add(q[1]);
        tone.add(q[2]);
      }
      if (ok) out.add(HandleIdiom(p[0], ini, fin, tone));
    }
    return out;
  }
}

/// Wordle-style marking of one layer: 'g' same position, 'y' present
/// elsewhere (each answer item used once), 'x' absent. Empty guess items
/// (zero initials) get '-'; empty answer items never match.
List<String> _layer(List<String> g, List<String> a) {
  final res = List.filled(g.length, 'x');
  final left = <String, int>{};
  for (var i = 0; i < g.length; i++) {
    if (g[i].isEmpty) {
      res[i] = '-';
    } else if (g[i] == a[i]) {
      res[i] = 'g';
    } else if (a[i].isNotEmpty) {
      left[a[i]] = (left[a[i]] ?? 0) + 1;
    }
  }
  // answer items whose guess slot was empty are still available elsewhere
  for (var i = 0; i < g.length; i++) {
    if (g[i].isEmpty && a[i].isNotEmpty) left[a[i]] = (left[a[i]] ?? 0) + 1;
  }
  for (var i = 0; i < g.length; i++) {
    if (res[i] != 'x') continue;
    final k = left[g[i]] ?? 0;
    if (k > 0) {
      res[i] = 'y';
      left[g[i]] = k - 1;
    }
  }
  return res;
}

/// 汉兜 feedback: 16 chars, 4 per character cell = [字, 声母, 韵母, 声调],
/// each 'g' / 'y' / 'x' ('-' = no initial).
String handleMark(String guess, String answer) {
  final g = HandleDict.byWord[guess]!, a = HandleDict.byWord[answer]!;
  final ch = _layer([for (final r in g.word.runes) String.fromCharCode(r)], [for (final r in a.word.runes) String.fromCharCode(r)]);
  final ini = _layer(g.ini, a.ini);
  final fin = _layer(g.fin, a.fin);
  final tone = _layer(g.tone, a.tone);
  final sb = StringBuffer();
  for (var i = 0; i < 4; i++) {
    sb
      ..write(ch[i])
      ..write(ini[i])
      ..write(fin[i])
      ..write(tone[i]);
  }
  return sb.toString();
}

class HandleGame extends WordRace {
  HandleGame(super.setup);

  @override
  List<String> get answerPool => HandleDict.common;

  @override
  String normalize(Object? raw) {
    final w = asStr(raw).replaceAll(RegExp(r'[\s,，。.!！?？、]'), '');
    if (w.isEmpty) throw GameError('请输入四字成语');
    if (w.runes.length != 4) throw GameError('请输入四个汉字（你输入了 ${w.runes.length} 个字）');
    if (!HandleDict.byWord.containsKey(w)) throw GameError('「$w」不在成语词库中');
    return w;
  }

  @override
  String mark(String guess, String answer) => handleMark(guess, answer);

  @override
  Map<String, dynamic> wordInfo(String word) => {'w': word, 'py': HandleDict.byWord[word]?.py ?? const []};
}
