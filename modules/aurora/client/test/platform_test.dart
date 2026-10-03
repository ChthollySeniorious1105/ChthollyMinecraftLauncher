import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aurora_client/main.dart';
import 'package:aurora_client/platform/game_ui.dart';
import 'package:aurora_client/platform/local_session.dart';
import 'package:aurora_client/platform/replay_store.dart';
import 'package:aurora_client/platform/sfx.dart';
import 'package:aurora_client/screens/local_game_screen.dart';
import 'package:aurora_client/screens/replay_screen.dart';
import 'package:aurora_client/screens/room_screen.dart';
import 'package:aurora_client/screens/stats_screen.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_client/theme/themes.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Platform features: single-player sessions, replays, rules, sounds.
void main() {
  late AppState app;
  late Directory tmp;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'name': 'tester', 'avatar': 3});
    app = AppState();
    app.prefs = await SharedPreferences.getInstance();
    app.games = [for (final g in gameRegistry) g.toJson()];
    tmp = Directory.systemTemp.createTempSync('aurora_replays_');
    ReplayStore.dirOverride = tmp.path;
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Human (seat 0) plays the first legal move a bot would pick.
  Future<LocalSession> playOut(LocalSession s, {int maxMs = 20000}) async {
    final end = DateTime.now().add(Duration(milliseconds: maxMs));
    while (!s.isOver) {
      if (DateTime.now().isAfter(end)) fail('local game did not finish');
      if (s.engine.waitingFor.contains(s.humanSeat)) {
        final a = s.engine.runBot(s.humanSeat);
        if (a != null) s.act(a);
      }
      await Future.delayed(const Duration(milliseconds: 3));
    }
    return s;
  }

  test('local session plays tictactoe to the end with bots and saves a replay', () async {
    final s = LocalSession(
      def: findGame('tictactoe')!,
      options: const {},
      players: 2,
      humanName: 'tester',
      humanAvatar: 3,
      botDelayMs: 1,
    );
    final errors = <String>[];
    s.onToast = errors.add;
    s.begin();
    expect(s.state, isNotNull);
    expect(s.state!.seat, 0);
    expect(s.state!.names.length, 2);
    await playOut(s);
    expect(s.state!.over, isTrue);
    expect(s.engine.placings, isNotNull);
    expect(errors, isEmpty);
    // replay saved on finish
    for (var i = 0; i < 100 && s.replayPath == null; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    expect(s.replayPath, isNotNull);
    final saved = await ReplayStore.list();
    expect(saved, isNotEmpty);
    final r = await ReplayStore.load(saved.first.path);
    expect(r.meta.game, 'tictactoe');
    expect(r.frames(0), isNotEmpty);
    expect(r.frames(-1), isNotEmpty);

    // 再来一局
    s.begin();
    expect(s.isOver, isFalse);
    await playOut(s);
    s.dispose();
  });

  test('local undo, resign and draw', () async {
    final s = LocalSession(
      def: findGame('tictactoe')!,
      options: const {},
      players: 2,
      humanName: 'tester',
      humanAvatar: 3,
      botDelayMs: 1,
      saveReplay: false,
    );
    s.begin();
    // wait for my turn, move, wait for the bot reply
    Future<void> myTurn() async {
      for (var i = 0; i < 500 && !s.engine.waitingFor.contains(0); i++) {
        await Future.delayed(const Duration(milliseconds: 2));
      }
    }

    await myTurn();
    final before = jsonEncode(s.engine.view(0));
    s.act(s.engine.runBot(0)!);
    expect(s.canUndo, isTrue);
    await myTurn();
    s.undo();
    expect(jsonEncode(s.engine.view(0)), before);
    expect(s.engine.waitingFor, contains(0));

    s.offerDraw();
    expect(s.isOver, isTrue);
    expect(s.engine.placings, [1, 1]);

    s.begin();
    s.resign();
    expect(s.isOver, isTrue);
    expect(s.myPlacing, 2);
    s.dispose();
  });

  test('app routes actions to the local session', () async {
    final s = LocalSession(
        def: findGame('tictactoe')!, options: const {}, players: 2, humanName: 't', humanAvatar: 1, botDelayMs: 1, saveReplay: false);
    app.startLocal(s);
    for (var i = 0; i < 500 && !s.engine.waitingFor.contains(0); i++) {
      await Future.delayed(const Duration(milliseconds: 2));
    }
    int? cells() => (s.state!.view['cells'] as List?)?.where((c) => c != -1).length;
    final n = cells();
    app.action(s.engine.runBot(0)!);
    expect(cells(), (n ?? 0) + 1);
    expect(app.recentGames.first, 'tictactoe');
    app.endLocal();
    expect(app.local, isNull);
  });

  test('replay gzip round trip + sfx wav', () {
    final doc = _syntheticReplay();
    final r = decodeReplayGz(encodeReplayGz(doc));
    expect(r.meta.id, 'test1');
    expect(r.frames(1).length, greaterThan(2));
    final wav = Sfx.wavFor(SfxKind.win);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.length, greaterThan(1000));
    // must not throw when audio isn't available
    Sfx().play(SfxKind.turn);
  });

  const sizes = [Size(390, 800), Size(800, 390), Size(1280, 720)];

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(AppScope(
      app: app,
      child: MaterialApp(theme: auroraThemes.first.toThemeData(), home: home),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('replay player renders a tictactoe replay', (tester) async {
    final r = Replay.fromJson(jsonDecode(jsonEncode(_syntheticReplay())) as Map<String, dynamic>);
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await pumpApp(tester, ReplayPlayerScreen(key: ValueKey(size), replay: r, gz: encodeReplayGz(_syntheticReplay())));
      expect(tester.takeException(), isNull, reason: 'size $size');
      expect(find.textContaining('回放'), findsWidgets);
      await tester.tap(find.byIcon(Icons.skip_next));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.play_circle));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: 'play $size');
      // switch perspective to seat 1
      await tester.tap(find.text('观众视角'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P2 视角').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'seat $size');
      await tester.tap(find.byIcon(Icons.skip_previous));
      await tester.pump();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rules, emotes, stats and local screens render', (tester) async {
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await pumpApp(tester, Scaffold(body: RulesView(findGame('tictactoe')!.rules * 3)));
      await pumpApp(tester, const LocalSetupScreen());
      expect(tester.takeException(), isNull, reason: 'setup $size');
      await pumpApp(tester, const StatsScreen());
      app.myStats = {
        'games': 12,
        'wins': 5,
        'per': {
          'tictactoe': {'p': 10, 'w': 4, 'elo': 1532},
          'chess': {'p': 2, 'w': 1, 'elo': 1490},
        },
      };
      app.leaderboards['tictactoe'] = [
        {'name': 'Alice', 'avatar': 7, 'elo': 1612, 'p': 30, 'w': 20},
        {'name': '小明', 'avatar': 8, 'elo': 1540, 'p': 12, 'w': 6},
      ];
      app.touch();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('1532'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'stats $size');
      await pumpApp(
        tester,
        Builder(
          builder: (c) => Scaffold(
            appBar: AppBar(actions: [
              GameActionsBar(GameActionsModel(
                canPlay: true,
                auto: true,
                canResign: true,
                canDraw: true,
                canUndo: true,
                onEmote: () => pickEmote(c),
                onAuto: (_) {},
                onResign: () {},
                onDraw: () {},
                onUndo: () {},
                onRules: () {},
              )),
            ]),
            body: Stack(children: [
              Positioned.fill(child: EmoteOverlay(events: app.emotes)),
              Positioned.fill(
                child: RequestOverlay(
                  request: const {'id': 1, 'kind': 'undo', 'fromId': 2, 'fromName': 'Alice', 'yes': [], 'need': [0]},
                  myId: 0,
                  onRespond: (_) {},
                ),
              ),
            ]),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'emotes $size');
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();
      app.sendEmote(0); // no local session, not connected: just a no-op send
      await tester.pump(const Duration(seconds: 3));
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('room screen: seats + in-game toolbar, request, tally', (tester) async {
    final def = findGame('tictactoe')!;
    final e = def.create(GameSetup(players: 2, options: def.defaultOptions(), names: ['tester', 'Alice'], bots: [false, false]));
    e.start();
    Map<String, dynamic> room({required bool playing, Map<String, dynamic>? request}) => {
          'id': 'AB12C', 'name': 'r', 'host': 1, 'game': 'tictactoe', 'options': def.defaultOptions(),
          'locked': false, 'private': false, 'range': [2, 2], 'playing': playing, 'hasGame': playing, 'canStart': !playing,
          'turnTimeout': 0, 'botLevel': 2,
          'caps': {'resign': playing, 'draw': playing, 'undo': playing},
          'request': request,
          'tally': [
            {'pid': 'p1', 'name': 'tester', 'avatar': 3, 'games': 2, 'wins': 1, 'points': 5},
            {'pid': 'p2', 'name': 'Alice', 'avatar': 9, 'games': 2, 'wins': 1, 'points': 4},
          ],
          'seats': [
            {'client': {'id': 1, 'name': 'tester', 'avatar': 3, 'online': true}, 'bot': false, 'botName': '', 'ready': true, 'auto': true},
            {'client': {'id': 2, 'name': 'Alice', 'avatar': 9, 'online': true}, 'bot': false, 'botName': '', 'ready': true, 'auto': false},
          ],
          'members': [
            {'id': 1, 'name': 'tester', 'avatar': 3, 'online': true},
            {'id': 2, 'name': 'Alice', 'avatar': 9, 'online': true},
          ],
        };
    app.myId = 1;
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      app.room = room(playing: false);
      app.game = null;
      await pumpApp(tester, const RoomScreen());
      expect(tester.takeException(), isNull, reason: 'seats $size');
      await tester.scrollUntilVisible(find.text('积分榜'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('积分榜'), findsOneWidget);
      app.room = room(playing: true, request: {'id': 7, 'kind': 'draw', 'fromId': 2, 'fromName': 'Alice', 'yes': [], 'need': [1]});
      app.game = GameState('tictactoe', 0, ['tester', 'Alice'], [false, false], [3, 9], e.view(0), false);
      app.touch();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: 'game $size');
      expect(find.text('Alice 请求和棋'), findsOneWidget);
      expect(find.textContaining('托管中'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('认输'), findsOneWidget);
      expect(find.text('悔棋'), findsOneWidget);
      await tester.tapAt(const Offset(5, 300));
      await tester.pumpAndSettle();
    }
    app.room = null;
    app.game = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('local game screen renders and plays', (tester) async {
    final s = LocalSession(
        def: findGame('tictactoe')!, options: const {}, players: 2, humanName: 'tester', humanAvatar: 3, botDelayMs: 1, saveReplay: false);
    app.startLocal(s);
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await pumpApp(tester, const LocalGameScreen());
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull, reason: 'local $size');
    }
    s.resign();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('再来一局'), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.endLocal();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

/// A finished bot-vs-bot tictactoe game recorded the way the server does.
Map<String, dynamic> _syntheticReplay() {
  final def = findGame('tictactoe')!;
  final setup = GameSetup(players: 2, options: def.defaultOptions(), names: ['P1', 'P2'], bots: [true, true], rng: Random(5));
  final e = def.create(setup);
  final rec = ReplayRecorder(2, startedAt: 0, minGapMs: 0);
  void snap() {
    for (var s = -1; s < 2; s++) {
      rec.add(s, e.view(s), force: true);
    }
  }

  e.start();
  snap();
  while (!e.isOver) {
    final s = e.waitingFor.first;
    e.handle(s, e.runBot(s)!);
    snap();
  }
  // spread frames out in time
  final doc = rec.finish((d) => ReplayMeta(
        id: 'test1',
        game: 'tictactoe',
        gameName: def.name,
        startedAt: DateTime(2026, 9, 1).millisecondsSinceEpoch,
        durationMs: 9000,
        names: ['P1', 'P2'],
        avatars: [5, 6],
        bots: [true, true],
        options: def.defaultOptions(),
        uids: ['', ''],
        ranking: e.placings,
        room: 'ABCDE',
      ));
  for (final t in (doc['tracks'] as List)) {
    var k = 0;
    for (final f in (t as List)) {
      (f as Map)['t'] = 1000 * k++;
    }
  }
  doc['logs'] = [
    [0, 'P1 执 X 先手'],
    [3000, '某条记录'],
  ];
  return doc;
}
