import 'dart:math';

import 'package:aurora_shared/games/cncards/bigtwo.dart';
import 'package:aurora_shared/games/cncards/bigtwo_rules.dart';
import 'package:aurora_shared/games/cncards/defs.dart';
import 'package:aurora_shared/games/cncards/douniu.dart';
import 'package:aurora_shared/games/cncards/douniu_rules.dart';
import 'package:aurora_shared/games/cncards/shisanshui.dart';
import 'package:aurora_shared/games/cncards/ssz_rules.dart';
import 'package:aurora_shared/games/cncards/zhajinhua.dart';
import 'package:aurora_shared/games/cncards/zjh_rules.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<String> cs(String s) => s.split(' ');
B2Combo b2(String s) => b2Classify(cs(s))!;
int ss(String s) => ssEval(cs(s));

GameSetup _setup(int n, Map<String, dynamic> opts, {int seed = 1}) => GameSetup(
      players: n,
      options: opts,
      names: [for (var i = 0; i < n; i++) 'P$i'],
      bots: List.filled(n, true),
      rng: Random(seed),
    );

void main() {
  group('锄大地', () {
    test('singles and pairs by rank then suit', () {
      expect(b2('2D').beats(b2('AS')), isTrue);
      expect(b2('3S').beats(b2('3H')), isTrue);
      expect(b2('3H').beats(b2('3C')), isTrue);
      expect(b2('3C').beats(b2('3D')), isTrue);
      expect(b2('KS KD').beats(b2('KH KC')), isTrue);
      expect(b2('3S 3D').beats(b2('KH KC')), isFalse);
      expect(b2Classify(cs('3S 4S')), isNull);
      expect(b2('5D 5C 5H').beats(b2('4S 4H 4C')), isTrue);
    });
    test('five-card hand order', () {
      final straight = b2('3D 4C 5H 6S 7D');
      final flush = b2('3H 5H 8H JH KH');
      final full = b2('4D 4C 4H 3S 3D');
      final quads = b2('5D 5C 5H 5S 3D');
      final sf = b2('3C 4C 5C 6C 7C');
      expect(straight.label, '顺子');
      expect(flush.label, '同花');
      expect(full.label, '葫芦');
      expect(quads.label, '铁支');
      expect(sf.label, '同花顺');
      final order = [straight, flush, full, quads, sf];
      for (var i = 0; i + 1 < order.length; i++) {
        expect(order[i + 1].beats(order[i]), isTrue, reason: '${order[i + 1].label} > ${order[i].label}');
      }
      expect(b2('8D 9C TH JS QD').beats(straight), isTrue);
      expect(b2('3S 4C 5H 6S 7S').beats(straight), isTrue); // 同点比最大牌花色
      expect(b2('4D 4C 4H 3S 3D').beats(b2('3D 3C 3H AS AD')), isTrue);
      expect(b2('3D 4C 5H 6S 7D').beats(b2('3S 3H')), isFalse); // 张数不同
      expect(b2Classify(cs('3D 4C 5H 6S 8D')), isNull);
    });
    test('first play must include ♦3', () {
      final g = BigTwo(_setup(4, {}))..start();
      expect(g.mustInclude, '3D');
      final s = g.turn;
      final other = g.hands[s].firstWhere((c) => c != '3D');
      expect(() => g.handle(s, {'type': 'play', 'cards': [other]}), throwsA(isA<GameError>()));
      expect(() => g.handle(s, {'type': 'pass'}), throwsA(isA<GameError>()));
      g.handle(s, {'type': 'play', 'cards': ['3D']});
      expect(g.hands[s].contains('3D'), isFalse);
    });
    test('multipliers', () {
      expect(BigTwo.mult(13, true), 3);
      expect(BigTwo.mult(10, true), 2);
      expect(BigTwo.mult(9, true), 1);
      expect(BigTwo.mult(13, false), 1);
    });
  });

  group('炸金花', () {
    int c(String a, String b, {bool r235 = false}) => zjhCompare(cs(a), cs(b), rule235: r235);
    test('categories', () {
      expect(zjhName(zjhEval(cs('AS AH AD'))), '豹子');
      expect(zjhName(zjhEval(cs('QH JH TH'))), '顺金');
      expect(zjhName(zjhEval(cs('2H 7H TH'))), '金花');
      expect(zjhName(zjhEval(cs('QH JS TH'))), '顺子');
      expect(zjhName(zjhEval(cs('QH QS 3H'))), '对子');
      expect(zjhName(zjhEval(cs('QH 9S 3H'))), '散牌');
    });
    test('ordering', () {
      expect(c('2S 2H 2D', 'AH KH QH'), greaterThan(0));
      expect(c('3H 4H 5H', '2H 7H TH'), greaterThan(0));
      expect(c('2H 7H TH', 'AS KH QD'), greaterThan(0));
      expect(c('4S 3H 5D', 'AS AH KD'), greaterThan(0));
      expect(c('AS AH 3D', 'KS KH QD'), greaterThan(0));
      expect(c('KS KH AD', 'KD KC QD'), greaterThan(0));
      expect(c('AS KH JD', 'AD KC TD'), greaterThan(0));
      expect(c('AS 2H 3D', '2S 3H 4D'), lessThan(0)); // A23 最小顺子
      expect(c('AS KH QD', 'KS QH JD'), greaterThan(0));
      expect(c('AS KH 9D', 'AH KD 9C'), 0);
    });
    test('235 beats 豹子 only when enabled', () {
      expect(zjhIs235(cs('2S 3H 5D')), isTrue);
      expect(zjhIs235(cs('2S 3S 5S')), isFalse);
      expect(c('2S 3H 5D', 'AS AH AD'), lessThan(0));
      expect(c('2S 3H 5D', 'AS AH AD', r235: true), greaterThan(0));
      expect(c('AS AH AD', '2S 3H 5D', r235: true), lessThan(0));
      expect(c('2S 3H 5D', '2D 4H 6D', r235: true), lessThan(0));
      expect(c('2S 3S 5S', 'AS AH AD', r235: true), lessThan(0));
    });
    test('views hide unseen cards', () {
      final g = Zhajinhua(_setup(3, {}))..start();
      final v = g.view(0);
      for (final h in v['cards'] as List) {
        expect((h as List).every((x) => x == 'back'), isTrue);
      }
      g.handle(0, {'type': 'look'});
      final v2 = g.view(0);
      expect((v2['cards'] as List)[0], g.cards[0]);
      expect(((v2['cards'] as List)[1] as List).every((x) => x == 'back'), isTrue);
    });
  });

  group('斗牛', () {
    DnResult e(String s, {bool sp = true}) => dnEval(cs(s), specials: sp);
    test('niu calculation', () {
      expect(e('TS JH 5D 3C 2S').level, 10); // 10+10+(5+3+2)=牛牛
      expect(e('KS QH 7D 3C 2S').level, 2); // K+7+3=20, Q+2 → 牛二
      expect(e('AS 2H 7D 5C 9S').level, 4); // A+2+7=10, 5+9=14 → 牛四
      expect(e('2S 3H 4D 7C 7S').level, 0); // 没牛
      expect(e('8S 8H 4D 6C 2S').level, 8); // 8+8+4=20, 6+2=8
      expect(e('AS AH AD AC 6S').level, 12); // 炸弹牛
      expect(e('AS AH AD AC 6S', sp: false).level, 0);
      expect(e('JS QH KD JC QS').level, 11); // 五花牛
      expect(e('JS QH KD JC QS', sp: false).level, 10);
      expect(e('AS AH 2D 2C 3S').level, 13); // 五小牛 sum 9
    });
    test('compare and payout', () {
      expect(dnCompare(e('TS JH 5D 3C 2S'), e('8S 8H 4D 6C 2S')), greaterThan(0));
      // same level → higher top card wins (K > Q)
      expect(dnCompare(e('KS 5H 5D 3C 2S'), e('QS 5C 5S 3D 2D')), greaterThan(0));
      expect(dnMult(10, 'std'), 3);
      expect(dnMult(7, 'std'), 2);
      expect(dnMult(6, 'std'), 1);
      expect(dnMult(13, 'std'), 6);
      expect(dnMult(8, 'high'), 8);
      expect(dnMult(10, 'high'), 10);
    });
  });

  group('十三水', () {
    test('lane evaluation', () {
      expect(ssName(ss('AS AH AD')), '三条');
      expect(ssName(ss('AS AH KD')), '对子');
      expect(ssName(ss('AS 3H KD')), '乌龙');
      expect(ssName(ss('AS 2H 3D 4C 5S')), '顺子');
      expect(ssName(ss('AS KS 3S 4S 9S')), '同花');
      expect(ssName(ss('9S 9H 9D 4C 4S')), '葫芦');
      expect(ssName(ss('9S 9H 9D 9C 4S')), '铁支');
      expect(ssName(ss('9S TS JS QS KS')), '同花顺');
      expect(ssName(ss('9S 9H 4D 4C AS')), '两对');
      // 3-card 三条 vs 5-card 三条 comparable
      expect(ss('AS AH AD') > ss('KS KH KD 2C 3S'), isTrue);
      expect(ss('9S 9H 4D 4C 2S') > ss('9D 9C 3D 3C AS'), isTrue);
    });
    test('validity (倒水)', () {
      expect(ssValid(cs('2S 3H 5D'), cs('7S 7H 9D JC KS'), cs('AS AH AD 4C 4S')), isTrue);
      expect(ssValid(cs('QS QH 5D'), cs('7S 7H 9D JC KS'), cs('AS AH AD 4C 4S')), isFalse);
      expect(ssValid(cs('2S 3H 5D'), cs('AS AH AD 4C 4S'), cs('7S 7H 9D JC KS')), isFalse);
    });
    test('lane values', () {
      expect(ssLaneValue(0, ss('AS AH AD')), 3);
      expect(ssLaneValue(1, ss('9S 9H 9D 4C 4S')), 2);
      expect(ssLaneValue(1, ss('9S 9H 9D 9C 4S')), 8);
      expect(ssLaneValue(2, ss('9S 9H 9D 9C 4S')), 4);
      expect(ssLaneValue(2, ss('9S TS JS QS KS')), 5);
      expect(ssLaneValue(2, ss('9S 9H 9D 4C 4S')), 1);
    });
    test('pair scoring and 打枪', () {
      final a = [ss('QS QH 5D'), ss('7S 7H 7D JC KS'), ss('AS AH AD 4C 4S')];
      final b = [ss('2S 3H 5C'), ss('6S 6H 9D JD KD'), ss('KC KH 8D 4D 3S')];
      final r = ssComparePair(a, b, aFoul: false, bFoul: false);
      expect(r.lanes, [1, 1, 1]);
      expect(r.sweep, isTrue);
      expect(r.total, 6); // 打枪翻倍
      final c = [ss('2S 3H 5C'), ss('6S 6H 9D JD KD'), ss('9S 9H 9D 9C 4S')];
      final r2 = ssComparePair(a, c, aFoul: false, bFoul: false);
      expect(r2.lanes, [1, 1, -4]);
      expect(r2.sweep, isFalse);
      expect(r2.total, -2);
      final foul = ssComparePair(a, c, aFoul: false, bFoul: true);
      expect(foul.total, 6);
    });
    test('specials', () {
      expect(ssSpecial(cs('AS 2H 3D 4C 5S 6H 7D 8C 9S TH JD QC KS'))?.name, '一条龙');
      expect(ssSpecial(cs('AS AH 3D 3C 5S 5H 7D 7C 9S 9H JD JC KS'))?.name, '六对半');
      expect(ssSpecial(cs('AS 2S 3S 4H 5H 6H 7H 8H 9D TD JD QD 9C')), isNull);
      expect(ssSpecial(cs('AS 2S 3S 4H 5H 6H 7H 9H 9D TD JD QD KD'))?.name, '三同花');
    });
    test('best arrangement is valid', () {
      final rng = Random(3);
      for (var i = 0; i < 10; i++) {
        final deck = [for (final r in '23456789TJQKA'.split('')) for (final s in 'SHDC'.split('')) '$r$s']..shuffle(rng);
        final h = deck.sublist(0, 13);
        final a = ssBestArrangement(h);
        expect(ssValid(a.front, a.mid, a.back), isTrue);
        expect({...a.front, ...a.mid, ...a.back}.length, 13);
      }
    });
    test('engine rejects 倒水 and settles', () {
      final g = Shisanshui(_setup(3, {'rounds': 1}))..start();
      g.hands[0] = cs('AS AH AD 4C 4S 7S 7H 9D JC KS 2S 3H 5D');
      expect(
          () => g.handle(0, {'type': 'arrange', 'front': cs('AS AH AD'), 'mid': cs('7S 7H 9D JC KS'), 'back': cs('4C 4S 2S 3H 5D')}),
          throwsA(isA<GameError>()));
      for (var s = 0; s < 3; s++) {
        g.handle(s, g.bot(s)!);
      }
      expect(g.isOver, isTrue);
      final d = (g.result!['delta'] as List).cast<int>();
      expect(d.fold(0, (x, y) => x + y), 0);
    });
  });

  group('v3', () {
    test('rules present', () {
      for (final d in cncardsGames) {
        expect(d.rules.length, greaterThan(300), reason: d.id);
      }
    });

    test('resign (2 players only) + placings', () {
      final engines = <GameEngine Function(GameSetup)>[BigTwo.new, Zhajinhua.new, Douniu.new, Shisanshui.new];
      for (final mk in engines) {
        final g = mk(_setup(2, {}))..start();
        expect(g.placings, isNull);
        expect(g.canResign, isTrue);
        g.resign(0);
        expect(g.isOver, isTrue);
        expect(g.placings, [2, 1]);
        expect(g.canResign, isFalse);
        expect(() => g.resign(1), throwsA(isA<GameError>()));
        final g3 = mk(_setup(3, {}))..start();
        expect(g3.canResign, isFalse);
      }
    });

    test('bigtwo placings by score with ties', () {
      final g = BigTwo(_setup(3, {'rounds': 1}))..start();
      final w = g.turn;
      g.hands[w] = [g.mustInclude!];
      final others = [for (var s = 0; s < 3; s++) if (s != w) s];
      g.hands[others[0]] = ['4D', '5D'];
      g.hands[others[1]] = ['4C', '5C'];
      g.handle(w, {'type': 'play', 'cards': [g.mustInclude!]});
      expect(g.isOver, isTrue);
      final p = g.placings!;
      expect(p[w], 1);
      expect(p[others[0]], 2);
      expect(p[others[1]], 2);
    });

    test('zhajinhua placings by chips', () {
      final g = Zhajinhua(_setup(3, {'hands': 5}))..start();
      g.phase = 'over';
      g.chips = [500, 1500, 1000];
      expect(g.placings, [3, 1, 2]);
    });

    test('shisanshui / douniu placings by score', () {
      final g = Shisanshui(_setup(3, {'rounds': 1}))..start();
      for (var s = 0; s < 3; s++) {
        g.handle(s, g.bot(s)!);
      }
      expect(g.isOver, isTrue);
      expect(g.placings, rankByScore(g.scores));
      final d = Douniu(_setup(4, {'hands': 5}))..start();
      d.phase = 'over';
      d.scores = [3, -5, 3, -1];
      expect(d.placings, [1, 4, 1, 3]);
    });

    test('bots at every level do not mutate state', () {
      for (final lvl in [0, 1, 2]) {
        final g = BigTwo(GameSetup(players: 4, options: {}, names: ['a', 'b', 'c', 'd'], bots: List.filled(4, true), rng: Random(5), botLevel: lvl))
          ..start();
        final before = g.view(g.turn).toString();
        final a = g.runBot(g.turn);
        expect(a, isNotNull);
        expect(g.view(g.turn).toString(), before);
      }
    });

    test('bigtwo hard bot is fast', () {
      final g = BigTwo(GameSetup(players: 4, options: {}, names: ['a', 'b', 'c', 'd'], bots: List.filled(4, true), rng: Random(9), botLevel: 2))
        ..start();
      final sw = Stopwatch()..start();
      g.runBot(g.turn);
      expect(sw.elapsedMilliseconds, lessThan(1500));
    });

    test('shisanshui arrangement levels are valid', () {
      final rng = Random(4);
      for (var i = 0; i < 5; i++) {
        final deck = [for (final r in '23456789TJQKA'.split('')) for (final s in 'SHDC'.split('')) '$r$s']..shuffle(rng);
        final h = deck.sublist(0, 13);
        for (final lvl in [0, 2]) {
          final a = ssBestArrangement(h, level: lvl, rng: rng);
          expect(ssValid(a.front, a.mid, a.back), isTrue);
          expect({...a.front, ...a.mid, ...a.back}.length, 13);
        }
      }
    });
  });

  test('simulate all', () {
    expect(runSims(cncardsGames, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
