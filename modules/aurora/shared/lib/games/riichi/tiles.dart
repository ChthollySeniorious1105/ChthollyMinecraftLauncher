/// Tile model for riichi mahjong.
///
/// Physical tiles are ints (ids). kind = id >> 2 (0..33), copy = id & 3.
///   kinds 0..8 = 1m..9m, 9..17 = 1p..9p, 18..26 = 1s..9s,
///   27..30 = 东南西北, 31..33 = 白发中.
/// Red fives are copy 0 of kinds 4 / 13 / 22 when akadora is enabled.
library;

int kindOf(int id) => id >> 2;
int copyOf(int id) => id & 3;

const int kEast = 27, kSouth = 28, kWest = 29, kNorth = 30;
const int kHaku = 31, kHatsu = 32, kChun = 33;

bool isHonor(int k) => k >= 27;
bool isSuited(int k) => k < 27;
bool isTerminal(int k) => k < 27 && (k % 9 == 0 || k % 9 == 8);
bool isYaochu(int k) => isHonor(k) || isTerminal(k);
bool isSimple(int k) => !isYaochu(k);
bool isDragon(int k) => k >= 31;
bool isWind(int k) => k >= 27 && k <= 30;
int suitOf(int k) => k < 27 ? k ~/ 9 : 3;
int numOf(int k) => k < 27 ? k % 9 + 1 : k - 26;

/// 万象修罗 百搭牌: four extra tiles (ids 136..139) that are not any real
/// tile. Never in the wall; one is dealt to each player.
const int kWildBase = 136;
bool isWildId(int id) => id >= kWildBase;

const List<int> yaochuKinds = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];

/// Kind code used by the client MahjongTile ('1m', '7z', ...).
String kindCode(int k) {
  if (k < 27) return '${k % 9 + 1}${'mps'[k ~/ 9]}';
  return '${k - 26}z';
}

/// Parse '1m' / '0p' / '5z' to a kind (red 0 -> 5). Returns -1 when invalid.
int parseKind(String code) {
  if (code.length != 2) return -1;
  final n = int.tryParse(code[0]);
  if (n == null) return -1;
  final s = 'mpsz'.indexOf(code[1]);
  if (s < 0) return -1;
  if (s == 3) return (n >= 1 && n <= 7) ? 27 + n - 1 : -1;
  final nn = n == 0 ? 5 : n;
  return s * 9 + nn - 1;
}

/// Parse a compact hand string like '123m456p789s11z' into kinds.
List<int> parseHand(String s) {
  final out = <int>[];
  final pending = <String>[];
  for (final ch in s.split('')) {
    if ('mpsz'.contains(ch)) {
      for (final d in pending) {
        out.add(parseKind('$d$ch'));
      }
      pending.clear();
    } else if (ch.trim().isNotEmpty) {
      pending.add(ch);
    }
  }
  return out;
}

const List<String> kindNames = [
  '一万', '二万', '三万', '四万', '五万', '六万', '七万', '八万', '九万',
  '一筒', '二筒', '三筒', '四筒', '五筒', '六筒', '七筒', '八筒', '九筒',
  '一索', '二索', '三索', '四索', '五索', '六索', '七索', '八索', '九索',
  '东', '南', '西', '北', '白', '发', '中',
];

const List<String> windNames = ['东', '南', '西', '北'];

/// Dora kind indicated by indicator kind [k]. In sanma 1m -> 9m.
int doraFromIndicator(int k, {bool sanma = false}) {
  if (k < 27) {
    if (sanma && k == 0) return 8;
    if (sanma && k == 8) return 0;
    return k ~/ 9 * 9 + (k % 9 + 1) % 9;
  }
  if (k <= 30) return 27 + (k - 27 + 1) % 4;
  return 31 + (k - 31 + 1) % 3;
}

/// Tile set configuration for one game.
class TileSet {
  final bool sanma;
  final bool aka;
  const TileSet({this.sanma = false, this.aka = true});

  bool kindInGame(int k) => !(sanma && k >= 1 && k <= 7);

  bool isRed(int id) {
    if (!aka || copyOf(id) != 0) return false;
    final k = kindOf(id);
    if (k == 13 || k == 22) return true;
    return k == 4 && !sanma;
  }

  List<int> allIds() => [
        for (var id = 0; id < 136; id++)
          if (kindInGame(kindOf(id))) id
      ];

  String code(int id) {
    final k = kindOf(id);
    if (isRed(id)) return '0${'mps'[k ~/ 9]}';
    return kindCode(k);
  }
}

/// Counts per kind (length 34) of a list of tile ids.
List<int> countsOfIds(Iterable<int> ids) {
  final c = List<int>.filled(34, 0);
  for (final id in ids) {
    c[kindOf(id)]++;
  }
  return c;
}

List<int> countsOfKinds(Iterable<int> kinds) {
  final c = List<int>.filled(34, 0);
  for (final k in kinds) {
    c[k]++;
  }
  return c;
}

/// Sort key: by kind, red five sorted just before normal fives.
int tileSortKey(int id) => kindOf(id) * 4 + copyOf(id);
