import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_shared/aurora_shared.dart';

enum ConnState { disconnected, connecting, connected }

/// Raw TCP connection to an Aurora server with frame decoding and keep-alive.
class Connection {
  Socket? _socket;
  FrameDecoder _decoder = FrameDecoder(maxFrame: kMaxServerFrame);
  Timer? _ping;
  final _json = StreamController<Map<String, dynamic>>.broadcast();
  final _voice = StreamController<(int, Uint8List)>.broadcast();
  final _closed = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get messages => _json.stream;

  /// (speaker client id, encoded audio)
  Stream<(int, Uint8List)> get voice => _voice.stream;
  Stream<String> get closed => _closed.stream;
  bool get isOpen => _socket != null;

  /// Parse "host:port", "host" or "[v6]:port".
  static (String, int) parseAddress(String input) {
    var s = input.trim();
    if (s.contains('://')) s = s.substring(s.indexOf('://') + 3);
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s.startsWith('[')) {
      final end = s.indexOf(']');
      if (end > 0) {
        final host = s.substring(1, end);
        final rest = s.substring(end + 1);
        final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
        return (host, port ?? kDefaultPort);
      }
    }
    final i = s.lastIndexOf(':');
    if (i > 0 && s.indexOf(':') == i) {
      return (s.substring(0, i), int.tryParse(s.substring(i + 1)) ?? kDefaultPort);
    }
    return (s, kDefaultPort);
  }

  SecureChannel? _channel;

  /// Fingerprint of the server we are talking to (after handshake).
  String? serverFingerprint;

  /// Server static public key (base64) — pin this per address.
  String? serverKey;

  /// Connects, performs the encrypted handshake and returns the server's
  /// static key (base64) so the caller can check it against a pinned value.
  Future<String> connect(String address) async {
    await close();
    final (host, port) = parseAddress(address);
    if (host.isEmpty) throw const SocketException('地址为空');
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 8));
    s.setOption(SocketOption.tcpNoDelay, true);
    _socket = s;
    _decoder = FrameDecoder(maxFrame: kMaxServerFrame);
    _channel = null;
    final hs = ClientHandshake();
    final ready = Completer<String>();
    s.listen(
      (data) {
        List<Frame> frames;
        try {
          frames = _decoder.add(data);
        } catch (_) {
          _drop('数据错误');
          return;
        }
        for (final f in frames) {
          if (_channel == null) {
            // only the server hello (or a legacy plaintext error) is unencrypted
            try {
              final m = f.json;
              if (m['t'] == Msg.error) {
                if (!ready.isCompleted) ready.completeError(SocketException('${m['msg']}'));
                _drop('${m['msg']}');
                return;
              }
              final (ch, spk) = hs.finish(m);
              _channel = ch;
              serverFingerprint = ch.fingerprint;
              serverKey = base64.encode(spk);
              if (!ready.isCompleted) ready.complete(serverKey);
            } catch (e) {
              if (!ready.isCompleted) ready.completeError(const SocketException('服务器握手失败（不是 Aurora 服务器或版本不兼容）'));
              _drop('握手失败');
              return;
            }
            continue;
          }
          Uint8List plain;
          try {
            plain = _channel!.open(f.kind, f.payload);
          } catch (_) {
            _drop('收到被篡改的数据，连接已断开');
            return;
          }
          if (f.kind == kFrameJson) {
            try {
              _json.add(Frame(f.kind, plain).json);
            } catch (_) {}
          } else if (f.kind == kFrameVoice && plain.length > 4) {
            final id = ByteData.sublistView(plain).getUint32(0);
            _voice.add((id, Uint8List.sublistView(plain, 4)));
          }
        }
      },
      onDone: () {
        if (!ready.isCompleted) ready.completeError(const SocketException('连接被服务器关闭'));
        _drop('连接已断开');
      },
      onError: (e) {
        if (!ready.isCompleted) ready.completeError(SocketException('$e'));
        _drop('连接错误：$e');
      },
      cancelOnError: true,
    );
    s.add(encodeJson(hs.hello()));
    final key = await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {
      _drop('握手超时');
      throw const SocketException('握手超时');
    });
    _ping = Timer.periodic(const Duration(seconds: 10), (_) {
      send({'t': Msg.ping, 'ts': DateTime.now().millisecondsSinceEpoch});
    });
    return key;
  }

  void _drop(String reason) {
    if (_socket == null) return;
    _ping?.cancel();
    _socket?.destroy();
    _socket = null;
    _channel = null;
    _closed.add(reason);
  }

  void _sendSealed(int kind, List<int> payload) {
    final s = _socket, ch = _channel;
    if (s == null || ch == null) return;
    try {
      s.add(encodeFrame(kind, ch.seal(kind, payload)));
    } catch (_) {}
  }

  void send(Map<String, dynamic> msg) => _sendSealed(kFrameJson, utf8.encode(jsonEncode(msg)));

  void sendVoice(Uint8List audio) => _sendSealed(kFrameVoice, audio);

  /// Test hook: simulate the network dropping (as if the peer vanished).
  void dropForTest() => _drop('连接已断开');

  Future<void> close() async {
    _ping?.cancel();
    final s = _socket;
    _socket = null;
    _channel = null;
    if (s != null) {
      try {
        await s.close();
      } catch (_) {}
      s.destroy();
    }
  }
}
