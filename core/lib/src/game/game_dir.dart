import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import 'version.dart';

/// A `.minecraft` directory.
class GameDir {
  final String root;
  GameDir(this.root);

  String get versionsDir => p.join(root, 'versions');
  String get librariesDir => p.join(root, 'libraries');
  String get assetsDir => p.join(root, 'assets');
  String versionDir(String id) => p.join(versionsDir, id);
  String versionJson(String id) => p.join(versionDir(id), '$id.json');
  String versionJar(String id) => p.join(versionDir(id), '$id.jar');
  String nativesDir(String id) => p.join(versionDir(id), 'natives-windows-x86_64');
  String library(String relPath) => p.join(librariesDir, relPath);

  /// Per-instance CML settings (Java, memory, isolation …).
  String instanceConfig(String id) => p.join(versionDir(id), 'cml.json');

  /// Working directory for an instance; isolated instances use their version folder.
  String gameDirFor(String id, {required bool isolated}) => isolated ? versionDir(id) : root;

  Future<Map<String, dynamic>> readVersionJson(String id) async {
    final f = File(versionJson(id));
    if (!await f.exists()) throw CmlException('version_missing', '找不到版本 $id 的 JSON 文件');
    try {
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } on FormatException catch (e) {
      throw CmlException('version_broken', '版本 $id 的 JSON 文件已损坏', e);
    }
  }

  /// Loads and resolves `inheritsFrom` chains.
  Future<GameVersion> load(String id, {int depth = 0}) async {
    if (depth > 8) throw CmlException('version_loop', '版本 $id 的继承关系过深或循环');
    final j = await readVersionJson(id);
    final parentId = j['inheritsFrom'] as String?;
    final parent = parentId == null ? null : await load(parentId, depth: depth + 1);
    return GameVersion.resolve(j, parent: parent);
  }

  /// Lists installed versions (folders containing a matching JSON).
  Future<List<InstalledVersion>> list() async {
    final d = Directory(versionsDir);
    if (!await d.exists()) return [];
    final out = <InstalledVersion>[];
    await for (final e in d.list()) {
      if (e is! Directory) continue;
      final id = p.basename(e.path);
      if (!await File(versionJson(id)).exists()) continue;
      try {
        final v = await load(id);
        out.add(InstalledVersion(id, v, null));
      } catch (err) {
        out.add(InstalledVersion(id, null, err));
      }
    }
    out.sort((a, b) => (b.version?.releaseTime ?? DateTime(0)).compareTo(a.version?.releaseTime ?? DateTime(0)));
    return out;
  }

  Future<void> writeVersionJson(String id, Map<String, dynamic> json) => JsonFile.write(versionJson(id), json);

  /// Renames a version folder and the files inside it.
  Future<void> rename(String from, String to) async {
    if (await Directory(versionDir(to)).exists()) throw CmlException('exists', '版本 $to 已存在');
    final j = await readVersionJson(from);
    j['id'] = to;
    await Directory(versionDir(from)).rename(versionDir(to));
    for (final ext in ['json', 'jar']) {
      final f = File(p.join(versionDir(to), '$from.$ext'));
      if (await f.exists()) await f.rename(p.join(versionDir(to), '$to.$ext'));
    }
    await writeVersionJson(to, j);
  }

  Future<void> delete(String id) async {
    final d = Directory(versionDir(id));
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Ensures `launcher_profiles.json` exists (Forge/OptiFine installers require it).
  Future<void> ensureProfiles() async {
    final f = File(p.join(root, 'launcher_profiles.json'));
    if (await f.exists()) return;
    await JsonFile.write(f.path, {
      'profiles': {
        'CML': {'name': 'CML', 'type': 'custom', 'lastVersionId': 'latest-release'}
      },
      'selectedProfile': 'CML',
      'clientToken': '00000000000000000000000000000000',
      'authenticationDatabase': {},
      'launcherVersion': {'name': 'CML', 'format': 21},
    });
  }
}

class InstalledVersion {
  final String id;
  final GameVersion? version;
  final Object? error;
  InstalledVersion(this.id, this.version, this.error);
  bool get broken => version == null;
}
