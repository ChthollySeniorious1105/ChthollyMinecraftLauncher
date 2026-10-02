import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
///
/// Bedrock Edition (UDP / RakNet) additions — all optional, Java rooms and old clients are unaffected:
///   C→S `auth` may carry `caps:['bedrock']`; the server only lets clients with this capability join
///         Bedrock rooms (an old CML would otherwise open a TCP listener for a UDP game).
///   C→S `host` {…, edition:'bedrock', bedrock:{edition,motd,protocol,version,players,max,guid,subMotd,
///         gamemode,gamemodeNum}, publicUdp?:bool}
///         → `hosted` {room, edition:'bedrock', publicUdp?:port}. A server that does not echo
///         `edition:'bedrock'` is too old; the client then leaves the room and reports an error.
///   `rooms` entries and `joined` gain `edition` ('java' when absent); `joined` also has `bedrock` {…}.
///   C→S `binfo` {bedrock:{…}}   host refreshes the pong info (players, motd…); the server relays
///         it to guests as S→C `binfo`.
///   C→S `uopen` {sid}            guest opens a UDP flow (one per local game endpoint ip:port);
///         the server allocates a room-wide flow id and forwards `uopen` {sid', src:'guest'|'public'} to the host.
///   both `uclose` {sid}          either side closes a flow. Flows idle for [TunnelLimits.flowIdle] are
///         closed by whichever side notices first (the server sweeps too).
/// Datagram frames ([FrameKind.datagram]) carry `u32 flowId | one UDP datagram` — exactly one datagram per
/// frame, so message boundaries are kept. Datagrams are capped at [TunnelLimits.maxDatagram] bytes
/// (frames above that are a protocol violation) and every hop drops — never queues — datagrams that
/// exceed the per-flow rate budget ([TokenBucket]). Flow ids and TCP stream ids are separate namespaces.
/// Datagram frames are sealed like every other frame (kind byte 3 is the AEAD associated data).
abstract class FrameKind {
  static const hello = 0;
  static const control = 1;
  static const data = 2;
  static const datagram = 3;
}

abstract class TunnelLimits {
  /// Max payload per frame (data frames are chunked to [dataChunk]).
  static const maxFrame = 256 * 1024;
  static const dataChunk = 32 * 1024;
  static const defaultPort = 25590;
  static const handshakeTimeout = Duration(seconds: 10);

  /// Largest relayed UDP datagram (RakNet MTU ≤ 1500).
  static const maxDatagram = 2048;

  /// UDP flows without traffic for this long are closed.
  static const flowIdle = Duration(seconds: 60);
  static const maxFlowsPerGuest = 8;
  static const maxFlowsPerRoom = 64;

  /// Per-flow, per-direction datagram budget (Bedrock uses well under 1 MiB/s per player).
  static const flowPacketsPerSec = 2000.0;
  static const flowBytesPerSec = 2.0 * 1024 * 1024;
}

/// Token bucket over packets and bytes; [allow] returns false (caller drops) when over budget.
class TokenBucket {
  final double packetRate, byteRate, packetBurst, byteBurst;
  double _p, _b;
  int _last = DateTime.now().microsecondsSinceEpoch;
  TokenBucket({this.packetRate = TunnelLimits.flowPacketsPerSec, this.byteRate = TunnelLimits.flowBytesPerSec, double? packetBurst, double? byteBurst})
      : packetBurst = packetBurst ?? packetRate * 2,
        byteBurst = byteBurst ?? byteRate * 2,
        _p = packetBurst ?? packetRate * 2,
        _b = byteBurst ?? byteRate * 2;

  bool allow(int bytes) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _last) / 1e6;
    _last = now;
    _p = (_p + dt * packetRate).clamp(0, packetBurst);
    _b = (_b + dt * byteRate).clamp(0, byteBurst);
    if (_p < 1 || _b < bytes) return false;
    _p -= 1;
    _b -= bytes;
    return true;
  }
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

  /// Payload of a [FrameKind.datagram] frame: `u32 flowId | datagram`.
  static Uint8List datagramPayload(int flowId, List<int> datagram) => dataPayload(flowId, datagram);

  /// Splits a datagram payload into (flowId, datagram); null when malformed or oversize.
  static (int, Uint8List)? parseDatagram(Uint8List plain) {
    if (plain.length < 4 || plain.length > 4 + TunnelLimits.maxDatagram) return null;
    return (ByteData.sublistView(plain, 0, 4).getUint32(0), Uint8List.sublistView(plain, 4));
  }

  static Uint8List json(Map<String, Object?> m) => utf8.encode(jsonEncode(m));
}

/// Ordered, backpressure-aware writer for a tunnel socket.
///
/// All frames go through one controller piped into the socket with `addStream`, which pauses the
/// controller while the OS send buffer is full; [queued] counts bytes still waiting in user space.
/// Reliable frames (control / TCP data) are always queued; callers drop datagrams while [congested]
/// (they must decide *before* sealing, because sealed frames consume a nonce counter).
class FrameWriter {
  final _ctl = StreamController<List<int>>();
  int queued = 0;
  bool _closed = false;

  /// Datagrams are dropped while more than this many bytes are queued.
  static const congestionLimit = 256 * 1024;

  FrameWriter(Socket socket) {
    socket.addStream(_ctl.stream.map((b) {
      queued -= b.length;
      return b;
    })).then((_) {}, onError: (Object _) {}); // dead sockets are reported via socket.done
  }

  bool get congested => queued > congestionLimit;

  void add(List<int> frame) {
    if (_closed) return;
    queued += frame.length;
    _ctl.add(frame);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _ctl.close();
  }
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
