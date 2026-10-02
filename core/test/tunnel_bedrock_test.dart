import 'dart:typed_data';

import 'package:cml_core/tunnel.dart';
import 'package:test/test.dart';

void main() {
  group('RakNet offline messages', () {
    test('ping encode / parse (0x01 and 0x02)', () {
      final p = RakNet.ping(123456789, -42);
      expect(p.length, 33);
      expect(p[0], 0x01);
      expect(p.sublist(9, 25), RakNet.magic);
      expect(RakNet.parsePing(p), 123456789);
      final open = RakNet.ping(7, 1, openConnections: true);
      expect(open[0], 0x02);
      expect(RakNet.parsePing(open), 7);
      // bad magic / wrong id / too short
      final bad = Uint8List.fromList(p)..[10] ^= 1;
      expect(RakNet.parsePing(bad), isNull);
      expect(RakNet.parsePing(Uint8List.fromList([0x05, ...p.sublist(1)])), isNull);
      expect(RakNet.parsePing(Uint8List.sublistView(p, 0, 20)), isNull);
    });

    test('pong encode / parse with server-id string', () {
      const info = BedrockServerInfo(
        motd: '我的世界',
        protocol: 766,
        version: '1.21.50',
        players: 2,
        maxPlayers: 10,
        guid: '12345678901234567890',
        subMotd: 'Bedrock level',
        gameMode: 'Creative',
        gameModeNum: 1,
        port4: 19132,
        port6: 19133,
      );
      final s = info.encode();
      expect(s, 'MCPE;我的世界;766;1.21.50;2;10;12345678901234567890;Bedrock level;Creative;1;19132;19133;');
      final pong = RakNet.pong(99, RakNet.guidToInt(info.guid), s);
      expect(pong[0], 0x1c);
      final (time, guid, str) = RakNet.parsePong(pong)!;
      expect(time, 99);
      expect(BigInt.from(guid).toUnsigned(64).toString(), '12345678901234567890');
      final back = BedrockServerInfo.parse(str)!;
      expect(back.motd, '我的世界');
      expect(back.protocol, 766);
      expect(back.version, '1.21.50');
      expect(back.players, 2);
      expect(back.maxPlayers, 10);
      expect(back.gameMode, 'Creative');
      expect(back.port4, 19132);
      expect(back.port6, 19133);
      expect(RakNet.parsePong(Uint8List.sublistView(pong, 0, pong.length - 1)), isNull);
    });

    test('server-id fields are sanitised', () {
      final s = const BedrockServerInfo(motd: 'a;b\nc', version: '1.0').encode();
      expect(s.split(';')[1], 'a,bc');
      expect(BedrockServerInfo.parse('garbage'), isNull);
      // older servers send fewer fields
      final short = BedrockServerInfo.parse('MCPE;Old;100;1.0;0;5')!;
      expect(short.motd, 'Old');
      expect(short.port4, 19132);
    });

    test('json wire form clamps untrusted values', () {
      final i = BedrockServerInfo.fromJson({'motd': 'x' * 500, 'protocol': -5, 'players': 1e12, 'guid': '12; drop', 'edition': 'evil'});
      expect(i.motd.length, 64);
      expect(i.protocol, 0);
      expect(i.players, 100000);
      expect(i.guid, '');
      expect(i.edition, 'MCPE');
      final rt = BedrockServerInfo.fromJson(const BedrockServerInfo(motd: 'm', protocol: 5, version: 'v', guid: '1').toJson());
      expect([rt.motd, rt.protocol, rt.version, rt.guid], ['m', 5, 'v', '1']);
    });
  });

  group('datagram frames', () {
    test('round-trip through encoder / decoder keeps boundaries', () {
      final a = Uint8List.fromList(List.generate(1400, (i) => i & 0xff));
      final b = Uint8List.fromList([1, 2, 3]);
      final empty = Uint8List(0);
      final bytes = [
        ...Frame.encode(FrameKind.datagram, Frame.datagramPayload(7, a)),
        ...Frame.encode(FrameKind.datagram, Frame.datagramPayload(0xfffffffe, b)),
        ...Frame.encode(FrameKind.datagram, Frame.datagramPayload(1, empty)),
      ];
      final dec = FrameDecoder();
      // feed in awkward chunks
      final frames = <Frame>[];
      for (var i = 0; i < bytes.length; i += 333) {
        frames.addAll(dec.add(bytes.sublist(i, (i + 333).clamp(0, bytes.length))));
      }
      expect(frames.length, 3);
      expect(frames.every((f) => f.kind == FrameKind.datagram), isTrue);
      final d0 = Frame.parseDatagram(frames[0].payload)!;
      expect(d0.$1, 7);
      expect(d0.$2, a);
      final d1 = Frame.parseDatagram(frames[1].payload)!;
      expect(d1.$1, 0xfffffffe);
      expect(d1.$2, b);
      expect(Frame.parseDatagram(frames[2].payload)!.$2, isEmpty);
    });

    test('oversize and short datagrams are rejected', () {
      expect(Frame.parseDatagram(Frame.datagramPayload(1, Uint8List(TunnelLimits.maxDatagram))), isNotNull);
      expect(Frame.parseDatagram(Frame.datagramPayload(1, Uint8List(TunnelLimits.maxDatagram + 1))), isNull);
      expect(Frame.parseDatagram(Uint8List(3)), isNull);
    });

    test('sealed datagram frames authenticate the kind byte', () {
      final id = ServerIdentity.fromSeed(ServerIdentity.newSeed());
      final c = ClientHandshake();
      final (reply, sch) = ServerHandshake(id).respond(c.hello());
      final (cch, _) = c.finish(reply);
      final payload = Frame.datagramPayload(3, [9, 9, 9]);
      final sealed = cch.seal(FrameKind.datagram, payload);
      expect(sch.open(FrameKind.datagram, sealed), payload);
      final again = cch.seal(FrameKind.datagram, payload);
      expect(() => sch.open(FrameKind.data, again), throwsA(anything));
    });
  });

  test('token bucket drops when over budget', () {
    final b = TokenBucket(packetRate: 10, byteRate: 1000, packetBurst: 5, byteBurst: 1000);
    var ok = 0;
    for (var i = 0; i < 20; i++) {
      if (b.allow(10)) ok++;
    }
    expect(ok, 5);
    final big = TokenBucket(packetRate: 1000, byteRate: 100, packetBurst: 1000, byteBurst: 100);
    expect(big.allow(150), isFalse);
    expect(big.allow(80), isTrue);
  });

  test('RoomInfo edition defaults to java', () {
    expect(RoomInfo.fromJson({'room': 'A', 'title': 't', 'host': 'h'}).isBedrock, isFalse);
    expect(RoomInfo.fromJson({'room': 'A', 'title': 't', 'host': 'h', 'edition': 'bedrock'}).isBedrock, isTrue);
  });
}
