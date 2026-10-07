import '../../src/engine.dart';
import 'a2_util.dart';

/// 眼疾手快 (Dobble / Spot It!, 2-8 人).
///
/// Deck: the projective plane of order 7 — 57 cards × 8 symbols, any two
/// cards share exactly one symbol. Real-time: a self-rescheduling tick (like
/// 贪吃蛇大作战) drives the countdown, the reveal pause, tap lockouts and
/// computer players' reactions. Everyone races at once
/// (`{'type':'tap','sym':i,'ver':round}`); the first correct tap wins the round.
///
/// Modes:
///  * tower 塔楼 — centre = draw pile. Match your top card with the centre
///    card to win it (it becomes your new top). Most cards when the pile runs
///    out wins.
///  * well 深井 — all cards dealt out, one face up in the centre. Match your
///    top card with the centre to put it on the centre. First to empty wins.
class Dobble extends GameEngine {
  Dobble(super.setup);

  static const order = 7;
  static const symbolsPerCard = order + 1; // 8
  static const cardCount = order * order + order + 1; // 57
  static const tickMs = 100;
  static const countdownTicks = 30;
  static const revealTicks = 14;
  static const penaltyTicks = 15; // 1.5 s

  static const symbols = [
    '🍎', '🍌', '🍇', '🍉', '🍓', '🍒', '🍍', '🥕', '🌽', '🍄', //
    '🌵', '🌻', '🌹', '🍀', '🍁', '🐶', '🐱', '🐭', '🐰', '🦊', //
    '🐻', '🐼', '🐸', '🐵', '🐔', '🐧', '🐢', '🐙', '🦋', '🐞', //
    '🐝', '🐬', '🐳', '⚽', '🏀', '🎈', '🎁', '🔑', '🔒', '💡', //
    '🔔', '🎵', '⏰', '⭐', '🌙', '⚡', '🔥', '💧', '🚗', '🚀', //
    '⚓', '👀', '👻', '🤖', '🎩', '🧀', '🍦',
  ];

  /// cards[i] = 8 symbol indices (0..56).
  static final List<List<int>> cards = buildDeck(order);

  /// Projective plane of prime order [n]: n²+n+1 cards of n+1 symbols.
  static List<List<int>> buildDeck(int n) {
    final out = <List<int>>[];
    for (var i = 0; i <= n; i++) {
      out.add([0, for (var j = 0; j < n; j++) 1 + i * n + j]);
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        out.add([i + 1, for (var k = 0; k < n; k++) n + 1 + n * k + (i * k + j) % n]);
      }
    }
    return out;
  }

  /// The one symbol two cards share.
  static int common(int a, int b) {
    final sa = cards[a].toSet();
    return cards[b].firstWhere(sa.contains);
  }

  late String mode;
  final List<int> centre = []; // tower: draw pile (last = face up); well: discard (last = face up)
  late List<List<int>> piles; // per player; last = top card
  late List<DobblePlayer> ps;
  int tick = 0;
  int countdown = countdownTicks;
  int reveal = 0;
  int round = 0; // ver: increments every time a new centre card shows
  bool over = false;
  int _resigns = 0;
  Map<String, dynamic>? last;
  List<Map<String, dynamic>>? ranking;

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? a2Placings(ranking, players) : null;

  @override
  int get botDelayMs => 600;

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能认输');
    final p = ps[seat];
    if (p.resignNo > 0) throw GameError('你已认输');
    p.resignNo = ++_resigns;
    host.log('${name(seat)} 认输');
    final still = [for (var s = 0; s < players; s++) if (ps[s].resignNo == 0) s];
    if (still.length <= 1) _finish(still.isEmpty ? '所有人都认输了' : '其他人都认输了');
  }

  @override
  void start() {
    mode = setup.opt<String>('mode', 'tower') == 'well' ? 'well' : 'tower';
    final deck = shuffled(List.generate(cardCount, (i) => i), rng);
    ps = [for (var s = 0; s < players; s++) DobblePlayer()];
    piles = [for (var s = 0; s < players; s++) <int>[]];
    if (mode == 'tower') {
      for (var s = 0; s < players; s++) {
        piles[s].add(deck.removeLast());
      }
      centre.addAll(deck);
    } else {
      centre.add(deck.removeLast());
      final each = deck.length ~/ players;
      for (var s = 0; s < players; s++) {
        for (var i = 0; i < each; i++) {
          piles[s].add(deck.removeLast());
        }
      }
    }
    round = 1;
    host.log(mode == 'tower'
        ? '眼疾手快（塔楼）开始！找出你的牌和中央牌唯一相同的图案，抢到就把中央牌收入囊中。'
        : '眼疾手快（深井）开始！找出你的牌和中央牌唯一相同的图案，把自己的牌打到中央，先出完者获胜。');
    host.schedule(tickMs, _tick);
  }

  int? topOf(int s) => piles[s].isEmpty ? null : piles[s].last;
  int? get centreCard => centre.isEmpty ? null : centre.last;

  bool active(int s) => ps[s].resignNo == 0 && piles[s].isNotEmpty;

  // ---------------------------------------------------------------- tick

  void _tick() {
    if (over) return;
    tick++;
    if (countdown > 0) {
      countdown--;
      if (countdown == 0) _newRound(false);
    } else if (reveal > 0) {
      reveal--;
      if (reveal == 0) _newRound(true);
    } else {
      // computer players react inside the tick (bot() only returns 'idle')
      for (var s = 0; s < players && !over && reveal == 0; s++) {
        final p = ps[s];
        if (!active(s) || !(isBot(s) || p.auto) || p.react < 0 || tick < p.react) continue;
        if (tick < p.lockUntil) continue;
        final lvl = isBot(s) ? botLevel : 1;
        final right = common(topOf(s)!, centreCard!);
        final miss = switch (lvl) { 0 => 22, 1 => 6, _ => 0 };
        if (miss > 0 && setup.botRng.nextInt(100) < miss) {
          final wrong = [for (final x in cards[topOf(s)!]) if (x != right) x];
          _tap(s, wrong[setup.botRng.nextInt(wrong.length)]);
        } else {
          _tap(s, right);
        }
      }
    }
    if (!over) host.schedule(tickMs, _tick);
  }

  /// Bot reaction time in ticks for [lvl].
  int _reactTicks(int lvl) => switch (lvl) {
        0 => 38 + setup.botRng.nextInt(40),
        2 => 13 + setup.botRng.nextInt(16),
        _ => 22 + setup.botRng.nextInt(28),
      };

  void _newRound(bool advance) {
    if (advance) round++;
    for (var s = 0; s < players; s++) {
      final p = ps[s];
      p.react = (isBot(s) || p.auto) && active(s) ? tick + _reactTicks(isBot(s) ? botLevel : 1) : -1;
    }
  }

  void _tap(int seat, int sym) {
    final p = ps[seat];
    final top = topOf(seat)!, c = centreCard!;
    if (!cards[top].contains(sym)) throw GameError('这个图案不在你的牌上');
    if (cards[c].contains(sym)) {
      p.wins++;
      if (mode == 'tower') {
        final won = centre.removeLast();
        piles[seat].add(won);
        last = {'k': 'win', 's': seat, 'sym': sym, 'card': won, 'ctr': c, 'mine': top, 'ver': round};
      } else {
        final played = piles[seat].removeLast();
        centre.add(played);
        last = {'k': 'win', 's': seat, 'sym': sym, 'card': played, 'ctr': c, 'mine': top, 'ver': round};
      }
      host.log('${name(seat)} 抢到了 ${symbols[sym]}！');
      if (mode == 'tower' && centre.isEmpty) {
        _finish('中央牌堆已抢完');
      } else if (mode == 'well' && piles[seat].isEmpty) {
        _finish('${name(seat)} 出完了所有牌');
      } else {
        reveal = revealTicks;
        for (final q in ps) {
          q.react = -1;
        }
      }
    } else {
      p.wrong++;
      p.lockUntil = tick + penaltyTicks;
      // bots try again after the lockout
      if (p.react >= 0) p.react = p.lockUntil + (_reactTicks(isBot(seat) ? botLevel : 1) ~/ 3);
      last = {'k': 'wrong', 's': seat, 'sym': sym, 'ver': round, 't': tick};
    }
  }

  void _finish(String why) {
    over = true;
    // tower: more cards is better; well: fewer cards left is better
    int score(int s) => mode == 'tower' ? piles[s].length : -piles[s].length;
    ranking = a2Ranking(players, (a, b) {
      final pa = ps[a], pb = ps[b];
      if (pa.resignNo != pb.resignNo) return pa.resignNo == 0 ? -1 : (pb.resignNo == 0 ? 1 : pb.resignNo - pa.resignNo);
      return score(b) - score(a);
    }, (s) => {'cards': piles[s].length, 'wins': ps[s].wins});
    reveal = 0;
    host.log('游戏结束（$why）！冠军：${a2Winners(ranking!, name)}');
  }

  @override
  List<int> get waitingFor {
    if (over || countdown > 0 || reveal > 0) return const [];
    return a2Rotated([for (var s = 0; s < players; s++) if (active(s)) s], tick);
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    if (type == 'idle') return;
    final p = ps[seat];
    if (type == 'auto') {
      p.auto = true;
      if (p.react < 0 && countdown == 0 && reveal == 0 && active(seat)) p.react = tick + _reactTicks(1);
      return;
    }
    if (type != 'tap') throw GameError('未知操作');
    if (p.resignNo > 0) throw GameError('你已认输');
    if (!active(seat)) throw GameError('你没有牌了');
    p.auto = false;
    if (countdown > 0) throw GameError('还没开始');
    final v = a.containsKey('ver') ? asInt(a['ver']) : round;
    if (reveal > 0 || v != round) throw GameError('慢了一步！');
    if (tick < p.lockUntil) throw GameError('点错了，冷却中…');
    final sym = asInt(a['sym']);
    if (sym < 0 || sym >= cardCount) throw GameError('图案无效');
    _tap(seat, sym);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (over || seat < 0 || seat >= players) return null;
    final p = ps[seat];
    // computer seats tap inside the tick; a disconnected human goes autopilot
    if (!active(seat) || isBot(seat) || p.auto) return {'type': 'idle'};
    return {'type': 'auto'};
  }

  // ---------------------------------------------------------------- view

  /// While a round's result is shown (and at the end) the table still shows
  /// the contested pair, so nobody can scan the next centre card early.
  bool get _showLast => (reveal > 0 || over) && last != null && last!['k'] == 'win';

  @override
  Map<String, dynamic> view(int seat) => {
        'phase': over ? 'over' : (countdown > 0 ? 'countdown' : (reveal > 0 ? 'reveal' : 'play')),
        'mode': mode,
        'tick': tick,
        'tickMs': tickMs,
        'cd': countdown,
        'ver': round,
        // countdown: cards stay face down
        'centre': countdown > 0 ? null : (_showLast ? last!['ctr'] : centreCard),
        'centreN': centre.length,
        'top': [
          for (var s = 0; s < players; s++)
            countdown > 0 ? null : (_showLast && last!['s'] == s ? last!['mine'] : topOf(s)),
        ],
        'n': [for (final p in piles) p.length],
        'wins': [for (final p in ps) p.wins],
        'lock': [for (final p in ps) (p.lockUntil - tick).clamp(0, penaltyTicks)],
        'out': [for (final p in ps) p.resignNo > 0],
        'pen': penaltyTicks,
        'last': last,
        'final': ranking,
      };
}

class DobblePlayer {
  int wins = 0;
  int wrong = 0;
  int lockUntil = 0;
  int react = -1; // tick at which a computer-controlled seat taps
  bool auto = false;
  int resignNo = 0;
}
