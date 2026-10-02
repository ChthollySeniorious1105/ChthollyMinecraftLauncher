/// 狼人杀 engine (the engine is the judge).
library;

import '../../src/ai.dart';
import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;
import 'roles.dart';

part 'werewolf_view.dart';
part 'werewolf_bot.dart';

/// Phases: night → [sheriff_signup → speech(sheriff) → sheriff_vote] → (announce) →
/// direction → speech(day) → vote → [speech(pk) → vote] → night …
/// Interrupting tasks: lastwords / shoot / badge.
///
/// Night order: 魔术师 → 丘比特(首夜) → 野孩子(首夜) → 守卫 → 狼人/狼美人 → 女巫 → 预言家 → 乌鸦.
/// The magician must act before anyone else; the witch acts after the wolves;
/// the other roles act in parallel (their effects are resolved at dawn).
class Werewolf extends GameEngine {
  Werewolf(super.setup);

  static const maxDays = 20;
  static const maxText = 60;
  static const dayPhases = {'sheriff_signup', 'speech', 'sheriff_vote', 'direction', 'vote'};

  late List<String> roles;
  late List<bool> alive;
  late String board;
  late String winMode; // edge | city
  late String selfSave; // first | never | always
  late bool sheriffOn;

  String phase = 'night';
  int round = 1; // night N precedes day N
  String winner = ''; // good | wolf | lovers | draw
  String reason = '';

  // ---- night state
  final Map<int, int> wolfVotes = {};
  int wolfKill = -2; // -2 undecided, -1 empty knife
  int guardTarget = -2;
  int lastGuard = -1;
  int seerTarget = -2;
  bool witchDone = false;
  bool antidote = true;
  bool poisonLeft = true;
  bool savedTonight = false;
  int poisonTarget = -1;
  final Set<int> slept = {};
  List<int>? _killers;

  // magician
  bool magicDone = false;
  int swapA = -1, swapB = -1;
  final Set<int> swapped = {};
  // wolf beauty
  bool charmDone = false;
  int charmPick = -1; // number chosen tonight
  int charmed = -1; // seat currently charmed
  // crow
  int crowTarget = -2;
  int crowMark = -1; // seat cursed for the coming exile vote
  // cupid / lovers
  List<int> lovers = const [];
  bool loversThird = false;
  // wild child
  int wildModel = -1;
  final Set<int> wildTurned = {};
  // hidden wolf
  bool hiddenActive = false;
  // knight
  bool duelUsed = false;
  String resumePhase = '';

  /// Per-night record revealed at the end.
  final List<Map<String, dynamic>> nights = [];

  // ---- day state
  Map<int, String> pendingDeaths = {};
  bool announced = false;
  bool exploded = false;
  Map<String, dynamic>? dawn;
  int sheriff = -1;
  final Map<int, bool> signup = {};
  List<int> candidates = [];
  final Set<int> withdrawn = {};
  List<int> speechOrder = [];
  int speechIdx = 0;
  String speechKind = ''; // sheriff | sheriff_pk | day | pk
  List<int> pkList = [];
  final Map<int, int> votes = {};
  Map<String, dynamic>? lastVote;

  /// All public vote records (exile + sheriff).
  final List<Map<String, dynamic>> voteHist = [];
  final List<Map<String, dynamic>> speeches = [];

  /// Public seer claims: {'s','d','t','w'}.
  final List<Map<String, dynamic>> claims = [];

  // ---- deaths / reveals
  final Map<int, String> deathCause = {};
  final Map<int, int> deathDay = {};
  final Set<int> diedAtNight = {};
  final Map<int, String> revealed = {};
  final Set<int> idiotFlipped = {};

  // ---- task queue (badge / lastwords / shoot)
  final List<Map<String, dynamic>> tasks = [];
  Map<String, dynamic>? task;
  String cont = '';

  // ---- logs
  final List<Map<String, dynamic>> pubLog = [];
  late List<List<String>> privLog;
  late List<List<int>> seerChecks; // per seat (only the seer's is used): [seat, wolf?1:0]

  // ---- bot memory: the wolf team's chosen fake seer (wolf-side knowledge only)
  int _fakeSeer = -1;
  int _salt = 0;
  final AiSlot _ai = AiSlot();
  // heuristic speech (claim) chosen when the LLM request for a speech started
  final Map<String, Map<String, dynamic>> _aiSpeechBase = {};

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (winner == 'draw' || winner.isEmpty) return List.filled(players, 1);
    return [for (var s = 0; s < players; s++) campOf(s) == winner ? 1 : 2];
  }

  /// Night: only the wolf pack hears each other; everyone else is silent.
  /// Dead players only reach other dead players. Day: everyone.
  @override
  Set<int>? voiceListeners(int seat) {
    if (seat < 0 || seat >= players || isOver) return null;
    if (!alive[seat]) return {for (var s = 0; s < players; s++) if (s != seat && !alive[s]) s};
    if (phase == 'night' || phase == 'dawn') {
      if (!inPack(seat)) return <int>{};
      return {for (final s in aliveSeats) if (s != seat && inPack(s)) s};
    }
    return null;
  }

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => phase == 'night' ? 700 : 1300;

  List<int> get aliveSeats => [for (var s = 0; s < players; s++) if (alive[s]) s];

  /// Wolf camp (including the hidden wolf and a wild child who turned).
  bool isWolfSeat(int s) => werewolfIsWolf(roles[s]) || wildTurned.contains(s);

  /// What the seer sees: the hidden wolf is checked as good.
  bool seerSeesWolf(int s) => isWolfSeat(s) && roles[s] != 'hiddenWolf';

  /// Wolves that open their eyes together (the hidden wolf joins once active).
  bool inPack(int s) => isWolfSeat(s) && (roles[s] != 'hiddenWolf' || hiddenActive);

  /// Wolves [s] knows about (including itself); empty for non-wolves.
  Set<int> knownWolves(int s) {
    if (!isWolfSeat(s)) return const {};
    if (roles[s] == 'hiddenWolf') return {for (var i = 0; i < players; i++) if (isWolfSeat(i)) i};
    return {for (var i = 0; i < players; i++) if (inPack(i)) i};
  }

  int get cupidSeat => roles.indexOf('cupid');
  int get magicianSeat => roles.indexOf('magician');
  int get beautySeat => roles.indexOf('wolfBeauty');

  int loverOf(int s) => lovers.length == 2 && lovers.contains(s) ? (lovers[0] == s ? lovers[1] : lovers[0]) : -1;

  /// Third camp (lovers + cupid) when the lovers are one wolf + one good player.
  Set<int> get team3 => loversThird ? {...lovers, if (cupidSeat >= 0) cupidSeat} : const {};

  /// Magician swap: the seat really affected by a night action on number [t].
  int sw(int t) => t < 0 ? t : (t == swapA ? swapB : (t == swapB ? swapA : t));

  bool get magicPending => phase == 'night' && magicianSeat >= 0 && alive[magicianSeat] && !magicDone;

  /// Seats that take part in tonight's wolf kill.
  List<int> get killers => _killers ??= [for (final s in aliveSeats) if (inPack(s)) s];

  bool get wolvesDecided => wolfKill != -2 || killers.isEmpty;

  /// Recompute tonight's pack (after roles were changed externally, e.g. in tests).
  void rebuildNight() => _killers = null;

  String seatName(int s) => '${s + 1}号';

  @override
  void start() {
    board = setup.opt<String>('board', 'auto');
    final (lo, hi) = werewolfRange(board);
    if (players < lo || players > hi) {
      board = 'auto';
    }
    winMode = setup.opt<String>('win', 'edge');
    selfSave = setup.opt<String>('selfSave', 'first');
    sheriffOn = setup.opt<bool>('sheriff', true);
    final list = werewolfRoles(board, players);
    roles = shuffled(list, rng);
    alive = List.filled(players, true);
    privLog = [for (var s = 0; s < players; s++) <String>[]];
    seerChecks = [for (var s = 0; s < players; s++) <int>[]];
    final wolves = [for (var s = 0; s < players; s++) if (inPack(s)) s];
    _salt = rng.nextInt(100000);
    if (rng.nextDouble() < 0.4) _fakeSeer = wolves[rng.nextInt(wolves.length)];
    _pub('狼人杀开始！$players 人局：${werewolfBoardSummary(list)}，'
        '胜利条件：${winMode == 'edge' ? '屠边' : '屠城'}');
    for (var s = 0; s < players; s++) {
      _priv(s, '你的身份是【${werewolfRoleNames[roles[s]]}】');
      if (inPack(s)) {
        _priv(s, '你的狼队友：${wolves.where((w) => w != s).map(seatName).join('、')}');
      } else if (roles[s] == 'hiddenWolf') {
        _priv(s, '你是隐狼，狼人是：${wolves.map(seatName).join('、')}（他们不知道你）');
      }
    }
    _startNight(first: true);
  }

  void _pub(String t) {
    pubLog.add({'d': round, 'n': phase == 'night', 't': t});
    host.log(t);
  }

  void _priv(int s, String t) => privLog[s].add('第$round${phase == 'night' ? '夜' : '天'}：$t');

  // ================================================================ night

  void _startNight({bool first = false}) {
    if (isOver) return;
    if (!first) {
      if (round >= maxDays) {
        _finish('draw', '已进行 $maxDays 天，平局');
        return;
      }
      round++;
    }
    phase = 'night';
    wolfVotes.clear();
    wolfKill = -2;
    guardTarget = -2;
    seerTarget = -2;
    witchDone = false;
    savedTonight = false;
    poisonTarget = -1;
    slept.clear();
    magicDone = false;
    swapA = swapB = -1;
    charmDone = false;
    charmPick = -1;
    crowTarget = -2;
    crowMark = -1;
    votes.clear();
    pkList = [];
    speechOrder = [];
    speechKind = '';
    task = null;
    final hw = roles.indexOf('hiddenWolf');
    if (hw >= 0 && alive[hw] && !hiddenActive && !aliveSeats.any((s) => s != hw && isWolfSeat(s))) {
      hiddenActive = true;
      _priv(hw, '其他狼人已全部出局，你变成了普通狼人，从今晚起可以刀人');
    }
    _killers = null;
    _pub('第 $round 夜，天黑请闭眼');
  }

  /// The night duty of seat [s] tonight.
  String nightDuty(int s) {
    if (killers.contains(s)) return 'kill';
    return switch (roles[s]) {
      'seer' => 'check',
      'guard' => 'guard',
      'witch' => 'witch',
      'magician' => 'magic',
      'crow' => 'curse',
      'cupid' when round == 1 => 'link',
      'wildChild' when round == 1 => 'model',
      _ => 'sleep',
    };
  }

  bool nightDone(int s) {
    if (!alive[s]) return true;
    return switch (nightDuty(s)) {
      'kill' => wolfKill != -2 && (roles[s] != 'wolfBeauty' || charmDone),
      'check' => seerTarget != -2,
      'guard' => guardTarget != -2,
      'witch' => witchDone,
      'magic' => magicDone,
      'curse' => crowTarget != -2,
      'link' => lovers.isNotEmpty,
      'model' => wildModel >= 0,
      _ => slept.contains(s),
    };
  }

  /// Is [s] still expected to act tonight (for waitingFor)?
  bool nightWaiting(int s) {
    if (nightDone(s)) return false;
    if (killers.contains(s)) {
      final needVote = wolfKill == -2 && !wolfVotes.containsKey(s);
      return needVote || (roles[s] == 'wolfBeauty' && !charmDone);
    }
    return true;
  }

  bool canSelfSave() => switch (selfSave) {
        'always' => true,
        'never' => false,
        _ => round == 1,
      };

  int _target(Map<String, dynamic> a, String k, {bool allowNone = true, int notSelf = -1}) {
    final t = asInt(a[k]);
    if (t == -1 && allowNone) return -1;
    if (t < 0 || t >= players || !alive[t] || t == notSelf) {
      throw GameError(notSelf >= 0 ? '请选择一名其他存活玩家' : '请选择一名存活玩家');
    }
    return t;
  }

  void _nightAction(int s, String type, Map<String, dynamic> a) {
    if (!alive[s]) throw GameError('你已出局');
    final t = asInt(a['target']);
    final duty = nightDuty(s);
    // Only the seer's result is revealed immediately, so only she waits for the magician;
    // every other night effect is resolved at dawn (after the swap is known).
    if (type == 'check' && magicPending) throw GameError('请等待魔术师先行动');
    switch (type) {
      case 'magic':
        if (duty != 'magic') throw GameError('你不是魔术师');
        if (magicDone) throw GameError('今晚已经行动过了');
        final x = asInt(a['a']), y = asInt(a['b']);
        if (x >= 0 || y >= 0) {
          for (final p in [x, y]) {
            if (p < 0 || p >= players || !alive[p]) throw GameError('请选择两名存活玩家');
            if (swapped.contains(p)) throw GameError('${seatName(p)} 已经被交换过了');
          }
          if (x == y) throw GameError('请选择两名不同的玩家');
          swapA = x;
          swapB = y;
          swapped.addAll([x, y]);
          _priv(s, '你交换了 ${seatName(x)} 和 ${seatName(y)} 的号码');
        } else {
          _priv(s, '你今晚没有交换');
        }
        magicDone = true;
      case 'link':
        if (duty != 'link') throw GameError('现在不能连情侣');
        if (lovers.isNotEmpty) throw GameError('已经连过情侣了');
        final x = _target(a, 'a', allowNone: false), y = _target(a, 'b', allowNone: false);
        if (x == y) throw GameError('请选择两名不同的玩家');
        // Identity choices (cupid / wild child) are not affected by the magician.
        final p = x, q = y;
        lovers = [p, q]..sort();
        loversThird = isWolfSeat(p) != isWolfSeat(q);
        _priv(s, '你将 ${seatName(p)} 和 ${seatName(q)} 连为情侣${loversThird ? '（人狼恋：你们三人组成第三方）' : ''}');
        for (final l in lovers) {
          final o = loverOf(l);
          _priv(
              l,
              '你和 ${seatName(o)} 成为情侣，对方身份是【${werewolfRoleNames[roles[o]]}】'
              '${loversThird ? '。你们是人狼恋，与丘比特 ${seatName(s)} 组成第三方，需要其他人全部出局才能获胜' : ''}');
        }
      case 'model':
        if (duty != 'model') throw GameError('现在不能选择榜样');
        if (wildModel >= 0) throw GameError('已经选择过榜样了');
        wildModel = _target(a, 'target', allowNone: false, notSelf: s);
        _priv(s, '你选择了 ${seatName(wildModel)} 作为榜样');
      case 'charm':
        if (roles[s] != 'wolfBeauty' || duty != 'kill') throw GameError('你不是狼美人');
        if (charmDone) throw GameError('今晚已经魅惑过了');
        final c = _target(a, 'target', notSelf: s);
        charmPick = c;
        charmDone = true;
        _priv(s, c < 0 ? '你今晚没有魅惑' : '你魅惑了 ${seatName(c)}');
        for (final w in killers) {
          if (w != s) _priv(w, c < 0 ? '狼美人今晚没有魅惑' : '狼美人魅惑了 ${seatName(c)}');
        }
      case 'curse':
        if (duty != 'curse') throw GameError('你不是乌鸦');
        if (crowTarget != -2) throw GameError('今晚已经诅咒过了');
        crowTarget = _target(a, 'target', notSelf: s);
        _priv(s, crowTarget < 0 ? '你今晚没有诅咒' : '你诅咒了 ${seatName(crowTarget)}');
      case 'kill':
        if (duty != 'kill') throw GameError('你不能刀人');
        if (wolfKill != -2 || wolfVotes.containsKey(s)) throw GameError('今晚已经决定了');
        if (t != -1 && (t < 0 || t >= players || !alive[t])) throw GameError('请选择一名存活玩家');
        wolfVotes[s] = t;
        if (killers.every(wolfVotes.containsKey)) _resolveWolves(killers);
      case 'guard':
        if (duty != 'guard') throw GameError('你不是守卫');
        if (guardTarget != -2) throw GameError('今晚已经守护过了');
        if (t != -1 && (t < 0 || t >= players || !alive[t])) throw GameError('请选择一名存活玩家');
        if (t >= 0 && t == lastGuard) throw GameError('不能连续两晚守护同一名玩家');
        guardTarget = t;
        _priv(s, t < 0 ? '你今晚空守' : '你守护了 ${seatName(t)}');
      case 'check':
        if (duty != 'check') throw GameError('你不是预言家');
        if (seerTarget != -2) throw GameError('今晚已经查验过了');
        if (t < 0 || t >= players || !alive[t] || t == s) throw GameError('请选择一名其他存活玩家');
        seerTarget = t;
        final w = seerSeesWolf(sw(t));
        seerChecks[s].addAll([t, w ? 1 : 0]);
        _priv(s, '你查验了 ${seatName(t)}：${w ? '狼人' : '好人'}');
      case 'witch':
        if (duty != 'witch') throw GameError('你不是女巫');
        if (witchDone) throw GameError('今晚已经行动过了');
        if (!wolvesDecided) throw GameError('请等待狼人行动');
        final save = asBool(a['save']);
        final p = asInt(a['poison']);
        if (save && p >= 0) throw GameError('同一晚不能同时使用解药和毒药');
        if (save) {
          if (!antidote) throw GameError('解药已经用过了');
          if (wolfKill < 0) throw GameError('今晚没有人被刀');
          if (wolfKill == s && !canSelfSave()) throw GameError('当前规则不能自救');
          antidote = false;
          savedTonight = true;
          _priv(s, '你对 ${seatName(wolfKill)} 使用了解药');
        }
        if (p >= 0) {
          if (!poisonLeft) throw GameError('毒药已经用过了');
          if (p >= players || !alive[p] || p == s) throw GameError('请选择一名其他存活玩家');
          poisonLeft = false;
          poisonTarget = p;
          _priv(s, '你对 ${seatName(p)} 使用了毒药');
        }
        if (!save && p < 0) _priv(s, '你今晚没有用药');
        witchDone = true;
      case 'sleep':
        if (duty != 'sleep') throw GameError('请先完成你的夜间行动');
        slept.add(s);
      default:
        throw GameError('现在是夜晚');
    }
    if (aliveSeats.every(nightDone)) _dawn();
  }

  void _resolveWolves(List<int> wolves) {
    final cnt = <int, int>{};
    for (final w in wolves) {
      cnt[wolfVotes[w]!] = (cnt[wolfVotes[w]!] ?? 0) + 1;
    }
    final top = cnt.values.reduce((a, b) => a > b ? a : b);
    final tied = [for (final e in cnt.entries) if (e.value == top) e.key]..sort();
    wolfKill = tied[rng.nextInt(tied.length)];
    for (final w in wolves) {
      _priv(w, wolfKill < 0 ? '狼队今晚空刀' : '狼队今晚击杀 ${seatName(wolfKill)}');
    }
    // A dead (or absent) witch never blocks the night.
  }

  void _dawn() {
    final deaths = <int, String>{};
    // Guard and witch act on numbers; the swap is a bijection so comparing numbers is exact.
    if (wolfKill >= 0) {
      final guarded = guardTarget == wolfKill;
      if (guarded == savedTonight) deaths[sw(wolfKill)] = 'wolf';
    }
    if (poisonTarget >= 0) deaths[sw(poisonTarget)] = 'poison';
    final b = beautySeat;
    if (b >= 0 && alive[b] && killers.contains(b)) charmed = charmPick >= 0 ? sw(charmPick) : -1;
    if (crowTarget >= 0) crowMark = sw(crowTarget);
    _expandDeaths(deaths);
    nights.add({
      'n': round,
      'kill': wolfKill,
      'guard': guardTarget,
      'save': savedTonight ? wolfKill : -1,
      'poison': poisonTarget,
      'check': seerTarget,
      'swap': swapA >= 0 ? [swapA, swapB] : null,
      'charm': b >= 0 && killers.contains(b) && charmPick >= 0 ? sw(charmPick) : -1,
      'curse': crowTarget >= 0 ? sw(crowTarget) : -1,
      'link': round == 1 && lovers.isNotEmpty ? lovers : null,
      'model': round == 1 && wildModel >= 0 ? wildModel : -1,
      'deaths': (deaths.keys.toList()..sort()),
    });
    if (guardTarget != -2) lastGuard = guardTarget;
    pendingDeaths = deaths;
    announced = false;
    exploded = false;
    dawn = null;
    phase = 'dawn';
    _pub('第 $round 天，天亮了');
    if (round == 1 && sheriffOn) {
      _startElection();
    } else {
      _announce();
    }
  }

  // ================================================================ deaths & tasks

  void _announce() {
    announced = true;
    pkList = [];
    speechKind = '';
    final ds = pendingDeaths.keys.toList()..sort();
    dawn = {'d': round, 'deaths': ds};
    _pub(ds.isEmpty ? '昨夜是平安夜' : '昨夜死亡：${ds.map(seatName).join('、')}');
    cont = exploded ? 'night' : 'discuss';
    // Seats that already died during the election (e.g. exploded / taken) are not killed twice.
    pendingDeaths.removeWhere((s, _) => !alive[s]);
    _kill(pendingDeaths, night: true);
    pendingDeaths = {};
    _runTasks();
  }

  /// Add chained deaths: lovers (殉情) and the wolf beauty's charmed player.
  void _expandDeaths(Map<int, String> m) {
    var changed = true;
    while (changed) {
      changed = false;
      for (final s in m.keys.toList()) {
        final o = loverOf(s);
        if (o >= 0 && alive[o] && !m.containsKey(o)) {
          m[o] = 'love';
          changed = true;
        }
        if (roles[s] == 'wolfBeauty' && charmed >= 0 && alive[charmed] && !m.containsKey(charmed)) {
          m[charmed] = 'charm';
          changed = true;
        }
      }
    }
  }

  /// Kill a batch simultaneously (plus chained deaths); queue their tasks.
  void _kill(Map<int, String> batch, {bool front = false, bool night = false}) {
    final m = Map.of(batch);
    final direct = m.keys.toSet();
    _expandDeaths(m);
    final ds = m.keys.toList()..sort();
    for (final s in ds) {
      alive[s] = false;
      deathCause[s] = m[s]!;
      deathDay[s] = round;
      if (night) diedAtNight.add(s);
      if (!night && !direct.contains(s)) {
        _pub(m[s] == 'love' ? '${seatName(s)} 殉情出局' : '${seatName(s)} 被狼美人魅惑，随之殉情出局');
      }
    }
    final b = beautySeat;
    if (b >= 0 && m.containsKey(b)) charmed = -1;
    final wc = roles.indexOf('wildChild');
    if (wc >= 0 && alive[wc] && wildModel >= 0 && m.containsKey(wildModel) && !wildTurned.contains(wc)) {
      wildTurned.add(wc);
      _priv(wc, '你的榜样 ${seatName(wildModel)} 出局了，你变成了狼人，从下一晚起与狼人一起行动');
      final pack = aliveSeats.where((w) => inPack(w) && w != wc).toList();
      _priv(wc, '你的狼队友：${pack.isEmpty ? '无' : pack.map(seatName).join('、')}');
      for (final w in pack) {
        _priv(w, '野孩子 ${seatName(wc)} 加入了狼队');
      }
    }
    if (_checkWin()) return;
    final add = <Map<String, dynamic>>[];
    for (final s in ds) {
      final cause = m[s]!;
      final r = roles[s];
      final hasSkill = r == 'hunter' || r == 'wolfking';
      final blocked = const {'poison', 'love', 'charm'}.contains(cause);
      final can = hasSkill && !blocked && (r == 'hunter' || cause != 'wolf');
      if (hasSkill && !can) {
        _priv(
            s,
            switch (cause) {
              'poison' => '你被毒杀，无法发动技能',
              'love' || 'charm' => '你殉情出局，无法发动技能',
              _ => '你在夜里被刀，无法发动技能',
            });
      }
      // Every dying player gets the same "skill" prompt so roles are not exposed.
      if (cause != 'explode' || r == 'wolfking') add.add({'k': 'shoot', 's': s, 'can': can});
      if (sheriff == s) add.add({'k': 'badge', 's': s});
      final lw = night ? round == 1 : const {'exile', 'shot', 'love', 'charm'}.contains(cause);
      if (lw) add.add({'k': 'lastwords', 's': s});
    }
    if (front) {
      tasks.insertAll(0, add);
    } else {
      tasks.addAll(add);
    }
  }

  void _runTasks() {
    if (isOver) return;
    while (tasks.isNotEmpty) {
      final t = tasks.removeAt(0);
      final s = t['s'] as int;
      final k = t['k'] as String;
      if (k == 'badge' && sheriff != s) continue;
      if (k == 'shoot' && aliveSeats.isEmpty) continue;
      task = t;
      phase = k;
      if (k == 'lastwords') _pub('请 ${seatName(s)} 发表遗言');
      if (k == 'badge') _pub('警长 ${seatName(s)} 出局，请移交或撕毁警徽');
      if (k == 'shoot') _pub('等待 ${seatName(s)} 确认是否发动技能');
      return;
    }
    task = null;
    switch (cont) {
      case 'announce':
        _announce();
      case 'discuss':
        _startDiscussion();
      case 'resume':
        if (resumePhase == 'speech' && speechOrder.isNotEmpty) {
          phase = 'speech';
          _skipInvalidSpeakers();
        } else {
          _startDiscussion();
        }
      default:
        _startNight();
    }
  }

  void _taskAction(int s, String type, Map<String, dynamic> a) {
    final t = task!;
    if (s != t['s']) throw GameError('请等待 ${seatName(t['s'] as int)} 操作');
    final target = asInt(a['target']);
    switch (phase) {
      case 'lastwords':
        if (type != 'end') throw GameError('请发表遗言');
        _addSpeech(s, 'lastwords', a);
      case 'badge':
        if (type != 'badge') throw GameError('请移交警徽');
        if (target >= 0) {
          if (target >= players || !alive[target]) throw GameError('只能移交给存活玩家');
          sheriff = target;
          _pub('警徽移交给 ${seatName(target)}');
        } else {
          sheriff = -1;
          _pub('${seatName(s)} 撕毁了警徽');
        }
      case 'shoot':
        if (type != 'shoot') throw GameError('请选择是否发动技能');
        final king = roles[s] == 'wolfking';
        if (target >= 0 && t['can'] != true) throw GameError('你没有可以发动的技能');
        if (target >= 0) {
          if (target >= players || !alive[target] || target == s) throw GameError('请选择一名存活玩家');
          revealed[s] = roles[s];
          _pub(king ? '狼王 ${seatName(s)} 带走了 ${seatName(target)}' : '猎人 ${seatName(s)} 开枪带走了 ${seatName(target)}');
          task = null;
          _kill({target: 'shot'}, front: true);
        } else {
          _pub('${seatName(s)} 没有发动技能');
          if (t['can'] == true) _priv(s, '你选择不发动技能');
        }
      default:
        throw GameError('现在不能操作');
    }
    task = null;
    _runTasks();
  }

  // ================================================================ sheriff

  void _startElection() {
    phase = 'sheriff_signup';
    signup.clear();
    candidates = [];
    withdrawn.clear();
    _pub('警长竞选开始，请选择是否上警');
  }

  void _electionLost(String why) {
    candidates = [];
    _pub('$why，警徽流失');
    _announce();
  }

  void _afterSignup() {
    candidates = [for (final s in aliveSeats) if (signup[s] == true) s];
    if (candidates.isEmpty) return _electionLost('无人上警');
    if (candidates.length == aliveSeats.length) return _electionLost('全员上警，无人投票');
    _pub('上警玩家：${candidates.map(seatName).join('、')}');
    final st = rng.nextInt(candidates.length);
    _beginSpeeches([...candidates.sublist(st), ...candidates.sublist(0, st)], 'sheriff');
  }

  List<int> get _sheriffVoters => [
        for (final s in aliveSeats)
          if (!withdrawn.contains(s) && !candidates.contains(s)) s
      ];

  void _afterSheriffSpeeches() {
    if (speechKind == 'sheriff') {
      if (candidates.isEmpty) return _electionLost('所有候选人都已退水');
      if (candidates.length == 1) return _elect(candidates.first);
    }
    if (_sheriffVoters.isEmpty) return _electionLost('没有可投票的玩家');
    phase = 'sheriff_vote';
    votes.clear();
    _pub(speechKind == 'sheriff_pk' ? '警长PK投票：${pkList.map(seatName).join('、')}' : '警长投票开始');
  }

  void _elect(int s) {
    sheriff = s;
    candidates = [];
    _pub('${seatName(s)} 当选警长（投票计 1.5 票）');
    _announce();
  }

  // ================================================================ speeches

  void _beginSpeeches(List<int> order, String kind) {
    speechOrder = order;
    speechIdx = 0;
    speechKind = kind;
    phase = 'speech';
    _skipInvalidSpeakers();
  }

  int get speaker => phase == 'speech' && speechIdx < speechOrder.length ? speechOrder[speechIdx] : -1;

  void _skipInvalidSpeakers() {
    while (speechIdx < speechOrder.length) {
      final s = speechOrder[speechIdx];
      final ok = alive[s] &&
          (speechKind != 'sheriff' || candidates.contains(s)) &&
          (speechKind != 'sheriff_pk' || pkList.contains(s));
      if (ok) return;
      speechIdx++;
    }
    switch (speechKind) {
      case 'sheriff':
      case 'sheriff_pk':
        _afterSheriffSpeeches();
      case 'day':
        _startVote(false);
      case 'pk':
        _startVote(true);
    }
  }

  void _addSpeech(int s, String kind, Map<String, dynamic> a) {
    var text = sanitizeText(asStr(a['text'])).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length > maxText) text = text.substring(0, maxText);
    Map<String, dynamic>? claim;
    final c = a['claim'];
    if (c is Map) {
      final t = asInt(c['target']);
      if (t >= 0 && t < players && t != s) {
        claim = {'s': s, 'd': round, 't': t, 'w': asBool(c['wolf'])};
        claims.add(claim);
      }
    }
    speeches.add({'d': round, 's': s, 'k': kind, 't': text, 'c': claim});
    final parts = <String>[
      if (claim != null) '【跳预言家】${seatName(claim['t'] as int)} 是${claim['w'] == true ? '狼人（查杀）' : '好人（金水）'}',
      if (text.isNotEmpty) text,
    ];
    final label = kind == 'lastwords' ? '遗言' : '发言';
    _pub('${seatName(s)} $label结束${parts.isEmpty ? '' : '：${parts.join(' ')}'}');
  }

  void _startDiscussion() {
    if (isOver) return;
    if (sheriff >= 0 && alive[sheriff]) {
      phase = 'direction';
      _pub('请警长 ${seatName(sheriff)} 选择发言顺序');
      return;
    }
    final ds = (dawn?['deaths'] as List?)?.cast<int>() ?? const <int>[];
    final start = ds.isNotEmpty ? (ds.first + 1) % players : (round - 1) % players;
    _beginSpeeches(_ring(start, 1), 'day');
    _pub('开始自由发言，从 ${seatName(speechOrder.first)} 开始');
  }

  /// Alive seats starting at [start] going in direction [dir].
  List<int> _ring(int start, int dir) => [
        for (var i = 0; i < players; i++)
          if (alive[((start + dir * i) % players + players) % players]) ((start + dir * i) % players + players) % players
      ];

  // ================================================================ votes

  List<int> get voteCands => pkList.isNotEmpty ? pkList : aliveSeats;

  List<int> get exileVoters => [
        for (final s in aliveSeats)
          if (!idiotFlipped.contains(s) && !pkList.contains(s)) s
      ];

  /// The crow's curse applies to the current exile vote.
  bool get crowActive => phase == 'vote' && crowMark >= 0 && alive[crowMark] && voteCands.contains(crowMark);

  void _startVote(bool pk) {
    if (pk) {
      pkList = [for (final s in pkList) if (alive[s]) s];
      if (pkList.isEmpty) {
        _pub('PK 玩家均已出局，今天无人被放逐');
        _startNight();
        return;
      }
    }
    if (exileVoters.isEmpty) {
      _pub('没有可投票的玩家，今天无人出局');
      _startNight();
      return;
    }
    phase = 'vote';
    votes.clear();
    _pub(pk ? 'PK 投票开始：${pkList.map(seatName).join('、')}' : '放逐投票开始');
    if (crowActive) _pub('${seatName(crowMark)} 被乌鸦诅咒，本轮放逐投票额外计 1 票');
  }

  List<int> get currentVoters => phase == 'vote' ? exileVoters : (phase == 'sheriff_vote' ? _sheriffVoters : const []);

  void _voteAction(int s, Map<String, dynamic> a) {
    if (!currentVoters.contains(s)) throw GameError('你没有投票权');
    if (votes.containsKey(s)) throw GameError('你已经投过票了');
    final t = asInt(a['target']);
    final cands = phase == 'vote' ? voteCands : (speechKind == 'sheriff_pk' ? pkList : candidates);
    if (t != -1 && !cands.contains(t)) throw GameError('只能投给候选玩家');
    if (t == s) throw GameError('不能投给自己');
    votes[s] = t;
    if (currentVoters.every(votes.containsKey)) {
      phase == 'vote' ? _resolveExile() : _resolveSheriff();
    }
  }

  (List<int>, List<List<num>>) _tally(bool weighted) {
    final score = <int, num>{};
    for (final e in votes.entries) {
      if (e.value < 0) continue;
      score[e.value] = (score[e.value] ?? 0) + (weighted && e.key == sheriff ? 1.5 : 1);
    }
    if (weighted && crowActive) score[crowMark] = (score[crowMark] ?? 0) + 1;
    final tally = [for (final e in score.entries) [e.key, e.value]]..sort((a, b) => b[1].compareTo(a[1]));
    if (score.isEmpty) return (<int>[], tally);
    final top = tally.first[1];
    return ([for (final t in tally) if (t[1] == top) t[0].toInt()]..sort(), tally);
  }

  Map<String, dynamic> _voteRecord(String kind, List<List<num>> tally, int out, List<int> tie) {
    final r = <String, dynamic>{
      'kind': kind,
      'd': round,
      'pk': pkList.isNotEmpty,
      'votes': [for (final e in votes.entries) [e.key, e.value]],
      'tally': tally,
      'out': out,
      'tie': tie,
      'crow': kind == 'exile' && crowActive ? crowMark : -1,
    };
    voteHist.add(r);
    return r;
  }

  void _resolveSheriff() {
    final (top, tally) = _tally(false);
    final pk = speechKind == 'sheriff_pk';
    if (top.length == 1) {
      lastVote = _voteRecord('sheriff', tally, top.first, const []);
      return _elect(top.first);
    }
    lastVote = _voteRecord('sheriff', tally, -1, top);
    if (top.isEmpty) return _electionLost('全员弃票');
    if (pk) return _electionLost('PK 后仍然平票');
    pkList = top;
    _pub('${top.map(seatName).join('、')} 平票，进入警长 PK');
    _beginSpeeches(List.of(top), 'sheriff_pk');
  }

  void _resolveExile() {
    final (top, tally) = _tally(true);
    final wasPk = pkList.isNotEmpty;
    if (top.length == 1) {
      lastVote = _voteRecord('exile', tally, top.first, const []);
      pkList = [];
      return _exile(top.first);
    }
    lastVote = _voteRecord('exile', tally, -1, top);
    if (top.isEmpty || wasPk) {
      pkList = [];
      _pub(top.isEmpty ? '全员弃票，今天无人出局' : 'PK 后仍然平票，今天无人出局');
      _startNight();
      return;
    }
    pkList = top;
    _pub('${top.map(seatName).join('、')} 平票，进入 PK 发言');
    _beginSpeeches(List.of(top), 'pk');
  }

  void _exile(int s) {
    if (roles[s] == 'idiot' && !idiotFlipped.contains(s)) {
      idiotFlipped.add(s);
      revealed[s] = 'idiot';
      _pub('${seatName(s)} 被放逐，翻牌亮出【白痴】身份，免于出局但失去投票权');
      if (sheriff == s) {
        sheriff = -1;
        _pub('白痴翻牌，警徽流失');
      }
      _startNight();
      return;
    }
    _pub('${seatName(s)} 被放逐出局');
    cont = 'night';
    _kill({s: 'exile'});
    _runTasks();
  }

  // ================================================================ day skills

  /// 狼美人 cannot self-explode; the hidden wolf only once it has become a normal wolf.
  bool canExplode(int s) =>
      s >= 0 && alive[s] && inPack(s) && roles[s] != 'wolfBeauty' && dayPhases.contains(phase);

  bool canDuel(int s) =>
      s >= 0 &&
      alive[s] &&
      roles[s] == 'knight' &&
      !duelUsed &&
      announced &&
      ((phase == 'speech' && (speechKind == 'day' || speechKind == 'pk')) || phase == 'direction');

  void _duel(int s, Map<String, dynamic> a) {
    if (roles[s] != 'knight') throw GameError('你不是骑士');
    if (duelUsed) throw GameError('决斗技能已经用过了');
    if (!canDuel(s)) throw GameError('现在不能决斗');
    final t = _target(a, 'target', allowNone: false, notSelf: s);
    duelUsed = true;
    revealed[s] = 'knight';
    if (isWolfSeat(t)) {
      revealed[t] = roles[t];
      _pub('骑士 ${seatName(s)} 翻牌与 ${seatName(t)} 决斗：${seatName(t)} 是狼人，决斗出局！立即进入黑夜');
      votes.clear();
      pkList = [];
      speechOrder = [];
      cont = 'night';
      _kill({t: 'duel'});
    } else {
      _pub('骑士 ${seatName(s)} 翻牌与 ${seatName(t)} 决斗：${seatName(t)} 是好人，骑士以死谢罪');
      resumePhase = phase;
      cont = 'resume';
      _kill({s: 'knight'});
    }
    _runTasks();
  }

  void _explode(int s, Map<String, dynamic> a) {
    if (s < 0 || !alive[s] || !isWolfSeat(s)) throw GameError('只有存活的狼人可以自爆');
    if (!inPack(s)) throw GameError('隐狼不能自爆');
    if (roles[s] == 'wolfBeauty') throw GameError('狼美人不能自爆');
    if (!dayPhases.contains(phase)) throw GameError('现在不能自爆');
    var take = -1;
    if (roles[s] == 'whiteWolfKing') take = _target(a, 'target', notSelf: s);
    revealed[s] = roles[s];
    _pub('${seatName(s)} 自爆！身份是【${werewolfRoleNames[roles[s]]}】'
        '${take >= 0 ? '，带走了 ${seatName(take)}' : ''}，直接进入黑夜');
    exploded = true;
    votes.clear();
    pkList = [];
    if (!announced) {
      if (candidates.isNotEmpty || phase == 'sheriff_signup') _pub('警长竞选中断，警徽流失');
      candidates = [];
      cont = 'announce';
    } else {
      cont = 'night';
    }
    speechOrder = [];
    _kill({s: 'explode', if (take >= 0) take: 'shot'});
    _runTasks();
  }

  // ================================================================ win

  bool _checkWin() {
    final all = aliveSeats;
    if (all.isEmpty) {
      _finish('draw', '所有玩家同归于尽');
      return true;
    }
    final t3 = team3;
    if (t3.isNotEmpty && alive[lovers[0]]) {
      // While the cross-camp lovers live, nobody else can win.
      if (all.every(t3.contains)) {
        _finish('lovers', '其他玩家全部出局（人狼恋）');
        return true;
      }
      return false;
    }
    final a = [for (final s in all) if (!t3.contains(s)) s];
    final wolves = a.where(isWolfSeat).length;
    final gods = a.where((s) => werewolfIsGod(roles[s])).length;
    final vill = a.where((s) => !isWolfSeat(s) && (roles[s] == 'villager' || roles[s] == 'wildChild')).length;
    final hasVill = roles.contains('villager') || roles.contains('wildChild');
    if (wolves == 0) {
      _finish('good', '所有狼人出局');
      return true;
    }
    if (winMode == 'edge') {
      if (gods == 0) {
        _finish('wolf', '神职全部出局（屠边）');
        return true;
      }
      if (vill == 0 && hasVill) {
        _finish('wolf', '平民全部出局（屠边）');
        return true;
      }
    } else if (gods + vill == 0) {
      _finish('wolf', '好人全部出局（屠城）');
      return true;
    }
    return false;
  }

  void _finish(String w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    tasks.clear();
    task = null;
    final camp = switch (w) { 'good' => '好人阵营', 'wolf' => '狼人阵营', 'lovers' => '情侣阵营', _ => '' };
    _pub('$camp${w == 'draw' ? '' : '获胜：'}$why');
  }

  /// Which camp [s] plays for (at the end of the game).
  String campOf(int s) => team3.contains(s) ? 'lovers' : (isWolfSeat(s) ? 'wolf' : 'good');

  // ================================================================ dispatch

  @override
  Map<String, dynamic> view(int seat) => buildView(seat);

  @override
  Map<String, dynamic>? bot(int seat) => botAction(seat);

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'night':
        // Everyone with a duty is waited on from the start of the night (the
        // witch even before the wolves decide): otherwise the per-seat clocks
        // the server publishes from waitingFor would reveal roles.
        return [for (final s in aliveSeats) if (nightWaiting(s)) s];
      case 'sheriff_signup':
        return [for (final s in aliveSeats) if (!signup.containsKey(s)) s];
      case 'speech':
        return speaker >= 0 ? [speaker] : const [];
      case 'lastwords':
      case 'badge':
      case 'shoot':
        return task == null ? const [] : [task!['s'] as int];
      case 'direction':
        return [sheriff];
      case 'vote':
      case 'sheriff_vote':
        return [for (final s in currentVoters) if (!votes.containsKey(s)) s];
      default:
        return const [];
    }
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('你是观众');
    final type = asStr(a['type']);
    if (type == 'explode') return _explode(seat, a);
    if (type == 'duel') return _duel(seat, a);
    switch (phase) {
      case 'night':
        _nightAction(seat, type, a);
      case 'sheriff_signup':
        if (type != 'run') throw GameError('请选择是否上警');
        if (!alive[seat] || signup.containsKey(seat)) throw GameError('你已经选择过了');
        signup[seat] = asBool(a['run']);
        if (aliveSeats.every(signup.containsKey)) _afterSignup();
      case 'speech':
        if (seat != speaker) throw GameError('还没轮到你发言');
        if (type == 'withdraw') {
          if (speechKind != 'sheriff') throw GameError('现在不能退水');
          candidates.remove(seat);
          withdrawn.add(seat);
          _pub('${seatName(seat)} 退水，放弃竞选');
        } else if (type == 'end') {
          _addSpeech(seat, speechKind, a);
        } else {
          throw GameError('请发言，结束后点击「结束发言」');
        }
        speechIdx++;
        _skipInvalidSpeakers();
      case 'direction':
        if (seat != sheriff) throw GameError('等待警长选择发言顺序');
        if (type != 'direction') throw GameError('请选择发言顺序');
        final dir = asInt(a['dir']) >= 0 ? 1 : -1;
        final order = _ring(sheriff + dir, dir)..remove(sheriff);
        order.add(sheriff);
        _pub('警长选择${dir > 0 ? '顺序（号码递增）' : '逆序（号码递减）'}发言，警长最后归票');
        _beginSpeeches(order, 'day');
      case 'vote':
      case 'sheriff_vote':
        if (type != 'vote') throw GameError('现在是投票阶段');
        _voteAction(seat, a);
      case 'lastwords':
      case 'badge':
      case 'shoot':
        _taskAction(seat, type, a);
      default:
        throw GameError('请稍候');
    }
  }
}
