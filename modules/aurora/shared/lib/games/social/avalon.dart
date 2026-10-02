import '../../src/engine.dart';

const avalonRoleNames = {
  'merlin': '梅林',
  'assassin': '刺客',
  'percival': '派西维尔',
  'morgana': '莫甘娜',
  'mordred': '莫德雷德',
  'oberon': '奥伯伦',
  'servant': '忠臣',
  'minion': '爪牙',
};

const _evilRoles = {'assassin', 'morgana', 'mordred', 'oberon', 'minion'};

bool avalonIsEvil(String role) => _evilRoles.contains(role);

/// Quest team sizes by player count.
const avalonQuestSizes = {
  5: [2, 3, 2, 3, 3],
  6: [2, 3, 4, 3, 4],
  7: [2, 3, 3, 4, 4],
  8: [3, 4, 4, 5, 5],
  9: [3, 4, 4, 5, 5],
  10: [3, 4, 4, 5, 5],
};

const avalonEvilCount = {5: 2, 6: 2, 7: 3, 8: 3, 9: 3, 10: 4};

/// Role list (unshuffled) for [n] players with the given optional roles.
List<String> avalonRoles(int n, {bool percival = true, bool mordred = false, bool oberon = false}) {
  final evilN = avalonEvilCount[n]!;
  final goodN = n - evilN;
  final evil = <String>['assassin'];
  if (percival) evil.add('morgana');
  if (mordred && evil.length < evilN) evil.add('mordred');
  if (oberon && evil.length < evilN) evil.add('oberon');
  while (evil.length < evilN) {
    evil.add('minion');
  }
  final good = <String>['merlin'];
  if (percival) good.add('percival');
  while (good.length < goodN) {
    good.add('servant');
  }
  return [...good, ...evil];
}

class Avalon extends GameEngine {
  Avalon(super.setup);

  late List<String> roles;
  String phase = 'propose'; // propose vote voteResult quest questResult assassin over
  int leader = 0;
  int quest = 0;
  int rejects = 0;
  List<int> team = [];
  Map<int, bool> votes = {};
  Map<int, bool> questCards = {};
  final List<Map<String, dynamic>> history = [];
  List<int?> results = List.filled(5, null); // 1 success 0 fail
  String winner = ''; // good / evil
  String reason = '';
  int assassinTarget = -1;
  Map<String, dynamic>? lastVote;
  Map<String, dynamic>? lastQuest;
  // bot memory: suspicion per seat (based on failed quests)
  late List<double> suspicion;

  List<int> get sizes => avalonQuestSizes[players]!;
  int get teamSize => sizes[quest];
  int failsNeeded(int q) => q == 3 && players >= 7 ? 2 : 1;

  @override
  bool get isOver => phase == 'over';

  @override
  int get botDelayMs => 900;

  @override
  List<int>? get placings =>
      isOver ? [for (var s = 0; s < players; s++) (avalonIsEvil(roles[s]) == (winner == 'evil')) ? 1 : 2] : null;

  @override
  void start() {
    roles = shuffled(
        avalonRoles(players,
            percival: setup.opt<bool>('percival', true),
            mordred: setup.opt<bool>('mordred', false),
            oberon: setup.opt<bool>('oberon', false)),
        rng);
    suspicion = List.filled(players, 0);
    leader = rng.nextInt(players);
    host.log('阿瓦隆开始！${players}人局，邪恶方 ${avalonEvilCount[players]} 人。${name(leader)} 担任首任队长');
  }

  int get successes => results.where((r) => r == 1).length;
  int get fails => results.where((r) => r == 0).length;

  @override
  List<int> get waitingFor {
    switch (phase) {
      case 'propose':
        return [leader];
      case 'vote':
        return [for (var s = 0; s < players; s++) if (!votes.containsKey(s)) s];
      case 'quest':
        return [for (final s in team) if (!questCards.containsKey(s)) s];
      case 'assassin':
        return [roles.indexOf('assassin')];
      default:
        return const [];
    }
  }

  void _finish(String w, String why) {
    winner = w;
    reason = why;
    phase = 'over';
    host.log('${w == 'good' ? '正义方' : '邪恶方'}获胜：$why');
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    if (isOver) throw GameError('对局已结束');
    final type = asStr(a['type']);
    switch (phase) {
      case 'propose':
        if (seat != leader) throw GameError('只有队长可以组队');
        if (type != 'propose') throw GameError('请选择队员');
        final t = asIntList(a['team']).toSet().toList()..sort();
        if (t.length != teamSize || t.any((s) => s < 0 || s >= players)) {
          throw GameError('需要选择 $teamSize 名队员');
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
      case 'quest':
        if (type != 'quest') throw GameError('请出任务牌');
        if (!team.contains(seat)) throw GameError('你不在任务队伍中');
        if (questCards.containsKey(seat)) throw GameError('你已经出过牌');
        final success = asBool(a['success']);
        if (!success && !avalonIsEvil(roles[seat])) throw GameError('正义方只能出成功');
        questCards[seat] = success;
        if (questCards.length == team.length) _resolveQuest();
        break;
      case 'assassin':
        if (seat != roles.indexOf('assassin')) throw GameError('只有刺客可以刺杀');
        if (type != 'assassinate') throw GameError('请选择刺杀目标');
        final t = asInt(a['target']);
        // Only reject targets the assassin already knows are evil (itself, visible
        // mates). Rejecting any evil seat would be an oracle revealing e.g. Oberon.
        if (t < 0 || t >= players || t == seat || knowledge(seat)['$t'] == '同伴') {
          throw GameError('请选择一名正义方玩家');
        }
        assassinTarget = t;
        host.log('刺客刺杀了 ${name(t)}');
        if (roles[t] == 'merlin') {
          _finish('evil', '刺客成功刺杀梅林');
        } else {
          _finish('good', '三次任务成功，刺客未能找到梅林');
        }
        break;
      default:
        throw GameError('请稍候');
    }
  }

  void _resolveVote() {
    final yes = votes.values.where((v) => v).length;
    final ok = yes * 2 > players;
    lastVote = {
      'leader': leader,
      'team': team,
      'votes': [for (var s = 0; s < players; s++) votes[s] == true],
      'approved': ok,
    };
    host.log('投票结果：$yes 赞成 / ${players - yes} 反对，${ok ? '通过' : '否决'}');
    if (ok) {
      rejects = 0;
      questCards = {};
      phase = 'quest';
    } else {
      rejects++;
      if (rejects >= 5) {
        _finish('evil', '连续五次组队被否决');
        return;
      }
      leader = (leader + 1) % players;
      phase = 'propose';
    }
  }

  void _resolveQuest() {
    final f = questCards.values.where((v) => !v).length;
    final ok = f < failsNeeded(quest);
    results[quest] = ok ? 1 : 0;
    lastQuest = {'quest': quest, 'team': team, 'fails': f, 'success': ok};
    history.add({'quest': quest, 'leader': leader, 'team': team, 'fails': f, 'success': ok});
    host.log('第${quest + 1}次任务${ok ? '成功' : '失败'}（${f}张失败）');
    if (!ok) {
      for (final s in team) {
        suspicion[s] += f / team.length * 2;
      }
    } else {
      for (final s in team) {
        suspicion[s] -= 0.3;
      }
    }
    quest++;
    if (successes >= 3) {
      phase = 'assassin';
      host.log('正义方完成三次任务！刺客请找出梅林');
      return;
    }
    if (fails >= 3) {
      _finish('evil', '三次任务失败');
      return;
    }
    leader = (leader + 1) % players;
    phase = 'propose';
  }

  /// What [seat] knows at night. Map seat(str) -> label.
  Map<String, String> knowledge(int seat) {
    final r = roles[seat];
    final out = <String, String>{};
    if (r == 'merlin') {
      for (var s = 0; s < players; s++) {
        if (avalonIsEvil(roles[s]) && roles[s] != 'mordred') out['$s'] = '邪恶';
      }
    } else if (r == 'percival') {
      for (var s = 0; s < players; s++) {
        if (roles[s] == 'merlin' || roles[s] == 'morgana') out['$s'] = '梅林?';
      }
    } else if (avalonIsEvil(r) && r != 'oberon') {
      for (var s = 0; s < players; s++) {
        if (s != seat && avalonIsEvil(roles[s]) && roles[s] != 'oberon') out['$s'] = '同伴';
      }
    }
    return out;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final over = isOver;
    final me = seat >= 0 && seat < players;
    return {
      'phase': phase,
      'leader': leader,
      'quest': quest,
      'sizes': sizes,
      'twoFail': players >= 7,
      'rejects': rejects,
      'team': team,
      'results': results,
      'voted': [for (var s = 0; s < players; s++) votes.containsKey(s)],
      'played': [for (final s in team) questCards.containsKey(s)],
      'lastVote': lastVote,
      'lastQuest': lastQuest,
      'history': history,
      'winner': winner,
      'reason': reason,
      'assassinTarget': assassinTarget,
      'evilCount': avalonEvilCount[players],
      'roleList': [for (final r in avalonRoles(players,
          percival: setup.opt<bool>('percival', true),
          mordred: setup.opt<bool>('mordred', false),
          oberon: setup.opt<bool>('oberon', false))) r],
      'myRole': me ? roles[seat] : null,
      'known': me ? knowledge(seat) : const <String, String>{},
      'myVote': me && votes.containsKey(seat) ? votes[seat] : null,
      'myCard': me && questCards.containsKey(seat) ? questCards[seat] : null,
      'assassin': phase == 'assassin' || over ? roles.indexOf('assassin') : -1,
      'roles': over ? roles : null,
    };
  }

  // ---------------------------------------------------------------- bot
  List<int> _pickTeam(int seat) {
    final evil = avalonIsEvil(roles[seat]);
    final known = knowledge(seat);
    final others = [for (var s = 0; s < players; s++) if (s != seat) s];
    double score(int s) {
      var sc = -suspicion[s] + rng.nextDouble() * 0.8;
      if (!evil && known['$s'] == '邪恶') sc -= 10;
      if (evil && known['$s'] == '同伴') sc += 0.5;
      return sc;
    }

    final scores = {for (final s in others) s: score(s)};
    others.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final t = [seat];
    if (evil) {
      // include self + good-looking players
      final goods = others.where((s) => known['$s'] != '同伴').toList();
      final pool = [...goods, ...others.where((s) => !goods.contains(s))];
      for (final s in pool) {
        if (t.length >= teamSize) break;
        t.add(s);
      }
    } else {
      for (final s in others) {
        if (t.length >= teamSize) break;
        t.add(s);
      }
    }
    return t..sort();
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    final role = roles[seat];
    final evil = avalonIsEvil(role);
    final known = knowledge(seat);
    switch (phase) {
      case 'propose':
        return {'type': 'propose', 'team': _pickTeam(seat)};
      case 'vote':
        if (votes.containsKey(seat)) return null;
        // 简单: often votes on a whim
        if (botLevel == 0 && rejects < 4 && rng.nextInt(3) == 0) return {'type': 'vote', 'approve': rng.nextBool()};
        if (rejects >= 4) {
          // the 5th proposal: good always approves, evil approves only if an evil player is on the team
          return {'type': 'vote', 'approve': !evil || team.any((s) => s == seat || known['$s'] == '同伴')};
        }
        bool approve;
        if (evil) {
          final hasEvil = team.contains(seat) || team.any((s) => known['$s'] == '同伴');
          approve = hasEvil ? rng.nextDouble() < 0.85 : rng.nextDouble() < 0.25;
        } else {
          final bad = team.any((s) => known['$s'] == '邪恶');
          if (bad) {
            approve = false;
          } else {
            final susp = team.fold(0.0, (a, s) => a + suspicion[s]);
            approve = team.contains(seat) || leader == seat ? susp < 2.5 : susp < 1.0 && rng.nextDouble() < 0.75;
            if (quest == 0 && rejects < 2) approve = rng.nextDouble() < 0.65 || team.contains(seat);
          }
        }
        return {'type': 'vote', 'approve': approve};
      case 'quest':
        if (!team.contains(seat) || questCards.containsKey(seat)) return null;
        if (!evil) return {'type': 'quest', 'success': true};
        // evil: fail if it matters, sometimes hold back early
        final mates = team.where((s) => s != seat && avalonIsEvil(roles[s]) && known.containsKey('$s')).length;
        var failP = quest == 0 ? 0.5 : 0.8;
        if (fails == 2) failP = 1.0;
        if (successes == 2) failP = 1.0;
        if (mates > 0 && failsNeeded(quest) == 1) failP *= 0.6;
        return {'type': 'quest', 'success': rng.nextDouble() >= failP};
      case 'assassin':
        // Only use what the assassin knows: itself and its known mates are evil.
        bool knownEvil(int s) => s == seat || known['$s'] == '同伴';
        final goods = [for (var s = 0; s < players; s++) if (!knownEvil(s)) s];
        // heuristic: players who were never on a failed quest and often rejected evil teams
        double sc(int s) {
          var v = -suspicion[s] + rng.nextDouble() * (botLevel == 2 ? 0.6 : 1.5);
          // 困难: whoever consistently rejected teams that later failed looks like Merlin
          if (botLevel == 2) {
            for (final h in history) {
              if (h['success'] == false && !(h['team'] as List).contains(s)) v += 0.4;
            }
          }
          if (lastVote != null) {
            final vs = (lastVote!['votes'] as List);
            final tm = (lastVote!['team'] as List).cast<int>();
            final evilOnTeam = tm.any(knownEvil);
            if (evilOnTeam && vs[s] == false) v += 1;
          }
          return v;
        }

        if (botLevel == 0) return {'type': 'assassinate', 'target': goods[rng.nextInt(goods.length)]};
        final sc2 = {for (final s in goods) s: sc(s)};
        goods.sort((a, b) => sc2[b]!.compareTo(sc2[a]!));
        return {'type': 'assassinate', 'target': goods.first};
    }
    return null;
  }
}
