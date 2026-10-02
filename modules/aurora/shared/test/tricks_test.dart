import 'dart:math';

import 'package:aurora_shared/games/tricks/bridge.dart';
import 'package:aurora_shared/games/tricks/bridge_rules.dart';
import 'package:aurora_shared/games/tricks/cards.dart';
import 'package:aurora_shared/games/tricks/defs.dart';
import 'package:aurora_shared/games/tricks/hearts.dart';
import 'package:aurora_shared/games/tricks/spades.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup(Map<String, dynamic> opts, {int seed = 3}) => GameSetup(
      players: 4,
      options: opts,
      names: ['北', '东', '南', '西'],
      bots: List.filled(4, true),
      rng: Random(seed),
    );

BrAuction _auction(int dealer, String calls) {
  final a = BrAuction(dealer);
  for (final c in calls.split(' ')) {
    a.add(a.turn, c);
  }
  return a;
}

int _dup(String c, bool vul, int tricks, {int doubled = 0}) =>
    brScore(BrContract(int.parse(c[0]), c[1], doubled, 0), vul, tricks).duplicateTotal(vul);

void main() {
  group('桥牌叫牌', () {
    test('合法性', () {
      final a = _auction(0, '1H');
      expect(a.illegal(1, '1D'), isNotNull); // lower
      expect(a.illegal(1, '1H'), isNotNull); // same
      expect(a.illegal(1, '1S'), isNull);
      expect(a.illegal(1, 'X'), isNull);
      expect(a.illegal(1, 'XX'), isNotNull);
      expect(a.illegal(2, '2H'), isNotNull); // not your turn
      a.add(1, 'P');
      expect(a.illegal(2, 'X'), isNotNull); // cannot double partner
      a.add(2, 'P');
      expect(a.illegal(3, 'X'), isNull); // double after two passes
      a.add(3, 'X');
      expect(a.illegal(0, 'XX'), isNull);
      expect(a.illegal(0, 'X'), isNotNull);
      a.add(0, 'P');
      expect(a.illegal(1, 'XX'), isNotNull); // cannot redouble own double
      a.add(1, 'P');
      expect(a.illegal(2, 'XX'), isNull);
      a.add(2, 'XX');
      expect(a.doubled, 2);
      expect(a.isOver, isFalse);
      a.add(3, 'P');
      a.add(0, 'P');
      a.add(1, 'P');
      expect(a.isOver, isTrue);
      expect(a.declarer, 0);
    });

    test('四家不叫', () {
      final a = _auction(2, 'P P P P');
      expect(a.passedOut, isTrue);
      final b = _auction(2, 'P P P');
      expect(b.isOver, isFalse);
    });

    test('定约人 = 本方最先叫出该花色者', () {
      // N 1H, E P, S 2H, W P, N 4H -> declarer N
      expect(_auction(0, '1H P 2H P 4H P P P').declarer, 0);
      // N 1C, E P, S 1H, W P, N 2H, E P, S 4H ... -> S named hearts first
      expect(_auction(0, '1C P 1H P 2H P 4H P P P').declarer, 2);
      // E opens 1S, S overcalls 2H, W 2S, N 3H -> declarer S
      final a = _auction(1, '1S 2H 2S 3H P P P');
      expect(a.declarer, 2);
      expect(a.doubled, 0);
      // doubled then new bid clears double
      expect(_auction(0, '1N X 2C P P P').doubled, 0);
    });

    test('legalCalls', () {
      final a = _auction(0, '7N');
      final l = a.legalCalls(1);
      expect(l, containsAll(['P', 'X']));
      expect(l.where(brIsBid), isEmpty);
    });
  });

  group('桥牌计分（复式）', () {
    test('典型分数', () {
      expect(_dup('4S', true, 10), 620);
      expect(_dup('4S', false, 10), 420);
      expect(_dup('3N', false, 10), 430);
      expect(_dup('3N', true, 9), 600);
      expect(_dup('1N', false, 5, doubled: 1), -300);
      expect(_dup('6H', true, 12), 1430);
      expect(_dup('6H', false, 12), 980);
      expect(_dup('7N', true, 13), 2220);
      expect(_dup('2S', false, 8), 110);
      expect(_dup('2S', false, 8, doubled: 1), 470);
      expect(_dup('1N', false, 7, doubled: 2), 560); // 1NTxx = 160 + 300 + 100
      expect(_dup('4H', true, 7), -300);
      expect(_dup('4H', true, 7, doubled: 1), -800);
      expect(_dup('4H', false, 6, doubled: 1), -800);
      expect(_dup('4H', false, 11, doubled: 1), 690);
      expect(_dup('3C', false, 10), 130);
      expect(_dup('5D', false, 11), 400);
      expect(_dup('1N', false, 5, doubled: 2), -600);
    });

    test('宕墩表', () {
      int down(int n, bool vul, int d) => -_dup('7N', vul, 13 - n, doubled: d);
      expect([for (var i = 1; i <= 5; i++) down(i, false, 1)], [100, 300, 500, 800, 1100]);
      expect([for (var i = 1; i <= 4; i++) down(i, true, 1)], [200, 500, 800, 1100]);
      expect(down(3, false, 0), 150);
    });

    test('大牌分与芝加哥局况', () {
      final hands = [
        ['AS', 'KS', 'QS', 'JS', '2H'],
        <String>[],
        <String>[],
        <String>[],
      ];
      expect(brHonours(hands, 'S'), (0, 100));
      expect(brChicagoVul(0, 0), [false, false]);
      expect(brChicagoVul(1, 1), [false, true]);
      expect(brChicagoVul(2, 2), [true, false]);
      expect(brChicagoVul(3, 3), [true, true]);
    });
  });

  group('桥牌引擎', () {
    test('明手由庄家代打，明手手牌在首攻后公开', () {
      final e = Bridge(_setup({'scoring': 'rubber', 'cap': 0}));
      e.start();
      // force: N 1S, everyone passes
      e.handle(0, {'type': 'call', 'call': '1S'});
      for (final s in [1, 2, 3]) {
        e.handle(s, {'type': 'call', 'call': 'P'});
      }
      expect(e.phase, 'play');
      expect(e.declarer, 0);
      expect(e.turn, 1);
      expect(e.view(1)['dummyHand'], isNull);
      e.handle(1, {'type': 'play', 'card': e.hands[1].first});
      expect(e.turn, 2);
      expect(e.waitingFor, [0]);
      expect(e.view(3)['dummyHand'], isNotNull);
      expect(() => e.handle(2, {'type': 'play', 'card': e.hands[2].first}), throwsA(isA<GameError>()));
      final legal = (e.view(0)['legal'] as List).cast<String>();
      expect(legal.every(e.hands[2].contains), isTrue);
      e.handle(0, {'type': 'play', 'card': legal.first});
      expect(e.turn, 3);
    });

    test('bot 不偷看', () {
      final e = Bridge(_setup({'scoring': 'chicago', 'cap': 0}));
      e.start();
      final v = e.view(1);
      expect(v['hand'], e.hands[1]);
      expect(v['dummyHand'], isNull);
      expect(v['allHands'], isNull);
    });
  });

  group('红心大战', () {
    test('射月', () {
      void check(List<int> taken, bool moon, List<int> add, int shooter) {
        final (a, s) = heartsHandScore(taken, moon);
        expect(a, add);
        expect(s, shooter);
      }

      check([0, 26, 0, 0], true, [26, 0, 26, 26], 1);
      check([0, 26, 0, 0], false, [0, 26, 0, 0], -1);
      check([13, 5, 8, 0], true, [13, 5, 8, 0], -1);
    });

    test('射月计分（整局模拟）', () {
      // Give seat 0 every heart and Q♠ as winners by constructing hands.
      final e = Hearts(_setup({'target': 100, 'moon': true, 'firstClean': false, 'cap': 0}));
      final host = SimHost();
      e.host = host;
      e.start();
      // hold hand: set handNo so passDir == 3
      e.handNo = 3;
      e.hands = [
        trSort(['AC', 'KC', 'QC', 'JC', 'TC', '9C', 'AH', 'KH', 'QH', 'JH', 'TH', '9H', 'AS']),
        trSort(['2C', '3C', '4C', '5C', '8H', '7H', '6H', '5H', '4H', '3H', '2H', 'QS', '2D']),
        trSort(['6C', '7C', '8C', '2S', '3S', '4S', '5S', '6S', '7S', '8S', '9S', 'TS', '3D']),
        trSort(['JS', 'KS', '4D', '5D', '6D', '7D', '8D', '9D', 'TD', 'JD', 'QD', 'KD', 'AD']),
      ];
      e.phase = 'play';
      e.turn = 1;
      // play: always the scripted choice: seat 0 plays highest legal, others lowest legal
      var guard = 0;
      while (e.phase == 'play' || e.phase == 'trickEnd') {
        if (e.phase == 'trickEnd') {
          host.runPending();
          continue;
        }
        final s = e.turn;
        final legal = e.legal(s);
        String c;
        if (s == 0) {
          c = trHighest(legal)!;
        } else {
          // dump points onto seat 0 when possible
          final pts = legal.where((x) => Hearts.points(x) > 0).toList();
          c = pts.isNotEmpty && e.trick.isNotEmpty && e.trick.any((t) => t['seat'] == 0) ? pts.first : trLowest(legal)!;
        }
        e.handle(s, {'type': 'play', 'card': c});
        if (++guard > 60) break;
      }
      final r = e.result!;
      final taken = (r['taken'] as List).cast<int>();
      if (taken[0] == 26) {
        expect(r['moon'], 0);
        expect(r['add'], [0, 26, 26, 26]);
      } else {
        expect(r['moon'], -1);
        expect((r['add'] as List).cast<int>().fold<int>(0, (a, b) => a + b), 26);
      }
    });

    test('第一墩规则与红心未破', () {
      final e = Hearts(_setup({'target': 100, 'moon': true, 'firstClean': true, 'cap': 0}));
      e.start();
      e.handNo = 3;
      e.hands = [
        trSort(['2C', 'AH', 'KH', 'QH', 'JH', 'TH', '9H', '8H', '7H', '6H', '5H', '4H', '3H']),
        trSort(['QS', '2H', 'AC', 'KC', 'QC', 'JC', 'TC', '9C', '8C', '7C', '6C', '5C', '4C']),
        trSort(['3C', 'AS', 'KS', 'JS', 'TS', '9S', '8S', '7S', '6S', '5S', '4S', '3S', '2S']),
        trSort(['AD', 'KD', 'QD', 'JD', 'TD', '9D', '8D', '7D', '6D', '5D', '4D', '3D', '2D']),
      ];
      e.phase = 'play';
      e.turn = 0;
      e.trickNo = 0;
      expect(e.legal(0), ['2C']);
      e.handle(0, {'type': 'play', 'card': '2C'});
      expect(e.legal(1).contains('QS'), isFalse);
      e.handle(1, {'type': 'play', 'card': 'AC'});
      e.handle(2, {'type': 'play', 'card': '3C'});
      // seat 3 void in clubs: may not play points, but has only diamonds
      e.handle(3, {'type': 'play', 'card': '2D'});
      expect(e.lastWinner, 1);
    });

    test('bot 传牌优先传 Q♠', () {
      final p = heartsBotPass(trSort(['QS', '3S', '2C', '3C', '4C', '5D', '6D', '7D', '8D', '9H', 'TH', 'JH', 'AH']));
      expect(p, contains('QS'));
      expect(p.length, 3);
    });
  });

  group('黑桃王计分', () {
    test('完成与袋', () {
      final r = spadesScoreTeam([4, 3], [5, 4], [false, false], 0);
      expect(r.delta, 72);
      expect(r.bags, 2);
      final f = spadesScoreTeam([5, 4], [4, 4], [false, false], 0);
      expect(f.delta, -90);
    });

    test('10 袋扣 100', () {
      final r = spadesScoreTeam([3, 3], [5, 4], [false, false], 7);
      expect(r.bags, 0); // 7 + 3 = 10 -> reset
      expect(r.delta, 60 + 3 - 100);
      expect(r.penalty, isTrue);
    });

    test('零墩', () {
      final ok = spadesScoreTeam([0, 4], [0, 5], [false, false], 0);
      expect(ok.delta, 100 + 40 + 1);
      final bad = spadesScoreTeam([0, 4], [2, 4], [false, false], 0);
      expect(bad.delta, -100 + 40 + 2);
      expect(bad.bags, 2);
      final blind = spadesScoreTeam([0, 4], [0, 4], [true, false], 0);
      expect(blind.delta, 240);
    });

    test('黑桃未破不能首出黑桃', () {
      final e = Spades(_setup({'target': 500, 'blindNil': false, 'cap': 0}));
      e.start();
      for (var i = 0; i < 4; i++) {
        e.handle(e.turn, {'type': 'bid', 'n': 3});
      }
      final s = e.turn;
      final h = e.hands[s];
      final legal = e.legal(s);
      if (h.any((c) => trSuit(c) != 'S')) expect(legal.every((c) => trSuit(c) != 'S'), isTrue);
    });
  });

  group('v3', () {
    test('placings', () {
      final h = Hearts(_setup({'target': 100}))..start();
      expect(h.placings, isNull);
      h.scores = [40, 101, 12, 40];
      h.phase = 'over';
      expect(h.placings, [2, 4, 1, 2]);
      final sp = Spades(_setup({}))..start();
      expect(sp.placings, isNull);
      sp.phase = 'over';
      sp.winner = 1;
      expect(sp.placings, [2, 1, 2, 1]);
      sp.winner = 2;
      expect(sp.placings, [1, 1, 1, 1]);
      final br = Bridge(_setup({}))..start();
      expect(br.placings, isNull);
      br.phase = 'over';
      br.winner = 0;
      expect(br.placings, [1, 2, 1, 2]);
    });

    test('hard bots are legal and fast', () {
      for (final def in tricksGames) {
        final r = simulate(def, 4, seed: 5, botLevel: 2);
        expect(r.finished, isTrue, reason: '${def.id}: ${r.error}');
      }
      final e = Hearts(GameSetup(
          players: 4, options: {}, names: ['a', 'b', 'c', 'd'], bots: List.filled(4, true), rng: Random(9), botLevel: 2));
      e.start();
      for (var s = 0; s < 4; s++) {
        e.handle(s, e.runBot(s)!);
      }
      final sw = Stopwatch()..start();
      final a = e.runBot(e.turn)!;
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(e.legal(e.turn), contains(a['card']));
    });
  });

  test('bots 对打', () {
    expect(runSims(tricksGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
