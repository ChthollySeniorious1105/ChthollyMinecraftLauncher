import '../../src/engine.dart';
import 'common.dart';

/// Score of a No Thanks! collection: sum of the lowest card of every run, minus chips.
int noThanksCardPoints(List<int> cards) {
  final s = List.of(cards)..sort();
  var total = 0;
  for (var i = 0; i < s.length; i++) {
    if (i == 0 || s[i] != s[i - 1] + 1) total += s[i];
  }
  return total;
}

/// Runs of consecutive cards, e.g. [[3,4,5],[9],[20,21]].
List<List<int>> noThanksRuns(List<int> cards) {
  final s = List.of(cards)..sort();
  final out = <List<int>>[];
  for (final c in s) {
    if (out.isNotEmpty && out.last.last == c - 1) {
      out.last.add(c);
    } else {
      out.add([c]);
    }
  }
  return out;
}

const noThanksRules = '''
# 概述
No Thanks!（不要谢谢）是一款 3~7 人的轻量推拉游戏。牌为 3~35 共 33 张，洗混后随机移除 9 张不用（谁也不知道是哪些）。每人开局 11 枚筹码（6 人 9 枚，7 人 7 枚）。

# 回合
- 翻开牌堆顶一张牌，从起始玩家开始轮流决定：
- 不要：在这张牌上放 1 枚筹码，轮到下一个人决定。
- 拿走：拿走这张牌和上面所有的筹码，然后翻开下一张牌，仍由你继续决定。
- 没有筹码的人不能说“不要”，必须拿走。

# 计分
- 每张牌的点数都是罚分，但连续的数字只算最小的那张：例如 27、28、29 只计 27 分。
- 每枚筹码抵 1 分。
- 最终得分 = 牌面罚分 − 筹码数，越低越好。

# 结束
- 牌堆翻完（24 张牌全部被拿走）后游戏结束，得分最低者获胜；并列时名次相同。

# 策略提示
- 筹码是你的“护盾”，用光后就只能被迫吃牌。
- 能接上你已有连号的牌几乎不扣分，别人会故意让它多转几圈来收你的筹码。
- 筹码和手牌数量是公开的（本实现中筹码数公开显示）。
''';

class NoThanks extends GameEngine with LightLog {
  NoThanks(super.setup);

  List<int> deck = [];
  int removedCount = 9;
  int current = -1;
  int pot = 0;
  int turn = 0;
  late List<int> chips = List.filled(players, _startChips);
  late List<List<int>> cards = [for (var i = 0; i < players; i++) <int>[]];
  bool over = false;
  Map<String, dynamic>? last;

  int get _startChips => players >= 7 ? 7 : (players == 6 ? 9 : 11);

  int total(int s) => noThanksCardPoints(cards[s]) - chips[s];

  @override
  void start() {
    final all = shuffled([for (var c = 3; c <= 35; c++) c], rng);
    deck = all.sublist(removedCount);
    current = deck.removeLast();
    turn = rng.nextInt(players);
    say('No Thanks! 开始：每人 $_startChips 枚筹码，${deck.length + 1} 张牌。${name(turn)} 先手');
  }

  @override
  bool get isOver => over;

  @override
  List<int> get waitingFor => over ? const [] : [turn];

  @override
  List<int>? get placings => over ? rankByScore([for (var i = 0; i < players; i++) total(i)], lowWins: true) : null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat != turn) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    if (type == 'pass') {
      if (chips[seat] <= 0) throw GameError('你没有筹码了，只能拿走这张牌');
      chips[seat]--;
      pot++;
      last = {'seat': seat, 'type': 'pass', 'card': current};
      say('${name(seat)} 不要 $current，放入 1 枚筹码（共 $pot）');
      turn = (turn + 1) % players;
      return;
    }
    if (type != 'take') throw GameError('未知操作');
    cards[seat].add(current);
    chips[seat] += pot;
    last = {'seat': seat, 'type': 'take', 'card': current, 'pot': pot};
    say('${name(seat)} 拿走 $current 和 $pot 枚筹码');
    pot = 0;
    if (deck.isEmpty) {
      current = -1;
      over = true;
      final scores = [for (var i = 0; i < players; i++) total(i)];
      final best = scores.reduce((a, b) => a < b ? a : b);
      say('游戏结束！${[for (var i = 0; i < players; i++) if (scores[i] == best) name(i)].join('、')} 以 $best 分获胜');
      return;
    }
    current = deck.removeLast();
  }

  @override
  Map<String, dynamic> view(int seat) => {
        'players': players,
        'turn': turn,
        'current': current,
        'pot': pot,
        'deck': deck.length,
        'removed': removedCount,
        'chips': chips,
        'cards': [for (final c in cards) (List.of(c)..sort())],
        'points': [for (final c in cards) noThanksCardPoints(c)],
        'total': [for (var i = 0; i < players; i++) total(i)],
        'last': last,
        'over': over,
        'log': recentLogs(),
      };

  // ---------------------------------------------------------------- bot

  /// Marginal card points if [s] takes [c].
  int _cost(int s, int c) => noThanksCardPoints([...cards[s], c]) - noThanksCardPoints(cards[s]);

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over) return null;
    if (chips[seat] <= 0) return {'type': 'take'};
    final cost = _cost(seat, current);
    final net = cost - pot; // what taking costs right now
    if (botLevel == 0) {
      if (net <= 0 || rng.nextDouble() < 0.12) return {'type': 'take'};
      return {'type': 'pass'};
    }
    // does anyone else want it (connects to their run)?
    var rivalWants = false;
    for (var o = 0; o < players; o++) {
      if (o != seat && _cost(o, current) <= 1) rivalWants = true;
    }
    final myChips = chips[seat];
    // how much net cost we'd accept: more when low on chips
    var threshold = myChips <= 2 ? 10 : (myChips <= 5 ? 5 : 2);
    if (botLevel >= 2) threshold += (deck.length < 6 ? 2 : 0);
    if (cost <= 2 && !rivalWants) {
      // fits our run: farm chips while it's safe, then take
      final nextHasChips = chips[(seat + 1) % players] > 0;
      final farm = botLevel >= 2 ? (pot < players + 2 && nextHasChips) : (pot < 3 && nextHasChips);
      if (farm && rng.nextDouble() < 0.85) return {'type': 'pass'};
      return {'type': 'take'};
    }
    if (cost <= 2) return {'type': 'take'}; // contested connector: grab it
    if (net <= threshold - 2) return {'type': 'take'};
    if (net <= 0) return {'type': 'take'};
    if (botLevel == 1 && rng.nextDouble() < 0.05) return {'type': 'take'};
    return {'type': 'pass'};
  }
}
