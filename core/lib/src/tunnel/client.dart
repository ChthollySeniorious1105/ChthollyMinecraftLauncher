import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import 'protocol.dart';
import 'secure.dart';

/// Pinned CMLS server identities (trust on first use, like SSH known_hosts).
class KnownServers {
  final String path;
  Map<String, String> _pins = {};
  KnownServers([String? path]) : path = path ?? p.join(Os.cmlHome, 'known_servers.json');

  Future<void> load() async {
    final j = await JsonFile.read(path);
    if (j is Map) _pins = j.map((k, v) => MapEntry('$k', '$v'));
  }

  String? pinned(String address) => _pins[address.toLowerCase()];

  Future<void> pin(String address, String keyB64) async {
    _pins[address.toLowerCase()] = keyB64;
    await JsonFile.write(path, _pins);
  }
}

/// Thrown when the server's identity differs from the pinned one.
class IdentityChangedException extends CmlException {
  final String newFingerprint;
  final String newKey;
  IdentityChangedException(this.newFingerprint, this.newKey)
      : super('identity_changed', '服务器身份已改变（指纹 $newFingerprint）。如果你没有重装服务器，可能有人在冒充它。');
}

class RoomInfo {
  final String room, title, version, host;
  final int players;
  final bool locked;
  RoomInfo(this.room, this.title, this.version, this.host, this.players, this.locked);
  factory RoomInfo.fromJson(Map j) =>
      RoomInfo('${j['room']}', '${j['title']}', '${j['version'] ?? ''}', '${j['host']}', (j['players'] as num?)?.toInt() ?? 0, j['locked'] == true);
}

/// Encrypted connection to a CMLS server, plus host/guest LAN bridging.
class TunnelClient {
  final String address; // host:port
  final KnownServers known;
  Socket? _sock;
  SecureChannel? _ch;
  final _dec = FrameDecoder();
  final _replies = <String, Completer<Map>>{};
  final _events = StreamController<Map>.broadcast();
  String fingerprint = '';
  String serverName = '';
  String motd = '';

  // stream bridging
  final _streams = <int, Socket>{};
  final _pending = <int, List<List<int>>>{};
  int _nextSid = 1;
  ServerSocket? _guestListener;
  Timer? _lanTimer;
  RawDatagramSocket? _lanSock;
  Timer? _ping;

  /// Host mode: local MC LAN port to connect to for each incoming stream.
  int? hostLanPort;
  String? room;
  bool isHost = false;

  TunnelClient(this.address, this.known);

  Stream<Map> get events => _events.stream;
  bool get connected => _ch != null;

  static (String, int) parseAddress(String a) {
    a = a.trim();
    final i = a.lastIndexOf(':');
    if (i > 0 && !a.endsWith(']')) {
      final port = int.tryParse(a.substring(i + 1));
      if (port != null) return (a.substring(0, i), port);
    }
    return (a, TunnelLimits.defaultPort);
  }

  /// Connects, performs the handshake and verifies the pinned identity.
  /// When [trustNewIdentity] is true a changed identity is accepted and re-pinned.
  Future<void> connect({required String name, String password = '', bool trustNewIdentity = false}) async {
    final (host, port) = parseAddress(address);
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
    s.setOption(SocketOption.tcpNoDelay, true);
    s.done.catchError((_) {});
    _sock = s;
    final hs = ClientHandshake();
    final helloDone = Completer<Map<String, dynamic>>();
    s.listen((chunk) {
      try {
        for (final f in _dec.add(chunk)) {
          if (_ch == null) {
            if (f.kind != FrameKind.hello) throw const FormatException('unexpected frame');
            if (!helloDone.isCompleted) helloDone.complete((jsonDecode(utf8.decode(f.payload)) as Map).cast<String, dynamic>());
          } else {
            _onFrame(f);
          }
        }
      } catch (e) {
        _fail(e);
      }
    }, onError: _fail, onDone: () => _fail(const CmlException('disconnected', '与联机服务器的连接已断开')));
    s.add(Frame.encode(FrameKind.hello, utf8.encode(jsonEncode(hs.hello()))));
    final shello = await helloDone.future.timeout(TunnelLimits.handshakeTimeout);
    final (ch, spk) = hs.finish(shello);
    final keyB64 = base64.encode(spk);
    fingerprint = SecureChannel.fingerprintOf(spk);
    final pinnedKey = known.pinned(address);
    if (pinnedKey != null && pinnedKey != keyB64 && !trustNewIdentity) {
      await close();
      throw IdentityChangedException(fingerprint, keyB64);
    }
    if (pinnedKey != keyB64) await known.pin(address, keyB64);
    _ch = ch;
    final ok = await request({'t': 'auth', 'name': name, 'password': password, 'v': 1});
    serverName = '${ok['server'] ?? ''}';
    motd = '${ok['motd'] ?? ''}';
    _ping = Timer.periodic(const Duration(seconds: 20), (_) => _send({'t': 'ping', 'ts': DateTime.now().millisecondsSinceEpoch}));
  }

  void _fail(Object e) {
    for (final c in _replies.values) {
      if (!c.isCompleted) c.completeError(e is CmlException ? e : CmlException('tunnel', '联机连接出错', e));
    }
    _replies.clear();
    if (!_events.isClosed) _events.add({'t': 'disconnected', 'reason': e is CmlException ? e.message : '$e'});
    close();
  }

  void _send(Map<String, Object?> m) {
    final ch = _ch;
    if (ch == null) return;
    try {
      _sock?.add(Frame.encode(FrameKind.control, ch.seal(FrameKind.control, Frame.json(m))));
    } on SocketException {
      // connection is going away; onDone will report it
    }
  }

  void _sendData(int sid, List<int> bytes) {
    final ch = _ch;
    if (ch == null) return;
    try {
      for (var i = 0; i < bytes.length; i += TunnelLimits.dataChunk) {
        final end = (i + TunnelLimits.dataChunk).clamp(0, bytes.length);
        _sock?.add(Frame.encode(FrameKind.data, ch.seal(FrameKind.data, Frame.dataPayload(sid, bytes, i, end))));
      }
    } on SocketException {
      // see _send
    }
  }

  /// Sends a request and waits for its reply type (or `error`).
  Future<Map> request(Map<String, Object?> m) {
    final reply = switch (m['t']) { 'auth' => 'ok', 'host' => 'hosted', 'rooms' => 'rooms', 'join' => 'joined', _ => '${m['t']}' };
    final c = Completer<Map>();
    _replies[reply] = c;
    _replies['error'] = c;
    _send(m);
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () => throw const CmlException('timeout', '联机服务器无响应'));
  }

  void _onFrame(Frame f) {
    final plain = _ch!.open(f.kind, f.payload);
    if (f.kind == FrameKind.data) {
      final sid = ByteData.sublistView(plain, 0, 4).getUint32(0);
      final data = Uint8List.sublistView(plain, 4);
      final s = _streams[sid];
      if (s != null) {
        s.add(data);
      } else {
        _pending[sid]?.add(data);
      }
      return;
    }
    if (f.kind != FrameKind.control) return;
    final m = jsonDecode(utf8.decode(plain)) as Map;
    final t = '${m['t']}';
    final waiter = _replies.remove(t);
    if (waiter != null) {
      _replies.remove('error');
      if (t == 'error') {
        waiter.completeError(CmlException('server', '${m['message']}'));
      } else {
        waiter.complete(m);
      }
      return;
    }
    switch (t) {
      case 'open': // host side: a guest opened a stream
        _hostOpen((m['sid'] as num).toInt());
      case 'close':
        final sid = (m['sid'] as num).toInt();
        _pending.remove(sid);
        _streams.remove(sid)?.destroy();
      case 'ping':
        _send({'t': 'pong', 'ts': m['ts']});
      case 'closed':
        _stopBridging();
    }
    _events.add(m);
  }

  // ---------------- host ----------------

  /// Detects a local "对局域网开放" game by listening for MC LAN broadcasts. Returns (motd, port).
  static Future<(String, int)?> detectLocalLan({Duration timeout = const Duration(seconds: 4)}) async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, LanBroadcast.port, reuseAddress: true);
      s.joinMulticast(InternetAddress(LanBroadcast.group));
      final c = Completer<(String, int)?>();
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = s!.receive();
        if (d == null || !d.address.isLoopback && !_isLocal(d.address)) return;
        final r = LanBroadcast.parse(utf8.decode(d.data, allowMalformed: true));
        if (r != null && !c.isCompleted) c.complete(r);
      });
      return await c.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      s?.close();
    }
  }

  static bool _isLocal(InternetAddress a) => a.type == InternetAddressType.IPv4;

  /// Creates a room that forwards guests to local port [lanPort].
  Future<String> host({required String title, required int lanPort, String version = '', String password = '', bool public = true}) async {
    hostLanPort = lanPort;
    isHost = true;
    final r = await request({'t': 'host', 'title': title, 'version': version, 'password': password, 'public': public});
    return room = '${r['room']}';
  }

  Future<void> _hostOpen(int sid) async {
    // guest bytes may arrive before the local connection is up: buffer them
    final pending = <List<int>>[];
    _pending[sid] = pending;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, hostLanPort!, timeout: const Duration(seconds: 5));
      s.setOption(SocketOption.tcpNoDelay, true);
      s.done.catchError((_) {});
      if (_pending.remove(sid) == null) {
        s.destroy(); // closed while connecting
        return;
      }
      _streams[sid] = s;
      for (final d in pending) {
        s.add(d);
      }
      s.listen((d) => _sendData(sid, d), onDone: () => _closeStream(sid), onError: (_) => _closeStream(sid));
    } catch (_) {
      _pending.remove(sid);
      _send({'t': 'close', 'sid': sid});
    }
  }

  void _closeStream(int sid) {
    if (_streams.remove(sid) != null) _send({'t': 'close', 'sid': sid});
  }

  // ---------------- guest ----------------

  Future<List<RoomInfo>> rooms() async {
    final r = await request({'t': 'rooms'});
    return [for (final j in r['list'] as List) RoomInfo.fromJson(j as Map)];
  }

  /// Joins [roomId] and exposes it locally: a TCP listener on 127.0.0.1 plus LAN broadcast,
  /// so the room shows up in Minecraft's multiplayer list. Returns the local port.
  Future<int> join(String roomId, {String password = '', int localPort = 0}) async {
    final r = await request({'t': 'join', 'room': roomId.toUpperCase(), 'password': password});
    room = '${r['room']}';
    isHost = false;
    final l = await ServerSocket.bind(InternetAddress.loopbackIPv4, localPort);
    _guestListener = l;
    l.listen((s) {
      s.setOption(SocketOption.tcpNoDelay, true);
      s.done.catchError((_) {});
      final sid = _nextSid++;
      _streams[sid] = s;
      _send({'t': 'open', 'sid': sid});
      s.listen((d) => _sendData(sid, d), onDone: () => _closeStream(sid), onError: (_) => _closeStream(sid));
    });
    await _startLanBroadcast('[CML] ${r['title']}', l.port);
    return l.port;
  }

  Future<void> _startLanBroadcast(String motd, int port) async {
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      s.multicastLoopback = true;
      _lanSock = s;
      final pkt = utf8.encode(LanBroadcast.packet(motd, port));
      _lanTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => s.send(pkt, InternetAddress(LanBroadcast.group), LanBroadcast.port));
    } catch (_) {
      // broadcasting is a convenience; users can still add 127.0.0.1:port manually
    }
  }

  Future<void> leave() async {
    _send({'t': 'leave'});
    _stopBridging();
  }

  void _stopBridging() {
    _lanTimer?.cancel();
    _lanSock?.close();
    _lanSock = null;
    _guestListener?.close();
    _guestListener = null;
    final streams = _streams.values.toList();
    _streams.clear();
    _pending.clear();
    for (final s in streams) {
      s.destroy();
    }
    room = null;
  }

  Future<void> close() async {
    _ping?.cancel();
    _stopBridging();
    _ch = null;
    final s = _sock;
    _sock = null;
    s?.destroy();
  }
}
