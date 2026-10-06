import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

/// Minimal raw-TCP test client speaking the encrypted protocol.
class TClient {
  late Socket s;
  final dec = FrameDecoder();
  final msgs = <Map<String, dynamic>>[];
  final voice = <Frame>[];
  final _waiters = <(bool Function(Map<String, dynamic>), Completer<Map<String, dynamic>>)>[];
  SecureChannel? ch;
  final _hs = ClientHandshake();
  final _ready = Completer<void>();
  bool closed = false;

  Future<void> connect(int port) async {
    s = await Socket.connect('127.0.0.1', port);
    s.done.catchError((_) {});
    s.listen((d) {
      for (final f in dec.add(d)) {
        if (ch == null) {
          final m = f.json;
          if (m['t'] == 'shello') {
            ch = _hs.finish(m).$1;
            _ready.complete();
          } else {
            _deliver(m);
          }
          continue;
        }
        final plain = ch!.open(f.kind, f.payload);
        if (f.kind == kFrameVoice) {
          voice.add(Frame(f.kind, plain));
          continue;
        }
        _deliver(Frame(f.kind, plain).json);
      }
    }, onDone: () => closed = true, onError: (_) => closed = true);
    s.add(encodeJson(_hs.hello()));
    await _ready.future.timeout(const Duration(seconds: 5));
  }

  void _deliver(Map<String, dynamic> m) {
    for (final w in List.of(_waiters)) {
      if (w.$1(m)) {
        _waiters.remove(w);
        w.$2.complete(m);
        return; // consumed
      }
    }
    msgs.add(m);
  }

  void send(Map<String, dynamic> m) => sendFrame(kFrameJson, utf8.encode(jsonEncode(m)));
  void sendFrame(int kind, List<int> payload) => s.add(encodeFrame(kind, ch!.seal(kind, payload)));

  Future<Map<String, dynamic>> wait(bool Function(Map<String, dynamic>) p) {
    for (final m in msgs) {
      if (p(m)) {
        msgs.remove(m);
        return Future.value(m);
      }
    }
    final c = Completer<Map<String, dynamic>>();
    _waiters.add((p, c));
    return c.future.timeout(const Duration(seconds: 5));
  }

  Future<Map<String, dynamic>> waitT(String t) => wait((m) => m['t'] == t);
  void clear() => msgs.clear();
}

void main() {
  late AuroraServer server;
  const port = 17788;

  setUp(() async {
    server = AuroraServer(port);
    await server.start();
  });
  tearDown(() => server.stop());

  test('hello, create room, join, chat, voice relay, bot game', () async {
    final a = TClient(), b = TClient();
    await a.connect(port);
    await b.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '甲', 'avatar': 5, 'token': ''});
    b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'Bob', 'avatar': 7, 'token': ''});
    final wa = await a.waitT(Msg.welcome);
    expect(wa['name'], '甲');
    expect((wa['games'] as List).isNotEmpty, true);
    await b.waitT(Msg.welcome);

    a.send({'t': 'create_room', 'name': 'r1', 'game': 'tictactoe'});
    final room = await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    final rid = room['room']['id'];
    final list = await b.wait((m) => m['t'] == Msg.rooms && (m['rooms'] as List).isNotEmpty);
    expect(list['rooms'][0]['id'], rid);

    b.send({'t': 'join_room', 'room': rid});
    await b.wait((m) => m['t'] == Msg.room && m['room'] != null);

    a.send({'t': 'chat', 'text': '你好'});
    final chat = await b.wait((m) => m['t'] == Msg.chatMsg && m['text'] == '你好');
    expect(chat['name'], '甲');

    // voice from a relayed to b with speaker id prefix
    a.sendFrame(kFrameVoice, List.filled(320, 7));
    await Future.delayed(const Duration(milliseconds: 200));
    expect(b.voice.length, 1);
    expect(b.voice.first.payload.length, 324);
    expect(a.voice, isEmpty);
    // sustained real-time voice (16 KB/s for 1 s) must not be throttled
    b.voice.clear();
    for (var i = 0; i < 25; i++) {
      a.sendFrame(kFrameVoice, List.filled(640, 1));
      await Future.delayed(const Duration(milliseconds: 40));
    }
    await Future.delayed(const Duration(milliseconds: 200));
    expect(b.voice.length, 25);

    // b is auto-seated; b must be ready before host can start
    a.send({'t': 'start'});
    final err = await a.waitT(Msg.error);
    expect(err['msg'], contains('准备'));
    b.send({'t': 'ready', 'ready': true});
    await Future.delayed(const Duration(milliseconds: 100));
    a.send({'t': 'start'});
    final g = await a.waitT(Msg.game);
    expect(g['game'], 'tictactoe');

    // non-host can't abort
    b.send({'t': 'abort'});
    expect((await b.waitT(Msg.error))['msg'], contains('房主'));
  });

  test('bot game runs to completion', () async {
    final a = TClient();
    await a.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'solo', 'avatar': 1, 'token': ''});
    await a.waitT(Msg.welcome);
    a.send({'t': 'create_room', 'game': 'tictactoe'});
    await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 100));
    a.send({'t': 'start'});
    // play by always choosing the first empty cell when it's our turn
    for (;;) {
      final g = await a.wait((m) => m['t'] == Msg.game);
      final v = g['view'] as Map;
      if (g['over'] == true) break;
      if (v['turn'] == g['seat']) {
        final cells = (v['cells'] as List);
        a.send({'t': 'action', 'a': {'cell': cells.indexOf(-1)}});
      }
    }
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('name validation and reconnect token', () async {
    final a = TClient();
    await a.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '一二三四五六七八九十', 'avatar': 1, 'token': ''});
    final e = await a.waitT(Msg.error);
    expect(e['fatal'], true);

    final b = TClient();
    await b.connect(port);
    b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'abcdefghijklmnopqr', 'avatar': 1, 'token': ''});
    final w = await b.waitT(Msg.welcome);
    b.send({'t': 'create_room', 'game': 'tictactoe'});
    final r = await b.wait((m) => m['t'] == Msg.room && m['room'] != null);
    b.s.destroy();
    await Future.delayed(const Duration(milliseconds: 100));

    final c = TClient();
    await c.connect(port);
    c.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'abc', 'avatar': 2, 'token': w['token']});
    final w2 = await c.waitT(Msg.welcome);
    expect(w2['id'], w['id']);
    final r2 = await c.wait((m) => m['t'] == Msg.room && m['room'] != null);
    expect(r2['room']['id'], r['room']['id']);
  });

  test('empty room is destroyed after TTL', () async {
    final srv = AuroraServer(port + 1, emptyTtl: const Duration(milliseconds: 300), sweepInterval: const Duration(milliseconds: 100));
    await srv.start();
    final a = TClient();
    await a.connect(port + 1);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'x', 'avatar': 1, 'token': ''});
    await a.waitT(Msg.welcome);
    a.send({'t': 'create_room', 'game': 'tictactoe'});
    await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    a.send({'t': 'leave_room'});
    await Future.delayed(const Duration(milliseconds: 150));
    expect(srv.rooms.length, 1, reason: 'not destroyed before TTL');
    await Future.delayed(const Duration(milliseconds: 500));
    expect(srv.rooms, isEmpty);
    await srv.stop();
  });

  test('turn timeout makes the bot move for an idle human', () async {
    final a = TClient();
    await a.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'idle', 'avatar': 1, 'token': ''});
    await a.waitT(Msg.welcome);
    a.send({'t': 'create_room', 'game': 'tictactoe'});
    await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    a.send({'t': 'add_bot', 'seat': 1});
    await Future.delayed(const Duration(milliseconds: 50));
    final room = server.rooms.values.first;
    room.turnTimeout = 1; // test hook: 1 s (UI only offers >= 15 s)
    a.send({'t': 'start'});
    // wait until the human is to move, then do nothing
    for (;;) {
      final g = await a.wait((m) => m['t'] == Msg.game);
      if ((g['view'] as Map)['turn'] == g['seat']) {
        expect((g['deadlines'] as Map).containsKey('${g['seat']}'), isTrue);
        break;
      }
    }
    final t = await a.wait((m) => m['t'] == Msg.toast && '${m['msg']}'.contains('超时'));
    expect(t['msg'], contains('代打'));
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('custom word files are loaded, hot-reloaded and passed to games', () async {
    final dir = Directory.systemTemp.createTempSync('aurora_words');
    final res = ServerResources(dir)..ensureTemplates();
    expect(res.lines('drawguess.words'), isEmpty, reason: 'template has only comments');
    final f = File('${dir.path}/drawguess.txt');
    f.writeAsStringSync('# c\n奶茶|食物\n\n 打太极 \n');
    expect(res.lines('drawguess.words'), ['奶茶|食物', '打太极']);
    await Future.delayed(const Duration(milliseconds: 1100));
    f.writeAsStringSync('饺子\n');
    expect(res.lines('drawguess.words'), ['饺子']);
    expect(res.snapshot()['drawguess.words'], ['饺子']);
    dir.deleteSync(recursive: true);
  });

  test('private rooms: 5-char code, hidden from list, join by code; spectate; start needs enough players', () async {
    final a = TClient(), b = TClient(), c = TClient();
    for (final x in [a, b, c]) {
      await x.connect(port);
    }
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'host', 'avatar': 1, 'token': ''});
    b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'b', 'avatar': 1, 'token': ''});
    c.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'c', 'avatar': 1, 'token': ''});
    for (final x in [a, b, c]) {
      await x.waitT(Msg.welcome);
    }
    a.send({'t': 'create_room', 'game': 'tictactoe', 'private': true});
    final r = await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
    final code = r['room']['id'] as String;
    expect(code, matches(RegExp(r'^[A-Z0-9]{5}$')));
    expect(code, matches(RegExp('[A-Z]')));
    expect(code, matches(RegExp('[0-9]')));
    expect(r['room']['private'], isTrue);
    expect(r['room']['canStart'], isFalse, reason: 'only the host is seated');
    b.clear();
    b.send({'t': 'list_rooms'});
    final list = await b.waitT(Msg.rooms);
    expect(list['rooms'], isEmpty, reason: 'private room must not be listed');
    // host cannot start alone
    a.send({'t': 'start'});
    expect((await a.waitT(Msg.error))['msg'], contains('需要'));
    // join by code (lower-case works), as spectator
    b.send({'t': 'join_room', 'room': code.toLowerCase(), 'spectate': true});
    final rb = await b.wait((m) => m['t'] == Msg.room && m['room'] != null && (m['room']['members'] as List).length == 2);
    expect((rb['room']['seats'] as List).where((s) => (s as Map)['client'] != null).length, 1, reason: 'spectator not seated');
    // normal join sits and makes it startable
    c.send({'t': 'join_room', 'room': code});
    final rc = await a.wait((m) => m['t'] == Msg.room && m['room'] != null && m['room']['canStart'] == true);
    expect(rc['room']['canStart'], isTrue);
    // host switches to public: now listed
    a.send({'t': 'set_private', 'private': false});
    await a.wait((m) => m['t'] == Msg.room && m['room'] != null && m['room']['private'] == false);
    final d = TClient();
    await d.connect(port);
    d.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'd', 'avatar': 1, 'token': ''});
    final ld = await d.wait((m) => m['t'] == Msg.rooms);
    expect((ld['rooms'] as List).length, 1);
    // non-host can't change visibility; switching game keeps members
    b.send({'t': 'set_private', 'private': true});
    expect((await b.waitT(Msg.error))['msg'], contains('房主'));
    a.send({'t': 'set_game', 'game': 'connect4', 'options': {}});
    final rg = await a.wait((m) => m['t'] == Msg.room && m['room'] != null && m['room']['game'] == 'connect4');
    expect((rg['room']['members'] as List).length, 3);
  });

  test('chat reactions: stick 😂 on someone else\'s message, toggle off', () async {
    final a = TClient(), b = TClient();
    await a.connect(port);
    await b.connect(port);
    a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '甲', 'avatar': 1, 'token': ''});
    b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': '乙', 'avatar': 2, 'token': ''});
    final wb = await b.waitT(Msg.welcome);
    await a.waitT(Msg.welcome);
    a.send({'t': 'create_room', 'name': 'r', 'game': 'tictactoe'});
    final rid = (await a.wait((m) => m['t'] == Msg.room && m['room'] != null))['room']['id'];
    b.send({'t': 'join_room', 'room': rid});
    await b.wait((m) => m['t'] == Msg.room && m['room'] != null);

    a.send({'t': 'chat', 'text': '笑死'});
    final msg = await b.wait((m) => m['t'] == Msg.chatMsg && m['text'] == '笑死');
    final id = msg['id'] as int;
    expect(id, greaterThan(0));
    expect(kReactions[0], '😂');

    b.send({'t': Msg.react, 'id': id, 'e': 0});
    final on = await a.waitT(Msg.reactMsg);
    expect(on, containsPair('id', id));
    expect(on['e'], 0);
    expect(on['on'], isTrue);
    expect(on['from'], wb['id']);
    expect(on['name'], '乙');

    b.send({'t': Msg.react, 'id': id, 'e': 0});
    expect((await a.waitT(Msg.reactMsg))['on'], isFalse);

    b.send({'t': Msg.react, 'id': id + 999, 'e': 0});
    expect((await b.waitT(Msg.error))['msg'], contains('太旧'));
    b.send({'t': Msg.react, 'id': id, 'e': kReactions.length});
    expect((await b.waitT(Msg.error))['msg'], contains('无效'));
  });

  group('security', () {
    Future<bool> closedSoon(Socket s) async {
      final done = Completer<bool>();
      s.listen((_) {}, onDone: () => done.complete(true), onError: (_) => done.complete(true));
      return done.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
    }

    test('plaintext v1 client is rejected', () async {
      final s = await Socket.connect('127.0.0.1', port);
      s.add(encodeJson({'t': 'hello', 'ver': 1, 'name': 'old', 'avatar': 1, 'token': ''}));
      expect(await closedSoon(s), isTrue);
    });

    test('garbage and oversized frames disconnect', () async {
      final s = await Socket.connect('127.0.0.1', port);
      s.add([0xFF, 0xFF, 0xFF, 0xFF, 0, 1, 2]);
      expect(await closedSoon(s), isTrue);
      final s2 = await Socket.connect('127.0.0.1', port);
      s2.add(encodeJson({'t': 'chello', 'v': 2, 'epk': 'AAAA', 'cn': 'AAAA'}));
      expect(await closedSoon(s2), isTrue);
    });

    test('silent socket is dropped after handshake timeout', () async {
      final s = await Socket.connect('127.0.0.1', port);
      expect(await closedSoon(s), isTrue);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('tampered encrypted frame disconnects', () async {
      final a = TClient();
      await a.connect(port);
      a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'x', 'avatar': 1, 'token': ''});
      await a.waitT(Msg.welcome);
      final frame = a.ch!.seal(kFrameJson, utf8.encode(jsonEncode({'t': 'list_rooms'})));
      frame[frame.length - 1] ^= 0x55;
      a.s.add(encodeFrame(kFrameJson, frame));
      await Future.delayed(const Duration(milliseconds: 300));
      expect(a.closed, isTrue);
    });

    test('room password brute force is throttled', () async {
      final a = TClient(), b = TClient();
      await a.connect(port);
      await b.connect(port);
      a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'host', 'avatar': 1, 'token': ''});
      b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'atk', 'avatar': 1, 'token': ''});
      await a.waitT(Msg.welcome);
      await b.waitT(Msg.welcome);
      a.send({'t': 'create_room', 'game': 'tictactoe', 'password': 'secret'});
      final r = await a.wait((m) => m['t'] == Msg.room && m['room'] != null);
      final id = r['room']['id'];
      await Future.delayed(const Duration(milliseconds: 100));
      b.clear();
      for (var i = 0; i < 5; i++) {
        b.send({'t': 'join_room', 'room': id, 'password': 'guess$i'});
        final e = await b.waitT(Msg.error);
        expect(e['msg'], contains('密码错误'), reason: 'attempt $i: ${e['msg']}');
      }
      b.send({'t': 'join_room', 'room': id, 'password': 'secret'});
      expect((await b.waitT(Msg.error))['msg'], contains('次数过多'));
    });

    test('names with bidi/zero-width chars are rejected, chat is sanitized', () async {
      final a = TClient();
      await a.connect(port);
      a.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'ad\u202Emin', 'avatar': 1, 'token': ''});
      expect((await a.waitT(Msg.error))['fatal'], isTrue);
      final b = TClient();
      await b.connect(port);
      b.send({'t': 'hello', 'ver': kProtocolVersion, 'name': 'ok', 'avatar': 1, 'token': ''});
      await b.waitT(Msg.welcome);
      b.send({'t': 'chat', 'text': 'hi\u202Eevil\u0007'});
      final c = await b.waitT(Msg.chatMsg);
      expect(c['text'], 'hievil');
    });

    test('too many connections from one IP are refused', () async {
      final socks = <Socket>[];
      for (var i = 0; i < maxPendingPerIp; i++) {
        socks.add(await Socket.connect('127.0.0.1', port));
      }
      final extra = await Socket.connect('127.0.0.1', port);
      expect(await closedSoon(extra), isTrue);
      for (final s in socks) {
        s.destroy();
      }
    });
  });

  test('frame decoder handles split and merged frames', () {
    final d = FrameDecoder();
    final f1 = encodeJson({'a': 1});
    final f2 = encodeJson({'b': '二'});
    final all = [...f1, ...f2];
    final out = <Frame>[];
    for (var i = 0; i < all.length; i += 3) {
      out.addAll(d.add(all.sublist(i, i + 3 > all.length ? all.length : i + 3)));
    }
    expect(out.map((f) => f.json).toList(), [
      {'a': 1},
      {'b': '二'}
    ]);
    expect(nameWidth('abc中文'), 7);
    expect(validateName('一二三四五六七八九'), isNull);
    expect(validateName('一二三四五六七八九十'), isNotNull);
  });

  test('client decoder accepts server frames larger than kMaxFrame', () {
    final big = encodeJson({'s': 'x' * (kMaxFrame * 2)});
    expect(() => FrameDecoder().add(big), throwsFormatException);
    final out = FrameDecoder(maxFrame: kMaxServerFrame).add(big);
    expect((out.single.json['s'] as String).length, kMaxFrame * 2);
  });
}
