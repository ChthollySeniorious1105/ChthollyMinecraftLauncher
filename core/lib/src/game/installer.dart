import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import '../common/task.dart';
import '../net/downloader.dart';
import '../net/http.dart';
import '../net/source.dart';
import 'game_dir.dart';
import 'version.dart';

class ManifestEntry {
  final String id;
  final String type; // release, snapshot, old_beta, old_alpha
  final String url;
  final DateTime releaseTime;
  final String? sha1;
  ManifestEntry(this.id, this.type, this.url, this.releaseTime, this.sha1);

  String get typeLabel => switch (type) {
        'release' => '正式版',
        'snapshot' => '快照版',
        'old_beta' => '远古 Beta',
        'old_alpha' => '远古 Alpha',
        _ => type,
      };

  /// April-fools and other special snapshots, by release date heuristic.
  bool get isAprilFools => releaseTime.month == 4 && releaseTime.day == 1 && type == 'snapshot';
}

class VersionManifest {
  final String latestRelease;
  final String latestSnapshot;
  final List<ManifestEntry> versions;
  VersionManifest(this.latestRelease, this.latestSnapshot, this.versions);

  ManifestEntry? find(String id) {
    for (final v in versions) {
      if (v.id == id) return v;
    }
    return null;
  }
}

/// Installs vanilla versions and repairs files (client, libraries, natives, assets, logging config).
class GameInstaller {
  final Http http;
  final Downloader dl;
  GameInstaller(this.http, this.dl);

  VersionManifest? _manifest;

  static String get _manifestCache => p.join(Os.cmlHome, 'cache', 'version_manifest.json');

  static VersionManifest _parseManifest(Map j) {
    final latest = j['latest'] as Map;
    return VersionManifest(
      '${latest['release']}',
      '${latest['snapshot']}',
      [
        for (final v in j['versions'] as List)
          ManifestEntry('${v['id']}', '${v['type']}', '${v['url']}', DateTime.parse('${v['releaseTime']}'), v['sha1'] as String?)
      ],
    );
  }

  /// Last downloaded manifest from disk (instant), or null.
  Future<VersionManifest?> cachedManifest() async {
    if (_manifest != null) return _manifest;
    try {
      final j = await JsonFile.read(_manifestCache);
      return j is Map ? _parseManifest(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<VersionManifest> manifest({bool refresh = false}) async {
    if (_manifest != null && !refresh) return _manifest!;
    final urls = Mirrors.candidates(Mirrors.manifestOfficial, dl.source);
    Object? err;
    for (final u in urls) {
      try {
        final j = await http.getJson(Uri.parse(u)) as Map;
        final m = _parseManifest(j);
        await JsonFile.write(_manifestCache, j, pretty: false);
        return _manifest = m;
      } catch (e) {
        err = e;
      }
    }
    throw CmlException('manifest', '无法获取版本列表，请检查网络或切换下载源', err);
  }

  /// Downloads a vanilla version JSON into [dir] under [id] (defaults to the MC id).
  Future<void> installVanillaJson(GameDir dir, ManifestEntry v, {String? id}) async {
    id ??= v.id;
    final path = dir.versionJson(id);
    await dl.download(DownloadItem(v.url, path, sha1: v.sha1));
    if (id != v.id) {
      final j = await dir.readVersionJson(id);
      j['id'] = id;
      await dir.writeVersionJson(id, j);
    }
  }

  /// Full install / repair of version [id] (JSON must exist). Reports progress to [task].
  Future<void> completeFiles(GameDir dir, String id, {Task? task}) async {
    final v = await dir.load(id);
    final items = <DownloadItem>[];

    // client jar
    final jarId = v.jar;
    if (v.client != null) {
      items.add(DownloadItem(v.client!.url, dir.versionJar(jarId == id ? id : jarId), sha1: v.client!.sha1, size: v.client!.size));
      if (jarId != id && !await File(dir.versionJar(id)).exists()) {
        // loader versions without a jar of their own launch the parent's jar
      }
    }

    // libraries
    for (final l in v.libraries) {
      if (!l.applies) continue;
      if (l.artifact != null || l.classifiers.isEmpty) {
        final url = l.url;
        if (url.isNotEmpty) {
          items.add(DownloadItem(url, dir.library(l.path), sha1: l.artifact?.sha1, size: l.artifact?.size ?? 0, fallbacks: _mavenFallbacks(l)));
        }
      }
      final nc = l.nativeClassifier;
      if (nc != null) {
        final f = l.classifiers[nc];
        final path = f?.path ?? l.name.withClassifier(nc).path;
        final url = f?.url ?? '${l.repo ?? 'https://libraries.minecraft.net/'}${l.name.withClassifier(nc).path}';
        items.add(DownloadItem(url, dir.library(path), sha1: f?.sha1, size: f?.size ?? 0));
      }
    }

    // logging config
    if (v.loggingFile != null && v.loggingId != null) {
      items.add(DownloadItem(v.loggingFile!.url, p.join(dir.assetsDir, 'log_configs', v.loggingId!), sha1: v.loggingFile!.sha1));
    }

    // asset index → objects
    if (v.assetIndex != null) {
      final ai = v.assetIndex!;
      final idxPath = p.join(dir.assetsDir, 'indexes', '${ai.id}.json');
      task?.update(detail: '下载资源索引', progress: -1);
      await dl.download(DownloadItem(ai.file.url, idxPath, sha1: ai.file.sha1));
      final idx = jsonDecode(await File(idxPath).readAsString()) as Map;
      final objects = (idx['objects'] as Map?) ?? {};
      final virtual = idx['virtual'] == true || idx['map_to_resources'] == true;
      for (final e in objects.entries) {
        final hash = '${(e.value as Map)['hash']}';
        final size = ((e.value as Map)['size'] as num).toInt();
        final rel = '${hash.substring(0, 2)}/$hash';
        items.add(DownloadItem('https://resources.download.minecraft.net/$rel', p.join(dir.assetsDir, 'objects', rel), sha1: hash, size: size));
      }
      await _download(items, task);
      if (virtual) await _copyVirtualAssets(dir, objects, idx['map_to_resources'] == true ? p.join(dir.versionDir(id), 'resources') : p.join(dir.assetsDir, 'virtual', ai.id));
    } else {
      await _download(items, task);
    }
  }

  Future<void> _download(List<DownloadItem> items, Task? task) async {
    final sw = Stopwatch()..start();
    var lastBytes = 0;
    var lastMs = 0;
    await dl.downloadAll(items, cancel: task?.cancel, onProgress: (done, total, bytes) {
      final ms = sw.elapsedMilliseconds;
      int? speed;
      if (ms - lastMs > 500) {
        speed = ((bytes - lastBytes) * 1000 / (ms - lastMs)).round();
        lastBytes = bytes;
        lastMs = ms;
      }
      task?.update(progress: total == 0 ? 1 : done / total, detail: '下载文件 $done / $total', speed: speed);
    });
  }

  List<String> _mavenFallbacks(Library l) {
    if (l.artifact != null && l.artifact!.url.isNotEmpty) return const [];
    return [
      'https://maven.minecraftforge.net/${l.name.path}',
      'https://maven.fabricmc.net/${l.name.path}',
      'https://maven.neoforged.net/releases/${l.name.path}',
      'https://repo1.maven.org/maven2/${l.name.path}',
    ];
  }

  Future<void> _copyVirtualAssets(GameDir dir, Map objects, String target) async {
    for (final e in objects.entries) {
      final hash = '${(e.value as Map)['hash']}';
      final dest = File(p.join(target, '${e.key}'));
      if (await dest.exists()) continue;
      await dest.parent.create(recursive: true);
      await File(p.join(dir.assetsDir, 'objects', hash.substring(0, 2), hash)).copy(dest.path);
    }
  }

  /// Extracts old-style native libraries into the version natives folder.
  static Future<String> extractNatives(GameDir dir, String id, GameVersion v) async {
    final out = Directory(dir.nativesDir(id));
    await out.create(recursive: true);
    for (final l in v.libraries) {
      if (!l.applies) continue;
      String? path;
      final nc = l.nativeClassifier;
      if (nc != null) {
        path = dir.library(l.classifiers[nc]?.path ?? l.name.withClassifier(nc).path);
      } else if (l.isNativeArtifact && (l.name.classifier!.contains('windows'))) {
        path = dir.library(l.path);
      }
      if (path == null || !await File(path).exists()) continue;
      final input = InputFileStream(path);
      try {
        final zip = ZipDecoder().decodeStream(input);
        for (final f in zip.files) {
          if (!f.isFile) continue;
          final name = f.name;
          if (name.startsWith('META-INF/')) continue;
          final lower = name.toLowerCase();
          if (!(lower.endsWith('.dll') || lower.endsWith('.so') || lower.endsWith('.dylib') || lower.endsWith('.jnilib'))) continue;
          final dest = File(p.join(out.path, p.basename(name)));
          if (await dest.exists() && await dest.length() == f.size) continue;
          await dest.writeAsBytes(f.readBytes()!);
        }
      } catch (_) {
        // a broken native jar should not block launch; the game will report the missing library
      } finally {
        await input.close();
      }
    }
    return out.path;
  }
}
