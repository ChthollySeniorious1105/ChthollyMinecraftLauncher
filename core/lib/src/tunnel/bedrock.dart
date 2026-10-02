import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Minimal RakNet offline-message helpers used by Bedrock Edition LAN discovery.
///
///   Unconnected Ping (0x01) / Ping Open Connections (0x02):
///     u8 id | i64 time | 16B OFFLINE_MESSAGE_DATA_ID magic | i64 client guid
///   Unconnected Pong (0x1c):
///     u8 id | i64 time | i64 server guid | magic | u16 len | utf8 server-id string
abstract class RakNet {
  static const unconnectedPing = 0x01;
  static const unconnectedPingOpen = 0x02;
  static const unconnectedPong = 0x1c;
  static const openConnectionRequest1 = 0x05;

  static const defaultPort4 = 19132;
  static const defaultPort6 = 19133;

  /// Largest datagram relayed (RakNet MTU is ≤ 1500; some clients probe with up to 1492 + headers).
  static const maxDatagram = 2048;

  static final magic = Uint8List.fromList(
      [0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe, 0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78]);

  static bool _hasMagic(Uint8List d, int at) {
    if (d.length < at + 16) return false;
    for (var i = 0; i < 16; i++) {
      if (d[at + i] != magic[i]) return false;
    }
    return true;
  }

  static Uint8List ping(int time, int clientGuid, {bool openConnections = false}) {
    final out = Uint8List(33);
    final b = ByteData.sublistView(out);
    out[0] = openConnections ? unconnectedPingOpen : unconnectedPing;
    b.setInt64(1, time);
    out.setRange(9, 25, magic);
    b.setInt64(25, clientGuid);
    return out;
  }

  /// Parses an Unconnected Ping (0x01 or 0x02). Returns the ping time, or null if [d] is not a ping.
  /// The trailing client guid is optional (some tools omit it).
  static int? parsePing(Uint8List d) {
    if (d.length < 25 || (d[0] != unconnectedPing && d[0] != unconnectedPingOpen) || !_hasMagic(d, 9)) return null;
    return ByteData.sublistView(d).getInt64(1);
  }

  static Uint8List pong(int time, int serverGuid, String serverId) {
    var s = utf8.encode(serverId);
    if (s.length > 0xffff) s = s.sublist(0, 0xffff);
    final out = Uint8List(35 + s.length);
    final b = ByteData.sublistView(out);
    out[0] = unconnectedPong;
    b.setInt64(1, time);
    b.setInt64(9, serverGuid);
    out.setRange(17, 33, magic);
    b.setUint16(33, s.length);
    out.setRange(35, out.length, s);
    return out;
  }

  /// Parses an Unconnected Pong into (time, server guid, server-id string).
  static (int, int, String)? parsePong(Uint8List d) {
    if (d.length < 35 || d[0] != unconnectedPong || !_hasMagic(d, 17)) return null;
    final b = ByteData.sublistView(d);
    final len = b.getUint16(33);
    if (d.length < 35 + len) return null;
    return (b.getInt64(1), b.getInt64(9), utf8.decode(Uint8List.sublistView(d, 35, 35 + len), allowMalformed: true));
  }

  /// Signed 64-bit view of an unsigned decimal guid string (as found in pong strings).
  static int guidToInt(String guid) {
    final v = BigInt.tryParse(guid.trim());
    if (v == null) return 0;
    return v.toUnsigned(64).toSigned(64).toInt();
  }

  static int randomGuid() {
    final r = Random.secure();
    return (r.nextInt(1 << 32) << 31) ^ r.nextInt(1 << 31);
  }
}

/// Parsed Bedrock server-id string:
/// `MCPE;motd;protocol;version;players;max;serverGuid;subMotd;gamemode;gamemodeNum;port4;port6;`
class BedrockServerInfo {
  final String edition; // MCPE / MCEE
  final String motd;
  final int protocol;
  final String version;
  final int players;
  final int maxPlayers;
  final String guid; // unsigned decimal
  final String subMotd;
  final String gameMode;
  final int gameModeNum;
  final int port4;
  final int port6;

  const BedrockServerInfo({
    this.edition = 'MCPE',
    this.motd = '',
    this.protocol = 0,
    this.version = '',
    this.players = 0,
    this.maxPlayers = 8,
    this.guid = '',
    this.subMotd = '',
    this.gameMode = 'Survival',
    this.gameModeNum = 1,
    this.port4 = RakNet.defaultPort4,
    this.port6 = RakNet.defaultPort6,
  });

  static String _field(String s, int max) {
    final t = s.replaceAll(';', ',').replaceAll(RegExp('[\\x00-\\x1f\\x7f]'), '').trim();
    return t.length > max ? t.substring(0, max) : t;
  }

  /// Encodes the server-id string carried in an Unconnected Pong.
  String encode() => [
        _field(edition, 8).isEmpty ? 'MCPE' : _field(edition, 8),
        _field(motd, 64),
        protocol,
        _field(version, 32),
        players,
        maxPlayers,
        guid.isEmpty ? '0' : _field(guid, 20),
        _field(subMotd, 64),
        _field(gameMode, 16),
        gameModeNum,
        port4,
        port6,
        '',
      ].join(';');

  static BedrockServerInfo? parse(String s) {
    final f = s.split(';');
    if (f.length < 6 || (f[0] != 'MCPE' && f[0] != 'MCEE')) return null;
    String at(int i) => i < f.length ? f[i] : '';
    int num(int i, int d) => int.tryParse(at(i).trim()) ?? d;
    return BedrockServerInfo(
      edition: f[0],
      motd: at(1),
      protocol: num(2, 0),
      version: at(3),
      players: num(4, 0),
      maxPlayers: num(5, 0),
      guid: at(6),
      subMotd: at(7),
      gameMode: at(8),
      gameModeNum: num(9, 1),
      port4: num(10, RakNet.defaultPort4),
      port6: num(11, RakNet.defaultPort6),
    );
  }

  BedrockServerInfo copyWith({String? motd, String? subMotd, String? guid, int? port4, int? port6, int? players, int? maxPlayers}) =>
      BedrockServerInfo(
        edition: edition,
        motd: motd ?? this.motd,
        protocol: protocol,
        version: version,
        players: players ?? this.players,
        maxPlayers: maxPlayers ?? this.maxPlayers,
        guid: guid ?? this.guid,
        subMotd: subMotd ?? this.subMotd,
        gameMode: gameMode,
        gameModeNum: gameModeNum,
        port4: port4 ?? this.port4,
        port6: port6 ?? this.port6,
      );

  /// Wire form inside CMLS control messages (`host` / `binfo` / `joined`). Ports are local to each side and not sent.
  Map<String, Object?> toJson() => {
        'edition': edition,
        'motd': motd,
        'protocol': protocol,
        'version': version,
        'players': players,
        'max': maxPlayers,
        'guid': guid,
        'subMotd': subMotd,
        'gamemode': gameMode,
        'gamemodeNum': gameModeNum,
      };

  /// Parses (and sanitises / clamps) the wire form; safe on untrusted input.
  static BedrockServerInfo fromJson(Object? j) {
    if (j is! Map) return const BedrockServerInfo();
    int n(Object? v, int d, int lo, int hi) => ((v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? d).clamp(lo, hi);
    final guid = '${j['guid'] ?? ''}';
    return BedrockServerInfo(
      edition: j['edition'] == 'MCEE' ? 'MCEE' : 'MCPE',
      motd: _field('${j['motd'] ?? ''}', 64),
      protocol: n(j['protocol'], 0, 0, 1 << 30),
      version: _field('${j['version'] ?? ''}', 32),
      players: n(j['players'], 0, 0, 100000),
      maxPlayers: n(j['max'], 8, 0, 100000),
      guid: RegExp(r'^\d{1,20}$').hasMatch(guid) ? guid : '',
      subMotd: _field('${j['subMotd'] ?? ''}', 64),
      gameMode: _field('${j['gamemode'] ?? 'Survival'}', 16),
      gameModeNum: n(j['gamemodeNum'], 1, 0, 9),
    );
  }

  /// True when the parts shown in the LAN list differ.
  bool differs(BedrockServerInfo o) =>
      motd != o.motd || protocol != o.protocol || version != o.version || players != o.players || maxPlayers != o.maxPlayers || subMotd != o.subMotd || gameMode != o.gameMode;

  @override
  String toString() => encode();
}
