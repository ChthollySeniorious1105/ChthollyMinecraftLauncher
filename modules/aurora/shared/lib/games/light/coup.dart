import 'dart:math';

import '../../src/ai.dart';
import '../../src/engine.dart';
import 'common.dart';

const coupRoles = ['duke', 'assassin', 'captain', 'ambassador', 'contessa'];
const coupRoleNames = {'duke': '公爵', 'assassin': '刺客', 'captain': '队长', 'ambassador': '大使', 'contessa': '伯爵夫人'};
const coupActionNames = {
  'income': '收入',
  'foreignaid': '外援',
  'coup': '政变',
  'tax': '征税',
  'assassinate': '刺杀',
  'steal': '勒索',
  'exchange': '交换',
};

/// Role an action claims (null = anyone may do it).
String? coupActionRole(String a) => switch (a) {
      'tax' => 'duke',
      'assassinate' => 'assassin',
      'steal' => 'captain',
      'exchange' => 'ambassador',
      _ => null,
    };

/// Roles that may block [action].
List<String> coupBlockRoles(String action) => switch (action) {
      'foreignaid' => ['duke'],
      'assassinate' => ['contessa'],
      'steal' => ['captain', 'ambassador'],
      _ => const [],
    };

String _rn(String r) => coupRoleNames[r] ?? r;

const coupRules = '''
# 概述
政变（Coup）是 2~6 人的虚张声势游戏。牌堆有 5 种角色各 3 张：公爵、刺客、队长、大使、伯爵夫人。每人暗置 2 张角色牌（称为“影响力”）并拿 2 枚金币（2 人局先手只拿 1 枚）。失去全部影响力的玩家出局，最后留下的人获胜。

# 行动（每回合选一个）
- 收入：拿 1 金币。不能被阻止。
- 外援：拿 2 金币。可以被任何宣称“公爵”的玩家阻止。
- 政变：支付 7 金币，指定一名玩家失去 1 点影响力。不能被阻止或质疑。回合开始时持有 10 枚及以上金币必须政变。
- 征税（宣称公爵）：拿 3 金币。
- 刺杀（宣称刺客）：支付 3 金币，指定一名玩家失去 1 点影响力。可被目标宣称“伯爵夫人”阻止。
- 勒索（宣称队长）：从一名玩家处拿走 2 金币（不足则拿走全部）。可被目标宣称“队长”或“大使”阻止。
- 交换（宣称大使）：从牌堆摸 2 张，与手牌一起挑选，保留与原来相同数量的牌，其余放回牌堆洗匀。

# 宣称与质疑
- 角色行动与阻止都只是“宣称”，你可以虚张声势，不必真的持有该角色。
- 任何其他玩家都可以质疑。被质疑者若确实持有该角色，亮出后放回牌堆洗匀并补摸 1 张，质疑者失去 1 点影响力；否则被质疑者失去 1 点影响力，宣称的行动/阻止无效。
- 刺杀被成功质疑时，3 金币退还；刺杀被伯爵夫人阻止时，金币不退。
- 阻止也可以被任何人质疑，规则相同。阻止成立则行动无效。
- 失去影响力时由本人选择翻开哪一张，翻开的牌公开，不再有效。

# 本实现的操作
- 轮到你时选择行动，需要目标的行动再点选目标。
- 其他人宣称时，你可以点“质疑”或“放行”；所有人都放行后才继续。
- 能阻止时会出现“阻止（宣称某角色）”按钮。
- 电脑玩家只根据公开信息（已翻开的牌、各人的宣称记录）和自己的手牌判断，会合理地虚张声势与质疑。

# 选项
- AI 电脑：开启后，电脑的质疑/阻止/行动选择由大模型给出（只提供该电脑可见的信息），模型回复不合法时自动使用内置策略。
''';

class Coup extends GameEngine with LightLog {
  Coup(super.setup);

  List<String> deck = [];
  late List<List<String>> hands = [for (var i = 0; i < players; i++) <String>[]];
  late List<List<String>> revealed = [for (var i = 0; i < players; i++) <String>[]];
  late List<int> coins = List.filled(players, 2);
  late List<int> outOrder = List.filled(players, 0);
  int _outs = 0;
  int turn = 0;

  /// action / respond / block / respondBlock / lose / exchange / over
  String phase = 'action';
  String action = '';
  int actor = -1;
  int target = -1;
  int blocker = -1;
  String blockRole = '';
  Set<int> passed = {};
  int loser = -1;
  String loseWhy = '';
  void Function()? _afterLose;
  List<String> exchangeCards = [];
  List<String> _drawn = [];
  Map<String, dynamic>? lastEvent;

  /// Public claim history (for bots and the UI): roles each seat has claimed and not been caught lying about.
  late List<Set<String>> claims = [for (var i = 0; i < players; i++) <String>{}];
  int _serial = 0;
  final _ai = AiSlot();

  bool alive(int s) => hands[s].isNotEmpty;
  List<int> get aliveSeats => [for (var i = 0; i < players; i++) if (alive(i)) i];

  @override
  void start() {
    deck = [for (final r in coupRoles) for (var k = 0; k < 3; k++) r]..shuffle(rng);
    for (var i = 0; i < players; i++) {
      hands[i] = [deck.removeLast(), deck.removeLast()];
    }
    turn = rng.nextInt(players);
    if (players == 2) coins[turn] = 1;
    say('政变开始！${name(turn)} 先行动');
  }

  @override
  bool get isOver => phase == 'over';

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'action':
        return [turn];
      case 'respond':
        return [for (final s in aliveSeats) if (s != actor && !passed.contains(s)) s];
      case 'block':
        return [for (final s in _blockers()) if (!passed.contains(s)) s];
      case 'respondBlock':
        return [for (final s in aliveSeats) if (s != blocker && !passed.contains(s)) s];
      case 'lose':
        return [loser];
      case 'exchange':
        return [actor];
    }
    return const [];
  }

  List<int> _blockers() {
    if (action == 'foreignaid') return [for (final s in aliveSeats) if (s != actor) s];
    if ((action == 'assassinate' || action == 'steal') && target >= 0 && alive(target)) return [target];
    return const [];
  }

  @override
  List<int>? get placings => isOver ? placingsFromElimination(outOrder) : null;

  @override
  bool get canResign => !isOver;

  @override
  void resign(int seat) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players || !alive(seat)) throw GameError('你已经出局了');
    say('${name(seat)} 认输');
    final involved = seat == actor || seat == target || seat == blocker || seat == loser || seat == turn;
    while (hands[seat].isNotEmpty) {
      _reveal(seat, hands[seat].first, '认输');
    }
    if (_checkOver()) return;
    if (phase == 'exchange' && seat == actor) {
      deck.addAll(_drawn);
      deck.shuffle(rng);
      _drawn = [];
    }
    if (involved && phase != 'action') {
      say('当前行动取消');
      _nextTurn();
    } else if (phase == 'action' && seat == turn) {
      _nextTurn();
    } else {
      _maybeAllPassed();
    }
  }

  // ---------------------------------------------------------------- flow

  void _reveal(int s, String role, String why) {
    hands[s].remove(role);
    revealed[s].add(role);
    say('${name(s)} 翻开了 ${_rn(role)}（$why）');
    if (hands[s].isEmpty) {
      outOrder[s] = ++_outs;
      say('${name(s)} 失去全部影响力，出局');
    }
  }

  bool _checkOver() {
    final a = aliveSeats;
    if (a.length <= 1) {
      phase = 'over';
      if (a.isNotEmpty) say('游戏结束！${name(a.first)} 获胜');
      return true;
    }
    return false;
  }

  void _loseInfluence(int s, String why, void Function() then) {
    if (!alive(s)) {
      then();
      return;
    }
    if (hands[s].length == 1) {
      _reveal(s, hands[s].first, why);
      then();
      return;
    }
    phase = 'lose';
    loser = s;
    loseWhy = why;
    _afterLose = then;
  }

  void _nextTurn() {
    if (_checkOver()) return;
    var s = (turn + 1) % players;
    while (!alive(s)) {
      s = (s + 1) % players;
    }
    turn = s;
    phase = 'action';
    action = '';
    actor = -1;
    target = -1;
    blocker = -1;
    blockRole = '';
    passed = {};
    loser = -1;
    exchangeCards = [];
  }

  /// Prove [s] holds [role]: shuffle it back and draw a replacement.
  void _proveAndSwap(int s, String role) {
    hands[s].remove(role);
    deck.add(role);
    deck.shuffle(rng);
    hands[s].add(deck.removeLast());
    say('${name(s)} 亮出 ${_rn(role)} 证明了宣称，洗回牌堆并补摸一张');
  }

  void _blockStage() {
    if (_checkOver()) return;
    if (!alive(actor)) {
      _nextTurn();
      return;
    }
    final b = _blockers();
    if (b.isEmpty) {
      _perform();
      return;
    }
    phase = 'block';
    passed = {};
  }

  void _perform() {
    if (_checkOver()) return;
    final a = actor;
    switch (action) {
      case 'income':
        coins[a] += 1;
      case 'foreignaid':
        coins[a] += 2;
        say('${name(a)} 获得外援 2 金币');
      case 'tax':
        coins[a] += 3;
        say('${name(a)} 征税 3 金币');
      case 'steal':
        if (alive(target)) {
          final n = min(2, coins[target]);
          coins[target] -= n;
          coins[a] += n;
          say('${name(a)} 从 ${name(target)} 处勒索了 $n 金币');
        }
      case 'assassinate':
        if (alive(target)) {
          _loseInfluence(target, '被刺杀', _nextTurn);
          return;
        }
      case 'coup':
        _loseInfluence(target, '被政变', _nextTurn);
        return;
      case 'exchange':
        final n = min(2, deck.length);
        _drawn = [for (var i = 0; i < n; i++) deck.removeLast()];
        exchangeCards = [...hands[a], ..._drawn];
        phase = 'exchange';
        return;
    }
    _nextTurn();
  }

  void _maybeAllPassed() {
    if (phase == 'respond' && waitingFor.isEmpty) {
      _blockStage();
    } else if (phase == 'block' && waitingFor.isEmpty) {
      _perform();
    } else if (phase == 'respondBlock' && waitingFor.isEmpty) {
      say('阻止成立，${name(actor)} 的${coupActionNames[action]}无效');
      lastEvent = {'type': 'blocked', 'seat': blocker, 'role': blockRole};
      _nextTurn();
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players || !alive(seat)) throw GameError('你已经出局了');
    final type = asStr(a['type']);
    switch (phase) {
      case 'action':
        if (seat != turn) throw GameError('还没轮到你');
        _declare(seat, type, asInt(a['target']));
      case 'respond':
        if (seat == actor || passed.contains(seat)) throw GameError('你不需要回应');
        if (type == 'pass') {
          passed.add(seat);
          _maybeAllPassed();
        } else if (type == 'challenge') {
          _challengeAction(seat);
        } else {
          throw GameError('请选择质疑或放行');
        }
      case 'block':
        if (!_blockers().contains(seat) || passed.contains(seat)) throw GameError('你不能阻止这个行动');
        if (type == 'pass') {
          passed.add(seat);
          _maybeAllPassed();
        } else if (type == 'block') {
          final role = asStr(a['role']);
          if (!coupBlockRoles(action).contains(role)) throw GameError('这个角色不能阻止该行动');
          blocker = seat;
          blockRole = role;
          claims[seat].add(role);
          passed = {};
          phase = 'respondBlock';
          lastEvent = {'type': 'block', 'seat': seat, 'role': role};
          say('${name(seat)} 宣称${_rn(role)}，阻止${coupActionNames[action]}');
        } else {
          throw GameError('请选择阻止或放行');
        }
      case 'respondBlock':
        if (seat == blocker || passed.contains(seat)) throw GameError('你不需要回应');
        if (type == 'pass') {
          passed.add(seat);
          _maybeAllPassed();
        } else if (type == 'challenge') {
          _challengeBlock(seat);
        } else {
          throw GameError('请选择质疑或放行');
        }
      case 'lose':
        if (seat != loser) throw GameError('等待 ${name(loser)} 选择失去的影响力');
        final r = asStr(a['card']);
        if (type != 'lose' || !hands[seat].contains(r)) throw GameError('请选择一张你的角色牌翻开');
        _reveal(seat, r, loseWhy);
        loser = -1;
        final f = _afterLose!;
        _afterLose = null;
        f();
      case 'exchange':
        if (seat != actor) throw GameError('等待 ${name(actor)} 交换');
        if (type != 'exchange') throw GameError('请选择要保留的牌');
        final keep = [for (final k in (a['keep'] is List ? a['keep'] as List : const [])) asStr(k)];
        final need = hands[seat].length;
        if (keep.length != need) throw GameError('请保留 $need 张牌');
        final pool = List.of(exchangeCards);
        for (final k in keep) {
          if (!pool.remove(k)) throw GameError('你不能保留这张牌');
        }
        hands[seat] = keep;
        deck.addAll(pool);
        deck.shuffle(rng);
        exchangeCards = [];
        say('${name(seat)} 完成交换');
        _nextTurn();
      default:
        throw GameError('请稍候');
    }
    _serial++;
  }

  void _declare(int seat, String type, int t) {
    if (!coupActionNames.containsKey(type)) throw GameError('未知行动');
    if (coins[seat] >= 10 && type != 'coup') throw GameError('持有 10 枚以上金币时必须发动政变');
    final needsTarget = type == 'coup' || type == 'assassinate' || type == 'steal';
    if (needsTarget) {
      if (t < 0 || t >= players || t == seat || !alive(t)) throw GameError('请选择一名存活的其他玩家');
    } else {
      t = -1;
    }
    if (type == 'coup' && coins[seat] < 7) throw GameError('政变需要 7 金币');
    if (type == 'assassinate' && coins[seat] < 3) throw GameError('刺杀需要 3 金币');
    if (type == 'steal' && coins[t] <= 0) throw GameError('对方没有金币可以勒索');
    action = type;
    actor = seat;
    target = t;
    blocker = -1;
    blockRole = '';
    passed = {};
    if (type == 'coup') coins[seat] -= 7;
    if (type == 'assassinate') coins[seat] -= 3;
    final role = coupActionRole(type);
    if (role != null) claims[seat].add(role);
    lastEvent = {'type': 'action', 'seat': seat, 'action': type, 'target': t};
    say('${name(seat)} ${role != null ? '宣称${_rn(role)}，' : ''}发动${coupActionNames[type]}${t >= 0 ? ' → ${name(t)}' : ''}');
    if (type == 'income') say('${name(seat)} 获得 1 金币');
    if (role != null) {
      phase = 'respond';
    } else if (type == 'foreignaid') {
      _blockStage();
    } else {
      _perform();
    }
  }

  void _challengeAction(int c) {
    final role = coupActionRole(action)!;
    say('${name(c)} 质疑 ${name(actor)} 的${_rn(role)}');
    if (hands[actor].contains(role)) {
      lastEvent = {'type': 'challengeFail', 'seat': c, 'against': actor, 'role': role};
      _proveAndSwap(actor, role);
      _loseInfluence(c, '质疑失败', _blockStage);
    } else {
      lastEvent = {'type': 'challengeWin', 'seat': c, 'against': actor, 'role': role};
      say('${name(actor)} 没有${_rn(role)}，质疑成功');
      claims[actor].remove(role);
      if (action == 'assassinate') coins[actor] += 3;
      _loseInfluence(actor, '虚张声势被识破', _nextTurn);
    }
  }

  void _challengeBlock(int c) {
    final role = blockRole;
    say('${name(c)} 质疑 ${name(blocker)} 的${_rn(role)}');
    if (hands[blocker].contains(role)) {
      lastEvent = {'type': 'challengeFail', 'seat': c, 'against': blocker, 'role': role};
      _proveAndSwap(blocker, role);
      say('阻止成立，${name(actor)} 的${coupActionNames[action]}无效');
      _loseInfluence(c, '质疑失败', _nextTurn);
    } else {
      lastEvent = {'type': 'challengeWin', 'seat': c, 'against': blocker, 'role': role};
      say('${name(blocker)} 没有${_rn(role)}，阻止无效');
      claims[blocker].remove(role);
      _loseInfluence(blocker, '虚张声势被识破', _perform);
    }
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final showAll = isOver;
    return {
      'players': players,
      'phase': phase,
      'turn': turn,
      'action': action,
      'actor': actor,
      'target': target,
      'blocker': blocker,
      'blockRole': blockRole,
      'claimRole': coupActionRole(action),
      'blockRoles': coupBlockRoles(action),
      'canBlock': me && phase == 'block' && _blockers().contains(seat) && !passed.contains(seat),
      'waiting': waitingFor,
      'passed': passed.toList(),
      'loser': loser,
      'loseWhy': loseWhy,
      'coins': coins,
      'handCounts': [for (final h in hands) h.length],
      'hand': me ? hands[seat] : <String>[],
      'hands': showAll ? hands : null,
      'revealed': revealed,
      'alive': [for (var i = 0; i < players; i++) alive(i)],
      'exchange': me && phase == 'exchange' && seat == actor ? exchangeCards : <String>[],
      'deck': deck.length,
      'claims': [for (final c in claims) c.toList()],
      'lastEvent': lastEvent,
      'winner': isOver && aliveSeats.isNotEmpty ? aliveSeats.first : -1,
      'log': recentLogs(14),
    };
  }

  // ---------------------------------------------------------------- bot

  static const _value = {'duke': 5.0, 'assassin': 4.2, 'captain': 4.0, 'contessa': 3.6, 'ambassador': 2.6};

  /// Copies of [role] [me] can account for (face-up everywhere + own hand).
  int _known(int me, String role) =>
      revealed.fold(0, (a, r) => a + r.where((x) => x == role).length) + hands[me].where((x) => x == role).length;

  double _threat(int s) => hands[s].length * 10 + coins[s] + (claims[s].contains('assassin') ? 3 : 0);

  List<int> _opponents(int me) => [for (final s in aliveSeats) if (s != me) s];

  int _strongest(int me, {bool Function(int)? ok}) {
    final opp = _opponents(me).where((s) => ok == null || ok(s)).toList();
    if (opp.isEmpty) return -1;
    opp.sort((a, b) => _threat(b).compareTo(_threat(a)));
    return opp.first;
  }

  /// Would claiming [role] be a risky bluff for [me]?
  double _bluffRisk(int me, String role) {
    final k = _known(me, role);
    if (k >= 3) return 1;
    return 0.15 + k * 0.3;
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (!waitingFor.contains(seat)) return null;
    final h = _heuristic(seat);
    if (aiOn && (phase == 'action' || phase == 'respond' || phase == 'block' || phase == 'respondBlock')) {
      final opts = _legalOptions(seat);
      if (opts.length > 1) {
        final r = _ai.poll(setup.ai!, 'coup:$_serial:$seat', () => _aiRequest(seat, opts));
        if (r.pending) return null;
        final pick = _parseAi(r.text, opts.length);
        if (pick != null) return opts[pick];
      }
    }
    return h;
  }

  int? _parseAi(String? t, int n) {
    if (t == null) return null;
    final bare = int.tryParse(t.trim());
    final j = AiText.json(t);
    final v = j?['choice'] ?? bare;
    final i = v is int ? v : (v is String ? int.tryParse(v) : null);
    if (i == null || i < 1 || i > n) return null;
    return i - 1;
  }

  String _describe(Map<String, dynamic> o) {
    final t = o['type'];
    switch (t) {
      case 'pass':
        return '放行（不质疑/不阻止）';
      case 'challenge':
        return phase == 'respondBlock' ? '质疑 ${name(blocker)} 的${_rn(blockRole)}' : '质疑 ${name(actor)} 的${_rn(coupActionRole(action)!)}';
      case 'block':
        return '宣称${_rn(o['role'] as String)}阻止';
      default:
        final role = coupActionRole(t as String);
        final tg = asInt(o['target']);
        return '${coupActionNames[t]}${role != null ? '（宣称${_rn(role)}）' : ''}${tg >= 0 ? ' 目标 ${name(tg)}' : ''}';
    }
  }

  AiRequest _aiRequest(int seat, List<Map<String, dynamic>> opts) {
    final b = StringBuffer()
      ..writeln('你是 ${name(seat)}，你的暗牌：${hands[seat].map(_rn).join('、')}，金币 ${coins[seat]}。')
      ..writeln('其他玩家：');
    for (final s in _opponents(seat)) {
      b.writeln('- ${name(s)}：暗牌 ${hands[s].length} 张，金币 ${coins[s]}，已翻开 ${revealed[s].map(_rn).join('、')}，曾宣称 ${claims[s].map(_rn).join('、')}');
    }
    b.writeln('最近发生：');
    for (final l in recentLogs(8)) {
      b.writeln('- $l');
    }
    if (phase != 'action') b.writeln('当前：${name(actor)} 发动${coupActionNames[action]}${target >= 0 ? ' → ${name(target)}' : ''}${blocker >= 0 ? '，${name(blocker)} 宣称${_rn(blockRole)}阻止' : ''}。');
    b.writeln('可选操作：');
    for (var i = 0; i < opts.length; i++) {
      b.writeln('${i + 1}. ${_describe(opts[i])}');
    }
    b.writeln('只回复 JSON：{"choice": 序号}');
    return AiRequest(
      system: '你在玩桌游《政变 Coup》，是一名精明的玩家。可以虚张声势，也要判断别人是否在虚张声势。权衡风险，只用给出的信息。',
      prompt: b.toString(),
      maxTokens: 60,
    );
  }

  List<Map<String, dynamic>> _legalOptions(int seat) {
    switch (phase) {
      case 'action':
        if (coins[seat] >= 10) return [for (final t in _opponents(seat)) {'type': 'coup', 'target': t}];
        return [
          {'type': 'income'},
          {'type': 'foreignaid'},
          {'type': 'tax'},
          {'type': 'exchange'},
          if (coins[seat] >= 7) for (final t in _opponents(seat)) {'type': 'coup', 'target': t},
          if (coins[seat] >= 3) for (final t in _opponents(seat)) {'type': 'assassinate', 'target': t},
          for (final t in _opponents(seat))
            if (coins[t] > 0) {'type': 'steal', 'target': t},
        ];
      case 'respond':
      case 'respondBlock':
        return [
          {'type': 'pass'},
          {'type': 'challenge'},
        ];
      case 'block':
        return [
          {'type': 'pass'},
          for (final r in coupBlockRoles(action)) {'type': 'block', 'role': r},
        ];
    }
    return const [];
  }

  Map<String, dynamic> _heuristic(int seat) {
    final lvl = botLevel;
    final my = hands[seat];
    switch (phase) {
      case 'lose':
        final sorted = List.of(my)..sort((a, b) => _value[a]!.compareTo(_value[b]!));
        return {'type': 'lose', 'card': lvl == 0 ? my[rng.nextInt(my.length)] : sorted.first};
      case 'exchange':
        final need = my.length;
        final pool = List.of(exchangeCards);
        final keep = <String>[];
        if (lvl == 0) {
          pool.shuffle(rng);
          keep.addAll(pool.take(need));
        } else {
          pool.sort((a, b) => _value[b]!.compareTo(_value[a]!));
          // prefer two different strong roles (more bluff-proof options)
          final rest = <String>[];
          for (final c in pool) {
            if (keep.length < need && !keep.contains(c)) {
              keep.add(c);
            } else {
              rest.add(c);
            }
          }
          while (keep.length < need) {
            keep.add(rest.removeAt(0));
          }
        }
        return {'type': 'exchange', 'keep': keep};
      case 'action':
        return _chooseAction(seat);
      case 'respond':
        return {'type': _shouldChallenge(seat, actor, coupActionRole(action)!) ? 'challenge' : 'pass'};
      case 'block':
        final roles = coupBlockRoles(action);
        for (final r in roles) {
          if (my.contains(r)) return {'type': 'block', 'role': r};
        }
        // bluff a block?
        final r = roles.reduce((a, b) => _bluffRisk(seat, a) <= _bluffRisk(seat, b) ? a : b);
        final risk = _bluffRisk(seat, r);
        double want;
        if (action == 'assassinate') {
          want = my.length == 1 ? 0.95 : 0.35; // dying anyway if we do nothing
        } else if (action == 'steal') {
          want = coins[seat] >= 2 ? 0.3 : 0.1;
        } else {
          want = 0.12;
        }
        if (lvl == 0) want *= 0.5;
        if (lvl >= 2 && risk >= 0.7 && !(action == 'assassinate' && my.length == 1)) want = 0;
        if (risk >= 1) want = 0;
        return rng.nextDouble() < want * (1 - risk * 0.6) ? {'type': 'block', 'role': r} : {'type': 'pass'};
      case 'respondBlock':
        return {'type': _shouldChallenge(seat, blocker, blockRole) ? 'challenge' : 'pass'};
    }
    return {'type': 'pass'};
  }

  bool _shouldChallenge(int me, int claimant, String role) {
    final lvl = botLevel;
    final k = _known(me, role);
    if (k >= 3) return lvl > 0 || rng.nextDouble() < 0.7; // impossible claim
    final responders = max(1, aliveSeats.length - 1);
    var p = 0.04 + k * 0.12;
    // stakes: an assassination on me (only after the claim, i.e. respond phase)
    final lethal = phase == 'respond' && action == 'assassinate' && target == me;
    if (lethal) {
      if (hands[me].contains('contessa')) return false; // just block
      if (hands[me].length == 1) p = k >= 1 ? 0.6 : 0.35;
    }
    // my action is being blocked
    if (phase == 'respondBlock' && actor == me) {
      p += action == 'assassinate' ? 0.15 : 0.08;
    }
    if (phase == 'respond' && action == 'steal' && target == me && coins[me] >= 2) p += 0.06;
    if (phase == 'respond' && action == 'tax' && coins[claimant] >= 4) p += 0.05;
    // a claimant who has claimed many different roles is suspicious
    if (claims[claimant].length >= 3) p += 0.12;
    if (hands[me].length == 1 && !lethal) p *= 0.4;
    if (lvl == 0) p = 0.08;
    if (lvl == 2) p *= 1.1;
    if (!lethal && phase != 'respondBlock') p /= responders * 0.6 + 0.4;
    return rng.nextDouble() < p;
  }

  Map<String, dynamic> _chooseAction(int seat) {
    final lvl = botLevel;
    final my = hands[seat];
    final c = coins[seat];
    final strongest = _strongest(seat);
    if (c >= 10 || (c >= 7 && (lvl > 0 || rng.nextDouble() < 0.5))) return {'type': 'coup', 'target': strongest};
    if (lvl == 0) {
      final opts = _legalOptions(seat);
      return opts[rng.nextInt(opts.length)];
    }
    final bluff = lvl == 2 ? 0.3 : 0.22;
    bool canClaim(String r) => my.contains(r) || (rng.nextDouble() < bluff && _bluffRisk(seat, r) < 0.6);

    // assassinate
    if (c >= 3) {
      final t = _strongest(seat, ok: (s) => !claims[s].contains('contessa') || lvl < 2);
      if (t >= 0 && (my.contains('assassin') || (rng.nextDouble() < bluff * 0.6 && _bluffRisk(seat, 'assassin') < 0.5))) {
        return {'type': 'assassinate', 'target': t};
      }
    }
    if (my.contains('duke')) return {'type': 'tax'};
    final stealT = _strongest(seat, ok: (s) => coins[s] >= 2 && !claims[s].contains('captain') && !claims[s].contains('ambassador'));
    if (my.contains('captain') && stealT >= 0) return {'type': 'steal', 'target': stealT};
    if (canClaim('duke')) return {'type': 'tax'};
    if (my.contains('ambassador') && (my.every((r) => _value[r]! < 4) || rng.nextDouble() < 0.3)) return {'type': 'exchange'};
    if (stealT >= 0 && canClaim('captain')) return {'type': 'steal', 'target': stealT};
    final dukeClaimed = _opponents(seat).any((s) => claims[s].contains('duke'));
    if (!dukeClaimed || rng.nextDouble() < 0.25) return {'type': 'foreignaid'};
    return {'type': 'income'};
  }
}
