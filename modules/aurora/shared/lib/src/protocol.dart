import 'dart:convert';
import 'dart:typed_data';

/// Wire format (TCP): [u32 big-endian length][u8 kind][payload...]
/// length = payload length + 1 (includes the kind byte).
/// kind 0 = UTF-8 JSON object, kind 1 = voice audio.
/// Since protocol v2 the first frame pair is a plaintext key exchange (see
/// secure.dart); every later frame payload is encrypted and authenticated.
const int kFrameJson = 0;
const int kFrameVoice = 1;
const int kMaxFrame = 256 * 1024;

/// Limit for frames the client accepts from the (authenticated) server. Game
/// views can be far larger than [kMaxFrame], e.g. the 传话画画 gallery carries
/// every drawing of every book.
const int kMaxServerFrame = 32 * 1024 * 1024;
const int kProtocolVersion = 3;

/// UDP port for LAN server discovery (client broadcasts [kDiscoveryHello]).
const int kDiscoveryPort = 7789;
const String kDiscoveryHello = 'AURORA_DISCOVER';
const int kDefaultPort = 7788;

Uint8List encodeFrame(int kind, List<int> payload) {
  final out = Uint8List(5 + payload.length);
  final bd = ByteData.sublistView(out);
  bd.setUint32(0, payload.length + 1);
  out[4] = kind;
  out.setRange(5, out.length, payload);
  return out;
}

Uint8List encodeJson(Map<String, dynamic> msg) =>
    encodeFrame(kFrameJson, utf8.encode(jsonEncode(msg)));

class Frame {
  final int kind;
  final Uint8List payload;
  Frame(this.kind, this.payload);
  Map<String, dynamic> get json =>
      jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
}

/// Incremental decoder for a TCP byte stream.
class FrameDecoder {
  FrameDecoder({this.maxFrame = kMaxFrame});

  final int maxFrame;
  final BytesBuilder _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Feed bytes, returns complete frames. Throws FormatException on bad data.
  List<Frame> add(List<int> data) {
    if (_pending.isNotEmpty) _buf.add(_pending);
    _buf.add(data);
    var bytes = _buf.takeBytes();
    final frames = <Frame>[];
    var off = 0;
    while (bytes.length - off >= 4) {
      final len = ByteData.sublistView(bytes, off, off + 4).getUint32(0);
      if (len < 1 || len > maxFrame) {
        throw const FormatException('bad frame length');
      }
      if (bytes.length - off - 4 < len) break;
      final kind = bytes[off + 4];
      final payload = Uint8List.fromList(
          Uint8List.sublistView(bytes, off + 5, off + 4 + len));
      frames.add(Frame(kind, payload));
      off += 4 + len;
    }
    _pending = off == 0 ? bytes : Uint8List.fromList(bytes.sublist(off));
    return frames;
  }
}

/// Display width: ASCII = 1, others (CJK etc.) = 2. Names must be <= 18.
int nameWidth(String s) {
  var w = 0;
  for (final r in s.runes) {
    w += r < 0x80 ? 1 : 2;
  }
  return w;
}

const int kMaxNameWidth = 18;
const int kAvatarCount = 500;

String? validateName(String name) {
  final n = name.trim();
  if (n.isEmpty) return '名称不能为空';
  if (nameWidth(n) > kMaxNameWidth) return '名称过长（最多18个英文字符或9个中文字符）';
  if (hasIllegalChars(n)) return '名称包含非法字符';
  return null;
}

/// Control chars, bidi overrides and zero-width characters (used for spoofing).
bool hasIllegalChars(String s) => s.runes.any((r) =>
    r < 0x20 ||
    r == 0x7F ||
    (r >= 0x200B && r <= 0x200F) ||
    (r >= 0x202A && r <= 0x202E) ||
    (r >= 0x2066 && r <= 0x2069) ||
    r == 0xFEFF);

/// Strip control / bidi characters from free text (chat, descriptions).
String sanitizeText(String s) => String.fromCharCodes(s.runes.where((r) =>
    r == 0x0A ||
    !(r < 0x20 ||
        r == 0x7F ||
        (r >= 0x202A && r <= 0x202E) ||
        (r >= 0x2066 && r <= 0x2069))));

/// Message type keys ("t" field).
abstract class Msg {
  // client -> server
  static const hello = 'hello'; // {name, avatar, token, ver}
  static const setProfile = 'set_profile'; // {name, avatar}
  static const listRooms = 'list_rooms';
  static const createRoom = 'create_room'; // {name, game, options, password, private}
  static const joinRoom = 'join_room'; // {room (code), password, spectate}
  static const leaveRoom = 'leave_room';
  static const sit = 'sit'; // {seat}
  static const stand = 'stand';
  static const ready = 'ready'; // {ready}
  static const setGame = 'set_game'; // host {game, options}
  static const addBot = 'add_bot'; // host {seat}
  static const removeSeat = 'remove_seat'; // host {seat} kicks bot/player from seat
  static const setTimeout = 'set_timeout'; // host {sec}
  static const setPrivate = 'set_private'; // host {private}
  static const start = 'start'; // host
  static const abort = 'abort'; // host: end current game
  static const action = 'action'; // {a: {...}}
  static const chat = 'chat'; // {text}
  static const voiceState = 'voice_state'; // {mic, speaking}
  static const ping = 'ping';

  // ---- v3 platform features (client -> server) ----
  static const setRoomOpts = 'set_room_opts'; // host {botLevel?, series?, specDelay?}
  static const emote = 'emote'; // {e: index into kEmotes}
  static const autoPlay = 'auto_play'; // {on} 托管 my seat
  static const resign = 'resign'; // 认输
  static const request = 'request'; // {kind: 'undo'|'draw'} ask the other players
  static const respond = 'respond'; // {id, yes}
  static const kick = 'kick'; // host {id} remove a member from the room (5 min ban)
  static const listReplays = 'list_replays'; // -> replays
  static const getReplay = 'get_replay'; // {id} -> replay_chunk*
  static const myStats = 'my_stats'; // -> stats
  static const leaderboard = 'leaderboard'; // {game} -> board

  // ---- v3 (server -> client) ----
  static const emoteMsg = 'emote_msg'; // {from (client id), name, avatar, seat (game seat or -1), e}
  static const replays = 'replays'; // {replays: [ReplayMeta.toJson]}
  static const replayChunk = 'replay_chunk'; // {id, i, n, data (base64 of gzip bytes)}
  static const stats = 'stats'; // {stats: {...}}
  static const board = 'board'; // {game, rows: [{name, avatar, elo, p, w}]}

  // server -> client
  static const welcome = 'welcome'; // {id, name, avatar, server}
  static const rooms = 'rooms'; // {rooms:[...]}
  static const room = 'room'; // full room snapshot or {room:null}
  static const game = 'game'; // {view, seat}
  static const chatMsg = 'chat_msg'; // {from, name, avatar, text, ts, system}
  static const error = 'error'; // {msg}
  static const pong = 'pong';
  static const toast = 'toast'; // {msg}
}

/// Quick emotes / phrases (index = emote id). Clients render them; the server
/// only checks the index.
const List<String> kEmotes = [
  '👍', '😂', '😭', '😡', '😱', '🤔', '😎', '🙏', '🎉', '💤', '❤️', '🤡',
  '快点吧，等得花儿都谢了', '打得漂亮！', '哈哈哈哈', '失误了失误了', '好险！', '再来一局？',
  '你是魔鬼吗', '合作愉快', '我太难了', '稳住，我们能赢',
];

/// Bot difficulty labels (GameSetup.botLevel).
const List<String> kBotLevels = ['简单', '普通', '困难'];
