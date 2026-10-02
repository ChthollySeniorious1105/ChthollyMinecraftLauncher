import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/werewolf/defs.dart';
import 'package:aurora_shared/games/werewolf/roles.dart';
import 'package:aurora_shared/games/werewolf/werewolf.dart';
import 'package:aurora_shared/src/ai.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

class _Ai extends FakeAi {
  String? Function(AiRequest) reply;
  _Ai(this.reply);
  @override
  String? completeNow(AiRequest req) {
    requests.add(req);
    return reply(req);
  }
}

Werewolf make(int n, Map<String, dynamic> opts, {List<String>? roles, int seed = 5, AiService? ai}) {
  final def = werewolfGames.first;
  final e = def.create(GameSetup(
    ai: ai,
    players: n,
    options: def.normalizeOptions(opts),
    names: [for (var i = 0; i < n; i++) 'P$i'],
    bots: List.filled(n, false),
    rng: Random(seed),
  )) as Werewolf;
  e.host = SimHost();
  e.start();
  if (roles != null) {
    e.roles = roles;
    e.rebuildNight();
  }
  return e;
}

int seatOf(Werewolf e, String r) => e.roles.indexOf(r);

/// Everyone who still has a night action and isn't a special role sleeps.
void sleepOthers(Werewolf e) {
  for (final s in List.of(e.waitingFor)) {
    if (e.phase != 'night') return;
    if (e.nightDuty(s) == 'sleep') e.handle(s, {'type': 'sleep'});
  }
}

void wolvesKill(Werewolf e, int t) {
  for (final s in List.of(e.killers)) {
    e.handle(s, {'type': 'kill', 'target': t});
  }
}

/// Pass all task prompts (skills: none, badge: tear, last words: end).
void passTasks(Werewolf e) {
  while (const {'lastwords', 'badge', 'shoot'}.contains(e.phase)) {
    final s = e.waitingFor.first;
    switch (e.phase) {
      case 'lastwords':
        e.handle(s, {'type': 'end'});
      case 'badge':
        e.handle(s, {'type': 'badge', 'target': -1});
      default:
        e.handle(s, {'type': 'shoot', 'target': -1});
    }
  }
}

void finishSpeeches(Werewolf e) {
  while (e.phase == 'speech') {
    e.handle(e.speaker, {'type': 'end', 'text': ''});
  }
}

// 9 players: wolves 0,1,2 seer 3 witch 4 hunter 5 villagers 6,7,8
const nine = ['wolf', 'wolf', 'wolf', 'seer', 'witch', 'hunter', 'villager', 'villager', 'villager'];
// 12 with guard + wolfking: 0 king, 1-3 wolves, 4 seer 5 witch 6 hunter 7 guard 8-11 villagers
const twelve = [
  'wolfking', 'wolf', 'wolf', 'wolf', 'seer', 'witch', 'hunter', 'guard', 'villager', 'villager', 'villager', 'villager'
];
const twelveIdiot = [
  'wolf', 'wolf', 'wolf', 'wolf', 'seer', 'witch', 'hunter', 'idiot', 'villager', 'villager', 'villager', 'villager'
];
// 12: 0 白狼王, 1-3 wolves, 4 seer 5 witch 6 hunter 7 knight 8-11 villagers
const wwk = [
  'whiteWolfKing', 'wolf', 'wolf', 'wolf', 'seer', 'witch', 'hunter', 'knight', 'villager', 'villager', 'villager', 'villager'
];
// 12: 0 狼美人, 1-3 wolves, 4 seer 5 witch 6 guard 7 knight 8 hunter 9-11 villagers
const beauty = [
  'wolfBeauty', 'wolf', 'wolf', 'wolf', 'seer', 'witch', 'guard', 'knight', 'hunter', 'villager', 'villager', 'villager'
];
// 12: 0-3 wolves, 4 magician 5 seer 6 witch 7 crow 8-11 villagers
const magic = [
  'wolf', 'wolf', 'wolf', 'wolf', 'magician', 'seer', 'witch', 'crow', 'villager', 'villager', 'villager', 'villager'
];
// 10: 0-2 wolves, 3 cupid 4 seer 5 witch 6 hunter 7-9 villagers
const cupid = ['wolf', 'wolf', 'wolf', 'cupid', 'seer', 'witch', 'hunter', 'villager', 'villager', 'villager'];
// 10: 0 隐狼, 1-2 wolves, 3 seer 4 witch 5 hunter 6-8 villagers 9 野孩子
const hidden = ['hiddenWolf', 'wolf', 'wolf', 'seer', 'witch', 'hunter', 'villager', 'villager', 'villager', 'wildChild'];

/// Everyone votes for [t] (who votes for [alt]).
void voteOut(Werewolf e, int t, {int alt = -1}) {
  for (final s in List.of(e.waitingFor)) {
    e.handle(s, {'type': 'vote', 'target': s == t ? alt : t});
  }
}

void main() {
  test('role distributions', () {
    String sum(int n) => werewolfBoardSummary(werewolfRoles('auto', n));
    expect(sum(6), '2狼 预女 2民');
    expect(sum(7), '2狼 预女猎 2民');
    expect(sum(8), '3狼 预女猎 2民');
    expect(sum(9), '3狼 预女猎 3民');
    expect(sum(10), '3狼 预女猎白 3民');
    expect(sum(11), '4狼 预女猎白 3民');
    expect(sum(12), '4狼 预女猎白 4民');
    for (var n = 6; n <= 12; n++) {
      expect(werewolfRoles('auto', n).length, n);
    }
    expect(werewolfRoles('ylshou12', 12).contains('guard'), isTrue);
    expect(werewolfRoles('wkguard12', 12).contains('wolfking'), isTrue);
    expect(werewolfRoles('nine', 9).length, 9);
    expect(werewolfRoles('six', 6).length, 6);
    final def = werewolfGames.first;
    expect(def.playerRange({'board': 'ylbai12'}), (12, 12));
    expect(def.playerRange({'board': 'auto'}), (6, 12));
  });

  test('同守同救 kills the target; guard alone saves', () {
    final e = make(12, {'board': 'wkguard12', 'sheriff': false}, roles: List.of(twelve));
    wolvesKill(e, 8);
    e.handle(7, {'type': 'guard', 'target': 8});
    e.handle(4, {'type': 'check', 'target': 0});
    e.handle(5, {'type': 'witch', 'save': true, 'poison': -1});
    sleepOthers(e);
    expect(e.alive[8], isFalse);

    final e2 = make(12, {'board': 'wkguard12', 'sheriff': false}, roles: List.of(twelve));
    wolvesKill(e2, 8);
    e2.handle(7, {'type': 'guard', 'target': 8});
    e2.handle(4, {'type': 'check', 'target': 0});
    e2.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e2);
    expect(e2.alive[8], isTrue);
    expect(e2.dawn!['deaths'], isEmpty);
  });

  test('guard cannot protect same seat twice in a row', () {
    final e = make(12, {'board': 'wkguard12', 'sheriff': false}, roles: List.of(twelve));
    e.lastGuard = 9;
    expect(() => e.handle(7, {'type': 'guard', 'target': 9}), throwsA(isA<GameError>()));
  });

  test('witch cannot save and poison the same night', () {
    final e = make(9, {'board': 'nine', 'sheriff': false}, roles: List.of(nine));
    wolvesKill(e, 6);
    expect(() => e.handle(4, {'type': 'witch', 'save': true, 'poison': 0}), throwsA(isA<GameError>()));
  });

  test('poisoned hunter cannot shoot; knifed hunter can', () {
    final e = make(9, {'board': 'nine', 'sheriff': false}, roles: List.of(nine));
    wolvesKill(e, 6);
    e.handle(3, {'type': 'check', 'target': 0});
    e.handle(4, {'type': 'witch', 'save': false, 'poison': 5});
    sleepOthers(e);
    expect(e.alive[5], isFalse);
    // every dead player gets the same prompt, but the hunter cannot fire
    while (e.phase != 'shoot' || e.task!['s'] != 5) {
      passTasks(e);
    }
    expect(e.task!['can'], isFalse);
    expect(() => e.handle(5, {'type': 'shoot', 'target': 0}), throwsA(isA<GameError>()));

    final e2 = make(9, {'board': 'nine', 'sheriff': false}, roles: List.of(nine));
    wolvesKill(e2, 5);
    e2.handle(3, {'type': 'check', 'target': 0});
    e2.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e2);
    expect(e2.phase, 'shoot');
    expect(e2.task!['can'], isTrue);
    e2.handle(5, {'type': 'shoot', 'target': 0});
    expect(e2.alive[0], isFalse);
  });

  test('idiot survives exile and loses vote', () {
    final e = make(12, {'board': 'ylbai12', 'sheriff': false}, roles: List.of(twelveIdiot));
    wolvesKill(e, -1);
    e.handle(4, {'type': 'check', 'target': 0});
    e.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    finishSpeeches(e);
    expect(e.phase, 'vote');
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': s == 7 ? 8 : 7});
    }
    expect(e.alive[7], isTrue);
    expect(e.idiotFlipped, contains(7));
    expect(e.phase, 'night');
    expect(e.exileVoters.contains(7), isFalse);
  });

  test('sheriff vote counts 1.5', () {
    final e = make(9, {'board': 'nine', 'sheriff': false}, roles: List.of(nine));
    wolvesKill(e, -1);
    e.handle(3, {'type': 'check', 'target': 0});
    e.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    e.sheriff = 3;
    sleepOthers(e);
    expect(e.phase, 'direction');
    e.handle(3, {'type': 'direction', 'dir': 1});
    finishSpeeches(e);
    // 4 votes on 0 (sheriff among them: 3.5)… vs 4 votes on 6 → 0 has 4.5
    final plan = {3: 0, 4: 0, 5: 0, 6: 0, 0: 6, 1: 6, 2: 6, 7: 6, 8: 1};
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': plan[s]});
    }
    expect(e.lastVote!['out'], 0);
  });

  test('sheriff election & PK then no exile on repeat tie', () {
    final e = make(9, {'board': 'nine', 'sheriff': true}, roles: List.of(nine));
    wolvesKill(e, -1);
    e.handle(3, {'type': 'check', 'target': 0});
    e.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.phase, 'sheriff_signup');
    for (var s = 0; s < 9; s++) {
      e.handle(s, {'type': 'run', 'run': s == 3 || s == 0});
    }
    finishSpeeches(e);
    expect(e.phase, 'sheriff_vote');
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': s < 5 ? 0 : 3});
    }
    // voters 1,2,4 → 0 ; 5,6,7,8 → 3
    expect(e.sheriff, 3);
    e.handle(3, {'type': 'direction', 'dir': -1});
    finishSpeeches(e);
    // tie 0 vs 6 with even counts (sheriff abstains)
    final plan = {3: -1, 1: 0, 2: 0, 4: 0, 0: 6, 5: 6, 7: 6, 8: -1, 6: -1};
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': plan[s]});
    }
    expect(e.pkList, [0, 6]);
    expect(e.phase, 'speech');
    finishSpeeches(e);
    expect(e.phase, 'vote');
    expect(e.waitingFor.contains(0), isFalse);
    expect(e.waitingFor.contains(6), isFalse);
    final pk = {1: 0, 2: 0, 3: -1, 4: 6, 5: 6, 7: -1, 8: -1};
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': pk[s]});
    }
    expect(e.phase, 'night');
    expect(e.alive.every((a) => a), isTrue);
  });

  test('屠边 vs 屠城', () {
    final e = make(6, {'board': 'six', 'win': 'edge', 'sheriff': false},
        roles: ['wolf', 'wolf', 'seer', 'witch', 'villager', 'villager']);
    e.alive[4] = false;
    wolvesKill(e, 5);
    e.handle(2, {'type': 'check', 'target': 0});
    e.handle(3, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.isOver, isTrue);
    expect(e.winner, 'wolf');

    final c = make(6, {'board': 'six', 'win': 'city', 'sheriff': false},
        roles: ['wolf', 'wolf', 'seer', 'witch', 'villager', 'villager']);
    c.alive[4] = false;
    wolvesKill(c, 5);
    c.handle(2, {'type': 'check', 'target': 0});
    c.handle(3, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(c);
    expect(c.isOver, isFalse);
  });

  test('wolf explode ends day', () {
    final e = make(9, {'board': 'nine', 'sheriff': false}, roles: List.of(nine));
    wolvesKill(e, -1);
    e.handle(3, {'type': 'check', 'target': 0});
    e.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.phase, 'speech');
    e.handle(1, {'type': 'explode'});
    expect(e.alive[1], isFalse);
    expect(e.phase, 'night');
    expect(e.round, 2);
  });

  test('villager view hides roles & night info', () {
    final e = make(9, {'board': 'nine'}, roles: List.of(nine));
    wolvesKill(e, 6);
    final v = e.view(7);
    final roles = v['roles'] as List;
    for (var s = 0; s < 9; s++) {
      expect(roles[s], s == 7 ? 'villager' : isNull);
    }
    expect(v['mates'], isEmpty);
    expect(v['checks'], isEmpty);
    expect(v['night'], isNot(contains('wolfVotes')));
    expect(v['night'], isNot(contains('kill')));
    final txt = jsonEncode(v);
    expect(txt.contains('wolfVotes'), isFalse);
    expect(v['nights'], isNull);
    // spectators see no roles either
    expect((e.view(-1)['roles'] as List).every((r) => r == null), isTrue);
    // wolves see teammates
    expect((e.view(0)['roles'] as List).sublist(0, 3), ['wolf', 'wolf', 'wolf']);
  });

  test('new boards', () {
    String sum(String b, int n) => werewolfBoardSummary(werewolfRoles(b, n));
    for (final b in ['wwkKnight12', 'beautyKnight12', 'magicCrow12']) {
      expect(werewolfRoles(b, 12).length, 12);
      expect(werewolfRoles(b, 12).where(werewolfIsWolf).length, 4);
    }
    for (final b in ['cupid10', 'hiddenWild10']) {
      expect(werewolfRoles(b, 10).length, 10);
      expect(werewolfRoles(b, 10).where(werewolfIsWolf).length, 3);
    }
    expect(sum('wwkKnight12', 12), '4狼(含白狼王) 预女猎骑 4民');
    expect(werewolfGames.first.playerRange({'board': 'cupid10'}), (10, 10));
  });

  test('白狼王 explodes and takes a player', () {
    final e = make(12, {'board': 'wwkKnight12', 'sheriff': false}, roles: List.of(wwk));
    wolvesKill(e, -1);
    e.handle(4, {'type': 'check', 'target': 1});
    e.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.phase, 'speech');
    expect(e.view(0)['explodeTake'], isTrue);
    expect(() => e.handle(0, {'type': 'explode', 'target': 0}), throwsA(isA<GameError>()));
    e.handle(0, {'type': 'explode', 'target': 4});
    expect(e.alive[0], isFalse);
    expect(e.alive[4], isFalse);
    expect(e.deathCause[4], 'shot');
    passTasks(e);
    expect(e.phase, 'night');
    expect(e.round, 2);
  });

  test('骑士 duel: wolf dies & night falls; good target kills the knight', () {
    Werewolf day() {
      final e = make(12, {'board': 'wwkKnight12', 'sheriff': false}, roles: List.of(wwk));
      wolvesKill(e, -1);
      e.handle(4, {'type': 'check', 'target': 1});
      e.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
      sleepOthers(e);
      return e;
    }

    final e = day();
    expect(e.view(7)['canDuel'], isTrue);
    expect(e.view(8)['canDuel'], isFalse);
    expect(() => e.handle(8, {'type': 'duel', 'target': 1}), throwsA(isA<GameError>()));
    e.handle(7, {'type': 'duel', 'target': 1});
    expect(e.alive[1], isFalse);
    expect(e.alive[7], isTrue);
    passTasks(e);
    expect(e.phase, 'night');
    expect(e.round, 2);
    expect(e.view(7)['canDuel'], isFalse);

    final e2 = day();
    e2.handle(7, {'type': 'duel', 'target': 9});
    expect(e2.alive[7], isFalse);
    expect(e2.alive[9], isTrue);
    passTasks(e2);
    expect(e2.phase, 'speech'); // the day continues
    expect(() => e2.handle(7, {'type': 'duel', 'target': 1}), throwsA(isA<GameError>()));
  });

  test('狼美人 charm: charmed hunter dies with her and cannot shoot', () {
    final e = make(12, {'board': 'beautyKnight12', 'sheriff': false}, roles: List.of(beauty));
    expect(e.waitingFor, contains(0));
    e.handle(0, {'type': 'charm', 'target': 8});
    wolvesKill(e, -1);
    e.handle(4, {'type': 'check', 'target': 1});
    e.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
    e.handle(6, {'type': 'guard', 'target': -1});
    sleepOthers(e);
    expect(e.charmed, 8);
    expect(e.canExplode(0), isFalse); // the wolf beauty cannot self-explode
    finishSpeeches(e);
    voteOut(e, 0, alt: 1);
    expect(e.alive[0], isFalse);
    expect(e.alive[8], isFalse);
    expect(e.deathCause[8], 'charm');
    while (e.phase != 'shoot' || e.task!['s'] != 8) {
      if (e.phase == 'night') fail('no prompt for the charmed hunter');
      final s = e.waitingFor.first;
      switch (e.phase) {
        case 'lastwords':
          e.handle(s, {'type': 'end'});
        case 'shoot':
          e.handle(s, {'type': 'shoot', 'target': -1});
        default:
          e.handle(s, {'type': 'badge', 'target': -1});
      }
    }
    expect(e.task!['can'], isFalse);
  });

  test('隐狼: seen as good, not in the pack, becomes a killer when the others are dead', () {
    final e = make(10, {'board': 'hiddenWild10', 'sheriff': false}, roles: List.of(hidden));
    expect(e.killers, [1, 2]);
    expect(e.nightDuty(0), 'sleep');
    expect(() => e.handle(0, {'type': 'kill', 'target': 5}), throwsA(isA<GameError>()));
    // the hidden wolf knows the wolves, they don't know it
    expect(e.view(0)['mates'], [1, 2]);
    expect(e.view(1)['mates'], [2]);
    expect((e.view(1)['roles'] as List)[0], isNull);
    wolvesKill(e, -1);
    e.handle(3, {'type': 'check', 'target': 0});
    expect(e.seerChecks[3], [0, 0]);
    e.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    e.handle(9, {'type': 'model', 'target': 6});
    sleepOthers(e);
    expect(e.canExplode(0), isFalse);
    finishSpeeches(e);
    e.alive[2] = false;
    voteOut(e, 1, alt: 7);
    passTasks(e);
    expect(e.isOver, isFalse);
    expect(e.phase, 'night');
    expect(e.hiddenActive, isTrue);
    expect(e.killers, [0]);
  });

  test('野孩子 turns wolf when the model dies', () {
    final e = make(10, {'board': 'hiddenWild10', 'sheriff': false}, roles: List.of(hidden));
    e.handle(9, {'type': 'model', 'target': 5});
    wolvesKill(e, 5);
    e.handle(3, {'type': 'check', 'target': 9});
    expect(e.seerChecks[3], [9, 0]);
    e.handle(4, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.alive[5], isFalse);
    expect(e.wildTurned, contains(9));
    expect(e.isWolfSeat(9), isTrue);
    passTasks(e);
    finishSpeeches(e);
    voteOut(e, 6, alt: 7);
    passTasks(e);
    expect(e.phase, 'night');
    expect(e.killers, containsAll([1, 2, 9]));
    expect(e.view(9)['turned'], isTrue);
  });

  test('魔术师 acts first; swaps redirect night actions; each seat once', () {
    final e = make(12, {'board': 'magicCrow12', 'sheriff': false}, roles: List.of(magic));
    expect(() => e.handle(5, {'type': 'check', 'target': 0}), throwsA(isA<GameError>()));
    wolvesKill(e, 8); // wolves may act before the magician; resolved at dawn → hits wolf 0
    e.handle(4, {'type': 'magic', 'a': 0, 'b': 8});
    e.handle(5, {'type': 'check', 'target': 0}); // sees villager 8
    expect(e.seerChecks[5], [0, 0]);
    e.handle(6, {'type': 'witch', 'save': false, 'poison': -1});
    e.handle(7, {'type': 'curse', 'target': -1});
    sleepOthers(e);
    expect(e.alive[0], isFalse);
    expect(e.alive[8], isTrue);
    passTasks(e);
    finishSpeeches(e);
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': -1});
    }
    passTasks(e);
    expect(e.phase, 'night');
    expect(() => e.handle(4, {'type': 'magic', 'a': 8, 'b': 9}), throwsA(isA<GameError>()));
    e.handle(4, {'type': 'magic', 'a': 9, 'b': 10});
  });

  test('乌鸦 curse adds one exile vote', () {
    final e = make(12, {'board': 'magicCrow12', 'sheriff': false}, roles: List.of(magic));
    e.handle(4, {'type': 'magic', 'a': -1, 'b': -1});
    wolvesKill(e, -1);
    e.handle(5, {'type': 'check', 'target': 0});
    e.handle(6, {'type': 'witch', 'save': false, 'poison': -1});
    e.handle(7, {'type': 'curse', 'target': 8});
    sleepOthers(e);
    finishSpeeches(e);
    expect(e.view(3)['crow'], 8);
    final plan = {0: 9, 1: 9, 2: 9, 3: 9, 4: 8, 5: 8, 6: 8};
    for (final s in List.of(e.waitingFor)) {
      e.handle(s, {'type': 'vote', 'target': plan[s] ?? -1});
    }
    expect(e.lastVote!['crow'], 8);
    expect(e.pkList, [8, 9]);
  });

  test('丘比特: lovers die together; heartbroken hunter cannot shoot', () {
    final e = make(10, {'board': 'cupid10', 'sheriff': false}, roles: List.of(cupid));
    e.handle(3, {'type': 'link', 'a': 6, 'b': 8});
    expect(e.loversThird, isFalse);
    expect((e.view(6)['roles'] as List)[8], 'villager');
    expect(e.view(6)['lovers'], [6, 8]);
    expect(e.view(7)['lovers'], isEmpty);
    wolvesKill(e, 8);
    e.handle(4, {'type': 'check', 'target': 0});
    e.handle(5, {'type': 'witch', 'save': false, 'poison': -1});
    sleepOthers(e);
    expect(e.alive[6], isFalse);
    expect(e.deathCause[6], 'love');
    while (e.phase != 'shoot' || e.task!['s'] != 6) {
      final s = e.waitingFor.first;
      e.handle(s, e.phase == 'lastwords' ? {'type': 'end'} : {'type': 'shoot', 'target': -1});
    }
    expect(e.task!['can'], isFalse);
  });

  test('人狼恋 third camp wins when everyone else is dead', () {
    final e = make(10, {'board': 'cupid10', 'sheriff': false}, roles: List.of(cupid));
    for (final s in [1, 2, 4, 5, 6, 8]) {
      e.alive[s] = false;
    }
    e.rebuildNight();
    e.handle(3, {'type': 'link', 'a': 0, 'b': 7});
    expect(e.loversThird, isTrue);
    expect(e.team3, {0, 3, 7});
    wolvesKill(e, 9);
    sleepOthers(e);
    expect(e.isOver, isTrue);
    expect(e.winner, 'lovers');
  });

  test('人狼恋 blocks the wolves from winning while the lovers live', () {
    final e = make(10, {'board': 'cupid10', 'sheriff': false}, roles: List.of(cupid));
    for (final s in [2, 4, 5, 6, 8]) {
      e.alive[s] = false;
    }
    e.rebuildNight();
    e.handle(3, {'type': 'link', 'a': 0, 'b': 7});
    wolvesKill(e, 9);
    sleepOthers(e);
    expect(e.isOver, isFalse);
    expect(e.aliveSeats, [0, 1, 3, 7]);
  });

  test('new role skills are used by bots', () {
    final def = werewolfGames.first;
    final seen = <String, int>{};
    void count(String k, bool b) => seen[k] = (seen[k] ?? 0) + (b ? 1 : 0);
    for (final (board, n) in [
      ('wwkKnight12', 12),
      ('beautyKnight12', 12),
      ('magicCrow12', 12),
      ('cupid10', 10),
      ('hiddenWild10', 10)
    ]) {
      final wins = <String, int>{};
      for (var seed = 1; seed <= 40; seed++) {
        final r = simulate(def, n, options: {'board': board}, seed: seed);
        expect(r.finished, isTrue, reason: '$board seed $seed: ${r.error}');
        final log = r.logs.join('\n');
        count('决斗', log.contains('决斗'));
        count('白狼王带人', log.contains('，带走了'));
        count('殉情', log.contains('殉情'));
        count('乌鸦', log.contains('乌鸦诅咒'));
        final w = r.logs.last.split('获胜').first;
        wins[w] = (wins[w] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('$board: $wins');
    }
    // ignore: avoid_print
    print(seen);
    for (final k in ['决斗', '白狼王带人', '殉情', '乌鸦']) {
      expect(seen[k], greaterThan(0), reason: k);
    }
  });

  test('voiceListeners', () {
    final e = make(9, {'board': 'nine', 'sheriff': false}, roles: nine);
    expect(e.phase, 'night');
    expect(e.voiceListeners(0), {1, 2});
    expect(e.voiceListeners(3), isEmpty);
    expect(e.voiceListeners(-1), isNull);
    sleepOthers(e);
    wolvesKill(e, 6);
    while (e.phase == 'night') {
      final s = e.waitingFor.first;
      e.handle(s, e.runBot(s)!);
    }
    passTasks(e);
    expect(e.phase, 'speech');
    expect(e.voiceListeners(0), isNull);
    expect(e.voiceListeners(3), isNull);
    if (!e.alive[6]) expect(e.voiceListeners(6), isEmpty); // only other dead players
  });

  group('AI speeches', () {
    Werewolf toSpeech(String? reply) {
      final e = make(9, {'board': 'nine', 'sheriff': false, 'ai': true}, roles: nine, ai: _Ai((_) => reply));
      while (e.phase != 'speech') {
        final s = e.waitingFor.first;
        e.handle(s, e.runBot(s)!);
      }
      return e;
    }

    test('valid reply is used and the prompt has only own private info', () {
      final e = toSpeech('我觉得 8号 昨天发言很奇怪，今天先听听他怎么说。');
      final s = e.speaker;
      final a = e.runBot(s)!;
      expect(a['type'], 'end');
      expect(a['text'], '我觉得 8号 昨天发言很奇怪，今天先听听他怎么说');
      final ai = e.setup.ai as _Ai;
      final prompt = ai.requests.last.prompt;
      if (!werewolfIsWolf(e.roles[s])) expect(prompt, isNot(contains('狼队友')));
      e.handle(s, a);
    });

    test('over-long / empty replies fall back', () {
      for (final r in ['', null, '很长' * 80, '{"text":"x"}']) {
        final e = toSpeech(r);
        final a = e.runBot(e.speaker)!;
        expect(a['type'], 'end');
        expect((a['text'] as String).isNotEmpty, isTrue);
        expect((a['text'] as String).length, lessThanOrEqualTo(Werewolf.maxText));
      }
    });
  });

  test('placings', () {
    final e = make(9, {'board': 'nine'}, roles: nine);
    expect(e.placings, isNull);
    e.winner = 'wolf';
    e.phase = 'over';
    expect(e.placings, [1, 1, 1, 2, 2, 2, 2, 2, 2]);
  });

  test('bot simulations', () {
    expect(runSims(werewolfGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
