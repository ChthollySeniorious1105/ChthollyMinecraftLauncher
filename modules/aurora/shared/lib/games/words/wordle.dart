import '../../src/engine.dart';
import 'race.dart';
import 'wordle_en_data.dart';

/// Parsed English word lists (lazy: parsed on first use, not at app start).
class WordleDict {
  static late final List<String> answers = _split(wordleEnAnswers);
  static late final Set<String> guesses = {..._split(wordleEnGuesses), ...answers};
  static late final List<String> guessList = guesses.toList();

  static List<String> _split(String s) => [for (final w in s.split(RegExp(r'\s+'))) if (w.length == 5) w];
}

/// Wordle colouring: 'g' right letter right place, 'y' in word elsewhere,
/// 'x' absent. Duplicate letters are handled like the original: each answer
/// letter can satisfy at most one guess letter, greens first.
String wordleMark(String guess, String answer) {
  final n = guess.length;
  final res = List.filled(n, 'x');
  final left = <int, int>{};
  for (var i = 0; i < n; i++) {
    if (guess.codeUnitAt(i) == answer.codeUnitAt(i)) {
      res[i] = 'g';
    } else {
      final c = answer.codeUnitAt(i);
      left[c] = (left[c] ?? 0) + 1;
    }
  }
  for (var i = 0; i < n; i++) {
    if (res[i] == 'g') continue;
    final c = guess.codeUnitAt(i);
    final k = left[c] ?? 0;
    if (k > 0) {
      res[i] = 'y';
      left[c] = k - 1;
    }
  }
  return res.join();
}

class WordleGame extends WordRace {
  WordleGame(super.setup);

  @override
  List<String> get answerPool => WordleDict.answers;

  @override
  List<String> get probePool => WordleDict.answers;

  @override
  String? get strongOpener => const ['raise', 'crane', 'slate', 'trace', 'arose'][rng.nextInt(5)];

  @override
  String normalize(Object? raw) {
    final w = asStr(raw).trim().toLowerCase();
    if (w.length != 5 || !RegExp(r'^[a-z]{5}$').hasMatch(w)) throw GameError('请输入 5 个英文字母');
    if (!WordleDict.guesses.contains(w)) throw GameError('「${w.toUpperCase()}」不在词库中');
    return w;
  }

  @override
  String mark(String guess, String answer) => wordleMark(guess, answer);

  @override
  String display(String word) => word.toUpperCase();
}
