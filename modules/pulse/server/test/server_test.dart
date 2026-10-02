import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pulse_server/server.dart';
import 'package:pulse_shared/pulse_shared.dart';
import 'package:test/test.dart';

/// Minimal encrypted test client.
class TC {
  late Socket s;
  late SecureChannel ch;
  final msgs = <Map<String, dynamic>>[];
  final voice = <Uint8List>[];
  final _waiters = <(bool Function(Map<String, dynamic>), Completer<Map<String, dynamic>>)>[];
  bool closed = false;
  String? token;
  int me = 0;

  static Future<TC> connect(int port) async {
    final c = TC();
    c.s = await Socket.connect('127.0.0.1', port);
    final dec = FrameDecoder();
    final hs = ClientHandshake();
    final ready = Completer<void>();
    c.s.listen((d) {
      for (final f in dec.add(d)) {
        if (!ready.isCompleted) {
          c.ch = hs.finish(f.json).$1;
          ready.complete();
          continue;
        }
        final p = c.ch.open(f.kind, f.payload);
        if (f.kind == kFrameVoice) {
          c.voice.add(p);
          continue;
        }
        final m = Frame(0, p).json;
        c.msgs.add(m);
        for (final w in c._waiters.toList()) {
          if (w.$1(m)) {
            c._waiters.remove(w);
            w.$2.complete(m);
          }
        }
      }
    }, onDone: () => c.closed = true, onError: (_) => c.closed = true);
    c.s.add(encodeJson(hs.hello()));
    await ready.future;
    return c;
  }

  void send(Map<String, dynamic> m) => s.add(encodeFrame(kFrameJson, ch.seal(kFrameJson, utf8.encode(jsonEncode(m)))));
  void sendVoice(List<int> p) => s.add(encodeFrame(kFrameVoice, ch.seal(kFrameVoice, p)));

  Future<Map<String, dynamic>> wait(String t, [bool Function(Map<String, dynamic>)? f]) {
    bool pred(Map<String, dynamic> m) => m['t'] == t && (f == null || f(m));
    for (final m in msgs) {
      if (pred(m)) {
        msgs.remove(m);
        return Future.value(m);
      }
    }
    final c = Completer<Map<String, dynamic>>();
    _waiters.add((
      (m) {
        if (!pred(m)) return false;
        msgs.remove(m);
        return true;
      },
      c
    ));
    return c.future.timeout(const Duration(seconds: 10));
  }

  Future<Map<String, dynamic>> auth(Map<String, dynamic> m) async {
    send({...m, 'ver': kProtocolVersion});
    final r = await Future.any([wait(Msg.authOk), wait(Msg.authErr)]);
    if (r['t'] == Msg.authOk) {
      token = r['token'] as String? ?? token;
      me = r['me'] as int;
      await wait(Msg.welcome);
    }
    return r;
  }

  void close() => s.destroy();
}

void main() {
  late Directory tmp;
  late PulseServer server;
  late int port;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pulse_test');
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

  test('register, first user is owner, login, resume, wrong password', () async {
    final a = await TC.connect(port);
    final r = await a.auth({'t': Msg.register, 'user': 'alice', 'pass': 'password123', 'display': '爱丽丝'});
    expect(r['t'], Msg.authOk);
    expect(server.store.users[a.me]!.role, Role.owner);
    expect(a.token, hasLength(64));
    // token is not stored in clear
    expect(server.store.sessions.keys.contains(a.token), isFalse);
    a.close();

    final b = await TC.connect(port);
    final bad = await b.auth({'t': Msg.login, 'user': 'alice', 'pass': 'nope-nope'});
    expect(bad['t'], Msg.authErr);
    final unknown = await b.auth({'t': Msg.login, 'user': 'nobody', 'pass': 'whatever1'});
    expect(unknown['msg'], bad['msg'], reason: 'same error for unknown users');
    final ok = await b.auth({'t': Msg.login, 'user': 'ALICE', 'pass': 'password123'});
    expect(ok['t'], Msg.authOk);
    b.close();

    final c = await TC.connect(port);
    final res = await c.auth({'t': Msg.resume, 'token': a.token});
    expect(res['t'], Msg.authOk);
    c.close();

    final d = await TC.connect(port);
    final res2 = await d.auth({'t': Msg.resume, 'token': 'f' * 64});
    expect(res2['code'], 'session');
    d.close();
  });

  test('login lockout after repeated failures', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'bob', 'pass': 'password123'});
    a.close();
    final b = await TC.connect(port);
    for (var i = 0; i < maxLoginFailures; i++) {
      expect((await b.auth({'t': Msg.login, 'user': 'bob', 'pass': 'wrongpass$i'}))['t'], Msg.authErr);
    }
    final locked = await b.auth({'t': Msg.login, 'user': 'bob', 'pass': 'password123'});
    expect(locked['code'], 'locked');
    b.close();
  });

  test('messages: send, history, edit, delete, reactions, permission', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'owner', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'member', 'pass': 'password123'});
    final ch = server.store.channels.values.firstWhere((c) => c.kind == ChannelKind.text).id;

    a.send({'t': Msg.sendMsg, 'ch': ch, 'text': 'hello\u202Eworld', 'nonce': 'x1'});
    final got = await b.wait(Msg.message);
    final m = got['m'] as Map<String, dynamic>;
    expect(m['text'], 'helloworld', reason: 'bidi override stripped');
    final id = m['id'] as int;

    b.send({'t': Msg.editMsg, 'ch': ch, 'id': id, 'text': 'hacked'});
    expect((await b.wait(Msg.error))['msg'], contains('自己'));

    a.send({'t': Msg.editMsg, 'ch': ch, 'id': id, 'text': 'hello world'});
    expect((await b.wait(Msg.messageEdited))['text'], 'hello world');

    b.send({'t': Msg.react, 'ch': ch, 'id': id, 'e': '👍'});
    expect((await a.wait(Msg.reaction))['uids'], [b.me]);

    b.send({'t': Msg.history, 'ch': ch});
    final h = await b.wait(Msg.historyData);
    expect((h['msgs'] as List).length, 1);

    b.send({'t': Msg.deleteMsg, 'ch': ch, 'id': id});
    expect((await b.wait(Msg.error))['msg'], contains('权限'));
    a.send({'t': Msg.deleteMsg, 'ch': ch, 'id': id});
    expect((await b.wait(Msg.messageDeleted))['id'], id);

    // too long
    a.send({'t': Msg.sendMsg, 'ch': ch, 'text': 'x' * (kMaxMessageLength + 1)});
    expect((await a.wait(Msg.error))['msg'], contains('超过'));

    // member can't create channels
    b.send({'t': Msg.chCreate, 'name': 'x', 'kind': 'text'});
    expect((await b.wait(Msg.error))['msg'], contains('权限'));
    a.close();
    b.close();
  });

  test('messages persist across restart', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'persist', 'pass': 'password123'});
    final ch = server.store.channels.values.firstWhere((c) => c.kind == ChannelKind.text).id;
    a.send({'t': Msg.sendMsg, 'ch': ch, 'text': '持久化测试'});
    await a.wait(Msg.message);
    a.close();
    await server.stop();
    final store2 = Store(Directory('${tmp.path}/data'))..load();
    expect(store2.users.values.single.username, 'persist');
    expect(store2.logs[ch]!.messages.single.text, '持久化测试');
    server = PulseServer(0, store: store2, identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
  });

  test('voice relay only within channel, respects mute/deaf/server mute', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'va', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'vb', 'pass': 'password123'});
    final c = await TC.connect(port);
    await c.auth({'t': Msg.register, 'user': 'vc', 'pass': 'password123'});
    final vchs = server.store.channels.values.where((x) => x.kind == ChannelKind.voice).toList();
    a.send({'t': Msg.voiceJoin, 'ch': vchs[0].id});
    b.send({'t': Msg.voiceJoin, 'ch': vchs[0].id});
    c.send({'t': Msg.voiceJoin, 'ch': vchs[1].id});
    await c.wait(Msg.voiceUser, (m) => m['id'] == c.me);
    await a.wait(Msg.voiceUser, (m) => m['id'] == b.me);
    a.sendVoice([0, 1, 9, 9, 9]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(b.voice, hasLength(1));
    expect(ByteData.sublistView(b.voice.single).getUint32(0), a.me);
    expect(b.voice.single.sublist(4), [0, 1, 9, 9, 9]);
    expect(c.voice, isEmpty);
    expect(a.voice, isEmpty);

    b.send({'t': Msg.voiceState, 'mute': false, 'deaf': true});
    await a.wait(Msg.voiceUser, (m) => m['id'] == b.me && m['deaf'] == true);
    a.sendVoice([0, 2, 1]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(b.voice, hasLength(1), reason: 'deafened users receive nothing');

    b.send({'t': Msg.voiceState, 'mute': false, 'deaf': false});
    await a.wait(Msg.voiceUser, (m) => m['id'] == b.me && m['deaf'] == false);
    a.send({'t': Msg.serverMute, 'id': b.me, 'on': true}); // a is owner
    await b.wait(Msg.voiceUser, (m) => m['id'] == b.me && m['smute'] == true);
    b.sendVoice([0, 3, 1]);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(a.voice, isEmpty, reason: 'server-muted users are not relayed');

    a.close();
    await b.wait(Msg.voiceUser, (m) => m['id'] == a.me && m['ch'] == null);
    b.close();
    c.close();
  });

  test('invite-only registration and ban', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'boss', 'pass': 'password123'});
    a.send({'t': Msg.serverSettings, 'regMode': RegMode.invite});
    await a.wait(Msg.server);
    final b = await TC.connect(port);
    expect((await b.auth({'t': Msg.register, 'user': 'guest', 'pass': 'password123'}))['code'], 'invite');
    a.send({'t': Msg.createInvite, 'uses': 1, 'hours': 1});
    final code = (await a.wait(Msg.inviteCode))['code'];
    expect((await b.auth({'t': Msg.register, 'user': 'guest', 'pass': 'password123', 'invite': code}))['t'], Msg.authOk);
    final c = await TC.connect(port);
    expect((await c.auth({'t': Msg.register, 'user': 'guest2', 'pass': 'password123', 'invite': code}))['code'], 'invite',
        reason: 'single-use invite');
    c.close();

    a.send({'t': Msg.ban, 'id': b.me, 'reason': 'test'});
    expect((await b.wait(Msg.error))['fatal'], true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(b.closed, isTrue);
    final d = await TC.connect(port);
    expect((await d.auth({'t': Msg.resume, 'token': b.token}))['t'], Msg.authErr);
    expect((await d.auth({'t': Msg.login, 'user': 'guest', 'pass': 'password123'}))['code'], 'banned');
    d.close();
    a.close();
  });

  test('tampered frame disconnects', () async {
    final a = await TC.connect(port);
    final sealed = a.ch.seal(kFrameJson, utf8.encode('{"t":"ping"}'));
    sealed[sealed.length - 1] ^= 1;
    a.s.add(encodeFrame(kFrameJson, sealed));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(a.closed, isTrue);
  });

  test('replayed frame disconnects', () async {
    final a = await TC.connect(port);
    final f = encodeFrame(kFrameJson, a.ch.seal(kFrameJson, utf8.encode('{"t":"ping","ver":1}')));
    a.s.add(f);
    a.s.add(f);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(a.closed, isTrue);
  });

  test('custom avatar upload, validation, download, removal', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'pic', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'viewer', 'pass': 'password123'});
    // minimal valid 64x64 PNG header + payload (validation reads only the header)
    final png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 64, 0, 0, 0, 64, 8, 6, 0, 0, 0, ...List.filled(200, 7)];
    a.send({'t': Msg.setAvatar, 'data': base64.encode(png)});
    final mm = await b.wait(Msg.member, (m) => (m['m'] as Map)['id'] == a.me && ((m['m'] as Map)['avh'] as String).isNotEmpty);
    final h = (mm['m'] as Map)['avh'] as String;
    expect(h, hasLength(64));
    b.send({'t': Msg.getAvatar, 'id': a.me, 'h': h});
    final data = await b.wait(Msg.avatarData);
    expect(base64.decode(data['data'] as String), png);

    // not an image / too big / too small are rejected
    a.send({'t': Msg.setAvatar, 'data': base64.encode(utf8.encode('<script>alert(1)</script>'))});
    expect((await a.wait(Msg.error))['msg'], contains('PNG'));
    final tiny = [...png]..[19] = 8..[23] = 8;
    a.send({'t': Msg.setAvatar, 'data': base64.encode(tiny)});
    expect((await a.wait(Msg.error))['msg'], contains('尺寸'));
    // path traversal in hash lookup is ignored
    b.send({'t': Msg.getAvatar, 'id': a.me, 'h': '../users'});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(b.msgs.where((m) => m['t'] == Msg.avatarData), isEmpty);

    a.send({'t': Msg.setAvatar, 'data': ''});
    await b.wait(Msg.member, (m) => (m['m'] as Map)['id'] == a.me && (m['m'] as Map)['avh'] == '');
    a.close();
    b.close();
  });

  test('status text, search, pins, jump to message', () async {
    final a = await TC.connect(port);
    await a.auth({'t': Msg.register, 'user': 'boss2', 'pass': 'password123'});
    final b = await TC.connect(port);
    await b.auth({'t': Msg.register, 'user': 'other', 'pass': 'password123'});
    a.send({'t': Msg.setStatusText, 'text': '在打游戏', 'emoji': '🎮', 'until': 0});
    final st = await b.wait(Msg.member, (m) => (m['m'] as Map)['stxt'] == '在打游戏');
    expect((st['m'] as Map)['semo'], '🎮');

    final ch = server.store.channels.values.firstWhere((c) => c.kind == ChannelKind.text).id;
    for (var i = 0; i < 8; i++) {
      (i.isEven ? a : b).send({'t': Msg.sendMsg, 'ch': ch, 'text': i == 5 ? 'find the Needle here' : 'filler $i'});
      await a.wait(Msg.message);
      await Future<void>.delayed(const Duration(milliseconds: 1100)); // chat rate limit
    }
    b.send({'t': Msg.search, 'q': 'needle'});
    final r = await b.wait(Msg.searchResult);
    expect((r['msgs'] as List).single['text'], 'find the Needle here');
    final hitId = (r['msgs'] as List).single['id'] as int;
    b.send({'t': Msg.search, 'q': '', 'from': a.me});
    expect(((await b.wait(Msg.searchResult))['msgs'] as List).length, 4);

    // members can only pin their own messages
    b.send({'t': Msg.pin, 'ch': ch, 'id': hitId - 1, 'on': true});
    expect((await b.wait(Msg.error))['msg'], contains('置顶'));
    a.send({'t': Msg.pin, 'ch': ch, 'id': hitId, 'on': true});
    expect((await b.wait(Msg.pinned))['id'], hitId);
    b.send({'t': Msg.pins, 'ch': ch});
    expect(((await b.wait(Msg.pinsData))['msgs'] as List).single['id'], hitId);

    b.send({'t': Msg.around, 'ch': ch, 'id': hitId});
    final h = await b.wait(Msg.historyData, (m) => m['around'] == hitId);
    expect((h['msgs'] as List).any((x) => x['id'] == hitId), isTrue);
    a.close();
    b.close();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
