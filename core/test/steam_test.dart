import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cml_core/cml_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds a v29 appinfo.vdf with the given apps (appid -> (name, type)).
Uint8List appInfoV29(Map<int, (String, String)> apps) {
  final strings = ['appinfo', 'common', 'name', 'type'];
  final b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void cstr(String s) => b..add(utf8.encode(s))..addByte(0);
  final entries = <Uint8List>[];
  for (final e in apps.entries) {
    final kv = BytesBuilder();
    void k(int type, int key) => kv..addByte(type)..add((ByteData(4)..setUint32(0, key, Endian.little)).buffer.asUint8List());
    k(0, 0); // appinfo {
    k(0, 1); // common {
    k(1, 2);
    kv..add(utf8.encode(e.value.$1))..addByte(0);
    k(1, 3);
    kv..add(utf8.encode(e.value.$2))..addByte(0);
    kv.addByte(8); // }
    kv.addByte(8); // }
    kv.addByte(8); // root end
    final body = BytesBuilder()
      ..add(Uint8List(4 + 4 + 8 + 20 + 4 + 20)) // infoState, lastUpdated, picsToken, sha1, change, binSha1
      ..add(kv.takeBytes());
    final bytes = body.takeBytes();
    final ent = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, e.key, Endian.little)).buffer.asUint8List())
      ..add((ByteData(4)..setUint32(0, bytes.length, Endian.little)).buffer.asUint8List())
      ..add(bytes);
    entries.add(ent.takeBytes());
  }
  final head = 4 + 4 + 8;
  final appsLen = entries.fold<int>(0, (a, x) => a + x.length) + 4;
  u32(0x07564429);
  u32(1);
  b.add((ByteData(8)..setInt64(0, head + appsLen, Endian.little)).buffer.asUint8List());
  for (final e in entries) {
    b.add(e);
  }
  u32(0); // end of apps
  u32(strings.length);
  for (final s in strings) {
    cstr(s);
  }
  return b.takeBytes();
}

void main() {
  test('Vdf parses nested keys, escapes and comments', () {
    final v = Vdf.parse('// c\n"a" { "b" "x\\"y" "c" { "d" "1" } }');
    expect((v['a'] as Map)['b'], 'x"y');
    expect(((v['a'] as Map)['c'] as Map)['d'], '1');
  });

  test('appinfo v29 names and types', () {
    final info = AppInfo.parse(appInfoV29({10: ('Game A', 'Game'), 20: ('Some DLC', 'DLC')}));
    expect(info.apps[10]!.name, 'Game A');
    expect(info.apps[10]!.type, 'game');
    expect(info.apps[20]!.type, 'dlc');
  });

  test('collections: hidden / favourite / user, deleted and dynamic ones skipped', () {
    String col(Map m) => jsonEncode(m);
    final text = jsonEncode([
      ['user-collections.hidden', {'key': 'user-collections.hidden', 'value': col({'id': 'hidden', 'name': 'Hidden', 'added': [1, 2, 3], 'removed': [3]})}],
      ['user-collections.favorite', {'value': col({'id': 'favorite', 'name': 'Fav', 'added': [5], 'removed': []})}],
      ['user-collections.uc-a', {'value': col({'id': 'uc-a', 'name': 'Mine', 'added': [1, 7], 'removed': []})}],
      ['user-collections.uc-dead', {'is_deleted': true}],
      ['user-collections.uc-dyn', {'value': col({'id': 'uc-dyn', 'name': 'Installed', 'filterSpec': {}})}],
      ['showcases', {'value': '{}'}],
    ]);
    final cols = {for (final c in Steam.readCollections(text)) c.id: c};
    expect(cols.keys.toSet(), {'hidden', 'favorite', 'uc-a'});
    expect(cols['hidden']!.apps, {1, 2}); // "removed" wins
    expect(cols['uc-a']!.name, 'Mine');
  });

  test('library: hidden flag, installed state, playtime, DLC dropped, account order', () async {
    final root = await Directory.systemTemp.createTemp('cml_steam');
    try {
      final s = root.path;
      const acct = 1000;
      const steamId = '76561197960266728'; // 76561197960265728 + 1000
      File(p.join(s, 'config', 'loginusers.vdf'))
        ..createSync(recursive: true)
        ..writeAsStringSync('"users" { "$steamId" { "PersonaName" "Me" "AutoLogin" "1" "Timestamp" "5" } }');
      final cfg = p.join(s, 'userdata', '$acct', 'config');
      for (final id in [10, 11, 20, 30]) {
        File(p.join(cfg, 'librarycache', '$id.json'))
          ..createSync(recursive: true)
          ..writeAsStringSync('[]');
      }
      File(p.join(cfg, 'librarycache', 'achievement_progress.json')).writeAsStringSync('{}');
      File(p.join(cfg, 'localconfig.vdf')).writeAsStringSync(
          '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { "10" { "LastPlayed" "1700000000" "Playtime" "95" } } } } } '
          '"FamilyGroup" { "name" "Fam" } }');
      File(p.join(cfg, 'cloudstorage', 'cloud-storage-namespace-1.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode([
          ['user-collections.hidden', {'value': jsonEncode({'id': 'hidden', 'name': 'H', 'added': [11], 'removed': []})}],
        ]));
      File(p.join(s, 'appcache', 'appinfo.vdf'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(appInfoV29({10: ('Alpha', 'game'), 11: ('Beta Game', 'game'), 20: ('Alpha DLC', 'dlc'), 30: ('Zeta', 'game')}));
      File(p.join(s, 'steamapps', 'appmanifest_10.acf'))
        ..createSync(recursive: true)
        ..writeAsStringSync('"AppState" { "appid" "10" "name" "Alpha" "installdir" "Alpha" "StateFlags" "4" "SizeOnDisk" "1234" }');
      File(p.join(s, 'appcache', 'librarycache', '30', 'abc', 'library_600x900.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0]);

      final accounts = Steam.accounts(s);
      expect(accounts.single.mostRecent, true);
      expect(accounts.single.accountId, acct);
      final lib = await Steam.library(s, accounts.single);
      expect(lib.warnings, isEmpty);
      expect(lib.familyName, 'Fam');
      final byId = {for (final g in lib.games) g.appId: g};
      expect(byId.keys.toSet(), {10, 11, 30}); // DLC dropped
      expect(byId[10]!.installed, true);
      expect(byId[10]!.install!.sizeOnDisk, 1234);
      expect(byId[10]!.playtimeMinutes, 95);
      expect(byId[10]!.lastPlayed, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
      expect(byId[11]!.hidden, true);
      expect(byId[30]!.coverPath, endsWith('library_600x900.jpg')); // hashed sub-folder
      expect(lib.games.map((g) => g.name).toList(), ['Alpha', 'Beta Game', 'Zeta']);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('broken collection file degrades to a warning, not a failure', () async {
    final root = await Directory.systemTemp.createTemp('cml_steam');
    try {
      final s = root.path;
      final cfg = p.join(s, 'userdata', '1', 'config');
      File(p.join(cfg, 'cloudstorage', 'cloud-storage-namespace-1.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{not json');
      final lib = await Steam.library(s, const SteamAccount('x', 1, 'x', true));
      expect(lib.warnings, contains('隐藏列表与收藏夹'));
    } finally {
      await root.delete(recursive: true);
    }
  });
}
