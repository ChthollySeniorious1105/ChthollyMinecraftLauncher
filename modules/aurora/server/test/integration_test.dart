import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

import 'server_test.dart' show TClient;

/// For every game: host + bots fill the room, game starts, host's seat is played
/// by the server-side bot takeover (host leaves after start). Verifies the room
/// keeps pushing views and the engine survives through the real server.
void main() {
  test('every game starts over TCP and runs with bots', () async {
    final server = AuroraServer(17790);
    await server.start();
    for (final def in gameRegistry) {
      final c = TClient();
      await c.connect(17790);
      c.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'host', 'avatar': 1, 'token': ''});
      await c.waitT(Msg.welcome);
      c.send({'t': 'create_room', 'game': def.id});
      await c.wait((m) => m['t'] == Msg.room && m['room'] != null);
      final (lo, _) = def.playerRange(def.defaultOptions());
      for (var i = 1; i < lo; i++) {
        c.send({'t': 'add_bot', 'seat': i});
      }
      await Future.delayed(const Duration(milliseconds: 50));
      c.send({'t': 'start'});
      final g = await c.wait((m) => m['t'] == Msg.game && m['game'] == def.id);
      expect(g['seat'], 0, reason: def.id);
      // leave → bot takeover; watch a few more updates via a spectator
      final spec = TClient();
      await spec.connect(17790);
      spec.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'spec', 'avatar': 2, 'token': ''});
      await spec.waitT(Msg.welcome);
      final roomId = server.rooms.keys.last;
      c.send({'t': 'leave_room'});
      spec.send({'t': 'join_room', 'room': roomId});
      var updates = 0;
      final until = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(until)) {
        try {
          final m = await spec.wait((m) => m['t'] == Msg.game);
          updates++;
          if (m['over'] == true) break;
        } catch (_) {
          break;
        }
      }
      final room = server.rooms[roomId]!;
      print('${def.id}: $updates spectator updates, playing=${room.playing}');
      expect(updates, greaterThan(0), reason: def.id);
      spec.s.destroy();
      c.s.destroy();
    }
    await server.stop();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
