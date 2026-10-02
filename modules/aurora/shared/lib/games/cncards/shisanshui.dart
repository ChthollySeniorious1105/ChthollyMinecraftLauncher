import '../../src/engine.dart';
import 'cards.dart';
import 'ssz_rules.dart';

/// 十三水。2-4 人，每人 13 张摆成 前3/中5/后5 三墩，两两比牌。
class Shisanshui extends GameEngine {
  Shisanshui(super.setup);

  late int rounds;
  late bool specialsOn;
  late bool homerunOn;
  int round = 0;
  late List<int> scores;
  late List<List<String>> hands;
  late List<SsArrangement?> placed;
  String phase = 'arrange'; // arrange | roundEnd | over
  Map<String, dynamic>? result;
  late List<bool> ready;

  int resigned = -1;

  @override
  bool get isOver => phase == 'over';

  @override
  List<int>? get placings {
    if (!isOver) return null;
    if (resigned >= 0) return rankWinners(players, [for (var s = 0; s < players; s++) if (s != resigned) s]);
    return rankByScore(scores);
  }

  @override
  bool get canResign => !isOver && players == 2;

  @override
  void resign(int seat) {
    if (!canResign || seat < 0 || seat >= players) throw GameError('现在不能认输');
    resigned = seat;
    phase = 'over';
    host.log('${name(seat)} 认输');
    host.log('游戏结束！${name(1 - seat)} 获胜');
  }

  @override
  List<int> get waitingFor {
    if (phase == 'arrange') return [for (var s = 0; s < players; s++) if (placed[s] == null) s];
    if (phase == 'roundEnd') return [for (var s = 0; s < players; s++) if (!ready[s]) s];
    return const [];
  }

  @override
  void start() {
    rounds = setup.opt<int>('rounds', 5);
    specialsOn = setup.opt<bool>('specials', true);
    homerunOn = setup.opt<bool>('homerun', true);
    scores = List.filled(players, 0);
    host.log('十三水开始：共 $rounds 局');
    _deal();
  }

  void _deal() {
    round++;
    final deck = shuffled(cnDeck(), rng);
    hands = [
      for (var s = 0; s < players; s++) deck.sublist(s * 13, s * 13 + 13)..sort((a, b) => cnRank(b) - cnRank(a))
    ];
    placed = List.filled(players, null);
    ready = List.filled(players, false);
    result = null;
    phase = 'arrange';
  }

  @override
  void handle(int seat, Map<String, dynamic> a) {
    final type = asStr(a['type']);
    if (phase == 'roundEnd') {
      if (type != 'continue') throw GameError('请点击继续');
      ready[seat] = true;
      if (waitingFor.isEmpty) _deal();
      return;
    }
    if (phase != 'arrange') throw GameError('游戏已结束');
    if (type != 'arrange') throw GameError('请摆好三墩后确认');
    if (placed[seat] != null) throw GameError('你已经确认了');
    List<String> lane(String k) => a[k] is List ? [for (final c in a[k] as List) '$c'] : <String>[];
    final f = lane('front'), m = lane('mid'), b = lane('back');
    if (f.length != 3 || m.length != 5 || b.length != 5) throw GameError('前墩3张、中墩5张、后墩5张');
    final all = [...f, ...m, ...b];
    final pool = List.of(hands[seat]);
    for (final c in all) {
      if (!pool.remove(c)) throw GameError('牌不在你的手中');
    }
    if (!ssValid(f, m, b) && a['force'] != true) {
      throw GameError('倒水了：需要 后墩 ≥ 中墩 ≥ 前墩');
    }
    placed[seat] = SsArrangement(f, m, b);
    host.log('${name(seat)} 已理好牌');
    if (waitingFor.isEmpty) _settle();
  }

  void _settle() {
    final foul = <bool>[];
    final sc = <List<int>>[];
    final special = <SsSpecial?>[];
    for (var s = 0; s < players; s++) {
      final p = placed[s]!;
      foul.add(!ssValid(p.front, p.mid, p.back));
      sc.add([ssEval(p.front), ssEval(p.mid), ssEval(p.back)]);
      special.add(specialsOn ? ssSpecial(hands[s]) : null);
    }
    final delta = List.filled(players, 0);
    final pair = List.generate(players, (_) => List.filled(players, 0));
    final laneRes = List.generate(players, (_) => List.generate(players, (_) => [0, 0, 0]));
    final guns = <List<int>>[]; // [shooter, target]
    for (var a = 0; a < players; a++) {
      for (var b = a + 1; b < players; b++) {
        int t;
        if (special[a] != null || special[b] != null) {
          final va = special[a]?.value ?? 0, vb = special[b]?.value ?? 0;
          t = va - vb;
          if (special[a] != null && special[b] != null) t = va.compareTo(vb) * (va > vb ? va : vb);
        } else {
          final r = ssComparePair(sc[a], sc[b], aFoul: foul[a], bFoul: foul[b]);
          t = r.total;
          laneRes[a][b] = r.lanes;
          laneRes[b][a] = [for (final x in r.lanes) -x];
          if (r.sweep) guns.add(t > 0 ? [a, b] : [b, a]);
        }
        pair[a][b] = t;
        pair[b][a] = -t;
      }
    }
    // 全垒打：打枪所有其他玩家（至少3人），对每人的得失再翻倍
    final homerun = <int>[];
    if (homerunOn && players >= 3) {
      for (var s = 0; s < players; s++) {
        if (guns.where((g) => g[0] == s).length == players - 1) {
          homerun.add(s);
          for (var o = 0; o < players; o++) {
            if (o == s) continue;
            pair[s][o] *= 2;
            pair[o][s] *= 2;
          }
        }
      }
    }
    for (var a = 0; a < players; a++) {
      for (var b = 0; b < players; b++) {
        delta[a] += pair[a][b];
      }
      scores[a] += delta[a];
    }
    for (final g in guns) {
      host.log('${name(g[0])} 打枪 ${name(g[1])}！');
    }
    for (final s in homerun) {
      host.log('${name(s)} 全垒打！');
    }
    result = {
      'delta': delta,
      'pair': pair,
      'lanes': laneRes,
      'foul': foul,
      'special': [for (final x in special) x?.name],
      'guns': guns,
      'homerun': homerun,
      'laneNames': [for (final l in sc) [for (final x in l) ssName(x)]],
      'arr': [for (final p in placed) p!.toJson()],
    };
    phase = round >= rounds ? 'over' : 'roundEnd';
  }

  List<int> get ranking {
    final r = List.generate(players, (i) => i);
    r.sort((a, b) => scores[b] - scores[a]);
    return r;
  }

  @override
  Map<String, dynamic> view(int seat) {
    final ended = phase != 'arrange';
    return {
      'phase': phase,
      'round': round,
      'rounds': rounds,
      'scores': scores,
      'hand': seat >= 0 ? hands[seat] : <String>[],
      'mine': seat >= 0 ? placed[seat]?.toJson() : null,
      'mySpecial': seat >= 0 && specialsOn ? ssSpecial(hands[seat])?.name : null,
      'done': [for (final p in placed) p != null],
      'result': ended ? result : null,
      'ready': phase == 'roundEnd' ? ready : null,
      'ranking': phase == 'over' ? ranking : null,
    };
  }

  @override
  Map<String, dynamic>? bot(int seat) {
    if (phase == 'roundEnd') return ready[seat] ? null : {'type': 'continue'};
    if (phase != 'arrange' || placed[seat] != null) return null;
    // 简单：一半概率随便摆一个不倒水的牌型；困难：额外考虑打枪翻倍
    final lvl = botLevel <= 0 ? (rng.nextDouble() < 0.5 ? 0 : 1) : (botLevel >= 2 ? 2 : 1);
    final a = ssBestArrangement(hands[seat], level: lvl, rng: rng);
    return {'type': 'arrange', ...a.toJson()};
  }

  @override
  int get botDelayMs => 1200;
}
