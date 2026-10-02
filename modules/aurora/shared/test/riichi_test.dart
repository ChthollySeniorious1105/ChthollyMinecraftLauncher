import 'dart:math';

import 'package:aurora_shared/games/riichi/defs.dart';
import 'package:aurora_shared/games/riichi/engine.dart';
import 'package:aurora_shared/games/riichi/scoring.dart';
import 'package:aurora_shared/games/riichi/shanten.dart';
import 'package:aurora_shared/games/riichi/state.dart';
import 'package:aurora_shared/games/riichi/tiles.dart';
import 'package:aurora_shared/games/riichi/yaku.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

/// Build a context from a 14-tile concealed string (winning tile included).
HandValue? ev(String hand, String win,
    {bool tsumo = false,
    bool riichi = false,
    bool ippatsu = false,
    List<Group> melds = const [],
    int dora = 0,
    int seat = kSouth,
    int round = kEast}) {
  final c = countsOfKinds(parseHand(hand));
  return evaluateHand(WinContext(
    counts: c,
    winKind: parseKind(win),
    melds: melds,
    tsumo: tsumo,
    riichi: riichi,
    ippatsu: ippatsu,
    dora: dora,
    seatWind: seat,
    roundWind: round,
  ));
}

List<String> names(HandValue v) => [for (final y in v.yaku) y.name];

/// A freshly started engine of [id] with [opts] overriding the defaults.
RiichiGame mk(String id, {Map<String, dynamic> opts = const {}, int seed = 1}) {
  final def = riichiGames.firstWhere((d) => d.id == id);
  final o = {...def.defaultOptions(), ...opts};
  final n = def.playerRange(o).$1;
  final e = def.create(GameSetup(
      players: n,
      options: o,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed))) as RiichiGame;
  e.host = SimHost();
  e.start();
  return e;
}

/// Builds a constructed position on top of a started engine.
class Deal {
  final RiichiGame e;
  final Map<int, List<int>> pool = {};
  Deal(this.e) {
    for (final id in e.ts.allIds()) {
      pool.putIfAbsent(kindOf(id), () => []).add(id);
    }
  }

  int take(String code) => pool[parseKind(code)]!.removeAt(0);

  List<int> takeAll(String hand) => [for (final k in parseHand(hand)) pool[k]!.removeAt(0)];

  /// Preset meld ('pon' / 'ankan') for [seat], called from [from].
  void meld(int seat, String type, String code, int from) {
    final ids = [for (var i = 0; i < (type == 'pon' ? 3 : 4); i++) take(code)];
    e.ps[seat].melds.add(Meld(type, ids, type == 'ankan' ? -1 : ids.last, type == 'ankan' ? -1 : from));
    if (type != 'pon') e.kanTotal++;
  }

  void river(int seat, String tiles) {
    for (final id in takeAll(tiles)) {
      e.ps[seat].river.add(Discard(id));
    }
    e.firstTurn[seat] = false;
  }

  /// Sets hands, gives the dealer [drawn], and puts [wall] at the front of the live wall
  /// (the live wall is exactly [wall] when [exactWall]).
  void finish(List<String> hands, String drawn, {List<String> wall = const [], bool exactWall = false}) {
    final d = e.dealer;
    for (var s = 0; s < e.n; s++) {
      e.ps[s].hand
        ..clear()
        ..addAll(takeAll(hands[s]));
    }
    final dr = take(drawn);
    e.ps[d].hand.add(dr);
    e.drawnId = dr;
    e.turn = d;
    e.phase = 'turn';
    final front = [for (final c in wall) take(c)];
    final rest = [for (final l in pool.values) ...l];
    e.indicators = rest.sublist(0, 5);
    e.uraIndicators = rest.sublist(5, 10);
    e.rinshanPile = rest.sublist(10, 14);
    e.live = exactWall ? front : [...front, ...rest.sublist(14)];
  }
}

/// A noten 13-tile hand without 1m / 7s-9s / 9m / 9p / 5s / 7m.
const junk = '2m5m8m2p5p8p1s3s6s1z2z3z4z';

void setDealer(RiichiGame e, int dealer) {
  e.oya0 = dealer;
  e.kyoku = 0;
  e.roundWind = 0;
}

void disc(RiichiGame e, int s, String code, {bool riichi = false}) {
  final id = e.ps[s].hand.lastWhere((i) => kindOf(i) == parseKind(code));
  e.handle(s, {'t': 'discard', 'tile': id, 'riichi': riichi});
}

/// Everyone offered a call passes.
void skipAll(RiichiGame e) {
  while (e.phase == 'call' || e.phase == 'chankan') {
    e.handle(e.waitingFor.first, {'t': 'skip'});
  }
}

void main() {
  // rule tests step engines synchronously; the timing cover is tested in the sims
  claimCoverEnabled = false;
  group('shanten', () {
    test('complete / tenpai / chiitoi / kokushi', () {
      expect(shanten(countsOfKinds(parseHand('123m456m789p234s99p')), 0), -1);
      expect(shanten(countsOfKinds(parseHand('123m456m789p23s99p')), 0), 0);
      expect(shanten(countsOfKinds(parseHand('1122m3344p5566s7z')), 0), 0);
      expect(shanten(countsOfKinds(parseHand('19m19p19s1234567z')), 0), 0);
      expect(shanten(countsOfKinds(parseHand('147m258p369s1234z')), 0), 6);
      expect(waitsOf(countsOfKinds(parseHand('1112345678999m')), 0).length, 9);
      expect(waitsOf(countsOfKinds(parseHand('19m19p19s1234567z')), 0).length, 13);
      // open hand: 1 meld + 10 tiles tenpai
      expect(shanten(countsOfKinds(parseHand('123m456p78s55z')), 1), 0);
    });
  });

  group('yaku / fu / points', () {
    test('pinfu tsumo 2han20fu = 400/700', () {
      final v = ev('123m456m789p234s99p', '4s', tsumo: true)!;
      expect(names(v), containsAll(['平和', '门前清自摸和']));
      expect(v.han, 2);
      expect(v.fu, 20);
      expect(tsumoPoints(v.basePoints, false), (700, 400));
    });

    test('pinfu ron 30fu = 1000', () {
      final v = ev('123m456m789p234s99p', '4s')!;
      expect(names(v), ['平和']);
      expect(v.fu, 30);
      expect(ronPoints(v.basePoints, false), 1000);
    });

    test('riichi ippatsu tsumo pinfu = 4han20fu 1300/2600', () {
      final v = ev('123m456m789p234s99p', '4s', tsumo: true, riichi: true, ippatsu: true)!;
      expect(names(v), containsAll(['立直', '一发', '门前清自摸和', '平和']));
      expect(v.han, 4);
      expect(tsumoPoints(v.basePoints, false), (2600, 1300));
    });

    test('chiitoitsu 25fu', () {
      final v = ev('11m22p33p44s55s77z99m', '7z')!;
      expect(names(v), contains('七对子'));
      expect(v.fu, 25);
      expect(v.han, 2);
      expect(ronPoints(v.basePoints, false), 1600);
    });

    test('kokushi single wait and 13-sided', () {
      final a = ev('19m19p19s12345677z', '1m')!;
      expect(a.yakuman, 1);
      final b = ev('19m19p19s12345677z', '7z')!;
      expect(b.yakuman, 2);
      expect(ronPoints(b.basePoints, false), 64000);
    });

    test('open tanyao 1han30fu = 1000', () {
      final v = ev('345m678s345p88s', '5p', melds: const [Group(1, 10, true)])!;
      expect(names(v), ['断幺九']);
      expect(v.fu, 30);
      expect(ronPoints(v.basePoints, false), 1000);
      // no kuitan: no yaku
      final c = countsOfKinds(parseHand('345m678s345p88s'));
      expect(
          evaluateHand(WinContext(counts: c, winKind: parseKind('5p'), melds: const [Group(1, 10, true)], kuitan: false)),
          isNull);
    });

    test('dora alone is not a yaku; dora counts on top', () {
      final c = countsOfKinds(parseHand('123m456m789p11s'));
      expect(
          evaluateHand(WinContext(counts: c, winKind: parseKind('1s'), melds: const [Group(0, 18, true)], dora: 3)),
          isNull);
      final v = ev('234m567m234p678s55p', '4m', riichi: true, dora: 2)!;
      // riichi + pinfu + tanyao + dora2 = 5 han mangan
      expect(v.han, 5);
      expect(names(v), containsAll(['立直', '平和', '断幺九', '宝牌']));
      expect(ronPoints(v.basePoints, true), 12000);
      expect(ronPoints(v.basePoints, false), 8000);
    });

    test('dora indicator wraps', () {
      expect(doraFromIndicator(parseKind('9m')), parseKind('1m'));
      expect(doraFromIndicator(parseKind('4z')), parseKind('1z'));
      expect(doraFromIndicator(parseKind('7z')), parseKind('5z'));
      expect(doraFromIndicator(parseKind('1m'), sanma: true), parseKind('9m'));
    });

    test('fu: kanchan + closed honor triplet + yakuhai', () {
      // 13m ron 2m (kanchan), 777z ankou (中, 8 fu), 456p, 789s, pair 55s
      final v = ev('123m777z456p789s55s', '2m')!;
      expect(names(v), contains('役牌 中'));
      // 20 + 10 menzen ron + 2 kanchan + 8 = 40
      expect(v.fu, 40);
      expect(v.han, 1);
      expect(ronPoints(v.basePoints, false), 1300);
    });

    test('ron on shanpon makes the triplet open', () {
      // 111z(东, round+seat for dealer) 222m 456p 789s + 33s; ron 2m shanpon
      final v = ev('111z222m456p789s33s', '2m', seat: kEast)!;
      // double east = 2 han; fu: 20+10+ 8 (east ankou) + 2 (2m minko) = 40
      expect(v.han, 2);
      expect(v.fu, 40);
    });

    test('yakuman: suuankou tanki, daisangen, junsei chuuren, tsuuiisou', () {
      expect(ev('111m333p555s777z22z', '2z', tsumo: true)!.yakuman, 2);
      expect(ev('111m333p555s777z22z', '1m', tsumo: true)!.yakuman, 1);
      expect(names(ev('555z666z777z123m44p', '4p')!), contains('大三元'));
      expect(ev('11123455678999m', '5m')!.yakuman, 2);
      expect(ev('11123456789999m', '5m')!.yakuman, 1);
      expect(names(ev('11122233344455z', '5z')!), contains('字一色'));
      final g = ev('22334466888s666z', '4s')!;
      expect(names(g), contains('绿一色'));
    });

    test('honitsu / chinitsu / ittsu / sanshoku / iipeikou', () {
      final a = ev('123456789m11122z', '9m')!;
      expect(names(a), containsAll(['一气通贯', '混一色']));
      final b = ev('112233m456m78999m', '9m')!;
      expect(names(b), contains('清一色'));
      final c = ev('123m123p123s456m99s', '6m')!;
      expect(names(c), contains('三色同顺'));
      final d = ev('112233m456p789s55z', '3m')!;
      expect(names(d), contains('一杯口'));
    });

    test('limit hands', () {
      expect(const HandValue([], 6, 30, 0).basePoints, 3000);
      expect(const HandValue([], 8, 30, 0).basePoints, 4000);
      expect(const HandValue([], 11, 30, 0).basePoints, 6000);
      expect(const HandValue([], 13, 30, 0).basePoints, 8000);
      expect(const HandValue([], 4, 40, 0).basePoints, 2000);
      expect(const HandValue([], 3, 30, 0).basePoints, 960);
      expect(ronPoints(960, false), 3900);
      expect(ronPoints(960, true), 5800);
      expect(tsumoPoints(960, false), (2000, 1000));
      expect(tsumoPoints(960, true), (2000, 2000));
    });
  });

  group('engine', () {
    Map<String, dynamic> startGame(String id, int seed) {
      final def = riichiGames.firstWhere((d) => d.id == id);
      final (lo, _) = def.playerRange(def.defaultOptions());
      final e = def.create(GameSetup(
          players: lo,
          options: def.defaultOptions(),
          names: [for (var i = 0; i < lo; i++) 'P$i'],
          bots: List.filled(lo, true),
          rng: Random(seed)));
      e.host = SimHost();
      e.start();
      return {'e': e, 'n': lo};
    }

    test('views hide other hands', () {
      final g = startGame('riichi4', 3);
      final e = g['e'] as GameEngine;
      final v = e.view(0);
      final seats = v['seats'] as List;
      for (var s = 1; s < 4; s++) {
        final h = (seats[s] as Map)['hand'] as List;
        expect(h.every((c) => c == 'back'), isTrue);
      }
      final spec = e.view(-1);
      expect(((spec['seats'] as List)[0] as Map)['hand'].every((c) => c == 'back'), isTrue);
      expect(spec.containsKey('me'), isFalse);
    });

    test('mingjing shows transparent tiles', () {
      final g = startGame('majsoul_mingjing', 5);
      final e = g['e'] as GameEngine;
      final h = (((e.view(0)['seats'] as List)[1] as Map)['hand'] as List).cast<String>();
      expect(h.any((c) => c.startsWith('G')), isTrue);
      expect(h.length, 13);
    });

    test('wanxiang deals one of 4 extra wildcard tiles each', () {
      final g = startGame('majsoul_wanxiang', 7);
      final e = g['e'] as RiichiGame;
      final ids = <int>{};
      for (var s = 0; s < 4; s++) {
        final hand = ((e.view(s)['me'] as Map)['hand'] as List).cast<Map>();
        final w = hand.where((t) => t['c'] == 'W').toList();
        expect(w.length, 1);
        ids.add((w.first['id'] as num).toInt());
        expect(hand.length, 13 + (e.turn == s && e.phase == 'turn' ? 1 : 0));
      }
      // extra tiles, not relabelled real ones: the normal 136 are all still in play
      expect(ids, {136, 137, 138, 139});
      final all = [
        ...e.live, ...e.indicators, ...e.uraIndicators, ...e.rinshanPile,
        for (final p in e.ps) ...p.hand,
      ];
      expect(all.where((id) => id < 136).toSet().length, 136);
    });

    test('shura exchange accepts any 3 tiles (no same-suit rule)', () {
      final g = startGame('majsoul_shura', 11);
      final e = g['e'] as RiichiGame;
      expect(e.phase, 'exchange');
      final hand = e.ps[0].hand;
      // pick tiles of different suits if possible
      final pick = <int>[];
      final suits = <int>{};
      for (final id in hand) {
        if (suits.add(suitOf(kindOf(id)))) pick.add(id);
        if (pick.length == 3) break;
      }
      for (final id in hand) {
        if (pick.length == 3) break;
        if (!pick.contains(id)) pick.add(id);
      }
      e.handle(0, {'t': 'exchange', 'tiles': pick});
      expect(e.exchSel[0], pick);
    });

    test('bloodbath tsumo winner only shows the winning tile', () {
      final e = mk('majsoul_shura');
      setDealer(e, 0);
      e.phase = 'turn';
      e.ps[1]
        ..won = true
        ..wonTsumo = true
        ..winTile = e.ps[1].hand.last;
      final seat1 = (e.view(0)['seats'] as List)[1] as Map;
      final hand = (seat1['hand'] as List).cast<String>();
      expect(hand.every((c) => c == 'back'), isTrue);
      expect(seat1['drawn'], isNot('back'));
      expect(seat1['drawn'], isNotNull);
    });

    test('四风连打: four identical first wind discards abort, dealer stays, honba +1', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      Deal(e).finish(List.filled(4, '1m4m7m2p5p8p3s6s9s2z3z5z1z'), '9m');
      for (var i = 0; i < 4; i++) {
        expect(e.turn, i);
        disc(e, i, '1z');
      }
      expect(e.phase, 'result');
      expect(e.result!['drawName'], '四风连打');
      expect(e.result!['abort'], true);
      expect(e.honba, 1);
      expect(e.dealer, 0);
      expect(e.ps.every((p) => p.score == 25000), isTrue);
    });

    test('四风连打 does not apply to other modes (明镜)', () {
      final e = mk('majsoul_mingjing');
      setDealer(e, 0);
      Deal(e).finish(List.filled(4, '1m4m7m2p5p8p3s6s9s2z3z5z1z'), '9m');
      for (var i = 0; i < 4; i++) {
        disc(e, e.turn, '1z');
      }
      expect(e.phase, 'turn');
    });

    test('四家立直: 4th riichi not ronned aborts, sticks stay on the table', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      Deal(e).finish(List.filled(4, '123456789m123p5p'), '7z', wall: ['7z', '7z', '7z']);
      for (var i = 0; i < 4; i++) {
        disc(e, e.turn, '7z', riichi: true);
      }
      expect(e.result!['drawName'], '四家立直');
      expect(e.kyoutaku, 4);
      expect(e.honba, 1);
      expect(e.ps.every((p) => p.score == 24000), isTrue);
      for (var s = 0; s < 4; s++) {
        e.handle(s, {'t': 'ok'});
      }
      expect(e.kyoutaku, 4);
      expect(e.dealer, 0);
    });

    test('四杠散了: 4 kans by 2+ players abort after the next discard', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      final d = Deal(e);
      d.meld(1, 'ankan', '9s', -1);
      d.meld(1, 'ankan', '8s', -1);
      d.meld(2, 'ankan', '7s', -1);
      d.finish(['1111m2p5p8p3s6s5z6z7z4z', '2m5m8m2p5p1z2z', '2m5m8m2p5p8p1s1z2z3z', junk], '9m');
      e.handle(0, {'t': 'ankan', 'kind': parseKind('1m')});
      expect(e.kanTotal, 4);
      expect(e.phase, 'turn');
      e.handle(0, {'t': 'discard', 'tile': e.drawnId});
      skipAll(e);
      expect(e.result?['drawName'], '四杠散了');
      expect(e.honba, 1);
    });

    test('四杠 by a single player does not abort', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      final d = Deal(e);
      d.meld(0, 'ankan', '9s', -1);
      d.meld(0, 'ankan', '8s', -1);
      d.meld(0, 'ankan', '7s', -1);
      d.finish(['1111m', junk, junk, junk], '9m');
      e.handle(0, {'t': 'ankan', 'kind': parseKind('1m')});
      e.handle(0, {'t': 'discard', 'tile': e.drawnId});
      skipAll(e);
      expect(e.phase, 'turn');
      expect(e.result, isNull);
    });

    for (final on in [true, false]) {
      test('三家和了 option ${on ? "on: abortive draw" : "off: triple ron"}', () {
        final e = mk('riichi4', opts: {'tripleRon': on});
        setDealer(e, 0);
        Deal(e).finish(
            ['1m4m7m2p8p3s6s9s1z2z3z4z6z', '123456789m123p5p', '123456789m123p5p', '123456789m123p5p'], '5p');
        disc(e, 0, '5p');
        expect(e.phase, 'call');
        for (var s = 1; s < 4; s++) {
          e.handle(s, {'t': 'ron'});
        }
        expect(e.phase, 'result');
        if (on) {
          expect(e.result!['drawName'], '三家和了');
          expect(e.ps.every((p) => p.score == 25000), isTrue);
          expect(e.honba, 1);
          expect(e.dealer, 0);
        } else {
          expect((e.result!['wins'] as List).length, 3);
          expect(e.ps[0].score, lessThan(25000));
        }
      });
    }

    for (final on in [true, false]) {
      test('流局满贯 ${on ? "replaces tenpai payments" : "disabled"}', () {
        final e = mk('riichi4', opts: {'nagashi': on});
        setDealer(e, 0);
        final d = Deal(e);
        d.river(1, '19m9p1s5z');
        d.finish([junk, '2m5m8m2p5p8p1s3s6s1z2z3z6z', '123456789m123p5p', '2m5m8m2p5p8p3s6s4z6z7z1p4p'], '7m',
            exactWall: true);
        disc(e, 0, '7m');
        expect(e.phase, 'result');
        final delta = (e.result!['deltas'] as List).cast<int>();
        if (on) {
          expect(e.result!['drawName'], '流局满贯');
          expect((e.result!['nagashi'] as List).single, {'seat': 1, 'points': 8000});
          expect(delta, [-4000, 8000, -2000, -2000]);
        } else {
          expect(e.result!['drawName'], '荒牌流局');
          expect(delta, [-1000, -1000, 3000, -1000]);
        }
        expect(e.dealer, 1); // dealer was noten
      });
    }

    test('final score: uma 10-20 + oka 20, tiebreak by seat order from the start dealer', () {
      final e = mk('riichi4');
      e.oya0 = 2;
      e.roundWind = 1;
      e.kyoku = 3; // 南4局, dealer = seat 1
      for (final (s, v) in [(0, 30000), (1, 30000), (2, 20000), (3, 20000)]) {
        e.ps[s].score = v;
      }
      Deal(e).finish([junk, junk, junk, junk], '7m', exactWall: true);
      disc(e, 1, '7m');
      expect(e.isOver, isTrue);
      final rk = (e.finalResult!['ranking'] as List).cast<Map>();
      expect([for (final r in rk) r['seat']], [0, 1, 2, 3]);
      expect([for (final r in rk) r['final']], [40.0, 10.0, -20.0, -30.0]);
    });

    test('final score: uma 无 has only oka', () {
      final e = mk('riichi4', opts: {'uma': 'none'});
      e.oya0 = 0;
      e.roundWind = 1;
      e.kyoku = 3;
      for (final (s, v) in [(0, 45000), (1, 25000), (2, 20000), (3, 10000)]) {
        e.ps[s].score = v;
      }
      Deal(e).finish([junk, junk, junk, junk], '7m', exactWall: true);
      disc(e, 3, '7m');
      final rk = (e.finalResult!['ranking'] as List).cast<Map>();
      expect([for (final r in rk) r['final']], [35.0, -5.0, -10.0, -20.0]);
    });

    test('final score 三麻: uma 15 + oka 15', () {
      final e = mk('riichi3');
      e.oya0 = 0;
      e.roundWind = 1;
      e.kyoku = 2; // 南3局, dealer = seat 2
      for (final (s, v) in [(0, 50000), (1, 30000), (2, 25000)]) {
        e.ps[s].score = v;
      }
      const h = '1m9m1p4p7p2s5s8s1z2z3z5z6z';
      Deal(e).finish([h, h, h], '5s', exactWall: true);
      disc(e, 2, '5s');
      expect(e.isOver, isTrue);
      final rk = (e.finalResult!['ranking'] as List).cast<Map>();
      expect([for (final r in rk) r['final']], [40.0, -10.0, -30.0]);
    });

    test('包牌 大三元: ron by another player splits the yakuman', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      final d = Deal(e);
      d.meld(1, 'pon', '5z', 3);
      d.meld(1, 'pon', '6z', 3);
      d.finish([junk, '77z234m9s9p', junk, junk], '7z', wall: ['9s']);
      disc(e, 0, '7z');
      e.handle(1, {'t': 'pon'});
      expect(e.ps[1].pao, 0);
      disc(e, 1, '9p');
      skipAll(e);
      expect(e.turn, 2);
      e.handle(2, {'t': 'discard', 'tile': e.drawnId});
      e.handle(1, {'t': 'ron'});
      final delta = (e.result!['deltas'] as List).cast<int>();
      expect(delta, [-16000, 32000, -16000, 0]);
      expect(((e.result!['wins'] as List).first as Map)['pao'], {'seat': 0, 'yaku': '大三元'});
    });

    test('包牌 大三元: tsumo is paid in full by the liable player', () {
      final e = mk('riichi4');
      setDealer(e, 0);
      final d = Deal(e);
      d.meld(1, 'pon', '5z', 3);
      d.meld(1, 'pon', '6z', 3);
      d.finish([junk, '77z234m9s9p', junk, junk], '7z', wall: ['9m', '5s', '9p', '9s']);
      disc(e, 0, '7z');
      e.handle(1, {'t': 'pon'});
      disc(e, 1, '9p');
      skipAll(e);
      for (final s in [2, 3, 0]) {
        expect(e.turn, s);
        e.handle(s, {'t': 'discard', 'tile': e.drawnId});
        skipAll(e);
      }
      expect(e.turn, 1);
      e.handle(1, {'t': 'tsumo'});
      final delta = (e.result!['deltas'] as List).cast<int>();
      expect(delta, [-32000, 32000, 0, 0]);
    });

    test('bots finish every variant', () {
      expect(runSims(riichiGames, n: 30, maxSteps: 60000), 0);
    });
  });

  group('v3 placings', () {
    for (final def in riichiGames) {
      for (final lvl in const [0, 1, 2]) {
        test('${def.id} botLevel $lvl: placings follow final score', () {
          _checkPlacings(def, (e) => [for (final p in (e as RiichiGame).ps) p.score], level: lvl, seed: 3 + lvl);
        }, timeout: const Timeout(Duration(minutes: 5)));
      }
    }
  });
}


/// v3: plays [def] to the end with bots at [level] and checks placings follow the final scores.
void _checkPlacings(GameDef def, List<int> Function(GameEngine) scoresOf, {int seed = 5, int level = 1, Map<String, dynamic> opts = const {}}) {
  final o = {...def.defaultOptions(), ...opts};
  final n = def.playerRange(o).$1;
  final e = def.create(GameSetup(
      players: n,
      options: o,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
      botLevel: level));
  final host = SimHost();
  e.host = host;
  e.start();
  host.runPending();
  var steps = 0;
  while (!e.isOver && steps++ < 200000) {
    expect(e.placings, isNull);
    final w = e.waitingFor;
    if (w.isEmpty) {
      expect(host.runPending(), isTrue);
      continue;
    }
    e.handle(w.first, e.runBot(w.first)!);
    host.runPending();
  }
  expect(e.isOver, isTrue);
  final p = e.placings!;
  final sc = scoresOf(e);
  expect(p.length, n);
  for (var i = 0; i < n; i++) {
    for (var j = 0; j < n; j++) {
      if (sc[i] > sc[j]) expect(p[i], lessThan(p[j]), reason: 'scores $sc placings $p');
      if (sc[i] == sc[j] && !def.id.startsWith('riichi') && !def.id.startsWith('majsoul')) {
        expect(p[i], p[j], reason: 'ties share a rank: $sc $p');
      }
    }
  }
  expect(def.rules.length, greaterThan(300));
}
