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
  test(
    'quiz answers and current scores are private until everyone submits',
    () {
      final e = QuizParty(setup(2))..start();
      e.handle(0, {'answer': e.q.$3});
      expect(e.view(1)['answer'], isNull);
      expect(e.view(-1)['scores'], isNull);
      expect(() => e.handle(0, {'answer': 1}), throwsA(isA<GameError>()));
      e.handle(1, {'answer': 0});
      expect(e.view(-1)['answer'], e.q.$3);
    },
  );
  test('memory never reveals unseen cards to players or spectators', () {
    final e = MemoryPairs(setup(2))..start();
    expect((e.view(-1)['cards'] as List).toSet(), {-1});
    e.handle(e.turn, {'cell': 0});
    expect((e.view(1)['cards'] as List).where((x) => x != -1).length, 1);
    expect(() => e.handle(e.turn, {'cell': 0}), throwsA(isA<GameError>()));
  });
  test('escape room requires collecting clues and spectator cannot act', () {
    final e = EscapeHouse(setup(2))..start();
    expect(() => e.handle(0, {'choice': 0}), throwsA(isA<GameError>()));
    expect(
      () => e.handle(-1, {'type': 'inspect', 'item': 0}),
      throwsA(isA<GameError>()),
    );
    for (var i = 0; i < 3; i++) {
      e.handle(i % 2, {'type': 'inspect', 'item': i});
    }
    e.handle(1, e.bot(1)!);
    expect(e.stage, 1);
    expect(e.inventory.length, 1);
  });
  test('daily puzzles deterministic, private, revision checked, solvable', () {
    for (final kind in dailyKinds.keys) {
      final a = DailyPuzzle(kind, 19), b = DailyPuzzle(kind, 19);
      expect(a.view(), b.view());
      expect(a.view().containsKey('solution'), isFalse);
      expect(a.view().containsKey('mines'), isFalse);
      expect(
        () => a.act({'cell': 0, 'revision': 999}),
        throwsA(isA<GameError>()),
      );
    }
    final p = DailyPuzzle('lights', 3);
    for (final i in LightsOut.solve(p.board, 4)) {
      p.act({'cell': i, 'revision': p.moves});
    }
    expect(p.won, isTrue);
    final sudoku = DailyPuzzle('sudoku', 9);
    for (var i = 0; i < 81; i++) {
      if (sudoku.board[i] == 0)
        sudoku.act({
          'cell': i,
          'digit': sudoku.solution[i],
          'revision': sudoku.moves,
        });
    }
    expect(sudoku.won, isTrue);
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
    final g = findGame('escapehouse')!.toJson();
    expect(matchesGame(g, players: 3, mode: 'coop'), isTrue);
    expect(matchesGame(g, players: 12), isFalse);
    expect(matchesGame(g, mode: 'competitive'), isFalse);
  });
}
