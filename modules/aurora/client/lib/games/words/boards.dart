import '../../widgets/common.dart';
import 'words_board.dart';

/// Wordle / 汉兜
final Map<String, BoardBuilder> wordsBoards = {
  'wordle': (g) => WordsBoard(g, handle: false),
  'handle': (g) => WordsBoard(g, handle: true),
};
