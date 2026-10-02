/// Riichi mahjong engine (四麻 / 三麻 / 雀魂 special modes).
library;

import '../../src/engine.dart';
import 'scoring.dart';
import 'shanten.dart';
import 'state.dart';
import 'tiles.dart';
import 'yaku.dart';

part 'flow.dart';
part 'win.dart';
part 'view.dart';
part 'bot.dart';

/// Static rule configuration of a mode.
class RiichiRules {
  final String mode; // riichi4 riichi3 shura wanxiang mingjing anye
  final bool sanma;
  final bool aka;
  final bool kuitan;
  final int winds; // 1 = 东风战, 2 = 半庄战
  final int startPoints;
  final bool bloodbath;
  final bool exchange;
  final bool wild;
  final bool mirror;
  final bool dark;
  final bool renchan;

  /// 途中流局：四风连打 / 四家立直（四麻）、四杠散了。
  final bool abortive;

  /// 三家和了 → 流局（否则三家同时荣和）。
  final bool tripleRonAbort;

  /// 流局满贯。
  final bool nagashi;

  /// 包牌（大三元 / 大四喜）。
  final bool pao;

  /// Uma per rank (1st first), in thousands. Empty = none.
  final List<int> uma;

  /// Return points (返点) for the final score; 0 = no final score calculation.
  final int returnPoints;
  const RiichiRules({
    required this.mode,
    this.sanma = false,
    this.aka = true,
    this.kuitan = true,
    this.winds = 2,
    this.startPoints = 25000,
    this.bloodbath = false,
    this.exchange = false,
    this.wild = false,
    this.mirror = false,
    this.dark = false,
    this.renchan = true,
    this.abortive = false,
    this.tripleRonAbort = false,
    this.nagashi = false,
    this.pao = false,
    this.uma = const [],
    this.returnPoints = 0,
  });
  int get honbaRon => 300;
  int get honbaTsumo => 100;
  int get notenTotal => sanma ? 2000 : 3000;
  int get topLine => sanma ? 40000 : 30000;
}

class RiichiGame extends GameEngine {
  final RiichiRules rules;
  RiichiGame(super.setup, this.rules) : ts = TileSet(sanma: rules.sanma, aka: rules.aka);

  final TileSet ts;
  late final int n = players;
  late final List<PState> ps = [for (var i = 0; i < n; i++) PState(rules.startPoints)];
  int oya0 = 0;
  int roundWind = 0; // 0 东 1 南
  int kyoku = 0;
  int honba = 0;
  int kyoutaku = 0;
  int handSerial = 0;

  // wall
  List<int> live = [];
  List<int> indicators = []; // 5 dora indicators
  List<int> uraIndicators = [];
  List<int> rinshanPile = [];
  int doraShown = 1;

  // turn state
  String phase = 'idle'; // exchange turn call chankan anyeOpen anyeLock result over (pause = claim-cover delay)

  /// Phase to show/resume while [phase] is 'pause' (claim-cover delay).
  String pausedPhase = '';
  int turn = 0;
  int drawnId = -1;
  bool rinshanFlag = false;
  bool afterCall = false;
  bool uninterrupted = true;
  int kanTotal = 0;
  int pendingRiichi = -1;
  bool pendingDouble = false;
  List<bool> firstTurn = [];
  String? _taKey;
  Map<String, dynamic>? _taVal;
  final Map<int, (String, List<int>)> _waitCache = {};
  final Set<int> wildIds = {};

  // response state (call / chankan / anye)
  int discarder = -1;
  int respTile = -1;
  String respKind = ''; // discard kakan ankan kita
  Map<int, Map<String, dynamic>> opts = {};
  Map<int, Map<String, dynamic>> resp = {};

  // exchange (换三张)
  int exchDir = 0; // 1 = 下家 (counter-clockwise), -1 = 上家, 2 = 对家
  Map<int, List<int>> exchSel = {};
  Map<int, List<int>> exchGot = {};

  // hand result
  List<Map<String, dynamic>> handWins = [];
  List<int> handDelta = [];
  Map<String, dynamic>? result;
  Set<int> confirmed = {};
  Map<String, dynamic>? finalResult;
  Map<String, dynamic>? _lastEvent;

  /// Increments on every table event so clients can replay animations.
  int eventSeq = 0;
  Map<String, dynamic>? get lastEvent => _lastEvent;
  set lastEvent(Map<String, dynamic>? e) {
    _lastEvent = e;
    if (e != null) eventSeq++;
  }
  bool _over = false;

  int get dealer => (oya0 + kyoku) % n;
  int seatWindIdx(int s) => (s - dealer + n) % n;
  int seatWindKind(int s) => 27 + seatWindIdx(s);
  int get roundWindKind => 27 + roundWind;
  bool isGlass(int id) => rules.mirror && copyOf(id) != 3;
  bool isWild(int id) => wildIds.contains(id);
  bool active(int s) => !ps[s].won;
  int get activeCount => ps.where((p) => !p.won).length;

  int nextActive(int s) {
    for (var i = 1; i <= n; i++) {
      final t = (s + i) % n;
      if (!ps[t].won) return t;
    }
    return s;
  }

  @override
  bool get isOver => _over;

  /// Final placings (雀魂: equal points are split by seat order from the first dealer).
  @override
  List<int>? get placings {
    if (!_over || finalResult == null) return null;
    final out = List<int>.filled(n, n);
    for (final r in (finalResult!['ranking'] as List).cast<Map<String, dynamic>>()) {
      out[r['seat'] as int] = r['rank'] as int;
    }
    return out;
  }

  @override
  int get botDelayMs => 600;

  @override
  Map<String, dynamic> view(int seat) => buildView(seat);

  @override
  Map<String, dynamic>? bot(int seat) => botAction(seat);

  @override
  void start() {
    oya0 = rng.nextInt(n);
    host.log('${name(oya0)} 为起家');
    _startHand();
  }

  // ------------------------------------------------------------------ hand setup
  void _startHand() {
    handSerial++;
    for (final p in ps) {
      p.resetHand();
    }
    wildIds.clear();
    final all = shuffled(ts.allIds(), rng);
    final dead = all.sublist(all.length - 14);
    live = all.sublist(0, all.length - 14);
    indicators = dead.sublist(0, 5);
    uraIndicators = dead.sublist(5, 10);
    rinshanPile = dead.sublist(10, 14);
    doraShown = 1;
    kanTotal = 0;
    pendingRiichi = -1;
    uninterrupted = true;
    rinshanFlag = false;
    afterCall = false;
    firstTurn = List.filled(n, true);
    handWins = [];
    handDelta = List.filled(n, 0);
    result = null;
    confirmed = {};
    lastEvent = null;
    opts = {};
    resp = {};
    for (var i = 0; i < 13; i++) {
      for (var k = 0; k < n; k++) {
        final s = (dealer + k) % n;
        if (i == 0 && rules.wild) {
          // 百搭牌 are extra tiles outside the normal 136, one per player
          final id = kWildBase + k;
          wildIds.add(id);
          ps[s].hand.add(id);
          continue;
        }
        ps[s].hand.add(live.removeAt(0));
      }
    }
    for (final p in ps) {
      _sortHand(p);
    }
    host.log('${windNames[roundWind]}${kyoku + 1}局 ${honba > 0 ? "$honba本场 " : ""}开始，庄家 ${name(dealer)}');
    if (rules.exchange) {
      exchDir = [1, -1, 2][rng.nextInt(3)];
      exchSel = {};
      exchGot = {};
      phase = 'exchange';
      return;
    }
    _beginPlay();
  }

  void _beginPlay() {
    turn = dealer;
    _draw(turn);
  }

  void _sortHand(PState p) {
    p.hand.sort((a, b) {
      final wa = isWild(a) ? 1 : 0, wb = isWild(b) ? 1 : 0;
      if (wa != wb) return wa - wb;
      return tileSortKey(a) - tileSortKey(b);
    });
  }

  /// Draw from the live wall and enter the turn phase.
  void _draw(int s) {
    if (live.isEmpty) {
      _exhaustiveDraw();
      return;
    }
    final id = live.removeAt(0);
    ps[s].hand.add(id);
    drawnId = id;
    turn = s;
    rinshanFlag = false;
    afterCall = false;
    ps[s].forbidden = {};
    phase = 'turn';
  }

  void _drawRinshan(int s) {
    final id = rinshanPile.removeAt(0);
    if (live.isNotEmpty) rinshanPile.add(live.removeLast());
    ps[s].hand.add(id);
    drawnId = id;
    turn = s;
    rinshanFlag = true;
    afterCall = false;
    ps[s].forbidden = {};
    phase = 'turn';
  }

  void _revealKanDora() {
    if (doraShown < 5) doraShown++;
  }

  // ------------------------------------------------------------------ hand end / progression
  /// Called when a hand is over. [dealerStays] = renchan, [draw] = exhaustive/abortive.
  void _finishHand(Map<String, dynamic> res, {required bool dealerStays, required bool draw, bool abort = false}) {
    result = res;
    res['deltas'] = List<int>.of(handDelta);
    res['scores'] = [for (final p in ps) p.score];
    res['serial'] = handSerial;
    res['round'] = '${windNames[roundWind]}${kyoku + 1}局';
    res['honba'] = honba;
    phase = 'result';
    confirmed = {};
    // next round state
    var busted = ps.any((p) => p.score < 0);
    final lastIndex = rules.winds * n - 1;
    final curIndex = roundWind * n + kyoku;
    var keep = rules.renchan && dealerStays;
    var gameEnd = busted;
    if (!gameEnd && curIndex >= lastIndex) {
      if (!keep) {
        gameEnd = true;
      } else if (!abort) {
        // agari-yame: all-last dealer on top with enough points
        final d = dealer;
        final top = ps.every((p) => p.score <= ps[d].score);
        if (top && ps[d].score >= rules.topLine) gameEnd = true;
      }
    }
    if (rules.bloodbath || !rules.renchan) {
      honba = 0;
    } else if (draw || keep) {
      honba++;
    } else {
      honba = 0;
    }
    if (!keep) {
      kyoku++;
      if (kyoku >= n) {
        kyoku = 0;
        roundWind++;
      }
    }
    res['gameEnd'] = gameEnd;
    if (gameEnd) {
      _endGame();
    } else {
      final serial = handSerial;
      host.schedule(25000, () {
        if (phase == 'result' && handSerial == serial) _startHand();
      });
    }
  }

  void _endGame() {
    // leftover riichi sticks go to the top player
    final order = List<int>.generate(n, (i) => (oya0 + i) % n);
    order.sort((a, b) => ps[b].score - ps[a].score);
    if (kyoutaku > 0) {
      ps[order.first].score += kyoutaku * 1000;
      kyoutaku = 0;
    }
    order.sort((a, b) {
      final d = ps[b].score - ps[a].score;
      if (d != 0) return d;
      return ((a - oya0 + n) % n) - ((b - oya0 + n) % n);
    });
    final ret = rules.returnPoints;
    final oka = ret > 0 ? (ret - rules.startPoints) * n / 1000 : 0.0;
    double? finalScore(int i) {
      if (ret <= 0) return null;
      final uma = i < rules.uma.length ? rules.uma[i] : 0;
      final v = (ps[order[i]].score - ret) / 1000 + uma + (i == 0 ? oka : 0);
      return (v * 10).round() / 10;
    }

    finalResult = {
      'ranking': [
        for (var i = 0; i < order.length; i++)
          {
            'seat': order[i],
            'rank': i + 1,
            'score': ps[order[i]].score,
            if (ret > 0) 'final': finalScore(i),
            if (ret > 0) 'uma': i < rules.uma.length ? rules.uma[i] : 0,
          }
      ],
      if (ret > 0) 'returnPoints': ret,
      if (ret > 0) 'oka': oka,
    };
    _over = true;
    host.log('对局结束：${[
      for (var i = 0; i < order.length; i++)
        '${name(order[i])} ${ps[order[i]].score}${ret > 0 ? '（${_fmtFinal(finalScore(i)!)}）' : ''}'
    ].join('，')}');
  }

  static String _fmtFinal(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)}';

  void _confirm(int seat) {
    if (phase != 'result') throw GameError('现在不需要确认');
    confirmed.add(seat);
    if (confirmed.length >= n) _startHand();
  }

  // ------------------------------------------------------------------ waiting
  @override
  List<int> get waitingFor {
    if (_over) return const [];
    switch (phase) {
      case 'exchange':
        return [for (var s = 0; s < n; s++) if (!exchSel.containsKey(s)) s];
      case 'turn':
        return [turn];
      case 'call':
      case 'chankan':
      case 'anyeOpen':
        return [for (final s in opts.keys) if (!resp.containsKey(s)) s];
      case 'anyeLock':
        return [discarder];
      case 'result':
        return [for (var s = 0; s < n; s++) if (!confirmed.contains(s)) s];
    }
    return const [];
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (_over) throw GameError('对局已结束');
    if (seat < 0 || seat >= n) throw GameError('你不是玩家');
    final t = asStr(a['t']);
    switch (phase) {
      case 'exchange':
        _handleExchange(seat, a);
      case 'turn':
        if (seat != turn) throw GameError('还没轮到你');
        _handleTurn(seat, t, a);
      case 'call':
      case 'chankan':
        _handleResponse(seat, t, a);
      case 'anyeOpen':
        _handleAnyeOpen(seat, t);
      case 'anyeLock':
        if (seat != discarder) throw GameError('还没轮到你');
        _handleAnyeLock(t == 'lock');
      case 'result':
        _confirm(seat);
      default:
        throw GameError('现在不能操作');
    }
  }
}
