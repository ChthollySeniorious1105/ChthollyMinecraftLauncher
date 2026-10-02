import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import 'bedrock.dart';
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

  /// `java` (TCP) or `bedrock` (UDP / RakNet).
  final String edition;
  RoomInfo(this.room, this.title, this.version, this.host, this.players, this.locked, {this.edition = 'java'});
  factory RoomInfo.fromJson(Map j) => RoomInfo('${j['room']}', '${j['title']}', '${j['version'] ?? ''}', '${j['host']}',
      (j['players'] as num?)?.toInt() ?? 0, j['locked'] == true,
      edition: j['edition'] == 'bedrock' ? 'bedrock' : 'java');
  bool get isBedrock => edition == 'bedrock';
}

/// Host side of one guest UDP flow: a dedicated local socket talking to the Bedrock server.
class _HostFlow {
  RawDatagramSocket? sock;
  final pending = <Uint8List>[];
  int last = DateTime.now().millisecondsSinceEpoch;
  final up = TokenBucket();
  bool closed = false;
}

/// Guest side of one UDP flow: a local Bedrock client endpoint.
class _GuestFlow {
  final InternetAddress addr;
  final int port;
  int last = DateTime.now().millisecondsSinceEpoch;
  final up = TokenBucket();
  _GuestFlow(this.addr, this.port);
}

/// Encrypted connection to a CMLS server, plus host/guest LAN bridging
/// (Java Edition over TCP, Bedrock Edition over UDP).
class TunnelClient {
  final String address; // host:port
  final KnownServers known;
  Socket? _sock;
  FrameWriter? _out;
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

  /// Edition of the current room: `java` or `bedrock`.
  String edition = 'java';
  bool get isBedrock => edition == 'bedrock';

  /// Title of the joined / hosted room.
  String roomTitle = '';

  // ---- Bedrock (UDP) ----
  /// Host mode: where the local Bedrock world / BDS listens.
  int? hostUdpPort;
  InternetAddress hostUdpAddress = InternetAddress.loopbackIPv4;

  /// Pong info of the room (host: as detected locally; guest: as reported by the host).
  BedrockServerInfo? bedrockInfo;

  /// Host mode: UDP port CMLS exposes this room on to the internet (null = not public).
  int? publicUdpPort;

  /// Guest mode: local UDP port the room is exposed on (19132 when LAN discovery works).
  int? bedrockLocalPort;
  bool get bedrockLanDiscoverable => bedrockLocalPort == RakNet.defaultPort4;

  final _hostFlows = <int, _HostFlow>{};
  final _guestFlows = <int, _GuestFlow>{};
  final _guestFlowByEndpoint = <String, int>{};

  /// Guest: endpoints whose flow the server refused / closed, with retry-after time (avoids uopen storms).
  final _flowCooldown = <String, int>{};
  RawDatagramSocket? _udp;
  Set<String> _localAddrs = {};
  bool _allowLanClients = false;
  final int _pongGuid = RakNet.randomGuid();
  Timer? _flowTimer;
  Timer? _infoTimer;

  /// Datagrams dropped because of rate limits / backpressure / flow limits (diagnostics).
  int droppedDatagrams = 0;

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
    final out = FrameWriter(s);
    _out = out;
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
    out.add(Frame.encode(FrameKind.hello, utf8.encode(jsonEncode(hs.hello()))));
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
    final ok = await request({
      't': 'auth',
      'name': name,
      'password': password,
      'v': 1,
      'caps': ['bedrock'],
    });
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
    _out?.add(Frame.encode(FrameKind.control, ch.seal(FrameKind.control, Frame.json(m))));
  }

  void _sendData(int sid, List<int> bytes) {
    final ch = _ch;
    if (ch == null) return;
    for (var i = 0; i < bytes.length; i += TunnelLimits.dataChunk) {
      final end = (i + TunnelLimits.dataChunk).clamp(0, bytes.length);
      _out?.add(Frame.encode(FrameKind.data, ch.seal(FrameKind.data, Frame.dataPayload(sid, bytes, i, end))));
    }
  }

  /// Sends one UDP datagram on flow [sid]; dropped (never queued) when over budget or backpressured.
  void _sendDatagram(int sid, Uint8List d, TokenBucket bucket) {
    final ch = _ch, out = _out;
    if (ch == null || out == null) return;
    if (d.length > TunnelLimits.maxDatagram || out.congested || !bucket.allow(d.length)) {
      droppedDatagrams++;
      return;
    }
    out.add(Frame.encode(FrameKind.datagram, ch.seal(FrameKind.datagram, Frame.datagramPayload(sid, d))));
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
    if (f.kind == FrameKind.datagram) {
      final d = Frame.parseDatagram(plain);
      if (d != null) _onDatagram(d.$1, d.$2);
      return;
    }
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
      case 'uopen': // host side: a guest (or a public internet client) opened a UDP flow
        _hostUOpen((m['sid'] as num).toInt());
      case 'uclose':
        final sid = (m['sid'] as num).toInt();
        final g = _guestFlows[sid];
        if (g != null) _flowCooldown['${g.addr.address}:${g.port}'] = DateTime.now().millisecondsSinceEpoch + 3000;
        _closeFlowLocal(sid);
      case 'binfo':
        if (!isHost) bedrockInfo = BedrockServerInfo.fromJson(m['bedrock']);
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
    edition = 'java';
    roomTitle = title;
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

  // ---------------- host: Bedrock ----------------

  /// Sends a RakNet Unconnected Ping to [addr]:[port] and returns the parsed pong, or null.
  static Future<BedrockServerInfo?> pingBedrock(InternetAddress addr, int port, {Duration timeout = const Duration(seconds: 2)}) async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(addr.type == InternetAddressType.IPv6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4, 0);
      final sock = s;
      final c = Completer<BedrockServerInfo?>();
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock.receive();
        if (d == null || d.port != port) return;
        final pong = RakNet.parsePong(d.data);
        final info = pong == null ? null : BedrockServerInfo.parse(pong.$3);
        if (info != null && !c.isCompleted) c.complete(info);
      }, onError: (_) {}); // e.g. ICMP port unreachable on Windows
      final ping = RakNet.ping(DateTime.now().millisecondsSinceEpoch, RakNet.randomGuid());
      sock.send(ping, addr, port);
      // UDP may drop the first probe: retry once half-way through
      final retry = Timer(timeout ~/ 2, () => sock.send(ping, addr, port));
      final r = await c.future.timeout(timeout, onTimeout: () => null);
      retry.cancel();
      return r;
    } catch (_) {
      return null;
    } finally {
      s?.close();
    }
  }

  /// Detects a local Bedrock world ("对局域网玩家可见") or Bedrock Dedicated Server by pinging
  /// 127.0.0.1 on [ports] (19132 / 19133). Returns (pong info, UDP port) or null.
  static Future<(BedrockServerInfo, int)?> detectLocalBedrock(
      {List<int> ports = const [RakNet.defaultPort4, RakNet.defaultPort6], Duration timeout = const Duration(seconds: 2)}) async {
    final results = await Future.wait([
      for (final p in ports) pingBedrock(InternetAddress.loopbackIPv4, p, timeout: timeout).then((i) => i == null ? null : (i, p)),
    ]);
    for (final r in results) {
      if (r != null) return r;
    }
    return null;
  }

  /// Creates a Bedrock room forwarding guest UDP flows to the local Bedrock server at
  /// 127.0.0.1:[udpPort]. [info] is the pong shown to guests (pinged when null).
  /// With [publicUdp] the host asks CMLS to also expose the room on its public UDP port
  /// (only effective if the server owner enabled `--public-udp`; see [publicUdpPort]).
  Future<String> hostBedrock({
    required String title,
    int udpPort = RakNet.defaultPort4,
    BedrockServerInfo? info,
    String password = '',
    bool public = true,
    bool publicUdp = false,
  }) async {
    info ??= await pingBedrock(hostUdpAddress, udpPort) ?? const BedrockServerInfo();
    hostUdpPort = udpPort;
    bedrockInfo = info;
    isHost = true;
    final r = await request({
      't': 'host',
      'title': title,
      'version': info.version,
      'password': password,
      'public': public,
      'edition': 'bedrock',
      'bedrock': info.toJson(),
      'publicUdp': publicUdp,
    });
    if (r['edition'] != 'bedrock') {
      _send({'t': 'leave'});
      throw const CmlException('server_too_old', '该联机服务器版本过旧，不支持基岩版房间，请让服主升级 CMLS');
    }
    edition = 'bedrock';
    roomTitle = title;
    publicUdpPort = (r['publicUdp'] as num?)?.toInt();
    _startFlowSweep();
    _infoTimer?.cancel();
    _infoTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final now = await pingBedrock(hostUdpAddress, udpPort);
      final old = bedrockInfo;
      if (now == null || room == null || !isHost || !isBedrock) return;
      bedrockInfo = now;
      if (old == null || now.differs(old)) _send({'t': 'binfo', 'bedrock': now.toJson()});
    });
    return room = '${r['room']}';
  }

  Future<void> _hostUOpen(int sid) async {
    if (!isHost || hostUdpPort == null) return;
    final old = _hostFlows[sid];
    if (old != null) {
      old.closed = true;
      old.sock?.close();
    }
    final f = _HostFlow();
    _hostFlows[sid] = f;
    try {
      final s = await RawDatagramSocket.bind(
          hostUdpAddress.type == InternetAddressType.IPv6 ? InternetAddress.loopbackIPv6 : InternetAddress.loopbackIPv4, 0);
      if (f.closed || _hostFlows[sid] != f) {
        s.close();
        return;
      }
      f.sock = s;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = s.receive()) != null) {
          // only accept replies from the Bedrock server itself
          if (d!.port != hostUdpPort || d.address.address != hostUdpAddress.address) continue;
          f.last = DateTime.now().millisecondsSinceEpoch;
          _sendDatagram(sid, d.data, f.up);
        }
      }, onError: (_) {}); // e.g. ICMP port unreachable on Windows
      for (final d in f.pending) {
        s.send(d, hostUdpAddress, hostUdpPort!);
      }
      f.pending.clear();
    } catch (_) {
      _hostFlows.remove(sid);
      _send({'t': 'uclose', 'sid': sid});
    }
  }

  void _onDatagram(int sid, Uint8List d) {
    if (isHost) {
      final f = _hostFlows[sid];
      if (f == null) return;
      f.last = DateTime.now().millisecondsSinceEpoch;
      final s = f.sock;
      if (s != null) {
        s.send(d, hostUdpAddress, hostUdpPort!);
      } else if (f.pending.length < 16) {
        f.pending.add(Uint8List.fromList(d));
      }
    } else {
      final f = _guestFlows[sid];
      if (f == null) return;
      f.last = DateTime.now().millisecondsSinceEpoch;
      _udp?.send(d, f.addr, f.port);
    }
  }

  /// Forgets a flow without notifying the server.
  void _closeFlowLocal(int sid) {
    final h = _hostFlows.remove(sid);
    if (h != null) {
      h.closed = true;
      h.sock?.close();
    }
    final g = _guestFlows.remove(sid);
    if (g != null) _guestFlowByEndpoint.remove('${g.addr.address}:${g.port}');
  }

  void _startFlowSweep() {
    _flowTimer?.cancel();
    _flowTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final cutoff = DateTime.now().millisecondsSinceEpoch - TunnelLimits.flowIdle.inMilliseconds;
      final idle = [
        for (final e in _hostFlows.entries)
          if (e.value.last < cutoff) e.key,
        for (final e in _guestFlows.entries)
          if (e.value.last < cutoff) e.key,
      ];
      for (final sid in idle) {
        _closeFlowLocal(sid);
        _send({'t': 'uclose', 'sid': sid});
      }
    });
  }

  /// Number of open UDP flows (diagnostics / tests).
  int get udpFlowCount => _hostFlows.length + _guestFlows.length;

  // ---------------- guest ----------------

  Future<List<RoomInfo>> rooms() async {
    final r = await request({'t': 'rooms'});
    return [for (final j in r['list'] as List) RoomInfo.fromJson(j as Map)];
  }

  /// Joins [roomId] and exposes it locally: a TCP listener on 127.0.0.1 plus LAN broadcast,
  /// so the room shows up in Minecraft's multiplayer list. Returns the local port.
  ///
  /// Bedrock rooms instead bind UDP 0.0.0.0:19132 (or [localPort]; falls back to a free port when busy,
  /// see [bedrockLanDiscoverable]) and answer RakNet LAN discovery pings with the room's pong, so the
  /// room shows up under Friends → LAN Games. Only datagrams from this machine are accepted unless
  /// [allowLanClients] (lets phones / consoles on the same LAN join through this PC).
  Future<int> join(String roomId, {String password = '', int localPort = 0, bool allowLanClients = false}) async {
    final r = await request({'t': 'join', 'room': roomId.toUpperCase(), 'password': password});
    room = '${r['room']}';
    isHost = false;
    roomTitle = '${r['title']}';
    if (r['edition'] == 'bedrock') {
      edition = 'bedrock';
      bedrockInfo = BedrockServerInfo.fromJson(r['bedrock']);
      try {
        return await _joinBedrock(localPort: localPort, allowLanClients: allowLanClients);
      } catch (e) {
        await leave();
        throw e is CmlException ? e : CmlException('udp_bind', '无法监听本地 UDP 端口', e);
      }
    }
    edition = 'java';
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

  Future<int> _joinBedrock({int localPort = 0, bool allowLanClients = false}) async {
    _allowLanClients = allowLanClients;
    _localAddrs = {'127.0.0.1', '::1'};
    try {
      for (final i in await NetworkInterface.list(includeLoopback: true, type: InternetAddressType.any)) {
        for (final a in i.addresses) {
          _localAddrs.add(a.address);
        }
      }
    } catch (_) {}
    RawDatagramSocket s;
    final want = localPort == 0 ? RakNet.defaultPort4 : localPort;
    try {
      // no SO_REUSEADDR: on Windows it would let us silently share the port with a local Bedrock server
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, want, reuseAddress: false);
    } on SocketException {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: false);
    }
    s.broadcastEnabled = true;
    _udp = s;
    bedrockLocalPort = s.port;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = s.receive()) != null) {
        _onLocalUdp(d!);
      }
    }, onError: (_) {}); // e.g. ICMP port unreachable on Windows
    _startFlowSweep();
    return s.port;
  }

  /// The pong this guest answers LAN discovery with.
  BedrockServerInfo guestPongInfo() {
    final b = bedrockInfo ?? const BedrockServerInfo();
    return b.copyWith(
      motd: roomTitle.isEmpty ? 'CML' : roomTitle,
      subMotd: 'CML ${room ?? ''}'.trim(),
      guid: _pongGuid.toUnsigned(64).toString(),
      port4: bedrockLocalPort,
      port6: bedrockLocalPort,
    );
  }

  void _onLocalUdp(Datagram d) {
    if (d.data.isEmpty || d.data.length > TunnelLimits.maxDatagram) return;
    if (!_allowLanClients && !_localAddrs.contains(d.address.address)) return;
    final pingTime = RakNet.parsePing(d.data);
    if (pingTime != null) {
      _udp?.send(RakNet.pong(pingTime, _pongGuid, guestPongInfo().encode()), d.address, d.port);
      return;
    }
    final key = '${d.address.address}:${d.port}';
    var sid = _guestFlowByEndpoint[key];
    if (sid == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final until = _flowCooldown[key];
      if (until != null) {
        if (now < until) {
          droppedDatagrams++;
          return;
        }
        _flowCooldown.remove(key);
      }
      if (_flowCooldown.length > 256) _flowCooldown.removeWhere((_, t) => t < now);
      if (_guestFlows.length >= TunnelLimits.maxFlowsPerGuest) {
        droppedDatagrams++;
        return;
      }
      sid = _nextSid++;
      _guestFlows[sid] = _GuestFlow(d.address, d.port);
      _guestFlowByEndpoint[key] = sid;
      _send({'t': 'uopen', 'sid': sid});
    }
    final f = _guestFlows[sid]!;
    f.last = DateTime.now().millisecondsSinceEpoch;
    _sendDatagram(sid, d.data, f.up);
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
    _flowTimer?.cancel();
    _infoTimer?.cancel();
    _udp?.close();
    _udp = null;
    bedrockLocalPort = null;
    publicUdpPort = null;
    for (final f in _hostFlows.values) {
      f.closed = true;
      f.sock?.close();
    }
    _hostFlows.clear();
    _guestFlows.clear();
    _guestFlowByEndpoint.clear();
    _flowCooldown.clear();
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
    _out?.close();
    _out = null;
    final s = _sock;
    _sock = null;
    s?.destroy();
  }
}
