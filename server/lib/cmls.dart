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
  ServerConfig({
    this.port = TunnelLimits.defaultPort,
    this.name = 'CMLS',
    this.motd = '',
    this.password = '',
    this.maxRooms = 200,
    this.maxPerIp = 8,
    this.maxConnections = 1000,
  });

  Map<String, Object?> toJson() =>
      {'port': port, 'name': name, 'motd': motd, 'password': password, 'maxRooms': maxRooms, 'maxPerIp': maxPerIp, 'maxConnections': maxConnections};

  static ServerConfig fromJson(Map j) => ServerConfig(
        port: (j['port'] as num?)?.toInt() ?? TunnelLimits.defaultPort,
        name: '${j['name'] ?? 'CMLS'}',
        motd: '${j['motd'] ?? ''}',
        password: '${j['password'] ?? ''}',
        maxRooms: (j['maxRooms'] as num?)?.toInt() ?? 200,
        maxPerIp: (j['maxPerIp'] as num?)?.toInt() ?? 8,
        maxConnections: (j['maxConnections'] as num?)?.toInt() ?? 1000,
      );
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

  Room(this.id, this.host, this.title, this.version, this.passwordHash, this.public);

  bool get locked => passwordHash.isNotEmpty;
  int allocSid() => _nextSid++;
}

/// One connected client.
class Peer {
  final Socket socket;
  final String ip;
  final int id;
  final _dec = FrameDecoder();
  SecureChannel? ch;
  String name = '';
  bool authed = false;
  Room? room;
  DateTime lastSeen = DateTime.now();

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

  CmlsServer(this.config, this.identity, {this.log = print});

  Iterable<Peer> get peers => _peers;

  Future<void> start({InternetAddress? bind}) async {
    _server = await ServerSocket.bind(bind ?? InternetAddress.anyIPv6, config.port, v6Only: false);
    _server!.listen(_accept);
    _sweep = Timer.periodic(const Duration(seconds: 30), (_) => _sweepIdle());
    log('CMLS 已启动：端口 ${config.port}，服务器指纹 ${identity.fingerprint}');
  }

  int get port => _server?.port ?? config.port;

  Future<void> stop() async {
    _sweep?.cancel();
    await _server?.close();
    final all = _peers.toList();
    _peers.clear();
    rooms.clear();
    for (final p in all) {
      p.socket.destroy();
    }
  }

  void ban(String ip) {
    _bannedIps.add(ip);
    for (final p in _peers.where((p) => p.ip == ip).toList()) {
      _drop(p);
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
    p.lastSeen = DateTime.now();
    if (p.ch == null) {
      if (f.kind != FrameKind.hello) throw const FormatException('expected hello');
      final (reply, ch) = ServerHandshake(identity).respond((jsonDecode(utf8.decode(f.payload)) as Map).cast<String, dynamic>());
      p.socket.add(Frame.encode(FrameKind.hello, utf8.encode(jsonEncode(reply))));
      p.ch = ch;
      return;
    }
    final plain = p.ch!.open(f.kind, f.payload);
    if (f.kind == FrameKind.data) {
      if (!p.authed) throw const FormatException('not authed');
      _relayData(p, plain);
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
    try {
      p.socket.add(Frame.encode(kind, ch.seal(kind, plain)));
    } on SocketException {
      _drop(p);
    }
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
          ..authed = true;
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
              {'room': r.id, 'title': r.title, 'version': r.version, 'host': r.host.name, 'players': r.guests.length + 1, 'locked': r.locked}
          ]
        });
      case 'host':
        if (p.room != null) _leave(p);
        if (rooms.length >= config.maxRooms) return _error(p, '服务器房间已满');
        if (rooms.values.where((r) => r.host.ip == p.ip).length >= 3) return _error(p, '你创建的房间过多');
        final id = _newRoomId();
        final pw = '${m['password'] ?? ''}';
        final r = Room(id, p, cleanName('${m['title'] ?? ''}', 48).isEmpty ? '${p.name} 的世界' : cleanName('${m['title']}', 48),
            cleanName('${m['version'] ?? ''}', 32), pw.isEmpty ? '' : _hash(id, pw), m['public'] != false);
        rooms[id] = r;
        p.room = r;
        _send(p, {'t': 'hosted', 'room': id});
        log('房间 $id 创建：${r.title}（${p.name} @ ${p.ip}）');
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
        if (r.guests.length >= 64) return _error(p, '房间已满');
        if (p.room != null) _leave(p);
        r.guests.add(p);
        r.guestToGlobal[p] = {};
        p.room = r;
        _send(p, {'t': 'joined', 'room': r.id, 'title': r.title, 'version': r.version, 'host': r.host.name});
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
      for (final g in r.guests) {
        g.room = null;
        _send(g, {'t': 'closed', 'reason': '房主已关闭房间'});
      }
      log('房间 ${r.id} 已关闭');
      return;
    }
    r.guests.remove(p);
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
