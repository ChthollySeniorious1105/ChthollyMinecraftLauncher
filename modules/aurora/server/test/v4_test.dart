import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aurora_server/server.dart';
import 'package:aurora_server/party.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';
import 'server_test.dart' show TClient;

class WebPeer {
  late WebSocket ws;
  final messages = <Map<String, dynamic>>[];
  SecureChannel? channel;
  Future<void> connect(int port) async {
    ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    final decoder = FrameDecoder(maxFrame: kMaxServerFrame),
        hs = ClientHandshake(),
        ready = Completer<void>();
    ws.listen((raw) {
      for (final f in decoder.add(raw as List<int>)) {
        if (channel == null) {
          channel = hs.finish(f.json).$1;
          ready.complete();
        } else {
          messages.add(Frame(f.kind, channel!.open(f.kind, f.payload)).json);
        }
      }
    });
    ws.add(encodeJson(hs.hello()));
    await ready.future.timeout(const Duration(seconds: 5));
  }

  void send(Map<String, dynamic> m) => ws.add(
    encodeFrame(
      kFrameJson,
      channel!.seal(kFrameJson, utf8.encode(jsonEncode(m))),
    ),
  );
  Future<Map<String, dynamic>> wait(
    String type, [
    bool Function(Map)? predicate,
  ]) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(end)) {
      final found = messages
          .where((m) => m['t'] == type && (predicate == null || predicate(m)))
          .firstOrNull;
      if (found != null) {
        messages.remove(found);
        return found;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('timeout: $type');
  }
}

void main() {
  test(
    'party votes choose only compatible games and scores survive transitions',
    () {
      final p = PartyNight(['wordtiles', 'memorypairs', 'lightsout']);
      expect(() => p.vote(1, 'memorypairs'), throwsA(isA<GameError>()));
      p.record(
        [
          {'key': 'a', 'name': '甲', 'avatar': 1},
          {'key': 'b', 'name': '乙', 'avatar': 2},
        ],
        [1, 2],
      );
      p.vote(1, 'lightsout');
      p.vote(2, 'lightsout');
      p.vote(3, 'memorypairs');
      expect(p.nextChoice({1, 2}, (_) => true), 'lightsout');
      expect(p.nextChoice({1, 2}, (id) => id == 'memorypairs'), 'memorypairs');
      p.advance('lightsout');
      expect(p.scores['a']!['points'], 100);
      p.record(
        [
          {'key': 'a', 'name': '甲', 'avatar': 1},
          {'key': 'b', 'name': '乙', 'avatar': 2},
        ],
        [2, 1],
      );
      p.advance('memorypairs');
      p.record([], null);
      expect(p.finished, isTrue);
      expect(() => p.advance('wordtiles'), throwsA(isA<GameError>()));
    },
  );
  test(
    'TCP and WebSocket share party, invite metadata and reconnect',
    () async {
      final dir = Directory.systemTemp.createTempSync('aurora_v4_');
      final server = AuroraServer(
        17862,
        webPort: 0,
        dataDir: dir,
        replayDir: Directory('${dir.path}/replays'),
        publicWebUrl: 'https://example.com/',
        publicNativeAddress: 'example.com:7788',
      );
      await server.start();
      final native = TClient(), web = WebPeer();
      addTearDown(() async {
        native.s.destroy();
        await web.ws.close();
        await server.stop();
        dir.deleteSync(recursive: true);
      });
      await native.connect(17862);
      await web.connect(server.webBoundPort!);
      native.send({
        't': Msg.hello,
        'ver': kProtocolVersion,
        'name': '客户端',
        'uid': 'native-user',
      });
      final nw = await native.waitT(Msg.welcome);
      expect(nw['publicWebUrl'], 'https://example.com/');
      web.send({
        't': Msg.hello,
        'ver': kProtocolVersion,
        'name': '手机网页',
        'uid': 'web-user',
      });
      final ww = await web.wait(Msg.welcome);
      native.send({'t': Msg.createRoom, 'name': '跨端派对', 'game': 'memorypairs'});
      final created = await native.wait(
        (m) => m['t'] == Msg.room && m['room'] != null,
      );
      final code = created['room']['id'];
      web.send({'t': Msg.joinRoom, 'room': code});
      await web.wait(Msg.room, (m) => m['room']?['id'] == code);
      native.clear();
      web.send({
        't': Msg.partyConfig,
        'queue': ['memorypairs', 'wordtiles'],
      });
      expect((await web.wait(Msg.error))['msg'], isNotEmpty);
      native.send({
        't': Msg.partyConfig,
        'queue': ['memorypairs', 'wordtiles'],
      });
      await native.wait(
        (m) => m['t'] == Msg.room && m['room']?['party'] != null,
      );
      web.send({'t': Msg.ready, 'ready': true});
      await native.wait(
        (m) =>
            m['t'] == Msg.room &&
            (m['room']['seats'] as List).any(
              (s) => s['client']?['name'] == '手机网页' && s['ready'] == true,
            ),
      );
      native.send({'t': Msg.start});
      await native.waitT(Msg.game);
      final room = server.rooms[code]!;
      // Drive real encrypted actions from both transport types to complete the round.
      var steps = 0;
      while (room.playing && steps++ < 200) {
        final e = room.engine!, seat = room.engine!.waitingFor.first;
        final a = e.runBot(seat)!;
        final version = jsonEncode(e.view(-1));
        if (seat == 0) {
          native.send({'t': Msg.action, 'a': a});
        } else {
          web.send({'t': Msg.action, 'a': a});
        }
        for (
          var i = 0;
          i < 100 && room.playing && jsonEncode(e.view(-1)) == version;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 12));
        }
      }
      expect(room.party!.roundComplete, isTrue);
      web.send({'t': Msg.partyVote, 'game': 'wordtiles'});
      await web.wait(
        Msg.room,
        (m) => (m['room']?['party']?['votes'] as Map?)?.isNotEmpty == true,
      );
      native.send({'t': Msg.partyNext});
      await native.wait(
        (m) => m['t'] == Msg.room && m['room']?['game'] == 'wordtiles',
      );
      expect(room.party!.scores, isNotEmpty);
      // Server-issued token also survives browser reload / a new network connection.
      await web.ws.close();
      final resumed = WebPeer();
      await resumed.connect(server.webBoundPort!);
      resumed.send({
        't': Msg.hello,
        'ver': kProtocolVersion,
        'name': '手机网页',
        'uid': 'web-user',
        'token': ww['token'],
      });
      expect((await resumed.wait(Msg.welcome))['id'], ww['id']);
      expect((await resumed.wait(Msg.room))['room']['id'], code);
      await resumed.ws.close();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
