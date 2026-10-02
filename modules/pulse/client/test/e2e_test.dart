import 'dart:async';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pulse_client/state/avatars.dart';
import 'package:pulse_client/native/native.dart';
import 'package:pulse_client/net/connection.dart';
import 'package:pulse_client/state/app_state.dart';
import 'package:pulse_client/state/settings.dart';
import 'package:pulse_server/server.dart';
import 'package:pulse_shared/pulse_shared.dart';

/// Real client state ↔ real server (in-process, loopback TCP).
Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tmp;
  late PulseServer server;
  late String addr;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pulse_e2e');
    final store = Store(Directory('${tmp.path}/data'))..load();
    server = PulseServer(0, store: store, identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
    addr = '127.0.0.1:${server.boundPort}';
  });

  tearDown(() async {
    await server.stop();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  AppState newApp() => AppState(Native.load(), Settings.memory());

  test('register, chat, history, voice join, identity pinning', () async {
    final a = newApp(), b = newApp();
    await a.start();
    await b.start();
    expect(await a.connectTo(addr), isTrue);
    a.register('alice', 'password123', 'Alice');
    await until(() => a.authed && a.channels.isNotEmpty);
    expect(a.isOwner, isTrue);
    expect(a.saved!.pinnedKey, isNotEmpty);

    expect(await b.connectTo(addr), isTrue);
    b.register('bob', 'password123', 'Bob');
    await until(() => b.authed);
    await until(() => a.members.containsKey(b.me));

    final ch = a.currentChannel!;
    a.sendMessage(ch, 'hi @bob');
    await until(() => b.histories[ch]?.messages.any((m) => m.text == 'hi @bob') ?? false);
    // optimistic echo replaced by the server copy
    await until(() => a.histories[ch]!.messages.where((m) => m.text == 'hi @bob').length == 1 && !a.histories[ch]!.messages.last.pending);
    expect(b.mentionsMe('hi @bob'), isTrue);

    // voice join is mirrored to the other client
    final vch = a.sortedChannels(ChannelKind.voice).first.id;
    a.joinVoice(vch);
    await until(() => a.voiceChannel == vch && b.voice[a.me]?.channel == vch);
    a.toggleMute();
    await until(() => b.voice[a.me]?.mute == true);
    a.leaveVoice();
    await until(() => !b.voice.containsKey(a.me));

    // admin creates a channel → both see it
    a.send({'t': Msg.chCreate, 'name': '新频道', 'kind': ChannelKind.text});
    await until(() => b.channels.values.any((c) => c.name == '新频道'));

    // server identity change is detected (TOFU)
    final port = server.boundPort;
    await a.disconnect();
    await b.disconnect();
    await server.stop();
    final store2 = Store(Directory('${tmp.path}/data'))..load();
    server = PulseServer(port, store: store2, identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
    expect(await a.connectTo(addr), isFalse);
    expect(a.identityMismatch, isNotNull);
    expect(a.state, ConnState.disconnected);

    a.dispose();
    b.dispose();
  });

  test('avatar upload is resized, cached and verified; search / pin / jump', () async {
    final a = newApp(), b = newApp();
    await a.start();
    await b.start();
    await a.connectTo(addr);
    a.register('pics', 'password123', 'Pics');
    await until(() => a.authed && a.currentChannel != null);
    await b.connectTo(addr);
    b.register('watch', 'password123', 'Watch');
    await until(() => b.authed && b.members.containsKey(a.me));

    // a 600x400 photo → square 256 px upload
    final photo = img.Image(width: 600, height: 400);
    img.fill(photo, color: img.ColorRgb8(200, 30, 90));
    final (bytes, err) = await prepareAvatar(Uint8List.fromList(img.encodeJpg(photo)));
    expect(err, isNull);
    expect(imageSize(bytes!), (256, 256));
    a.uploadAvatar(bytes);
    await until(() => (b.members[a.me]?.avatarHash ?? '').isNotEmpty);
    final h = b.members[a.me]!.avatarHash;
    expect(b.avatars.get(a.me, h), isNull, reason: 'first access triggers a download');
    await until(() => b.avatars.get(a.me, h) != null);
    expect(sha256Hex(b.avatars.get(a.me, h)!), h);
    // tampered data with a wrong hash is rejected
    b.avatars.put('0' * 64, bytes);
    expect(b.avatars.get(a.me, '0' * 64), isNull);

    final ch = a.currentChannel!;
    for (var i = 0; i < 4; i++) {
      a.sendMessage(ch, i == 2 ? '记得周五开黑' : 'msg $i');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    }
    await until(() => (b.histories[ch]?.messages.length ?? 0) >= 4);
    b.search('开黑');
    await until(() => !b.searching && b.searchResults.isNotEmpty);
    final hit = b.searchResults.single;
    a.setPinned(a.histories[ch]!.messages.firstWhere((m) => m.id == hit.id), true);
    await until(() => b.histories[ch]!.messages.firstWhere((m) => m.id == hit.id).pinned);
    b.loadPins(ch);
    await until(() => b.pins[ch]?.length == 1);

    (int, int)? jumped;
    b.jumpTo.addListener(() => jumped ??= b.jumpTo.value);
    b.jumpToMessage(ch, hit.id);
    expect(jumped, (ch, hit.id));

    a.setStatusText('开会中', '📅');
    await until(() => b.members[a.me]?.statusText == '开会中');
    a.dispose();
    b.dispose();
  });
}
