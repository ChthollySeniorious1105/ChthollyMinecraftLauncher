import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../common/errors.dart';

/// Reads the library of the Steam client logged in on this machine, from local files only
/// (read-only, no network, no API key). Launch / install / uninstall are handed to the Steam client
/// through documented `steam://` URLs — CML never downloads game files itself.
///
/// Files (relative to the Steam install):
///   config/loginusers.vdf                                 accounts that logged in here
///   `config/libraryfolders.vdf` + `<lib>/steamapps/appmanifest_<id>.acf`   installed games, download state
///   `userdata/<accountId>/config/librarycache/<id>.json`   every app in the account's library (incl. family-shared)
///   `userdata/<accountId>/config/localconfig.vdf`          LastPlayed / Playtime, family group
///   `userdata/<accountId>/config/cloudstorage/cloud-storage-namespace-1.json`   collections (hidden / favourite / user)
///   `appcache/appinfo.vdf`                                  app names and types (binary KV, v28 / v29)
///   `appcache/librarycache/<id>/…`                          cover images
///
/// These are Valve's internal formats. Every reader is defensive: a file that can't be parsed
/// degrades that one feature (e.g. no hidden filter) instead of failing the whole library.
class SteamAccount {
  final String steamId; // 64-bit, as string
  final int accountId; // userdata folder name
  final String personaName;
  /// The account Steam logs into automatically (MostRecent, else AutoLogin, else newest Timestamp).
  final bool mostRecent;
  final int timestamp;
  const SteamAccount(this.steamId, this.accountId, this.personaName, this.mostRecent, [this.timestamp = 0]);
}

/// Download / install state from an appmanifest.
class SteamInstall {
  final String libraryPath;
  final String installDir;
  final int sizeOnDisk;
  final int stateFlags;
  final int bytesToDownload;
  final int bytesDownloaded;
  const SteamInstall(this.libraryPath, this.installDir, this.sizeOnDisk, this.stateFlags, this.bytesToDownload, this.bytesDownloaded);

  /// StateFlags bit 4 = fully installed; 1024 = update running, 512 / 1048576 = update required / queued.
  bool get fullyInstalled => stateFlags & 4 != 0;
  bool get updating => stateFlags & (1024 | 512 | 2 | 1048576) != 0 && !(fullyInstalled && bytesToDownload > 0 && bytesDownloaded >= bytesToDownload);
  double? get progress => bytesToDownload > 0 && bytesDownloaded < bytesToDownload ? bytesDownloaded / bytesToDownload : null;
  String get path => p.join(libraryPath, 'steamapps', 'common', installDir);
}

class SteamGame {
  final int appId;
  final String name;
  final SteamInstall? install;
  final DateTime? lastPlayed;
  final int playtimeMinutes;
  final bool hidden;
  final bool favorite;

  /// User collection ids this app is in.
  final Set<String> collections;

  /// Local cover image (portrait 600×900 preferred), if Steam cached one.
  final String? coverPath;
  final String? headerPath;
  const SteamGame({
    required this.appId,
    required this.name,
    this.install,
    this.lastPlayed,
    this.playtimeMinutes = 0,
    this.hidden = false,
    this.favorite = false,
    this.collections = const {},
    this.coverPath,
    this.headerPath,
  });

  bool get installed => install != null;

  /// Public Steam CDN artwork, used when there is no local cache (the cloudflare host 301-redirects here).
  String get coverUrl => 'https://shared.steamstatic.com/store_item_assets/steam/apps/$appId/library_600x900.jpg';
  String get headerUrl => 'https://shared.steamstatic.com/store_item_assets/steam/apps/$appId/header.jpg';
}

class SteamCollection {
  final String id;
  final String name;
  final Set<int> apps;
  const SteamCollection(this.id, this.name, this.apps);
}

class SteamLibrary {
  final SteamAccount account;
  final List<SteamGame> games;
  final List<SteamCollection> collections;

  /// Features that could not be read, for a non-fatal notice in the UI (e.g. "隐藏列表").
  final List<String> warnings;
  final String? familyName;
  const SteamLibrary(this.account, this.games, this.collections, this.warnings, this.familyName);
}

abstract class Steam {
  /// Steam install folder from the registry (HKCU\Software\Valve\Steam\SteamPath), else the default.
  static Future<String?> installPath() async {
    if (!Platform.isWindows) return null;
    try {
      final r = await Process.run('reg', ['query', r'HKCU\Software\Valve\Steam', '/v', 'SteamPath']);
      final m = RegExp(r'SteamPath\s+REG_SZ\s+(.+)').firstMatch('${r.stdout}');
      if (m != null) {
        final path = m.group(1)!.trim().replaceAll('/', r'\');
        if (Directory(path).existsSync()) return path;
      }
    } catch (_) {}
    for (final c in [r'C:\Program Files (x86)\Steam', r'C:\Program Files\Steam']) {
      if (Directory(c).existsSync()) return c;
    }
    return null;
  }

  static List<SteamAccount> accounts(String steam) {
    final f = File(p.join(steam, 'config', 'loginusers.vdf'));
    if (!f.existsSync()) return const [];
    final users = Vdf.parse(f.readAsStringSync())['users'];
    if (users is! Map) return const [];
    final out = <SteamAccount>[];
    for (final e in users.entries) {
      final id = BigInt.tryParse('${e.key}');
      if (id == null || e.value is! Map) continue;
      final v = e.value as Map;
      final acct = (id - BigInt.parse('76561197960265728')).toInt();
      if (!Directory(p.join(steam, 'userdata', '$acct')).existsSync()) continue;
      final recent = '${v['MostRecent']}' == '1' || '${v['AutoLogin']}' == '1';
      out.add(SteamAccount('${e.key}', acct, '${v['PersonaName'] ?? v['AccountName'] ?? acct}', recent, int.tryParse('${v['Timestamp'] ?? 0}') ?? 0));
    }
    out.sort((a, b) => a.mostRecent != b.mostRecent ? (b.mostRecent ? 1 : -1) : b.timestamp.compareTo(a.timestamp));
    if (out.isNotEmpty && !out.any((a) => a.mostRecent)) {
      final f = out.first;
      out[0] = SteamAccount(f.steamId, f.accountId, f.personaName, true, f.timestamp);
    }
    return out;
  }

  /// Library folders (each has a steamapps/ subfolder).
  static List<String> libraryFolders(String steam) {
    final f = File(p.join(steam, 'config', 'libraryfolders.vdf'));
    final out = <String>{steam};
    if (f.existsSync()) {
      final lf = Vdf.parse(f.readAsStringSync())['libraryfolders'];
      if (lf is Map) {
        for (final v in lf.values) {
          if (v is Map && v['path'] != null) out.add('${v['path']}'.replaceAll(r'\\', r'\'));
        }
      }
    }
    return out.where((d) => Directory(p.join(d, 'steamapps')).existsSync()).toList();
  }

  static Map<int, ({String name, SteamInstall install})> installed(String steam) {
    final out = <int, ({String name, SteamInstall install})>{};
    for (final lib in libraryFolders(steam)) {
      final dir = Directory(p.join(lib, 'steamapps'));
      for (final f in dir.listSync().whereType<File>()) {
        final m = RegExp(r'appmanifest_(\d+)\.acf$').firstMatch(p.basename(f.path));
        if (m == null) continue;
        try {
          final st = Vdf.parse(f.readAsStringSync())['AppState'];
          if (st is! Map) continue;
          int n(String k) => int.tryParse('${st[k] ?? 0}') ?? 0;
          out[int.parse(m.group(1)!)] = (
            name: '${st['name'] ?? ''}',
            install: SteamInstall(lib, '${st['installdir'] ?? ''}', n('SizeOnDisk'), n('StateFlags'), n('BytesToDownload'), n('BytesDownloaded')),
          );
        } catch (_) {}
      }
    }
    return out;
  }

  /// Full library of [account]. [appInfo] can be reused between calls (it is the slow part).
  static Future<SteamLibrary> library(String steam, SteamAccount account, {AppInfo? appInfo}) async {
    final warnings = <String>[];
    final cfg = p.join(steam, 'userdata', '${account.accountId}', 'config');

    // apps in the library: per-account library cache (one json per app)
    final ids = <int>{};
    final cacheDir = Directory(p.join(cfg, 'librarycache'));
    if (cacheDir.existsSync()) {
      for (final f in cacheDir.listSync().whereType<File>()) {
        final id = int.tryParse(p.basenameWithoutExtension(f.path));
        if (id != null && f.path.endsWith('.json')) ids.add(id);
      }
    } else {
      warnings.add('库缓存');
    }
    final inst = installed(steam);
    ids.addAll(inst.keys);

    // names and types
    AppInfo? info = appInfo;
    if (info == null) {
      try {
        info = await AppInfo.load(p.join(steam, 'appcache', 'appinfo.vdf'));
      } catch (_) {
        warnings.add('游戏名称');
      }
    }

    // playtime
    final played = <int, (DateTime?, int)>{};
    String? familyName;
    try {
      final lc = Vdf.parse(File(p.join(cfg, 'localconfig.vdf')).readAsStringSync())['UserLocalConfigStore'];
      if (lc is Map) {
        final apps = _path(lc, ['Software', 'Valve', 'Steam', 'apps']);
        if (apps is Map) {
          for (final e in apps.entries) {
            final id = int.tryParse('${e.key}');
            if (id == null || e.value is! Map) continue;
            final v = e.value as Map;
            final lp = int.tryParse('${v['LastPlayed'] ?? ''}');
            played[id] = (lp == null || lp == 0 ? null : DateTime.fromMillisecondsSinceEpoch(lp * 1000), int.tryParse('${v['Playtime'] ?? 0}') ?? 0);
          }
        }
        final fam = lc['FamilyGroup'];
        if (fam is Map && fam['name'] != null) familyName = '${fam['name']}';
      }
    } catch (_) {
      warnings.add('游玩记录');
    }

    // collections
    final cols = <SteamCollection>[];
    Set<int> hidden = {}, favorite = {};
    try {
      final all = readCollections(File(p.join(cfg, 'cloudstorage', 'cloud-storage-namespace-1.json')).readAsStringSync());
      for (final c in all) {
        if (c.id == 'hidden') {
          hidden = c.apps;
        } else if (c.id == 'favorite') {
          favorite = c.apps;
        } else {
          cols.add(c);
        }
      }
    } catch (_) {
      warnings.add('隐藏列表与收藏夹');
    }

    final art = _artIndex(steam);
    final games = <SteamGame>[];
    for (final id in ids) {
      final a = info?.apps[id];
      final i = inst[id];
      // keep games; installed applications / demos too (things the user can launch). Drop DLC, betas,
      // configs and Steam's own tools (e.g. Steamworks Common Redistributables).
      final type = a?.type ?? (i != null ? 'game' : '');
      if (!(type == 'game' || (i != null && (type == 'application' || type == 'demo')))) continue;
      final name = (a?.name.isNotEmpty == true ? a!.name : i?.name) ?? '';
      if (name.isEmpty) continue;
      final pl = played[id];
      games.add(SteamGame(
        appId: id,
        name: name,
        install: i?.install,
        lastPlayed: pl?.$1,
        playtimeMinutes: pl?.$2 ?? 0,
        hidden: hidden.contains(id),
        favorite: favorite.contains(id),
        collections: {for (final c in cols) if (c.apps.contains(id)) c.id},
        // portrait art: older clients cache library_600x900*, newer ones library_capsule* (300×450)
        coverPath: _pick(art[id], const ['library_600x900_schinese.jpg', 'library_600x900.jpg', 'library_capsule_schinese.jpg', 'library_capsule.jpg']),
        headerPath: _pick(art[id], const ['header_schinese.jpg', 'header.jpg', 'library_header_schinese.jpg', 'library_header.jpg']),
      ));
    }
    games.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return SteamLibrary(account, games, cols, warnings, familyName);
  }

  /// Parses Steam's collection store. Format: `[[key, {value: "<json>", is_deleted?}], …]`; collection
  /// values are `{id, name, added: [appid], removed: [appid]}` (dynamic collections carry `filterSpec`
  /// instead of a list; they are skipped — their contents are computed by the Steam client).
  static List<SteamCollection> readCollections(String text) {
    final j = jsonDecode(text);
    if (j is! List) throw const FormatException('collections');
    final out = <SteamCollection>[];
    for (final e in j) {
      if (e is! List || e.length < 2 || e[0] is! String || e[1] is! Map) continue;
      final key = e[0] as String;
      final v = e[1] as Map;
      if (!key.startsWith('user-collections.') || v['is_deleted'] == true || v['value'] is! String) continue;
      final c = jsonDecode(v['value'] as String);
      if (c is! Map || c['filterSpec'] != null) continue;
      final added = {for (final x in (c['added'] as List? ?? const [])) if (x is int) x};
      added.removeAll({for (final x in (c['removed'] as List? ?? const [])) if (x is int) x});
      out.add(SteamCollection('${c['id'] ?? key.substring(17)}', '${c['name'] ?? ''}', added));
    }
    return out;
  }

  /// One pass over appcache/librarycache: appid -> (file name -> path). Newer clients put art in
  /// hashed sub-folders (`<id>/<hash>/library_600x900.jpg`); the top-level file wins when both exist.
  static Map<int, Map<String, String>> _artIndex(String steam) {
    final out = <int, Map<String, String>>{};
    final root = Directory(p.join(steam, 'appcache', 'librarycache'));
    if (!root.existsSync()) return out;
    for (final d in root.listSync().whereType<Directory>()) {
      final id = int.tryParse(p.basename(d.path));
      if (id == null) continue;
      final files = <String, String>{};
      for (final e in d.listSync()) {
        if (e is File) {
          files[p.basename(e.path)] = e.path;
        } else if (e is Directory) {
          for (final f in e.listSync().whereType<File>()) {
            files.putIfAbsent(p.basename(f.path), () => f.path);
          }
        }
      }
      out[id] = files;
    }
    return out;
  }

  static String? _pick(Map<String, String>? files, List<String> names) {
    if (files == null) return null;
    for (final n in names) {
      final f = files[n];
      if (f != null) return f;
    }
    return null;
  }

  static Object? _path(Map m, List<String> keys) {
    Object? cur = m;
    for (final k in keys) {
      if (cur is! Map) return null;
      // VDF keys are case-insensitive in practice (Software vs software)
      cur = cur[k] ?? cur.entries.where((e) => '${e.key}'.toLowerCase() == k.toLowerCase()).map((e) => e.value).firstOrNull;
    }
    return cur;
  }

  // ---- actions: all performed by the Steam client ----
  static Future<void> launch(int appId) => _open('steam://rungameid/$appId');
  static Future<void> install(int appId) => _open('steam://install/$appId');
  static Future<void> uninstall(int appId) => _open('steam://uninstall/$appId');
  static Future<void> validate(int appId) => _open('steam://validate/$appId');
  static Future<void> storePage(int appId) => _open('steam://store/$appId');
  static Future<void> libraryPage(int appId) => _open('steam://nav/games/details/$appId');
  static Future<void> downloads() => _open('steam://open/downloads');

  static Future<void> _open(String url) async {
    try {
      await Process.start('explorer.exe', [url], mode: ProcessStartMode.detached);
    } catch (e) {
      throw CmlException('steam_open', '无法调用 Steam（$url）', e);
    }
  }
}

/// Minimal parser for Valve's text KeyValues (.vdf / .acf): nested `"key" { … }` and `"key" "value"`.
abstract class Vdf {
  static Map<String, Object> parse(String s) {
    var i = 0;
    String? token() {
      while (i < s.length) {
        final c = s.codeUnitAt(i);
        if (c == 0x2F && i + 1 < s.length && s.codeUnitAt(i + 1) == 0x2F) {
          while (i < s.length && s.codeUnitAt(i) != 0x0A) {
            i++;
          }
        } else if (c <= 0x20) {
          i++;
        } else {
          break;
        }
      }
      if (i >= s.length) return null;
      final c = s[i];
      if (c == '{' || c == '}') {
        i++;
        return c;
      }
      if (c == '"') {
        final b = StringBuffer();
        i++;
        while (i < s.length && s[i] != '"') {
          if (s[i] == r'\' && i + 1 < s.length) {
            final n = s[i + 1];
            b.write(switch (n) { 'n' => '\n', 't' => '\t', _ => n });
            i += 2;
          } else {
            b.write(s[i++]);
          }
        }
        i++;
        return b.toString();
      }
      final st = i;
      while (i < s.length && s.codeUnitAt(i) > 0x20 && s[i] != '{' && s[i] != '}') {
        i++;
      }
      return s.substring(st, i);
    }

    Map<String, Object> obj() {
      final m = <String, Object>{};
      while (true) {
        final k = token();
        if (k == null || k == '}') return m;
        final v = token();
        if (v == null) return m;
        m[k] = v == '{' ? obj() : v;
      }
    }

    return obj();
  }
}

class AppInfoEntry {
  final String name;
  final String type; // game, dlc, application, tool, demo, config, music, beta …
  const AppInfoEntry(this.name, this.type);
}

/// Steam's appcache/appinfo.vdf: header, then per app `appid, size, infoState, lastUpdated, picsToken,
/// sha1, changeNumber, binarySha1` and a binary KeyValues body. v29 (0x07564429) stores key names in
/// a string table at the offset written after the header; v28 (0x07564428) inlines them.
/// Only `appinfo.common.name` / `.type` are extracted; the rest of each body is skipped by size.
class AppInfo {
  final Map<int, AppInfoEntry> apps;
  AppInfo(this.apps);

  static Future<AppInfo> load(String path) async => parse(await File(path).readAsBytes());

  static AppInfo parse(Uint8List d) {
    final bd = ByteData.sublistView(d);
    final magic = bd.getUint32(0, Endian.little);
    var off = 8;
    List<String>? strings;
    if (magic == 0x07564429) {
      final st = bd.getInt64(off, Endian.little);
      off += 8;
      final n = bd.getUint32(st, Endian.little);
      var q = st + 4;
      strings = List.filled(n, '');
      for (var k = 0; k < n; k++) {
        final e = d.indexOf(0, q);
        strings[k] = utf8.decode(d.sublist(q, e), allowMalformed: true);
        q = e + 1;
      }
    } else if (magic != 0x07564428) {
      throw FormatException('appinfo.vdf: unsupported version 0x${magic.toRadixString(16)}');
    }
    final out = <int, AppInfoEntry>{};
    while (off + 8 <= d.length) {
      final appId = bd.getUint32(off, Endian.little);
      if (appId == 0) break;
      final size = bd.getUint32(off + 4, Endian.little);
      final body = off + 8;
      final kv = body + 4 + 4 + 8 + 20 + 4 + 20;
      try {
        final r = _KvReader(d, bd, kv, strings);
        final root = r.readObject();
        final common = (root['appinfo'] as Map?)?['common'] as Map?;
        if (common != null) out[appId] = AppInfoEntry('${common['name'] ?? ''}', '${common['type'] ?? ''}'.toLowerCase());
      } catch (_) {
        // one bad entry doesn't invalidate the file
      }
      off = body + size;
    }
    return AppInfo(out);
  }
}

class _KvReader {
  final Uint8List d;
  final ByteData bd;
  int p;
  final List<String>? strings;
  _KvReader(this.d, this.bd, this.p, this.strings);

  String _cstr() {
    final e = d.indexOf(0, p);
    final s = utf8.decode(d.sublist(p, e), allowMalformed: true);
    p = e + 1;
    return s;
  }

  Map<String, Object> readObject() {
    final out = <String, Object>{};
    while (true) {
      final t = d[p++];
      if (t == 8) return out;
      final String key;
      if (strings != null) {
        key = strings![bd.getUint32(p, Endian.little)];
        p += 4;
      } else {
        key = _cstr();
      }
      switch (t) {
        case 0:
          out[key] = readObject();
        case 1:
          out[key] = _cstr();
        case 2:
          out[key] = bd.getInt32(p, Endian.little);
          p += 4;
        case 3:
          out[key] = bd.getFloat32(p, Endian.little);
          p += 4;
        case 7:
          out[key] = bd.getUint64(p, Endian.little);
          p += 8;
        default:
          throw FormatException('kv type $t');
      }
    }
  }
}
