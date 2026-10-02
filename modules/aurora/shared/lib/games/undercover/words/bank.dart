import 'words_0.dart';
import 'words_1.dart';
import 'words_2.dart';
import 'words_3.dart';
import 'words_4.dart';
import 'words_5.dart';
import 'words_6.dart';
import 'words_7.dart';
import 'words_8.dart';
import 'words_9.dart';

/// 谁是卧底词库：每项为 '词A|词B'（两个相近但不同的词）。
const List<List<String>> _parts = [
  wordsPart0, wordsPart1, wordsPart2, wordsPart3, wordsPart4,
  wordsPart5, wordsPart6, wordsPart7, wordsPart8, wordsPart9,
];

List<String>? _flat;

/// All raw pairs 'A|B'.
List<String> get undercoverWordBank => _flat ??= [for (final p in _parts) ...p];

/// Pair at [i] split into (a, b).
(String, String) undercoverPair(int i) {
  final s = undercoverWordBank[i];
  final k = s.indexOf('|');
  return (s.substring(0, k), s.substring(k + 1));
}
