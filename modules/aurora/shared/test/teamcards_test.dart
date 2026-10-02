import 'dart:math';

import 'package:aurora_shared/games/teamcards/defs.dart';
import 'package:aurora_shared/games/teamcards/guandan.dart';
import 'package:aurora_shared/games/teamcards/guandan_rules.dart';
import 'package:aurora_shared/games/teamcards/shengji.dart';
import 'package:aurora_shared/games/teamcards/shengji_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<String> cs(String s) => s.split(' ');

String? gd(String s, {int level = 2}) => gdPick(cs(s), null, level)?.type;

void main() {
  group('掼蛋牌型', () {
    test('基本牌型', () {
      expect(gd('3S'), 'single');
      expect(gd('5S 5D'), 'pair');
      expect(gd('7S 7D 7C'), 'triple');
      expect(gd('7S 7D 7C 3S 3D'), 'full');
      expect(gd('3S 4D 5C 6S 7H'), 'straight');
      expect(gd('AS 2D 3C 4S 5H', level: 9), 'straight');
      expect(gd('TS JD QC KS AH'), 'straight');
      expect(gd('JS QD KC AS 2H', level: 9), isNull);
      expect(gd('3S 3D 4C 4S 5H 5D'), 'tube');
      expect(gd('3S 3D 3C 4S 4H 4D'), 'plate');
      expect(gd('9S 9D 9C 9H'), 'bomb');
      expect(gd('3S 4S 5S 6S 7S'), 'sf');
      expect(gd('BJ BJ RJ RJ'), 'jokers');
      expect(gd('BJ RJ'), isNull);
      expect(gd('3S 3D 4C 4S'), isNull);
    });

    test('逢人配', () {
      // level 2: 2H is wild
      expect(gd('2H 5S'), 'pair');
      expect(gdPick(cs('2H 5S'), null, 2)!.key, 5);
      expect(gd('2H 3S 4S 6S 7S'), 'sf');
      expect(gd('2H 3S 4D 6S 7S'), 'straight');
      expect(gd('2H 9S 9D 9C'), 'bomb');
      expect(gd('2H 2H 9S 9D 9C 9H'), 'bomb');
      expect(gdPick(cs('2H 2H 9S 9D 9C 9H'), null, 2)!.len, 6);
      expect(gd('2H 7S 7D 3S 3D'), 'full');
      expect(gdPick(cs('2H 7S 7D 3S 3D'), null, 2)!.key, 7);
      expect(gd('2H BJ'), isNull, reason: '王不能配');
      expect(gd('2H 3S 3D 4S 4D 5S'), 'tube');
    });

    test('级牌大于 A，顺子中按原点数', () {
      final l = 7;
      expect(gdValue('7S', l), 15);
      final a = gdPick(cs('7S'), null, l)!;
      final b = gdPick(cs('AS'), null, l)!;
      expect(gdBeats(a, b), isTrue);
      expect(gd('5S 6D 7C 8S 9H', level: l), 'straight');
    });

    test('炸弹大小', () {
      final b4 = gdPick(cs('3S 3D 3C 3H'), null, 2)!;
      final b5 = gdPick(cs('3S 3D 3C 3H 3S'), null, 2)!;
      final sf = gdPick(cs('3S 4S 5S 6S 7S'), null, 2)!;
      final b6 = gdPick(cs('4S 4D 4C 4H 4S 4D'), null, 2)!;
      final jk = gdPick(cs('BJ BJ RJ RJ'), null, 2)!;
      expect(gdBeats(b5, b4), isTrue);
      expect(gdBeats(sf, b5), isTrue);
      expect(gdBeats(b6, sf), isTrue);
      expect(gdBeats(jk, b6), isTrue);
      final st = gdPick(cs('3S 4D 5C 6S 7H'), null, 2)!;
      expect(gdBeats(b4, st), isTrue);
      expect(gdPick(cs('4S 5D 6C 7S 8H'), st, 2)?.type, 'straight');
      expect(gdPick(cs('4S 4D'), st, 2), isNull);
    });

    test('候选出牌', () {
      final hand = cs('2H 5S 5D 9C 9D 9S 3S 4D 6C 7S');
      final c = gdCandidates(hand, null, 2);
      expect(c.any((p) => p.combo.type == 'straight'), isTrue);
      expect(c.any((p) => p.combo.type == 'bomb' && p.combo.key == 9), isTrue);
      expect(c.any((p) => p.combo.type == 'full'), isTrue);
      final t = gdPick(cs('8S 8D'), null, 2)!;
      final f = gdCandidates(hand, t, 2);
      expect(f.every((p) => p.combo.type == 'pair' || p.combo.isBomb), isTrue);
      expect(f.any((p) => p.combo.type == 'pair' && p.combo.key == 9), isTrue);
    });
  });

  group('升级规则', () {
    const t = SjTrump(2, 'S');
    test('主牌判定', () {
      expect(t.isTrump('BJ'), isTrue);
      expect(t.isTrump('2H'), isTrue);
      expect(t.isTrump('5S'), isTrue);
      expect(t.isTrump('5H'), isFalse);
      expect(t.order('2S') > t.order('2H'), isTrue);
      expect(t.order('2H') > t.order('AS'), isTrue);
      expect(t.order('RJ') > t.order('BJ'), isTrue);
    });

    test('拖拉机识别', () {
      final c = sjDecompose(cs('7H 7H 8H 8H'), t);
      expect(c.length, 1);
      expect(c.first.isTractor, isTrue);
      // 级牌 2 跳过：AH AH 3H 3H? no, 3 and A are not adjacent; KH KH AH AH is
      expect(sjDecompose(cs('KH KH AH AH'), t).first.isTractor, isTrue);
      // with level 7, 6 and 8 are adjacent
      const t7 = SjTrump(7, 'S');
      expect(sjDecompose(cs('6H 6H 8H 8H'), t7).first.isTractor, isTrue);
      // trump: 副级牌对 + 主级牌对 相连
      expect(sjDecompose(cs('2H 2H 2S 2S'), t).first.isTractor, isTrue);
      expect(sjDecompose(cs('AS AS 2H 2H'), t).first.isTractor, isTrue);
      expect(sjDecompose(cs('2H 2H 2D 2D'), t).length, 2);
    });

    test('跟牌合法性', () {
      final lead = cs('9H 9H');
      final hand = cs('3H 3H 5H 7C 8C');
      expect(sjFollowError(lead, cs('3H 5H'), hand, t), isNotNull);
      expect(sjFollowError(lead, cs('3H 3H'), hand, t), isNull);
      expect(sjFollowError(lead, cs('7C 8C'), hand, t), isNotNull);
      final hand2 = cs('5H 7C 8C');
      expect(sjFollowError(lead, cs('5H 7C'), hand2, t), isNull);
      expect(sjFollowError(lead, cs('7C 8C'), hand2, t), isNotNull);
      // tractor must be followed by tractor
      final tl = cs('9H 9H TH TH');
      final h3 = cs('3H 3H 4H 4H 6H 6H 8C 8C');
      expect(sjFollowError(tl, cs('3H 3H 6H 6H'), h3, t), isNotNull);
      expect(sjFollowError(tl, cs('3H 3H 4H 4H'), h3, t), isNull);
      final h4 = cs('3H 3H 6H 7H 8C');
      expect(sjFollowError(tl, cs('3H 6H 7H 8C'), h4, t), isNotNull);
      expect(sjFollowError(tl, cs('3H 3H 6H 7H'), h4, t), isNull);
    });

    test('比较与甩牌', () {
      final lead = cs('9H 9H');
      final comps = sjDecompose(lead, t);
      expect(sjPower(cs('JH JH'), comps, 'H', t) > sjPower(lead, comps, 'H', t, isLead: true), isTrue);
      expect(sjPower(cs('JH QH'), comps, 'H', t), -1);
      expect(sjPower(cs('3S 3S'), comps, 'H', t) > sjPower(cs('AH AH'), comps, 'H', t), isTrue);
      final th = cs('AH AH KH');
      final tc = sjDecompose(th, t);
      expect(tc.length, 2);
      expect(sjCompBeatable(tc.last, 'H', cs('3H 4H'), t), isFalse);
      expect(sjCompBeatable(sjDecompose(cs('QH'), t).first, 'H', cs('3H KH'), t), isTrue);
      expect(sjPower(cs('3H 3H 4H'), tc, 'H', t), -1);
    });

    test('点数', () {
      expect(sjPointsOf(cs('5H TS KD 3C')), 25);
    });
  });

  group('v3', () {
    GameSetup setup() => GameSetup(players: 4, options: {}, names: ['a', 'b', 'c', 'd'], bots: List.filled(4, true), rng: Random(4));
    test('placings', () {
      final g = Guandan(setup())..start();
      expect(g.placings, isNull);
      g.phase = 'over';
      g.winnerTeam = 1;
      expect(g.placings, [2, 1, 2, 1]);
      g.winnerTeam = 2;
      expect(g.placings, [1, 1, 1, 1]);
      final s = Shengji(setup())..start();
      expect(s.placings, isNull);
      s.phase = 'over';
      s.winnerTeam = 0;
      expect(s.placings, [1, 2, 1, 2]);
    });

    test('real game placings are team based', () {
      for (final def in teamcardsGames) {
        for (final lvl in [0, 2]) {
          final r = simulate(def, 4, options: {'target': 5, 'cap': 3}, seed: 3, botLevel: lvl);
          expect(r.finished, isTrue, reason: '${def.id} lvl $lvl: ${r.error}');
        }
      }
    });
  });

  test('模拟对局', () {
    expect(runSims(teamcardsGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
