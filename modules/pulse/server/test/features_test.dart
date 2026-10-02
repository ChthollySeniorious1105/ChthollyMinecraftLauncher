import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_server/server.dart';
import 'package:pulse_shared/pulse_shared.dart';
import 'package:test/test.dart';

import 'server_test.dart' show TC;

/// Roles / permissions, direct messages, attachments, screen share relay.
void main() {
  late Directory tmp;
  late PulseServer server;
  late int port;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pulse_test2');
    final store = Store(Directory('${tmp.path}/data'))..load();
    server = PulseServer(0, store: store, identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
    port = server.boundPort;
  });

  tearDown(() async {
    await server.stop();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('roles: permissions, hierarchy, channel overwrites', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'own', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'mod', 'pass': 'password123'});
    final c = await TC.connect(port);
    await c.auth({'t': Msg.register, 'user': 'pleb', 'pass': 'password123'});

    // owner creates a moderator role that can manage roles + kick, gives it to b
    a.send({'t': Msg.roleCreate, 'name': '版主'});
    final roles = await b.wait(Msg.roles, (m) => (m['roles'] as List).any((r) => r['name'] == '版主'));
    final modId = (roles['roles'] as List).firstWhere((r) => r['name'] == '版主')['id'] as int;
    a.send({'t': Msg.roleUpdate, 'id': modId, 'perms': Perm.everyoneDefault | Perm.manageRoles | Perm.kickMembers | Perm.manageChannels});
    await b.wait(Msg.roles, (m) => (m['roles'] as List).any((r) => r['id'] == modId && (r['perms'] as int) & Perm.kickMembers != 0));
    a.send({'t': Msg.memberRoles, 'id': b.me, 'roles': [modId]});
    await b.wait(Msg.member, (m) => (m['m'] as Map)['id'] == b.me && ((m['m'] as Map)['roles'] as List).contains(modId));

    // b creates a role (placed below its own) but can't grant what it doesn't have or edit its own role
    b.send({'t': Msg.roleCreate, 'name': '小号'});
    final r2 = await b.wait(Msg.roles, (m) => (m['roles'] as List).any((r) => r['name'] == '小号'));
    final small = (r2['roles'] as List).firstWhere((r) => r['name'] == '小号');
    final mod = (r2['roles'] as List).firstWhere((r) => r['id'] == modId);
    expect(small['pos'] as int, lessThan(mod['pos'] as int), reason: 'created below the creator');
    b.send({'t': Msg.roleUpdate, 'id': small['id'], 'perms': Perm.administrator});
    expect((await b.wait(Msg.error))['msg'], contains('没有的权限'));
    b.send({'t': Msg.roleUpdate, 'id': modId, 'name': 'x'});
    expect((await b.wait(Msg.error))['msg'], contains('低'));
    // ... nor kick the owner
    b.send({'t': Msg.kick, 'id': a.me});
    expect((await b.wait(Msg.error))['msg'], contains('不能'));
    // c has no permission to create channels
    c.send({'t': Msg.chCreate, 'name': 'x', 'kind': 'text'});
    expect((await c.wait(Msg.error))['msg'], contains('权限'));

    // private channel: hidden from @everyone, visible to 版主
    b.send({'t': Msg.chCreate, 'name': '内部', 'kind': 'text'});
    final chs = await b.wait(Msg.channels, (m) => (m['channels'] as List).any((x) => x['name'] == '内部'));
    final secret = (chs['channels'] as List).firstWhere((x) => x['name'] == '内部')['id'] as int;
    a.send({
      't': Msg.channelPerms,
      'id': secret,
      'ow': [
        {'id': RoleDef.everyone, 'allow': 0, 'deny': Perm.viewChannel},
        {'id': modId, 'allow': Perm.viewChannel, 'deny': 0},
      ],
    });
    await c.wait(Msg.channels, (m) => !(m['channels'] as List).any((x) => x['id'] == secret));
    final bl = await b.wait(Msg.channels, (m) => (m['channels'] as List).any((x) => x['id'] == secret));
    final mine = (bl['channels'] as List).firstWhere((x) => x['id'] == secret);
    expect((mine['perms'] as int) & Perm.viewChannel, isNonZero);
    b.send({'t': Msg.sendMsg, 'ch': secret, 'text': '机密'});
    await b.wait(Msg.message, (m) => m['ch'] == secret);
    c.send({'t': Msg.history, 'ch': secret});
    c.send({'t': Msg.search, 'q': '机密'});
    final sr = await c.wait(Msg.searchResult);
    expect(sr['msgs'], isEmpty, reason: 'search must not leak hidden channels');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.msgs.where((m) => m['t'] == Msg.message || m['t'] == Msg.historyData), isEmpty);

    // read-only channel: @everyone can't send
    final general = server.store.channels.values.firstWhere((x) => x.kind == ChannelKind.text).id;
    a.send({
      't': Msg.channelPerms,
      'id': general,
      'ow': [
        {'id': RoleDef.everyone, 'allow': 0, 'deny': Perm.sendMessages},
      ],
    });
    await c.wait(Msg.channels, (m) => ((m['channels'] as List).firstWhere((x) => x['id'] == general)['perms'] as int) & Perm.sendMessages == 0);
    c.send({'t': Msg.sendMsg, 'ch': general, 'text': 'hi'});
    expect((await c.wait(Msg.error))['msg'], contains('发言'));

    b.send({'t': Msg.kick, 'id': c.me});
    expect((await c.wait(Msg.error))['fatal'], true);
    a.close();
    b.close();
  });

  test('legacy admin accounts migrate to an 管理员 role', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'old1', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'old2', 'pass': 'password123'});
    a.close();
    b.close();
    await server.stop();
    // simulate a pre-roles data file: role 1 = admin
    final f = File('${tmp.path}/data/users.json');
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    for (final u in j['users'] as List) {
      if (u['user'] == 'old2') u['role'] = 1;
    }
    f.writeAsStringSync(jsonEncode(j));
    final store2 = Store(Directory('${tmp.path}/data'))..load();
    final u2 = store2.userByName('old2')!;
    expect(u2.role, Role.member);
    final r = store2.roles[u2.roles.single]!;
    expect(r.name, '管理员');
    expect(r.perms & Perm.kickMembers, isNonZero);
    server = PulseServer(0, store: store2, identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
  });

  test('direct messages are private', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'dma', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'dmb', 'pass': 'password123'});
    final c = await TC.connect(port);
    await c.auth({'t': Msg.register, 'user': 'dmc', 'pass': 'password123'});
    a.send({'t': Msg.dmOpen, 'uid': b.me});
    final dm = (await a.wait(Msg.dm))['c'] as Map;
    final id = dm['id'] as int;
    expect(dm['kind'], ChannelKind.dm);
    expect(dm['members'], containsAll([a.me, b.me]));
    a.send({'t': Msg.sendMsg, 'ch': id, 'text': '悄悄话'});
    expect(((await b.wait(Msg.dm))['c'] as Map)['id'], id, reason: 'recipient gets the DM channel with the first message');
    expect(((await b.wait(Msg.message))['m'] as Map)['text'], '悄悄话');
    c.send({'t': Msg.history, 'ch': id});
    c.send({'t': Msg.sendMsg, 'ch': id, 'text': 'intrude'});
    expect((await c.wait(Msg.error))['msg'], contains('不存在'));
    expect(c.msgs.where((m) => m['t'] == Msg.message), isEmpty);
    // same pair → same channel
    b.send({'t': Msg.dmOpen, 'uid': a.me});
    expect(((await b.wait(Msg.dm))['c'] as Map)['id'], id);
    a.close();
    b.close();
    c.close();
  });

  test('file upload / download over auxiliary connections, quota, expiry', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'up', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'down', 'pass': 'password123'});
    final ch = server.store.channels.values.firstWhere((x) => x.kind == ChannelKind.text).id;
    final pin = base64.encode(server.identity.publicKey);
    final src = File('${tmp.path}/src.bin');
    final data = Uint8List.fromList(List.generate(1000000, (i) => (i * 31) & 255));
    src.writeAsBytesSync(data);

    a.send({'t': Msg.uploadRequest, 'ch': ch, 'name': '../../evil:name?.bin', 'size': data.length, 'nonce': 'n1'});
    final tk = await a.wait(Msg.uploadTicket);
    final fid = tk['id'] as String;
    var progress = 0;
    await uploadFile(address: '127.0.0.1:$port', pinnedKey: pin, ticket: tk['ticket'] as String, path: src.path, onProgress: (d) => progress = d);
    expect(progress, data.length);
    expect(server.store.files[fid]!.complete, isTrue);
    expect(server.store.files[fid]!.name, isNot(contains('/')));
    // tickets are single use
    await expectLater(
        uploadFile(address: '127.0.0.1:$port', pinnedKey: pin, ticket: tk['ticket'] as String, path: src.path), throwsA(isA<TransferException>()));
    // a different server identity is refused by the client
    a.send({'t': Msg.uploadRequest, 'ch': ch, 'name': 'x', 'size': 1, 'nonce': 'n9'});
    final tk9 = await a.wait(Msg.uploadTicket);
    await expectLater(
        uploadFile(address: '127.0.0.1:$port', pinnedKey: base64.encode(List.filled(32, 1)), ticket: tk9['ticket'] as String, path: src.path),
        throwsA(isA<TransferException>()));
    a.send({'t': Msg.uploadCancel, 'id': tk9['id']}); // releases its quota reservation

    a.send({'t': Msg.sendMsg, 'ch': ch, 'text': '', 'att': [fid], 'nonce': 'm1'});
    final msg = (await b.wait(Msg.message))['m'] as Map;
    expect((msg['att'] as List).single['id'], fid);
    expect((msg['att'] as List).single['exp'] as int, greaterThan(DateTime.now().millisecondsSinceEpoch));
    // the same upload can't be attached twice
    a.send({'t': Msg.sendMsg, 'ch': ch, 'text': 'again', 'att': [fid]});
    expect((await a.wait(Msg.error))['msg'], contains('附件'));

    b.send({'t': Msg.fileRequest, 'id': fid});
    final ft = await b.wait(Msg.fileTicket);
    final dst = File('${tmp.path}/dst.bin');
    await downloadFile(address: '127.0.0.1:$port', pinnedKey: pin, ticket: ft['ticket'] as String, path: dst.path);
    expect(dst.readAsBytesSync(), data);
    // resume from the middle
    dst.writeAsBytesSync(data.sublist(0, 300000));
    b.send({'t': Msg.fileRequest, 'id': fid});
    final ft2 = await b.wait(Msg.fileTicket);
    await downloadFile(address: '127.0.0.1:$port', pinnedKey: pin, ticket: ft2['ticket'] as String, path: dst.path, offset: 300000);
    expect(dst.readAsBytesSync(), data);

    // 2 GiB hard cap and per-file limit
    a.send({'t': Msg.uploadRequest, 'ch': ch, 'name': 'huge', 'size': kMaxFileBytes + 1, 'nonce': 'n2'});
    expect((await a.wait(Msg.error))['msg'], contains('过大'));
    server.setStorage(fileMaxMB: 1);
    a.send({'t': Msg.uploadRequest, 'ch': ch, 'name': 'big', 'size': 2 * 1024 * 1024, 'nonce': 'n3'});
    expect((await a.wait(Msg.error))['msg'], contains('过大'));

    // quota: a new 1 MB upload with a 1 MB quota evicts the oldest file
    server.setStorage(maxMB: 1, fileMaxMB: 1);
    await b.wait(Msg.server, (m) => m['storageMB'] == 1);
    a.send({'t': Msg.uploadRequest, 'ch': ch, 'name': 'new.bin', 'size': 1024 * 1024, 'nonce': 'n4'});
    final gone = await b.wait(Msg.filesGone);
    expect(gone['ids'], [fid]);
    expect(server.store.fileData(fid).existsSync(), isFalse);
    await a.wait(Msg.uploadTicket, (m) => m['nonce'] == 'n4');
    b.send({'t': Msg.fileRequest, 'id': fid});
    expect((await b.wait(Msg.error))['msg'], contains('过期'));

    // expiry after the retention time
    final fresh = server.store.files.values.firstWhere((f) => f.name == 'new.bin');
    server.store.files[fresh.id] = FileRec(fresh.id, fresh.name, fresh.size, fresh.uid, fresh.ch, 0)
      ..complete = true
      ..msg = 1;
    server.setStorage(days: 7);
    expect(server.store.files.containsKey(fresh.id), isFalse);
    a.close();
    b.close();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('screen share relay: only viewers get frames, keyframe requests', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'streamer', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'viewer', 'pass': 'password123'});
    final vch = server.store.channels.values.firstWhere((x) => x.kind == ChannelKind.voice).id;
    a.send({'t': Msg.streamStart, 'w': 1280, 'h': 720, 'fps': 30});
    expect((await a.wait(Msg.error))['msg'], contains('语音'));
    a.send({'t': Msg.voiceJoin, 'ch': vch});
    await a.wait(Msg.voiceUser, (m) => m['id'] == a.me);
    a.send({'t': Msg.streamStart, 'w': 1280, 'h': 720, 'fps': 30, 'title': '桌面'});
    final st = await b.wait(Msg.streams, (m) => (m['streams'] as List).isNotEmpty);
    expect((st['streams'] as List).single['uid'], a.me);

    Future<MediaClient> media(TC c) async {
      c.send({'t': Msg.mediaRequest});
      final t = await c.wait(Msg.mediaTicket);
      return MediaClient.connect(port, t['ticket'] as String);
    }

    final ma = await media(a);
    final mb = await media(b);
    b.send({'t': Msg.watch, 'uid': a.me, 'on': true});
    await a.wait(Msg.keyframeRequest);
    await b.wait(Msg.streams, (m) => ((m['streams'] as List).single['viewers'] as List).contains(b.me));
    ma.sendVideo(true, [0, 0, 0, 1, 0x65, 1, 2, 3]);
    ma.sendVideo(false, [0, 0, 0, 1, 0x41, 9]);
    await until(() => mb.frames.length == 2);
    expect(ByteData.sublistView(mb.frames[0]).getUint32(0), a.me);
    expect(mb.frames[0][4], kVideoKey);
    expect(mb.frames[1].sublist(5), [0, 0, 0, 1, 0x41, 9]);
    b.send({'t': Msg.watch, 'uid': a.me, 'on': false});
    await b.wait(Msg.streams, (m) => ((m['streams'] as List).single['viewers'] as List).isEmpty);
    ma.sendVideo(true, [7]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(mb.frames, hasLength(2));
    a.send({'t': Msg.voiceLeave});
    await b.wait(Msg.streams, (m) => (m['streams'] as List).isEmpty);
    ma.close();
    mb.close();
    a.close();
    b.close();
  });
}

Future<void> until(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Test media connection (screen share).
class MediaClient {
  late Socket s;
  late SecureChannel ch;
  final frames = <Uint8List>[];

  static Future<MediaClient> connect(int port, String ticket) async {
    final c = MediaClient();
    c.s = await Socket.connect('127.0.0.1', port);
    final dec = FrameDecoder(maxFrame: kMaxMediaFrame);
    final hs = ClientHandshake();
    final ready = Completer<void>();
    var hello = false;
    c.s.listen((d) {
      for (final f in dec.add(d)) {
        if (!hello) {
          hello = true;
          c.ch = hs.finish(f.json).$1;
          c.s.add(encodeFrame(kFrameJson, c.ch.seal(kFrameJson, utf8.encode(jsonEncode({'t': Msg.aux, 'ticket': ticket, 'kind': 'media'})))));
          continue;
        }
        final p = c.ch.open(f.kind, f.payload);
        if (f.kind == kFrameJson && !ready.isCompleted) ready.complete();
        if (f.kind == kFrameVideo) c.frames.add(p);
      }
    });
    c.s.add(encodeJson(hs.hello()));
    await ready.future.timeout(const Duration(seconds: 5));
    return c;
  }

  void sendVideo(bool key, List<int> au) => s.add(encodeFrame(kFrameVideo, ch.seal(kFrameVideo, [key ? kVideoKey : 0, ...au])));
  void close() => s.destroy();
}
