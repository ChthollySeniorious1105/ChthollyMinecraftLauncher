import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../game/game_dir.dart';
import '../game/version.dart';
import '../net/downloader.dart';
import 'content_api.dart';
import 'updater.dart';

enum ExportFormat {
  /// Modrinth `.mrpack`: mods/packs found on Modrinth are referenced by URL, the rest go into overrides.
  modrinth('Modrinth 整合包（.mrpack）', 'mrpack'),

  /// CurseForge `.zip`: files found on CurseForge are referenced by project/file id.
  curseforge('CurseForge 整合包（.zip）', 'zip'),

  /// Complete copy: version JSON + jar + all game files. Re-import works offline and with any loader.
  full('完整实例（.cmlpack，包含全部文件）', 'cmlpack');

  final String label;
  final String ext;
  const ExportFormat(this.label, this.ext);
}

/// Folders of an instance and whether they are exported by default.
class ExportEntry {
  final String path; // relative to the game dir
  final int size;
  final int files;
  bool selected;
  ExportEntry(this.path, this.size, this.files, this.selected);
}

class ExportResult {
  final String output;
  final int referenced; // files linked to a platform
  final int bundled; // files stored inside the pack
  ExportResult(this.output, this.referenced, this.bundled);
}

/// Exports an installed version as a modpack / full instance, and imports `.cmlpack`.
class InstanceExporter {
  final ContentApi api;
  InstanceExporter(this.api);

  static const _defaultOn = {'mods', 'config', 'resourcepacks', 'shaderpacks', 'kubejs', 'scripts', 'defaultconfigs', 'options.txt', 'servers.dat', 'optionsshaders.txt'};
  static const _alwaysOff = {'logs', 'crash-reports', 'screenshots', '.cml-old', 'natives-windows-x86_64', 'cml.json', '.fabric', '.mixin.out', 'downloads'};

  /// Top-level entries of the instance's game dir for the export picker.
  static Future<List<ExportEntry>> scan(String gameDir, String versionId) async {
    final d = Directory(gameDir);
    if (!await d.exists()) return [];
    final out = <ExportEntry>[];
    await for (final e in d.list()) {
      final name = p.basename(e.path);
      if (_alwaysOff.contains(name) || name == '$versionId.json' || name == '$versionId.jar' || name.endsWith('.log')) continue;
      var size = 0, files = 0;
      if (e is File) {
        size = await e.length();
        files = 1;
      } else if (e is Directory) {
        await for (final f in e.list(recursive: true)) {
          if (f is File) {
            size += await f.length();
            files++;
          }
        }
      }
      out.add(ExportEntry(name, size, files, _defaultOn.contains(name)));
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return out;
  }

  Future<ExportResult> export({
    required GameDir dir,
    required String versionId,
    required String gameDir,
    required List<String> include,
    required ExportFormat format,
    required String output,
    required String name,
    String version = '1.0.0',
    String summary = '',
    Task? task,
  }) async {
    final v = await dir.load(versionId);
    final files = <String>[];
    for (final inc in include) {
      final path = p.join(gameDir, inc);
      if (await File(path).exists()) {
        files.add(inc);
      } else if (await Directory(path).exists()) {
        await for (final f in Directory(path).list(recursive: true)) {
          if (f is File) files.add(p.relative(f.path, from: gameDir).replaceAll('\\', '/'));
        }
      }
    }
    files.sort();
    if (format == ExportFormat.full) return _full(dir, versionId, gameDir, files, output, task);

    // resolve platform references for jars/zips in content folders
    final linkable = [for (final f in files) if (RegExp(r'^(mods|resourcepacks|shaderpacks)/[^/]+\.(jar|zip)$').hasMatch(f)) f];
    final mr = <String, ContentVersion>{};
    final cf = <String, ContentVersion>{};
    if (linkable.isNotEmpty) {
      task?.update(detail: '在${format == ExportFormat.modrinth ? ' Modrinth' : ' CurseForge'} 上查找文件', progress: -1);
      final bySha = <String, String>{};
      for (final f in linkable) {
        bySha[await Downloader.fileSha1(File(p.join(gameDir, f)))] = f;
      }
      if (format == ExportFormat.modrinth) {
        try {
          final r = await api.mrVersionsByHash(bySha.keys.toList());
          r.forEach((sha, ver) => mr[bySha[sha]!] = ver);
        } catch (_) {}
      } else {
        final byFp = <int, String>{};
        for (final f in linkable) {
          byFp[curseforgeFingerprint(await File(p.join(gameDir, f)).readAsBytes())] = f;
        }
        try {
          for (final (fp, ver) in await api.cfMatchFingerprints(byFp.keys.toList())) {
            final f = byFp[fp];
            if (f != null) cf[f] = ver;
          }
        } catch (_) {}
      }
    }

    final loaderDeps = _loaderDeps(v);
    final enc = ZipFileEncoder()..create(output);
    var bundled = 0;
    try {
      if (format == ExportFormat.modrinth) {
        final entries = <Map<String, Object?>>[];
        for (final f in files) {
          final ver = mr[f];
          if (ver == null) continue;
          final file = ver.files.firstWhere((x) => x.filename == p.basename(f), orElse: () => ver.primaryFile);
          final bytes = await File(p.join(gameDir, f)).readAsBytes();
          entries.add({
            'path': f,
            'hashes': {'sha1': file.sha1 ?? await Downloader.fileSha1(File(p.join(gameDir, f))), 'sha512': await _sha512(bytes)},
            'env': {'client': 'required', 'server': 'optional'},
            'downloads': [file.url],
            'fileSize': bytes.length,
          });
        }
        enc.addArchiveFile(ArchiveFile.bytes(
            'modrinth.index.json',
            utf8.encode(const JsonEncoder.withIndent('  ').convert({
              'formatVersion': 1,
              'game': 'minecraft',
              'versionId': version,
              'name': name,
              if (summary.isNotEmpty) 'summary': summary,
              'files': entries,
              'dependencies': {'minecraft': v.baseVersion, ...loaderDeps.$1},
            }))));
      } else {
        final mods = [
          for (final f in files)
            if (cf[f] != null) {'projectID': int.parse(cf[f]!.projectId), 'fileID': int.parse(cf[f]!.id), 'required': true}
        ];
        enc.addArchiveFile(ArchiveFile.bytes(
            'manifest.json',
            utf8.encode(const JsonEncoder.withIndent('  ').convert({
              'minecraft': {
                'version': v.baseVersion,
                'modLoaders': [if (loaderDeps.$2 != null) {'id': loaderDeps.$2, 'primary': true}],
              },
              'manifestType': 'minecraftModpack',
              'manifestVersion': 1,
              'name': name,
              'version': version,
              'author': '',
              'files': mods,
              'overrides': 'overrides',
            }))));
      }
      final linked = format == ExportFormat.modrinth ? mr : cf;
      for (var i = 0; i < files.length; i++) {
        final f = files[i];
        if (linked.containsKey(f)) continue;
        task?.update(detail: f, progress: i / files.length);
        await enc.addFile(File(p.join(gameDir, f)), 'overrides/$f');
        bundled++;
      }
    } finally {
      await enc.close();
    }
    return ExportResult(output, (format == ExportFormat.modrinth ? mr : cf).length, bundled);
  }

  /// Loader dependency for mrpack (`fabric-loader` → ver) and CurseForge id (`fabric-0.16.5`).
  static (Map<String, String>, String?) _loaderDeps(GameVersion v) {
    for (final l in v.libraries) {
      final k = '${l.name.group}:${l.name.artifact}';
      final ver = l.name.version;
      if (k == 'net.fabricmc:fabric-loader') return ({'fabric-loader': ver}, 'fabric-$ver');
      if (k == 'org.quiltmc:quilt-loader') return ({'quilt-loader': ver}, 'quilt-$ver');
      if (k.startsWith('net.neoforged:neoforge') || k == 'net.neoforged:forge') {
        final nv = ver.split('-').last;
        return ({'neoforge': nv}, 'neoforge-$nv');
      }
      if (k == 'net.minecraftforge:forge' || k == 'net.minecraftforge:fmlloader') {
        final fv = ver.contains('-') ? ver.split('-')[1] : ver;
        return ({'forge': fv}, 'forge-$fv');
      }
    }
    return (const {}, null);
  }

  Future<ExportResult> _full(GameDir dir, String id, String gameDir, List<String> files, String output, Task? task) async {
    final enc = ZipFileEncoder()..create(output);
    try {
      // the whole inheritsFrom chain so the instance can be restored anywhere
      var cur = id;
      final chain = <String>[];
      while (true) {
        chain.add(cur);
        final j = await dir.readVersionJson(cur);
        final parent = j['inheritsFrom'] as String?;
        if (parent == null) break;
        cur = parent;
      }
      for (final vid in chain) {
        await enc.addFile(File(dir.versionJson(vid)), 'versions/$vid/$vid.json');
        if (await File(dir.versionJar(vid)).exists()) await enc.addFile(File(dir.versionJar(vid)), 'versions/$vid/$vid.jar');
      }
      // libraries that are not downloadable (OptiFine patched jars, local forge artifacts)
      final v = await dir.load(id);
      for (final l in v.libraries) {
        final url = l.url;
        final local = File(dir.library(l.path));
        if (await local.exists() && (url.isEmpty || l.name.group.startsWith('optifine') || l.artifact == null && l.repo == null)) {
          await enc.addFile(local, 'libraries/${l.path}');
        }
      }
      enc.addArchiveFile(ArchiveFile.bytes('cmlpack.json', utf8.encode(jsonEncode({'format': 1, 'version': id, 'chain': chain}))));
      for (var i = 0; i < files.length; i++) {
        task?.update(detail: files[i], progress: i / files.length);
        await enc.addFile(File(p.join(gameDir, files[i])), 'game/${files[i]}');
      }
    } finally {
      await enc.close();
    }
    return ExportResult(output, 0, files.length);
  }

  /// Imports a `.cmlpack` into [dir] as [name] (isolated). Returns the version id.
  static Future<String> importFull(GameDir dir, String file, String name, {Task? task}) async {
    final input = InputFileStream(file);
    try {
      final z = ZipDecoder().decodeStream(input);
      final meta = z.findFile('cmlpack.json');
      if (meta == null) throw const CmlException('cmlpack', '不是 CML 实例包');
      final m = jsonDecode(utf8.decode(meta.readBytes()!)) as Map;
      final original = '${m['version']}';
      if (await Directory(dir.versionDir(name)).exists()) throw CmlException('exists', '版本 $name 已存在');
      var n = 0;
      for (final f in z.files) {
        if (!f.isFile || f.name.contains('..')) continue;
        String? target;
        if (f.name.startsWith('versions/')) {
          final parts = f.name.split('/');
          final vid = parts[1];
          if (vid == original) {
            target = dir.versionDir(name) + Platform.pathSeparator + parts.last.replaceFirst(original, name);
          } else {
            target = p.join(dir.root, f.name);
            if (await File(target).exists()) continue; // keep the user's existing base version
          }
        } else if (f.name.startsWith('libraries/')) {
          target = p.join(dir.root, f.name);
          if (await File(target).exists()) continue;
        } else if (f.name.startsWith('game/')) {
          target = p.join(dir.versionDir(name), f.name.substring(5));
        }
        if (target == null) continue;
        await File(target).parent.create(recursive: true);
        await File(target).writeAsBytes(f.readBytes()!);
        task?.update(detail: f.name, progress: ++n / z.files.length);
      }
      final j = await dir.readVersionJson(name);
      j['id'] = name;
      await dir.writeVersionJson(name, j);
      return name;
    } finally {
      await input.close();
    }
  }

  static Future<String> _sha512(Uint8List b) async => crypto.sha512.convert(b).toString();
}
