import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_client/native/native.dart';
import 'package:pulse_client/state/app_state.dart';
import 'package:pulse_client/state/settings.dart';
import 'package:pulse_server/server.dart';
import 'package:pulse_shared/pulse_shared.dart';

void main() {
  test('connection survives keep-alive pings', () async {
    final tmp = await Directory.systemTemp.createTemp('pulse_ping');
    final server = PulseServer(0, store: Store(Directory('${tmp.path}/d'))..load(), identity: ServerIdentity.fromSeed(ServerIdentity.newSeed()));
    await server.start();
    final a = AppState(Native.load(), Settings.memory());
    await a.start();
    var closed = '';
    a.conn.closed.listen((r) => closed = r);
    await a.connectTo('127.0.0.1:${server.boundPort}');
    a.register('pinger', 'password123', 'P');
    while (!a.authed || a.currentChannel == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    a.sendTyping(a.currentChannel!);
    a.sendMessage(a.currentChannel!, 'x');
    await Future<void>.delayed(const Duration(seconds: 23));
    expect(closed, '', reason: 'closed: $closed');
    expect(a.authed, isTrue);
    expect(a.conn.pingMs, greaterThanOrEqualTo(0));
    await server.stop();
  }, timeout: const Timeout(Duration(seconds: 60)));
}
