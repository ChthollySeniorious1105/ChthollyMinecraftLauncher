import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cml_core/tunnel.dart';
import 'package:crypto/crypto.dart';

class ServerConfig {
  int port;
  String name;
  String motd;

  /// Optional server password required at `auth`.
  String password;
  int maxRooms;
  int maxPerIp;
  int maxConnections;

  /// Public game-facing Bedrock UDP endpoint (0 = off, -1 = ephemeral port for tests). See [CmlsServer].
  int publicUdpPort;

  /// Room exposed on [publicUdpPort]; empty = the first password-less Bedrock room whose host asked for `publicUdp`.
  String publicUdpRoom;

  /// Max concurrent internet clients on the public UDP port, in total and per source IP.
  int publicUdpMaxFlows;
  int publicUdpMaxPerIp;
  ServerConfig({
    this.port = TunnelLimits.defaultPort,
    this.name = 'CMLS',
    this.motd = '',
    this.password = '',
    this.maxRooms = 200,
    this.maxPerIp = 8,
    this.maxConnections = 1000,
    this.publicUdpPort = 0,
    this.publicUdpRoom = '',
    this.publicUdpMaxFlows = 32,
    this.publicUdpMaxPerIp = 4,
  });

  Map<String, Object?> toJson() => {
        'port': port,
        'name': name,
        'motd': motd,
        'password': password,
        'maxRooms': maxRooms,
        'maxPerIp': maxPerIp,
        'maxConnections': maxConnections,
        'publicUdpPort': publicUdpPort,
        'publicUdpRoom': publicUdpRoom,
        'publicUdpMaxFlows': publicUdpMaxFlows,
        'publicUdpMaxPerIp': publicUdpMaxPerIp,
      };

  static ServerConfig fromJson(Map j) => ServerConfig(
        port: (j['port'] as num?)?.toInt() ?? TunnelLimits.defaultPort,
        name: '${j['name'] ?? 'CMLS'}',
        motd: '${j['motd'] ?? ''}',
        password: '${j['password'] ?? ''}',
        maxRooms: (j['maxRooms'] as num?)?.toInt() ?? 200,
        maxPerIp: (j['maxPerIp'] as num?)?.toInt() ?? 8,
        maxConnections: (j['maxConnections'] as num?)?.toInt() ?? 1000,
        publicUdpPort: (j['publicUdpPort'] as num?)?.toInt() ?? 0,
        publicUdpRoom: '${j['publicUdpRoom'] ?? ''}',
        publicUdpMaxFlows: (j['publicUdpMaxFlows'] as num?)?.toInt() ?? 32,
        publicUdpMaxPerIp: (j['publicUdpMaxPerIp'] as num?)?.toInt() ?? 4,
      );
}

/// One UDP flow of a Bedrock room: a guest CML endpoint, or a public internet client.
class UdpFlow {
  final int id;
  final Peer? guest;
  final int guestSid;
  final InternetAddress? addr; // public flows only
  final int port;
  DateTime last = DateTime.now();
  final toHost = TokenBucket();
  final fromHost = TokenBucket();
  UdpFlow.guest(this.id, Peer this.guest, this.guestSid)
      : addr = null,
        port = 0;
  UdpFlow.public(this.id, InternetAddress this.addr, this.port)
      : guest = null,
        guestSid = 0;
  bool get isPublic => guest == null;
  String get endpoint => '${addr?.address}:$port';
}

class Room {
  final String id;
  final Peer host;
  final String title;
  final String version;
  final String passwordHash;
  final bool public;
  final Set<Peer> guests = {};
  final DateTime created = DateTime.now();

  /// Routing: global stream id → (guest, guest-local sid). Host sees global ids.
  final Map<int, (Peer, int)> streams = {};
  final Map<Peer, Map<int, int>> guestToGlobal = {};
  int _nextSid = 1;

  /// Failed password attempts per IP and lock-until.
  final Map<String, (int, DateTime)> failures = {};

  /// `java` or `bedrock`.
  final String edition;

  /// Bedrock pong info reported by the host (sanitised).
  BedrockServerInfo bedrock;

  /// Host asked to be exposed on the server's public UDP port.
  final bool wantsPublicUdp;

  /// UDP flows: room-wide flow id → flow. Guest flows are also indexed by guest → (guest-local id → flow id),
  /// public internet flows by source endpoint `ip:port`.
  final Map<int, UdpFlow> flows = {};
  final Map<Peer, Map<int, int>> guestFlows = {};
  final Map<String, int> publicFlows = {};

  Room(this.id, this.host, this.title, this.version, this.passwordHash, this.public,
      {this.edition = 'java', this.bedrock = const BedrockServerInfo(), this.wantsPublicUdp = false});

  bool get locked => passwordHash.isNotEmpty;
  bool get isBedrock => edition == 'bedrock';
  int allocSid() => _nextSid++;
}

/// One connected client.
class Peer {
  final Socket socket;
  final String ip;
  final int id;
  final _dec = FrameDecoder();
  late final FrameWriter out = FrameWriter(socket);
  Set<String> caps = {};
  SecureChannel? ch;
  String name = '';
  bool authed = false;
  Room? room;
  DateTime lastSeen = DateTime.now();

  /// Aggregate datagram budget for everything this peer sends (all of its flows).
  final dgram = TokenBucket(packetRate: 8000, byteRate: 8 * 1024 * 1024);

  // simple token bucket for control messages
  double _tokens = 30;
  DateTime _refill = DateTime.now();

  Peer(this.socket, this.id) : ip = socket.remoteAddress.address;

  bool allowControl() {
    final now = DateTime.now();
    _tokens = min(30, _tokens + now.difference(_refill).inMilliseconds / 100); // 10/s
    _refill = now;
    if (_tokens < 1) return false;
    _tokens--;
    return true;
  }
}

/// CMLS relay server.
///
/// Relays Java TCP streams ([FrameKind.data]) and Bedrock UDP flows ([FrameKind.datagram]) between a room's
/// host and its guests over the encrypted tunnel. Optionally ([ServerConfig.publicUdpPort]) it is also a
/// game-facing Bedrock "server": it answers RakNet Unconnected Pings on that UDP port with the room's pong
/// and relays raw RakNet datagrams from any internet client to the host's game. That exposes the host's
/// game to the internet like a normal public server (room passwords do not apply there — only the game's
/// own online-mode / allow-list does), so it is off by default, rate limited per source IP and capped in flows.
class CmlsServer {
  final ServerConfig config;
  final ServerIdentity identity;
  final void Function(String) log;
  ServerSocket? _server;
  final _peers = <Peer>{};
  final rooms = <String, Room>{};
  final _bannedIps = <String>{};
  int _nextPeer = 1;
  Timer? _sweep;
  Timer? _flowSweep;
  RawDatagramSocket? _publicUdp;

  /// Room that claimed the public UDP port (host opt-in mode).
  String? _publicClaim;
  final _pingBuckets = <String, TokenBucket>{};
  final _newFlowBuckets = <String, TokenBucket>{};
  final _globalPings = TokenBucket(packetRate: 200, byteRate: 200 * 64.0);

  /// Datagrams dropped by rate limits / backpressure (diagnostics).
  int droppedDatagrams = 0;

  CmlsServer(this.config, this.identity, {this.log = print});

  Iterable<Peer> get peers => _peers;

  Future<void> start({InternetAddress? bind}) async {
    _server = await ServerSocket.bind(bind ?? InternetAddress.anyIPv6, config.port, v6Only: false);
    _server!.listen(_accept);
    _sweep = Timer.periodic(const Duration(seconds: 30), (_) => _sweepIdle());
    _flowSweep = Timer.periodic(const Duration(seconds: 5), (_) => _sweepFlows());
    if (config.publicUdpPort != 0) {
      final u = await RawDatagramSocket.bind(bind ?? InternetAddress.anyIPv4, config.publicUdpPort < 0 ? 0 : config.publicUdpPort);
      _publicUdp = u;
      u.listen((e) {
        if (e != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = u.receive()) != null) {
          _onPublicUdp(d!);
        }
      }, onError: (_) {}); // e.g. ICMP port unreachable on Windows
      log('基岩版公网 UDP 入口已开启：UDP ${u.port}（被公开的房间会像普通公网服务器一样暴露给任何人）');
    }
    log('CMLS 已启动：端口 ${config.port}，服务器指纹 ${identity.fingerprint}');
  }

  int get port => _server?.port ?? config.port;

  /// Bound public Bedrock UDP port, or null when disabled.
  int? get publicUdpPort => _publicUdp?.port;

  /// The room currently exposed on the public UDP port.
  Room? get publicRoom {
    if (_publicUdp == null) return null;
    final id = config.publicUdpRoom.isNotEmpty ? config.publicUdpRoom.toUpperCase() : _publicClaim;
    final r = id == null ? null : rooms[id];
    return r != null && r.isBedrock ? r : null;
  }

  /// Points the public UDP port at [roomId] (empty = host opt-in mode). Existing public flows are closed.
  void setPublicUdpRoom(String roomId) {
    for (final r in rooms.values) {
      _closePublicFlows(r);
    }
    config.publicUdpRoom = roomId.toUpperCase();
  }

  Future<void> stop() async {
    _sweep?.cancel();
    _flowSweep?.cancel();
    _publicUdp?.close();
    _publicUdp = null;
    await _server?.close();
    final all = _peers.toList();
    _peers.clear();
    rooms.clear();
    for (final p in all) {
      p.out.close();
      p.socket.destroy();
    }
  }

  void ban(String ip) {
    _bannedIps.add(ip);
    for (final p in _peers.where((p) => p.ip == ip).toList()) {
      _drop(p);
    }
    for (final r in rooms.values) {
      for (final f in r.flows.values.where((f) => f.isPublic && f.addr!.address == ip).toList()) {
        _closeFlow(r, f);
      }
    }
  }

  void _accept(Socket s) {
    final ip = s.remoteAddress.address;
    if (_bannedIps.contains(ip) || _peers.length >= config.maxConnections || _peers.where((p) => p.ip == ip).length >= config.maxPerIp) {
      s.destroy();
      return;
    }
    s.setOption(SocketOption.tcpNoDelay, true);
    s.done.catchError((_) {}); // write errors on dead sockets are reported here
    final p = Peer(s, _nextPeer++);
    p.out; // all writes go through the backpressure-aware writer
    _peers.add(p);
    final hsTimer = Timer(TunnelLimits.handshakeTimeout, () {
      if (!p.authed) _drop(p);
    });
    s.listen((chunk) {
      try {
        for (final f in p._dec.add(chunk)) {
          _onFrame(p, f);
        }
      } catch (_) {
        _drop(p); // never echo internal errors
      }
    }, onDone: () {
      hsTimer.cancel();
      _drop(p);
    }, onError: (_) => _drop(p), cancelOnError: true);
  }

  void _onFrame(Peer p, Frame f) {
    if (!_peers.contains(p)) return;
    p.lastSeen = DateTime.now();
    if (p.ch == null) {
      if (f.kind != FrameKind.hello) throw const FormatException('expected hello');
      final (reply, ch) = ServerHandshake(identity).respond((jsonDecode(utf8.decode(f.payload)) as Map).cast<String, dynamic>());
      p.out.add(Frame.encode(FrameKind.hello, utf8.encode(jsonEncode(reply))));
      p.ch = ch;
      return;
    }
    final plain = p.ch!.open(f.kind, f.payload);
    if (f.kind == FrameKind.data) {
      if (!p.authed) throw const FormatException('not authed');
      _relayData(p, plain);
      return;
    }
    if (f.kind == FrameKind.datagram) {
      if (!p.authed) throw const FormatException('not authed');
      final d = Frame.parseDatagram(plain);
      if (d == null) throw const FormatException('bad datagram');
      _relayDatagram(p, d.$1, d.$2);
      return;
    }
    if (f.kind != FrameKind.control) throw const FormatException('bad kind');
    if (!p.allowControl()) return;
    _onControl(p, (jsonDecode(utf8.decode(plain)) as Map).cast<String, dynamic>());
  }

  void _send(Peer p, Map<String, Object?> m) => _write(p, FrameKind.control, Frame.json(m));

  void _sendData(Peer p, int sid, List<int> bytes, int start) => _write(p, FrameKind.data, Frame.dataPayload(sid, bytes, start));

  void _write(Peer p, int kind, List<int> plain) {
    final ch = p.ch;
    if (ch == null || !_peers.contains(p)) return;
    p.out.add(Frame.encode(kind, ch.seal(kind, plain)));
  }

  /// Datagrams are dropped (never queued) when the receiver's tunnel is backpressured.
  void _writeDatagram(Peer p, int sid, List<int> d) {
    if (p.out.congested) {
      droppedDatagrams++;
      return;
    }
    _write(p, FrameKind.datagram, Frame.datagramPayload(sid, d));
  }

  void _error(Peer p, String msg) => _send(p, {'t': 'error', 'message': msg});

  /// Strips control and Unicode bidi characters, trims, and caps length.
  static String cleanName(String s, int max) {
    final t = s.replaceAll(RegExp('[\\x00-\\x1f\\x7f\\u200e\\u200f\\u202a-\\u202e\\u2066-\\u2069]'), '').trim();
    return (t.length > max ? t.substring(0, max) : t).trim();
  }

  void _onControl(Peer p, Map<String, dynamic> m) {
    final t = '${m['t']}';
    if (!p.authed && t != 'auth') return _drop(p);
    switch (t) {
      case 'auth':
        if (config.password.isNotEmpty && !_constEq('${m['password'] ?? ''}', config.password)) {
          _error(p, '服务器密码错误');
          Timer(const Duration(milliseconds: 500), () => _drop(p));
          return;
        }
        var name = cleanName('${m['name'] ?? ''}', 32);
        if (name.isEmpty) name = '玩家${p.id}';
        p
          ..name = name
          ..authed = true
          ..caps = {if (m['caps'] is List) for (final c in (m['caps'] as List).take(16)) '$c'};
        _send(p, {'t': 'ok', 'server': config.name, 'motd': config.motd});
      case 'ping':
        _send(p, {'t': 'pong', 'ts': m['ts']});
      case 'pong':
        break;
      case 'rooms':
        _send(p, {
          't': 'rooms',
          'list': [
            for (final r in rooms.values.where((r) => r.public))
              {
                'room': r.id,
                'title': r.title,
                'version': r.version,
                'host': r.host.name,
                'players': r.guests.length + 1,
                'locked': r.locked,
                'edition': r.edition,
              }
          ]
        });
      case 'host':
        if (p.room != null) _leave(p);
        if (rooms.length >= config.maxRooms) return _error(p, '服务器房间已满');
        if (rooms.values.where((r) => r.host.ip == p.ip).length >= 3) return _error(p, '你创建的房间过多');
        final id = _newRoomId();
        final pw = '${m['password'] ?? ''}';
        final bedrock = m['edition'] == 'bedrock';
        final r = Room(id, p, cleanName('${m['title'] ?? ''}', 48).isEmpty ? '${p.name} 的世界' : cleanName('${m['title']}', 48),
            cleanName('${m['version'] ?? ''}', 32), pw.isEmpty ? '' : _hash(id, pw), m['public'] != false,
            edition: bedrock ? 'bedrock' : 'java',
            bedrock: bedrock ? BedrockServerInfo.fromJson(m['bedrock']) : const BedrockServerInfo(),
            wantsPublicUdp: bedrock && m['publicUdp'] == true);
        rooms[id] = r;
        p.room = r;
        // A host may claim the public UDP port only while it is free and only for a password-less room
        // (the public port bypasses room passwords). The owner can pin a room with --public-udp-room.
        if (r.wantsPublicUdp && _publicUdp != null && config.publicUdpRoom.isEmpty && publicRoom == null && !r.locked) {
          _publicClaim = id;
        }
        final exposed = publicRoom == r;
        _send(p, {'t': 'hosted', 'room': id, if (bedrock) 'edition': 'bedrock', if (exposed) 'publicUdp': _publicUdp!.port});
        log('房间 $id 创建：${r.title}（${p.name} @ ${p.ip}）${bedrock ? ' [基岩版]' : ''}${exposed ? ' [公网 UDP ${_publicUdp!.port}]' : ''}');
        _roster(r);
      case 'join':
        final r = rooms['${m['room'] ?? ''}'.toUpperCase()];
        if (r == null) return _error(p, '房间不存在');
        if (r.host == p) return _error(p, '不能加入自己的房间');
        if (r.locked) {
          final f = r.failures[p.ip];
          if (f != null && f.$1 >= 5 && DateTime.now().isBefore(f.$2)) return _error(p, '密码错误次数过多，请 2 分钟后再试');
          if (!_constEq(_hash(r.id, '${m['password'] ?? ''}'), r.passwordHash)) {
            final n = (f?.$1 ?? 0) + 1;
            r.failures[p.ip] = (n, DateTime.now().add(const Duration(minutes: 2)));
            return _error(p, '房间密码错误');
          }
          r.failures.remove(p.ip);
        }
        if (r.isBedrock && !p.caps.contains('bedrock')) return _error(p, '这是基岩版房间，你的 CML 版本过旧，请先更新');
        if (r.guests.length >= 64) return _error(p, '房间已满');
        if (p.room != null) _leave(p);
        r.guests.add(p);
        r.guestToGlobal[p] = {};
        r.guestFlows[p] = {};
        p.room = r;
        _send(p, {
          't': 'joined',
          'room': r.id,
          'title': r.title,
          'version': r.version,
          'host': r.host.name,
          'edition': r.edition,
          if (r.isBedrock) 'bedrock': r.bedrock.toJson(),
        });
        _roster(r);
      case 'leave':
        _leave(p);
      case 'open': // guest opens a stream
        final r = p.room;
        if (r == null || r.host == p) return;
        final local = (m['sid'] as num?)?.toInt();
        if (local == null || r.guestToGlobal[p]!.length >= 32) return;
        final g = r.allocSid();
        r.streams[g] = (p, local);
        r.guestToGlobal[p]![local] = g;
        _send(r.host, {'t': 'open', 'sid': g});
      case 'binfo': // host refreshes the Bedrock pong info
        final r = p.room;
        if (r == null || r.host != p || !r.isBedrock) return;
        r.bedrock = BedrockServerInfo.fromJson(m['bedrock']);
        for (final g in r.guests) {
          _send(g, {'t': 'binfo', 'bedrock': r.bedrock.toJson()});
        }
      case 'uopen': // guest opens a UDP flow
        final r = p.room;
        if (r == null || r.host == p || !r.isBedrock) return;
        final local = (m['sid'] as num?)?.toInt();
        final mine = r.guestFlows[p]!;
        if (local == null || mine.containsKey(local)) return;
        if (mine.length >= TunnelLimits.maxFlowsPerGuest || _guestFlowCount(r) >= TunnelLimits.maxFlowsPerRoom) {
          _send(p, {'t': 'uclose', 'sid': local});
          return;
        }
        final g = r.allocSid();
        r.flows[g] = UdpFlow.guest(g, p, local);
        mine[local] = g;
        _send(r.host, {'t': 'uopen', 'sid': g, 'src': 'guest'});
      case 'uclose':
        final r = p.room;
        final sid = (m['sid'] as num?)?.toInt();
        if (r == null || sid == null) return;
        if (r.host == p) {
          final f = r.flows[sid];
          if (f != null) _closeFlow(r, f, notifyHost: false);
        } else {
          final g = r.guestFlows[p]?[sid];
          final f = g == null ? null : r.flows[g];
          if (f != null) _closeFlow(r, f, notifyGuest: false);
        }
      case 'close':
        final r = p.room;
        final sid = (m['sid'] as num?)?.toInt();
        if (r == null || sid == null) return;
        if (r.host == p) {
          final route = r.streams.remove(sid);
          if (route != null) {
            r.guestToGlobal[route.$1]?.remove(route.$2);
            _send(route.$1, {'t': 'close', 'sid': route.$2});
          }
        } else {
          final g = r.guestToGlobal[p]?.remove(sid);
          if (g != null) {
            r.streams.remove(g);
            _send(r.host, {'t': 'close', 'sid': g});
          }
        }
    }
  }

  void _relayData(Peer p, Uint8List plain) {
    final r = p.room;
    if (r == null || plain.length < 4) return;
    final sid = ByteData.sublistView(plain, 0, 4).getUint32(0);
    if (r.host == p) {
      final route = r.streams[sid];
      if (route != null) _sendData(route.$1, route.$2, plain, 4);
    } else {
      final g = r.guestToGlobal[p]?[sid];
      if (g != null) _sendData(r.host, g, plain, 4);
    }
  }

  // ---------------- Bedrock UDP flows ----------------

  int _guestFlowCount(Room r) => r.flows.values.where((f) => !f.isPublic).length;

  void _relayDatagram(Peer p, int sid, Uint8List d) {
    final r = p.room;
    if (r == null || !r.isBedrock) return;
    if (!p.dgram.allow(d.length)) {
      droppedDatagrams++;
      return;
    }
    if (r.host == p) {
      final f = r.flows[sid];
      if (f == null) return;
      if (!f.fromHost.allow(d.length)) {
        droppedDatagrams++;
        return;
      }
      f.last = DateTime.now();
      if (f.isPublic) {
        _publicUdp?.send(d, f.addr!, f.port);
      } else {
        _writeDatagram(f.guest!, f.guestSid, d);
      }
    } else {
      final g = r.guestFlows[p]?[sid];
      final f = g == null ? null : r.flows[g];
      if (f == null) return;
      if (!f.toHost.allow(d.length)) {
        droppedDatagrams++;
        return;
      }
      f.last = DateTime.now();
      _writeDatagram(r.host, f.id, d);
    }
  }

  void _closeFlow(Room r, UdpFlow f, {bool notifyHost = true, bool notifyGuest = true}) {
    if (r.flows.remove(f.id) == null) return;
    if (f.isPublic) {
      r.publicFlows.remove(f.endpoint);
    } else {
      r.guestFlows[f.guest]?.remove(f.guestSid);
      if (notifyGuest) _send(f.guest!, {'t': 'uclose', 'sid': f.guestSid});
    }
    if (notifyHost) _send(r.host, {'t': 'uclose', 'sid': f.id});
  }

  void _closePublicFlows(Room r) {
    for (final f in r.flows.values.where((f) => f.isPublic).toList()) {
      _closeFlow(r, f);
    }
  }

  void _sweepFlows() {
    final cutoff = DateTime.now().subtract(TunnelLimits.flowIdle);
    for (final r in rooms.values) {
      for (final f in r.flows.values.where((f) => f.last.isBefore(cutoff)).toList()) {
        _closeFlow(r, f);
      }
    }
    // forget rate-limit state of quiet sources
    if (_pingBuckets.length > 4096) _pingBuckets.clear();
    if (_newFlowBuckets.length > 4096) _newFlowBuckets.clear();
  }

  /// Stable pong guid of this server (derived from its identity key).
  late final int _serverGuid = identity.publicKey.take(8).fold<int>(0, (a, b) => (a << 8) | b) & 0x7fffffffffffffff;

  /// Game-facing public UDP endpoint: answers LAN-style pings and relays RakNet to the exposed room's host.
  void _onPublicUdp(Datagram d) {
    final ip = d.address.address;
    if (d.data.isEmpty || d.data.length > TunnelLimits.maxDatagram || _bannedIps.contains(ip)) return;
    final r = publicRoom;
    if (r == null) return;
    final key = '$ip:${d.port}';
    final existing = r.publicFlows[key];
    final pingTime = RakNet.parsePing(d.data);
    if (pingTime != null && existing == null) {
      // pongs are larger than pings: rate limit per source and globally against reflection abuse
      final b = _pingBuckets.putIfAbsent(ip, () => TokenBucket(packetRate: 4, byteRate: 4 * 64.0, packetBurst: 8, byteBurst: 8 * 64.0));
      if (!b.allow(d.data.length) || !_globalPings.allow(d.data.length)) return;
      final port = _publicUdp!.port;
      final info = r.bedrock.copyWith(motd: r.title, subMotd: config.name, guid: '$_serverGuid', port4: port, port6: port);
      _publicUdp!.send(RakNet.pong(pingTime, _serverGuid, info.encode()), d.address, d.port);
      return;
    }
    var f = existing == null ? null : r.flows[existing];
    if (f == null) {
      // a new flow only starts with RakNet Open Connection Request 1 — random junk allocates no state
      if (d.data[0] != RakNet.openConnectionRequest1) return;
      final nb = _newFlowBuckets.putIfAbsent(ip, () => TokenBucket(packetRate: 2, byteRate: 1e9, packetBurst: 6, byteBurst: 1e9));
      final perIp = r.publicFlows.keys.where((k) => k.startsWith('$ip:')).length;
      final total = r.publicFlows.length;
      if (perIp >= config.publicUdpMaxPerIp || total >= config.publicUdpMaxFlows || !nb.allow(1)) {
        droppedDatagrams++;
        return;
      }
      final id = r.allocSid();
      f = UdpFlow.public(id, d.address, d.port);
      r.flows[id] = f;
      r.publicFlows[key] = id;
      _send(r.host, {'t': 'uopen', 'sid': id, 'src': 'public'});
    }
    if (!f.toHost.allow(d.data.length)) {
      droppedDatagrams++;
      return;
    }
    f.last = DateTime.now();
    _writeDatagram(r.host, f.id, d.data);
  }

  void _roster(Room r) {
    final list = [r.host.name, for (final g in r.guests) g.name];
    for (final x in [r.host, ...r.guests]) {
      _send(x, {'t': 'members', 'list': list});
    }
  }

  void _leave(Peer p) {
    final r = p.room;
    if (r == null) return;
    p.room = null;
    if (r.host == p) {
      rooms.remove(r.id);
      if (_publicClaim == r.id) _publicClaim = null;
      r.flows.clear();
      r.publicFlows.clear();
      for (final g in r.guests) {
        g.room = null;
        _send(g, {'t': 'closed', 'reason': '房主已关闭房间'});
      }
      log('房间 ${r.id} 已关闭');
      return;
    }
    r.guests.remove(p);
    for (final g in (r.guestFlows.remove(p) ?? <int, int>{}).values) {
      r.flows.remove(g);
      _send(r.host, {'t': 'uclose', 'sid': g});
    }
    final mine = r.guestToGlobal.remove(p) ?? {};
    for (final g in mine.values) {
      r.streams.remove(g);
      _send(r.host, {'t': 'close', 'sid': g});
    }
    _roster(r);
  }

  void _drop(Peer p) {
    if (!_peers.remove(p)) return;
    _leave(p);
    p.out.close();
    p.socket.destroy();
  }

  void _sweepIdle() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 90));
    for (final p in _peers.where((p) => p.lastSeen.isBefore(cutoff)).toList()) {
      _drop(p);
    }
  }

  final _rng = Random.secure();
  String _newRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    while (true) {
      final id = String.fromCharCodes(List.generate(5, (_) => chars.codeUnitAt(_rng.nextInt(chars.length))));
      if (!rooms.containsKey(id)) return id;
    }
  }

  static String _hash(String salt, String pw) => sha256.convert(utf8.encode('cmls-room|$salt|$pw')).toString();

  static bool _constEq(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var d = x.length ^ y.length;
    for (var i = 0; i < min(x.length, y.length); i++) {
      d |= x[i] ^ y[i];
    }
    return d == 0;
  }
}
