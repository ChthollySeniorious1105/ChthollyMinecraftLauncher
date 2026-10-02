/// Tile helpers for 国标麻将 / 广东推倒胡 (private to the mcr package).
///
/// Tiles are ints: 0..26 numbers (suit = t ~/ 9: 0 万 m, 1 筒 p, 2 条 s; rank = t % 9 + 1),
/// 27..30 东南西北, 31 白 32 发 33 中, 34..41 flowers 春夏秋冬梅兰竹菊.
library;

const int kKinds = 34;
const int kFlowerBase = 34;

const List<String> suitNames = ['万', '筒', '条'];
const String _suitLetters = 'mps';
const List<String> honorNames = ['东', '南', '西', '北', '白', '发', '中'];
const List<String> flowerNames = ['春', '夏', '秋', '冬', '梅', '兰', '竹', '菊'];
const List<String> windNames = ['东', '南', '西', '北'];

bool isFlower(int t) => t >= kFlowerBase && t < kFlowerBase + 8;
bool isHonor(int t) => t >= 27 && t < 34;
bool isWind(int t) => t >= 27 && t <= 30;
bool isDragon(int t) => t >= 31 && t <= 33;
bool isNumber(int t) => t >= 0 && t < 27;
int suitOf(int t) => t < 27 ? t ~/ 9 : 3;
int rankOf(int t) => t < 27 ? t % 9 + 1 : 0;
bool isTerminal(int t) => t < 27 && (t % 9 == 0 || t % 9 == 8);
bool isYaojiu(int t) => isTerminal(t) || isHonor(t);
int tileOf(int suit, int rank) => suit * 9 + rank - 1;

String tileCode(int t) {
  if (t < 0) return 'back';
  if (t < 27) return '${t % 9 + 1}${_suitLetters[t ~/ 9]}';
  if (t < 34) return '${t - 26}z';
  if (t < 42) return '${t - 33}f';
  return 'back';
}

int tileFromCode(Object? c) {
  if (c is! String || c.length != 2) return -1;
  final r = int.tryParse(c[0]);
  if (r == null) return -1;
  final s = _suitLetters.indexOf(c[1]);
  if (s >= 0) return r >= 1 && r <= 9 ? s * 9 + r - 1 : -1;
  if (c[1] == 'z') return r >= 1 && r <= 7 ? 26 + r : -1;
  if (c[1] == 'f') return r >= 1 && r <= 8 ? 33 + r : -1;
  return -1;
}

String tileName(int t) {
  if (t < 0) return '?';
  if (t < 27) return '${'一二三四五六七八九'[t % 9]}${suitNames[t ~/ 9]}';
  if (t < 34) return honorNames[t - 27];
  if (t < 42) return flowerNames[t - 34];
  return '?';
}

/// Parse "123m456p11z" style strings into tile ids (tests / debugging).
List<int> parseTiles(String s) {
  final out = <int>[];
  final digits = <int>[];
  for (final ch in s.split('')) {
    if ('mpszf'.contains(ch)) {
      for (final d in digits) {
        out.add(tileFromCode('$d$ch'));
      }
      digits.clear();
    } else if (ch.trim().isNotEmpty) {
      digits.add(int.parse(ch));
    }
  }
  return out;
}

List<int> countsOf(Iterable<int> tiles) {
  final c = List<int>.filled(kKinds, 0);
  for (final t in tiles) {
    if (t >= 0 && t < kKinds) c[t]++;
  }
  return c;
}

int countTotal(List<int> c) {
  var n = 0;
  for (final x in c) {
    n += x;
  }
  return n;
}

/// A called / declared meld.
class Meld {
  /// 'chi' 吃, 'peng' 碰, 'mgang' 直杠(明杠), 'bgang' 补杠(明杠), 'agang' 暗杠
  String kind;

  /// For chi: the lowest tile of the sequence; otherwise the tile.
  final int tile;

  /// The tile taken from another player (-1 for 暗杠).
  final int claimed;

  /// Seat the tile came from (-1 for 暗杠).
  final int from;
  Meld(this.kind, this.tile, {this.claimed = -1, this.from = -1});

  bool get isKong => kind == 'mgang' || kind == 'bgang' || kind == 'agang';
  bool get isChi => kind == 'chi';
  bool get concealed => kind == 'agang';
  int get size => isKong ? 4 : 3;
  List<int> get tiles => isChi ? [tile, tile + 1, tile + 2] : List.filled(size, tile);

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'tiles': [for (final t in tiles) tileCode(t)],
        'claimed': claimed >= 0 ? tileCode(claimed) : null,
        'from': from,
      };
}

/// The six 组合龙 (knitted straight) patterns: each is 9 tile ids.
final List<List<int>> knittedPatterns = () {
  const perms = [
    [0, 1, 2],
    [0, 2, 1],
    [1, 0, 2],
    [1, 2, 0],
    [2, 0, 1],
    [2, 1, 0],
  ];
  return [
    for (final p in perms)
      [
        for (var k = 0; k < 3; k++)
          for (var r = k + 1; r <= 9; r += 3) tileOf(p[k], r)
      ]
  ];
}();

const List<int> yaojiuKinds = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];
