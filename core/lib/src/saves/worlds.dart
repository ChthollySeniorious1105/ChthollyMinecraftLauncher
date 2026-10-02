import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../bedrock/store_games.dart';
import '../common/errors.dart';
import '../common/os.dart';
import '../nbt/nbt.dart';

enum Edition { java, bedrock }

/// A Java or Bedrock world on disk.
class WorldInfo {
  final Edition edition;
  final String path;
  final String name;
  final DateTime lastPlayed;
  final String? version; // e.g. "1.21.4" (Java) / "1.21.50" (Bedrock lastOpenedWithVersion)
  final int? dataVersion; // Java DataVersion / Bedrock StorageVersion
  final int gameMode; // 0 survival, 1 creative, 2 adventure, 3 spectator
  final bool hardcore;
  final bool cheats;
  final int? seed;
  final File? icon;

  /// Where the world lives (instance name or Bedrock root label).
  final String location;

  WorldInfo({
    required this.edition,
    required this.path,
    required this.name,
    required this.lastPlayed,
    required this.version,
    required this.dataVersion,
    required this.gameMode,
    required this.hardcore,
    required this.cheats,
    required this.seed,
    required this.icon,
    required this.location,
  });

  String get folderName => p.basename(path);
  String get gameModeLabel => hardcore ? '极限' : switch (gameMode) { 1 => '创造', 2 => '冒险', 3 => '旁观', _ => '生存' };
}

abstract class Worlds {
  // ---------------- listing ----------------

  static Future<List<WorldInfo>> listJava(String savesDir, {String location = ''}) async {
    final d = Directory(savesDir);
    if (!await d.exists()) return [];
    final out = <WorldInfo>[];
    await for (final e in d.list()) {
      if (e is! Directory) continue;
      final w = await readJava(e.path, location: location);
      if (w != null) out.add(w);
    }
    out.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return out;
  }

  static Future<WorldInfo?> readJava(String dir, {String location = ''}) async {
    final f = File(p.join(dir, 'level.dat'));
    if (!await f.exists()) return null;
    try {
      final root = Nbt.decodeAuto(await f.readAsBytes()).tag;
      final data = root.getCompound('Data') ?? root;
      final icon = File(p.join(dir, 'icon.png'));
      final wgs = data.getCompound('WorldGenSettings');
      return WorldInfo(
        edition: Edition.java,
        path: dir,
        name: data.getString('LevelName') ?? p.basename(dir),
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(data.getInt('LastPlayed') ?? 0),
        version: (data.at('Version.Name') as StringTag?)?.value,
        dataVersion: data.getInt('DataVersion'),
        gameMode: data.getInt('GameType') ?? 0,
        hardcore: (data.getInt('hardcore') ?? 0) != 0,
        cheats: (data.getInt('allowCommands') ?? 0) != 0,
        seed: wgs?.getInt('seed') ?? data.getInt('RandomSeed'),
        icon: await icon.exists() ? icon : null,
        location: location,
      );
    } catch (_) {
      return WorldInfo(
          edition: Edition.java,
          path: dir,
          name: '${p.basename(dir)}（level.dat 损坏）',
          lastPlayed: DateTime(2000),
          version: null,
          dataVersion: null,
          gameMode: 0,
          hardcore: false,
          cheats: false,
          seed: null,
          icon: null,
          location: location);
    }
  }

  static Future<List<WorldInfo>> listBedrock() async {
    final out = <WorldInfo>[];
    for (final r in BedrockPaths.roots()) {
      final d = Directory(r.worlds);
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e is! Directory) continue;
        final w = await readBedrock(e.path, location: r.label);
        if (w != null) out.add(w);
      }
    }
    out.sort((a, b) => b.lastPlayed.compareTo(a.lastPlayed));
    return out;
  }

  static Future<WorldInfo?> readBedrock(String dir, {String location = ''}) async {
    final f = File(p.join(dir, 'level.dat'));
    if (!await f.exists()) return null;
    String name = p.basename(dir);
    final nameFile = File(p.join(dir, 'levelname.txt'));
    if (await nameFile.exists()) name = (await nameFile.readAsString()).trim();
    try {
      final (storage, root) = Nbt.decodeBedrockLevelDat(await f.readAsBytes());
      final t = root.tag;
      final ver = t.getList('lastOpenedWithVersion');
      final icon = File(p.join(dir, 'world_icon.jpeg'));
      return WorldInfo(
        edition: Edition.bedrock,
        path: dir,
        name: t.getString('LevelName') ?? name,
        lastPlayed: DateTime.fromMillisecondsSinceEpoch((t.getInt('LastPlayed') ?? 0) * 1000),
        version: ver?.value.take(4).map((e) => e.plain).join('.'),
        dataVersion: storage,
        gameMode: t.getInt('GameType') ?? 0,
        hardcore: (t.getInt('IsHardcore') ?? 0) != 0,
        cheats: (t.getInt('commandsEnabled') ?? 0) != 0,
        seed: t.getInt('RandomSeed'),
        icon: await icon.exists() ? icon : null,
        location: location,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------- edits ----------------

  /// Renames the in-game world name (folder stays).
  static Future<void> rename(WorldInfo w, String newName) async {
    await backup(w);
    final f = File(p.join(w.path, 'level.dat'));
    if (w.edition == Edition.java) {
      final raw = await f.readAsBytes();
      final comp = Nbt.detect(raw);
      final root = Nbt.decode(Nbt.decompress(raw));
      (root.tag.getCompound('Data') ?? root.tag)['LevelName'] = StringTag(newName);
      await f.writeAsBytes(Nbt.compress(Nbt.encode(root.tag, name: root.name), comp == NbtCompression.none ? NbtCompression.gzip : comp));
    } else {
      final (storage, root) = Nbt.decodeBedrockLevelDat(await f.readAsBytes());
      root.tag['LevelName'] = StringTag(newName);
      await f.writeAsBytes(Nbt.encodeBedrockLevelDat(storage, root));
      await File(p.join(w.path, 'levelname.txt')).writeAsString(newName);
    }
  }

  /// Sets game mode / cheats in level.dat.
  static Future<void> setOptions(WorldInfo w, {int? gameMode, bool? cheats}) async {
    await backup(w);
    final f = File(p.join(w.path, 'level.dat'));
    if (w.edition == Edition.java) {
      final raw = await f.readAsBytes();
      final comp = Nbt.detect(raw);
      final root = Nbt.decode(Nbt.decompress(raw));
      final d = root.tag.getCompound('Data') ?? root.tag;
      if (gameMode != null) d['GameType'] = IntTag(gameMode);
      if (cheats != null) d['allowCommands'] = ByteTag(cheats ? 1 : 0);
      await f.writeAsBytes(Nbt.compress(Nbt.encode(root.tag, name: root.name), comp == NbtCompression.none ? NbtCompression.gzip : comp));
    } else {
      final (storage, root) = Nbt.decodeBedrockLevelDat(await f.readAsBytes());
      if (gameMode != null) root.tag['GameType'] = IntTag(gameMode);
      if (cheats != null) root.tag['commandsEnabled'] = ByteTag(cheats ? 1 : 0);
      await f.writeAsBytes(Nbt.encodeBedrockLevelDat(storage, root));
    }
  }

  // ---------------- backup / import / export ----------------

  static String get backupDir => p.join(Os.cmlHome, 'backups', 'worlds');

  /// Zips the world into the CML backup folder. Returns the zip path.
  static Future<String> backup(WorldInfo w) async {
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final out = p.join(backupDir, '${w.edition.name}-${_safe(w.name)}-$stamp.zip');
    await zipDir(w.path, out);
    return out;
  }

  /// Export: Java → .zip, Bedrock → .mcworld (same zip layout, world files at the root).
  static Future<String> export(WorldInfo w, String targetDir) async {
    final ext = w.edition == Edition.bedrock ? 'mcworld' : 'zip';
    final out = p.join(targetDir, '${_safe(w.name)}.$ext');
    await zipDir(w.path, out, includeFolder: w.edition == Edition.java);
    return out;
  }

  /// Imports a .zip / .mcworld into [destParent] (Java saves dir or Bedrock minecraftWorlds). Returns new world dir.
  static Future<String> import(String archive, String destParent) async {
    final input = InputFileStream(archive);
    try {
      final z = ZipDecoder().decodeStream(input);
      // locate level.dat to find the world root inside the archive
      final level = z.files.where((f) => f.isFile && p.posix.basename(f.name) == 'level.dat').toList()
        ..sort((a, b) => a.name.length.compareTo(b.name.length));
      if (level.isEmpty) throw const CmlException('not_world', '压缩包中没有找到存档（缺少 level.dat）');
      final prefix = p.posix.dirname(level.first.name) == '.' ? '' : '${p.posix.dirname(level.first.name)}/';
      var name = prefix.isEmpty ? p.basenameWithoutExtension(archive) : p.posix.basename(prefix.substring(0, prefix.length - 1));
      var dest = p.join(destParent, _safe(name));
      for (var i = 2; await Directory(dest).exists(); i++) {
        dest = p.join(destParent, '${_safe(name)} ($i)');
      }
      for (final f in z.files) {
        if (!f.isFile || !f.name.startsWith(prefix)) continue;
        final rel = f.name.substring(prefix.length);
        if (rel.isEmpty || rel.split('/').contains('..')) continue;
        final o = File(p.join(dest, rel));
        await o.parent.create(recursive: true);
        await o.writeAsBytes(f.readBytes()!);
      }
      return dest;
    } finally {
      await input.close();
    }
  }

  static Future<void> delete(WorldInfo w, {bool backupFirst = true}) async {
    if (backupFirst) await backup(w);
    await Directory(w.path).delete(recursive: true);
  }

  static Future<String> copy(WorldInfo w, String destParent) async {
    var dest = p.join(destParent, w.folderName);
    for (var i = 2; await Directory(dest).exists(); i++) {
      dest = p.join(destParent, '${w.folderName} ($i)');
    }
    await copyDir(w.path, dest);
    return dest;
  }

  static Future<void> zipDir(String dir, String out, {bool includeFolder = false}) async {
    await File(out).parent.create(recursive: true);
    final enc = ZipFileEncoder()..create(out);
    try {
      final base = includeFolder ? p.dirname(dir) : dir;
      await for (final e in Directory(dir).list(recursive: true)) {
        if (e is! File) continue;
        if (p.basename(e.path) == 'session.lock') continue; // locked while the game runs
        await enc.addFile(e, p.relative(e.path, from: base).replaceAll('\\', '/'));
      }
    } finally {
      await enc.close();
    }
  }

  static Future<void> copyDir(String from, String to) async {
    await Directory(to).create(recursive: true);
    await for (final e in Directory(from).list(recursive: true)) {
      final rel = p.relative(e.path, from: from);
      if (e is Directory) {
        await Directory(p.join(to, rel)).create(recursive: true);
      } else if (e is File) {
        await File(p.join(to, rel)).parent.create(recursive: true);
        await e.copy(p.join(to, rel));
      }
    }
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim().isEmpty ? 'world' : s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();

  /// Java DataVersion → release name for common versions (for display / Chunker target guess).
  static String? javaVersionForDataVersion(int dv) {
    const table = <int, String>{
      4671: '1.21.11', 4556: '1.21.10', 4440: '1.21.9', 4325: '1.21.6', 4189: '1.21.4', 4082: '1.21.3', 3955: '1.21.1', 3953: '1.21',
      3839: '1.20.6', 3700: '1.20.4', 3578: '1.20.2', 3465: '1.20.1', 3337: '1.19.4', 3120: '1.19.2', 2975: '1.18.2',
      2730: '1.17.1', 2586: '1.16.5', 2230: '1.15.2', 1976: '1.14.4', 1631: '1.13.2', 1343: '1.12.2',
    };
    String? best;
    var bestDv = -1;
    for (final e in table.entries) {
      if (e.key <= dv && e.key > bestDv) {
        bestDv = e.key;
        best = e.value;
      }
    }
    return best;
  }

  static Uint8List? readIcon(WorldInfo w) => w.icon?.readAsBytesSync();
}
