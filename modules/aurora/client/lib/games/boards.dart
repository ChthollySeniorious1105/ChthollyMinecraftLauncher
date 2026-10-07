import 'package:flutter/material.dart';

import '../widgets/common.dart';
import 'riichi/boards.dart';
import 'sichuan/boards.dart';
import 'poker/boards.dart';
import 'uno/boards.dart';
import 'chess/boards.dart';
import 'military/boards.dart';
import 'race/boards.dart';
import 'tabletop/boards.dart';
import 'social/boards.dart';
import 'undercover/boards.dart';
import 'dice2/boards.dart';
import 'arcade/boards.dart';
import 'onenight/boards.dart';
import 'cards3/boards.dart';
import 'hkmj/boards.dart';
import 'taiwan/boards.dart';
import 'party2/boards.dart';
import 'monopoly/boards.dart';
import 'euro/boards.dart';
import 'abstract/boards.dart';
import 'shogi/boards.dart';
import 'cncards/boards.dart';
import 'tricks/boards.dart';
import 'mcr/boards.dart';
import 'drawguess/boards.dart';
import 'werewolf/boards.dart';
import 'teamcards/boards.dart';
import 'pokerplus/boards.dart';
import 'classic/boards.dart';
import 'mahjong2/boards.dart';
import 'cards4/boards.dart';
import 'abstract2/boards.dart';
import 'euro2/boards.dart';
import 'light/boards.dart';
import 'party3/boards.dart';
import 'party4/boards.dart';
import 'arcade2/boards.dart';
import 'family/boards.dart';
import 'duel2/boards.dart';
import 'words/boards.dart';
import 'bang/boards.dart';

/// Game id -> board widget. Each game package owns its own boards.dart map.
final Map<String, BoardBuilder> boardRegistry = {
  ...party4Boards,
  ...riichiBoards,
  ...sichuanBoards,
  ...pokerBoards,
  ...unoBoards,
  ...chessBoards,
  ...militaryBoards,
  ...raceBoards,
  ...tabletopBoards,
  ...socialBoards,
  ...undercoverBoards,
  ...dice2Boards,
  ...arcadeBoards,
  ...onenightBoards,
  ...cards3Boards,
  ...hkmjBoards,
  ...taiwanBoards,
  ...party2Boards,
  ...monopolyBoards,
  ...euroBoards,
  ...abstractBoards,
  ...shogiBoards,
  ...cncardsBoards,
  ...tricksBoards,
  ...mcrBoards,
  ...drawguessBoards,
  ...werewolfBoards,
  ...teamcardsBoards,
  ...pokerplusBoards,
  ...classicBoards,
  ...mahjong2Boards,
  ...cards4Boards,
  ...abstract2Boards,
  ...euro2Boards,
  ...lightBoards,
  ...party3Boards,
  ...arcade2Boards,
  ...familyBoards,
  ...duel2Boards,
  ...wordsBoards,
  ...bangBoards,
};

Widget buildBoard(GameContext g) {
  final b = boardRegistry[g.state.game];
  if (b == null) return Center(child: Text('客户端不支持该游戏：${g.state.game}，请更新客户端'));
  return b(g);
}
