import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cml_core/tunnel.dart';
import 'package:cmls/cmls.dart';
import 'package:test/test.dart';

void main() {
  late CmlsServer server;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cmls');
    server = CmlsServer(ServerConfig(port: 0, name: 'Test'), ServerIdentity.fromSeed(ServerIdentity.newSeed()), log: (_) {});
    await server.start(bind: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  test('host and guest relay a TCP stream end-to-end', () async {
    // fake "Minecraft LAN" server on the host: echoes uppercase
    final mc = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    mc.listen((s) => s.listen((d) => s.add(utf8.encode(utf8.decode(d).toUpperCase()))));

    final addr = '127.0.0.1:${server.port}';
    final host = TunnelClient(addr, KnownServers('${tmp.path}/a.json'));
    await host.connect(name: 'Host');
    final room = await host.host(title: '测试世界', lanPort: mc.port, version: '1.21.4', password: 'pw');
    expect(room.length, 5);

    final guest = TunnelClient(addr, KnownServers('${tmp.path}/b.json'));
    await guest.connect(name: 'Guest');
    final list = await guest.rooms();
    expect(list.single.title, '测试世界');
    expect(list.single.locked, isTrue);

    await expectLater(guest.join(room, password: 'wrong'), throwsA(isA<Exception>()));
    final localPort = await guest.join(room, password: 'pw');

    final s = await Socket.connect(InternetAddress.loopbackIPv4, localPort);
    final got = Completer<String>();
    final buf = StringBuffer();
    s.listen((d) {
      buf.write(utf8.decode(d));
      if (buf.length >= 11 && !got.isCompleted) got.complete(buf.toString());
    });
    s.add(utf8.encode('hello world'));
    expect(await got.future.timeout(const Duration(seconds: 5)), 'HELLO WORLD');

    // a big payload crosses chunk boundaries intact
    final big = List.generate(200000, (i) => 'abcdefghij'.codeUnitAt(i % 10));
    final got2 = Completer<int>();
    var n = 0;
    final s2 = await Socket.connect(InternetAddress.loopbackIPv4, localPort);
    s2.listen((d) {
      n += d.length;
      if (n >= big.length && !got2.isCompleted) got2.complete(n);
    });
    s2.add(big);
    expect(await got2.future.timeout(const Duration(seconds: 10)), big.length);

    await s.close();
    await s2.close();
    await guest.close();
    await host.close();
    await mc.close();
  });

  test('pinned identity change is rejected', () async {
    final known = KnownServers('${tmp.path}/k.json');
    final addr = '127.0.0.1:${server.port}';
    await known.pin(addr, base64.encode(List.filled(32, 7)));
    final c = TunnelClient(addr, known);
    await expectLater(c.connect(name: 'x'), throwsA(isA<IdentityChangedException>()));
    final c2 = TunnelClient(addr, known);
    await c2.connect(name: 'x', trustNewIdentity: true);
    expect(c2.connected, isTrue);
    await c2.close();
  });

  test('name sanitising', () {
    expect(CmlsServer.cleanName("  a${String.fromCharCode(0x202e)}bc  ", 32), "abc");
    expect(CmlsServer.cleanName('x' * 40, 32).length, 32);
  });
}
