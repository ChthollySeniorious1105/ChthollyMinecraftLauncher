import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/games/cards3/bac_rules.dart';
import 'package:aurora_shared/games/cards3/baccarat.dart';
import 'package:aurora_shared/games/cards3/defs.dart';
import 'package:aurora_shared/games/cards3/gandengyan.dart';
import 'package:aurora_shared/games/cards3/gdy_rules.dart';
import 'package:aurora_shared/games/cards3/gongzhu.dart';
import 'package:aurora_shared/games/cards3/gz_rules.dart';
import 'package:aurora_shared/games/cards3/shed_rules.dart';
import 'package:aurora_shared/games/cards3/wushik.dart';
import 'package:aurora_shared/games/cards3/zhengshangyou.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<String> cs(String s) => s.split(' ');
GdyCombo? lead(String s) => gdyBestLead(cs(s));
GdyCombo? follow(String s, String t) => gdyFollowAs(cs(s), lead(t)!);
const wk = ShedRules(k510: true);
ShedCombo w(String s) => shedClassify(cs(s), wk)!;

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

void main() {
  group('干瞪眼', () {
    test('follow must be exactly one higher', () {
      expect(follow('6S', '5H'), isNotNull);
      expect(follow('7S', '5H'), isNull);
      expect(follow('5S', '5H'), isNull);
      expect(follow('6S 6D', '5H 5C'), isNotNull);
      expect(follow('7S 7D', '5H 5C'), isNull);
      expect(follow('4S 5D 6C', '3H 4C 5D'), isNotNull);
      expect(follow('5S 6D 7C', '3H 4C 5D'), isNull);
      expect(follow('4S 5D 6C 7C', '3H 4C 5D'), isNull); // 张数不同
    });
    test('2 beats any single/pair, not 2 itself or bombs', () {
      expect(follow('2S', 'AH'), isNotNull);
      expect(follow('2S', '3H'), isNotNull);
      expect(follow('2S 2H', '3H 3D'), isNotNull);
      expect(follow('2S', '2H'), isNull);
      expect(follow('3S', '2H'), isNull);
      expect(follow('2S', '5H 5D 5C'), isNull);
      expect(follow('2S 3H 4D', 'AH KD QC'), isNull); // 2 不进顺子
    });
    test('bombs', () {
      expect(follow('3S 3H 3D', 'AH'), isNotNull);
      expect(follow('3S 3H 3D', '2H 2C'), isNotNull);
      expect(follow('4S 4H 4D', '3S 3H 3C'), isNotNull);
      expect(follow('3S 3H 3D 3C', 'KS KH KC'), isNotNull); // 四张大于三张
      expect(follow('KS KH KC', '3S 3H 3D 3C'), isNull);
      expect(follow('BJ RJ', '3S 3H 3D 3C'), isNotNull);
      expect(lead('BJ RJ')!.isRocket, isTrue);
    });
    test('jokers are wild', () {
      expect(follow('6S BJ', '5H 5C')!.type, 'pair');
      expect(follow('RJ', '9H')!.key, 10);
      expect(follow('4S RJ 6C', '3H 4C 5D')!.type, 'straight');
      expect(lead('7S 7H BJ')!.isBomb, isTrue);
      expect(lead('7S RJ')!.type, 'pair');
      expect(lead('3S 5S RJ')!.type, 'straight');
      expect(lead('3S 3H 4D RJ')!.type, 'pairs');
      expect(follow('2S RJ', 'KH KD'), isNotNull);
      expect(lead('3S 9H RJ'), isNull);
    });
    test('engine validation and draw after trick', () {
      final e = Gandengyan(_setup(3, {'rounds': 1}));
      e.start();
      final t = e.turn;
      expect(e.hands[t].length, 6);
      expect(() => e.handle(t, {'type': 'play', 'cards': 'x'}), throwsA(isA<GameError>()));
      expect(() => e.handle(t, {'type': 'play', 'cards': ['ZZ']}), throwsA(isA<GameError>()));
      expect(() => e.handle(t, {'type': 'pass'}), throwsA(isA<GameError>()));
      expect(e.hands[t].length, 6);
      final c = e.hands[t].first;
      e.handle(t, {'type': 'play', 'cards': [c]});
      if (e.phase == 'play') {
        final pile = e.pile.length;
        while (e.turn != t && e.phase == 'play') {
          e.handle(e.turn, {'type': 'pass'});
        }
        expect(e.pile.length, pile - 1);
        expect(e.hands[t].length, 6);
      }
    });
  });

  group('五十K', () {
    test('510K ordering', () {
      final mixed = w('5S TH KD');
      final pureD = w('5D TD KD');
      final pureS = w('5S TS KS');
      final pureH = w('5H TH KH');
      final bomb4 = w('3S 3H 3D 3C');
      expect(mixed.type, 'k510');
      expect(pureD.beats(mixed), isTrue);
      expect(mixed.beats(pureD), isFalse);
      expect(pureS.beats(pureH), isTrue);
      expect(pureH.beats(pureD), isTrue);
      expect(bomb4.beats(pureS), isTrue);
      expect(pureS.beats(bomb4), isFalse);
      expect(mixed.beats(w('2S 2H 2D')), isTrue);
      expect(w('BJ RJ').beats(w('AS AH AD AC')), isTrue);
      expect(w('4S 4H 4D 4C 4S').beats(w('AS AH AD AC')), isTrue);
    });
    test('combo shapes', () {
      expect(w('3S 4H 5D 6C 7S').type, 'straight');
      expect(shedClassify(cs('JS QH KD AC 2S'), wk), isNull);
      expect(w('3S 3H 4D 4C').type, 'pairs');
      expect(w('3S 3H 3D 4C 4S 4H').type, 'plane');
      expect(w('9S 9H').beats(w('8S 8H')), isTrue);
      expect(w('9S 9H').beats(w('8S')), isFalse);
    });
  });

  group('争上游', () {
    test('tribute: 下游 gives best card, 上游 returns one, 下游 leads', () {
      final e = Zhengshangyou(_setup(4, {'rounds': 3}));
      e.start();
      var guard = 0;
      while (e.phase == 'play' && guard++ < 2000) {
        e.handle(e.turn, e.bot(e.turn)!);
      }
      expect(e.phase, 'roundEnd');
      final order = List.of(e.finish);
      for (var s = 0; s < 4; s++) {
        e.handle(s, {'type': 'continue'});
      }
      expect(e.phase, 'tribute');
      expect(e.upSeat, order.first);
      expect(e.downSeat, order.last);
      final up = e.hands[e.upSeat];
      final upLen = up.length;
      expect(up.contains(e.tributeCard), isTrue);
      final down = e.hands[e.downSeat];
      // 下游剩下的牌都不大于贡牌
      final tv = e.tributeCard!;
      expect(down.every((c) => _v(c) <= _v(tv)), isTrue);
      expect(() => e.handle(e.downSeat, {'type': 'return', 'cards': [down.first]}), throwsA(isA<GameError>()));
      expect(() => e.handle(e.upSeat, {'type': 'return', 'cards': [up[0], up[1]]}), throwsA(isA<GameError>()));
      final give = up.first;
      e.handle(e.upSeat, {'type': 'return', 'cards': [give]});
      expect(e.hands[e.downSeat].contains(give), isTrue);
      expect(e.hands[e.upSeat].length, upLen - 1);
      expect(e.phase, 'play');
      expect(e.turn, e.downSeat);
    });
  });

  group('拱猪', () {
    test('scoring cases', () {
      expect(gzScore(cs('QS')), -100);
      expect(gzScore(cs('JD')), 100);
      expect(gzScore(cs('TC')), 50);
      expect(gzScore(cs('AH KH')), -90);
      expect(gzScore(cs('2H 3H 4H')), 0);
      expect(gzScore(cs('5H 6H 7H 8H 9H TH')), -60);
      expect(gzScore(cs('QS TC')), -200);
      expect(gzScore(cs('QS JD')), 0);
      expect(gzScore(cs('JD TC')), 200);
      expect(gzScore(cs('AH QS'), exposed: {'QS'}), -250);
      expect(gzScore(cs('AH'), exposed: {'AH'}), -100);
      expect(gzScore(cs('JD TC'), exposed: {'TC'}), 400);
      expect(gzScore(cs('JD'), exposed: {'JD'}), 200);
      final all = cs('2H 3H 4H 5H 6H 7H 8H 9H TH JH QH KH AH');
      expect(gzScore(all), 200);
      expect(gzScore([...all, 'TC']), 400);
      // 全部红心值合计 -200
      expect(all.fold(0, (a, c) => a + gzHeart(c)), -200);
    });
    test('must follow suit; 2C leads', () {
      final e = Gongzhu(_setup(4, {'expose': false}));
      e.start();
      final l = e.turn;
      expect(e.legal(l), ['2C']);
      final other = e.hands[l].firstWhere((c) => c != '2C');
      expect(() => e.handle(l, {'type': 'play', 'card': other}), throwsA(isA<GameError>()));
      e.handle(l, {'type': 'play', 'card': '2C'});
      final n = e.turn;
      final hasClub = e.hands[n].any((c) => c.endsWith('C'));
      if (hasClub) {
        final off = e.hands[n].where((c) => !c.endsWith('C'));
        if (off.isNotEmpty) {
          expect(() => e.handle(n, {'type': 'play', 'card': off.first}), throwsA(isA<GameError>()));
        }
      }
    });
  });

  group('百家乐', () {
    test('player draws on 0-5, stands on 6-7', () {
      for (var t = 0; t <= 9; t++) {
        expect(bacPlayerDraws(t), t <= 5, reason: 'player $t');
      }
    });
    test('banker drawing table exhaustive', () {
      // rows: banker total 0..7 ; columns: player third card 0..9 ; '-' = player stood
      const table = {
        0: 'DDDDDDDDDD',
        1: 'DDDDDDDDDD',
        2: 'DDDDDDDDDD',
        3: 'DDDDDDDDSD',
        4: 'SSDDDDDDSS',
        5: 'SSSSDDDDSS',
        6: 'SSSSSSDDSS',
        7: 'SSSSSSSSSS',
      };
      for (final e in table.entries) {
        for (var p = 0; p <= 9; p++) {
          expect(bacBankerDraws(e.key, p), e.value[p] == 'D', reason: 'banker ${e.key} player3 $p');
        }
      }
      for (var b = 0; b <= 7; b++) {
        expect(bacBankerDraws(b, null), b <= 5, reason: 'banker $b, player stood');
      }
    });
    test('deal sequence and naturals', () {
      List<String> seq(String s) => cs(s).reversed.toList();
      String Function() drawer(List<String> l) => () => l.removeLast();
      // P: 2,3 =5 draws 4 -> 9 ; B: K,5 = 5, player third 4 -> draws 7 -> 2
      var c = bacDeal(drawer(seq('2S KS 3H 5D 4C 7H')));
      expect(c.player, cs('2S 3H 4C'));
      expect(c.banker, cs('KS 5D 7H'));
      expect(c.winner, 'P');
      // natural 8 stops everything
      c = bacDeal(drawer(seq('8S 2S KH 2D 9C')));
      expect(c.player.length, 2);
      expect(c.banker.length, 2);
      // player stands on 6, banker 5 draws
      c = bacDeal(drawer(seq('3S KS 3H 5D 2C')));
      expect(c.player.length, 2);
      expect(c.banker, cs('KS 5D 2C'));
      expect(c.b, 7);
    });
    test('payouts', () {
      final bw = const BacCoup(['KS', '2S'], ['9S', 'KH']);
      expect(bacPayout('B', 100, bw), 95);
      expect(bacPayout('P', 100, bw), -100);
      final tie = const BacCoup(['4S', '4H'], ['8S', 'KH']);
      expect(bacPayout('B', 100, tie), 0);
      expect(bacPayout('P', 100, tie), 0);
      expect(bacPayout('T', 100, tie), 800);
      expect(bacPayout('PP', 100, tie), 1100);
      expect(bacPayout('BP', 100, tie), -100);
    });
  });

  group('v3', () {
    void playOut(GameEngine e, {int guard = 200000}) {
      final host = SimHost();
      e.host = host;
      e.start();
      host.runPending();
      var g = 0;
      while (!e.isOver && g++ < guard) {
        var acted = false;
        for (final s in e.waitingFor) {
          final a = e.runBot(s);
          if (a != null) {
            e.handle(s, a);
            acted = true;
            break;
          }
        }
        if (!host.runPending() && !acted) fail('stuck');
      }
      expect(e.isOver, isTrue);
    }

    test('rules present', () {
      for (final d in cards3Games) {
        expect(d.rules.length, greaterThan(300), reason: d.id);
        expect(d.undo, isFalse);
      }
    });

    test('placings null before over', () {
      for (final d in cards3Games) {
        final n = d.defaultOptionsRange().$1 < 4 && d.id == 'wushik' ? 4 : d.defaultOptionsRange().$1;
        final e = d.create(_setup(n, d.defaultOptions()));
        e.start();
        expect(e.placings, isNull, reason: d.id);
      }
    });

    test('gandengyan placings by score', () {
      final e = Gandengyan(_setup(3, {'rounds': 3}));
      playOut(e);
      expect(e.placings, rankByScore(e.scores));
      expect(e.placings!.contains(1), isTrue);
    });

    test('gandengyan resign (2 players only)', () {
      final e3 = Gandengyan(_setup(3, {'rounds': 3}))..start();
      expect(e3.canResign, isFalse);
      final e = Gandengyan(_setup(2, {'rounds': 3}));
      final host = SimHost();
      e.host = host;
      e.start();
      expect(e.canResign, isTrue);
      e.resign(0);
      expect(e.isOver, isTrue);
      expect(e.placings, [2, 1]);
      expect(e.canResign, isFalse);
      expect(host.logs.last, contains('认输'));
      expect(e.view(1)['result'], isNotNull);
      expect(() => e.resign(1), throwsA(isA<GameError>()));
    });

    test('wushik team placings: winners 1, losers 2', () {
      final e = Wushik(_setup(4, {'mode': 'team', 'rounds': 1}));
      playOut(e);
      final p = e.placings!;
      expect(p[0], p[2]);
      expect(p[1], p[3]);
      if (e.scores[0] == e.scores[1]) {
        expect(p, [1, 1, 1, 1]);
      } else {
        expect(p[e.scores[0] > e.scores[1] ? 0 : 1], 1);
        expect(p[e.scores[0] > e.scores[1] ? 1 : 0], 2);
      }
    });

    test('wushik free placings by score', () {
      final e = Wushik(_setup(3, {'mode': 'free', 'rounds': 1}));
      playOut(e);
      expect(e.placings, rankByScore(e.scores));
    });

    test('zhengshangyou placings by score', () {
      final e = Zhengshangyou(_setup(4, {'rounds': 3}));
      playOut(e);
      expect(e.placings, rankByScore(e.scores));
    });

    test('gongzhu placings: higher score is better', () {
      final e = Gongzhu(_setup(4, {'limit': 500}));
      playOut(e);
      final p = e.placings!;
      final best = [0, 1, 2, 3].reduce((a, b) => e.scores[a] >= e.scores[b] ? a : b);
      final worst = [0, 1, 2, 3].reduce((a, b) => e.scores[a] <= e.scores[b] ? a : b);
      expect(p[best], 1);
      expect(e.scores[worst], lessThanOrEqualTo(-500));
      expect(p[worst], greaterThan(1));
    });

    test('baccarat placings by chips; hard bot bets banker only', () {
      final e = Baccarat(GameSetup(
          players: 3, options: {'rounds': 10, 'pairs': true}, names: ['a', 'b', 'c'], bots: [true, true, true],
          rng: Random(3), botLevel: 2));
      e.host = SimHost();
      e.start();
      final a = e.runBot(0)!;
      expect(a['type'], 'bet');
      expect((a['bets'] as Map).keys, ['B']);
      playOut(Baccarat(_setup(3, {'rounds': 10, 'pairs': true})));
      final b = Baccarat(_setup(3, {'rounds': 10, 'pairs': true}));
      playOut(b);
      expect(b.placings, rankByScore(b.chips));
    });

    test('bot() does not mutate state (all levels)', () {
      for (final lvl in [0, 1, 2]) {
        for (final d in cards3Games) {
          final n = d.id == 'wushik' || d.id == 'gongzhu' ? 4 : 3;
          final e = d.create(GameSetup(
              players: n, options: d.defaultOptions(), names: [for (var i = 0; i < n; i++) 'P$i'],
              bots: List.filled(n, true), rng: Random(5), botLevel: lvl));
          e.host = SimHost();
          e.start();
          for (var k = 0; k < 30 && !e.isOver; k++) {
            final w = e.waitingFor;
            if (w.isEmpty) break;
            final before = [for (var s = -1; s < n; s++) jsonEncode(e.view(s))];
            final a = e.runBot(w.first);
            expect([for (var s = -1; s < n; s++) jsonEncode(e.view(s))], before, reason: '${d.id} lvl $lvl');
            if (a == null) break;
            e.handle(w.first, a);
          }
        }
      }
    });
  });

  test('bot simulations', () {
    claimCoverEnabled = false;
    expect(runSims(cards3Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

int _v(String c) {
  if (c == 'BJ') return 16;
  if (c == 'RJ') return 17;
  return '3456789TJQKA2'.indexOf(c[0]) + 3;
}
