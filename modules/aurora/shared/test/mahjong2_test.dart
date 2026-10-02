import 'package:aurora_shared/games/mahjong2/cs_rules.dart';
import 'package:aurora_shared/games/mahjong2/defs.dart';
import 'package:aurora_shared/games/mahjong2/ep_fans.dart';
import 'package:aurora_shared/games/mahjong2/tiles.dart';
import 'package:aurora_shared/src/engine.dart' show claimCoverEnabled;
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

List<int> h(String s) => countsOf(parseTiles(s));

CsResult? cs(String s, [List<Meld> melds = const [], CsCtx ctx = const CsCtx()]) => csEvaluate(h(s), melds, ctx);
List<String> csNames(CsResult r) => [for (final (n, _) in r.big) n];

EpResult? ep(String s, String win, {List<Meld> melds = const [], bool tsumo = false, int wc = 2}) =>
    evaluate2p(h(s), melds, EpCtx(parseTiles(win).first, selfDrawn: tsumo, waitCount: wc));
List<String> epNames(EpResult r) => [for (final (n, _, _) in r.items) n];

void main() {
  claimCoverEnabled = false;

  group('长沙 胡牌', () {
    test('小胡 needs 2-5-8 将', () {
      expect(cs('123m456m789p234s55s'), isNotNull);
      expect(cs('123m456m789p234s55s')!.isBig, isFalse);
      expect(cs('123m456m789p234s11s'), isNull);
      expect(cs('123m456m789p234s33p'), isNull);
    });
    test('碰碰胡 / 清一色 without 258 将', () {
      expect(csNames(cs('111m333m777p999s11s')!), ['碰碰胡']);
      expect(csNames(cs('11123456789999m')!), contains('清一色'));
      expect(cs('11123456789999m')!.bigCount, 1);
    });
    test('将将胡 any shape', () {
      final r = cs('22m55m88m222p555p88s')!;
      expect(csNames(r), contains('将将胡'));
    });
    test('七小对 / 豪华七小对', () {
      expect(csNames(cs('113355m7799p1133s')!), ['七小对']);
      expect(csNames(cs('111155m7799p1133s')!), ['豪华七小对']);
      expect(cs('111155m7799p1133s')!.bigCount, 2);
    });
    test('situational 大胡 allow non-258 pair', () {
      expect(cs('123m456m789p234s11s', const [], const CsCtx(selfDrawn: true, haidi: true)), isNotNull);
      expect(csNames(cs('123m456m789p234s11s', const [], const CsCtx(kaiGang: true, selfDrawn: true))!), ['杠上开花']);
    });
    test('全求人', () {
      final melds = [
        Meld('peng', parseTiles('1m').first, claimed: 0, from: 1),
        Meld('chi', parseTiles('3p').first, claimed: 9, from: 1),
        Meld('peng', parseTiles('9s').first, claimed: 26, from: 2),
        Meld('peng', parseTiles('7m').first, claimed: 6, from: 3),
      ];
      final r = cs('55s', melds)!;
      expect(csNames(r), contains('全求人'));
    });
    test('起手胡', () {
      final q = csQishou(h('1111m34679p13s79s'));
      final names = [for (final (n, _) in q) n];
      expect(names, containsAll(['大四喜', '板板胡']));
      expect([for (final (n, _) in csQishou(h('111m222m33345m666m'))) n], containsAll(['缺一色', '六六顺']));
      expect(csQishou(h('123m456p789s2255m8p')), isEmpty);
    });
  });

  group('二人 番种', () {
    test('大三元', () {
      final r = ep('555666777z123m99m', '9m')!;
      expect(epNames(r), contains('大三元'));
      expect(r.base, greaterThanOrEqualTo(88));
      expect(epNames(r), isNot(contains('箭刻')));
    });
    test('清一色 七对', () {
      final r = ep('11335577992244m', '4m')!;
      expect(epNames(r), anyOf(contains('七对'), contains('连七对')));
      final r2 = ep('11223344556677m', '7m')!;
      expect(epNames(r2), contains('连七对'));
    });
    test('混一色 + 碰碰和', () {
      final r = ep('111m333m555z666z99m', '6z')!;
      expect(epNames(r), containsAll(['混一色', '碰碰和', '双箭刻', '三暗刻']));
      // winning on the pair keeps all four pungs concealed -> 四暗刻 (no 碰碰和)
      final r4 = ep('111m333m555z666z99m', '9m')!;
      expect(epNames(r4), contains('四暗刻'));
      expect(epNames(r4), isNot(contains('碰碰和')));
    });
    test('plain chow hand is below 8 番', () {
      final r = ep('123m456m789m234m11z', '1z')!;
      // 清龙 16 + 混一色 6 ...
      expect(epNames(r), contains('清龙'));
      final r2 = ep('123m345m456m678m11z', '1z')!;
      expect(epNames(r2), containsAll(['混一色', '门前清', '连六']));
      expect(r2.base, 9);
      final r3 = ep('123m345m678m11z', '1z', melds: [Meld('chi', 3, claimed: 3, from: 1)])!;
      expect(r3.base, lessThan(8));
    });
    test('不是和牌', () {
      expect(ep('123m456m789m234m12z', '2z'), isNull);
    });
  });

  test('sims', () {
    expect(runSims(mahjong2Games, n: 30), 0);
  }, timeout: const Timeout(Duration(minutes: 30)));
}
