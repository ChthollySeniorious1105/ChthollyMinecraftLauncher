import 'package:aurora_client/games/uno/rummikub_board.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_client/theme/themes.dart';
import 'package:aurora_client/widgets/common.dart';
import 'package:aurora_shared/games/uno/rummikub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

int _t(int color, int number) => color * 13 + number - 1;

/// A human player arranging tiles on the 拉密 board must be able to submit.
void main() {
  // Regression: dropping the 3rd tile of a group (红10 蓝10 黄10) made the set
  // valid as-is, rkNormalize returned the same list, and `..clear()..addAll(n)`
  // emptied it — the whole group vanished from the table.
  for (final mode in ['tap-box', 'tap-tile', 'drag']) {
    for (final melded in [true, false]) {
      testWidgets('build a same-number group from the rack via $mode (melded=$melded)', (tester) async {
        SharedPreferences.setMockInitialValues({'name': 'tester', 'avatar': 3});
        final app = AppState();
        app.prefs = await tester.runAsync(SharedPreferences.getInstance) as SharedPreferences;
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final r10 = _t(0, 10), b10 = _t(1, 10), y10 = _t(2, 10);
        final run = [_t(3, 1), _t(3, 2), _t(3, 3)];
        final view = <String, dynamic>{
          'table': [run],
          'rack': [r10, b10, y10, _t(0, 2), _t(1, 5)],
          'counts': [5, 9],
          'melded': [melded, true],
          'wall': 50,
          'turn': 0,
          'last': '',
          'lastAdded': <int>[],
          'over': false,
          'winner': -1,
          'scores': <int>[],
        };
        final sent = <Map<String, dynamic>>[];
        final gs = GameState('rummikub', 0, ['我', '电脑'], [false, true], [1, 2], view, false);
        await tester.pumpWidget(MaterialApp(
          theme: auroraThemes.first.toThemeData(),
          home: Scaffold(body: SizedBox.expand(child: RummikubBoard(GameContext(app, gs, actionOverride: sent.add)))),
        ));
        await tester.pump();

        Finder movable(int id) => find.byWidgetPredicate((w) => w is RummiTile && w.id == id && w.onTap != null).last;
        Finder anchor() => find.byWidgetPredicate((w) => w is RummiTile && w.id == r10).first;
        final newSet = find.text('+ 新组合');

        Future<void> place(int id, {required bool first}) async {
          if (mode == 'drag') {
            final from = tester.getCenter(movable(id));
            final to = first ? tester.getCenter(newSet) : tester.getCenter(anchor());
            await tester.dragFrom(from, to - from);
          } else {
            await tester.tap(movable(id));
            await tester.pump();
            if (first) {
              await tester.tap(newSet);
            } else if (mode == 'tap-tile') {
              await tester.tap(anchor());
            } else {
              final rect = tester.getRect(anchor());
              await tester.tapAt(Offset(rect.left - 3, rect.center.dy)); // set box padding
            }
          }
          await tester.pumpAndSettle();
        }

        await place(r10, first: true);
        await place(b10, first: false);
        await place(y10, first: false);

        final submit = find.widgetWithText(FilledButton, '确认出牌');
        expect(tester.widget<FilledButton>(submit).onPressed, isNotNull, reason: '确认出牌 should be enabled');
        await tester.tap(submit);
        await tester.pump();

        expect(sent, hasLength(1));
        final table = [for (final s in sent.single['table'] as List) (s as List).cast<int>()];
        expect(table, hasLength(2));
        expect(table.every(rkValid), isTrue);
        expect(table.firstWhere((s) => s.contains(r10)).toSet(), {r10, b10, y10});
      });
    }
  }
}
