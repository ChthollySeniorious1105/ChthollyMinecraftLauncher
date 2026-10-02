import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../nbt/nbt.dart';

/// One entry of `servers.dat`.
class SavedServer {
  String name;
  String ip;

  /// Base64 PNG favicon cached by the game.
  String? icon;

  /// `acceptTextures`: null = prompt, true/false = resource pack policy.
  bool? acceptTextures;
  SavedServer(this.name, this.ip, {this.icon, this.acceptTextures});

  (String, int) get hostPort {
    var s = ip.trim();
    if (s.startsWith('[')) {
      final e = s.indexOf(']');
      final port = s.length > e + 2 ? int.tryParse(s.substring(e + 2)) : null;
      return (s.substring(1, e), port ?? 25565);
    }
    final i = s.lastIndexOf(':');
    if (i > 0 && s.indexOf(':') == i) return (s.substring(0, i), int.tryParse(s.substring(i + 1)) ?? 25565);
    return (s, 25565);
  }
}

/// Reads / writes `servers.dat` (uncompressed big-endian NBT) of a game directory.
class ServerList {
  final String path;
  ServerList(String gameDir) : path = p.join(gameDir, 'servers.dat');

  Future<List<SavedServer>> load() async {
    final f = File(path);
    if (!await f.exists()) return [];
    final root = Nbt.decodeAuto(await f.readAsBytes()).tag;
    return [
      for (final t in root.getList('servers')?.value ?? const <Tag>[])
        if (t is CompoundTag)
          SavedServer(
            t.getString('name') ?? 'Minecraft Server',
            t.getString('ip') ?? '',
            icon: t.getString('icon'),
            acceptTextures: t.has('acceptTextures') ? (t.getInt('acceptTextures') ?? 0) != 0 : null,
          )
    ];
  }

  /// Writes the list, keeping a one-time backup of the game's original file.
  Future<void> save(List<SavedServer> servers) async {
    final f = File(path);
    final bak = File('$path.cml-bak');
    if (await f.exists() && !await bak.exists()) await f.copy(bak.path);
    final list = ListTag(TagId.compound);
    for (final s in servers) {
      list.add(CompoundTag({
        'name': StringTag(s.name),
        'ip': StringTag(s.ip),
        if (s.icon != null) 'icon': StringTag(s.icon!),
        if (s.acceptTextures != null) 'acceptTextures': ByteTag(s.acceptTextures! ? 1 : 0),
      }));
    }
    await f.parent.create(recursive: true);
    await f.writeAsBytes(Nbt.encode(CompoundTag({'servers': list})));
  }
}

/// Result of a Server List Ping.
class ServerStatus {
  final String motd;
  final String version;
  final int protocol;
  final int online;
  final int max;
  final List<String> sample;
  final Uint8List? favicon;
  final int pingMs;
  ServerStatus(this.motd, this.version, this.protocol, this.online, this.max, this.sample, this.favicon, this.pingMs);
}

/// Modern (1.7+) Server List Ping with SRV lookup, falling back to the 1.6 legacy ping.
abstract class ServerPinger {
  static Future<ServerStatus> ping(String address, {Duration timeout = const Duration(seconds: 5)}) async {
    var (host, port) = SavedServer('', address).hostPort;
    if (!address.contains(':')) {
      final srv = await _srv(host);
      if (srv != null) (host, port) = srv;
    }
    try {
      return await _modern(host, port, timeout);
    } catch (_) {
      return _legacy(host, port, timeout);
    }
  }

  /// `_minecraft._tcp.<host>` SRV record via nslookup (no DNS library in dart:io).
  static Future<(String, int)?> _srv(String host) async {
    if (InternetAddress.tryParse(host) != null || host == 'localhost') return null;
    try {
      final r = await Process.run('nslookup', ['-type=SRV', '_minecraft._tcp.$host']).timeout(const Duration(seconds: 3));
      final out = '${r.stdout}';
      final port = RegExp(r'port\s*=\s*(\d+)').firstMatch(out)?.group(1);
      final target = RegExp(r'svr hostname\s*=\s*(\S+)').firstMatch(out)?.group(1);
      if (port != null && target != null) return (target.replaceAll(RegExp(r'\.$'), ''), int.parse(port));
    } catch (_) {}
    return null;
  }

  static List<int> _varint(int v) {
    final out = <int>[];
    v &= 0xffffffff;
    do {
      var b = v & 0x7f;
      v >>>= 7;
      if (v != 0) b |= 0x80;
      out.add(b);
    } while (v != 0);
    return out;
  }

  static List<int> _string(String s) {
    final b = utf8.encode(s);
    return [..._varint(b.length), ...b];
  }

  static List<int> _packet(int id, List<int> body) {
    final data = [..._varint(id), ...body];
    return [..._varint(data.length), ...data];
  }

  static Future<ServerStatus> _modern(String host, int port, Duration timeout) async {
    final sw = Stopwatch()..start();
    final s = await Socket.connect(host, port, timeout: timeout);
    final connectMs = sw.elapsedMilliseconds;
    final buf = BytesBuilder(copy: false);
    final done = Completer<void>();
    final sub = s.listen((d) {
      buf.add(d);
      if (!done.isCompleted && _complete(buf.toBytes())) done.complete();
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    });
    try {
      final handshake = _packet(0x00, [..._varint(767), ..._string(host), (port >> 8) & 0xff, port & 0xff, ..._varint(1)]);
      s.add([...handshake, ..._packet(0x00, const [])]);
      await done.future.timeout(timeout);
      final bytes = buf.toBytes();
      var pos = 0;
      int readVar() {
        var v = 0, shift = 0;
        while (true) {
          final b = bytes[pos++];
          v |= (b & 0x7f) << shift;
          if (b & 0x80 == 0) return v;
          shift += 7;
        }
      }

      readVar(); // packet length
      if (readVar() != 0) throw const FormatException('bad status packet');
      final len = readVar();
      final json = jsonDecode(utf8.decode(bytes.sublist(pos, pos + len))) as Map;
      final players = json['players'] as Map? ?? const {};
      final ver = json['version'] as Map? ?? const {};
      Uint8List? icon;
      final fav = json['favicon'];
      if (fav is String && fav.contains(',')) {
        try {
          icon = base64.decode(fav.substring(fav.indexOf(',') + 1).replaceAll('\n', ''));
        } catch (_) {}
      }
      return ServerStatus(
        motdText(json['description']),
        '${ver['name'] ?? ''}',
        (ver['protocol'] as num?)?.toInt() ?? -1,
        (players['online'] as num?)?.toInt() ?? 0,
        (players['max'] as num?)?.toInt() ?? 0,
        [for (final x in players['sample'] as List? ?? []) '${(x as Map)['name']}'],
        icon,
        connectMs,
      );
    } finally {
      await sub.cancel();
      s.destroy();
    }
  }

  static bool _complete(Uint8List b) {
    var pos = 0, v = 0, shift = 0;
    while (pos < b.length && pos < 5) {
      final x = b[pos++];
      v |= (x & 0x7f) << shift;
      if (x & 0x80 == 0) return b.length - pos >= v;
      shift += 7;
    }
    return false;
  }

  /// Pre-1.7 servers: 0xFE 0x01 → kick packet with §1 fields.
  static Future<ServerStatus> _legacy(String host, int port, Duration timeout) async {
    final sw = Stopwatch()..start();
    final s = await Socket.connect(host, port, timeout: timeout);
    try {
      s.add([0xFE, 0x01]);
      final data = await s.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d)).timeout(timeout);
      final b = data.toBytes();
      if (b.isEmpty || b[0] != 0xFF) throw const FormatException('not a minecraft server');
      final chars = <int>[];
      for (var i = 3; i + 1 < b.length; i += 2) {
        chars.add((b[i] << 8) | b[i + 1]);
      }
      final parts = String.fromCharCodes(chars).split('\u0000');
      if (parts.length >= 6) {
        return ServerStatus(parts[3], parts[2], int.tryParse(parts[1]) ?? -1, int.tryParse(parts[4]) ?? 0, int.tryParse(parts[5]) ?? 0, const [], null,
            sw.elapsedMilliseconds);
      }
      final old = String.fromCharCodes(chars).split('§');
      return ServerStatus(old.first, '', -1, int.tryParse(old.length > 1 ? old[1] : '') ?? 0, int.tryParse(old.length > 2 ? old[2] : '') ?? 0,
          const [], null, sw.elapsedMilliseconds);
    } finally {
      s.destroy();
    }
  }

  /// Flattens a chat component (string / {text, extra}) into plain text with § codes kept.
  static String motdText(Object? d) {
    if (d == null) return '';
    if (d is String) return d;
    if (d is List) return d.map(motdText).join();
    if (d is Map) {
      final codes = StringBuffer();
      const colors = {
        'black': '0', 'dark_blue': '1', 'dark_green': '2', 'dark_aqua': '3', 'dark_red': '4', 'dark_purple': '5', 'gold': '6', 'gray': '7',
        'dark_gray': '8', 'blue': '9', 'green': 'a', 'aqua': 'b', 'red': 'c', 'light_purple': 'd', 'yellow': 'e', 'white': 'f',
      };
      final c = colors[d['color']];
      if (c != null) codes.write('§$c');
      if (d['bold'] == true) codes.write('§l');
      if (d['italic'] == true) codes.write('§o');
      return '$codes${d['text'] ?? ''}${motdText(d['extra'])}';
    }
    return '$d';
  }
}
