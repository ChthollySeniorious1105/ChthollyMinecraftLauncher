import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_server/server.dart';
import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

/// Browser client path: static files + encrypted protocol over a WebSocket.
void main() {
  late AuroraServer server;
  late Directory tmp;
  late int webPort;
  const port = 17830;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('aurora_web_');
    final web = Directory('${tmp.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<html>aurora-web</html>');
    File('${web.path}/main.dart.js').writeAsStringSync('console.log(1)');
    File('${tmp.path}/secret.txt').writeAsStringSync('secret');
    server = AuroraServer(port,
        webPort: 0, webDir: web, dataDir: Directory('${tmp.path}/data'), replayDir: Directory('${tmp.path}/replays'));
    await server.start();
    webPort = server.webBoundPort!;
  });

  tearDownAll(() async {
    await server.stop();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<(int, String, ContentType?)> get(String path) async {
    final c = HttpClient();
    try {
      final req = await c.getUrl(Uri.parse('http://127.0.0.1:$webPort$path'));
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join(), res.headers.contentType);
    } finally {
      c.close(force: true);
    }
  }

  test('serves the web client and falls back to index.html', () async {
    final (s1, b1, t1) = await get('/');
    expect(s1, 200);
    expect(b1, contains('aurora-web'));
    expect(t1?.mimeType, 'text/html');
    final (s2, b2, t2) = await get('/main.dart.js');
    expect(s2, 200);
    expect(b2, contains('console'));
    expect(t2?.mimeType, 'text/javascript');
    expect((await get('/room/ABC12')).$2, contains('aurora-web'));
    expect((await get('/missing.js')).$1, 404);
  });

  test('path traversal is refused', () async {
    for (final p in ['/../secret.txt', '/%2e%2e/secret.txt', '/..%2fsecret.txt', '/..%5csecret.txt']) {
      final (s, b, _) = await get(p);
      expect(b, isNot(contains('secret')), reason: p);
      expect(s == 404 || s == 400 || b.contains('aurora-web'), isTrue, reason: p);
    }
  });

  test('plain GET on /ws is rejected', () async {
    expect((await get('/ws')).$1, 400);
  });

  test('a WebSocket client logs in, creates a room and chats', () async {
    final ws = await WebSocket.connect('ws://127.0.0.1:$webPort/ws');
    final dec = FrameDecoder(maxFrame: kMaxServerFrame);
    final hs = ClientHandshake();
    SecureChannel? ch;
    final ready = Completer<void>();
    final msgs = StreamController<Map<String, dynamic>>.broadcast();
    ws.listen((d) {
      for (final f in dec.add(d as List<int>)) {
        if (ch == null) {
          ch = hs.finish(f.json).$1;
          ready.complete();
          continue;
        }
        msgs.add(Frame(f.kind, ch!.open(f.kind, f.payload)).json);
      }
    });
    void send(Map<String, dynamic> m) => ws.add(encodeFrame(kFrameJson, ch!.seal(kFrameJson, utf8.encode(jsonEncode(m)))));
    Future<Map<String, dynamic>> waitT(String t) => msgs.stream.firstWhere((m) => m['t'] == t).timeout(const Duration(seconds: 5));

    ws.add(encodeJson(hs.hello()));
    await ready.future.timeout(const Duration(seconds: 5));
    final welcome = waitT(Msg.welcome);
    send({'t': Msg.hello, 'ver': kProtocolVersion, 'name': '网页玩家', 'avatar': 2, 'token': ''});
    final w = await welcome;
    expect(w['name'], '网页玩家');
    expect(server.onlineClients.map((c) => c.name), contains('网页玩家'));

    final room = msgs.stream.firstWhere((m) => m['t'] == Msg.room && m['room'] != null).timeout(const Duration(seconds: 5));
    send({'t': Msg.createRoom, 'game': 'tictactoe'});
    expect((await room)['room']['game'], 'tictactoe');

    final chat = waitT(Msg.chatMsg);
    send({'t': Msg.chat, 'text': 'hello from browser'});
    expect((await chat)['text'], 'hello from browser');

    await ws.close();
    await Future.delayed(const Duration(milliseconds: 200));
    expect(server.onlineClients.map((c) => c.name), isNot(contains('网页玩家')));
  });

  test('server without a web dir answers with a hint page', () async {
    final s = AuroraServer(port + 1, webPort: 0, dataDir: Directory('${tmp.path}/d2'), replayDir: Directory('${tmp.path}/r2'));
    await s.start();
    try {
      final c = HttpClient();
      final res = await (await c.getUrl(Uri.parse('http://127.0.0.1:${s.webBoundPort}/'))).close();
      expect(await res.transform(utf8.decoder).join(), contains('没有部署网页客户端'));
      c.close(force: true);
    } finally {
      await s.stop();
    }
  });
}
