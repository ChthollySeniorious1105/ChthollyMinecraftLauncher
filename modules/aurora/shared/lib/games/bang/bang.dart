import 'dart:math';

import '../../src/engine.dart';
import 'bang_cards.dart';
import 'common.dart';

/// 西部无间道 (Bang!) base game.
class Bang extends GameEngine with BangLog {
  Bang(super.setup);

  late List<String> roles;
  late List<int> chars; // index into bangChars, -1 = no ability
  late List<int> hp;
  late List<int> maxHp;
  late List<bool> alive;
  late List<List<int>> hands;
  late List<List<int>> equip;
  late List<List<int>> hostility;
  List<int> deck = [];
  List<int> discard = [];

  /// drawchoice / play / respond / store / discard / over
  String phase = 'play';
  int turn = 0;
  int bangs = 0;
  int turns = 0;
  int sheriff = 0;
  List<int> winners = [];
  List<int> kitCards = [];

  // pending reaction
  String rtype = ''; // shot / indians / duel / store
  int rsrc = -1;
  int rcard = -1;
  List<int> rqueue = [];
  int rneed = 0;
  bool rprep = false;
  bool rslab = false;
  List<int> duelPair = [];
  List<int> storeCards = [];

  bool get useChars => setup.opt<bool>('chars', true);

  String charKey(int s) => chars[s] >= 0 ? bangChars[chars[s]].key : '';
  bool isChar(int s, String k) => charKey(s) == k;
  String charName(int s) => chars[s] >= 0 ? bangChars[chars[s]].name : '枪手';

  List<int> get aliveSeats => [for (var i = 0; i < players; i++) if (alive[i]) i];

  @override
  void start() {
    final r = shuffled(bangRolesFor(players), rng);
    roles = r;
    sheriff = roles.indexOf('sheriff');
    final cs = shuffled(List.generate(bangChars.length, (i) => i), rng);
    chars = [for (var i = 0; i < players; i++) useChars ? cs[i] : -1];
    maxHp = [
      for (var i = 0; i < players; i++) (chars[i] >= 0 ? bangChars[chars[i]].hp : 4) + (roles[i] == 'sheriff' ? 1 : 0)
    ];
    hp = List.of(maxHp);
    alive = List.filled(players, true);
    hands = [for (var i = 0; i < players; i++) <int>[]];
    equip = [for (var i = 0; i < players; i++) <int>[]];
    hostility = [for (var i = 0; i < players; i++) List.filled(players, 0)];
    deck = shuffled(List.generate(bangDeck.length, (i) => i), rng);
    for (var i = 0; i < players; i++) {
      _give(i, hp[i]);
    }
    say('西部无间道开始！警长是 ${name(sheriff)}（${charName(sheriff)}）');
    _startTurn(sheriff);
    _post();
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor => switch (phase) {
        'drawchoice' || 'play' || 'discard' => [turn],
        'respond' || 'store' => rqueue.isEmpty ? const [] : [rqueue.first],
        _ => const [],
      };

  @override
  List<int>? get placings => isOver ? rankWinners(players, winners) : null;

  // ------------------------------------------------------------ helpers

  int _drawCard() {
    if (deck.isEmpty) {
      if (discard.isEmpty) return -1;
      deck = shuffled(discard, rng);
      discard = [];
      say('牌堆用完，重新洗牌');
    }
    return deck.removeLast();
  }

  void _give(int s, int n) {
    for (var i = 0; i < n; i++) {
      final c = _drawCard();
      if (c < 0) return;
      hands[s].add(c);
    }
  }

  String kindOf(int id) => bangDeck[id].kind;

  int nextAlive(int s) {
    for (var k = 1; k <= players; k++) {
      final t = (s + k) % players;
      if (alive[t]) return t;
    }
    return s;
  }

  bool hasEquip(int s, String kind) => equip[s].any((c) => kindOf(c) == kind);

  int weaponOf(int s) => equip[s].firstWhere((c) => bangWeaponRange.containsKey(kindOf(c)), orElse: () => -1);

  int range(int s) {
    final w = weaponOf(s);
    return w < 0 ? 1 : bangWeaponRange[kindOf(w)]!;
  }

  int dist(int a, int b) {
    if (a == b) return 0;
    final al = aliveSeats;
    final ia = al.indexOf(a), ib = al.indexOf(b);
    if (ia < 0 || ib < 0) return 99;
    var d = (ia - ib).abs();
    d = min(d, al.length - d);
    if (hasEquip(b, 'mustang')) d++;
    if (isChar(b, 'paul')) d++;
    if (hasEquip(a, 'scope')) d--;
    if (isChar(a, 'rose')) d--;
    return max(1, d);
  }

  bool unlimitedBang(int s) => isChar(s, 'willy') || hasEquip(s, 'volcanic');

  /// Kind a hand card acts as when played in the play phase.
  String playKind(int s, int id) {
    final k = kindOf(id);
    return k == 'missed' && isChar(s, 'calamity') ? 'bang' : k;
  }

  bool isMissedFor(int s, int id) => kindOf(id) == 'missed' || (kindOf(id) == 'bang' && isChar(s, 'calamity'));
  bool isBangFor(int s, int id) => kindOf(id) == 'bang' || (kindOf(id) == 'missed' && isChar(s, 'calamity'));

  int cardsOf(int s) => hands[s].length + equip[s].length;

  /// Draw! check; returns true when the outcome is good for [s].
  bool _check(int s, bool Function(BangCard c) good, String what) {
    final a = _drawCard();
    if (a < 0) return false;
    discard.add(a);
    var res = good(bangDeck[a]);
    final shown = [a];
    if (isChar(s, 'lucky')) {
      final b = _drawCard();
      if (b >= 0) {
        discard.add(b);
        shown.add(b);
        res = res || good(bangDeck[b]);
      }
    }
    say('${name(s)} $what判定：${shown.map(bangCardLabel).join(' / ')} → ${res ? '成功' : '失败'}');
    return res;
  }

  // ------------------------------------------------------------ turn flow

  void _startTurn(int s) {
    var guard = 0;
    while (!isOver && guard++ < players * 3) {
      turn = s;
      turns++;
      bangs = 0;
      kitCards = [];
      say('—— 轮到 ${name(s)}（${charName(s)}）');
      final dyn = equip[s].where((c) => kindOf(c) == 'dynamite').toList();
      if (dyn.isNotEmpty) {
        equip[s].remove(dyn.first);
        final safe = _check(s, (c) => !(c.suit == 'S' && c.rank >= 2 && c.rank <= 9), '炸药');
        if (!safe) {
          discard.add(dyn.first);
          say('💥 炸药在 ${name(s)} 面前爆炸！');
          _damage(s, 3, -1);
          if (isOver) return;
          if (!alive[s]) {
            s = nextAlive(s);
            continue;
          }
        } else {
          final n = nextAlive(s);
          equip[n].add(dyn.first);
          say('炸药传给了 ${name(n)}');
        }
      }
      final jail = equip[s].where((c) => kindOf(c) == 'jail').toList();
      if (jail.isNotEmpty) {
        equip[s].remove(jail.first);
        discard.add(jail.first);
        if (!_check(s, (c) => c.suit == 'H', '监狱')) {
          say('${name(s)} 被关在监狱里，跳过本回合');
          s = nextAlive(s);
          continue;
        }
        say('${name(s)} 越狱成功！');
      }
      _drawPhase(s);
      return;
    }
    if (!isOver) _drawPhase(turn);
  }

  bool _jesseCan(int s) => isChar(s, 'jesse') && [for (final t in aliveSeats) if (t != s && hands[t].isNotEmpty) t].isNotEmpty;
  bool _pedroCan(int s) => isChar(s, 'pedro') && discard.isNotEmpty;

  void _drawPhase(int s) {
    if (_jesseCan(s) || _pedroCan(s)) {
      phase = 'drawchoice';
      return;
    }
    if (isChar(s, 'kit')) {
      for (var i = 0; i < 3; i++) {
        final c = _drawCard();
        if (c >= 0) kitCards.add(c);
      }
      if (kitCards.length > 2) {
        phase = 'drawchoice';
        return;
      }
      hands[s].addAll(kitCards);
      kitCards = [];
      say('${name(s)} 摸了牌');
      phase = 'play';
      return;
    }
    if (isChar(s, 'blackjack')) {
      _give(s, 1);
      final c = _drawCard();
      if (c >= 0) {
        hands[s].add(c);
        final red = bangDeck[c].suit == 'H' || bangDeck[c].suit == 'D';
        say('${name(s)} 亮出第二张牌 ${bangCardLabel(c)}${red ? '，是红色，再摸 1 张' : ''}');
        if (red) _give(s, 1);
      }
    } else {
      _give(s, 2);
    }
    phase = 'play';
  }

  void _nextTurn() => _startTurn(nextAlive(turn));

  void _resume() {
    _clearPending();
    if (isOver) return;
    if (!alive[turn]) {
      _nextTurn();
    } else {
      phase = 'play';
    }
  }

  void _clearPending() {
    rtype = '';
    rsrc = -1;
    rcard = -1;
    rqueue = [];
    rneed = 0;
    rprep = false;
    rslab = false;
    duelPair = [];
    if (storeCards.isNotEmpty) discard.addAll(storeCards);
    storeCards = [];
  }

  // ------------------------------------------------------------ damage / death

  void _damage(int t, int n, int src) {
    if (!alive[t] || isOver) return;
    hp[t] -= n;
    say('${name(t)} 失去 $n 点生命（剩 ${max(0, hp[t])}）');
    if (hp[t] <= 0) _rescue(t);
    if (hp[t] <= 0) {
      _kill(t, src);
      return;
    }
    if (isChar(t, 'bart')) {
      _give(t, n);
      say('${name(t)}（巴特·卡西迪）摸 $n 张牌');
    }
    if (isChar(t, 'elgringo') && src >= 0 && src != t && alive[src]) {
      for (var i = 0; i < n && hands[src].isNotEmpty; i++) {
        hands[t].add(hands[src].removeAt(rng.nextInt(hands[src].length)));
      }
      say('${name(t)}（艾尔·格林戈）从 ${name(src)} 手里抽了牌');
    }
  }

  void _rescue(int t) {
    while (hp[t] <= 0) {
      final beer = hands[t].where((c) => kindOf(c) == 'beer').toList();
      if (beer.isNotEmpty && aliveSeats.length > 2) {
        hands[t].remove(beer.first);
        discard.add(beer.first);
        hp[t]++;
        say('${name(t)} 濒死喝下啤酒，回复到 ${hp[t]}');
        continue;
      }
      if (isChar(t, 'sid') && hands[t].length >= 2) {
        final two = (List.of(hands[t])..sort((a, b) => cardValue(a) - cardValue(b))).take(2).toList();
        for (final c in two) {
          hands[t].remove(c);
          discard.add(c);
        }
        hp[t]++;
        say('${name(t)}（席德·凯臣）弃 2 张牌回复到 ${hp[t]}');
        continue;
      }
      break;
    }
  }

  void _kill(int t, int src) {
    alive[t] = false;
    hp[t] = 0;
    say('☠️ ${name(t)} 死亡，身份是【${bangRoleName[roles[t]]}】');
    final cards = [...hands[t], ...equip[t]];
    hands[t] = [];
    equip[t] = [];
    final vulture = aliveSeats.where((s) => isChar(s, 'vulture')).toList();
    if (vulture.isNotEmpty && cards.isNotEmpty) {
      hands[vulture.first].addAll(cards);
      say('${name(vulture.first)}（秃鹫山姆）拿走了 ${name(t)} 的 ${cards.length} 张牌');
    } else {
      discard.addAll(cards);
    }
    if (_checkWin()) return;
    if (src >= 0 && src != t && alive[src]) {
      if (roles[t] == 'outlaw') {
        _give(src, 3);
        say('${name(src)} 击杀歹徒，奖励摸 3 张牌');
      } else if (roles[t] == 'deputy' && roles[src] == 'sheriff') {
        discard.addAll([...hands[src], ...equip[src]]);
        hands[src] = [];
        equip[src] = [];
        say('警长误杀副警长，弃掉所有手牌和装备！');
      }
    }
  }

  bool _checkWin() {
    final al = aliveSeats;
    if (!alive[sheriff]) {
      if (al.length == 1 && roles[al.first] == 'renegade') {
        _finish([al.first], '叛徒独自活到最后，叛徒获胜！');
      } else {
        _finish([for (var i = 0; i < players; i++) if (roles[i] == 'outlaw') i], '警长倒下了，歹徒获胜！');
      }
      return true;
    }
    if (!al.any((s) => roles[s] == 'outlaw' || roles[s] == 'renegade')) {
      _finish([for (var i = 0; i < players; i++) if (roles[i] == 'sheriff' || roles[i] == 'deputy') i], '歹徒和叛徒全部伏法，警长阵营获胜！');
      return true;
    }
    return false;
  }

  void _finish(List<int> w, String msg) {
    winners = w;
    phase = 'over';
    rqueue = [];
    say('🏁 $msg');
  }

  // ------------------------------------------------------------ pending reactions

  void _advance() {
    var guard = 0;
    while (!isOver && guard++ < 200) {
      if (rqueue.isEmpty) {
        _resume();
        return;
      }
      final t = rqueue.first;
      if (!alive[t]) {
        _pop();
        continue;
      }
      switch (rtype) {
        case 'shot':
          if (!rprep) {
            rprep = true;
            rneed = rslab ? 2 : 1;
            var barrels = (hasEquip(t, 'barrel') ? 1 : 0) + (isChar(t, 'jourdonnais') ? 1 : 0);
            while (barrels-- > 0 && rneed > 0) {
              if (_check(t, (c) => c.suit == 'H', '酒桶')) rneed--;
            }
          }
          if (rneed <= 0) {
            say('${name(t)} 躲开了射击');
            _pop();
            continue;
          }
          if (hands[t].where((c) => isMissedFor(t, c)).length < rneed) {
            _pop();
            _damage(t, 1, rsrc);
            continue;
          }
          phase = 'respond';
          return;
        case 'indians':
          if (!hands[t].any((c) => isBangFor(t, c))) {
            _pop();
            _damage(t, 1, rsrc);
            continue;
          }
          phase = 'respond';
          return;
        case 'duel':
          if (!hands[t].any((c) => isBangFor(t, c))) {
            final other = duelPair.firstWhere((x) => x != t);
            rqueue = [];
            say('${name(t)} 拿不出 BANG!，输掉了决斗');
            _damage(t, 1, other);
            continue;
          }
          phase = 'respond';
          return;
        case 'store':
          if (storeCards.isEmpty) {
            rqueue = [];
            continue;
          }
          if (storeCards.length == 1) {
            _storeTake(t, storeCards.first);
            continue;
          }
          phase = 'store';
          return;
        default:
          rqueue = [];
      }
    }
  }

  void _pop() {
    if (rqueue.isNotEmpty) rqueue.removeAt(0);
    rprep = false;
  }

  void _storeTake(int t, int c) {
    storeCards.remove(c);
    hands[t].add(c);
    say('${name(t)} 从杂货铺拿了 ${bangCardLabel(c)}');
    _pop();
  }

  void _discardFromHand(int s, int c) {
    hands[s].remove(c);
    discard.add(c);
  }

  // ------------------------------------------------------------ legality (public + own hand only)

  /// Targets for playing [id] from [s]'s hand in the play phase:
  /// null = not playable, [] = playable without a target.
  List<int>? targetsFor(int s, int id) {
    if (!hands[s].contains(id)) return null;
    final others = [for (final t in aliveSeats) if (t != s) t];
    final k = playKind(s, id);
    switch (k) {
      case 'bang':
        if (bangs >= 1 && !unlimitedBang(s)) return null;
        final r = range(s);
        final l = [for (final t in others) if (dist(s, t) <= r) t];
        return l.isEmpty ? null : l;
      case 'missed':
        return null;
      case 'beer':
        return aliveSeats.length <= 2 || hp[s] >= maxHp[s] ? null : const [];
      case 'saloon' || 'stagecoach' || 'wellsfargo' || 'store' || 'gatling' || 'indians':
        return const [];
      case 'duel':
        return others;
      case 'panic':
        final l = [for (final t in others) if (dist(s, t) <= 1 && cardsOf(t) > 0) t];
        return l.isEmpty ? null : l;
      case 'catbalou':
        final l = [for (final t in others) if (cardsOf(t) > 0) t];
        return l.isEmpty ? null : l;
      case 'jail':
        final l = [for (final t in others) if (roles[t] != 'sheriff' && !hasEquip(t, 'jail')) t];
        return l.isEmpty ? null : l;
      default: // blue self-equipment
        return hasEquip(s, k) ? null : const [];
    }
  }

  List<int> respondCards(int s) {
    if (rqueue.isEmpty || rqueue.first != s) return const [];
    return switch (rtype) {
      'shot' => [for (final c in hands[s]) if (isMissedFor(s, c)) c],
      'indians' || 'duel' => [for (final c in hands[s]) if (isBangFor(s, c)) c],
      _ => const [],
    };
  }

  int get discardNeed => phase == 'discard' ? max(0, hands[turn].length - hp[turn]) : 0;

  // ------------------------------------------------------------ actions

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (!waitingFor.contains(seat)) throw GameError('还没轮到你');
    final type = asStr(a['type']);
    switch (phase) {
      case 'drawchoice':
        _handleDraw(seat, a);
      case 'play':
        if (type == 'end') {
          if (hands[seat].length > hp[seat]) {
            phase = 'discard';
            say('${name(seat)} 需要弃 ${hands[seat].length - hp[seat]} 张牌');
          } else {
            say('${name(seat)} 结束回合');
            _nextTurn();
          }
        } else if (type == 'sid') {
          _sid(seat, asIntList(a['cards']));
        } else if (type == 'play') {
          _play(seat, asInt(a['card']), asInt(a['target']), asInt(a['pick'], -1));
        } else {
          throw GameError('请出牌或结束回合');
        }
      case 'discard':
        if (type != 'discard') throw GameError('请选择要弃掉的牌');
        final cs = asIntList(a['cards']);
        if (cs.toSet().length != cs.length || cs.length != discardNeed || !cs.every(hands[seat].contains)) {
          throw GameError('需要弃掉 $discardNeed 张手牌');
        }
        for (final c in cs) {
          _discardFromHand(seat, c);
        }
        say('${name(seat)} 弃了 ${cs.length} 张牌，结束回合');
        _nextTurn();
      case 'respond':
        if (type == 'take') {
          _respondTake(seat);
        } else if (type == 'respond') {
          final c = asInt(a['card']);
          if (!respondCards(seat).contains(c)) throw GameError('这张牌不能用来回应');
          _respondCard(seat, c);
        } else {
          throw GameError('请出牌回应或承受伤害');
        }
      case 'store':
        if (type != 'pick') throw GameError('请从杂货铺挑一张牌');
        final c = asInt(a['card']);
        if (!storeCards.contains(c)) throw GameError('杂货铺里没有这张牌');
        _storeTake(seat, c);
        _advance();
      default:
        throw GameError('请稍候');
    }
    _post();
  }

  void _handleDraw(int s, Map<String, dynamic> a) {
    if (asStr(a['type']) != 'draw') throw GameError('请选择摸牌方式');
    if (isChar(s, 'kit')) {
      final b = asInt(a['back']);
      if (!kitCards.contains(b)) throw GameError('请选择一张放回牌堆顶的牌');
      kitCards.remove(b);
      hands[s].addAll(kitCards);
      deck.add(b);
      kitCards = [];
      say('${name(s)}（基特·卡尔森）看了 3 张牌，留下 2 张');
      phase = 'play';
      return;
    }
    final src = a['src'];
    if (src == 'discard') {
      if (!_pedroCan(s)) throw GameError('不能从弃牌堆摸牌');
      final c = discard.removeLast();
      hands[s].add(c);
      say('${name(s)}（佩德罗）从弃牌堆拿了 ${bangCardLabel(c)}');
      _give(s, 1);
    } else if (src is int && src >= 0) {
      if (!_jesseCan(s) || src == s || src >= players || !alive[src] || hands[src].isEmpty) {
        throw GameError('不能从这名玩家手里抽牌');
      }
      hands[s].add(hands[src].removeAt(rng.nextInt(hands[src].length)));
      say('${name(s)}（杰西·琼斯）从 ${name(src)} 手里抽了 1 张牌');
      _give(s, 1);
    } else {
      _give(s, 2);
    }
    phase = 'play';
  }

  void _sid(int s, List<int> cs) {
    if (!isChar(s, 'sid')) throw GameError('只有席德·凯臣有这个能力');
    if (cs.length != 2 || cs[0] == cs[1] || !cs.every(hands[s].contains)) throw GameError('请选择 2 张手牌');
    if (hp[s] >= maxHp[s]) throw GameError('生命已满');
    for (final c in cs) {
      _discardFromHand(s, c);
    }
    hp[s]++;
    say('${name(s)}（席德·凯臣）弃 2 张牌回复 1 点生命');
  }

  void _play(int s, int id, int target, int pick) {
    final ts = targetsFor(s, id);
    if (ts == null) throw GameError('现在不能打出这张牌');
    if (ts.isNotEmpty && !ts.contains(target)) throw GameError('请选择一个合法的目标');
    final k = playKind(s, id);
    final label = bangCardLabel(id);
    hands[s].remove(id);
    if (bangBlueKinds.contains(k) && k != 'jail') {
      if (bangWeaponRange.containsKey(k)) {
        final old = weaponOf(s);
        if (old >= 0) {
          equip[s].remove(old);
          discard.add(old);
        }
      }
      equip[s].add(id);
      say('${name(s)} 装备了 $label');
      return;
    }
    if (k == 'jail') {
      equip[target].add(id);
      hostility[s][target]++;
      say('${name(s)} 把 ${name(target)} 关进了监狱');
      return;
    }
    discard.add(id);
    switch (k) {
      case 'bang':
        bangs++;
        hostility[s][target]++;
        say('${name(s)} 对 ${name(target)} 打出 $label');
        _beginPending('shot', s, id, [target], slab: isChar(s, 'slab'));
      case 'beer':
        hp[s]++;
        say('${name(s)} 喝了啤酒，回复到 ${hp[s]}');
      case 'saloon':
        for (final t in aliveSeats) {
          hp[t] = min(maxHp[t], hp[t] + 1);
        }
        say('${name(s)} 打出酒馆，所有人回复 1 点生命');
      case 'stagecoach':
        _give(s, 2);
        say('${name(s)} 打出驿站，摸 2 张牌');
      case 'wellsfargo':
        _give(s, 3);
        say('${name(s)} 打出富国银行，摸 3 张牌');
      case 'store':
        final n = aliveSeats.length;
        final cards = <int>[];
        for (var i = 0; i < n; i++) {
          final c = _drawCard();
          if (c >= 0) cards.add(c);
        }
        say('${name(s)} 打出杂货铺：${cards.map(bangCardLabel).join('、')}');
        storeCards = cards;
        _beginPending('store', s, id, [s, for (var t = nextAlive(s); t != s; t = nextAlive(t)) t]);
      case 'gatling':
        say('${name(s)} 打出加特林！');
        _beginPending('shot', s, id, [for (var t = nextAlive(s); t != s; t = nextAlive(t)) t]);
      case 'indians':
        say('${name(s)} 打出印第安人！');
        _beginPending('indians', s, id, [for (var t = nextAlive(s); t != s; t = nextAlive(t)) t]);
      case 'duel':
        hostility[s][target]++;
        say('${name(s)} 向 ${name(target)} 发起决斗');
        duelPair = [s, target];
        _beginPending('duel', s, id, [target]);
      case 'panic' || 'catbalou':
        hostility[s][target]++;
        int got;
        var fromHand = false;
        if (pick >= 0 && equip[target].contains(pick)) {
          got = pick;
          equip[target].remove(pick);
        } else if (hands[target].isEmpty) {
          got = equip[target].first;
          equip[target].remove(got);
        } else {
          got = hands[target].removeAt(rng.nextInt(hands[target].length));
          fromHand = true;
        }
        if (k == 'panic') {
          hands[s].add(got);
          say('${name(s)} 打出惊慌，拿走了 ${name(target)} 的${fromHand ? '一张手牌' : ' ${bangCardLabel(got)}'}');
        } else {
          discard.add(got);
          say('${name(s)} 打出卡特巴卢，弃掉了 ${name(target)} 的 ${bangCardLabel(got)}');
        }
    }
  }

  void _beginPending(String type, int src, int card, List<int> queue, {bool slab = false}) {
    rtype = type;
    rsrc = src;
    rcard = card;
    rqueue = queue;
    rslab = slab;
    rprep = false;
    _advance();
  }

  void _respondTake(int s) {
    switch (rtype) {
      case 'shot' || 'indians':
        _pop();
        _damage(s, 1, rsrc);
      case 'duel':
        final other = duelPair.firstWhere((x) => x != s);
        rqueue = [];
        say('${name(s)} 放弃决斗');
        _damage(s, 1, other);
    }
    _advance();
  }

  void _respondCard(int s, int c) {
    _discardFromHand(s, c);
    switch (rtype) {
      case 'shot':
        rneed--;
        say('${name(s)} 打出 ${bangCardLabel(c)} 躲避');
        if (rneed <= 0) _pop();
      case 'indians':
        say('${name(s)} 弃了 ${bangCardLabel(c)} 应付印第安人');
        _pop();
      case 'duel':
        final other = duelPair.firstWhere((x) => x != s);
        say('${name(s)} 在决斗中打出 ${bangCardLabel(c)}');
        rqueue = [other];
    }
    _advance();
  }

  /// Suzy Lafayette draws whenever her hand is empty.
  void _post() {
    if (isOver) return;
    for (final s in aliveSeats) {
      if (isChar(s, 'suzy') && hands[s].isEmpty) {
        _give(s, 1);
        say('${name(s)}（苏西·拉法叶）手牌为空，摸 1 张');
      }
    }
  }

  // ------------------------------------------------------------ view

  bool roleVisible(int viewer, int s) => isOver || s == viewer || roles[s] == 'sheriff' || !alive[s];

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final waiting = waitingFor;
    final myTurnPlay = me && phase == 'play' && turn == seat;
    return {
      'players': [
        for (var s = 0; s < players; s++)
          {
            'char': chars[s],
            'hp': hp[s],
            'maxHp': maxHp[s],
            'alive': alive[s],
            'role': roleVisible(seat, s) ? roles[s] : null,
            'hand': hands[s].length,
            'equip': equip[s],
            'range': range(s),
            'dist': me ? dist(seat, s) : null,
          }
      ],
      'phase': phase,
      'turn': turn,
      'sheriff': sheriff,
      'bangs': bangs,
      'deck': deck.length,
      'discardTop': discard.isEmpty ? -1 : discard.last,
      'hand': me ? hands[seat] : <int>[],
      'playable': myTurnPlay
          ? [
              for (final c in hands[seat])
                if (targetsFor(seat, c) case final t?) {'card': c, 'targets': t}
            ]
          : <Map<String, dynamic>>[],
      'canSid': myTurnPlay && isChar(seat, 'sid') && hp[seat] < maxHp[seat] && hands[seat].length >= 2,
      'rtype': rtype,
      'rsrc': rsrc,
      'rcard': rcard,
      'rneed': rneed,
      'responder': rqueue.isEmpty ? -1 : rqueue.first,
      'duel': duelPair,
      'respondCards': me ? respondCards(seat) : <int>[],
      'store': storeCards,
      'kit': me && seat == turn ? kitCards : <int>[],
      'drawJesse': me && phase == 'drawchoice' && seat == turn && _jesseCan(seat)
          ? [for (final t in aliveSeats) if (t != seat && hands[t].isNotEmpty) t]
          : <int>[],
      'drawPedro': me && phase == 'drawchoice' && seat == turn && _pedroCan(seat),
      'discardNeed': discardNeed,
      'winners': winners,
      'waiting': waiting,
      'log': recentLogs(14),
      'result': isOver ? {'winners': winners, 'roles': roles} : null,
    };
  }

  // ------------------------------------------------------------ bot

  int cardValue(int id) => switch (kindOf(id)) {
        'missed' => 8,
        'beer' => 7,
        'bang' => 6,
        'wellsfargo' || 'stagecoach' => 6,
        'barrel' || 'scope' || 'mustang' => 5,
        'panic' || 'catbalou' || 'duel' || 'gatling' || 'indians' => 5,
        'jail' || 'store' || 'saloon' => 4,
        'dynamite' => 1,
        _ => 3,
      };

  /// Public pro-sheriff estimate for [x] (>0 looks loyal, <0 looks hostile).
  double _align(int x) {
    if (x == sheriff) return 10;
    if (!alive[x]) return roles[x] == 'deputy' ? 5 : -5;
    double base(int y) => -hostility[y][sheriff].toDouble();
    var a = base(x) * 2;
    for (var y = 0; y < players; y++) {
      if (y == x || y == sheriff) continue;
      final b = base(y);
      if (b < 0) a += hostility[x][y] * 1.0;
      if (b == 0 && hostility[x][y] > 0) a -= 0.3 * hostility[x][y];
    }
    return a;
  }

  /// How much [me] wants to hurt [x], using only public info + own role.
  double enemyScore(int me, int x) {
    if (x == me || !alive[x]) return -100;
    final al = aliveSeats.length;
    // derivable from public info: role counts are fixed and dead roles are revealed
    final outlawsLeft = bangRolesFor(players).where((r) => r == 'outlaw').length -
        [for (var i = 0; i < players; i++) if (!alive[i] && roles[i] == 'outlaw') i].length;
    final late = turns > 60 * players ? 1.0 : 0.0;
    switch (roles[me]) {
      case 'sheriff' || 'deputy':
        if (x == sheriff) return -100;
        return -_align(x) + (outlawsLeft == 0 ? 0.6 : 0) + late;
      case 'outlaw':
        if (x == sheriff) return 100;
        return _align(x) + 0.1;
      default: // renegade
        if (al <= 2) return 100;
        if (x == sheriff) return outlawsLeft == 0 && al <= 2 ? 100 : -50;
        if (outlawsLeft == 0) return 50;
        return -_align(x) + (al <= 3 ? 1 : 0) + late;
    }
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (!waitingFor.contains(seat)) return null;
    final lvl = botLevel;
    switch (phase) {
      case 'drawchoice':
        if (isChar(seat, 'kit') && kitCards.isNotEmpty) {
          final b = (List.of(kitCards)..sort((a, b) => cardValue(a) - cardValue(b))).first;
          return {'type': 'draw', 'back': b};
        }
        if (_jesseCan(seat)) {
          final ts = [for (final t in aliveSeats) if (t != seat && hands[t].isNotEmpty) t]
            ..sort((a, b) => enemyScore(seat, b).compareTo(enemyScore(seat, a)));
          if (lvl == 0 || enemyScore(seat, ts.first) > 0) return {'type': 'draw', 'src': ts.first};
        }
        if (_pedroCan(seat) && cardValue(discard.last) >= 6) return {'type': 'draw', 'src': 'discard'};
        return {'type': 'draw', 'src': 'deck'};
      case 'discard':
        final h = List.of(hands[seat])..sort((a, b) => cardValue(a) - cardValue(b));
        if (lvl == 0) h.shuffle(rng);
        return {'type': 'discard', 'cards': h.take(discardNeed).toList()};
      case 'store':
        final s = List.of(storeCards)..sort((a, b) => cardValue(b) - cardValue(a));
        return {'type': 'pick', 'card': lvl == 0 ? storeCards[rng.nextInt(storeCards.length)] : s.first};
      case 'respond':
        final rc = respondCards(seat);
        if (rc.isEmpty) return {'type': 'take'};
        if (rtype == 'duel' && lvl == 0 && rng.nextDouble() < 0.3) return {'type': 'take'};
        // with plenty of life, keep a lone BANG! against Indians sometimes
        if (rtype == 'indians' && lvl >= 1 && hp[seat] >= 4 && rc.length == 1 && rng.nextDouble() < 0.3) {
          return {'type': 'take'};
        }
        return {'type': 'respond', 'card': rc.first};
      case 'play':
        return _botPlay(seat);
    }
    return null;
  }

  Map<String, dynamic> _botPlay(int s) {
    final lvl = botLevel;
    final plays = <int, List<int>>{};
    for (final c in hands[s]) {
      final t = targetsFor(s, c);
      if (t != null) plays[c] = t;
    }
    Map<String, dynamic> end() =>
        isChar(s, 'sid') && hp[s] < maxHp[s] && hands[s].length >= 4 && hp[s] <= 1
            ? {'type': 'sid', 'cards': (List.of(hands[s])..sort((a, b) => cardValue(a) - cardValue(b))).take(2).toList()}
            : {'type': 'end'};
    if (plays.isEmpty) return end();
    if (lvl == 0) {
      if (rng.nextDouble() < 0.25) return end();
      final cs = plays.keys.toList();
      final c = cs[rng.nextInt(cs.length)];
      final ts = plays[c]!;
      return {'type': 'play', 'card': c, if (ts.isNotEmpty) 'target': ts[rng.nextInt(ts.length)], 'pick': -1};
    }
    double sc(int t) => enemyScore(s, t) + rng.nextDouble() * 0.2;
    int? best(List<int> ts, double minScore) {
      final l = ts.where((t) => enemyScore(s, t) > minScore).toList();
      if (l.isEmpty) return null;
      l.sort((a, b) => sc(b).compareTo(sc(a)));
      return l.first;
    }

    final crowded = hands[s].length > hp[s];
    final others = [for (final t in aliveSeats) if (t != s) t];
    final enemies = others.where((t) => enemyScore(s, t) > 0).length;
    final friends = others.where((t) => enemyScore(s, t) < 0).length;
    // priority order
    for (final k in ['stagecoach', 'wellsfargo']) {
      for (final c in plays.keys) {
        if (kindOf(c) == k) return {'type': 'play', 'card': c};
      }
    }
    for (final c in plays.keys) {
      final k = kindOf(c);
      if (k == 'barrel' || k == 'mustang' || k == 'scope') return {'type': 'play', 'card': c};
      if (bangWeaponRange.containsKey(k)) {
        final cur = weaponOf(s);
        final curR = cur < 0 ? 1 : bangWeaponRange[kindOf(cur)]!;
        final bangCount = hands[s].where((x) => isBangFor(s, x)).length;
        if (k == 'volcanic' ? (cur < 0 && bangCount >= 2) : bangWeaponRange[k]! > curR) {
          return {'type': 'play', 'card': c};
        }
      }
      if (k == 'dynamite' && (lvl == 2 ? hp[s] >= 3 : rng.nextBool())) return {'type': 'play', 'card': c};
      if (k == 'beer' && (hp[s] < maxHp[s] - 1 || crowded)) return {'type': 'play', 'card': c};
      if (k == 'saloon' && hp[s] < maxHp[s]) return {'type': 'play', 'card': c};
      if (k == 'store') return {'type': 'play', 'card': c};
    }
    for (final c in plays.keys) {
      final k = kindOf(c);
      if (k == 'jail') {
        final t = best(plays[c]!, 0.5);
        if (t != null) return {'type': 'play', 'card': c, 'target': t};
      }
      if (k == 'panic' || k == 'catbalou') {
        final t = best(plays[c]!, 0);
        if (t != null) {
          final eq = equip[t].where((x) => kindOf(x) != 'jail' && kindOf(x) != 'dynamite').toList()
            ..sort((a, b) => cardValue(b) - cardValue(a));
          final pick = eq.isNotEmpty && (hands[t].isEmpty || rng.nextBool()) ? eq.first : -1;
          return {'type': 'play', 'card': c, 'target': t, 'pick': pick};
        }
      }
      if ((k == 'gatling' || k == 'indians') && (enemies > friends || (enemies > 0 && crowded))) {
        return {'type': 'play', 'card': c};
      }
      if (k == 'duel') {
        final t = best(plays[c]!, 0);
        final myBangs = hands[s].where((x) => isBangFor(s, x)).length;
        if (t != null && (myBangs >= 2 || lvl == 1 || hands[t].length <= 1)) return {'type': 'play', 'card': c, 'target': t};
      }
    }
    for (final c in plays.keys) {
      if (playKind(s, c) == 'bang') {
        var t = best(plays[c]!, 0);
        // a hand that would be discarded anyway: risk a shot at an unknown
        if (t == null && crowded && roles[s] != 'sheriff' && roles[s] != 'deputy') t = best(plays[c]!, -0.5);
        if (t == null && crowded && rng.nextDouble() < 0.15) t = best(plays[c]!, -1);
        if (t != null) return {'type': 'play', 'card': c, 'target': t};
      }
    }
    return end();
  }
}
