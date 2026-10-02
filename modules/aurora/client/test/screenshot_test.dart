import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:aurora_client/games/boards.dart';
import 'package:aurora_client/main.dart';
import 'package:aurora_client/net/connection.dart';
import 'package:aurora_client/screens/connect_screen.dart';
import 'package:aurora_client/screens/lobby_screen.dart';
import 'package:aurora_client/screens/profile_screen.dart';
import 'package:aurora_client/screens/room_screen.dart';
import 'package:aurora_client/screens/settings_screen.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_client/theme/themes.dart';
import 'package:aurora_client/widgets/common.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dev tool: writes PNG screenshots of every board mid-game to build/shots/.
/// Run: flutter test test/screenshot_test.dart  (optionally --plain-name `id`)
/// Only runs when env SHOTS=1 so the normal test suite stays fast.
void main() {
  final shots = Platform.environment['SHOTS'] == '1';
  late AppState app;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'name': 'tester', 'avatar': 3});
    app = AppState();
    app.prefs = await SharedPreferences.getInstance();
    await _loadFonts();
  });

  final sizes = {'desk': const Size(1280, 720), 'phone': const Size(390, 800)};
  final stepsAt = int.tryParse(Platform.environment['STEP'] ?? '') ?? 40;

  testWidgets('screens render without overflow', (tester) async {
    app.name = '小明';
    app.avatar = 42;
    app.recentServers = ['192.168.1.11:7788', 'frp.example.com:23456'];
    app.games = [for (final g in gameRegistry) g.toJson()];
    app.serverName = '周末麻将局';
    app.onlineCount = 7;
    app.rooms = [
      {'id': '3842', 'name': '小明的房间', 'game': 'riichi4', 'gameName': '日本麻将（四人）', 'players': 3, 'seats': 4, 'members': 3, 'playing': false, 'locked': false},
      {'id': '5120', 'name': '斗地主开黑', 'game': 'doudizhu', 'gameName': '斗地主', 'players': 3, 'seats': 3, 'members': 4, 'playing': true, 'locked': true},
      {'id': '7001', 'name': '卧底局', 'game': 'undercover', 'gameName': '谁是卧底', 'players': 6, 'seats': 12, 'members': 6, 'playing': false, 'locked': false},
    ];
    final screens = <String, Widget Function()>{
      'connect': () => const ConnectScreen(),
      'profile': () => const ProfileScreen(),
      'settings': () => const SettingsScreen(),
      'lobby': () {
        app.state = ConnState.connected;
        app.myId = 1;
        return const LobbyScreen();
      },
      'room': () {
        app.room = {
          'id': '3842', 'name': '小明的房间', 'host': 1, 'game': 'riichi4', 'options': findGame('riichi4')!.defaultOptions(),
          'locked': false, 'range': [4, 4], 'playing': false, 'hasGame': false,
          'botLevel': 1,
          'caps': {'resign': false, 'draw': false, 'undo': false},
          'request': null,
          'tally': [
            {'pid': 'a', 'name': '小明', 'avatar': 42, 'games': 3, 'wins': 2, 'points': 8},
            {'pid': 'b', 'name': 'Alice', 'avatar': 77, 'games': 3, 'wins': 1, 'points': 6},
          ],
          'seats': [
            {'client': {'id': 1, 'name': '小明', 'avatar': 42, 'online': true}, 'bot': false, 'botName': '', 'ready': false, 'takenOver': false},
            {'client': {'id': 2, 'name': 'Alice', 'avatar': 77, 'online': true}, 'bot': false, 'botName': '', 'ready': true, 'takenOver': false},
            {'client': null, 'bot': true, 'botName': '电脑1', 'ready': true, 'takenOver': false},
            {'client': null, 'bot': false, 'botName': '', 'ready': false, 'takenOver': false},
          ],
          'members': [
            {'id': 1, 'name': '小明', 'avatar': 42, 'online': true},
            {'id': 2, 'name': 'Alice', 'avatar': 77, 'online': true},
            {'id': 3, 'name': '观众甲', 'avatar': 300, 'online': true},
          ],
        };
        app.chat.addAll([
          ChatLine(0, '系统', 0, 'Alice 进入了房间', DateTime.now(), true),
          ChatLine(2, 'Alice', 77, '来一局半庄？', DateTime.now(), false),
          ChatLine(1, '小明', 42, '好，等我加个电脑', DateTime.now(), false),
        ]);
        return const RoomScreen();
      },
    };
    for (final e in screens.entries) {
      for (final size in sizes.entries) {
        tester.view.physicalSize = size.value;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        final theme = auroraThemes.first;
        final w = e.value();
        await tester.pumpWidget(AppScope(
          app: app,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.toThemeData(),
            builder: (c, child) => RepaintBoundary(key: key, child: DecoratedBox(decoration: theme.backgroundDecoration, child: child)),
            home: w,
          ),
        ));
        await tester.pump(const Duration(milliseconds: 50));
        final err = tester.takeException();
        if (err != null && !'$err'.contains('MissingPluginException')) fail('${e.key} ${size.key}: $err');
        if (!shots) continue;
        await tester.runAsync(() async {
          for (var i = 0; i < 5; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 1.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('build/shots/_screen_${e.key}_${size.key}.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    }
    tester.view.resetPhysicalSize();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  if (!shots) return;
  for (final def in gameRegistry) {
    testWidgets(def.id, (tester) async {
      final opts = def.defaultOptions();
      final (lo, hi) = def.playerRange(opts);
      final players = min(hi, max(lo, 4));
      final setup = GameSetup(
        players: players,
        options: opts,
        names: [for (var i = 0; i < players; i++) ['小明', 'Alice', '雀士', 'Bob', '阿猫', '阿狗'][i % 6]],
        bots: List.filled(players, true),
        hostSeat: 0,
        rng: Random(11),
      );
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

      run();
      for (var s = 0; s < stepsAt && !e.isOver; s++) {
        final w = e.waitingFor;
        if (w.isEmpty) {
          run();
          continue;
        }
        // stop early when it's seat 0's turn after a while, so we see our own actions
        if (s > stepsAt ~/ 2 && w.contains(0)) break;
        final seat = w.first;
        final a = e.runBot(seat);
        if (a == null) break;
        e.handle(seat, a);
        run();
      }
      final v = e.view(0);
      final gs = GameState(def.id, 0, setup.names, setup.bots, List.generate(players, (i) => 40 + i * 37), v, e.isOver);
      for (final entry in sizes.entries) {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        final theme = auroraThemes.first;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.toThemeData(),
          home: RepaintBoundary(
            key: key,
            child: DecoratedBox(
              decoration: theme.backgroundDecoration,
              child: Scaffold(body: SizedBox.expand(child: buildBoard(GameContext(app, gs)))),
            ),
          ),
        ));
        await tester.runAsync(() async {
          // let images/svgs decode
          for (var i = 0; i < 5; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await boundary.toImage(pixelRatio: 1.0);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final f = File('build/shots/${def.id}_${entry.key}.png');
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
      tester.view.resetPhysicalSize();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
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
    var c = false;
    q.add(() {
      if (!c) fn();
    });
    return () => c = true;
  }
}

Future<void> _loadFonts() async {
  // Real CJK font so screenshots show text instead of boxes.
  for (final path in [r'C:\Windows\Fonts\msyh.ttc', r'C:\Windows\Fonts\simhei.ttf']) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('Microsoft YaHei')..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await loader.load();
    for (final fam in ['Roboto', 'FlutterTest']) {
      final l2 = FontLoader(fam)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      await l2.load();
    }
    break;
  }
  for (final (fam, path) in [('Segoe UI Symbol', r'C:\Windows\Fonts\seguisym.ttf'), ('Segoe UI Emoji', r'C:\Windows\Fonts\seguiemj.ttf')]) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final l = FontLoader(fam)..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    await l.load();
  }
  final icons = File(r'D:\Tools\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}
