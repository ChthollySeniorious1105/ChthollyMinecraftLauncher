import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cml_core/tunnel.dart';
import 'package:cmls/cmls.dart';
import 'package:test/test.dart';

/// Fake Bedrock server: answers Unconnected Ping with a pong and echoes every other datagram as `0xEE | data`.
Future<RawDatagramSocket> fakeBedrock({String motd = 'Fake BDS'}) async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  s.listen((e) {
    if (e != RawSocketEvent.read) return;
    Datagram? d;
    while ((d = s.receive()) != null) {
      final t = RakNet.parsePing(d!.data);
      if (t != null) {
        final info = BedrockServerInfo(motd: motd, protocol: 766, version: '1.21.50', players: 1, maxPlayers: 8, guid: '42', port4: s.port);
        s.send(RakNet.pong(t, 42, info.encode()), d.address, d.port);
      } else {
        s.send([0xEE, ...d.data], d.address, d.port);
      }
    }
  });
  return s;
}

/// UDP "game client": collects received datagrams.
class UdpProbe {
  final RawDatagramSocket sock;
  final _rx = StreamController<Uint8List>.broadcast();
  UdpProbe._(this.sock) {
    sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = sock.receive()) != null) {
        _rx.add(d!.data);
      }
    });
  }
  static Future<UdpProbe> open() async => UdpProbe._(await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0));

  /// Sends [data] to [port] (retrying, since UDP may be dropped while flows are being set up) until [match].
  Future<Uint8List> roundTrip(int port, List<int> data, bool Function(Uint8List) match, {Duration timeout = const Duration(seconds: 5)}) async {
    final got = _rx.stream.firstWhere(match);
    sock.send(data, InternetAddress.loopbackIPv4, port);
    final t = Timer.periodic(const Duration(milliseconds: 300), (_) => sock.send(data, InternetAddress.loopbackIPv4, port));
    try {
      return await got.timeout(timeout);
    } finally {
      t.cancel();
    }
  }

  void close() {
    sock.close();
    _rx.close();
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  late CmlsServer server;
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cmlsb');
    server = CmlsServer(ServerConfig(port: 0, name: 'Test', publicUdpPort: -1), ServerIdentity.fromSeed(ServerIdentity.newSeed()), log: (_) {});
    await server.start(bind: InternetAddress.loopbackIPv4);
  });

  tearDown(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  test('pingBedrock / detect parse a pong', () async {
    final bds = await fakeBedrock(motd: 'Detect me');
    final info = await TunnelClient.pingBedrock(InternetAddress.loopbackIPv4, bds.port);
    expect(info, isNotNull);
    expect(info!.motd, 'Detect me');
    expect(info.version, '1.21.50');
    expect(info.protocol, 766);
    final det = await TunnelClient.detectLocalBedrock(ports: [bds.port]);
    expect(det?.$2, bds.port);
    expect(await TunnelClient.pingBedrock(InternetAddress.loopbackIPv4, 9, timeout: const Duration(milliseconds: 300)), isNull);
    bds.close();
  });

  test('bedrock room relays UDP datagrams end-to-end and answers LAN pings', () async {
    final bds = await fakeBedrock();
    final addr = '127.0.0.1:${server.port}';
    final host = TunnelClient(addr, KnownServers('${tmp.path}/a.json'));
    await host.connect(name: 'Host');
    final room = await host.hostBedrock(title: '基岩测试', udpPort: bds.port, password: 'pw');
    expect(host.isBedrock, isTrue);
    expect(host.bedrockInfo?.version, '1.21.50');
    expect(host.publicUdpPort, isNull); // locked rooms never go public

    final guest = TunnelClient(addr, KnownServers('${tmp.path}/b.json'));
    await guest.connect(name: 'Guest');
    final list = await guest.rooms();
    expect(list.single.isBedrock, isTrue);
    expect(list.single.version, '1.21.50');

    final localPort = await guest.join(room, password: 'pw');
    expect(guest.isBedrock, isTrue);
    expect(localPort, guest.bedrockLocalPort);
    expect(guest.bedrockLanDiscoverable, localPort == RakNet.defaultPort4);

    final game = await UdpProbe.open();
    // LAN discovery: the guest answers pings itself with the room's pong
    final pong = await game.roundTrip(localPort, RakNet.ping(555, 1), (d) => d.isNotEmpty && d[0] == RakNet.unconnectedPong);
    final (time, _, str) = RakNet.parsePong(pong)!;
    expect(time, 555);
    final info = BedrockServerInfo.parse(str)!;
    expect(info.motd, '基岩测试');
    expect(info.version, '1.21.50');
    expect(info.protocol, 766);
    expect(info.port4, localPort);

    // game datagrams travel guest → CMLS → host → fake BDS and back, boundaries intact
    final msg = Uint8List.fromList([0x05, ...RakNet.magic, 11, 1, 2, 3]);
    final echo = await game.roundTrip(localPort, msg, (d) => d.isNotEmpty && d[0] == 0xEE);
    expect(echo.sublist(1), msg);
    for (final n in [1, 500, 1400, 2000]) {
      final m = Uint8List.fromList(List.generate(n, (i) => (i * 7 + n) & 0xff))..[0] = 0x84;
      final e = await game.roundTrip(localPort, m, (d) => d.length == n + 1 && d[0] == 0xEE && _eq(d.sublist(1), m));
      expect(e.length, n + 1);
    }
    expect(host.udpFlowCount, 1);
    expect(server.rooms[room]!.flows.length, 1);

    // a second local client endpoint gets its own flow
    final game2 = await UdpProbe.open();
    final e2 = await game2.roundTrip(localPort, [0x84, 9, 9], (d) => d.isNotEmpty && d[0] == 0xEE);
    expect(e2, [0xEE, 0x84, 9, 9]);
    expect(server.rooms[room]!.flows.length, 2);

    // oversize datagrams are dropped, not forwarded
    game.sock.send(Uint8List(TunnelLimits.maxDatagram + 10), InternetAddress.loopbackIPv4, localPort);

    // leaving tears flows down on the server and host
    await guest.leave();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.rooms[room]!.flows, isEmpty);
    expect(host.udpFlowCount, 0);

    game.close();
    game2.close();
    await guest.close();
    await host.close();
    bds.close();
  });

  test('public UDP endpoint answers pings and relays internet clients to the host', () async {
    final bds = await fakeBedrock();
    final addr = '127.0.0.1:${server.port}';
    final host = TunnelClient(addr, KnownServers('${tmp.path}/a.json'));
    await host.connect(name: 'Host');
    final room = await host.hostBedrock(title: 'Public World', udpPort: bds.port, publicUdp: true);
    expect(host.publicUdpPort, server.publicUdpPort);
    expect(server.publicRoom?.id, room);
    final pub = server.publicUdpPort!;

    final game = await UdpProbe.open();
    final pong = await game.roundTrip(pub, RakNet.ping(77, 3), (d) => d.isNotEmpty && d[0] == RakNet.unconnectedPong);
    final info = BedrockServerInfo.parse(RakNet.parsePong(pong)!.$3)!;
    expect(info.motd, 'Public World');
    expect(info.subMotd, 'Test');
    expect(info.port4, pub);

    // random junk does not open a flow
    game.sock.send([0x84, 1, 2, 3], InternetAddress.loopbackIPv4, pub);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.rooms[room]!.flows, isEmpty);

    // Open Connection Request 1 opens a flow; then normal traffic flows both ways
    final ocr1 = Uint8List.fromList([RakNet.openConnectionRequest1, ...RakNet.magic, 11, ...List.filled(64, 0)]);
    final e = await game.roundTrip(pub, ocr1, (d) => d.isNotEmpty && d[0] == 0xEE);
    expect(e.sublist(1), ocr1);
    final e2 = await game.roundTrip(pub, [0x84, 4, 5, 6], (d) => d.length == 5 && d[0] == 0xEE);
    expect(e2, [0xEE, 0x84, 4, 5, 6]);
    expect(server.rooms[room]!.flows.values.single.isPublic, isTrue);

    // per-IP flow cap: the probe IP may open at most publicUdpMaxPerIp flows
    final extra = <UdpProbe>[];
    for (var i = 0; i < server.config.publicUdpMaxPerIp + 2; i++) {
      final p = await UdpProbe.open();
      extra.add(p);
      p.sock.send(ocr1, InternetAddress.loopbackIPv4, pub);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.rooms[room]!.publicFlows.length, server.config.publicUdpMaxPerIp);

    // a second room cannot steal the public port
    final host2 = TunnelClient(addr, KnownServers('${tmp.path}/c.json'));
    await host2.connect(name: 'Host2');
    await host2.hostBedrock(title: 'Other', udpPort: bds.port, publicUdp: true);
    expect(host2.publicUdpPort, isNull);
    expect(server.publicRoom?.id, room);

    // closing the room frees the endpoint: pings go unanswered
    await host.leave();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.publicRoom, isNull);
    await expectLater(game.roundTrip(pub, RakNet.ping(1, 1), (d) => d[0] == RakNet.unconnectedPong, timeout: const Duration(milliseconds: 700)),
        throwsA(isA<TimeoutException>()));

    for (final p in extra) {
      p.close();
    }
    game.close();
    await host.close();
    await host2.close();
    bds.close();
  });

  test('java rooms are unaffected and report edition java', () async {
    final addr = '127.0.0.1:${server.port}';
    final host = TunnelClient(addr, KnownServers('${tmp.path}/a.json'));
    await host.connect(name: 'Host');
    await host.host(title: 'J', lanPort: 1);
    final guest = TunnelClient(addr, KnownServers('${tmp.path}/b.json'));
    await guest.connect(name: 'Guest');
    expect((await guest.rooms()).single.edition, 'java');
    await guest.close();
    await host.close();
  });
}
