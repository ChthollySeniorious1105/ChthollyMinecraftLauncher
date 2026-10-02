/// 百家乐 (punto banco) rules.
library;

import 'cards.dart';

/// Point value: A=1, 2-9 face, 10/J/Q/K = 0.
int bacValue(String c) {
  final t = c3Trick(c); // 2..14
  if (t == 14) return 1;
  if (t >= 10) return 0;
  return t;
}

int bacTotal(List<String> cards) => cards.fold(0, (a, c) => a + bacValue(c)) % 10;

/// Whether the player (闲) draws a third card given his two-card total.
bool bacPlayerDraws(int playerTotal) => playerTotal <= 5;

/// Whether the banker (庄) draws a third card.
/// [playerThird] is the value (0-9) of the player's third card or null if the
/// player stood.
bool bacBankerDraws(int bankerTotal, int? playerThird) {
  if (playerThird == null) return bankerTotal <= 5;
  switch (bankerTotal) {
    case 0:
    case 1:
    case 2:
      return true;
    case 3:
      return playerThird != 8;
    case 4:
      return playerThird >= 2 && playerThird <= 7;
    case 5:
      return playerThird >= 4 && playerThird <= 7;
    case 6:
      return playerThird == 6 || playerThird == 7;
    default:
      return false;
  }
}

class BacCoup {
  final List<String> player;
  final List<String> banker;
  const BacCoup(this.player, this.banker);
  int get p => bacTotal(player);
  int get b => bacTotal(banker);

  /// 'B' 庄 / 'P' 闲 / 'T' 和
  String get winner => p > b ? 'P' : (b > p ? 'B' : 'T');
  bool get playerPair => c3Trick(player[0]) == c3Trick(player[1]);
  bool get bankerPair => c3Trick(banker[0]) == c3Trick(banker[1]);
  bool get natural => (bacTotal(player.sublist(0, 2)) >= 8) || (bacTotal(banker.sublist(0, 2)) >= 8);
}

/// Deals one coup from [draw] (which pops the next card of the shoe).
BacCoup bacDeal(String Function() draw) {
  final p = [draw()];
  final b = [draw()];
  p.add(draw());
  b.add(draw());
  final pt = bacTotal(p), bt = bacTotal(b);
  if (pt >= 8 || bt >= 8) return BacCoup(p, b); // 例牌，都不补
  int? third;
  if (bacPlayerDraws(pt)) {
    final c = draw();
    p.add(c);
    third = bacValue(c);
  }
  if (bacBankerDraws(bt, third)) b.add(draw());
  return BacCoup(p, b);
}

/// Net win (profit, not including returned stake) for [bet] on [area] given
/// the coup outcome. Push returns 0. Losing returns -bet.
/// Areas: 'B' 庄 (0.95), 'P' 闲 (1:1), 'T' 和 (8:1), 'PP' 闲对 / 'BP' 庄对 (11:1).
/// On a tie, 庄/闲 bets push.
double bacPayout(String area, int bet, BacCoup c) {
  switch (area) {
    case 'B':
      if (c.winner == 'T') return 0;
      return c.winner == 'B' ? bet * 0.95 : -bet.toDouble();
    case 'P':
      if (c.winner == 'T') return 0;
      return c.winner == 'P' ? bet.toDouble() : -bet.toDouble();
    case 'T':
      return c.winner == 'T' ? bet * 8.0 : -bet.toDouble();
    case 'PP':
      return c.playerPair ? bet * 11.0 : -bet.toDouble();
    case 'BP':
      return c.bankerPair ? bet * 11.0 : -bet.toDouble();
  }
  return 0;
}

const Map<String, String> bacAreaName = {'B': '庄', 'P': '闲', 'T': '和', 'PP': '闲对', 'BP': '庄对'};
