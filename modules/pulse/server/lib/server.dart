import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pulse_shared/pulse_shared.dart';

import 'media_hub.dart';
import 'passwords.dart';
import 'store.dart';
import 'transfer_worker.dart';

export 'passwords.dart';
export 'store.dart';

/// Security limits.
const handshakeTimeout = Duration(seconds: 10);
const authTimeout = Duration(minutes: 3); // time to type credentials (pending sockets are capped per IP)
const idleTimeout = Duration(seconds: 60);
const maxConnectionsPerIp = 12;
const maxPendingPerIp = 4;
const maxConnections = 1000;
const maxSessionsPerUser = 20;
const sessionLifetime = Duration(days: 30);
const maxLoginFailures = 5; // per ip+username, then locked for [loginLockout]
const loginLockout = Duration(minutes: 5);
const maxIpAuthPerMinute = 20; // login/register attempts per IP per minute
const maxRegistrationsPerIpPerHour = 3;
const maxChannels = 100;
const maxUsers = 10000;
const maxRoles = 100;
const maxPendingUploadsPerUser = 20;
const uploadIdle = Duration(minutes: 30); // unfinished uploads are dropped after this
const ticketLifetime = Duration(minutes: 10);
const maxAuxPerUser = 8; // concurrent transfer connections
const mediaBacklog = 4 * 1024 * 1024; // bytes queued to a viewer before frames are skipped

void logLine(String s) {
  final t = DateTime.now().toIso8601String().substring(11, 19);
  stdout.writeln('[$t] $s');
}

/// Token bucket.
class Bucket {
  final double rate, burst;
  double _tokens;
  DateTime _last = DateTime.now();
  Bucket(this.rate, this.burst) : _tokens = burst;
  bool take([double n = 1]) {
    final now = DateTime.now();
    _tokens = min(burst, _tokens + now.difference(_last).inMicroseconds / 1e6 * rate);
    _last = now;
    if (_tokens < n) return false;
    _tokens -= n;
    return true;
  }
}

/// One TCP connection (a user may have several, e.g. two PCs).
class Conn {
  final int id;
  final Socket socket;
  final String ip;
  SecureChannel? channel;
  User? user;
  String? sessionHash;
  DateTime lastSeen = DateTime.now();
  bool closed = false;

  final msgs = Bucket(20, 60); // all JSON messages
  final chat = Bucket(1, 6); // chat messages: 1/s, burst 6
  final typing = Bucket(0.5, 2);
  final avatars = Bucket(20, 200); // avatar downloads (a fresh client fetches many at once)
  final avatarUploads = Bucket(1 / 30, 3);
  final searches = Bucket(1, 5);
  final voice = Bucket(40000, 60000); // bytes/s: 128 kbps Opus = 16 KB/s, headroom for overhead
  final uploads = Bucket(1, 20); // upload / download ticket requests
  final thumbs = Bucket(30, 300);

  /// Auxiliary connection state (file transfer / screen share), null for the main connection.
  String? auxKind;
  User? auxUser;
  TransferWorker? worker;
  List<Uint8List>? pendingWorkerInput; // upload frames that arrived before the worker started
  /// Auxiliary connections write through a queue: dart:io sockets reject add() while a
  /// flush is pending, and the flushes give us backpressure.
  final List<Uint8List> _queue = [];
  int queued = 0; // bytes queued or in flight
  bool _flushing = false;
  void Function(int frames)? onWritten; // after frames reached the OS

  void write(Uint8List frame) {
    if (closed) return;
    _queue.add(frame);
    queued += frame.length;
    if (!_flushing) _pump();
  }

  void _pump() {
    if (_queue.isEmpty || closed) {
      _flushing = false;
      return;
    }
    _flushing = true;
    final batch = List.of(_queue);
    _queue.clear();
    var bytes = 0;
    for (final f in batch) {
      socket.add(f);
      bytes += f.length;
    }
    socket.flush().then((_) {
      queued -= bytes;
      onWritten?.call(batch.length);
      _pump();
    }, onError: (_) {
      _flushing = false;
    });
  }
  final video = Bucket(kMaxStreamKbps * 125 * 1.5, 8 * 1024 * 1024); // bytes/s from a streamer

  Conn(this.id, this.socket, this.ip);

  void sendRaw(Uint8List frame) {
    final ch = channel;
    if (closed || ch == null) return;
    try {
      final kind = frame[4];
      socket.add(encodeFrame(kind, ch.seal(kind, Uint8List.sublistView(frame, 5))));
    } catch (_) {}
  }

  void send(Map<String, dynamic> m) => sendRaw(encodeJson(m));
}

/// Live voice state of a user (only one voice channel per user at a time).
class VoiceState {
  final int channel;
  final Conn conn;
  bool mute = false, deaf = false;
  VoiceState(this.channel, this.conn);
}

/// A screen share in a voice channel.
class StreamInfo {
  final int uid;
  int channel;
  int w, h, fps;
  String title;
  final Set<int> viewers = {}; // user ids
  StreamInfo(this.uid, this.channel, this.w, this.h, this.fps, this.title);
  Map<String, dynamic> toJson() => {'uid': uid, 'ch': channel, 'w': w, 'h': h, 'fps': fps, 'title': title, 'viewers': viewers.toList()};
}

/// One-time token that authorizes an auxiliary connection.
class Ticket {
  final int uid;
  final String kind; // upload | download | media
  final String file;
  final DateTime expires;
  Ticket(this.uid, this.kind, this.file) : expires = DateTime.now().add(ticketLifetime);
}

class PulseServer {
  final int port;
  final Store store;
  final ServerIdentity identity;
  final int? discoveryPort;
  ServerSocket? _socket;
  RawDatagramSocket? _udp;
  Timer? _sweeper;
  int _nextConn = 1;
  final Random _rng = Random.secure();

  final Set<Conn> conns = {};
  final Map<String, int> _connsPerIp = {};
  final Map<String, int> _pendingPerIp = {};
  final Map<int, VoiceState> voice = {}; // by user id
  final Set<int> serverMuted = {};
  final Map<int, int> _lastChat = {}; // uid -> epoch ms (slowmode)
  final Map<int, StreamInfo> streams = {}; // by streamer uid
  final Map<String, Ticket> _tickets = {};
  final Map<int, Conn> _media = {}; // uid -> media connection
  final Map<String, DateTime> _uploadActivity = {}; // file id -> last activity (unfinished uploads)
  MediaHub? _hub;

  /// IPs banned until restart (console `ban` / admin ban records the last IP).
  final Set<String> bannedIps = {};
  final Map<String, (int, DateTime)> _loginFails = {};
  final Map<String, Bucket> _ipAuth = {};
  final Map<String, List<DateTime>> _ipRegs = {};

  PulseServer(this.port, {required this.store, required this.identity, this.discoveryPort});

  Iterable<Conn> get authed => conns.where((c) => c.user != null && !c.closed && c.auxKind == null);
  bool isOnline(int uid) => authed.any((c) => c.user!.id == uid);

  Future<void> start() async {
    _socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _socket!.listen(_onSocket);
    _sweeper = Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
    for (final b in store.bans.values) {
      if (b.ip.isNotEmpty) bannedIps.add(b.ip);
    }
    _hub = MediaHub(
      onOut: (id, frame) {
        final c = _connById(id);
        if (c != null && !c.closed) {
          c.write(frame);
          if (c.queued > mediaBacklog) _hub!.setSlow(c.id, true);
        }
      },
      onBad: (id) {
        final c = _connById(id);
        if (c != null) _close(c);
      },
      onSkipped: (id, streamer) {
        // a slow viewer missed frames: it resumes at the next keyframe, ask for one
        final c = _connById(id);
        if (c != null) _requestKeyframe(streamer);
      },
    );
    await _hub!.start();
    _expireFiles();
    logLine('Pulse 服务器已启动，监听 TCP $boundPort');
    if (discoveryPort != null) await _startDiscovery(discoveryPort!);
  }

  int? get discoveryBoundPort => _udp?.port;
  int get boundPort => _socket?.port ?? port;

  Future<void> _startDiscovery(int udpPort) async {
    try {
      final u = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udp = u;
      final hello = utf8.encode(kDiscoveryHello);
      u.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = u.receive()) != null) {
          final dg = d!;
          if (dg.data.length != hello.length || !_bytesEq(dg.data, hello)) continue;
          final reply = utf8.encode(jsonEncode({
            'name': store.name,
            'port': boundPort,
            'online': authed.map((c) => c.user!.id).toSet().length,
            'fp': identity.fingerprint,
          }));
          try {
            u.send(reply, dg.address, dg.port);
          } catch (_) {}
        }
      }, onError: (_) {});
      logLine('局域网发现已开启（UDP ${u.port}）');
    } catch (e) {
      logLine('局域网发现未开启（UDP $udpPort 无法监听：$e）');
    }
  }

  static bool _bytesEq(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> stop() async {
    _sweeper?.cancel();
    _udp?.close();
    _hub?.stop();
    for (final c in conns) {
      c.worker?.kill();
    }
    for (final c in conns.toList()) {
      c.socket.destroy();
    }
    await _socket?.close();
    await store.flush();
  }

  void _sweep() {
    final now = DateTime.now();
    _loginFails.removeWhere((_, v) => now.difference(v.$2) >= loginLockout);
    _ipRegs.removeWhere((_, v) => v.every((t) => now.difference(t) > const Duration(hours: 1)));
    if (_ipAuth.length > 5000) _ipAuth.clear();
    for (final c in conns.toList()) {
      if (now.difference(c.lastSeen) > idleTimeout) {
        logLine('#${c.id} ${c.user?.username ?? c.ip} 超时断开');
        _close(c);
      }
    }
    // custom statuses with an expiry
    final nowMs = now.millisecondsSinceEpoch;
    for (final u in store.users.values) {
      if (u.statusUntil > 0 && u.statusUntil < nowMs) {
        u.statusText = '';
        u.statusEmoji = '';
        u.statusUntil = 0;
        store.markDirty('users');
        _broadcast({'t': Msg.member, 'm': _memberJson(u)});
      }
    }
    _tickets.removeWhere((_, t) => now.isAfter(t.expires));
    // drop abandoned uploads (also frees their reserved quota)
    for (final e in _uploadActivity.entries.toList()) {
      final f = store.files[e.key];
      if (f == null || f.msg != 0) {
        _uploadActivity.remove(e.key);
      } else if (now.difference(e.value) > uploadIdle && !conns.any((c) => c.worker != null && c.auxKind == 'upload:${e.key}')) {
        _uploadActivity.remove(e.key);
        store.deleteFile(e.key);
      }
    }
    if (now.second < 5) _expireFiles(); // about once a minute
    store.retryDeletes();
    // expire old sessions
    final cutoff = now.subtract(sessionLifetime).millisecondsSinceEpoch;
    final before = store.sessions.length;
    store.sessions.removeWhere((_, s) => s.lastUsed < cutoff);
    if (store.sessions.length != before) store.markDirty('sessions');
  }

  // ---------------------------------------------------------------- sockets

  void _onSocket(Socket s) {
    final ip = s.remoteAddress.address;
    if (bannedIps.contains(ip) ||
        conns.length >= maxConnections ||
        (_connsPerIp[ip] ?? 0) >= maxConnectionsPerIp ||
        (_pendingPerIp[ip] ?? 0) >= maxPendingPerIp) {
      s.destroy();
      return;
    }
    _connsPerIp[ip] = (_connsPerIp[ip] ?? 0) + 1;
    _pendingPerIp[ip] = (_pendingPerIp[ip] ?? 0) + 1;
    final c = Conn(_nextConn++, s, ip);
    conns.add(c);
    var pending = true;
    void donePending() {
      if (!pending) return;
      pending = false;
      _dec(_pendingPerIp, ip);
    }

    try {
      s.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    s.done.catchError((_) {});
    final decoder = FrameDecoder(maxFrame: kMaxMediaFrame);
    // unauthenticated sockets must finish key exchange + login quickly
    final hsTimer = Timer(handshakeTimeout, () {
      if (c.channel == null) _close(c);
    });
    final authTimer = Timer(authTimeout, () {
      if (c.user == null) _close(c);
    });

    s.listen(
      (data) {
        if (c.closed) return;
        List<Frame> frames;
        try {
          frames = decoder.add(data);
        } catch (_) {
          return _close(c);
        }
        for (final f in frames) {
          if (c.closed) return;
          // auxiliary connections: bulk frames go to their worker / the media hub still sealed
          if (c.auxKind != null) {
            c.lastSeen = DateTime.now();
            _auxFrame(c, f);
            continue;
          }
          if (c.channel == null) {
            // 1) key exchange (the only plaintext frames)
            if (f.kind != kFrameJson || f.payload.length > 1024) return _close(c);
            try {
              final (reply, ch) = ServerHandshake(identity).respond(f.json);
              c.channel = ch;
              s.add(encodeJson(reply));
              hsTimer.cancel();
            } catch (_) {
              return _close(c);
            }
            continue;
          }
          if (f.payload.length > kMaxFrame) return _close(c); // big frames only on auxiliary connections
          // 2) everything else is authenticated + encrypted
          Uint8List plain;
          try {
            plain = c.channel!.open(f.kind, f.payload);
          } catch (_) {
            logLine('${c.ip} 发送了无法解密或被篡改的数据，已断开');
            return _close(c);
          }
          c.lastSeen = DateTime.now();
          if (f.kind == kFrameVoice) {
            if (c.user != null) _relayVoice(c, plain);
            continue;
          }
          if (f.kind != kFrameJson) continue;
          Map<String, dynamic> m;
          try {
            m = Frame(f.kind, plain).json;
          } catch (_) {
            continue;
          }
          if (c.user == null && m['t'] == Msg.aux) {
            if (_startAux(c, m)) {
              authTimer.cancel();
              donePending();
            } else {
              return _close(c);
            }
          } else if (c.user == null) {
            _preAuth(c, m).then((ok) {
              if (ok) {
                authTimer.cancel();
                donePending();
              }
            });
          } else {
            _dispatch(c, m);
          }
        }
      },
      onDone: () => _onGone(c, hsTimer, authTimer, donePending),
      onError: (_) => _onGone(c, hsTimer, authTimer, donePending),
      cancelOnError: true,
    );
  }

  void _dec(Map<String, int> m, String k) {
    final n = (m[k] ?? 1) - 1;
    if (n <= 0) {
      m.remove(k);
    } else {
      m[k] = n;
    }
  }

  void _onGone(Conn c, Timer a, Timer b, void Function() donePending) {
    a.cancel();
    b.cancel();
    donePending();
    if (!conns.remove(c)) return;
    _dec(_connsPerIp, c.ip);
    c.closed = true;
    if (c.auxKind != null) return _auxGone(c);
    final u = c.user;
    if (u == null) return;
    if (streams[u.id] != null && voice[u.id]?.conn == c) _stopStream(u.id);
    final v = voice[u.id];
    if (v != null && v.conn == c) _leaveVoice(u.id);
    logLine('${u.display} (${u.username}) 断开连接');
    if (!isOnline(u.id)) _broadcast({'t': Msg.presence, 'id': u.id, 'online': false, 'status': u.status});
  }

  void _close(Conn c) {
    if (c.closed) return;
    c.socket.destroy();
  }

  void _broadcast(Map<String, dynamic> m, {Conn? except}) {
    final f = encodeJson(m);
    for (final c in authed) {
      if (c != except) c.sendRaw(f);
    }
  }

  /// Sends to every connection of the given users.
  void _sendTo(Iterable<int> uids, Map<String, dynamic> m) {
    final set = uids.toSet();
    final f = encodeJson(m);
    for (final c in authed) {
      if (set.contains(c.user!.id)) c.sendRaw(f);
    }
  }

  /// Sends to everyone who can view [ch] (DMs: its two members).
  void _sendChannel(Channel ch, Map<String, dynamic> m) {
    final f = encodeJson(m);
    final ok = <int, bool>{};
    for (final c in authed) {
      final u = c.user!;
      if (ok.putIfAbsent(u.id, () => _canView(u, ch))) c.sendRaw(f);
    }
  }

  Conn? _connById(int id) {
    for (final c in conns) {
      if (c.id == id) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------- auth

  String _newToken() => List.generate(32, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  Future<bool> _preAuth(Conn c, Map<String, dynamic> m) async {
    final t = m['t'];
    if (t == Msg.ping) {
      c.send({'t': Msg.pong, 'ts': m['ts']});
      return false;
    }
    void fail(String msg, [String code = 'auth']) => c.send({'t': Msg.authErr, 'msg': msg, 'code': code});
    if (asInt(m['ver']) != kProtocolVersion) {
      fail('客户端版本与服务器不匹配，请更新 Pulse', 'version');
      return false;
    }
    final bucket = _ipAuth.putIfAbsent(c.ip, () => Bucket(maxIpAuthPerMinute / 60, maxIpAuthPerMinute.toDouble()));
    if (t != Msg.resume && !bucket.take()) {
      fail('尝试过于频繁，请稍后再试', 'rate');
      return false;
    }
    switch (t) {
      case Msg.resume:
        final token = asStr(m['token']);
        if (token.length != 64) {
          fail('登录已过期，请重新登录', 'session');
          return false;
        }
        final h = Store.tokenHash(token);
        final s = store.sessions[h];
        final u = s == null ? null : store.users[s.uid];
        if (s == null || u == null) {
          fail('登录已过期，请重新登录', 'session');
          return false;
        }
        if (store.bans.containsKey(u.id)) {
          fail('你已被此服务器封禁', 'banned');
          return false;
        }
        s.lastUsed = DateTime.now().millisecondsSinceEpoch;
        s.lastIp = c.ip;
        store.markDirty('sessions');
        _completeLogin(c, u, h, token: null);
        return true;
      case Msg.login:
        final username = asStr(m['user']).trim();
        final pass = asStr(m['pass']);
        if (!await _checkServerPass(c, m)) return false;
        final key = '${c.ip}|${username.toLowerCase()}';
        final fails = _loginFails[key];
        if (fails != null && fails.$1 >= maxLoginFailures) {
          final left = loginLockout - DateTime.now().difference(fails.$2);
          fail('密码错误次数过多，请 ${left.inMinutes + 1} 分钟后再试', 'locked');
          return false;
        }
        final u = store.userByName(username);
        // always run one Argon2id verification so timing doesn't reveal existence
        final ok = await Passwords.verify(pass, u?.passHash ?? await Passwords.dummy()) && u != null;
        if (c.closed) return false;
        if (!ok) {
          final n = (fails?.$1 ?? 0) + 1;
          _loginFails[key] = (n, DateTime.now());
          await Future<void>.delayed(Duration(milliseconds: 200 + _rng.nextInt(300)));
          fail('用户名或密码错误');
          return false;
        }
        _loginFails.remove(key);
        if (store.bans.containsKey(u.id)) {
          fail('你已被此服务器封禁', 'banned');
          return false;
        }
        if (Passwords.needsRehash(u.passHash)) {
          u.passHash = await Passwords.hash(pass);
          store.markDirty('users');
        }
        _issueSession(c, u);
        return true;
      case Msg.register:
        if (!await _checkServerPass(c, m)) return false;
        final username = asStr(m['user']).trim();
        final pass = asStr(m['pass']);
        final display = sanitizeText(asStr(m['display']).trim());
        final err = validateUsername(username) ?? validatePassword(pass) ?? validateDisplayName(display.isEmpty ? username : display);
        if (err != null) {
          fail(err, 'invalid');
          return false;
        }
        final first = store.users.isEmpty;
        Invite? invite;
        if (!first) {
          if (store.regMode == RegMode.closed) {
            fail('此服务器已关闭注册', 'closed');
            return false;
          }
          if (store.regMode == RegMode.invite) {
            invite = store.invites[asStr(m['invite']).trim()];
            if (invite == null || invite.expired) {
              fail('邀请码无效或已过期', 'invite');
              return false;
            }
          }
        }
        final regs = _ipRegs.putIfAbsent(c.ip, () => []);
        regs.removeWhere((x) => DateTime.now().difference(x) > const Duration(hours: 1));
        if (regs.length >= maxRegistrationsPerIpPerHour) {
          fail('此 IP 注册过于频繁，请稍后再试', 'rate');
          return false;
        }
        if (store.users.length >= maxUsers) {
          fail('服务器用户数已满', 'full');
          return false;
        }
        if (store.userByName(username) != null) {
          fail('用户名已被占用', 'taken');
          return false;
        }
        final h = await Passwords.hash(pass);
        if (c.closed) return false;
        if (store.userByName(username) != null) {
          fail('用户名已被占用', 'taken');
          return false;
        }
        if (invite != null) {
          if (invite.uses > 0) invite.uses--;
          store.markDirty('moderation');
        }
        regs.add(DateTime.now());
        final u = store.addUser(username, display.isEmpty ? username : display, h)..avatar = _rng.nextInt(16);
        logLine('新用户注册：${u.username}${first ? "（首个用户，已设为服主）" : ""}');
        _broadcast({'t': Msg.member, 'm': _memberJson(u)});
        _issueSession(c, u);
        return true;
    }
    fail('请先登录');
    return false;
  }

  Future<bool> _checkServerPass(Conn c, Map<String, dynamic> m) async {
    if (store.serverPassHash.isEmpty) return true;
    final ok = await Passwords.verify(asStr(m['serverPass']), store.serverPassHash);
    if (!ok) c.send({'t': Msg.authErr, 'msg': '服务器密码错误', 'code': 'serverpass'});
    return ok;
  }

  void _issueSession(Conn c, User u) {
    final token = _newToken();
    final h = Store.tokenHash(token);
    final now = DateTime.now().millisecondsSinceEpoch;
    // cap sessions per user: drop the least recently used
    final mine = store.sessions.values.where((s) => s.uid == u.id).toList()..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    while (mine.length >= maxSessionsPerUser) {
      store.sessions.remove(mine.removeAt(0).hash);
    }
    store.sessions[h] = Session(h, u.id, now, now, c.ip);
    store.markDirty('sessions');
    _completeLogin(c, u, h, token: token);
  }

  void _completeLogin(Conn c, User u, String sessionHash, {required String? token}) {
    final wasOnline = isOnline(u.id);
    c.user = u;
    c.sessionHash = sessionHash;
    logLine('${u.display} (${u.username}) 已登录 ${c.ip}');
    c.send({'t': Msg.authOk, 'token': ?token, 'me': u.id});
    c.send(_welcome(u));
    if (!wasOnline) _broadcast({'t': Msg.presence, 'id': u.id, 'online': true, 'status': u.status}, except: c);
  }

  Map<String, dynamic> _serverInfo() => {
        'name': store.name,
        'motd': store.motd,
        'regMode': store.regMode,
        'hasPass': store.serverPassHash.isNotEmpty,
        'fp': identity.fingerprint,
        'fileDays': store.fileDays,
        'fileMaxMB': store.fileMaxMB,
        'storageMB': store.storageMB,
      };

  /// Channels [u] can see, each with u's effective permissions there. DMs only
  /// show up for their members (and not while hidden).
  List<Map<String, dynamic>> _channelsJson(User u) {
    final list = store.channels.values.where((ch) => ch.isDm ? ch.members.contains(u.id) && !ch.hiddenFor.contains(u.id) : _canView(u, ch)).toList()
      ..sort((a, b) => a.kind == b.kind ? a.position.compareTo(b.position) : a.kind.compareTo(b.kind));
    return [for (final ch in list) _channelJson(u, ch)];
  }

  Map<String, dynamic> _channelJson(User u, Channel ch) => {
        ...ch.toJson()..remove('hidden'),
        'last': store.logs[ch.id]?.messages.lastOrNull?.id ?? 0,
        'perms': _chPerms(u, ch),
      };

  /// Sends every member its own channel list (permissions differ per member).
  void _pushChannels() {
    for (final c in authed) {
      c.send({'t': Msg.channels, 'channels': _channelsJson(c.user!), 'base': _basePerms(c.user!)});
    }
  }

  void _pushRoles() => _broadcast({'t': Msg.roles, 'roles': [for (final r in store.roles.values) r.toJson()]});

  Map<String, dynamic> _memberJson(User u) {
    final online = isOnline(u.id);
    return {
      'id': u.id,
      'user': u.username,
      'display': u.display,
      'role': u.isOwner ? Role.owner : ((_basePerms(u) & Perm.administrator) != 0 ? Role.admin : Role.member),
      'roles': u.roles.toList(),
      'color': u.color,
      'avatar': u.avatar,
      'avh': u.avatarHash,
      'bio': u.bio,
      if (u.statusText.isNotEmpty || u.statusEmoji.isNotEmpty) 'stxt': u.statusText,
      if (u.statusEmoji.isNotEmpty) 'semo': u.statusEmoji,
      // invisible users appear offline to everyone else
      'online': online && u.status != 'invisible',
      'status': u.status == 'invisible' ? 'offline' : u.status,
    };
  }

  Map<String, dynamic> _voiceJson(int uid, VoiceState v) =>
      {'id': uid, 'ch': v.channel, 'mute': v.mute, 'deaf': v.deaf, 'smute': serverMuted.contains(uid)};

  Map<String, dynamic> _welcome(User me) => {
        't': Msg.welcome,
        'me': me.id,
        'myStatus': me.status,
        'server': _serverInfo(),
        'channels': _channelsJson(me),
        'base': _basePerms(me),
        'roles': [for (final r in store.roles.values) r.toJson()],
        'members': [for (final u in store.users.values) if (!store.bans.containsKey(u.id)) _memberJson(u)],
        'voice': [for (final e in voice.entries) _voiceJson(e.key, e.value)],
        'streams': [for (final st in streams.values) st.toJson()],
      };

  // ---------------------------------------------------------------- permissions

  int _basePerms(User u) => Perms.base(store.roles, u.roles, owner: u.isOwner);

  /// Effective permissions of [u] in [ch]. DMs: members may chat / attach / react, nothing else.
  int _chPerms(User u, Channel ch) {
    if (ch.isDm) {
      return ch.members.contains(u.id) ? Perm.viewChannel | Perm.sendMessages | Perm.attachFiles | Perm.addReactions : 0;
    }
    return Perms.channel(store.roles, u.roles, ch.overwrites, owner: u.isOwner);
  }

  bool _canView(User u, Channel ch) => (_chPerms(u, ch) & Perm.viewChannel) != 0;
  bool _has(User u, int perm, [Channel? ch]) => ((ch == null ? _basePerms(u) : _chPerms(u, ch)) & perm) == perm;
  int _top(User u) => Perms.top(store.roles, u.roles, owner: u.isOwner);

  // ---------------------------------------------------------------- dispatch

  /// Can [actor] act on [target] with [perm]? Needs the permission and a higher top role
  /// (the owner can act on everyone, nobody can act on the owner).
  bool _canModerate(User actor, User target, int perm, [Channel? ch]) =>
      actor.id != target.id && !target.isOwner && _has(actor, perm, ch) && _top(actor) > _top(target);

  void _err(Conn c, String msg) => c.send({'t': Msg.error, 'msg': msg});

  void _dispatch(Conn c, Map<String, dynamic> m) {
    final t = m['t'];
    final u = c.user!;
    if (t != Msg.ping && !c.msgs.take()) return; // flood: silently drop
    try {
      switch (t) {
        case Msg.ping:
          c.send({'t': Msg.pong, 'ts': m['ts']});
        case Msg.logout:
          final h = c.sessionHash;
          if (h != null && store.sessions.remove(h) != null) store.markDirty('sessions');
          _close(c);
        case Msg.sendMsg:
          _onSend(c, u, m);
        case Msg.editMsg:
          final (log, msg) = _findMsg(u, m);
          if (msg == null) return;
          if (msg.uid != u.id) return _err(c, '只能编辑自己的消息');
          final text = _cleanText(asStr(m['text']));
          if (text == null) return _err(c, '消息不能为空或超过 $kMaxMessageLength 字');
          log!.edit(msg, text);
          _sendChannel(store.channels[msg.ch]!, {'t': Msg.messageEdited, 'ch': msg.ch, 'id': msg.id, 'text': text, 'edited': msg.edited});
        case Msg.deleteMsg:
          final (log, msg) = _findMsg(u, m);
          if (msg == null) return;
          final ch = store.channels[msg.ch]!;
          final author = store.users[msg.uid];
          final mod = !ch.isDm && _has(u, Perm.manageMessages, ch) && (author == null || author.id == u.id || _top(u) >= _top(author));
          if (msg.uid != u.id && !mod) return _err(c, '没有权限删除这条消息');
          log!.delete(msg);
          for (final a in msg.attachments) {
            store.deleteFile(asStr(a['id']));
          }
          _sendChannel(ch, {'t': Msg.messageDeleted, 'ch': msg.ch, 'id': msg.id});
        case Msg.history:
          final (ch, log) = _readable(u, asInt(m['ch']));
          if (log == null) return;
          final (page, more) = log.page(asInt(m['before']), kHistoryPage);
          c.send({'t': Msg.historyData, 'ch': ch!.id, 'msgs': [for (final x in page) _msgJson(x)], 'more': more, 'before': asInt(m['before'])});
        case Msg.typing:
          final (ch, log) = _readable(u, asInt(m['ch']));
          if (log == null || !_has(u, Perm.sendMessages, ch) || !c.typing.take()) return;
          final f = encodeJson({'t': Msg.typingNotice, 'ch': ch!.id, 'uid': u.id});
          for (final o in authed) {
            if (o != c && _canView(o.user!, ch)) o.sendRaw(f);
          }
        case Msg.react:
          final (log, msg) = _findMsg(u, m);
          final e = asStr(m['e']);
          if (msg == null || e.isEmpty || e.length > 16 || hasIllegalChars(e)) return;
          final ch = store.channels[msg.ch]!;
          // removing my own reaction is always allowed
          if (!(msg.reactions[e]?.contains(u.id) ?? false) && !_has(u, Perm.addReactions, ch)) return _err(c, '你没有添加表情回应的权限');
          final set = msg.reactions[e];
          if (set == null && msg.reactions.length >= 20) return;
          final s = msg.reactions.putIfAbsent(e, () => <int>{});
          if (!s.remove(u.id)) s.add(u.id);
          if (s.isEmpty) msg.reactions.remove(e);
          log!.setReaction(msg, e);
          _sendChannel(ch, {'t': Msg.reaction, 'ch': msg.ch, 'id': msg.id, 'e': e, 'uids': (msg.reactions[e] ?? const <int>{}).toList()});
        case Msg.voiceJoin:
          final ch = store.channels[asInt(m['ch'])];
          if (ch == null || ch.kind != ChannelKind.voice || !_canView(u, ch)) return;
          if (!_has(u, Perm.connect, ch)) return _err(c, '你没有加入这个语音频道的权限');
          _joinVoice(c, u, ch.id);
        case Msg.voiceLeave:
          final v = voice[u.id];
          if (v != null && v.conn == c) _leaveVoice(u.id);
        case Msg.dmOpen:
          _onDmOpen(c, u, asInt(m['uid']));
        case Msg.dmClose:
          final ch = store.channels[asInt(m['id'])];
          if (ch == null || !ch.isDm || !ch.members.contains(u.id)) return;
          ch.hiddenFor.add(u.id);
          store.markDirty('channels');
          _sendTo([u.id], {'t': Msg.channels, 'channels': _channelsJson(u), 'base': _basePerms(u)});
        case Msg.uploadRequest:
          _onUploadRequest(c, u, m);
        case Msg.uploadCancel:
          final f = store.files[asStr(m['id'])];
          if (f != null && f.uid == u.id && f.msg == 0) store.deleteFile(f.id);
        case Msg.fileRequest:
          _onFileRequest(c, u, asStr(m['id']));
        case Msg.getThumb:
          final f = store.files[asStr(m['id'])];
          if (f == null || !f.complete || !f.hasThumb || !c.thumbs.take()) return;
          final ch = store.channels[f.ch];
          if (ch == null || !_canView(u, ch)) return;
          try {
            c.send({'t': Msg.thumbData, 'id': f.id, 'data': base64.encode(store.fileThumb(f.id).readAsBytesSync())});
          } catch (_) {}
        case Msg.mediaRequest:
          if (!c.uploads.take()) return _err(c, '请求太频繁');
          final tk = _newToken();
          _tickets[tk] = Ticket(u.id, 'media', '');
          c.send({'t': Msg.mediaTicket, 'ticket': tk});
        case Msg.streamStart:
          _onStreamStart(c, u, m);
        case Msg.streamStop:
          if (streams.containsKey(u.id)) _stopStream(u.id);
        case Msg.watch:
          _onWatch(c, u, asInt(m['uid']), asBool(m['on'], true));
        case Msg.keyframe:
          final st = streams[asInt(m['uid'])];
          if (st != null && st.viewers.contains(u.id)) _requestKeyframe(st.uid);
        case Msg.voiceState:
          final v = voice[u.id];
          if (v == null || v.conn != c) return;
          v.mute = asBool(m['mute']);
          v.deaf = asBool(m['deaf']);
          _broadcast({'t': Msg.voiceUser, ..._voiceJson(u.id, v)});
        case Msg.setProfile:
          _onProfile(c, u, m);
        case Msg.changePassword:
          _onChangePassword(c, u, m);
        case Msg.setAvatar:
          _onSetAvatar(c, u, m);
        case Msg.getAvatar:
          final h = asStr(m['h']);
          final b = store.avatar(h);
          if (b != null && c.avatars.take()) c.send({'t': Msg.avatarData, 'id': asInt(m['id']), 'h': h, 'data': base64.encode(b)});
        case Msg.search:
          _onSearch(c, u, m);
        case Msg.pin:
          final (log, msg) = _findMsg(u, m);
          if (msg == null) return;
          final ch = store.channels[msg.ch]!;
          if (!ch.isDm && !_has(u, Perm.manageMessages, ch) && msg.uid != u.id) return _err(c, '只有有“管理消息”权限的成员或作者可以置顶消息');
          final on = asBool(m['on'], true);
          if (on && log!.pinnedMessages.length >= 50) return _err(c, '每个频道最多置顶 50 条消息');
          log!.setPinned(msg, on);
          _sendChannel(ch, {'t': Msg.pinned, 'ch': msg.ch, 'id': msg.id, 'on': on, 'by': u.id});
        case Msg.pins:
          final (ch, log) = _readable(u, asInt(m['ch']));
          if (log == null) return;
          c.send({'t': Msg.pinsData, 'ch': ch!.id, 'msgs': [for (final x in log.pinnedMessages.reversed) _msgJson(x)]});
        case Msg.around:
          final (ch, log) = _readable(u, asInt(m['ch']));
          if (log == null) return;
          final (page, more) = log.around(asInt(m['id']), kHistoryPage * 2);
          c.send({'t': Msg.historyData, 'ch': ch!.id, 'msgs': [for (final x in page) _msgJson(x)], 'more': more, 'around': asInt(m['id'])});
        case Msg.setStatusText:
          final text = sanitizeText(asStr(m['text'])).replaceAll('\n', ' ').trim();
          final emoji = asStr(m['emoji']).trim();
          if (textWidth(text) > 128 || emoji.length > 16 || hasIllegalChars(emoji)) return _err(c, '状态文字过长');
          u.statusText = text;
          u.statusEmoji = emoji;
          u.statusUntil = text.isEmpty && emoji.isEmpty ? 0 : asInt(m['until']);
          store.markDirty('users');
          _broadcast({'t': Msg.member, 'm': _memberJson(u)});
        default:
          _adminDispatch(c, u, t, m);
      }
    } catch (e, st) {
      logLine('处理 ${u.username} 的 $t 出错：$e\n$st');
      _err(c, '请求处理失败');
    }
  }

  String? _cleanText(String raw) {
    final text = sanitizeText(raw).trim();
    if (text.isEmpty || text.length > kMaxMessageLength) return null;
    return text;
  }

  /// The channel + log if [u] may read it.
  (Channel?, ChannelLog?) _readable(User u, int chId) {
    final ch = store.channels[chId];
    if (ch == null || !_canView(u, ch)) return (null, null);
    return (ch, store.logs[chId]);
  }

  (ChannelLog?, ChatMessage?) _findMsg(User u, Map<String, dynamic> m) {
    final (_, log) = _readable(u, asInt(m['ch']));
    return (log, log?.byId(asInt(m['id'])));
  }

  /// Message JSON for clients: attachments that expired / were evicted are marked gone.
  Map<String, dynamic> _msgJson(ChatMessage x) {
    final j = x.toJson();
    if (x.attachments.isNotEmpty) {
      j['att'] = [
        for (final a in x.attachments)
          {...a, 'exp': asInt(a['at']) + store.fileDays * 86400000, if (!store.files.containsKey(asStr(a['id']))) 'gone': true},
      ];
    }
    return j;
  }

  void _onSend(Conn c, User u, Map<String, dynamic> m) {
    final chId = asInt(m['ch']);
    final (ch, log) = _readable(u, chId);
    if (ch == null || log == null) return _err(c, '频道不存在');
    if (!_has(u, Perm.sendMessages, ch)) return _err(c, '你没有在此频道发言的权限');
    if (ch.isDm) {
      final other = ch.members.firstWhere((x) => x != u.id, orElse: () => 0);
      if (store.bans.containsKey(other) || !store.users.containsKey(other)) return _err(c, '对方已不在此服务器');
    }
    final ids = {for (final a in (m['att'] as List? ?? const [])) asStr(a)}.toList();
    if (ids.length > kMaxAttachments) return _err(c, '每条消息最多 $kMaxAttachments 个附件');
    final files = <FileRec>[];
    for (final id in ids) {
      final f = store.files[id];
      if (f == null || f.uid != u.id || f.ch != chId || !f.complete || f.msg != 0) return _err(c, '附件无效或已过期，请重新上传');
      files.add(f);
    }
    final raw = sanitizeText(asStr(m['text'])).trim();
    final text = files.isNotEmpty && raw.isEmpty ? '' : _cleanText(raw);
    if (text == null || raw.length > kMaxMessageLength) return _err(c, '消息不能为空或超过 $kMaxMessageLength 字');
    if (!c.chat.take()) return _err(c, '发送太快了，请稍等');
    final now = DateTime.now().millisecondsSinceEpoch;
    if (ch.slowmode > 0 && !_has(u, Perm.manageMessages, ch) && !_has(u, Perm.manageChannels, ch)) {
      final last = _lastChat[u.id] ?? 0;
      final wait = ch.slowmode * 1000 - (now - last);
      if (wait > 0) return _err(c, '慢速模式：请 ${(wait / 1000).ceil()} 秒后再发');
    }
    _lastChat[u.id] = now;
    var reply = asInt(m['reply']);
    if (reply > 0 && log.byId(reply) == null) reply = 0;
    final msg = ChatMessage(store.newMessageId(), chId, u.id, text, now, reply)
      ..everyone = !ch.isDm && _has(u, Perm.mentionEveryone, ch)
      ..attachments = [for (final f in files) f.attachment()];
    for (final f in files) {
      f.msg = msg.id;
      _uploadActivity.remove(f.id);
    }
    if (files.isNotEmpty) store.markDirty('files');
    log.add(msg);
    if (ch.isDm) {
      // a closed DM pops up again for the recipient
      if (ch.hiddenFor.isNotEmpty) {
        final shown = ch.hiddenFor.toList();
        ch.hiddenFor.clear();
        store.markDirty('channels');
        for (final id in shown) {
          final o = store.users[id];
          if (o != null) _sendTo([id], {'t': Msg.dm, 'c': _channelJson(o, ch)});
        }
      }
    }
    _sendChannel(ch, {'t': Msg.message, 'ch': chId, 'm': _msgJson(msg), 'nonce': asStr(m['nonce'])});
  }

  // ---------------------------------------------------------------- direct messages

  void _onDmOpen(Conn c, User u, int other) {
    final o = store.users[other];
    if (o == null || o.id == u.id || store.bans.containsKey(o.id)) return _err(c, '无法给该用户发私信');
    var ch = store.dmBetween(u.id, o.id);
    if (ch == null) {
      if (store.channels.values.where((x) => x.isDm && x.members.contains(u.id)).length >= 500) return _err(c, '私信会话过多');
      ch = store.addChannel('', ChannelKind.dm, members: [u.id, o.id]);
      ch.hiddenFor.add(o.id); // the other side sees it with the first message
    }
    if (ch.hiddenFor.remove(u.id)) store.markDirty('channels');
    _sendTo([u.id], {'t': Msg.dm, 'c': _channelJson(u, ch), 'open': true});
  }

  // ---------------------------------------------------------------- files

  /// Deletes files older than the retention time (also called once a minute).
  void _expireFiles() {
    final cutoff = DateTime.now().millisecondsSinceEpoch - store.fileDays * 86400000;
    final gone = [for (final f in store.files.values) if (f.complete && f.created < cutoff) f.id];
    _dropFiles(gone, '过期');
  }

  /// Makes room for [need] more bytes by deleting the oldest finished files.
  bool _makeRoom(int need) {
    if (need > store.storageMax) return false;
    var used = store.storageUsed;
    if (used + need <= store.storageMax) return true;
    final old = store.files.values.where((f) => f.complete).toList()..sort((a, b) => a.created.compareTo(b.created));
    final gone = <String>[];
    for (final f in old) {
      if (used + need <= store.storageMax) break;
      used -= f.size;
      gone.add(f.id);
    }
    _dropFiles(gone, '超出存储上限');
    return used + need <= store.storageMax;
  }

  void _dropFiles(List<String> ids, String why) {
    if (ids.isEmpty) return;
    final byCh = <int, List<String>>{};
    for (final id in ids) {
      final f = store.files[id];
      if (f == null) continue;
      byCh.putIfAbsent(f.ch, () => []).add(id);
      store.deleteFile(id);
    }
    logLine('删除 ${ids.length} 个附件（$why）');
    for (final e in byCh.entries) {
      final ch = store.channels[e.key];
      if (ch != null) _sendChannel(ch, {'t': Msg.filesGone, 'ch': e.key, 'ids': e.value});
    }
  }

  void _onUploadRequest(Conn c, User u, Map<String, dynamic> m) {
    final nonce = asStr(m['nonce']);
    void fail(String msg) => c.send({'t': Msg.error, 'msg': msg, 'upload': nonce});
    if (!c.uploads.take()) return fail('上传请求太频繁');
    final (ch, log) = _readable(u, asInt(m['ch']));
    if (ch == null || log == null) return fail('频道不存在');
    if (!_has(u, Perm.attachFiles | Perm.sendMessages, ch)) return fail('你没有在此频道上传文件的权限');
    final resume = store.files[asStr(m['resume'])];
    if (resume != null && resume.uid == u.id && !resume.complete && resume.ch == ch.id) {
      _uploadActivity[resume.id] = DateTime.now();
      final tk = _newToken();
      _tickets[tk] = Ticket(u.id, 'upload', resume.id);
      return c.send({'t': Msg.uploadTicket, 'id': resume.id, 'ticket': tk, 'nonce': nonce, 'offset': resume.received});
    }
    final size = asInt(m['size'], -1);
    if (size < 0) return fail('文件大小无效');
    if (size > store.fileMax) return fail('文件过大：此服务器单个文件最大 ${formatBytes(store.fileMax)}');
    final pending = store.files.values.where((f) => f.uid == u.id && f.msg == 0).length;
    if (pending >= maxPendingUploadsPerUser) return fail('未发送的上传过多，请先发送或取消');
    if (!_makeRoom(size)) return fail('服务器存储空间不足（上限 ${formatBytes(store.storageMax)}）');
    final name = sanitizeFileName(asStr(m['name']));
    final id = List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final f = FileRec(id, name, size, u.id, ch.id, DateTime.now().millisecondsSinceEpoch);
    // optional thumbnail (images) generated by the uploader: must be a small, valid image
    final thumb = asStr(m['thumb']);
    if (thumb.isNotEmpty) {
      try {
        final b = base64.decode(thumb);
        final sz = imageSize(b);
        if (b.length <= kMaxThumbBytes && sz != null && sz.$1 <= 512 && sz.$2 <= 512) {
          store.fileDir.createSync(recursive: true);
          store.fileThumb(id).writeAsBytesSync(b, flush: true);
          f.hasThumb = true;
          f.w = asInt(m['w']).clamp(0, 65535);
          f.h = asInt(m['h']).clamp(0, 65535);
        }
      } catch (_) {}
    }
    store.files[id] = f;
    _uploadActivity[id] = DateTime.now();
    final tk = _newToken();
    _tickets[tk] = Ticket(u.id, 'upload', id);
    if (size == 0) {
      f.complete = true;
      store.markDirty('files');
    }
    c.send({'t': Msg.uploadTicket, 'id': id, 'ticket': tk, 'nonce': nonce, 'offset': 0});
  }

  void _onFileRequest(Conn c, User u, String id) {
    if (!c.uploads.take()) return _err(c, '请求太频繁');
    final f = store.files[id];
    final ch = f == null ? null : store.channels[f.ch];
    if (f == null || !f.complete) return c.send({'t': Msg.error, 'msg': '文件已过期或已被删除', 'file': id});
    if (ch == null || !_canView(u, ch)) return _err(c, '没有权限下载此文件');
    final tk = _newToken();
    _tickets[tk] = Ticket(u.id, 'download', id);
    c.send({'t': Msg.fileTicket, 'id': id, 'ticket': tk, 'size': f.size, 'name': f.name});
  }

  // ---------------------------------------------------------------- auxiliary connections

  /// First message on a fresh connection carrying a ticket instead of a login.
  bool _startAux(Conn c, Map<String, dynamic> m) {
    final t = _tickets.remove(asStr(m['ticket']));
    final kind = asStr(m['kind']);
    if (t == null || DateTime.now().isAfter(t.expires) || t.kind != kind) {
      c.send({'t': Msg.auxError, 'msg': '传输凭证无效或已过期'});
      return false;
    }
    final u = store.users[t.uid];
    if (u == null || store.bans.containsKey(u.id)) return false;
    if (conns.where((x) => x.auxUser?.id == u.id).length >= maxAuxPerUser) {
      c.send({'t': Msg.auxError, 'msg': '同时进行的传输过多'});
      return false;
    }
    c.auxUser = u;
    switch (kind) {
      case 'upload':
        final f = store.files[t.file];
        if (f == null || f.complete) {
          c.send({'t': Msg.auxError, 'msg': '上传已失效'});
          return false;
        }
        c.auxKind = 'upload:${f.id}';
        // resume: continue after what is already on disk
        final have = store.fileData(f.id).existsSync() ? store.fileData(f.id).lengthSync() : 0;
        final offset = have.clamp(0, f.size);
        f.received = offset;
        c.send({'t': Msg.auxReady, 'offset': offset, 'size': f.size});
        _startWorker(c, true, f, offset);
      case 'download':
        final f = store.files[t.file];
        if (f == null || !f.complete) {
          c.send({'t': Msg.auxError, 'msg': '文件已过期或已被删除'});
          return false;
        }
        final offset = asInt(m['offset']).clamp(0, f.size);
        c.auxKind = 'download:${f.id}';
        c.send({'t': Msg.auxReady, 'offset': offset, 'size': f.size});
        _startWorker(c, false, f, offset);
      case 'media':
        c.auxKind = 'media';
        c.onWritten = (_) {
          if (c.queued <= mediaBacklog ~/ 2) _hub!.setSlow(c.id, false);
        };
        _media[u.id]?.socket.destroy(); // one media connection per user
        _media[u.id] = c;
        c.send({'t': Msg.auxReady, 'offset': 0, 'size': 0});
        _hub!.add(c.id, u.id, c.channel!.exportState());
        c.channel = null; // the hub owns the crypto state now
        _routeAll();
      default:
        return false;
    }
    return true;
  }

  void _startWorker(Conn c, bool upload, FileRec f, int offset) {
    final state = c.channel!.exportState();
    c.channel = null; // the worker owns the crypto state now
    if (upload) store.fileDir.createSync(recursive: true);
    final pendingIn = <Uint8List>[];
    if (!upload) {
      // flow control: one credit back to the worker per frame that reached the socket
      c.onWritten = (n) {
        for (var i = 0; i < n; i++) {
          c.worker?.send('more');
        }
      };
    }
    TransferWorker.start(
      upload: upload,
      channelState: state,
      path: store.fileData(f.id).path,
      offset: offset,
      size: f.size,
      id: f.id,
      onMessage: (msg) {
        if (msg == null) {
          // worker exited
          if (!c.closed) _close(c);
          return;
        }
        final l = msg as List;
        switch (l[0]) {
          case 'ack':
            f.received = l[1] as int;
            _uploadActivity[f.id] = DateTime.now();
          case 'frame':
            c.write(l[1] as Uint8List);
            c.lastSeen = DateTime.now(); // downloads only receive
          case 'done':
            if (upload) {
              f.complete = true;
              _uploadActivity[f.id] = DateTime.now();
              store.markDirty('files');
              logLine('${c.auxUser!.username} 上传了 ${f.name}（${formatBytes(f.size)}）');
              Timer(const Duration(seconds: 2), () => _close(c));
            } else {
              // the client closes once it has everything; this is only a fallback
              Timer(const Duration(seconds: 60), () => _close(c));
            }
          case 'err':
            logLine('${c.auxUser!.username} 传输 ${f.name} 失败：${l[1]}');
            Timer(const Duration(milliseconds: 300), () => _close(c));
        }
      },
    ).then((w) {
      if (c.closed) return w.kill();
      c.worker = w;
      for (final p in pendingIn) {
        w.send(p);
      }
      pendingIn.clear();
    });
    c.pendingWorkerInput = pendingIn;
  }

  /// A frame on an auxiliary connection (still sealed).
  void _auxFrame(Conn c, Frame f) {
    if (c.auxKind == 'media') {
      if (f.kind == kFrameVideo && !c.video.take(f.payload.length.toDouble())) return; // over the bitrate cap: drop
      _hub!.input(c.id, f.kind, f.payload);
      return;
    }
    if (c.auxKind!.startsWith('upload:') && f.kind == kFrameData) {
      final w = c.worker;
      if (w != null) {
        w.send(f.payload);
      } else {
        c.pendingWorkerInput?.add(f.payload);
      }
      return;
    }
    // downloads only send; anything else is a protocol violation
    if (f.kind != kFrameJson) _close(c);
  }

  void _auxGone(Conn c) {
    c.worker?.send('stop');
    final w = c.worker;
    if (w != null) Timer(const Duration(seconds: 5), w.kill);
    if (c.auxKind == 'media') {
      _hub?.remove(c.id);
      final u = c.auxUser!;
      if (_media[u.id] == c) _media.remove(u.id);
    }
  }

  // ---------------------------------------------------------------- screen share

  void _onStreamStart(Conn c, User u, Map<String, dynamic> m) {
    final v = voice[u.id];
    if (v == null || v.conn != c) return _err(c, '请先加入语音频道再共享屏幕');
    final ch = store.channels[v.channel]!;
    if (!_has(u, Perm.stream, ch)) return _err(c, '你没有在此频道共享屏幕的权限');
    final title = sanitizeText(asStr(m['title'])).replaceAll('\n', ' ').trim();
    final st = streams[u.id] ??= StreamInfo(u.id, ch.id, 0, 0, 0, '');
    st
      ..channel = ch.id
      ..w = asInt(m['w']).clamp(0, 8192)
      ..h = asInt(m['h']).clamp(0, 8192)
      ..fps = asInt(m['fps']).clamp(0, 120)
      ..title = title.length > 100 ? title.substring(0, 100) : title;
    _pushStreams();
  }

  void _stopStream(int uid) {
    final st = streams.remove(uid);
    if (st == null) return;
    _hub?.route(uid, const []);
    _pushStreams();
  }

  void _onWatch(Conn c, User u, int uid, bool on) {
    final st = streams[uid];
    if (st == null) return;
    if (on) {
      final ch = store.channels[st.channel];
      if (ch == null || !_has(u, Perm.viewChannel | Perm.connect, ch)) return _err(c, '你没有观看此直播的权限');
      if (uid == u.id) return;
      st.viewers.add(u.id);
      _requestKeyframe(uid);
    } else {
      st.viewers.remove(u.id);
    }
    _routeAll();
    _pushStreams();
  }

  void _requestKeyframe(int streamer) {
    final v = voice[streamer];
    v?.conn.send({'t': Msg.keyframeRequest});
  }

  void _routeAll() {
    for (final st in streams.values) {
      _hub?.route(st.uid, [for (final v in st.viewers) ?_media[v]?.id]);
    }
  }

  void _pushStreams() {
    _routeAll();
    _broadcast({'t': Msg.streams, 'streams': [for (final st in streams.values) st.toJson()]});
  }

  void _onProfile(Conn c, User u, Map<String, dynamic> m) {
    if (m.containsKey('display')) {
      final d = sanitizeText(asStr(m['display'])).trim();
      final err = validateDisplayName(d);
      if (err != null) return _err(c, err);
      u.display = d;
    }
    if (m.containsKey('bio')) {
      final b = sanitizeText(asStr(m['bio'])).trim();
      u.bio = b.length > 190 ? b.substring(0, 190) : b;
    }
    if (m.containsKey('color')) u.color = asInt(m['color']) & 0xFFFFFFFF;
    if (m.containsKey('avatar')) u.avatar = asInt(m['avatar']).clamp(0, 63);
    final wasVisible = u.status != 'invisible';
    if (m.containsKey('status') && kStatuses.contains(m['status'])) u.status = asStr(m['status']);
    store.markDirty('users');
    _broadcast({'t': Msg.member, 'm': _memberJson(u)});
    if (wasVisible != (u.status != 'invisible')) {
      _broadcast({'t': Msg.presence, 'id': u.id, 'online': u.status != 'invisible', 'status': u.status == 'invisible' ? 'offline' : u.status});
    }
  }

  void _onSearch(Conn c, User u, Map<String, dynamic> m) {
    if (!c.searches.take()) return _err(c, '搜索太频繁，请稍候');
    final q = sanitizeText(asStr(m['q'])).trim().toLowerCase();
    final from = asInt(m['from']);
    final chId = asInt(m['ch']);
    if (q.isEmpty && from == 0) return c.send({'t': Msg.searchResult, 'q': q, 'msgs': [], 'more': false});
    final hits = <ChatMessage>[];
    var more = false;
    final logs = [
      for (final e in store.logs.entries)
        if ((chId == 0 || e.key == chId) && store.channels[e.key] != null && _canView(u, store.channels[e.key]!)) e.value,
    ];
    outer:
    for (final log in logs) {
      for (var i = log.messages.length - 1; i >= 0; i--) {
        final x = log.messages[i];
        if (from != 0 && x.uid != from) continue;
        if (q.isNotEmpty && !x.text.toLowerCase().contains(q)) continue;
        if (hits.length >= 50) {
          more = true;
          break outer;
        }
        hits.add(x);
      }
    }
    hits.sort((a, b) => b.id.compareTo(a.id));
    c.send({'t': Msg.searchResult, 'q': q, 'msgs': [for (final x in hits) _msgJson(x)], 'more': more});
  }

  void _onSetAvatar(Conn c, User u, Map<String, dynamic> m) {
    final data = asStr(m['data']);
    // removing is always allowed; uploads are rate limited (they are stored and broadcast)
    if (data.isNotEmpty && !c.avatarUploads.take()) return _err(c, '修改头像太频繁，请稍后再试');
    if (data.isEmpty) {
      u.avatarHash = '';
    } else {
      List<int> bytes;
      try {
        bytes = base64.decode(data);
      } catch (_) {
        return _err(c, '头像数据无效');
      }
      final err = validateAvatar(bytes);
      if (err != null) return _err(c, err);
      u.avatarHash = store.putAvatar(bytes);
    }
    store.markDirty('users');
    store.pruneAvatars();
    _broadcast({'t': Msg.member, 'm': _memberJson(u)});
  }

  Future<void> _onChangePassword(Conn c, User u, Map<String, dynamic> m) async {
    final err = validatePassword(asStr(m['new']));
    if (err != null) return _err(c, err);
    if (!await Passwords.verify(asStr(m['old']), u.passHash)) return _err(c, '原密码错误');
    u.passHash = await Passwords.hash(asStr(m['new']));
    store.markDirty('users');
    // revoke every other session of this user
    store.sessions.removeWhere((h, s) => s.uid == u.id && h != c.sessionHash);
    store.markDirty('sessions');
    for (final o in authed.toList()) {
      if (o.user!.id == u.id && o != c) {
        o.send({'t': Msg.error, 'msg': '密码已在其他设备修改，请重新登录', 'fatal': true});
        _close(o);
      }
    }
    c.send({'t': Msg.toast, 'msg': '密码已修改，其他设备已退出登录'});
  }

  // ---------------------------------------------------------------- voice

  void _joinVoice(Conn c, User u, int ch) {
    final old = voice[u.id];
    if (old != null) {
      if (old.channel == ch && old.conn == c) return;
      if (old.conn != c) old.conn.send({'t': Msg.toast, 'msg': '你已在另一台设备加入语音'});
      _leaveVoice(u.id);
    }
    final v = VoiceState(ch, c);
    voice[u.id] = v;
    _broadcast({'t': Msg.voiceUser, ..._voiceJson(u.id, v)});
  }

  void _leaveVoice(int uid) {
    if (voice.remove(uid) == null) return;
    _broadcast({'t': Msg.voiceUser, 'id': uid, 'ch': null});
    if (streams.containsKey(uid)) _stopStream(uid);
  }

  void _relayVoice(Conn c, Uint8List payload) {
    final u = c.user!;
    final v = voice[u.id];
    if (v == null || v.conn != c || v.mute || serverMuted.contains(u.id)) return;
    final ch = store.channels[v.channel];
    if (ch == null || !_has(u, Perm.speak, ch)) return;
    if (payload.length < 3 || payload.length > kMaxVoicePacket + 2 || !c.voice.take(payload.length.toDouble())) return;
    final out = Uint8List(4 + payload.length);
    ByteData.sublistView(out).setUint32(0, u.id);
    out.setRange(4, out.length, payload);
    final frame = encodeFrame(kFrameVoice, out);
    for (final e in voice.entries) {
      if (e.key == u.id || e.value.channel != v.channel || e.value.deaf) continue;
      e.value.conn.sendRaw(frame);
    }
  }

  // ---------------------------------------------------------------- admin

  void _adminDispatch(Conn c, User u, Object? t, Map<String, dynamic> m) {
    void need(int perm, [Channel? ch]) {
      if (!_has(u, perm, ch)) throw _Denied();
    }

    try {
      switch (t) {
        case Msg.chCreate:
          need(Perm.manageChannels);
          final name = sanitizeText(asStr(m['name'])).trim();
          final kind = m['kind'] == ChannelKind.voice ? ChannelKind.voice : ChannelKind.text;
          final err = validateChannelName(name);
          if (err != null) return _err(c, err);
          if (store.channels.values.where((x) => !x.isDm).length >= maxChannels) return _err(c, '频道数量已达上限');
          final topic = sanitizeText(asStr(m['topic'])).trim();
          store.addChannel(name, kind, topic: topic.length > kMaxTopic ? topic.substring(0, kMaxTopic) : topic);
          _audit(u, '创建频道「$name」');
          _pushChannels();
        case Msg.chUpdate:
          final ch = store.channels[asInt(m['id'])];
          if (ch == null || ch.isDm) return;
          need(Perm.manageChannels, ch);
          if (m.containsKey('name')) {
            final name = sanitizeText(asStr(m['name'])).trim();
            final err = validateChannelName(name);
            if (err != null) return _err(c, err);
            ch.name = name;
          }
          if (m.containsKey('topic')) {
            final topic = sanitizeText(asStr(m['topic'])).trim();
            ch.topic = topic.length > kMaxTopic ? topic.substring(0, kMaxTopic) : topic;
          }
          if (m.containsKey('slowmode')) ch.slowmode = asInt(m['slowmode']).clamp(0, 21600);
          if (m.containsKey('bitrate')) ch.bitrate = asInt(m['bitrate'], 64000).clamp(16000, 128000);
          store.markDirty('channels');
          _pushChannels();
        case Msg.channelPerms:
          final ch = store.channels[asInt(m['id'])];
          if (ch == null || ch.isDm) return;
          need(Perm.manageChannels | Perm.manageRoles, ch);
          final list = <Overwrite>[];
          for (final o in (m['ow'] as List? ?? const [])) {
            final ow = Overwrite.fromJson((o as Map).cast<String, dynamic>());
            final r = store.roles[ow.role];
            if (r == null || (ow.allow == 0 && ow.deny == 0)) continue;
            list.add(ow);
          }
          // can't grant (or take away) what I don't have myself
          final mine = _chPerms(u, ch);
          final old = {for (final o in ch.overwrites) o.role: o};
          for (final o in list) {
            final p = old[o.role];
            final changed = (o.allow ^ (p?.allow ?? 0)) | (o.deny ^ (p?.deny ?? 0));
            if (!u.isOwner && (changed & ~mine) != 0) return _err(c, '不能修改你自己没有的权限');
            final r = store.roles[o.role]!;
            if (!u.isOwner && r.id != RoleDef.everyone && r.position >= _top(u)) return _err(c, '不能修改不低于你最高角色的角色权限');
          }
          ch.overwrites = list;
          store.markDirty('channels');
          _audit(u, '修改了频道「${ch.name}」的权限');
          _pushChannels();
          _enforceAccess();
        case Msg.chDelete:
          final ch = store.channels[asInt(m['id'])];
          if (ch == null || ch.isDm) return;
          need(Perm.manageChannels, ch);
          if (store.channels.values.where((x) => x.kind == ChannelKind.text).length <= 1 && ch.kind == ChannelKind.text) {
            return _err(c, '至少保留一个文字频道');
          }
          for (final e in voice.entries.toList()) {
            if (e.value.channel == ch.id) _leaveVoice(e.key);
          }
          _dropFiles([for (final f in store.files.values) if (f.ch == ch.id) f.id], '频道已删除');
          store.removeChannel(ch.id);
          _audit(u, '删除频道「${ch.name}」');
          _pushChannels();
        case Msg.chMove:
          final ch = store.channels[asInt(m['id'])];
          if (ch == null || ch.isDm) return;
          need(Perm.manageChannels);
          final same = store.channels.values.where((x) => x.kind == ch.kind).toList()..sort((a, b) => a.position.compareTo(b.position));
          final i = same.indexOf(ch);
          final j = (i + asInt(m['delta'])).clamp(0, same.length - 1);
          if (i == j) return;
          same
            ..removeAt(i)
            ..insert(j, ch);
          for (var k = 0; k < same.length; k++) {
            same[k].position = k;
          }
          store.markDirty('channels');
          _pushChannels();
        case Msg.setRole:
          // ownership transfer (the old fixed admin level is replaced by roles)
          if (!u.isOwner) return _err(c, '只有服主可以转让服务器');
          final target = store.users[asInt(m['id'])];
          if (target == null || target.id == u.id || asInt(m['role']) != Role.owner) return;
          u.role = Role.member;
          target.role = Role.owner;
          store.markDirty('users');
          _audit(u, '将服主转让给 ${target.username}');
          _broadcast({'t': Msg.member, 'm': _memberJson(u)});
          _broadcast({'t': Msg.member, 'm': _memberJson(target)});
          _pushChannels();
        case Msg.roleCreate:
          need(Perm.manageRoles);
          if (store.roles.length >= maxRoles) return _err(c, '角色数量已达上限');
          final name = sanitizeText(asStr(m['name'], '新角色')).trim();
          if (name.isEmpty || textWidth(name) > 32 || hasIllegalChars(name)) return _err(c, '角色名称无效');
          final r = store.addRole(name);
          // new roles go right below my top role so I can still manage them
          if (!u.isOwner) {
            final top = _top(u);
            for (final x in store.roles.values) {
              if (x.id != r.id && x.position >= top) x.position++;
            }
            r.position = top;
            store.normalizeRoles();
          }
          _audit(u, '创建角色「$name」');
          _pushRoles();
        case Msg.roleUpdate:
          need(Perm.manageRoles);
          final r = store.roles[asInt(m['id'])];
          if (r == null) return;
          if (!u.isOwner && r.position >= _top(u)) return _err(c, '只能编辑比你最高角色低的角色');
          if (m.containsKey('name') && r.id != RoleDef.everyone) {
            final name = sanitizeText(asStr(m['name'])).trim();
            if (name.isEmpty || textWidth(name) > 32 || hasIllegalChars(name)) return _err(c, '角色名称无效');
            r.name = name;
          }
          if (m.containsKey('color')) r.color = asInt(m['color']) & 0xFFFFFFFF;
          if (m.containsKey('hoist')) r.hoist = asBool(m['hoist']);
          if (m.containsKey('ment')) r.mentionable = asBool(m['ment']);
          if (m.containsKey('perms')) {
            final p = asInt(m['perms']) & Perm.all;
            if (!u.isOwner && ((p ^ r.perms) & ~_basePerms(u)) != 0) return _err(c, '不能授予或移除你自己没有的权限');
            r.perms = p;
          }
          store.markDirty('channels');
          _audit(u, '编辑角色「${r.name}」');
          _pushRoles();
          _afterRoleChange();
        case Msg.roleDelete:
          need(Perm.manageRoles);
          final r = store.roles[asInt(m['id'])];
          if (r == null || r.id == RoleDef.everyone) return;
          if (!u.isOwner && r.position >= _top(u)) return _err(c, '只能删除比你最高角色低的角色');
          store.roles.remove(r.id);
          store.normalizeRoles();
          for (final x in store.users.values) {
            x.roles.remove(r.id);
          }
          for (final ch in store.channels.values) {
            ch.overwrites.removeWhere((o) => o.role == r.id);
          }
          store.markDirty('users');
          store.markDirty('channels');
          _audit(u, '删除角色「${r.name}」');
          _pushRoles();
          _afterRoleChange();
        case Msg.roleMove:
          need(Perm.manageRoles);
          final r = store.roles[asInt(m['id'])];
          if (r == null || r.id == RoleDef.everyone) return;
          final list = store.roles.values.where((x) => x.id != RoleDef.everyone).toList()..sort((a, b) => a.position.compareTo(b.position));
          final i = list.indexOf(r);
          final j = (i + asInt(m['delta'])).clamp(0, list.length - 1);
          if (i == j) return;
          // both the moved role and the one it swaps with must be below me
          if (!u.isOwner && (r.position >= _top(u) || list[j].position >= _top(u))) return _err(c, '只能调整比你最高角色低的角色');
          list
            ..removeAt(i)
            ..insert(j, r);
          for (var k = 0; k < list.length; k++) {
            list[k].position = k + 1;
          }
          store.markDirty('channels');
          _pushRoles();
          _afterRoleChange();
        case Msg.memberRoles:
          need(Perm.manageRoles);
          final target = store.users[asInt(m['id'])];
          if (target == null) return;
          final want = {for (final r in (m['roles'] as List? ?? const [])) asInt(r)}..removeWhere((r) => !store.roles.containsKey(r) || r == RoleDef.everyone);
          final changed = want.difference(target.roles).union(target.roles.difference(want));
          if (!u.isOwner) {
            if (target.id != u.id && _top(target) >= _top(u)) return _err(c, '不能修改角色不低于你的成员');
            if (changed.any((r) => store.roles[r]!.position >= _top(u))) return _err(c, '只能分配比你最高角色低的角色');
          }
          target.roles
            ..clear()
            ..addAll(want);
          store.markDirty('users');
          _audit(u, '修改了 ${target.username} 的角色');
          _broadcast({'t': Msg.member, 'm': _memberJson(target)});
          _afterRoleChange();
        case Msg.kick || Msg.ban:
          final target = store.users[asInt(m['id'])];
          if (target == null) return;
          if (!_canModerate(u, target, t == Msg.ban ? Perm.banMembers : Perm.kickMembers)) return _err(c, '不能对该成员执行此操作');
          if (t == Msg.ban) {
            final ip = authed.where((x) => x.user!.id == target.id).map((x) => x.ip).firstOrNull ??
                store.sessions.values.where((s) => s.uid == target.id).map((s) => s.lastIp).firstOrNull ??
                '';
            final reason = sanitizeText(asStr(m['reason'])).trim();
            store.bans[target.id] = Ban(target.id, reason.length > 200 ? reason.substring(0, 200) : reason, DateTime.now().millisecondsSinceEpoch, ip);
            if (ip.isNotEmpty && asBool(m['ip'])) bannedIps.add(ip);
            store.sessions.removeWhere((_, s) => s.uid == target.id);
            store.markDirty('sessions');
            store.markDirty('moderation');
            _broadcast({'t': Msg.memberRemoved, 'id': target.id});
          }
          _audit(u, '${t == Msg.ban ? "封禁" : "踢出"} ${target.username}');
          _disconnectUser(target.id, t == Msg.ban ? '你已被管理员封禁' : '你已被管理员移出服务器');
        case Msg.unban:
          need(Perm.banMembers);
          final b = store.bans.remove(asInt(m['id']));
          if (b == null) return;
          bannedIps.remove(b.ip);
          store.markDirty('moderation');
          final target = store.users[b.uid];
          if (target != null) _broadcast({'t': Msg.member, 'm': _memberJson(target)});
          _audit(u, '解除封禁 ${target?.username ?? b.uid}');
          _sendBans(c);
        case Msg.listBans:
          if (!_has(u, Perm.banMembers) && !_has(u, Perm.manageServer)) throw _Denied();
          _sendBans(c);
        case Msg.serverMute:
          final target = store.users[asInt(m['id'])];
          final v = target == null ? null : voice[target.id];
          final ch = v == null ? null : store.channels[v.channel];
          if (target == null || !_canModerate(u, target, Perm.muteMembers, ch)) return _err(c, '不能对该成员执行此操作');
          if (asBool(m['on'])) {
            serverMuted.add(target.id);
          } else {
            serverMuted.remove(target.id);
          }
          if (v != null) _broadcast({'t': Msg.voiceUser, ..._voiceJson(target.id, v)});
        case Msg.moveMember:
          final target = store.users[asInt(m['id'])];
          final ch = store.channels[asInt(m['ch'])];
          final v = target == null ? null : voice[target.id];
          if (v == null || ch == null || ch.kind != ChannelKind.voice) return;
          final from = store.channels[v.channel];
          if (target!.id != u.id && !_canModerate(u, target, Perm.moveMembers, from)) return _err(c, '不能对该成员执行此操作');
          if (!_has(u, Perm.moveMembers, ch) && target.id != u.id) return _err(c, '不能移动到该频道');
          if (!_has(target, Perm.connect, ch)) return _err(c, '对方没有加入该频道的权限');
          final nv = VoiceState(ch.id, v.conn)
            ..mute = v.mute
            ..deaf = v.deaf;
          voice[target.id] = nv;
          _broadcast({'t': Msg.voiceUser, ..._voiceJson(target.id, nv)});
          final st = streams[target.id];
          if (st != null) {
            st.channel = ch.id;
            _pushStreams();
          }
        case Msg.serverSettings:
          need(Perm.manageServer);
          _onSettings(c, u, m);
        case Msg.storageInfo:
          need(Perm.manageServer);
          c.send({
            't': Msg.storageData,
            'used': store.storageUsed,
            'files': store.files.values.where((f) => f.complete).length,
            'maxMB': store.storageMB,
            'fileDays': store.fileDays,
            'fileMaxMB': store.fileMaxMB,
          });
        case Msg.createInvite:
          need(Perm.createInvite);
          final code = List.generate(8, (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_rng.nextInt(32)]).join();
          final hours = asInt(m['hours'], 24).clamp(0, 24 * 30);
          final uses = asInt(m['uses'], 1).clamp(-1, 1000);
          final inv = Invite(code, u.id, uses == 0 ? -1 : uses, hours == 0 ? 0 : DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch);
          store.invites[code] = inv;
          store.markDirty('moderation');
          c.send({'t': Msg.inviteCode, 'code': code, 'uses': inv.uses, 'expires': inv.expires});
        default:
          _err(c, '未知请求');
      }
    } on _Denied {
      _err(c, '没有管理员权限');
    }
  }

  /// Roles / overwrites changed: refresh everyone's channel lists and member badges,
  /// and remove people from voice channels / streams they may no longer use.
  void _afterRoleChange() {
    for (final x in store.users.values) {
      if (!store.bans.containsKey(x.id)) _broadcast({'t': Msg.member, 'm': _memberJson(x)});
    }
    _pushChannels();
    _enforceAccess();
  }

  void _enforceAccess() {
    for (final e in voice.entries.toList()) {
      final u = store.users[e.key];
      final ch = store.channels[e.value.channel];
      if (u == null || ch == null) continue;
      if (!_has(u, Perm.connect, ch)) {
        e.value.conn.send({'t': Msg.toast, 'msg': '你已没有此语音频道的权限'});
        _leaveVoice(e.key);
      } else if (streams.containsKey(u.id) && !_has(u, Perm.stream, ch)) {
        _stopStream(u.id);
      }
    }
    for (final st in streams.values) {
      final ch = store.channels[st.channel];
      st.viewers.removeWhere((v) {
        final u = store.users[v];
        return u == null || ch == null || !_has(u, Perm.viewChannel | Perm.connect, ch);
      });
    }
    _pushStreams();
  }

  Future<void> _onSettings(Conn c, User u, Map<String, dynamic> m) async {
    if (m.containsKey('name')) {
      final n = sanitizeText(asStr(m['name'])).trim();
      if (n.isEmpty || textWidth(n) > 48) return _err(c, '服务器名称无效');
      store.name = n;
    }
    if (m.containsKey('motd')) {
      final s = sanitizeText(asStr(m['motd'])).trim();
      store.motd = s.length > 500 ? s.substring(0, 500) : s;
    }
    if (m.containsKey('regMode') && [RegMode.open, RegMode.invite, RegMode.closed].contains(m['regMode'])) {
      store.regMode = asStr(m['regMode']);
    }
    if (m.containsKey('serverPass')) {
      if (!u.isOwner) return _err(c, '只有服主可以修改服务器密码');
      final p = asStr(m['serverPass']);
      store.serverPassHash = p.isEmpty ? '' : await Passwords.hash(p);
    }
    if (m.containsKey('fileDays')) store.fileDays = asInt(m['fileDays'], store.fileDays).clamp(1, 3650);
    if (m.containsKey('fileMaxMB')) store.fileMaxMB = asInt(m['fileMaxMB'], store.fileMaxMB).clamp(1, kMaxFileBytes ~/ (1024 * 1024));
    if (m.containsKey('storageMB')) store.storageMB = asInt(m['storageMB'], store.storageMB).clamp(1, 1 << 30);
    store.markDirty('channels');
    _expireFiles();
    _makeRoom(0);
    _audit(u, '修改了服务器设置');
    _broadcast({'t': Msg.server, ..._serverInfo()});
  }

  void _sendBans(Conn c) => c.send({
        't': Msg.bans,
        'bans': [
          for (final b in store.bans.values)
            {
              'id': b.uid,
              'user': store.users[b.uid]?.username ?? '?',
              'display': store.users[b.uid]?.display ?? '?',
              'reason': b.reason,
              'at': b.at,
            }
        ],
      });

  void _audit(User u, String what) => logLine('[管理] ${u.username}：$what');

  void _disconnectUser(int uid, String reason) {
    for (final o in authed.toList()) {
      if (o.user!.id == uid) {
        o.send({'t': Msg.error, 'msg': reason, 'fatal': true});
        Timer(const Duration(milliseconds: 200), () => _close(o));
      }
    }
    for (final o in conns.toList()) {
      if (o.auxUser?.id == uid) _close(o);
    }
    if (voice.containsKey(uid)) _leaveVoice(uid);
  }

  // ---------------------------------------------------------------- console

  User? findUser(String s) {
    final id = int.tryParse(s.replaceFirst('#', ''));
    return (id != null ? store.users[id] : null) ?? store.userByName(s);
  }

  List<String> describeUsers() => [
        for (final u in store.users.values)
          '#${u.id} ${u.username}「${u.display}」${u.isOwner ? '服主' : u.roles.map((r) => store.roles[r]?.name ?? '').join('、')}'
              '${isOnline(u.id) ? " 在线" : ""}${voice.containsKey(u.id) ? " 语音:${store.channels[voice[u.id]!.channel]?.name}" : ""}'
              '${store.bans.containsKey(u.id) ? " [已封禁]" : ""}',
      ];

  void announce(String text) {
    for (final c in authed) {
      c.send({'t': Msg.toast, 'msg': '【公告】$text'});
    }
  }

  /// Console: `owner` transfers ownership; `op` / `deop` add / remove the role named 管理员
  /// (created with administrator permission if missing).
  bool consoleSetRole(String who, int role) {
    final u = findUser(who);
    if (u == null) return false;
    if (role == Role.owner) {
      for (final o in store.users.values) {
        if (o.isOwner) o.role = Role.member;
      }
      u.role = Role.owner;
    } else {
      var r = store.roles.values.where((x) => x.name == '管理员').firstOrNull;
      if (role == Role.admin) {
        r ??= store.addRole('管理员', perms: Perm.administrator, color: 0xFF5865F2, hoist: true);
        u.roles.add(r.id);
        _pushRoles();
      } else {
        u.roles.removeWhere((x) => (store.roles[x]!.perms & Perm.administrator) != 0);
      }
    }
    store.markDirty('users');
    _afterRoleChange();
    return true;
  }

  /// Console `storage`: usage summary.
  String describeStorage() =>
      '附件 ${store.files.values.where((f) => f.complete).length} 个，占用 ${formatBytes(store.storageUsed)} / ${formatBytes(store.storageMax)}；'
      '保留 ${store.fileDays} 天；单个文件上限 ${formatBytes(store.fileMax)}';

  void setStorage({int? days, int? maxMB, int? fileMaxMB}) {
    if (days != null) store.fileDays = days.clamp(1, 3650);
    if (maxMB != null) store.storageMB = maxMB.clamp(1, 1 << 30);
    if (fileMaxMB != null) store.fileMaxMB = fileMaxMB.clamp(1, kMaxFileBytes ~/ (1024 * 1024));
    store.markDirty('channels');
    _expireFiles();
    _makeRoom(0);
    _broadcast({'t': Msg.server, ..._serverInfo()});
  }

  bool consoleKick(String who, {bool ban = false}) {
    final u = findUser(who);
    if (u == null) return false;
    if (ban) {
      final ip = authed.where((x) => x.user!.id == u.id).map((x) => x.ip).firstOrNull ?? '';
      store.bans[u.id] = Ban(u.id, '控制台封禁', DateTime.now().millisecondsSinceEpoch, ip);
      if (ip.isNotEmpty) bannedIps.add(ip);
      store.sessions.removeWhere((_, s) => s.uid == u.id);
      store.markDirty('sessions');
      store.markDirty('moderation');
      _broadcast({'t': Msg.memberRemoved, 'id': u.id});
    }
    _disconnectUser(u.id, ban ? '你已被服务器封禁' : '你已被服务器管理员断开');
    return true;
  }

  bool consoleUnban(String who) {
    final u = findUser(who);
    if (u == null) return false;
    final b = store.bans.remove(u.id);
    if (b == null) return false;
    bannedIps.remove(b.ip);
    store.markDirty('moderation');
    _broadcast({'t': Msg.member, 'm': _memberJson(u)});
    return true;
  }

  Future<bool> consoleResetPassword(String who, String pass) async {
    final u = findUser(who);
    if (u == null) return false;
    u.passHash = await Passwords.hash(pass);
    store.sessions.removeWhere((_, s) => s.uid == u.id);
    store.markDirty('users');
    store.markDirty('sessions');
    _disconnectUser(u.id, '密码已被管理员重置，请重新登录');
    return true;
  }

  String createInviteConsole(int uses, int hours) {
    final code = List.generate(8, (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_rng.nextInt(32)]).join();
    store.invites[code] = Invite(code, 0, uses == 0 ? -1 : uses, hours == 0 ? 0 : DateTime.now().add(Duration(hours: hours)).millisecondsSinceEpoch);
    store.markDirty('moderation');
    return code;
  }

  void setRegMode(String mode) {
    store.regMode = mode;
    store.markDirty('channels');
    _broadcast({'t': Msg.server, ..._serverInfo()});
  }
}

class _Denied implements Exception {}
