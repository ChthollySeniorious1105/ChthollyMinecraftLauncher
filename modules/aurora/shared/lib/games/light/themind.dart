import 'dart:math';

import '../../src/engine.dart';
import 'common.dart';

int theMindLevels(int players) => switch (players) { 2 => 12, 3 => 10, _ => 8 };

const theMindRules = '''
# 概述
心灵同步（The Mind）是 2~4 人的合作游戏。牌为 1~100。所有人一起闯关：第 N 关每人发 N 张牌，大家要在不交流牌面的情况下，把所有手牌按从小到大的顺序打到桌面中央。

# 出牌
- 没有回合顺序。任何人觉得“该我了”的时候，按下“出牌”即可打出自己手里最小的那张牌。
- 出牌顺序以按下的先后为准。
- 如果打出的牌比某人手里的牌大，出现失误：全队失去 1 条生命，所有比这张牌小的手牌都被弃掉（公开显示），然后继续。
- 生命耗尽则闯关失败，游戏结束。

# 手里剑（飞镖）
- 任何人都可以提议使用手里剑。所有仍有手牌的玩家同意后，每人把自己最小的一张牌公开弃掉，消耗 1 枚手里剑。可以借此获得信息、打破僵局。
- 在任何人出牌后，未完成的投票会被取消。

# 关卡与奖励
- 2 人 12 关、3 人 10 关、4 人 8 关。通关全部关卡即胜利。
- 开局生命数 = 人数，手里剑 1 枚。
- 完成第 2、5、8 关奖励 1 枚手里剑；完成第 3、6、9 关奖励 1 条生命（生命最多 5、手里剑最多 3）。

# 结果
- 这是合作游戏，所有玩家同赢同输（名次全部并列第一，结果显示通关到第几关）。

# 电脑玩家
- 电脑只看自己的手牌和桌面上最后一张牌，等待的时间与“自己最小牌和桌面最后一张之间的差距”成正比；难度越高，节奏越稳定。
- 电脑会同意手里剑提议。
''';

class TheMind extends GameEngine with LightLog {
  TheMind(super.setup);

  late final int levels = theMindLevels(players);
  late List<List<int>> hands = [for (var i = 0; i < players; i++) <int>[]];
  late List<bool> ready = List.filled(players, false);
  late List<bool> votes = List.filled(players, false);
  int level = 0;
  int lives = 0;
  int stars = 1;
  int lastCard = 0;
  List<Map<String, int>> pile = []; // {seat, card}
  List<Map<String, dynamic>> discards = []; // {seat, card, why}
  String phase = 'play'; // play / levelEnd / over
  bool won = false;
  int _epoch = 0;
  String? reward;
  Map<String, dynamic>? lastMistake;

  @override
  void start() {
    lives = players;
    say('心灵同步开始！共 $levels 关，生命 $lives，手里剑 $stars');
    _newLevel();
  }

  void _newLevel() {
    level++;
    final deck = shuffled([for (var c = 1; c <= 100; c++) c], rng);
    for (var i = 0; i < players; i++) {
      hands[i] = deck.sublist(i * level, (i + 1) * level)..sort();
    }
    lastCard = 0;
    pile = [];
    discards = [];
    lastMistake = null;
    reward = null;
    phase = 'play';
    say('—— 第 $level 关：每人 $level 张 ——');
    _arm();
  }

  int get _cardsLeft => hands.fold(0, (a, h) => a + h.length);

  /// (Re)start every seat's "I think it's my turn" timer. Each seat only uses
  /// its own lowest card, the last played card and public card counts.
  void _arm() {
    final ep = ++_epoch;
    votes = List.filled(players, false);
    ready = List.filled(players, false);
    if (phase != 'play') return;
    final timers = <(int, int)>[];
    final left = _cardsLeft;
    for (var s = 0; s < players; s++) {
      if (hands[s].isEmpty) continue;
      final gap = hands[s].first - lastCard;
      final expected = (100 - lastCard) / (left + 1);
      final noise = switch (botLevel) { 0 => 0.45, 1 => 0.25, _ => 0.16 };
      final f = 1 + (rng.nextDouble() * 2 - 1) * noise;
      // pace relative to the expected spacing of the remaining cards
      final rel = gap / max(1.0, expected);
      final ms = (600 + rel * 1600 * f + gap * 25).round().clamp(400, 30000);
      timers.add((ms, s));
    }
    timers.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (ms, s) in timers) {
      host.schedule(ms, () {
        if (ep != _epoch || phase != 'play' || hands[s].isEmpty) return;
        if (isBot(s)) {
          _play(s);
        } else {
          ready[s] = true; // 托管 / 掉线：server asks bot() which now plays
        }
      });
    }
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor =>
      phase == 'play' ? [for (var s = 0; s < players; s++) if (hands[s].isNotEmpty && !isBot(s)) s] : const [];

  @override
  List<int>? get placings => isOver ? List.filled(players, 1) : null;

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (phase != 'play') throw GameError('请等待下一关开始');
    if (seat < 0 || seat >= players) throw GameError('无效座位');
    switch (asStr(a['type'])) {
      case 'play':
        if (hands[seat].isEmpty) throw GameError('你已经没有手牌了');
        _play(seat);
      case 'star':
        if (stars <= 0) throw GameError('没有手里剑了');
        if (hands[seat].isEmpty) throw GameError('你已经没有手牌了');
        final first = !votes.contains(true);
        votes[seat] = true;
        if (first) say('${name(seat)} 提议使用手里剑');
        // bots agree right away
        for (var s = 0; s < players; s++) {
          if (isBot(s) && hands[s].isNotEmpty) votes[s] = true;
        }
        _checkStar();
      case 'unstar':
        votes[seat] = false;
      default:
        throw GameError('未知操作');
    }
  }

  void _checkStar() {
    for (var s = 0; s < players; s++) {
      if (hands[s].isNotEmpty && !votes[s]) return;
    }
    stars--;
    final shown = <String>[];
    for (var s = 0; s < players; s++) {
      if (hands[s].isEmpty) continue;
      final c = hands[s].removeAt(0);
      discards.add({'seat': s, 'card': c, 'why': 'star'});
      shown.add('${name(s)} $c');
    }
    say('使用手里剑！弃掉：${shown.join('，')}');
    _after();
  }

  void _play(int seat) {
    final c = hands[seat].removeAt(0);
    pile.add({'seat': seat, 'card': c});
    lastCard = c;
    final lost = <String>[];
    for (var s = 0; s < players; s++) {
      while (hands[s].isNotEmpty && hands[s].first < c) {
        final x = hands[s].removeAt(0);
        discards.add({'seat': s, 'card': x, 'why': 'mistake'});
        lost.add('${name(s)} $x');
      }
    }
    if (lost.isNotEmpty) {
      lives--;
      lastMistake = {'seat': seat, 'card': c, 'lost': lost};
      say('${name(seat)} 打出 $c —— 失误！弃掉 ${lost.join('，')}，剩余生命 $lives');
      if (lives <= 0) {
        phase = 'over';
        won = false;
        say('生命耗尽，闯关失败！最终到达第 $level 关');
        return;
      }
    } else {
      say('${name(seat)} 打出 $c');
    }
    _after();
  }

  void _after() {
    if (_cardsLeft == 0) {
      _levelDone();
    } else {
      _arm();
    }
  }

  void _levelDone() {
    _epoch++;
    if (level >= levels) {
      phase = 'over';
      won = true;
      say('恭喜！全部 $levels 关通关，心灵完全同步！');
      return;
    }
    reward = null;
    if (const [2, 5, 8].contains(level) && stars < 3) {
      stars++;
      reward = '手里剑 +1';
    } else if (const [3, 6, 9].contains(level) && lives < 5) {
      lives++;
      reward = '生命 +1';
    }
    say('第 $level 关通过！${reward ?? ''}');
    phase = 'levelEnd';
    host.schedule(3000, () {
      if (phase == 'levelEnd') _newLevel();
    });
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    return {
      'players': players,
      'phase': phase,
      'level': level,
      'levels': levels,
      'lives': lives,
      'stars': stars,
      'lastCard': lastCard,
      'pile': [for (final p in pile) Map<String, dynamic>.from(p)],
      'discards': discards,
      'hand': me ? hands[seat] : <int>[],
      'handCounts': [for (final h in hands) h.length],
      'votes': votes,
      'won': won,
      'reward': reward,
      'lastMistake': lastMistake,
      'over': isOver,
      'log': recentLogs(),
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase != 'play' || hands[seat].isEmpty) return null;
    if (votes.contains(true) && !votes[seat]) return {'type': 'star'};
    return ready[seat] ? {'type': 'play'} : null;
  }
}
