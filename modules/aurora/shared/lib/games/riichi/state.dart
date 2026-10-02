/// Per-player state for a riichi hand.
library;

import 'tiles.dart';
import 'yaku.dart';

class Meld {
  /// 'chi', 'pon', 'minkan' (daiminkan), 'ankan', 'kakan'.
  String type;
  final List<int> tiles; // ids, called tile included
  final int calledId; // -1 for ankan
  final int from; // seat the tile was called from, -1 for ankan
  Meld(this.type, this.tiles, this.calledId, this.from);

  bool get isKan => type == 'minkan' || type == 'ankan' || type == 'kakan';
  bool get open => type != 'ankan';
  int get kind => tiles.map(kindOf).reduce((a, b) => a < b ? a : b);

  Group toGroup() {
    if (type == 'chi') return Group(0, kind, true);
    if (isKan) return Group(2, kindOf(tiles.first), open);
    return Group(1, kindOf(tiles.first), true);
  }
}

class Discard {
  final int id;
  final bool tsumogiri;
  bool riichi; // sideways riichi declaration tile
  bool called = false; // taken by chi/pon/kan
  bool ronned = false; // won on (bloodbath)
  bool dark; // 暗夜之战: face down
  bool locked = false; // 暗夜之战: locked face down forever
  Discard(this.id, {this.tsumogiri = false, this.riichi = false, this.dark = false});
}

class PState {
  final List<int> hand = [];
  final List<Meld> melds = [];
  final List<Discard> river = [];
  final List<int> kita = [];
  int score;
  bool riichi = false;
  bool doubleRiichi = false;
  bool ippatsu = false;
  bool riichiFuriten = false;
  bool tempFuriten = false;
  bool won = false; // bloodbath: already won this hand
  int winTile = -1; // bloodbath: the tile this seat won on (shown face up)
  bool wonTsumo = false;
  int riichiRiverIndex = -1;

  /// 包牌: seat liable for [paoYaku] (-1 = none).
  int pao = -1;
  String paoYaku = '';

  /// Kinds that may not be discarded this turn (kuikae).
  Set<int> forbidden = {};

  PState(this.score);

  void resetHand() {
    hand.clear();
    melds.clear();
    river.clear();
    kita.clear();
    riichi = false;
    doubleRiichi = false;
    ippatsu = false;
    riichiFuriten = false;
    tempFuriten = false;
    won = false;
    winTile = -1;
    wonTsumo = false;
    riichiRiverIndex = -1;
    pao = -1;
    paoYaku = '';
    forbidden = {};
  }

  bool get closed => melds.every((m) => !m.open);
}
