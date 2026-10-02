import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../game/game_dir.dart';
import '../game/installer.dart';
import '../game/loaders.dart';
import '../game/version.dart';
import '../net/downloader.dart';
import 'content_api.dart';
import 'exporter.dart';

/// Installs content files into an instance and imports modpacks.
class ContentInstaller {
  final ContentApi api;
  final Downloader dl;
  final GameInstaller game;
  final LoaderInstaller loaders;
  ContentInstaller(this.api, this.dl, this.game, this.loaders);

  /// Downloads [v]'s primary file into [folder] (e.g. `<instance>/mods`). Returns the saved path.
  Future<String> installFile(ContentVersion v, String folder, {Task? task}) async {
    final f = v.primaryFile;
    final dest = p.join(folder, f.filename);
    final urls = api.fileUrls(f.url);
    await dl.download(DownloadItem(urls.first, dest, sha1: f.sha1, size: f.size, fallbacks: urls.skip(1).toList()), cancel: task?.cancel);
    return dest;
  }

  /// Installs [v] plus required dependencies (Modrinth only; CurseForge deps are resolved by latest compatible file).
  Future<List<String>> installWithDependencies(ContentVersion v, String folder, {String? gameVersion, String? loader, Task? task}) async {
    final done = <String>{};
    final out = <String>[];
    Future<void> go(ContentVersion ver) async {
      if (!done.add(ver.projectId)) return;
      out.add(await installFile(ver, folder, task: task));
      for (final d in ver.dependencies.where((d) => d.required)) {
        if (done.contains(d.projectId)) continue;
        ContentVersion? dep;
        if (ver.platform == ContentPlatform.modrinth) {
          dep = d.versionId != null
              ? await api.mrVersion(d.versionId!)
              : (await api.mrVersions(d.projectId, gameVersion: gameVersion, loader: loader)).firstOrNull;
        } else {
          final list = await api.versions(_stub(d.projectId), gameVersion: gameVersion, loader: loader);
          dep = list.firstOrNull;
        }
        if (dep != null) await go(dep);
      }
    }

    await go(v);
    return out;
  }

  ContentProject _stub(String id) => ContentProject(
      platform: ContentPlatform.curseforge,
      id: id,
      slug: id,
      title: id,
      description: '',
      author: '',
      iconUrl: null,
      downloads: 0,
      categories: const [],
      gameVersions: const [],
      loaders: const [],
      updated: null,
      type: ContentType.mod);

  /// Imports a `.mrpack` or CurseForge `.zip` modpack as a new isolated version [name].
  Future<String> importModpack(GameDir dir, String file, String name, {required String javaPath, Task? task}) async {
    final input = InputFileStream(file);
    try {
      final zip = ZipDecoder().decodeStream(input);
      if (zip.findFile('modrinth.index.json') != null) return await _mrpack(dir, zip, name, javaPath, task);
      if (zip.findFile('manifest.json') != null) return await _curse(dir, zip, name, javaPath, task);
      if (zip.findFile('cmlpack.json') != null) {
        await input.close();
        return await InstanceExporter.importFull(dir, file, name, task: task);
      }
      throw const CmlException('modpack_format', '无法识别的整合包格式（支持 Modrinth .mrpack、CurseForge .zip 与 CML .cmlpack）');
    } finally {
      await input.close();
    }
  }

  Future<String> _prepareBase(GameDir dir, String mc, ModLoader? loader, String? loaderVersion, String name, String javaPath, Task? task) async {
    task?.update(detail: '安装 Minecraft $mc', progress: -1);
    final m = await game.manifest();
    final entry = m.find(mc) ?? (throw CmlException('mc_missing', '找不到 Minecraft $mc'));
    if (!await File(dir.versionJson(mc)).exists()) await game.installVanillaJson(dir, entry);
    await game.completeFiles(dir, mc, task: task);
    if (loader == null) {
      if (name != mc) {
        await game.installVanillaJson(dir, entry, id: name);
        await File(dir.versionJar(mc)).copy(dir.versionJar(name));
      }
      return name;
    }
    task?.update(detail: '安装 ${loader.label} $loaderVersion', progress: -1);
    final id = await loaders.install(dir, LoaderVersion(loader, mc, loaderVersion!), javaPath: javaPath, id: name, task: task);
    await game.completeFiles(dir, id, task: task);
    return id;
  }

  Future<String> _mrpack(GameDir dir, Archive zip, String name, String javaPath, Task? task) async {
    final idx = jsonDecode(utf8.decode(zip.findFile('modrinth.index.json')!.readBytes()!)) as Map;
    final deps = (idx['dependencies'] as Map).cast<String, dynamic>();
    final mc = '${deps['minecraft']}';
    ModLoader? loader;
    String? lv;
    for (final (k, l) in [('fabric-loader', ModLoader.fabric), ('quilt-loader', ModLoader.quilt), ('forge', ModLoader.forge), ('neoforge', ModLoader.neoforge)]) {
      if (deps[k] != null) {
        loader = l;
        lv = '${deps[k]}';
      }
    }
    final id = await _prepareBase(dir, mc, loader, lv, name, javaPath, task);
    final gameDir = dir.versionDir(id);

    final items = <DownloadItem>[];
    for (final f in idx['files'] as List) {
      final env = f['env'] as Map?;
      if (env != null && env['client'] == 'unsupported') continue;
      final rel = '${f['path']}';
      if (rel.contains('..') || p.isAbsolute(rel)) continue; // path traversal guard
      final urls = [for (final u in f['downloads'] as List) ...api.fileUrls('$u')];
      items.add(DownloadItem(urls.first, p.join(gameDir, rel), sha1: (f['hashes'] as Map?)?['sha1'] as String?, size: (f['fileSize'] as num?)?.toInt() ?? 0, fallbacks: urls.skip(1).toList()));
    }
    task?.update(detail: '下载整合包文件', progress: 0);
    await dl.downloadAll(items, cancel: task?.cancel, onProgress: (d, t, _) => task?.update(progress: d / t, detail: '下载整合包文件 $d / $t'));
    await _extractOverrides(zip, ['overrides/', 'client-overrides/'], gameDir);
    return id;
  }

  Future<String> _curse(GameDir dir, Archive zip, String name, String javaPath, Task? task) async {
    final man = jsonDecode(utf8.decode(zip.findFile('manifest.json')!.readBytes()!)) as Map;
    final mcInfo = man['minecraft'] as Map;
    final mc = '${mcInfo['version']}';
    ModLoader? loader;
    String? lv;
    final primary = (mcInfo['modLoaders'] as List? ?? []).firstWhere((l) => l['primary'] == true, orElse: () => (mcInfo['modLoaders'] as List?)?.firstOrNull);
    if (primary != null) {
      final s = '${primary['id']}'; // forge-47.2.0 / fabric-0.15.7 / neoforge-21.1.65
      final dash = s.indexOf('-');
      final kind = s.substring(0, dash);
      lv = s.substring(dash + 1);
      loader = switch (kind) { 'forge' => ModLoader.forge, 'fabric' => ModLoader.fabric, 'quilt' => ModLoader.quilt, 'neoforge' => ModLoader.neoforge, _ => null };
    }
    final id = await _prepareBase(dir, mc, loader, lv, name, javaPath, task);
    final gameDir = dir.versionDir(id);

    final ids = [for (final f in man['files'] as List) (f['fileID'] as num).toInt()];
    task?.update(detail: '解析 ${ids.length} 个 Mod', progress: -1);
    final files = <ContentVersion>[];
    for (var i = 0; i < ids.length; i += 100) {
      files.addAll(await api.cfFiles(ids.sublist(i, (i + 100).clamp(0, ids.length))));
    }
    final items = <DownloadItem>[];
    for (final v in files) {
      final f = v.primaryFile;
      final folder = f.filename.endsWith('.zip') && !f.filename.contains('mod') ? 'resourcepacks' : 'mods';
      final urls = api.fileUrls(f.url);
      items.add(DownloadItem(urls.first, p.join(gameDir, folder, f.filename), sha1: f.sha1, size: f.size, fallbacks: urls.skip(1).toList()));
    }
    await dl.downloadAll(items, cancel: task?.cancel, onProgress: (d, t, _) => task?.update(progress: d / t, detail: '下载整合包文件 $d / $t'));
    await _extractOverrides(zip, ['${man['overrides'] ?? 'overrides'}/'], gameDir);
    return id;
  }

  static Future<void> _extractOverrides(Archive zip, List<String> prefixes, String dest) async {
    for (final f in zip.files) {
      if (!f.isFile) continue;
      for (final pre in prefixes) {
        if (!f.name.startsWith(pre)) continue;
        final rel = f.name.substring(pre.length);
        if (rel.isEmpty || rel.contains('..')) continue;
        final out = File(p.join(dest, rel));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.readBytes()!);
      }
    }
  }
}

/// A file in an instance's mods/resourcepacks/shaderpacks folder.
class LocalContent {
  final File file;
  LocalContent(this.file);
  String get name => p.basename(file.path);
  bool get enabled => !name.endsWith('.disabled');
  String get displayName => enabled ? name : name.substring(0, name.length - '.disabled'.length);

  Future<LocalContent> setEnabled(bool on) async {
    if (on == enabled) return this;
    final target = on ? p.join(p.dirname(file.path), displayName) : '${file.path}.disabled';
    return LocalContent(await file.rename(target));
  }

  /// Reads mod metadata (fabric.mod.json / quilt.mod.json / mods.toml / neoforge.mods.toml / mcmod.info).
  Future<ModMeta?> readMeta() async {
    try {
      final input = InputFileStream(file.path);
      try {
        final z = ZipDecoder().decodeStream(input);
        String? txt(String n) {
          final f = z.findFile(n);
          return f == null ? null : utf8.decode(f.readBytes()!, allowMalformed: true);
        }

        final fabric = txt('fabric.mod.json') ?? txt('quilt.mod.json');
        if (fabric != null) {
          final j = jsonDecode(fabric) as Map;
          final q = j['quilt_loader'] as Map?;
          final meta = (q?['metadata'] as Map?) ?? j;
          return ModMeta('${q?['id'] ?? j['id']}', '${meta['name'] ?? j['id']}', '${q?['version'] ?? j['version']}', '${meta['description'] ?? ''}');
        }
        final toml = txt('META-INF/neoforge.mods.toml') ?? txt('META-INF/mods.toml');
        if (toml != null) {
          String? field(String k) => RegExp('^\\s*$k\\s*=\\s*["\']([^"\']*)', multiLine: true).firstMatch(toml)?.group(1);
          return ModMeta(field('modId') ?? '', field('displayName') ?? field('modId') ?? displayName, field('version') ?? '', field('description') ?? '');
        }
        final info = txt('mcmod.info');
        if (info != null) {
          final j = jsonDecode(info);
          final m = (j is List ? j.firstOrNull : (j['modList'] as List?)?.firstOrNull) as Map?;
          if (m != null) return ModMeta('${m['modid']}', '${m['name']}', '${m['version']}', '${m['description'] ?? ''}');
        }
      } finally {
        await input.close();
      }
    } catch (_) {}
    return null;
  }

  static Future<List<LocalContent>> list(String folder, {List<String> exts = const ['.jar', '.zip']}) async {
    final d = Directory(folder);
    if (!await d.exists()) return [];
    final out = <LocalContent>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final n = e.path.toLowerCase().replaceAll('.disabled', '');
      if (exts.any(n.endsWith)) out.add(LocalContent(e));
    }
    out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    return out;
  }
}

class ModMeta {
  final String id, name, version, description;
  ModMeta(this.id, this.name, this.version, this.description);
}
