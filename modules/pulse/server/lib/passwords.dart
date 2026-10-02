import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

/// Password hashing: Argon2id (m = 19 MiB, t = 2, p = 1 — OWASP minimum), run
/// in a short-lived isolate so the ~80 ms of work never stalls voice relay.
///
/// Encoded as `argon2id$v=19$m=19456,t=2,p=1$<salt b64>$<hash b64>` so the
/// parameters can be raised later; [needsRehash] tells the server to upgrade
/// an old hash after a successful login.
class Passwords {
  static const _m = 19456, _t = 2, _p = 1;

  /// At most this many hashes run concurrently; the rest queue.
  static const maxConcurrent = 4;
  static int _running = 0;
  static final List<void Function()> _queue = [];

  static Future<T> _limited<T>(Future<T> Function() f) async {
    if (_running >= maxConcurrent) {
      final gate = Completer<void>();
      _queue.add(gate.complete);
      await gate.future;
    }
    _running++;
    try {
      return await f();
    } finally {
      _running--;
      if (_queue.isNotEmpty) _queue.removeAt(0)();
    }
  }

  static List<int> _salt() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256));
  }

  static Future<List<int>> _derive(String pass, List<int> salt, int m, int t, int p) {
    return Isolate.run(() async {
      final a = DartArgon2id(parallelism: p, memory: m, iterations: t, hashLength: 32);
      final k = await a.deriveKey(secretKey: SecretKey(utf8.encode(pass)), nonce: salt);
      return await k.extractBytes();
    });
  }

  static Future<String> hash(String pass) => _limited(() async {
        final salt = _salt();
        final h = await _derive(pass, salt, _m, _t, _p);
        return 'argon2id\$v=19\$m=$_m,t=$_t,p=$_p\$${base64.encode(salt)}\$${base64.encode(h)}';
      });

  /// A syntactically valid hash of a random password; verifying against it
  /// costs the same as a real account, so login timing does not reveal whether
  /// a username exists.
  static String? _dummy;
  static Future<String> dummy() async => _dummy ??= await hash(base64.encode(_salt()));

  static Future<bool> verify(String pass, String encoded) => _limited(() async {
        final parts = encoded.split('\$');
        if (parts.length != 5 || parts[0] != 'argon2id') return false;
        final params = {for (final kv in parts[2].split(',')) kv.split('=')[0]: int.tryParse(kv.split('=').last) ?? 0};
        final m = params['m'] ?? 0, t = params['t'] ?? 0, p = params['p'] ?? 0;
        if (m < 8 || m > 1 << 20 || t < 1 || t > 10 || p < 1 || p > 8) return false;
        List<int> salt, want;
        try {
          salt = base64.decode(parts[3]);
          want = base64.decode(parts[4]);
        } catch (_) {
          return false;
        }
        final got = await _derive(pass, salt, m, t, p);
        return constantTimeEquals(got, want);
      });

  static bool needsRehash(String encoded) => !encoded.startsWith('argon2id\$v=19\$m=$_m,t=$_t,p=$_p\$');

  static bool constantTimeEquals(List<int> a, List<int> b) {
    var d = a.length ^ b.length;
    for (var i = 0; i < max(a.length, b.length); i++) {
      d |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
    }
    return d == 0;
  }
}
