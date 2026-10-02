import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:aurora_shared/src/engine.dart';
import 'package:aurora_shared/src/secure.dart';
import 'package:test/test.dart';

void main() {
  test('handshake derives matching keys and frames round-trip', () {
    final id = ServerIdentity.fromSeed(ServerIdentity.newSeed());
    final c = ClientHandshake();
    final (reply, sch) = ServerHandshake(id).respond(c.hello());
    final (cch, spk) = c.finish(reply);
    expect(spk, id.publicKey);
    expect(cch.fingerprint, id.fingerprint);
    for (var i = 0; i < 5; i++) {
      final msg = Uint8List.fromList(List.generate(100 + i, (j) => j));
      expect(sch.open(0, cch.seal(0, msg)), msg);
      expect(cch.open(1, sch.seal(1, msg)), msg);
    }
  });

  test('tamper, replay, reorder, wrong kind are rejected', () {
    final id = ServerIdentity.fromSeed(ServerIdentity.newSeed());
    final c = ClientHandshake();
    final (reply, s) = ServerHandshake(id).respond(c.hello());
    final (cl, _) = c.finish(reply);
    final f1 = cl.seal(0, [1, 2, 3]);
    final f2 = cl.seal(0, [4, 5, 6]);
    // reorder
    expect(() => s.open(0, f2), throwsA(anything));
    // wrong kind (AAD)
    expect(() => s.open(1, f1), throwsA(anything));
    // tamper
    final t = Uint8List.fromList(f1)..[9] ^= 1;
    expect(() => s.open(0, t), throwsA(anything));
    expect(s.open(0, f1), [1, 2, 3]);
    // replay
    expect(() => s.open(0, f1), throwsA(anything));
    expect(s.open(0, f2), [4, 5, 6]);
  });

  test('man-in-the-middle with a different static key cannot read traffic', () {
    final real = ServerIdentity.fromSeed(ServerIdentity.newSeed());
    final mitm = ServerIdentity.fromSeed(ServerIdentity.newSeed());
    final c = ClientHandshake();
    final hello = c.hello();
    // attacker answers but claims the real server's static key
    final (reply, attackerCh) = ServerHandshake(mitm).respond(hello);
    reply['spk'] = base64.encode(real.publicKey);
    final (clientCh, spk) = c.finish(reply);
    expect(spk, real.publicKey, reason: 'pin check would pass...');
    // ...but keys differ, so nothing decrypts
    expect(() => attackerCh.open(0, clientCh.seal(0, [7, 7, 7])), throwsA(anything));
  });

  test('server identity is deterministic from seed', () {
    final seed = ServerIdentity.newSeed();
    expect(ServerIdentity.fromSeed(seed).publicKey, ServerIdentity.fromSeed(seed).publicKey);
  });

  test('claim cover delay: ~60% of no-claim discards pause 500-1000ms', () {
    final rng = Random(1);
    var paused = 0;
    for (var i = 0; i < 10000; i++) {
      final ms = claimCoverDelayMs(rng);
      if (ms != 0) {
        paused++;
        expect(ms, inInclusiveRange(500, 1000));
      }
    }
    expect(paused / 10000, closeTo(0.6, 0.03));
  });
}

