import '../../src/engine.dart';
import 'util.dart';

/// 抵抗组织: no special roles. Spies know each other; leader proposes a team,
/// everyone votes, the team plays success/fail. Optional 计划卡 (simplified
/// plot cards, all "loyalty reveal" effects resolved right away): at the start
/// of every mission the leader draws one of 窃听/坦白/建立信任.
class Resistance extends GameEngine {
  Resistance(super.setup);

  late List<bool> spy;
  String phase = 'propose'; // plot propose vote mission over
  int leader = 0;
  int mission = 0;
  int rejects = 0;
  List<int> team = [];
  Map<int, bool> votes = {};
  Map<int, bool> cards = {};
  List<int?> results = List.filled(5, null);
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? lastVote;
  String winner = '';
  String reason = '';
  late List<double> suspicion;

  // plot cards
  bool get plotOn => setup.opt<bool>('plot', false);
  List<String> plotDeck = [];
  String plotCard = ''; // overheard / openup / confidence
  String plotStage = ''; // give / use
  int plotHolder = -1;
  Map<String, dynamic>? lastPlot; // public: {card, leader, holder, target}
  /// Private loyalty knowledge learned from plot cards: seat -> {seat(str): isSpy}.
  late List<Map<String, bool>> known;

  List<int> get sizes => resistanceMissionSizes[players]!;
  int get teamSize => sizes[mission];
  int failsNeeded(int m) => m == 3 && players >= 7 ? 2 : 1;
  int get successes => results.where((r) => r == 1).length;
  int get fails => results.where((r) => r == 0).length;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings => isOver ? [for (var s = 0; s < players; s++) spy[s] == (winner == 'spy') ? 1 : 2] : null;

  @override
  int get botDelayMs => 900;

  @override
  void start() {
    final n = resistanceSpyCount[players]!;
    spy = shuffled([for (var i = 0; i < players; i++) i < n], rng);
    suspicion = List.filled(players, 0);
    known = [for (var i = 0; i < players; i++) <String, bool>{}];
    leader = rng.nextInt(players);
    plotDeck = shuffled([
      for (var i = 0; i < 3; i++) ...['overheard', 'openup', 'confidence'],
    ], rng);
    host.log('抵抗组织开始！$players 人局，间谍 $n 人。${name(leader)} 担任首任队长');
    _beginMission();
  }

  @override
  List<int> get waitingFor => switch (phase) {
        'plot' => [plotStage == 'give' ? leader : plotHolder],
        'propose' => [leader],
        'vote' => [for (var s = 0; s < players; s++) if (!votes.containsKey(s)) s],
        'mission' => [for (final s in team) if (!cards.containsKey(s)) s],
        _ => const [],
      };

  void _finish(String w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    host.log('${w == 'res' ? '抵抗组织' : '间谍'}获胜：$why');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    if (seat < 0 || seat >= players) throw GameError('观众不能操作');
    final type = asStr(a['type']);
    switch (phase) {
      case 'plot':
        if (type != 'plot') throw GameError('请先处理计划卡');
        _plot(seat, asInt(a['target']));
        break;
      case 'propose':
        if (seat != leader) throw GameError('只有队长可以组队');
        if (type != 'propose') throw GameError('请选择队员');
        final raw = asIntList(a['team']);
        final t = raw.toSet().toList()..sort();
        if (t.length != raw.length || t.length != teamSize || t.any((s) => s < 0 || s >= players)) {
          throw GameError('需要选择 $teamSize 名不同的队员');
        }
        team = t;
        votes = {};
        phase = 'vote';
        host.log('${name(leader)} 提名：${team.map(name).join('、')}');
        break;
      case 'vote':
        if (type != 'vote') throw GameError('请投票');
        if (votes.containsKey(seat)) throw GameError('你已经投过票');
        votes[seat] = asBool(a['approve']);
        if (votes.length == players) _resolveVote();
        break;
      case 'mission':
        if (type != 'mission') throw GameError('请出任务牌');
        if (!team.contains(seat)) throw GameError('你不在任务队伍中');
        if (cards.containsKey(seat)) throw GameError('你已经出过牌');
        final ok = asBool(a['success']);
        if (!ok && !spy[seat]) throw GameError('抵抗组织成员只能出成功');
        cards[seat] = ok;
        if (cards.length == team.length) _resolveMission();
        break;
      default:
        throw GameError('请稍候');
    }
  }

  void _resolveVote() {
    final yes = votes.values.where((v) => v).length;
    final ok = yes * 2 > players;
    lastVote = {
      'mission': mission,
      'leader': leader,
      'team': team,
      'votes': [for (var s = 0; s < players; s++) votes[s] == true],
      'approved': ok,
    };
    host.log('投票：$yes 赞成 / ${players - yes} 反对，${ok ? '通过' : '否决'}');
    if (ok) {
      rejects = 0;
      cards = {};
      phase = 'mission';
      return;
    }
    rejects++;
    // Bots: approving a rejected team is mildly suspicious only in hindsight; skip.
    if (rejects >= 5) {
      _finish('spy', '连续五次组队被否决');
      return;
    }
    leader = (leader + 1) % players;
    phase = 'propose';
  }

  void _resolveMission() {
    final f = cards.values.where((v) => !v).length;
    final ok = f < failsNeeded(mission);
    results[mission] = ok ? 1 : 0;
    history.add({'mission': mission, 'leader': leader, 'team': team, 'fails': f, 'success': ok});
    host.log('第${mission + 1}次任务${ok ? '成功' : '失败'}（$f 张失败）');
    for (final s in team) {
      suspicion[s] += f > 0 ? f / team.length * 2 : -0.3;
    }
    mission++;
    if (successes >= 3) {
      _finish('res', '三次任务成功');
      return;
    }
    if (fails >= 3) {
      _finish('spy', '三次任务失败');
      return;
    }
    leader = (leader + 1) % players;
    team = [];
    _beginMission();
  }

  static const plotNames = {'overheard': '窃听', 'openup': '坦白', 'confidence': '建立信任'};
  static const plotDesc = {
    'overheard': '队长把此卡交给一名其他玩家，该玩家查看相邻一名玩家的身份',
    'openup': '队长把此卡交给一名其他玩家，该玩家向任意一名玩家公开自己的身份',
    'confidence': '队长必须向一名其他玩家公开自己的身份',
  };

  void _beginMission() {
    phase = 'propose';
    if (!plotOn) return;
    if (plotDeck.isEmpty) {
      plotDeck = shuffled(['overheard', 'openup', 'confidence'], rng);
    }
    plotCard = plotDeck.removeLast();
    plotHolder = -1;
    plotStage = plotCard == 'confidence' ? 'use' : 'give';
    if (plotCard == 'confidence') plotHolder = leader;
    phase = 'plot';
    host.log('队长 ${name(leader)} 抽到计划卡【${plotNames[plotCard]}】');
  }

  List<int> plotTargets(int seat) {
    if (phase != 'plot') return const [];
    if (plotStage == 'give') {
      return seat == leader ? [for (var s = 0; s < players; s++) if (s != leader) s] : const [];
    }
    if (seat != plotHolder) return const [];
    if (plotCard == 'overheard') return {(seat + 1) % players, (seat + players - 1) % players}.toList()..sort();
    return [for (var s = 0; s < players; s++) if (s != seat) s];
  }

  void _plot(int seat, int t) {
    final who = plotStage == 'give' ? leader : plotHolder;
    if (seat != who) throw GameError('现在不是你处理计划卡');
    if (!plotTargets(seat).contains(t)) throw GameError('请选择一名有效的玩家');
    if (plotStage == 'give') {
      plotHolder = t;
      plotStage = 'use';
      host.log('${name(leader)} 把【${plotNames[plotCard]}】交给了 ${name(t)}');
      return;
    }
    if (plotCard == 'overheard') {
      known[seat]['$t'] = spy[t];
      host.log('${name(seat)} 窃听了 ${name(t)} 的身份');
    } else {
      known[t]['$seat'] = spy[seat];
      host.log('${name(seat)} 向 ${name(t)} 公开了自己的身份');
    }
    lastPlot = {'card': plotCard, 'leader': leader, 'holder': seat, 'target': t};
    plotCard = '';
    plotStage = '';
    plotHolder = -1;
    phase = 'propose';
  }

  @override
  Map<String, dynamic> view(int seat) {
    final me = seat >= 0 && seat < players;
    final over = isOver;
    return {
      'phase': phase,
      'leader': leader,
      'mission': mission,
      'sizes': sizes,
      'twoFail': players >= 7,
      'rejects': rejects,
      'team': team,
      'results': results,
      'voted': [for (var s = 0; s < players; s++) votes.containsKey(s)],
      'played': [for (final s in team) cards.containsKey(s)],
      'lastVote': lastVote,
      'history': history,
      'spyCount': resistanceSpyCount[players],
      'mySpy': me ? spy[seat] : null,
      'spies': over || (me && spy[seat]) ? [for (var s = 0; s < players; s++) if (spy[s]) s] : null,
      'myVote': me ? votes[seat] : null,
      'myCard': me ? cards[seat] : null,
      'winner': winner,
      'reason': reason,
      'plotOn': plotOn,
      'plotCard': plotCard,
      'plotStage': plotStage,
      'plotHolder': plotHolder,
      'plotTargets': me ? plotTargets(seat) : const <int>[],
      'lastPlot': lastPlot,
      'known': me ? known[seat] : const <String, bool>{},
    };
  }

  // ------------------------------------------------------------ bot
  // Resistance bots don't know who is a spy; they use only public mission
  // outcomes (suspicion) and their own identity. Spy bots know their mates.

  List<int> _pickTeam(int seat) {
    final isSpy = spy[seat];
    final others = [for (var s = 0; s < players; s++) if (s != seat) s];
    final sc = {
      for (final s in others)
        s: (isSpy ? (spy[s] ? -1.0 : 0.0) : -suspicion[s] + _knownScore(seat, s)) +
            rng.nextDouble() * switch (botLevel) { 0 => 3.0, 2 => 0.3, _ => 0.8 },
    };
    others.sort((a, b) => sc[b]!.compareTo(sc[a]!));
    return ([seat, ...others.take(teamSize - 1)])..sort();
  }

  double _knownScore(int seat, int s) {
    final k = known[seat]['$s'];
    return k == null ? 0 : (k ? -20 : 3);
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final isSpy = spy[seat];
    switch (phase) {
      case 'plot':
        final ts = plotTargets(seat);
        if (ts.isEmpty) return null;
        return {'type': 'plot', 'target': ts[rng.nextInt(ts.length)]};
      case 'propose':
        return {'type': 'propose', 'team': _pickTeam(seat)};
      case 'vote':
        if (votes.containsKey(seat)) return null;
        if (rejects >= 4) return {'type': 'vote', 'approve': !isSpy || team.any((s) => spy[s])};
        if (isSpy) {
          final has = team.any((s) => spy[s]);
          return {'type': 'vote', 'approve': rng.nextDouble() < (has ? 0.85 : 0.3)};
        }
        if (team.any((s) => known[seat]['$s'] == true)) return {'type': 'vote', 'approve': false};
        if (botLevel == 0 && rng.nextInt(3) == 0) return {'type': 'vote', 'approve': rng.nextBool()};
        final susp = team.fold(0.0, (a, s) => a + (s == seat ? 0 : suspicion[s]));
        final approve = leader == seat || (mission == 0 && rejects < 2 ? rng.nextDouble() < 0.7 : susp < 1.2);
        return {'type': 'vote', 'approve': approve};
      case 'mission':
        if (!team.contains(seat) || cards.containsKey(seat)) return null;
        if (!isSpy) return {'type': 'mission', 'success': true};
        final mates = team.where((s) => s != seat && spy[s]).length;
        var p = mission == 0 ? 0.5 : 0.85;
        if (fails == 2 || successes == 2) p = 1;
        if (failsNeeded(mission) == 2) p = mates > 0 ? 1 : 0.2;
        if (mates > 0 && failsNeeded(mission) == 1 && p < 1) p *= 0.6;
        return {'type': 'mission', 'success': rng.nextDouble() >= p};
    }
    return null;
  }
}
