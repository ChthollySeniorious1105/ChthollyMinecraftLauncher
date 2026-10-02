import 'dart:convert';
import 'dart:typed_data';

/// Wire format (TCP): [u32 big-endian length][u8 kind][payload...]
/// length = payload length + 1 (includes the kind byte).
/// kind 0 = UTF-8 JSON object, kind 1 = voice (Opus).
///
/// The first frame pair is a plaintext X25519 key exchange (see secure.dart);
/// every later frame payload is sealed with ChaCha20-Poly1305.
///
/// Voice payloads (after decryption):
///   client → server  [u16 seq][opus packet]
///   server → client  [u32 speaker user id][u16 seq][opus packet]
///
/// Auxiliary connections (same port, same handshake) carry bulk data so it never
/// delays voice on the main connection; the first sealed JSON is [Msg.aux]:
///   upload    client → server kFrameData chunks, server answers JSON aux_ready / aux_done
///   download  server → client kFrameData chunks
///   media     screen share video, kFrameVideo:
///               client → server [u8 flags][H.264 access unit]
///               server → client [u32 streamer id][u8 flags][H.264 access unit]
const int kFrameJson = 0;
const int kFrameVoice = 1;
const int kFrameData = 2;
const int kFrameVideo = 3;
const int kMaxFrame = 256 * 1024;
const int kMaxMediaFrame = 4 * 1024 * 1024; // video keyframes can be large
const int kFileChunk = 192 * 1024; // file data per kFrameData frame
const int kProtocolVersion = 2;

const int kDefaultPort = 7800;

/// UDP port for LAN server discovery (client broadcasts [kDiscoveryHello]).
const int kDiscoveryPort = 7801;
const String kDiscoveryHello = 'PULSE_DISCOVER';

/// Content limits (enforced by the server, mirrored in the client UI).
const int kMaxMessageLength = 2000;
const int kMaxChannelName = 32;
const int kMaxTopic = 256;
const int kMaxDisplayWidth = 32;
const int kMaxVoicePacket = 1500;
const int kHistoryPage = 50;

/// Attachments: hard limit 2 GiB per file (servers can set a lower limit), at most
/// [kMaxAttachments] per message; files expire after the server's retention time
/// and the oldest are evicted when the storage quota is exceeded.
const int kMaxFileBytes = 2 * 1024 * 1024 * 1024;
const int kMaxAttachments = 10;
const int kMaxFileName = 180;
const int kMaxThumbBytes = 96 * 1024;
const int kDefaultFileDays = 7;
const int kDefaultStorageMB = 20 * 1024;

/// Video flags (first byte of a media payload).
const int kVideoKey = 1;
const int kMaxStreamKbps = 20000;

/// Custom avatars: square PNG/JPEG/WebP, <= 96 KiB, 32..512 px (clients upload 256x256).
const int kMaxAvatarBytes = 96 * 1024;
const int kAvatarUploadSize = 256;

/// Detects the image type from magic bytes; null if not an accepted avatar format.
String? avatarImageType(List<int> b) {
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
  if (b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'webp';
  }
  return null;
}

/// Reads width/height from a PNG / JPEG / WebP header without decoding (null if malformed).
(int, int)? imageSize(List<int> b) {
  int be16(int i) => (b[i] << 8) | b[i + 1];
  int be32(int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  int le16(int i) => b[i] | (b[i + 1] << 8);
  try {
    switch (avatarImageType(b)) {
      case 'png':
        return (be32(16), be32(20));
      case 'jpeg':
        var i = 2;
        while (i + 9 < b.length) {
          if (b[i] != 0xFF) return null;
          final marker = b[i + 1];
          final len = be16(i + 2);
          // SOF0..SOF15 except DHT(C4), JPG(C8), DAC(CC)
          if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) return (be16(i + 7), be16(i + 5));
          i += 2 + len;
        }
        return null;
      case 'webp':
        final kind = String.fromCharCodes(b.sublist(12, 16));
        if (kind == 'VP8 ') return (le16(26) & 0x3FFF, le16(28) & 0x3FFF);
        if (kind == 'VP8L') {
          final v = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
          return ((v & 0x3FFF) + 1, ((v >> 14) & 0x3FFF) + 1);
        }
        if (kind == 'VP8X') return ((b[24] | (b[25] << 8) | (b[26] << 16)) + 1, (b[27] | (b[28] << 8) | (b[29] << 16)) + 1);
        return null;
    }
  } catch (_) {}
  return null;
}

/// Validates an uploaded avatar; returns an error message or null.
String? validateAvatar(List<int> b) {
  if (b.isEmpty || b.length > kMaxAvatarBytes) return '头像文件过大（最多 ${kMaxAvatarBytes ~/ 1024} KB）';
  if (avatarImageType(b) == null) return '头像只支持 PNG / JPEG / WebP';
  final sz = imageSize(b);
  if (sz == null) return '头像图片已损坏';
  final (w, h) = sz;
  if (w < 32 || h < 32 || w > 512 || h > 512) return '头像尺寸需在 32–512 像素之间';
  return null;
}

Uint8List encodeFrame(int kind, List<int> payload) {
  final out = Uint8List(5 + payload.length);
  ByteData.sublistView(out).setUint32(0, payload.length + 1);
  out[4] = kind;
  out.setRange(5, out.length, payload);
  return out;
}

Uint8List encodeJson(Map<String, dynamic> msg) => encodeFrame(kFrameJson, utf8.encode(jsonEncode(msg)));

class Frame {
  final int kind;
  final Uint8List payload;
  Frame(this.kind, this.payload);
  Map<String, dynamic> get json => jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
}

/// Incremental decoder for a TCP byte stream. Incoming chunks are queued and only
/// copied once a whole frame is available (large media / file frames arrive in
/// many small TCP reads).
class FrameDecoder {
  /// Largest accepted frame; auxiliary connections raise it to [kMaxMediaFrame].
  int maxFrame;
  FrameDecoder({this.maxFrame = kMaxFrame});

  final List<Uint8List> _chunks = [];
  int _head = 0; // read offset into _chunks.first
  int _avail = 0;

  /// Bytes buffered but not yet returned as frames.
  int get buffered => _avail;

  /// Feed bytes, returns complete frames. Throws FormatException on bad data.
  List<Frame> add(List<int> data) {
    if (data.isNotEmpty) {
      _chunks.add(data is Uint8List ? data : Uint8List.fromList(data));
      _avail += data.length;
    }
    final frames = <Frame>[];
    while (_avail >= 4) {
      final h = _peek(4);
      final len = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
      if (len < 1 || len > maxFrame) throw const FormatException('bad frame length');
      if (_avail - 4 < len) break;
      _take(4);
      final body = _take(len);
      frames.add(Frame(body[0], Uint8List.sublistView(body, 1)));
    }
    return frames;
  }

  Uint8List _peek(int n) {
    final first = _chunks.first;
    if (first.length - _head >= n) return Uint8List.sublistView(first, _head, _head + n);
    final out = Uint8List(n);
    var o = 0, i = 0, off = _head;
    while (o < n) {
      final c = _chunks[i++];
      final k = (c.length - off) < (n - o) ? c.length - off : n - o;
      out.setRange(o, o + k, c, off);
      o += k;
      off = 0;
    }
    return out;
  }

  Uint8List _take(int n) {
    final out = Uint8List(n);
    var o = 0;
    while (o < n) {
      final c = _chunks.first;
      final k = (c.length - _head) < (n - o) ? c.length - _head : n - o;
      out.setRange(o, o + k, c, _head);
      o += k;
      _head += k;
      if (_head == c.length) {
        _chunks.removeAt(0);
        _head = 0;
      }
    }
    _avail -= n;
    return out;
  }
}

/// Display width: ASCII = 1, others (CJK etc.) = 2.
int textWidth(String s) {
  var w = 0;
  for (final r in s.runes) {
    w += r < 0x80 ? 1 : 2;
  }
  return w;
}

/// Control chars, bidi overrides and zero-width characters (used for spoofing).
bool hasIllegalChars(String s) => s.runes.any((r) =>
    r < 0x20 ||
    r == 0x7F ||
    (r >= 0x200B && r <= 0x200F) ||
    (r >= 0x202A && r <= 0x202E) ||
    (r >= 0x2066 && r <= 0x2069) ||
    r == 0xFEFF);

/// Strip control / bidi characters from free text (messages, topics). Keeps newlines.
String sanitizeText(String s) => String.fromCharCodes(s.runes.where((r) =>
    r == 0x0A ||
    !(r < 0x20 || r == 0x7F || (r >= 0x202A && r <= 0x202E) || (r >= 0x2066 && r <= 0x2069))));

final RegExp _userRe = RegExp(r'^[A-Za-z0-9_.\-]{2,32}$');

/// Login name: 2–32 of A-Z a-z 0-9 _ . - (case-insensitive unique).
String? validateUsername(String u) {
  if (!_userRe.hasMatch(u)) return '用户名需为 2–32 位字母、数字或 _ . -';
  return null;
}

String? validateDisplayName(String n) {
  final s = n.trim();
  if (s.isEmpty) return '昵称不能为空';
  if (textWidth(s) > kMaxDisplayWidth) return '昵称过长（最多 32 个英文字符或 16 个中文字符）';
  if (hasIllegalChars(s)) return '昵称包含非法字符';
  return null;
}

String? validatePassword(String p) {
  if (p.length < 8) return '密码至少 8 位';
  if (p.length > 128) return '密码过长';
  return null;
}

/// File names: strip path separators / reserved characters, keep it short.
String sanitizeFileName(String n) {
  var s = sanitizeText(n).replaceAll('\n', ' ').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  s = s.replaceAll(RegExp(r'^\.+'), '').trim();
  if (s.isEmpty) s = 'file';
  if (s.length > kMaxFileName) {
    final dot = s.lastIndexOf('.');
    final ext = dot > 0 && s.length - dot <= 12 ? s.substring(dot) : '';
    s = s.substring(0, kMaxFileName - ext.length) + ext;
  }
  return s;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Image attachments that clients render inline.
bool isImageName(String n) => RegExp(r'\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false).hasMatch(n);

String? validateChannelName(String n) {
  final s = n.trim();
  if (s.isEmpty) return '频道名不能为空';
  if (textWidth(s) > kMaxChannelName) return '频道名过长';
  if (hasIllegalChars(s)) return '频道名包含非法字符';
  return null;
}

int asInt(Object? v, [int def = 0]) => v is int ? v : (v is num ? v.toInt() : def);
String asStr(Object? v, [String def = '']) => v is String ? v : def;
bool asBool(Object? v, [bool def = false]) => v is bool ? v : def;

/// Coarse account level sent as `role` in member JSON for display:
/// 2 = owner, 1 = has a role with [Perm.administrator], 0 = everyone else.
/// Real authorization uses roles + permissions ([RoleDef], [Perms]).
abstract class Role {
  static const member = 0;
  static const admin = 1;
  static const owner = 2;
  static String label(int r) => switch (r) { owner => '服主', admin => '管理员', _ => '成员' };
}

/// Permission bits (Discord-like). Channel overwrites can allow / deny the
/// [Perm.channelScoped] ones per role.
abstract class Perm {
  static const viewChannel = 1 << 0;
  static const sendMessages = 1 << 1;
  static const attachFiles = 1 << 2;
  static const addReactions = 1 << 3;
  static const mentionEveryone = 1 << 4;
  static const manageMessages = 1 << 5; // delete others' messages, pin
  static const connect = 1 << 6;
  static const speak = 1 << 7;
  static const stream = 1 << 8; // screen share
  static const muteMembers = 1 << 9;
  static const moveMembers = 1 << 10;
  static const kickMembers = 1 << 11;
  static const banMembers = 1 << 12;
  static const manageChannels = 1 << 13;
  static const manageRoles = 1 << 14;
  static const manageServer = 1 << 15; // server settings, ban list, storage
  static const createInvite = 1 << 16;
  static const administrator = 1 << 17; // everything, bypasses channel overwrites
  static const all = (1 << 18) - 1;

  static const everyoneDefault = viewChannel | sendMessages | attachFiles | addReactions | connect | speak | stream;
  static const channelScoped = viewChannel | sendMessages | attachFiles | addReactions | mentionEveryone | manageMessages |
      connect | speak | stream | muteMembers | moveMembers | manageChannels;
  static const moderation = muteMembers | moveMembers | kickMembers | banMembers;

  /// (bit, label, description) in UI order.
  static const List<(int, String, String)> labels = [
    (administrator, '管理员', '拥有全部权限，并无视频道权限设置（谨慎授予）'),
    (manageServer, '管理服务器', '修改服务器名称、公告、注册方式、文件存储设置，查看封禁列表'),
    (manageRoles, '管理角色', '创建 / 编辑比自己最高角色低的角色，并分配给成员'),
    (manageChannels, '管理频道', '创建、编辑、删除、排序频道及设置频道权限'),
    (kickMembers, '踢出成员', ''),
    (banMembers, '封禁成员', ''),
    (createInvite, '创建邀请码', ''),
    (viewChannel, '查看频道', '看到频道并阅读消息记录'),
    (sendMessages, '发送消息', ''),
    (attachFiles, '上传文件', '在消息中附加文件和图片'),
    (addReactions, '添加表情回应', ''),
    (mentionEveryone, '提及 @everyone', '@everyone / @全体 会提醒所有人'),
    (manageMessages, '管理消息', '删除他人消息、置顶消息'),
    (connect, '连接语音', '加入语音频道'),
    (speak, '语音发言', ''),
    (stream, '屏幕共享', '在语音频道中共享屏幕或窗口'),
    (muteMembers, '服务器静音成员', ''),
    (moveMembers, '移动成员', '在语音频道之间移动成员'),
  ];
}

/// A server role. Role id 0 is "@everyone" (position 0, cannot be deleted or moved).
class RoleDef {
  final int id;
  String name;
  int color; // ARGB, 0 = none
  int position; // higher = more powerful
  int perms;
  bool hoist; // shown as its own group in the member list
  bool mentionable;
  RoleDef(this.id, this.name, {this.color = 0, this.position = 0, this.perms = 0, this.hoist = false, this.mentionable = false});

  static const everyone = 0;

  factory RoleDef.fromJson(Map<String, dynamic> j) => RoleDef(asInt(j['id']), asStr(j['name']),
      color: asInt(j['color']), position: asInt(j['pos']), perms: asInt(j['perms']) & Perm.all, hoist: asBool(j['hoist']), mentionable: asBool(j['ment']));
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'color': color, 'pos': position, 'perms': perms, 'hoist': hoist, 'ment': mentionable};
}

/// Channel permission overwrite for one role.
class Overwrite {
  final int role;
  int allow, deny;
  Overwrite(this.role, this.allow, this.deny);
  factory Overwrite.fromJson(Map<String, dynamic> j) =>
      Overwrite(asInt(j['id']), asInt(j['allow']) & Perm.channelScoped, asInt(j['deny']) & Perm.channelScoped);
  Map<String, dynamic> toJson() => {'id': role, 'allow': allow, 'deny': deny};
}

/// Permission math shared by the server (enforcement) and the client (UI).
abstract class Perms {
  /// Server-wide permissions of a member.
  static int base(Map<int, RoleDef> roles, Iterable<int> userRoles, {required bool owner}) {
    if (owner) return Perm.all;
    var p = roles[RoleDef.everyone]?.perms ?? Perm.everyoneDefault;
    for (final r in userRoles) {
      p |= roles[r]?.perms ?? 0;
    }
    return (p & Perm.administrator) != 0 ? Perm.all : p;
  }

  /// Permissions in a channel: @everyone overwrite first, then all of the member's
  /// role overwrites combined (deny, then allow wins) — same order as Discord.
  static int channel(Map<int, RoleDef> roles, Iterable<int> userRoles, List<Overwrite> ow, {required bool owner}) {
    var p = base(roles, userRoles, owner: owner);
    if ((p & Perm.administrator) != 0) return Perm.all;
    for (final o in ow) {
      if (o.role == RoleDef.everyone) p = (p & ~o.deny) | o.allow;
    }
    var allow = 0, deny = 0;
    for (final o in ow) {
      if (o.role != RoleDef.everyone && userRoles.contains(o.role)) {
        allow |= o.allow;
        deny |= o.deny;
      }
    }
    p = (p & ~deny) | allow;
    // without view nothing else in the channel applies
    if ((p & Perm.viewChannel) == 0) p &= ~Perm.channelScoped;
    return p;
  }

  /// Highest role position (the owner is above every role).
  static int top(Map<int, RoleDef> roles, Iterable<int> userRoles, {required bool owner}) {
    if (owner) return 1 << 30;
    var t = 0;
    for (final r in userRoles) {
      final p = roles[r]?.position ?? 0;
      if (p > t) t = p;
    }
    return t;
  }
}

abstract class ChannelKind {
  static const text = 'text';
  static const voice = 'voice';
  static const dm = 'dm'; // private conversation between two members
}

/// Registration policy (server setting).
abstract class RegMode {
  static const open = 'open';
  static const invite = 'invite';
  static const closed = 'closed';
}

/// Presence states chosen by the user (online is implied by a connection).
const List<String> kStatuses = ['online', 'idle', 'dnd', 'invisible'];

/// Quick reactions offered by the client; the server accepts any short emoji string.
const List<String> kQuickReactions = ['👍', '❤️', '😂', '🎉', '😮', '😢', '🔥', '👀'];

/// Message type keys ("t" field).
abstract class Msg {
  // ---- client → server (before login) ----
  static const register = 'register'; // {user, pass, display, invite?, serverPass?, ver}
  static const login = 'login'; // {user, pass, serverPass?, ver}
  static const resume = 'resume'; // {token, ver}

  // ---- client → server (after login) ----
  static const logout = 'logout'; // revoke this session token
  static const sendMsg = 'send'; // {ch, text, reply?, nonce, att?: [upload id]} (text may be empty with attachments)
  static const editMsg = 'edit'; // {ch, id, text}
  static const deleteMsg = 'delete'; // {ch, id}
  static const history = 'history'; // {ch, before?} -> history
  static const typing = 'typing'; // {ch}
  static const react = 'react'; // {ch, id, e} toggles my reaction
  static const voiceJoin = 'vjoin'; // {ch}
  static const voiceLeave = 'vleave';
  static const voiceState = 'vstate'; // {mute, deaf}
  static const setProfile = 'profile'; // {display?, color?, status?, bio?, avatar?(palette index)}
  static const setAvatar = 'set_avatar'; // {data: base64 image} or {data: ''} to remove
  static const getAvatar = 'get_avatar'; // {id, h} -> avatar_data
  static const setStatusText = 'status_text'; // {text, emoji, until (epoch ms, 0 = never)}
  static const search = 'search'; // {q, ch? (0 = all text channels), from? (uid)} -> search_result
  static const pin = 'pin'; // {ch, id, on} (admins or the author)
  static const pins = 'pins'; // {ch} -> pins_data
  static const around = 'around'; // {ch, id} -> history_data centred on a message (jump to)
  static const changePassword = 'chpass'; // {old, new}
  static const ping = 'ping';
  static const dmOpen = 'dm_open'; // {uid} -> dm
  static const dmClose = 'dm_close'; // {id} hide from my list (reappears on a new message)
  static const uploadRequest = 'up_req'; // {ch, name, size, nonce, thumb?: base64 jpeg, w?, h?} -> up_ticket
  static const uploadCancel = 'up_cancel'; // {id}
  static const fileRequest = 'file_req'; // {id} -> file_ticket
  static const getThumb = 'get_thumb'; // {id} -> thumb_data
  static const mediaRequest = 'media_req'; // {} -> media_ticket (screen share connection)
  static const streamStart = 'stream_start'; // {w, h, fps, title} (in a voice channel, needs Perm.stream)
  static const streamStop = 'stream_stop';
  static const watch = 'watch'; // {uid, on}
  static const keyframe = 'keyframe'; // viewer → server → streamer: please send an IDR {uid}

  // ---- auxiliary connection (first message after the handshake) ----
  static const aux = 'aux'; // {ticket, kind: 'upload'|'download'|'media', id?, offset?}
  static const auxReady = 'aux_ready'; // {offset, size} upload: resume offset; download: total size
  static const auxDone = 'aux_done'; // {id}
  static const auxError = 'aux_err'; // {msg}

  // ---- admin ----
  static const chCreate = 'ch_create'; // {name, kind, topic?}
  static const chUpdate = 'ch_update'; // {id, name?, topic?, slowmode?}
  static const chDelete = 'ch_delete'; // {id}
  static const chMove = 'ch_move'; // {id, delta}
  static const setRole = 'set_role'; // {id, role} (owner only)
  static const kick = 'kick'; // {id}
  static const ban = 'ban'; // {id, reason?}
  static const unban = 'unban'; // {id}
  static const serverMute = 'smute'; // {id, on}
  static const moveMember = 'vmove'; // {id, ch}
  static const serverSettings = 'settings'; // {name?, motd?, regMode?, serverPass?}
  static const createInvite = 'invite'; // {uses?, hours?} -> invite_code (createInvite)
  static const listBans = 'bans'; // -> bans
  static const roleCreate = 'role_create'; // {name} (manageRoles)
  static const roleUpdate = 'role_update'; // {id, name?, color?, perms?, hoist?, ment?}
  static const roleDelete = 'role_delete'; // {id}
  static const roleMove = 'role_move'; // {id, delta}
  static const memberRoles = 'member_roles'; // {id, roles: [role id]}
  static const channelPerms = 'ch_perms'; // {id, ow: [{id, allow, deny}]}
  static const storageInfo = 'storage'; // -> storage_data (manageServer)

  // ---- server → client ----
  static const authOk = 'auth_ok'; // {token, me}
  static const authErr = 'auth_err'; // {msg, code}
  static const welcome = 'welcome'; // full state snapshot
  static const message = 'msg'; // {ch, m: message}
  static const messageEdited = 'msg_edit'; // {ch, id, text, edited}
  static const messageDeleted = 'msg_del'; // {ch, id}
  static const historyData = 'history_data'; // {ch, msgs, more}
  static const typingNotice = 'typing_on'; // {ch, uid}
  static const reaction = 'reaction'; // {ch, id, e, uids}
  static const channels = 'channels'; // {channels (each with my effective 'perms'), base: my server-wide perms}
  static const member = 'member'; // {m} upsert; m.avh = avatar hash ('' = palette avatar)
  static const avatarData = 'avatar_data'; // {id, h, data (base64)}
  static const searchResult = 'search_result'; // {q, msgs: [message], more}
  static const pinsData = 'pins_data'; // {ch, msgs}
  static const pinned = 'pinned'; // {ch, id, on, by}
  static const memberRemoved = 'member_rm'; // {id}
  static const presence = 'presence'; // {id, online, status}
  static const voiceUser = 'vuser'; // {id, ch (null = left), mute, deaf, smute}
  static const server = 'server'; // {name, motd, regMode, hasPass, fileDays, fileMaxMB, storageMB}
  static const roles = 'roles'; // {roles: [RoleDef]}
  static const dm = 'dm'; // {c: channel} a DM channel (opened or got a message)
  static const uploadTicket = 'up_ticket'; // {id, ticket, nonce, offset}
  static const fileTicket = 'file_ticket'; // {id, ticket, size, name}
  static const thumbData = 'thumb_data'; // {id, data}
  static const filesGone = 'files_gone'; // {ids} expired / evicted / deleted
  static const mediaTicket = 'media_ticket'; // {ticket}
  static const keyframeRequest = 'keyframe_req'; // to a streamer: a viewer needs an IDR frame
  static const streams = 'streams'; // {streams: [{uid, ch, w, h, fps, title, viewers: [uid]}]}
  static const storageData = 'storage_data'; // {used, files, maxMB, fileDays, fileMaxMB}
  static const inviteCode = 'invite_code'; // {code, uses, expires}
  static const bans = 'ban_list'; // {bans: [{id, user, display, reason, at}]}
  static const toast = 'toast'; // {msg}
  static const error = 'error'; // {msg, fatal?}
  static const pong = 'pong';
}
