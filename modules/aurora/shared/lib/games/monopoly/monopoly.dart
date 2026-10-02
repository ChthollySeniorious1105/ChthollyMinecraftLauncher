import '../../src/engine.dart';
import 'board_data.dart';

part 'monopoly_rules.dart';
part 'monopoly_bot.dart';

class MDebt {
  final int from;
  final int to; // -1 = bank
  final int amount;
  final bool pot; // goes to the free-parking pot (when enabled)
  final String why;
  MDebt(this.from, this.to, this.amount, this.why, {this.pot = false});
}

/// 大富翁 engine.
///
/// phases: roll (turn player may manage, then roll / jail options), buy,
/// auction (simultaneous sealed rounds), debt (a debtor must raise cash or go
/// bankrupt), trade (target answers), end (manage, then end turn), over.
class MonopolyGame extends GameEngine {
  MonopolyGame(super.setup);

  late final bool auctionOn = setup.opt<bool>('auction', true);
  late final bool potOn = setup.opt<bool>('parking', false);
  late final int startCash = setup.opt<int>('cash', 1500);
  late final int endRounds = setup.opt<int>('end', 0);
  int get roundLimit => endRounds > 0 ? endRounds : 200;

  late List<int> cash, pos, jailTurns;
  late List<bool> inJail, bankrupt;
  late List<List<String>> jailCards;
  final List<int> owner = List.filled(40, -1);
  final List<int> houses = List.filled(40, 0); // 5 = hotel
  final List<bool> mortgaged = List.filled(40, false);
  int housesLeft = 32, hotelsLeft = 12, pot = 0;

  int turn = 0, round = 1, doubles = 0, rolls = 0;
  bool again = false;
  List<int> dice = [0, 0];
  String phase = 'roll';
  int buySq = -1;

  // auction
  int aucSq = -1, aucHigh = 0, aucLeader = -1, aucRound = 0;
  List<int> aucActive = [];
  Map<int, int> aucBids = {}; // this round (hidden); 0 = pass
  Map<String, int> aucLast = {}; // previous round, public

  final List<MDebt> debts = [];
  void Function()? _cont;

  Map<String, dynamic>? trade;
  String tradeReturn = 'end';
  int tradesThisTurn = 0;

  List<int> chance = [], chest = [];
  Map<String, dynamic>? lastCard;
  final List<String> events = [];
  final List<int> bankruptOrder = [];
  final List<int> resignOrder = [];
  int winner = -1;
  bool over = false;
  List<Map<String, dynamic>>? result;

  // bot memory (public information only; only written by handle())
  final Set<String> botDeclined = {};

  @override
  void start() {
    cash = List.filled(players, startCash);
    pos = List.filled(players, 0);
    jailTurns = List.filled(players, 0);
    inJail = List.filled(players, false);
    bankrupt = List.filled(players, false);
    jailCards = [for (var i = 0; i < players; i++) <String>[]];
    chance = shuffled(List.generate(16, (i) => i), rng);
    chest = shuffled(List.generate(16, (i) => i), rng);
    turn = 0;
    phase = 'roll';
    _ev('大富翁开局！每人起始资金 ¥$startCash', log: true);
  }

  // ------------------------------------------------------------ helpers
  void _ev(String s, {bool log = false}) {
    events.add(s);
    if (events.length > 10) events.removeAt(0);
    if (log) host.log(s);
  }

  List<int> get active => [for (var s = 0; s < players; s++) if (!bankrupt[s]) s];
  MDebt? get curDebt => phase == 'debt' && debts.isNotEmpty ? debts.first : null;

  int worth(int s) {
    if (bankrupt[s]) return 0;
    var w = cash[s];
    for (var i = 0; i < 40; i++) {
      if (owner[i] != s) continue;
      final sq = mBoard[i];
      w += mortgaged[i] ? sq.price - sq.mortgage : sq.price;
      w += houses[i] * sq.houseCost;
    }
    return w;
  }

  // ------------------------------------------------------------ actions
  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (over) throw GameError('游戏已结束');
    if (seat < 0 || seat >= players || bankrupt[seat]) throw GameError('你已出局');
    final t = asStr(a['t']);
    switch (t) {
      case 'roll':
        _needTurn(seat, 'roll');
        _doRoll();
      case 'payJail':
        _needTurn(seat, 'roll');
        if (!inJail[seat]) throw GameError('你不在监狱中');
        if (cash[seat] < 50) throw GameError('资金不足 ¥50');
        cash[seat] -= 50;
        if (potOn) pot += 50;
        inJail[seat] = false;
        jailTurns[seat] = 0;
        _ev('${name(seat)} 支付 ¥50 保释出狱', log: true);
      case 'useCard':
        _needTurn(seat, 'roll');
        if (!inJail[seat]) throw GameError('你不在监狱中');
        if (jailCards[seat].isEmpty) throw GameError('你没有出狱许可证');
        final deck = jailCards[seat].removeLast();
        _returnJailCard(deck);
        inJail[seat] = false;
        jailTurns[seat] = 0;
        _ev('${name(seat)} 使用出狱许可证出狱', log: true);
      case 'buy':
        _needTurn(seat, 'buy');
        final sq = mBoard[buySq];
        if (cash[seat] < sq.price) throw GameError('资金不足，无法购买');
        cash[seat] -= sq.price;
        owner[buySq] = seat;
        _ev('${name(seat)} 以 ¥${sq.price} 购买了 ${sq.name}', log: true);
        buySq = -1;
        _resume();
      case 'decline':
        _needTurn(seat, 'buy');
        final sq = buySq;
        buySq = -1;
        if (auctionOn) {
          _startAuction(sq);
        } else {
          _ev('${name(seat)} 放弃购买 ${mBoard[sq].name}');
          _resume();
        }
      case 'bid':
      case 'pass':
        if (phase != 'auction' || !aucWaiting.contains(seat)) throw GameError('现在不需要你出价');
        var amt = 0;
        if (t == 'bid') {
          amt = asInt(a['amount'], 0);
          if (amt < aucHigh + 10) throw GameError('出价至少 ¥${aucHigh + 10}');
          if (amt > cash[seat]) throw GameError('出价不能超过现金');
        }
        aucBids[seat] = amt;
        if (aucWaiting.isEmpty) _aucResolve();
      case 'build':
      case 'sell':
      case 'mortgage':
      case 'unmortgage':
        final sq = asInt(a['sq']);
        if (sq < 0 || sq >= 40) throw GameError('无效地产');
        final err = manageError(seat, t, sq);
        if (err != null) throw GameError(err);
        _manage(seat, t, sq);
      case 'trade':
        if (!(phase == 'roll' || phase == 'end') || seat != turn) throw GameError('只能在自己回合发起交易');
        if (tradesThisTurn >= 5) throw GameError('本回合交易次数已达上限');
        final offer = {
          'from': seat,
          'to': asInt(a['to']),
          'give': asIntList(a['give']),
          'get': asIntList(a['get']),
          'giveCash': asInt(a['giveCash'], 0),
          'getCash': asInt(a['getCash'], 0),
        };
        final err = tradeError(offer);
        if (err != null) throw GameError(err);
        tradesThisTurn++;
        trade = offer;
        tradeReturn = phase;
        phase = 'trade';
        _ev('${name(seat)} 向 ${name(offer['to'] as int)} 提出交易');
      case 'accept':
      case 'reject':
        if (phase != 'trade' || trade == null || trade!['to'] != seat) throw GameError('没有待回应的交易');
        final offer = trade!;
        final from = offer['from'] as int;
        if (t == 'accept') {
          final err = tradeError(offer);
          if (err != null) throw GameError(err);
          _applyTrade(offer);
          _ev('${name(seat)} 接受了 ${name(from)} 的交易', log: true);
        } else {
          botDeclined.add(_tradeKey(offer));
          _ev('${name(seat)} 拒绝了 ${name(from)} 的交易');
        }
        trade = null;
        phase = tradeReturn;
      case 'pay':
        final d = curDebt;
        if (d == null || d.from != seat) throw GameError('你没有待付款项');
        if (cash[seat] < d.amount) throw GameError('现金不足，请先抵押或卖房');
        _resume();
      case 'bankrupt':
        final d = curDebt;
        if (d == null || d.from != seat) throw GameError('只有无力偿债时才能宣告破产');
        _declareBankrupt(seat, d.to);
      case 'end':
        _needTurn(seat, 'end');
        _nextTurn();
      default:
        throw GameError('未知操作');
    }
  }

  void _needTurn(int seat, String ph) {
    if (phase != ph || seat != turn) throw GameError('现在不能这样操作');
  }

  // ------------------------------------------------------------ turn flow
  void _doRoll() {
    final p = turn;
    final d1 = rng.nextInt(6) + 1, d2 = rng.nextInt(6) + 1;
    dice = [d1, d2];
    rolls++;
    final dbl = d1 == d2;
    final sum = d1 + d2;
    if (inJail[p]) {
      if (dbl) {
        inJail[p] = false;
        jailTurns[p] = 0;
        again = false;
        _ev('${name(p)} 掷出对子 $d1+$d2，出狱！', log: true);
        _moveBy(p, sum);
        return;
      }
      jailTurns[p]++;
      if (jailTurns[p] >= 3) {
        inJail[p] = false;
        jailTurns[p] = 0;
        again = false;
        _ev('${name(p)} 第三次未掷出对子，须支付 ¥50 出狱');
        debts.add(MDebt(p, -1, 50, '保释金', pot: true));
        _cont = () {
          if (bankrupt[p]) {
            _finishStep();
          } else {
            _moveBy(p, sum);
          }
        };
        _resume();
        return;
      }
      again = false;
      _ev('${name(p)} 掷出 $d1+$d2，未能出狱（第 ${jailTurns[p]} 次）');
      phase = 'end';
      return;
    }
    if (dbl) {
      doubles++;
      if (doubles >= 3) {
        again = false;
        _sendJail(p, '连续三次掷出对子');
        phase = 'end';
        return;
      }
    }
    again = dbl;
    _ev('${name(p)} 掷出 $d1+$d2${dbl ? '（对子）' : ''}');
    _moveBy(p, sum);
  }

  void _moveBy(int p, int n) {
    final np = pos[p] + n;
    if (np >= 40) _passGo(p);
    pos[p] = np % 40;
    _land(p);
  }

  void _moveTo(int p, int target, {bool collect = true}) {
    if (collect && target < pos[p]) _passGo(p);
    pos[p] = target;
  }

  void _passGo(int p) {
    cash[p] += 200;
    _ev('${name(p)} 经过起点，领取 ¥200');
  }

  void _sendJail(int p, String why) {
    pos[p] = mJailSq;
    inJail[p] = true;
    jailTurns[p] = 0;
    doubles = 0;
    if (p == turn) again = false;
    _ev('${name(p)} $why，入狱！', log: true);
  }

  void _land(int p, {int stationMult = 1, int utilMult = 0}) {
    final at = pos[p];
    final sq = mBoard[at];
    switch (sq.type) {
      case SqType.street:
      case SqType.station:
      case SqType.utility:
        final o = owner[at];
        if (o < 0) {
          buySq = at;
          phase = 'buy';
          return;
        }
        if (o != p && !mortgaged[at]) {
          var diceSum = dice[0] + dice[1];
          if (utilMult > 0) {
            final a = rng.nextInt(6) + 1, b = rng.nextInt(6) + 1;
            diceSum = a + b;
            _ev('${name(p)} 为公用事业重新掷骰：$a+$b');
          }
          final r = rentFor(at, diceSum: diceSum, stationMult: stationMult, utilMult: utilMult);
          _ev('${name(p)} 到达 ${sq.name}，需向 ${name(o)} 支付租金 ¥$r');
          debts.add(MDebt(p, o, r, '${sq.name} 租金'));
        } else if (o != p) {
          _ev('${name(p)} 到达 ${sq.name}（已抵押，免租）');
        }
      case SqType.tax:
        _ev('${name(p)} 缴纳${sq.name} ¥${sq.rents[0]}');
        debts.add(MDebt(p, -1, sq.rents[0], sq.name, pot: true));
      case SqType.chance:
      case SqType.chest:
        _drawCard(p, sq.type == SqType.chance ? 'chance' : 'chest');
        return;
      case SqType.parking:
        if (potOn && pot > 0) {
          _ev('${name(p)} 在免费停车拿走奖池 ¥$pot', log: true);
          cash[p] += pot;
          pot = 0;
        }
      case SqType.goToJail:
        _sendJail(p, '被警察带走');
        phase = 'end';
      default:
        break;
    }
    _resume();
  }

  void _drawCard(int p, String deckName) {
    final deck = deckName == 'chance' ? chance : chest;
    final idx = deck.removeAt(0);
    final c = (deckName == 'chance' ? mChanceCards : mChestCards)[idx];
    if (c.kind == 'jailFree') {
      jailCards[p].add(deckName);
    } else {
      deck.add(idx);
    }
    final label = deckName == 'chance' ? '机会' : '命运';
    lastCard = {'deck': deckName, 'label': label, 'text': c.text, 'seat': p, 'n': rolls};
    _ev('${name(p)} 抽到$label：${c.text}');
    switch (c.kind) {
      case 'move':
        _moveTo(p, c.a);
        _land(p);
        return;
      case 'back':
        pos[p] = (pos[p] - c.a + 40) % 40;
        _land(p);
        return;
      case 'nearStation':
        final t = mStations.firstWhere((s) => s > pos[p], orElse: () => mStations.first);
        _moveTo(p, t);
        _land(p, stationMult: 2);
        return;
      case 'nearUtility':
        final t = mUtilities.firstWhere((s) => s > pos[p], orElse: () => mUtilities.first);
        _moveTo(p, t);
        _land(p, utilMult: 10);
        return;
      case 'jail':
        _sendJail(p, '抽到入狱卡');
        phase = 'end';
      case 'money':
        if (c.a >= 0) {
          cash[p] += c.a;
        } else {
          debts.add(MDebt(p, -1, -c.a, '$label卡', pot: true));
        }
      case 'each':
        for (final o in active) {
          if (o == p) continue;
          if (c.a > 0) {
            debts.add(MDebt(o, p, c.a, '$label卡'));
          } else {
            debts.add(MDebt(p, o, -c.a, '$label卡'));
          }
        }
      case 'repairs':
        var total = 0;
        for (var i = 0; i < 40; i++) {
          if (owner[i] != p) continue;
          total += houses[i] == 5 ? c.b : houses[i] * c.a;
        }
        if (total > 0) debts.add(MDebt(p, -1, total, '房屋维修', pot: true));
      default:
        break;
    }
    _resume();
  }

  void _returnJailCard(String deck) {
    final list = deck == 'chance' ? chance : chest;
    final cards = deck == 'chance' ? mChanceCards : mChestCards;
    final idx = cards.indexWhere((c) => c.kind == 'jailFree');
    list.add(idx);
  }

  /// Settle queued debts; when done, run the continuation or finish the step.
  void _resume() {
    while (debts.isNotEmpty) {
      final d = debts.first;
      if (bankrupt[d.from]) {
        debts.removeAt(0);
        continue;
      }
      if (cash[d.from] >= d.amount) {
        cash[d.from] -= d.amount;
        if (d.to >= 0 && !bankrupt[d.to]) {
          cash[d.to] += d.amount;
        } else if (d.to < 0 && d.pot && potOn) {
          pot += d.amount;
        }
        debts.removeAt(0);
        continue;
      }
      phase = 'debt';
      return;
    }
    if (over) return;
    final c = _cont;
    _cont = null;
    if (c != null) {
      c();
      return;
    }
    _finishStep();
  }

  void _finishStep() {
    if (over) return;
    if (bankrupt[turn]) {
      _nextTurn();
      return;
    }
    if (phase == 'end' && !again) return;
    phase = again && !inJail[turn] ? 'roll' : 'end';
  }

  void _nextTurn() {
    doubles = 0;
    again = false;
    tradesThisTurn = 0;
    var n = turn;
    do {
      n++;
      if (n >= players) {
        n = 0;
        round++;
      }
    } while (bankrupt[n]);
    turn = n;
    if (round > roundLimit) {
      _ev('已达到 $roundLimit 回合上限', log: true);
      _finishGame();
      return;
    }
    phase = 'roll';
  }

  void _finishGame() {
    over = true;
    phase = 'over';
    final order = finalOrder;
    winner = order.first;
    result = [
      for (final s in order) {'seat': s, 'worth': worth(s), 'cash': cash[s], 'bankrupt': bankrupt[s]},
    ];
    _ev('游戏结束，${name(winner)} 获胜！总资产 ¥${worth(winner)}', log: true);
  }

  @override
  bool get isOver => over;

  @override
  List<int>? get placings => over ? placingsImpl : null;

  @override
  bool get canResign => !over;

  @override
  void resign(int seat) => _resignImpl(seat);

  @override
  Map<String, dynamic> view(int seat) => _viewImpl(seat);

  @override
  Map<String, dynamic>? bot(int seat) => botImpl(seat);

  @override
  List<int> get waitingFor {
    if (over) return const [];
    switch (phase) {
      case 'auction':
        return aucWaiting;
      case 'debt':
        return [curDebt!.from];
      case 'trade':
        return [trade!['to'] as int];
      default:
        return [turn];
    }
  }

  @override
  int get botDelayMs => phase == 'auction' ? 500 : 700;
}
