import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:pulse_shared/pulse_shared.dart';

/// Persistent server data under `data/`:
///   users.json      accounts (Argon2id password hashes), roles, profiles
///   sessions.json   login sessions; only SHA-256 of each token is stored
///   channels.json   channels (incl. DMs), roles, server settings
///   moderation.json bans, invites
///   files.json      attachment index; contents in `files/<id>.bin` (+ `.thumb`)
///   `messages/<channel>.log`  append-only op log (create / edit / delete / react)
///
/// JSON files are written atomically (tmp + rename) and debounced.
class Store {
  final Directory dir;
  Store(this.dir);

  final Map<int, User> users = {};
  final Map<String, Session> sessions = {}; // key = sha256(token) hex
  final Map<int, Channel> channels = {};
  final Map<int, Ban> bans = {}; // by user id
  final Map<String, Invite> invites = {};
  final Map<int, ChannelLog> logs = {};
  final Map<int, RoleDef> roles = {};
  final Map<String, FileRec> files = {};
  int _nextUser = 1, _nextChannel = 1, _nextMsg = 1, _nextRole = 1;

  /// Server settings editable by admins (also stored here).
  String name = 'Pulse 服务器';
  String motd = '';
  String regMode = RegMode.open;

  /// Optional server join password (Argon2id hash, '' = none).
  String serverPassHash = '';

  /// Attachments: days until uploaded files expire, total storage quota (oldest files
  /// are deleted when exceeded) and the per-file limit (never above 2 GiB).
  int fileDays = kDefaultFileDays;
  int storageMB = kDefaultStorageMB;
  int fileMaxMB = kMaxFileBytes ~/ (1024 * 1024);

  /// How many messages per channel are kept in memory (older stay on disk).
  static const memoryMessages = 5000;

  Timer? _flush;
  final Set<String> _dirty = {};

  File _f(String n) => File('${dir.path}${Platform.pathSeparator}$n');

  Map<String, dynamic>? _read(String n) {
    final f = _f(n);
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      stderr.writeln('读取 $n 失败：$e（将备份为 $n.corrupt）');
      try {
        f.copySync('${f.path}.corrupt');
      } catch (_) {}
      return null;
    }
  }

  void load() {
    dir.createSync(recursive: true);
    Directory('${dir.path}${Platform.pathSeparator}messages').createSync(recursive: true);
    final u = _read('users.json');
    if (u != null) {
      _nextUser = asInt(u['next'], 1);
      for (final j in (u['users'] as List? ?? const [])) {
        final x = User.fromJson(j as Map<String, dynamic>);
        users[x.id] = x;
      }
    }
    final s = _read('sessions.json');
    if (s != null) {
      for (final j in (s['sessions'] as List? ?? const [])) {
        final x = Session.fromJson(j as Map<String, dynamic>);
        if (users.containsKey(x.uid)) sessions[x.hash] = x;
      }
    }
    final c = _read('channels.json');
    if (c != null) {
      _nextChannel = asInt(c['next'], 1);
      name = asStr(c['name'], name);
      motd = asStr(c['motd']);
      regMode = asStr(c['regMode'], RegMode.open);
      serverPassHash = asStr(c['serverPass']);
      fileDays = asInt(c['fileDays'], kDefaultFileDays).clamp(1, 3650);
      storageMB = asInt(c['storageMB'], kDefaultStorageMB).clamp(1, 1 << 30);
      fileMaxMB = asInt(c['fileMaxMB'], fileMaxMB).clamp(1, kMaxFileBytes ~/ (1024 * 1024));
      _nextRole = asInt(c['nextRole'], 1);
      for (final j in (c['channels'] as List? ?? const [])) {
        final x = Channel.fromJson(j as Map<String, dynamic>);
        channels[x.id] = x;
      }
      for (final j in (c['roles'] as List? ?? const [])) {
        final r = RoleDef.fromJson(j as Map<String, dynamic>);
        roles[r.id] = r;
      }
    }
    _migrateRoles();
    final m = _read('moderation.json');
    if (m != null) {
      for (final j in (m['bans'] as List? ?? const [])) {
        final b = Ban.fromJson(j as Map<String, dynamic>);
        bans[b.uid] = b;
      }
      for (final j in (m['invites'] as List? ?? const [])) {
        final i = Invite.fromJson(j as Map<String, dynamic>);
        if (!i.expired) invites[i.code] = i;
      }
    }
    final f = _read('files.json');
    if (f != null) {
      for (final j in (f['files'] as List? ?? const [])) {
        final x = FileRec.fromJson(j as Map<String, dynamic>);
        if (x.complete && x.msg != 0) files[x.id] = x; // unfinished / never sent uploads are dropped on restart
      }
    }
    _cleanFileDir();
    if (channels.values.every((c) => c.isDm)) {
      addChannel('综合', ChannelKind.text, topic: '欢迎来到 Pulse！');
      addChannel('闲聊', ChannelKind.text);
      addChannel('大厅', ChannelKind.voice);
      addChannel('开黑', ChannelKind.voice);
    }
    for (final ch in channels.values) {
      if (ch.hasLog) {
        final log = ChannelLog(_f('messages${Platform.pathSeparator}${ch.id}.log'));
        log.load();
        logs[ch.id] = log;
        if (log.maxId >= _nextMsg) _nextMsg = log.maxId + 1;
      }
    }
  }

  int newMessageId() => _nextMsg++;

  void markDirty(String what) {
    _dirty.add(what);
    _flush ??= Timer(const Duration(seconds: 2), flush);
  }

  Future<void> flush() async {
    _flush?.cancel();
    _flush = null;
    final d = _dirty.toList();
    _dirty.clear();
    for (final w in d) {
      switch (w) {
        case 'users':
          _write('users.json', {'next': _nextUser, 'users': [for (final u in users.values) u.toJson()]});
        case 'sessions':
          _write('sessions.json', {'sessions': [for (final s in sessions.values) s.toJson()]});
        case 'channels':
          _write('channels.json', {
            'next': _nextChannel,
            'name': name,
            'motd': motd,
            'regMode': regMode,
            'serverPass': serverPassHash,
            'fileDays': fileDays,
            'storageMB': storageMB,
            'fileMaxMB': fileMaxMB,
            'nextRole': _nextRole,
            'channels': [for (final c in channels.values) c.toJson()],
            'roles': [for (final r in roles.values) r.toJson()],
          });
        case 'files':
          _write('files.json', {'files': [for (final x in files.values) if (x.complete) x.toJson()]});
        case 'moderation':
          invites.removeWhere((_, i) => i.expired);
          _write('moderation.json', {
            'bans': [for (final b in bans.values) b.toJson()],
            'invites': [for (final i in invites.values) i.toJson()],
          });
      }
    }
    for (final l in logs.values) {
      await l.flush();
    }
  }

  void _write(String n, Map<String, dynamic> data) {
    final f = _f(n);
    final tmp = File('${f.path}.tmp');
    try {
      tmp.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(data), flush: true);
      tmp.renameSync(f.path);
    } catch (e) {
      stderr.writeln('保存 $n 失败：$e');
    }
  }

  /// Creates @everyone, and moves accounts of the old fixed "admin" level into an 管理员 role.
  void _migrateRoles() {
    if (!roles.containsKey(RoleDef.everyone)) {
      roles[RoleDef.everyone] = RoleDef(RoleDef.everyone, '@everyone', perms: Perm.everyoneDefault);
      markDirty('channels');
    }
    final legacy = users.values.where((u) => u.role == Role.admin).toList();
    if (legacy.isNotEmpty) {
      final r = addRole('管理员',
          perms: Perm.everyoneDefault | Perm.manageServer | Perm.manageChannels | Perm.manageMessages | Perm.mentionEveryone | Perm.createInvite |
              Perm.moderation,
          color: 0xFF5865F2,
          hoist: true);
      for (final u in legacy) {
        u.role = Role.member;
        u.roles.add(r.id);
      }
      markDirty('users');
    }
  }

  RoleDef addRole(String name, {int perms = 0, int color = 0, bool hoist = false}) {
    final pos = roles.values.fold<int>(0, (a, r) => max(a, r.position)) + 1;
    final r = RoleDef(_nextRole++, name, perms: perms, color: color, hoist: hoist, position: pos);
    roles[r.id] = r;
    markDirty('channels');
    return r;
  }

  /// Renumbers role positions 1..n (keeping order); @everyone stays 0.
  void normalizeRoles() {
    final list = roles.values.where((r) => r.id != RoleDef.everyone).toList()..sort((a, b) => a.position.compareTo(b.position));
    for (var i = 0; i < list.length; i++) {
      list[i].position = i + 1;
    }
    roles[RoleDef.everyone]?.position = 0;
  }

  User addUser(String username, String display, String passHash) {
    final u = User(_nextUser++, username, display, passHash)
      ..role = users.isEmpty ? Role.owner : Role.member // first account owns the server
      ..created = DateTime.now().millisecondsSinceEpoch;
    users[u.id] = u;
    markDirty('users');
    return u;
  }

  User? userByName(String username) {
    final l = username.toLowerCase();
    for (final u in users.values) {
      if (u.username.toLowerCase() == l) return u;
    }
    return null;
  }

  Channel addChannel(String name, String kind, {String topic = '', List<int> members = const []}) {
    final pos = channels.values.where((c) => c.kind == kind).fold<int>(-1, (a, c) => max(a, c.position)) + 1;
    final c = Channel(_nextChannel++, name, kind)
      ..topic = topic
      ..position = pos
      ..members = [...members];
    channels[c.id] = c;
    if (c.hasLog) {
      final log = ChannelLog(_f('messages${Platform.pathSeparator}${c.id}.log'));
      log.load();
      logs[c.id] = log;
    }
    markDirty('channels');
    return c;
  }

  void removeChannel(int id) {
    channels.remove(id);
    final log = logs.remove(id);
    if (log != null) {
      log.close();
      try {
        log.file.renameSync('${log.file.path}.deleted-${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
    }
    markDirty('channels');
  }

  /// The DM channel between two users (null if none yet).
  Channel? dmBetween(int a, int b) {
    for (final c in channels.values) {
      if (c.isDm && c.members.contains(a) && c.members.contains(b)) return c;
    }
    return null;
  }

  // ---- attachments: files/<id>.bin, files/<id>.thumb
  Directory get fileDir => Directory('${dir.path}${Platform.pathSeparator}files');
  File fileData(String id) => File('${fileDir.path}${Platform.pathSeparator}$id.bin');
  File fileThumb(String id) => File('${fileDir.path}${Platform.pathSeparator}$id.thumb');

  /// Bytes used by stored and in-progress (reserved) uploads.
  int get storageUsed => files.values.fold(0, (a, f) => a + f.size);
  int get storageMax => storageMB * 1024 * 1024;
  int get fileMax => min(fileMaxMB * 1024 * 1024, kMaxFileBytes);

  /// Files that could not be deleted yet (still open by a download); retried by [retryDeletes].
  final Set<String> _undeleted = {};

  void deleteFile(String id) {
    files.remove(id);
    for (final f in [fileData(id), fileThumb(id)]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        _undeleted.add(f.path);
      }
    }
    markDirty('files');
  }

  void retryDeletes() {
    for (final p in _undeleted.toList()) {
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
        _undeleted.remove(p);
      } catch (_) {}
    }
  }

  /// Removes files on disk that are not in the index (crashed uploads etc.).
  void _cleanFileDir() {
    if (!fileDir.existsSync()) return;
    for (final f in fileDir.listSync().whereType<File>()) {
      final id = f.uri.pathSegments.last.split('.').first;
      if (!files.containsKey(id)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static String tokenHash(String token) => hash.sha256.convert(utf8.encode(token)).toString();

  // ---- avatars: content-addressed files data/avatars/<sha256>.img
  Directory get _avatarDir => Directory('${dir.path}${Platform.pathSeparator}avatars');
  File _avatarFile(String h) => File('${_avatarDir.path}${Platform.pathSeparator}$h.img');
  final Map<String, List<int>> _avatarCache = {};

  /// Stores avatar bytes, returns their hash.
  String putAvatar(List<int> bytes) {
    final h = hash.sha256.convert(bytes).toString();
    _avatarDir.createSync(recursive: true);
    final f = _avatarFile(h);
    if (!f.existsSync()) f.writeAsBytesSync(bytes, flush: true);
    _avatarCache[h] = bytes;
    return h;
  }

  List<int>? avatar(String h) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
    final c = _avatarCache[h];
    if (c != null) return c;
    final f = _avatarFile(h);
    if (!f.existsSync()) return null;
    final b = f.readAsBytesSync();
    if (_avatarCache.length > 500) _avatarCache.clear();
    return _avatarCache[h] = b;
  }

  /// Deletes avatar files no user references any more.
  void pruneAvatars() {
    if (!_avatarDir.existsSync()) return;
    final used = {for (final u in users.values) u.avatarHash};
    for (final f in _avatarDir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.img') && !used.contains(name.substring(0, name.length - 4))) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}

class User {
  final int id;
  String username;
  String display;
  String passHash;
  int role = Role.member;
  int color = 0; // 0 = theme default, else ARGB
  String bio = '';
  String status = 'online';
  int created = 0;
  int avatar = 0; // index into the built-in avatar palette
  String avatarHash = ''; // sha256 of the custom avatar image ('' = palette avatar)
  String statusText = ''; // custom status ("在打游戏")
  String statusEmoji = '';
  int statusUntil = 0; // epoch ms, 0 = keep
  final Set<int> roles = {}; // RoleDef ids (@everyone implied)

  User(this.id, this.username, this.display, this.passHash);

  bool get isOwner => role == Role.owner;

  factory User.fromJson(Map<String, dynamic> j) => User(asInt(j['id']), asStr(j['user']), asStr(j['display']), asStr(j['pass']))
    ..role = asInt(j['role'])
    ..color = asInt(j['color'])
    ..bio = asStr(j['bio'])
    ..status = asStr(j['status'], 'online')
    ..created = asInt(j['created'])
    ..avatar = asInt(j['avatar'])
    ..avatarHash = asStr(j['avh'])
    ..statusText = asStr(j['stxt'])
    ..statusEmoji = asStr(j['semo'])
    ..statusUntil = asInt(j['suntil'])
    ..roles.addAll([for (final r in (j['roles'] as List? ?? const [])) asInt(r)]);

  Map<String, dynamic> toJson() => {
        'id': id,
        'user': username,
        'display': display,
        'pass': passHash,
        'role': role,
        'color': color,
        'bio': bio,
        'status': status,
        'created': created,
        'avatar': avatar,
        'avh': avatarHash,
        'stxt': statusText,
        'semo': statusEmoji,
        'suntil': statusUntil,
        'roles': roles.toList(),
      };
}

class Session {
  final String hash;
  final int uid;
  final int created;
  int lastUsed;
  String lastIp;
  Session(this.hash, this.uid, this.created, this.lastUsed, this.lastIp);

  factory Session.fromJson(Map<String, dynamic> j) =>
      Session(asStr(j['h']), asInt(j['uid']), asInt(j['created']), asInt(j['used']), asStr(j['ip']));
  Map<String, dynamic> toJson() => {'h': hash, 'uid': uid, 'created': created, 'used': lastUsed, 'ip': lastIp};
}

class Channel {
  final int id;
  String name;
  final String kind;
  String topic = '';
  int position = 0;
  int slowmode = 0; // seconds between messages per member (admins exempt)
  int bitrate = 64000; // voice channels: suggested Opus bitrate
  List<Overwrite> overwrites = [];
  List<int> members = []; // DM: the two participants
  final Set<int> hiddenFor = {}; // DM: users who closed it (shown again on a new message)

  Channel(this.id, this.name, this.kind);

  bool get hasLog => kind != ChannelKind.voice;
  bool get isDm => kind == ChannelKind.dm;

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(asInt(j['id']), asStr(j['name']), asStr(j['kind'], ChannelKind.text))
    ..topic = asStr(j['topic'])
    ..position = asInt(j['pos'])
    ..slowmode = asInt(j['slow'])
    ..bitrate = asInt(j['bitrate'], 64000)
    ..overwrites = [for (final o in (j['ow'] as List? ?? const [])) Overwrite.fromJson(o as Map<String, dynamic>)]
    ..members = [for (final m in (j['members'] as List? ?? const [])) asInt(m)]
    ..hiddenFor.addAll([for (final m in (j['hidden'] as List? ?? const [])) asInt(m)]);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'topic': topic,
        'pos': position,
        'slow': slowmode,
        'bitrate': bitrate,
        if (overwrites.isNotEmpty) 'ow': [for (final o in overwrites) o.toJson()],
        if (members.isNotEmpty) 'members': members,
        if (hiddenFor.isNotEmpty) 'hidden': hiddenFor.toList(),
      };
}

/// An uploaded attachment. Files expire [Store.fileDays] after upload; the oldest
/// are evicted when the storage quota is exceeded.
class FileRec {
  final String id;
  final String name;
  final int size;
  final int uid; // uploader
  final int ch;
  final int created; // epoch ms
  int received = 0; // bytes on disk (upload progress)
  bool complete = false;
  bool hasThumb = false;
  int w = 0, h = 0; // image size (from the uploader), 0 = not an image
  int msg = 0; // message it is attached to (0 = not sent yet)
  FileRec(this.id, this.name, this.size, this.uid, this.ch, this.created);

  factory FileRec.fromJson(Map<String, dynamic> j) =>
      FileRec(asStr(j['id']), asStr(j['name']), asInt(j['size']), asInt(j['uid']), asInt(j['ch']), asInt(j['created']))
        ..received = asInt(j['size'])
        ..complete = asBool(j['done'])
        ..hasThumb = asBool(j['thumb'])
        ..w = asInt(j['w'])
        ..h = asInt(j['h'])
        ..msg = asInt(j['msg']);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'size': size, 'uid': uid, 'ch': ch, 'created': created, 'done': complete, 'thumb': hasThumb, 'w': w, 'h': h, 'msg': msg};

  /// Attachment descriptor stored in the message.
  Map<String, dynamic> attachment() =>
      {'id': id, 'name': name, 'size': size, if (w > 0) 'w': w, if (h > 0) 'h': h, if (hasThumb) 'thumb': true, 'at': created};
}

class Ban {
  final int uid;
  final String reason;
  final int at;
  final String ip;
  Ban(this.uid, this.reason, this.at, this.ip);
  factory Ban.fromJson(Map<String, dynamic> j) => Ban(asInt(j['uid']), asStr(j['reason']), asInt(j['at']), asStr(j['ip']));
  Map<String, dynamic> toJson() => {'uid': uid, 'reason': reason, 'at': at, 'ip': ip};
}

class Invite {
  final String code;
  final int by;
  int uses; // remaining, -1 = unlimited
  final int expires; // epoch ms, 0 = never
  Invite(this.code, this.by, this.uses, this.expires);
  bool get expired => (expires > 0 && DateTime.now().millisecondsSinceEpoch > expires) || uses == 0;
  factory Invite.fromJson(Map<String, dynamic> j) => Invite(asStr(j['code']), asInt(j['by']), asInt(j['uses'], -1), asInt(j['exp']));
  Map<String, dynamic> toJson() => {'code': code, 'by': by, 'uses': uses, 'exp': expires};
}

class ChatMessage {
  final int id;
  final int ch;
  final int uid;
  String text;
  final int ts;
  int edited = 0;
  final int reply;
  bool deleted = false;
  bool pinned = false;
  bool everyone = false; // author was allowed to notify @everyone
  List<Map<String, dynamic>> attachments = const [];
  final Map<String, Set<int>> reactions = {};

  ChatMessage(this.id, this.ch, this.uid, this.text, this.ts, this.reply);

  Map<String, dynamic> toJson() => {
        'id': id,
        'ch': ch,
        'uid': uid,
        'text': text,
        'ts': ts,
        if (edited > 0) 'edited': edited,
        if (reply > 0) 'reply': reply,
        if (pinned) 'pin': true,
        if (everyone) 'ev': true,
        if (attachments.isNotEmpty) 'att': attachments,
        if (reactions.isNotEmpty) 'react': {for (final e in reactions.entries) e.key: e.value.toList()},
      };
}

/// Append-only per-channel message log. Ops (one JSON object per line):
///   {"o":"m", ...message}         new message
///   {"o":"e","id":..,"text":..,"at":..}  edit
///   {"o":"d","id":..}            delete
///   {"o":"r","id":..,"e":"👍","u":[uids]}  reaction set
class ChannelLog {
  final File file;
  ChannelLog(this.file);

  /// Messages in id order (only the newest [Store.memoryMessages]).
  final List<ChatMessage> messages = [];
  final Map<int, ChatMessage> _byId = {};
  int maxId = 0;
  final List<String> _pending = [];
  IOSink? _sink;

  void load() {
    if (!file.existsSync()) return;
    var lines = 0;
    try {
      for (final line in file.readAsLinesSync()) {
        if (line.isEmpty) continue;
        lines++;
        try {
          _apply(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {}
      }
    } catch (e) {
      stderr.writeln('读取消息记录 ${file.path} 失败：$e');
    }
    messages.removeWhere((m) => m.deleted);
    _trim();
    // compact when the log is mostly edits/deletes/old messages
    if (lines > messages.length * 2 + 1000) _compact();
  }

  void _apply(Map<String, dynamic> j) {
    switch (j['o']) {
      case 'm':
        final m = ChatMessage(asInt(j['id']), asInt(j['ch']), asInt(j['uid']), asStr(j['text']), asInt(j['ts']), asInt(j['reply']))
          ..edited = asInt(j['edited'])
          ..pinned = asBool(j['pin'])
          ..everyone = asBool(j['ev'])
          ..attachments = [for (final a in (j['att'] as List? ?? const [])) (a as Map).cast<String, dynamic>()];
        final r = j['react'];
        if (r is Map) {
          for (final e in r.entries) {
            m.reactions['${e.key}'] = {for (final u in (e.value as List)) asInt(u)};
          }
        }
        messages.add(m);
        _byId[m.id] = m;
        if (m.id > maxId) maxId = m.id;
      case 'e':
        final m = _byId[asInt(j['id'])];
        if (m != null) {
          m.text = asStr(j['text']);
          m.edited = asInt(j['at']);
        }
      case 'd':
        final m = _byId.remove(asInt(j['id']));
        m?.deleted = true;
      case 'p':
        _byId[asInt(j['id'])]?.pinned = asBool(j['on']);
      case 'r':
        final m = _byId[asInt(j['id'])];
        if (m != null) {
          final us = {for (final u in (j['u'] as List? ?? const [])) asInt(u)};
          if (us.isEmpty) {
            m.reactions.remove(asStr(j['e']));
          } else {
            m.reactions[asStr(j['e'])] = us;
          }
        }
    }
  }

  void _trim() {
    if (messages.length > Store.memoryMessages) {
      final drop = messages.length - Store.memoryMessages;
      for (final m in messages.take(drop)) {
        _byId.remove(m.id);
      }
      messages.removeRange(0, drop);
    }
  }

  void _compact() {
    try {
      final tmp = File('${file.path}.tmp');
      final sb = StringBuffer();
      for (final m in messages) {
        sb.writeln(jsonEncode({'o': 'm', ...m.toJson()}));
      }
      tmp.writeAsStringSync(sb.toString(), flush: true);
      tmp.renameSync(file.path);
    } catch (e) {
      stderr.writeln('压缩消息记录失败：$e');
    }
  }

  ChatMessage? byId(int id) => _byId[id];

  void add(ChatMessage m) {
    messages.add(m);
    _byId[m.id] = m;
    if (m.id > maxId) maxId = m.id;
    _trim();
    _append({'o': 'm', ...m.toJson()});
  }

  void edit(ChatMessage m, String text) {
    m.text = text;
    m.edited = DateTime.now().millisecondsSinceEpoch;
    _append({'o': 'e', 'id': m.id, 'text': text, 'at': m.edited});
  }

  void delete(ChatMessage m) {
    m.deleted = true;
    messages.remove(m);
    _byId.remove(m.id);
    _append({'o': 'd', 'id': m.id});
  }

  void setPinned(ChatMessage m, bool on) {
    m.pinned = on;
    _append({'o': 'p', 'id': m.id, 'on': on});
  }

  List<ChatMessage> get pinnedMessages => [for (final m in messages) if (m.pinned) m];

  /// Messages around [id] (half before, half after), oldest first.
  (List<ChatMessage>, bool) around(int id, int n) {
    var lo = 0, hi = messages.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (messages[mid].id < id) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final start = max(0, lo - n ~/ 2);
    final end = min(messages.length, start + n);
    return (messages.sublist(start, end), start > 0);
  }

  void setReaction(ChatMessage m, String e) {
    _append({'o': 'r', 'id': m.id, 'e': e, 'u': (m.reactions[e] ?? const <int>{}).toList()});
  }

  /// Up to [n] messages older than [before] (0 = newest), oldest first.
  (List<ChatMessage>, bool) page(int before, int n) {
    var end = messages.length;
    if (before > 0) {
      // binary search: first index with id >= before
      var lo = 0, hi = messages.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (messages[mid].id < before) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      end = lo;
    }
    final start = max(0, end - n);
    return (messages.sublist(start, end), start > 0);
  }

  void _append(Map<String, dynamic> op) => _pending.add(jsonEncode(op));

  Future<void> flush() async {
    if (_pending.isEmpty) return;
    final lines = _pending.join('\n');
    _pending.clear();
    try {
      _sink ??= file.openWrite(mode: FileMode.append);
      _sink!.writeln(lines);
      await _sink!.flush();
    } catch (e) {
      stderr.writeln('写入消息记录失败：$e');
    }
  }

  void close() {
    _sink?.close();
    _sink = null;
  }
}
