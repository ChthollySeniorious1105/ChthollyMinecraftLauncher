import '../../src/engine.dart';

/// 德国心脏病 (Halli Galli).
///
/// Card encoding: `fruit * 10 + count` (fruit 0..3 = 草莓/香蕉/青柠/李子, count 1..5).
/// Everyone may `ring` at any time (not listed in [waitingFor]; only the
/// flipper is). Rings carry the `ver` the client saw — a stale ring (someone
/// was faster, or a new card was flipped) is rejected without penalty.
/// Bot rings are scheduled with a random reaction delay via [GameHost.schedule].
class HalliGalli extends GameEngine {
  HalliGalli(super.setup);

  static const fruitNames = ['草莓', '香蕉', '青柠', '李子'];
  static const countDist = [1, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5];
  static const maxFlipsDefault = 600;

  late List<List<int>> down; // face-down piles; last = top
  late List<List<int>> up; // face-up piles; last = top
  int turn = 0;
  int flips = 0;
  int ver = 0;
  late int maxFlips;
  late int reactMin;
  bool over = false;
  Map<String, dynamic>? last; // {'k':'flip'|'win'|'wrong', 's', ...}
  List<Map<String, dynamic>>? ranking;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? rankByScore([for (var s = 0; s < players; s++) total(s)]) : null;

  @override
  int get botDelayMs => 1300;

  static List<int> fullDeck() => [
        for (var f = 0; f < 4; f++)
          for (final n in countDist) f * 10 + n,
      ];

  @override
  void start() {
    maxFlips = setup.opt<int>('maxFlips', maxFlipsDefault);
    reactMin = switch (setup.opt<String>('botSpeed', 'normal')) {
      'slow' => 1100,
      'fast' => 450,
      _ => 700,
    } + switch (botLevel) { 0 => 600, 2 => -200, _ => 0 };
    final deck = shuffled(fullDeck(), rng);
    down = [for (var i = 0; i < players; i++) <int>[]];
    up = [for (var i = 0; i < players; i++) <int>[]];
    for (var i = 0; i < deck.length; i++) {
      down[i % players].add(deck[i]);
    }
    turn = 0;
    host.log('德国心脏病开始！轮流翻牌，桌面上某种水果恰好 5 个时抢先拍铃！');
  }

  int total(int s) => down[s].length + up[s].length;
  bool alive(int s) => total(s) > 0;

  /// Sum of each fruit over the visible top cards.
  static List<int> fruitTotals(List<List<int>> upPiles) {
    final t = [0, 0, 0, 0];
    for (final p in upPiles) {
      if (p.isEmpty) continue;
      final c = p.last;
      t[c ~/ 10] += c % 10;
    }
    return t;
  }

  List<int> get totals => fruitTotals(up);

  /// Index of a fruit totalling exactly 5, or -1.
  int get fiveFruit => totals.indexOf(5);

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  int? _nextFlipper(int from) {
    for (var i = 1; i <= players; i++) {
      final s = (from + i) % players;
      if (down[s].isNotEmpty) return s;
    }
    return null;
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    switch (asStr(a['type'])) {
      case 'flip':
        if (seat != turn) throw GameError('还没轮到你翻牌');
        if (down[seat].isEmpty) throw GameError('你没有牌可翻了');
        final c = down[seat].removeLast();
        up[seat].add(c);
        flips++;
        ver++;
        last = {'k': 'flip', 's': seat, 'c': c};
        final nx = _nextFlipper(seat);
        _checkEnd();
        if (over) return;
        if (nx == null) {
          // nobody can flip any more: only a final ring can change anything
          if (fiveFruit < 0) _finish('所有人都翻完了牌');
          if (!over) {
            _scheduleBotRings();
            final v = ver;
            host.schedule(6000, () {
              if (!over && ver == v) _finish('所有人都翻完了牌');
            });
          }
          return;
        }
        turn = nx;
        _scheduleBotRings();
      case 'ring':
        if (!alive(seat)) throw GameError('你已出局');
        final v = a.containsKey('ver') ? asInt(a['ver']) : ver;
        if (v != ver) throw GameError('慢了一步！');
        _ring(seat);
      default:
        throw GameError('未知操作');
    }
  }

  void _ring(int seat) {
    ver++;
    final f = fiveFruit;
    if (f >= 0) {
      final won = <int>[];
      for (final p in up) {
        won.addAll(p);
        p.clear();
      }
      won.shuffle(rng);
      down[seat].insertAll(0, won); // under the pile
      last = {'k': 'win', 's': seat, 'f': f, 'n': won.length};
      host.log('${name(seat)} 拍铃成功！${fruitNames[f]}恰好 5 个，收走 ${won.length} 张牌');
      turn = seat;
    } else {
      final given = <int>[];
      for (var i = 1; i < players; i++) {
        final o = (seat + i) % players;
        if (!alive(o)) continue;
        if (down[seat].isNotEmpty) {
          down[o].insert(0, down[seat].removeLast());
          given.add(o);
        } else if (up[seat].isNotEmpty) {
          down[o].insert(0, up[seat].removeAt(0));
          given.add(o);
        }
      }
      last = {'k': 'wrong', 's': seat, 'n': given.length};
      host.log('${name(seat)} 拍错了铃！罚给每人 1 张牌');
      if (down[turn].isEmpty) {
        final nx = _nextFlipper(turn);
        if (nx != null) turn = nx;
      }
    }
    _checkEnd();
    if (!over && down.every((d) => d.isEmpty) && fiveFruit < 0) _finish('所有人都翻完了牌');
  }

  void _checkEnd() {
    if (over) return;
    final alivePlayers = [for (var s = 0; s < players; s++) if (alive(s)) s];
    if (alivePlayers.length <= 1) {
      _finish('只剩一名玩家有牌');
    } else if (flips >= maxFlips) {
      _finish('达到翻牌上限');
    } else if (down[turn].isEmpty && _nextFlipper(turn) == null && fiveFruit < 0) {
      _finish('所有人都翻完了牌');
    }
  }

  void _finish(String why) {
    over = true;
    final order = [for (var s = 0; s < players; s++) s]..sort((a, b) => total(b) != total(a) ? total(b) - total(a) : a - b);
    ranking = [];
    var rank = 0;
    for (var i = 0; i < order.length; i++) {
      if (i == 0 || total(order[i]) != total(order[i - 1])) rank = i + 1;
      ranking!.add({'s': order[i], 'cards': total(order[i]), 'rank': rank});
    }
    host.log('游戏结束（$why）！冠军：${[for (final r in ranking!) if (r['rank'] == 1) name(r['s'] as int)].join('、')}');
  }

  void _scheduleBotRings() {
    if (fiveFruit < 0) return;
    final v = ver;
    final bots = [for (var s = 0; s < players; s++) if (isBot(s) && alive(s)) s]..shuffle(rng);
    for (final s in bots) {
      final delay = reactMin + rng.nextInt(900);
      host.schedule(delay, () {
        if (over || ver != v || fiveFruit < 0 || !alive(s)) return;
        _ring(s);
      });
    }
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over) return null;
    if (fiveFruit >= 0 && alive(seat)) return {'type': 'ring', 'ver': ver};
    // 简单: now and then gets excited and rings on a wrong table
    if (botLevel == 0 && alive(seat) && flips > 0 && rng.nextInt(25) == 0) return {'type': 'ring', 'ver': ver};
    if (seat == turn && down[seat].isNotEmpty) return {'type': 'flip'};
    return null;
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : 'play',
        'turn': turn,
        'ver': ver,
        'flips': flips,
        'maxFlips': maxFlips,
        'down': [for (final d in down) d.length],
        'upCount': [for (final u in up) u.length],
        'top': [for (final u in up) u.isEmpty ? null : u.last],
        'alive': [for (var s = 0; s < players; s++) alive(s)],
        'last': last,
        'final': ranking,
      };
}
