import 'games/riichi/defs.dart';
import 'games/sichuan/defs.dart';
import 'games/poker/defs.dart';
import 'games/uno/defs.dart';
import 'games/chess/defs.dart';
import 'games/military/defs.dart';
import 'games/race/defs.dart';
import 'games/tabletop/defs.dart';
import 'games/social/defs.dart';
import 'games/undercover/defs.dart';
import 'games/classic/defs.dart';
import 'games/pokerplus/defs.dart';
import 'games/teamcards/defs.dart';
import 'games/werewolf/defs.dart';
import 'games/drawguess/defs.dart';
import 'games/mcr/defs.dart';
import 'games/tricks/defs.dart';
import 'games/cncards/defs.dart';
import 'games/shogi/defs.dart';
import 'games/abstract/defs.dart';
import 'games/euro/defs.dart';
import 'games/monopoly/defs.dart';
import 'games/party2/defs.dart';
import 'games/taiwan/defs.dart';
import 'games/hkmj/defs.dart';
import 'games/cards3/defs.dart';
import 'games/onenight/defs.dart';
import 'games/arcade/defs.dart';
import 'games/dice2/defs.dart';
import 'games/mahjong2/defs.dart';
import 'games/cards4/defs.dart';
import 'games/abstract2/defs.dart';
import 'games/euro2/defs.dart';
import 'games/light/defs.dart';
import 'games/party3/defs.dart';
import 'src/engine.dart';
import 'games/party4/defs.dart';
import 'games/arcade2/defs.dart';
import 'games/family/defs.dart';
import 'games/duel2/defs.dart';
import 'games/words/defs.dart';
import 'games/bang/defs.dart';

/// All game types known to the server and clients. Order = lobby order.
/// Each game package owns its own defs.dart list; add games there, not here.
final List<GameDef> gameRegistry = [
  ...party4Games,
  ...riichiGames,
  ...sichuanGames,
  ...mcrGames,
  ...taiwanGames,
  ...hkmjGames,
  ...pokerGames,
  ...unoGames,
  ...chessGames,
  ...militaryGames,
  ...raceGames,
  ...tabletopGames,
  ...socialGames,
  ...undercoverGames,
  ...classicGames,
  ...pokerplusGames,
  ...teamcardsGames,
  ...werewolfGames,
  ...drawguessGames,
  ...tricksGames,
  ...cncardsGames,
  ...shogiGames,
  ...abstractGames,
  ...euroGames,
  ...monopolyGames,
  ...party2Games,
  ...cards3Games,
  ...onenightGames,
  ...arcadeGames,
  ...dice2Games,
  ...mahjong2Games,
  ...cards4Games,
  ...abstract2Games,
  ...euro2Games,
  ...lightGames,
  ...party3Games,
  ...arcade2Games,
  ...familyGames,
  ...duel2Games,
  ...wordsGames,
  ...bangGames,
];

GameDef? findGame(String id) {
  for (final g in gameRegistry) {
    if (g.id == id) return g;
  }
  return null;
}
