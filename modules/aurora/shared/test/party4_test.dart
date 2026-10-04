import 'dart:math';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:aurora_shared/games/party4/defs.dart';
import 'package:aurora_shared/games/party4/games.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup setup(int n, [Map<String, dynamic> opts = const {}]) => GameSetup(
  players: n,
  options: opts,
  names: List.generate(n, (i) => '玩家$i'),
  bots: List.filled(n, false),
  rng: Random(7),
);
void main() {
  test(
    'all new games finish across player counts, options and bot levels',
    () => expect(runSims(party4Games, n: 30), 0),
    timeout: const Timeout(Duration(minutes: 10)),
  );
  test('memory never reveals unseen cards to players or spectators', () {
    final e = MemoryPairs(setup(2))..start();
    expect((e.view(-1)['cards'] as List).toSet(), {-1});
    e.handle(e.turn, {'cell': 0});
    expect((e.view(1)['cards'] as List).where((x) => x != -1).length, 1);
    expect(() => e.handle(e.turn, {'cell': 0}), throwsA(isA<GameError>()));
  });
  test('invitation round trips without leaking room secrets', () {
    const i = AuroraInvitation(
      'https://play.example.com/',
      'A7K2Q',
      'play.example.com:7788',
    );
    final r = AuroraInvitation.parse('一起玩 ${i.url}')!;
    expect(r.room, i.room);
    expect(r.nativeAddress, i.nativeAddress);
    expect(AuroraInvitation.parse('https://example.com/?room=x'), isNull);
    expect(
      AuroraInvitation.parse('https://user:secret@example.com/?room=A7K2Q'),
      isNull,
    );
  });
  test('discovery filters count, duration, difficulty and cooperation', () {
    final g = findGame('hanabi')!.toJson();
    expect(matchesGame(g, players: 3, mode: 'coop'), isTrue);
    expect(matchesGame(g, players: 12), isFalse);
    expect(matchesGame(g, mode: 'competitive'), isFalse);
  });
}
