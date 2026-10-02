import 'dart:math';

import 'package:aurora_shared/games/abstract/backgammon.dart';
import 'package:aurora_shared/games/abstract/backgammon_rules.dart';
import 'package:aurora_shared/games/abstract/connect6.dart';
import 'package:aurora_shared/games/abstract/defs.dart';
import 'package:aurora_shared/games/abstract/hex.dart';
import 'package:aurora_shared/games/abstract/mancala.dart';
import 'package:aurora_shared/games/abstract/ninemen.dart';
import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/simulate.dart';
import 'package:test/test.dart';

GameSetup _setup([Map<String, dynamic> opts = const {}, int seed = 1]) => GameSetup(
      players: 2,
      options: opts,
      names: const ['P0', 'P1'],
      bots: const [false, false],
      rng: Random(seed),
    );

BgPos _empty() => BgPos([List.filled(26, 0), List.filled(26, 0)]);

void main() {
  group('backgammon', () {
    test('must use both dice when possible', () {
      // 玩家0：一子在 相对13；另一子在相对 8。对手在 相对(我) 7 和 10 各封 2 子。
      final p = _empty();
      p.c[0][13] = 1;
      p.c[0][2] = 14;
      p.c[1][25 - 7] = 2; // 封住我方 7 点
      // 骰 6-3：13-6=7 被封；13-3=10 再 10-6=4 可行 → 必须两颗都用
      final ms = p.legalNow(0, [6, 3]);
      expect(ms.every((m) => !(m.from == 13 && m.die == 6)), isTrue);
      expect(ms.any((m) => m.from == 13 && m.to == 10), isTrue);
      // 从 2 点用 3 走不出（未全部回家？全在内盘 → 可以移出，但会导致只用一颗）
      for (final m in ms) {
        final q = p.clone()..apply(0, m);
        final rest = List.of([6, 3])..remove(m.die);
        expect(q.legalNow(0, rest), isNotEmpty);
      }
    });

    test('only one die usable -> must use the larger', () {
      final p = _empty();
      p.c[0][24] = 1;
      p.c[0][20] = 14;
      // 封住 18(24-6), 21(24-3)→那么 24 只能走... 设置：骰 5-2
      // 对手封 19(24-5) 以外的所有后续点
      p.c[1][25 - 22] = 2; // 封 22 (24-2)
      p.c[1][25 - 17] = 2; // 封 17 (24-5-2)
      p.c[1][25 - 15] = 2; // 封 15 (20-5)
      p.c[1][25 - 18] = 2; // 封 18 (20-2)
      // 24-5=19 可走，之后 19-2=17 封，20-2=18 封 → 只能用一颗
      // 24-2 被封；20-5=15 封；20-2=18 封 → 仅 5 可用
      final ms = p.legalNow(0, [5, 2]);
      expect(ms, isNotEmpty);
      expect(ms.every((m) => m.die == 5), isTrue);
    });

    test('larger die rule when either but not both', () {
      final p = _empty();
      p.c[0][10] = 1;
      p.c[0][1] = 0;
      // 对手封 4 (10-6) 后只能... 构造：10-6=4 可，10-4=6 可，但 4-4=0? 不在内盘外还有子→不可移出
      p.c[0][20] = 14;
      p.c[1][25 - 14] = 2; // 20-6
      p.c[1][25 - 16] = 2; // 20-4
      p.c[1][25 - 10 + 0] = 0;
      p.c[1][25 - 0 - 6] = 0;
      // 10-6=4 → 4-4 = 0 不能移出（20 还有子）；10-4=6 → 6-6 = 0 同理不可
      // 20 点被封 → 仅能用其中一颗 → 必须用 6
      final ms = p.legalNow(0, [6, 4]);
      expect(ms, isNotEmpty);
      expect(ms.every((m) => m.die == 6), isTrue);
    });

    test('bar entry and hitting', () {
      final p = _empty();
      p.c[0][25] = 1;
      p.c[0][6] = 14;
      p.c[1][25 - 22] = 1; // 对手散子在我的 22 点（我从中柱用 3 进入）
      p.c[1][25 - 20] = 2; // 20 点被封（用5进不来）
      p.c[1][6] = 12;
      final ms = p.legalNow(0, [3, 5]);
      // 中柱有子必须先进入
      expect(ms.every((m) => m.from == 25), isTrue);
      expect(ms.length, 1);
      final m = ms.single;
      expect(m.to, 22);
      expect(m.hit, isTrue);
      p.apply(0, m);
      expect(p.bar(1), 1);
      expect(p.bar(0), 0);
    });

    test('bearing off rules', () {
      final p = _empty();
      p.c[0][5] = 1;
      p.c[0][3] = 1;
      p.c[0][0] = 13;
      // 骰 6：最高点是 5 → 可以用 6 移出 5
      var ms = p.singleMoves(0, 6);
      expect(ms.any((m) => m.from == 5 && m.to == 0), isTrue);
      expect(ms.any((m) => m.from == 3 && m.to == 0), isFalse);
      // 骰 4：3 不能移出（5 更高），只能 5->1
      ms = p.singleMoves(0, 4);
      expect(ms.map((m) => '${m.from}/${m.to}').toSet(), {'5/1'});
      // 外面还有子不能移出
      p.c[0][8] = 1;
      p.c[0][0] = 12;
      ms = p.singleMoves(0, 5);
      expect(ms.any((m) => m.to == 0), isFalse);
    });

    test('gammon / backgammon kinds', () {
      final p = _empty();
      p.c[0][0] = 15;
      p.c[1][10] = 15;
      expect(p.winKind(0), 2);
      p.c[1][10] = 14;
      p.c[1][25] = 1;
      expect(p.winKind(0), 3);
      p.c[1][25] = 0;
      p.c[1][0] = 1;
      expect(p.winKind(0), 1);
    });

    test('engine: drop ends game with cube value', () {
      final e = Backgammon(_setup({'match': 5, 'cube': true, 'crawford': true}));
      e.start();
      // 跑到有人可以加倍
      var guard = 0;
      while (e.phase != 'roll' && guard++ < 50) {
        final a = e.bot(e.turn)!;
        e.handle(e.turn, a['type'] == 'move' || a['type'] == 'confirm' ? a : {'type': 'roll'});
      }
      expect(e.phase, 'roll');
      final t = e.turn;
      e.handle(t, {'type': 'double'});
      expect(e.waitingFor, [1 - t]);
      e.handle(1 - t, {'type': 'drop'});
      expect(e.score[t], 1);
    });
  });

  test('mancala capture and extra turn', () {
    final s = MancalaState(List.filled(14, 0), 0);
    s.pits[0] = 1; // 播到坑1（空）→ 吃对面 11
    s.pits[11] = 5;
    s.pits[5] = 1; // 保证不结束
    s.pits[8] = 1;
    final r = s.play(0);
    expect(r.captured, 6);
    expect(s.pits[6], 6);
    expect(s.pits[11], 0);
    expect(s.turn, 1);
    // 再走一次
    final t = MancalaState(List.filled(14, 0), 0);
    t.pits[4] = 2;
    t.pits[0] = 1;
    t.pits[9] = 1;
    final r2 = t.play(4);
    expect(r2.again, isTrue);
    expect(t.turn, 0);
  });

  test('connect6 two-stone turns', () {
    final e = Connect6(_setup());
    e.start();
    final b = e.blackSeat;
    e.handle(b, {'type': 'play', 'point': 180});
    expect(e.turn, 1 - b);
    e.handle(1 - b, {'type': 'play', 'point': 0});
    expect(e.turn, 1 - b);
    e.handle(1 - b, {'type': 'play', 'point': 1});
    expect(e.turn, b);
    expect(() => e.handle(1 - b, {'type': 'play', 'point': 2}), throwsA(isA<GameError>()));
    // 六连获胜
    for (final p in [181, 182]) {
      e.handle(b, {'type': 'play', 'point': p});
    }
    e.handle(1 - b, {'type': 'play', 'point': 40});
    e.handle(1 - b, {'type': 'play', 'point': 41});
    e.handle(b, {'type': 'play', 'point': 183});
    e.handle(b, {'type': 'play', 'point': 184});
    e.handle(1 - b, {'type': 'play', 'point': 60});
    e.handle(1 - b, {'type': 'play', 'point': 61});
    expect(e.isOver, isFalse);
    e.handle(b, {'type': 'play', 'point': 185});
    expect(e.isOver, isTrue);
    expect(e.winner, b);
  });

  test('hex win detection', () {
    final b = HexBoard(5);
    for (var r = 0; r < 5; r++) {
      b.cells[r * 5 + 2] = 1;
    }
    expect(b.winPath(1), isNotNull);
    expect(b.winPath(2), isNull);
    // 蓝：沿斜线相连 (r, c) -> (r-1, c+1) 相邻
    final c = HexBoard(3);
    c.cells[2 * 3 + 0] = 2;
    c.cells[1 * 3 + 1] = 2;
    c.cells[0 * 3 + 2] = 2;
    expect(c.winPath(2), isNotNull);
    // (0,0)-(1,1) 不相邻
    final d = HexBoard(2);
    d.cells[0] = 2;
    d.cells[3] = 2;
    expect(d.winPath(2), isNull);
  });

  test('hex swap rule', () {
    final e = Hex(_setup({'size': 11, 'swap': true}));
    e.start();
    final red = e.redSeat;
    e.handle(red, {'type': 'play', 'point': 60});
    e.handle(1 - red, {'type': 'swap'});
    expect(e.redSeat, 1 - red);
    expect(e.turn, red);
    expect(e.board.cells[60], 1);
  });

  test('morris mill and removal', () {
    final e = NineMensMorris(_setup());
    e.start();
    final f = e.firstSeat, o = 1 - f;
    e.handle(f, {'type': 'place', 'point': 0});
    e.handle(o, {'type': 'place', 'point': 3});
    e.handle(f, {'type': 'place', 'point': 1});
    e.handle(o, {'type': 'place', 'point': 4});
    e.handle(f, {'type': 'place', 'point': 2});
    expect(e.phaseOf(f), 'remove');
    expect(e.waitingFor, [f]);
    expect(() => e.handle(f, {'type': 'remove', 'point': 0}), throwsA(isA<GameError>()));
    e.handle(f, {'type': 'remove', 'point': 3});
    expect(e.st.cells[3], 0);
    expect(e.st.onBoard[o], 1);
    expect(e.st.turn, o);
  });

  test('morris removal protects mills', () {
    final s = MorrisState(List.filled(24, 0), [5, 5], [0, 0], 0, false, true);
    // 对手(座位1) 三连 0,1,2 + 一个散子 9
    for (final p in [0, 1, 2, 9]) {
      s.cells[p] = 2;
    }
    s.onBoard[1] = 4;
    s.cells[21] = 1;
    s.cells[22] = 1;
    s.onBoard[0] = 2;
    final mill = s.apply(2400 + 23);
    expect(mill, isTrue);
    expect(s.removable(0), [9]);
    s.cells[9] = 0;
    expect(s.removable(0).toSet(), {0, 1, 2});
  });

  group('v3: resign / draw / placings', () {
    GameEngine make(String id, [int seed = 1]) {
      final def = abstractGames.firstWhere((d) => d.id == id);
      final e = def.create(_setup(def.defaultOptions(), seed));
      e.start();
      return e;
    }

    for (final id in ['backgammon', 'mancala', 'connect6', 'hex', 'ninemen']) {
      test('$id resign', () {
        for (final seat in [0, 1]) {
          final e = make(id);
          final logs = <String>[];
          e.host = _LogHost(logs);
          expect(e.placings, isNull);
          expect(e.canResign, isTrue);
          e.resign(seat);
          expect(e.isOver, isTrue);
          expect(e.canResign, isFalse);
          expect(e.placings, seat == 0 ? [2, 1] : [1, 2]);
          expect(logs, contains('P$seat 认输'));
          expect(e.waitingFor, isEmpty);
          expect(() => e.resign(1 - seat), throwsA(isA<GameError>()));
        }
      });
    }

    for (final id in ['mancala', 'connect6', 'hex', 'ninemen']) {
      test('$id agreeDraw', () {
        final e = make(id);
        expect(e.canDraw, isTrue);
        e.agreeDraw();
        expect(e.isOver, isTrue);
        expect(e.canDraw, isFalse);
        expect(e.placings, [1, 1]);
        expect(e.view(0)['result'], isNotNull);
      });
    }

    test('backgammon has no draw, no undo', () {
      final e = make('backgammon');
      expect(e.canDraw, isFalse);
      expect(abstractGames.firstWhere((d) => d.id == 'backgammon').undo, isFalse);
      for (final id in ['mancala', 'connect6', 'hex', 'ninemen']) {
        expect(abstractGames.firstWhere((d) => d.id == id).undo, isTrue);
      }
    });

    test('placings after a natural win', () {
      final e = Connect6(_setup());
      e.start();
      final b = e.blackSeat;
      e.handle(b, {'type': 'play', 'point': 180});
      var o = 0;
      for (var i = 1; i <= 5; i++) {
        e.handle(1 - b, {'type': 'play', 'point': o++});
        e.handle(1 - b, {'type': 'play', 'point': o++ + 40});
        if (i < 5) {
          e.handle(b, {'type': 'play', 'point': 180 + i});
          e.handle(b, {'type': 'play', 'point': 300 + i});
        } else {
          e.handle(b, {'type': 'play', 'point': 185});
        }
      }
      expect(e.isOver, isTrue);
      expect(e.placings, b == 0 ? [1, 2] : [2, 1]);
    });

    test('mancala tie gives both first', () {
      final e = Mancala(_setup({'seeds': 4, 'capture': true}));
      e.start();
      final t = e.st.turn;
      // 构造平局：双方仓各 23，仅当前方最后一坑剩 1 颗，播入己仓后结束
      e.st.pits.fillRange(0, 14, 0);
      e.st.pits[MancalaState.store(t)] = 23;
      e.st.pits[MancalaState.store(1 - t)] = 24;
      e.st.pits[MancalaState.first(t) + 5] = 1;
      e.handle(t, {'type': 'play', 'pit': MancalaState.first(t) + 5});
      expect(e.isOver, isTrue);
      expect(e.placings, [1, 1]);
    });
  });

  test('bots finish all games', () {
    expect(runSims(abstractGames, n: 10), 0);
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _LogHost implements GameHost {
  final List<String> logs;
  _LogHost(this.logs);
  @override
  void log(String text) => logs.add(text);
  @override
  void Function() schedule(int ms, void Function() fn) => () {};
}
