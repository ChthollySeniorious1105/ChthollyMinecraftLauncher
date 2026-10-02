import 'dart:convert';
import 'dart:typed_data';

/// CML ⇄ CMLS wire protocol.
///
/// Every frame: `u32 length (big-endian, of kind+payload) | u8 kind | payload`.
/// Before the handshake completes only [FrameKind.hello] frames (plaintext JSON) are allowed;
/// afterwards every payload is sealed by the [SecureChannel] (kind byte is the AEAD associated data).
///
/// Control messages are JSON objects with a `t` field:
///   C→S `auth`   {name, password?}                        → `ok` {server, motd} | `error`
///   C→S `host`   {title, version, password?, public}      → `hosted` {room}
///   C→S `rooms`                                           → `rooms` {list:[{room,title,version,host,players,locked}]}
///   C→S `join`   {room, password?}                        → `joined` {room,title,version,host}
///   C→S `leave`                                           → (room closed for guest / room destroyed for host)
///   C→S `open`   {sid}            guest opens a game stream; server forwards `open` {sid'} to the host
///   both `close` {sid}            either side closes a stream
///   S→C `members`{list:[name]}    room roster updates (host and guests)
///   S→C `closed` {reason}         room ended
///   both `ping` / `pong` {ts}
/// Data frames ([FrameKind.data]) carry `u32 sid | bytes` (raw Minecraft TCP stream bytes).
abstract class FrameKind {
  static const hello = 0;
  static const control = 1;
  static const data = 2;
}

abstract class TunnelLimits {
  /// Max payload per frame (data frames are chunked to [dataChunk]).
  static const maxFrame = 256 * 1024;
  static const dataChunk = 32 * 1024;
  static const defaultPort = 25590;
  static const handshakeTimeout = Duration(seconds: 10);
}

class Frame {
  final int kind;
  final Uint8List payload;
  Frame(this.kind, this.payload);

  static Uint8List encode(int kind, List<int> payload) {
    final out = Uint8List(5 + payload.length);
    final d = ByteData.sublistView(out);
    d.setUint32(0, payload.length + 1);
    out[4] = kind;
    out.setRange(5, out.length, payload);
    return out;
  }

  static Uint8List dataPayload(int sid, List<int> bytes, [int start = 0, int? end]) {
    end ??= bytes.length;
    final out = Uint8List(4 + end - start);
    ByteData.sublistView(out).setUint32(0, sid);
    out.setRange(4, out.length, bytes, start);
    return out;
  }

  static Uint8List json(Map<String, Object?> m) => utf8.encode(jsonEncode(m));
}

/// Incremental frame parser.
class FrameDecoder {
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// Feeds bytes and returns complete frames. Throws [FormatException] on oversize frames.
  List<Frame> add(List<int> chunk) {
    _buf.add(_pending);
    _buf.add(chunk);
    var data = _buf.takeBytes();
    final out = <Frame>[];
    var p = 0;
    while (data.length - p >= 5) {
      final len = ByteData.sublistView(data, p, p + 4).getUint32(0);
      if (len < 1 || len > TunnelLimits.maxFrame + 64) throw const FormatException('frame too large');
      if (data.length - p - 4 < len) break;
      out.add(Frame(data[p + 4], Uint8List.fromList(Uint8List.sublistView(data, p + 5, p + 4 + len))));
      p += 4 + len;
    }
    _pending = p == data.length ? Uint8List(0) : Uint8List.fromList(Uint8List.sublistView(data, p));
    data = Uint8List(0);
    return out;
  }
}

/// Minecraft Java LAN discovery packet (UDP multicast 224.0.2.60:4445).
abstract class LanBroadcast {
  static const group = '224.0.2.60';
  static const port = 4445;

  static String packet(String motd, int port) => '[MOTD]${motd.replaceAll('[', '(').replaceAll(']', ')')}[/MOTD][AD]$port[/AD]';

  /// Parses a LAN packet into (motd, port).
  static (String, int)? parse(String s) {
    final m = RegExp(r'\[MOTD\](.*)\[/MOTD\]\[AD\](\d+)\[/AD\]').firstMatch(s);
    if (m == null) return null;
    final port = int.tryParse(m.group(2)!);
    return port == null ? null : (m.group(1)!, port);
  }
}
