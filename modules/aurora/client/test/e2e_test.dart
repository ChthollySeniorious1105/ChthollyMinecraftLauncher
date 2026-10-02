import 'dart:convert';
import 'dart:io';

import 'package:aurora_client/net/connection.dart';
import 'package:aurora_client/state/app_state.dart';
import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives two real client AppStates (same code the app uses) against a real
/// in-process server over TCP: connect, create/join room, chat, bots, play
/// tic-tac-toe to the end, reconnect after a drop.
void main() {
  test('address parsing', () {
    expect(Connection.parseAddress('1.2.3.4:9000'), ('1.2.3.4', 9000));
    expect(Connection.parseAddress(' frp.example.com:23456 '), ('frp.example.com', 23456));
    expect(Connection.parseAddress('myhost'), ('myhost', kDefaultPort));
    expect(Connection.parseAddress('[::1]:7000'), ('::1', 7000));
    expect(Connection.parseAddress('tcp://1.2.3.4:81/'), ('1.2.3.4', 81));
  });

  test('two clients play a full game through the real server', () async {
    final tmp = Directory.systemTemp.createTempSync('aurora_e2e');
    final server = AuroraServer(17801, dataDir: Directory('${tmp.path}/data'), replayDir: Directory('${tmp.path}/replays'));
    await server.start();
    SharedPreferences.setMockInitialValues({});

    Future<AppState> mk(String name, int avatar) async {
      final a = AppState();
      await a.load();
      a.saveProfile(name, avatar);
      await a.connect('127.0.0.1:17801');
      return a;
    }

    Future<void> until(bool Function() p, [String what = '']) async {
      final end = DateTime.now().add(const Duration(seconds: 8));
      while (!p()) {
        if (DateTime.now().isAfter(end)) fail('timeout waiting for $what');
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }

    final a = await mk('甲', 10);
    final b = await mk('Bob', 20);
    await until(() => a.state == ConnState.connected && b.state == ConnState.connected, 'connect');
    expect(a.games.length, gameRegistry.length);

    a.send({'t': 'create_room', 'name': 'x', 'game': 'tictactoe'});
    await until(() => b.rooms.isNotEmpty, 'room list');
    b.send({'t': 'join_room', 'room': b.rooms.first['id']});
    await until(() => b.room != null && a.seats.where((s) => s['client'] != null).length == 2, 'join');
    expect(a.isHost, isTrue);
    expect(b.isHost, isFalse);

    b.send({'t': 'chat', 'text': 'hi 你好'});
    await until(() => a.chat.any((l) => l.text == 'hi 你好'), 'chat');

    b.send({'t': 'ready', 'ready': true});
    await until(() => a.seats[b.mySeat]['ready'] == true, 'ready');
    a.send({'t': 'start'});
    await until(() => a.game != null && b.game != null, 'game start');

    // both humans play first free cell when it's their turn
    for (var i = 0; i < 20 && !(a.game?.over ?? false); i++) {
      for (final p in [a, b]) {
        final g = p.game!;
        if (!g.over && g.view['turn'] == g.seat) {
          final cells = (g.view['cells'] as List);
          p.action({'cell': cells.indexOf(-1)});
          final before = cells.where((c) => c != -1).length;
          await until(() => (p.game!.view['cells'] as List).where((c) => c != -1).length > before || p.game!.over, 'move');
        }
      }
    }
    expect(a.game!.over, isTrue);
    expect(b.game!.over, isTrue);

    // v3: tally, stats, replay list + download, emote
    await until(() => (a.room?['tally'] as List?)?.isNotEmpty ?? false, 'tally');
    final replays = <Map>[];
    final stats = <Map>[];
    final chunks = <int, String>{};
    var nChunks = -1;
    final sub = a.conn.messages.listen((m) {
      if (m['t'] == Msg.replays) replays.addAll((m['replays'] as List).cast<Map>());
      if (m['t'] == Msg.stats) stats.add(m['stats'] as Map);
      if (m['t'] == Msg.replayChunk) {
        chunks[m['i'] as int] = m['data'] as String;
        nChunks = m['n'] as int;
      }
    });
    a.send({'t': Msg.myStats});
    await until(() => stats.isNotEmpty, 'stats');
    expect(stats.first['games'], greaterThanOrEqualTo(1)); // both test clients share mock prefs → same uid
    a.send({'t': Msg.listReplays});
    await until(() => replays.isNotEmpty, 'replays');
    a.send({'t': Msg.getReplay, 'id': replays.first['id']});
    await until(() => nChunks > 0 && chunks.length == nChunks, 'replay chunks');
    final bytes = gzip.decode(base64.decode([for (var i = 0; i < nChunks; i++) chunks[i]!].join()));
    final rp = Replay.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    expect(rp.meta.game, 'tictactoe');
    expect(rp.frames(0).last.$2['cells'], a.game!.view['cells']);
    b.send({'t': Msg.emote, 'e': 1});
    var gotEmote = false;
    final sub2 = a.conn.messages.listen((m) {
      if (m['t'] == Msg.emoteMsg) gotEmote = true;
    });
    await until(() => gotEmote, 'emote');
    await sub.cancel();
    await sub2.cancel();

    // drop b's socket; it must reconnect automatically and be back in the room
    final roomId = a.room!['id'];
    b.conn.dropForTest();
    await until(() => b.state == ConnState.connected && b.room?['id'] == roomId, 'reconnect');

    await a.disconnect();
    await b.disconnect();
    await server.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
