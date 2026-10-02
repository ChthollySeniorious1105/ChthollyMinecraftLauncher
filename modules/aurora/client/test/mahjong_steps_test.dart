import 'dart:math';

import 'package:aurora_client/games/boards.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_client/theme/themes.dart';
import 'package:aurora_client/widgets/common.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders every mahjong board after every single action of a bot game,
/// including the claim-cover pause right after a discard (before the
/// scheduled resume runs). Regression test for the board flashing to an
/// error box for 0.5–1 s after discarding.
void main() {
  late AppState app;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'name': 'tester', 'avatar': 3});
    app = AppState();
    app.prefs = await SharedPreferences.getInstance();
  });

  const ids = ['riichi4', 'riichi3', 'majsoul_anye', 'majsoul_mingjing', 'sichuan', 'hkmj', 'mcr', 'taiwan16'];
  for (final id in ids) {
    testWidgets('every step renders: $id', (tester) async {
      final def = gameRegistry.firstWhere((d) => d.id == id);
      final opts = def.defaultOptions();
      final players = def.playerRange(opts).$1;
      final setup = GameSetup(
          players: players,
          options: opts,
          names: [for (var i = 0; i < players; i++) 'p$i'],
          bots: List.filled(players, true),
          hostSeat: 0,
          rng: Random(3));
      final e = def.create(setup);
      final q = <void Function()>[];
      e.host = _Host(q);
      e.start();
      void run() {
        while (q.isNotEmpty) {
          final l = List.of(q);
          q.clear();
          for (final f in l) {
            f();
          }
        }
      }

      Future<void> render(String when) async {
        final gs = GameState(id, 0, setup.names, setup.bots, List.filled(players, 1), e.view(0), e.isOver);
        await tester.pumpWidget(MaterialApp(
          theme: auroraThemes.first.toThemeData(),
          home: Scaffold(body: SizedBox.expand(child: buildBoard(GameContext(app, gs)))),
        ));
        await tester.pump(const Duration(milliseconds: 16));
        final err = tester.takeException();
        if (err != null) {
          debugPrint('$err\n${err is Error ? err.stackTrace : ''}');
          fail('$id $when (phase ${e.view(0)['phase']}): $err');
        }
      }

      run();
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      var steps = 0;
      while (!e.isOver && steps < 300) {
        await render('step $steps');
        final w = e.waitingFor;
        if (w.isEmpty) {
          if (q.isEmpty) break;
          run();
          continue;
        }
        final a = e.runBot(w.first);
        if (a == null) break;
        e.handle(w.first, a);
        await render('after action $steps'); // may be mid claim-cover pause
        run();
        steps++;
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}

class _Host implements GameHost {
  final List<void Function()> q;
  _Host(this.q);
  @override
  void log(String text) {}
  @override
  void Function() schedule(int ms, void Function() fn) {
    var cancelled = false;
    q.add(() {
      if (!cancelled) fn();
    });
    return () => cancelled = true;
  }
}
