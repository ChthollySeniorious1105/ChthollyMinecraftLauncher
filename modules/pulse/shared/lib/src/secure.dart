import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/dart.dart';
import 'package:cryptography/cryptography.dart';

/// Encrypted transport for Pulse (protocol v1, same construction as Aurora v2).
///
/// Handshake (plaintext frames, JSON):
///   C → S  {t:'chello', v:1, epk: b64(client ephemeral X25519 pub), cn: b64(16B nonce)}
///   S → C  {t:'shello', v:1, epk: b64(server ephemeral X25519 pub), sn: b64(16B nonce),
///           spk: b64(server static X25519 pub)}
/// Keys: ee = DH(c_eph, s_eph), es = DH(c_eph, s_static)
///   prk = HKDF-SHA256(ikm = ee || es, salt = cn || sn, info = "aurora-v2" || transcript hash)
///   c2s key, s2c key = 32B each; per-direction 64-bit counters as nonces.
/// The server proves possession of its static key because `es` is part of the key
/// derivation: a man-in-the-middle without the static private key cannot derive
/// the session keys, so the first encrypted frame fails authentication.
/// Clients pin `spk` per server address (trust on first use) and refuse to talk
/// if it later changes, like SSH known_hosts.
///
/// After the handshake every frame payload is `counter(8) || ciphertext || tag(16)`
/// sealed with ChaCha20-Poly1305; replayed/reordered/tampered frames are rejected.
class SecureChannel {
  final SecretKeyData _sendKey;
  final SecretKeyData _recvKey;
  int _sendCtr = 0;
  int _recvCtr = 0;
  static const _aead = DartChacha20.poly1305Aead();

  /// Short fingerprint of the server static key (shown to users for verification).
  final String fingerprint;

  SecureChannel._(this._sendKey, this._recvKey, this.fingerprint);

  static List<int> _nonce(int ctr) {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, ctr);
    return n;
  }

  /// Seal one frame (kind byte is authenticated as associated data).
  Uint8List seal(int kind, List<int> plain) {
    final ctr = _sendCtr++;
    final box = _aead.encryptSync(plain, secretKey: _sendKey, nonce: _nonce(ctr), aad: [kind]);
    final out = Uint8List(8 + box.cipherText.length + 16);
    ByteData.sublistView(out).setUint64(0, ctr);
    out.setRange(8, 8 + box.cipherText.length, box.cipherText);
    out.setRange(8 + box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// Open one frame. Throws on tamper, replay or reordering.
  Uint8List open(int kind, Uint8List sealed) {
    if (sealed.length < 24) throw const FormatException('short frame');
    final ctr = ByteData.sublistView(sealed, 0, 8).getUint64(0);
    if (ctr != _recvCtr) throw const FormatException('replayed or reordered frame');
    final ct = Uint8List.sublistView(sealed, 8, sealed.length - 16);
    final mac = Mac(Uint8List.sublistView(sealed, sealed.length - 16));
    final plain = _aead.decryptSync(SecretBox(ct, nonce: _nonce(ctr), mac: mac), secretKey: _recvKey, aad: [kind]);
    _recvCtr++;
    return Uint8List.fromList(plain);
  }

  /// Keys + counters, to continue this channel in another isolate ([SecureChannel.restore]).
  /// The original must not be used afterwards.
  List<Object> exportState() => [Uint8List.fromList(_sendKey.bytes), Uint8List.fromList(_recvKey.bytes), _sendCtr, _recvCtr, fingerprint];

  factory SecureChannel.restore(List<Object> s) =>
      SecureChannel._(SecretKeyData(s[0] as List<int>), SecretKeyData(s[1] as List<int>), s[4] as String)
        .._sendCtr = s[2] as int
        .._recvCtr = s[3] as int;

  static String fingerprintOf(List<int> staticPub) {
    final d = hash.sha256.convert(staticPub).bytes;
    return [for (var i = 0; i < 8; i++) d[i].toRadixString(16).padLeft(2, '0')].join(':').toUpperCase();
  }

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static List<int> _dh(SimpleKeyPairData mine, List<int> theirPub) {
    const x = DartX25519();
    final s = x.sharedSecretSync(
      keyPairData: mine,
      remotePublicKey: SimplePublicKey(theirPub, type: KeyPairType.x25519),
    ) as SecretKeyData;
    // reject all-zero shared secrets (low-order points)
    if (s.bytes.every((b) => b == 0)) throw const FormatException('invalid public key');
    return s.bytes;
  }

  static List<int> _hmac(List<int> key, List<int> data) => hash.Hmac(hash.sha256, key).convert(data).bytes;

  /// HKDF-SHA256 (RFC 5869) producing [len] bytes.
  static List<int> _hkdf(List<int> ikm, List<int> salt, List<int> info, int len) {
    final prk = _hmac(salt, ikm);
    final out = <int>[];
    var t = <int>[];
    for (var i = 1; out.length < len; i++) {
      t = _hmac(prk, [...t, ...info, i]);
      out.addAll(t);
    }
    return out.sublist(0, len);
  }

  static SecureChannel _derive({
    required bool isClient,
    required List<int> ee,
    required List<int> es,
    required List<int> cn,
    required List<int> sn,
    required List<int> cEph,
    required List<int> sEph,
    required List<int> sStatic,
  }) {
    final transcript = hash.sha256.convert([...cEph, ...sEph, ...sStatic, ...cn, ...sn]).bytes;
    final okm = _hkdf([...ee, ...es], [...cn, ...sn], [...utf8.encode('pulse-v1'), ...transcript], 64);
    final c2s = SecretKeyData(okm.sublist(0, 32));
    final s2c = SecretKeyData(okm.sublist(32, 64));
    final fp = fingerprintOf(sStatic);
    return isClient ? SecureChannel._(c2s, s2c, fp) : SecureChannel._(s2c, c2s, fp);
  }

  static SimpleKeyPairData _keyPairFromSeed(List<int> seed) {
    final priv = DartX25519.modifiedPrivateKeyBytes(seed);
    // compute public key: X25519(priv, 9)
    final base = Uint8List(32)..[0] = 9;
    const x = DartX25519();
    final tmp = SimpleKeyPairData(priv, publicKey: SimplePublicKey(base, type: KeyPairType.x25519), type: KeyPairType.x25519);
    final pub = (x.sharedSecretSync(keyPairData: tmp, remotePublicKey: SimplePublicKey(base, type: KeyPairType.x25519))
            as SecretKeyData)
        .bytes;
    return SimpleKeyPairData(priv, publicKey: SimplePublicKey(pub, type: KeyPairType.x25519), type: KeyPairType.x25519);
  }

  static List<int> _pub(SimpleKeyPairData k) => k.publicKey.bytes;
}

/// Long-term server identity (32-byte X25519 private seed, persisted by the server).
class ServerIdentity {
  final SimpleKeyPairData keyPair;
  ServerIdentity._(this.keyPair);

  factory ServerIdentity.fromSeed(List<int> seed) {
    if (seed.length != 32) throw ArgumentError('seed must be 32 bytes');
    return ServerIdentity._(SecureChannel._keyPairFromSeed(seed));
  }

  static List<int> newSeed() => SecureChannel._random(32);

  List<int> get publicKey => SecureChannel._pub(keyPair);
  String get fingerprint => SecureChannel.fingerprintOf(publicKey);
}

/// Client side of the handshake.
class ClientHandshake {
  final SimpleKeyPairData _eph = SecureChannel._keyPairFromSeed(SecureChannel._random(32));
  final List<int> _cn = SecureChannel._random(16);

  Map<String, dynamic> hello() => {
        't': 'chello',
        'v': 1,
        'epk': base64.encode(SecureChannel._pub(_eph)),
        'cn': base64.encode(_cn),
      };

  /// Returns (channel, server static public key bytes).
  (SecureChannel, List<int>) finish(Map<String, dynamic> shello) {
    if (shello['t'] != 'shello' || shello['v'] != 1) throw const FormatException('bad server hello');
    final sEph = base64.decode('${shello['epk']}');
    final sStatic = base64.decode('${shello['spk']}');
    final sn = base64.decode('${shello['sn']}');
    if (sEph.length != 32 || sStatic.length != 32 || sn.length != 16) throw const FormatException('bad server hello');
    final ch = SecureChannel._derive(
      isClient: true,
      ee: SecureChannel._dh(_eph, sEph),
      es: SecureChannel._dh(_eph, sStatic),
      cn: _cn,
      sn: sn,
      cEph: SecureChannel._pub(_eph),
      sEph: sEph,
      sStatic: sStatic,
    );
    return (ch, sStatic);
  }
}

/// Server side of the handshake.
class ServerHandshake {
  final ServerIdentity identity;
  ServerHandshake(this.identity);

  /// Returns (reply message, channel) or throws FormatException.
  (Map<String, dynamic>, SecureChannel) respond(Map<String, dynamic> chello) {
    if (chello['t'] != 'chello' || chello['v'] != 1) throw const FormatException('bad client hello');
    final cEph = base64.decode('${chello['epk']}');
    final cn = base64.decode('${chello['cn']}');
    if (cEph.length != 32 || cn.length != 16) throw const FormatException('bad client hello');
    final eph = SecureChannel._keyPairFromSeed(SecureChannel._random(32));
    final sn = SecureChannel._random(16);
    // server computes: ee = DH(s_eph, c_eph), es = DH(s_static, c_eph)
    final ch = SecureChannel._derive(
      isClient: false,
      ee: SecureChannel._dh(eph, cEph),
      es: SecureChannel._dh(identity.keyPair, cEph),
      cn: cn,
      sn: sn,
      cEph: cEph,
      sEph: SecureChannel._pub(eph),
      sStatic: identity.publicKey,
    );
    return (
      {
        't': 'shello',
        'v': 1,
        'epk': base64.encode(SecureChannel._pub(eph)),
        'sn': base64.encode(sn),
        'spk': base64.encode(identity.publicKey),
      },
      ch
    );
  }
}
