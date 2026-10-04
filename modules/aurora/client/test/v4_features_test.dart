import 'package:aurora_client/main.dart';
import 'package:aurora_client/net/connection.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_client/theme/themes.dart';
import 'package:aurora_client/widgets/game_picker.dart';
import 'package:aurora_client/widgets/invite_dialog.dart';
import 'package:aurora_client/widgets/party_panel.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState app;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'name': '简体中文玩家', 'avatar': 1});
    app = AppState();
    await app.load();
    app.games = gameRegistry.map((g) => g.toJson()).toList();
    app.state = ConnState.connected;
    app.address = 'example.com:7788';
    app.publicWebUrl = 'https://example.com/';
    app.myId = 1;
    app.room = {
      'id': 'A7K2Q',
      'host': 1,
      'playing': false,
      'seats': [
        {
          'client': {'id': 1, 'name': '甲'},
          'bot': false,
        },
        {
          'client': {'id': 2, 'name': '乙'},
          'bot': false,
        },
      ],
      'party': {
        'queue': ['memorypairs', 'wordtiles', 'lightsout'],
        'index': 0,
        'finished': false,
        'roundComplete': true,
        'votes': {'1': 'wordtiles'},
        'scores': [
          {'name': '甲', 'points': 100, 'wins': 1},
        ],
      },
    };
  });
  tearDown(() => app.dispose());
  Future<void> pump(
    WidgetTester tester,
    Widget child,
    Size size, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      AppScope(
        app: app,
        child: MaterialApp(
          theme: auroraThemes.first.toThemeData(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.takeException(),
      isNull,
      reason: '${child.runtimeType} $size',
    );
  }

  const sizes = [
    Size(360, 740),
    Size(844, 390),
    Size(760, 640),
    Size(1280, 720),
  ];
  testWidgets('all new platform screens fit phone, landscape and CML panel', (
    tester,
  ) async {
    for (final size in sizes) {
      await pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(child: PartyPanel(app: app)),
        ),
        size,
      );
      await pump(tester, InviteDialog(app: app), size);
      expect(find.byType(QrImageView), findsOneWidget);
      await pump(
        tester,
        Scaffold(
          body: GamePickerGrid(games: app.games, onPick: (_) {}),
        ),
        size,
      );
    }
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('game finder filters cooperation and picks a compatible game', (
    tester,
  ) async {
    String? selected;
    await pump(
      tester,
      Scaffold(
        body: GamePickerGrid(games: app.games, onPick: (id) => selected = id),
      ),
      const Size(1280, 720),
    );
    await tester.tap(find.text('玩法：不限'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('合作').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('帮我选'));
    await tester.pump();
    expect(selected, isNotNull);
    expect(findGame(selected!)!.toJson()['mode'], 'coop');
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
