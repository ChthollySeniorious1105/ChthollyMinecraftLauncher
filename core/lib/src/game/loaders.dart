import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../net/downloader.dart';
import '../net/http.dart';
import '../net/source.dart';
import 'game_dir.dart';
import 'version.dart';

class LoaderVersion {
  final ModLoader loader;
  final String mcVersion;
  final String version;
  final bool stable;
  LoaderVersion(this.loader, this.mcVersion, this.version, {this.stable = true});
  @override
  String toString() => '${loader.label} $version';
}

/// Lists and installs Fabric / Quilt / Forge / NeoForge on top of an installed vanilla version.
class LoaderInstaller {
  final Http http;
  final Downloader dl;
  LoaderInstaller(this.http, this.dl);

  Future<dynamic> _json(String url) async {
    Object? err;
    for (final u in Mirrors.candidates(url, dl.source)) {
      try {
        return await http.getJson(Uri.parse(u));
      } catch (e) {
        err = e;
      }
    }
    throw CmlException('loader_list', '获取加载器版本列表失败', err);
  }

  Future<String> _text(String url) async {
    Object? err;
    for (final u in Mirrors.candidates(url, dl.source)) {
      try {
        return await http.text(Uri.parse(u));
      } catch (e) {
        err = e;
      }
    }
    throw CmlException('loader_list', '获取加载器版本列表失败', err);
  }

  Future<List<LoaderVersion>> list(ModLoader loader, String mc) async {
    switch (loader) {
      case ModLoader.fabric:
        final j = await _json('https://meta.fabricmc.net/v2/versions/loader/$mc') as List;
        return [for (final e in j) LoaderVersion(loader, mc, '${e['loader']['version']}', stable: e['loader']['stable'] == true)];
      case ModLoader.quilt:
        final j = await _json('https://meta.quiltmc.org/v3/versions/loader/$mc') as List;
        return [
          for (final e in j) LoaderVersion(loader, mc, '${e['loader']['version']}', stable: !'${e['loader']['version']}'.contains('-'))
        ];
      case ModLoader.forge:
        final xml = await _text('https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml');
        return [
          for (final v in _mavenVersions(xml))
            if (v.startsWith('$mc-')) LoaderVersion(loader, mc, v.substring(mc.length + 1))
        ].reversed.toList();
      case ModLoader.neoforge:
        if (mc == '1.20.1') {
          final xml = await _text('https://maven.neoforged.net/releases/net/neoforged/forge/maven-metadata.xml');
          return [for (final v in _mavenVersions(xml)) if (v.startsWith('1.20.1-')) LoaderVersion(loader, mc, v)].reversed.toList();
        }
        final xml = await _text('https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml');
        return [
          for (final v in _mavenVersions(xml))
            if (neoForgeMc(v) == mc) LoaderVersion(loader, mc, v, stable: !v.contains('beta') && !v.contains('alpha'))
        ].reversed.toList();
      default:
        throw CmlException('loader_unsupported', '暂不支持自动安装 ${loader.label}');
    }
  }

  /// NeoForge `21.1.65` → `1.21.1`, `21.0.10` → `1.21`; year-based `26.1.0.5` → `26.1`, `26.1.2.3` → `26.1.2`.
  static String neoForgeMc(String v) {
    final parts = v.split(RegExp(r'[.\-+]'));
    if (parts.length < 2) return '';
    final major = int.tryParse(parts[0]) ?? 0;
    if (major >= 25) {
      // four-component versions: mcMajor.mcMinor.mcPatch.build
      final patch = parts.length >= 4 ? parts[2] : '0';
      return patch == '0' ? '${parts[0]}.${parts[1]}' : '${parts[0]}.${parts[1]}.$patch';
    }
    return parts[1] == '0' ? '1.${parts[0]}' : '1.${parts[0]}.${parts[1]}';
  }

  static List<String> _mavenVersions(String xml) =>
      [for (final m in RegExp(r'<version>([^<]+)</version>').allMatches(xml)) m.group(1)!];

  /// Default instance name like `1.21.1-Fabric 0.16.5`.
  static String defaultName(LoaderVersion v) => '${v.mcVersion}-${v.loader.label} ${v.version}';

  /// Installs [v]. The vanilla version [v.mcVersion] must be installed in [dir] first.
  /// Returns the new version id.
  Future<String> install(GameDir dir, LoaderVersion v, {required String javaPath, String? id, Task? task}) async {
    id ??= defaultName(v);
    switch (v.loader) {
      case ModLoader.fabric:
        await _installProfile(dir, id, 'https://meta.fabricmc.net/v2/versions/loader/${v.mcVersion}/${v.version}/profile/json', v.mcVersion);
      case ModLoader.quilt:
        await _installProfile(dir, id, 'https://meta.quiltmc.org/v3/versions/loader/${v.mcVersion}/${v.version}/profile/json', v.mcVersion);
      case ModLoader.forge:
        final full = '${v.mcVersion}-${v.version}';
        // very old Forge versions add the mc version again as suffix in the maven path
        await _installForgeLike(dir, id, 'https://maven.minecraftforge.net/net/minecraftforge/forge/$full/forge-$full-installer.jar', javaPath, task);
      case ModLoader.neoforge:
        final url = v.version.startsWith('1.20.1-')
            ? 'https://maven.neoforged.net/releases/net/neoforged/forge/${v.version}/forge-${v.version}-installer.jar'
            : 'https://maven.neoforged.net/releases/net/neoforged/neoforge/${v.version}/neoforge-${v.version}-installer.jar';
        await _installForgeLike(dir, id, url, javaPath, task);
      default:
        throw CmlException('loader_unsupported', '暂不支持自动安装 ${v.loader.label}');
    }
    return id;
  }

  Future<void> _installProfile(GameDir dir, String id, String url, String mc) async {
    final j = (await _json(url) as Map).cast<String, dynamic>();
    j['id'] = id;
    j['inheritsFrom'] = mc;
    await dir.writeVersionJson(id, j);
  }

  /// Forge / NeoForge: run the official installer headless (`--installClient`),
  /// then rename the produced version to [id]. Legacy installers (≤1.12) are unpacked manually.
  Future<void> _installForgeLike(GameDir dir, String id, String installerUrl, String javaPath, Task? task) async {
    final tmp = await Directory.systemTemp.createTemp('cml-forge');
    try {
      final installer = p.join(tmp.path, 'installer.jar');
      task?.update(detail: '下载安装器', progress: -1);
      await dl.download(DownloadItem(installerUrl, installer));
      final profile = _readZipJson(installer, 'install_profile.json');
      if (profile == null) throw CmlException('forge_installer', '安装器格式无法识别');

      if (profile['versionInfo'] is Map) {
        await _installLegacyForge(dir, id, installer, profile);
        return;
      }
      final producedId = '${profile['version'] ?? ''}';
      await dir.ensureProfiles();
      task?.update(detail: '运行安装器（可能需要几分钟）', progress: -1);
      final before = (await dir.list()).map((e) => e.id).toSet();
      final proc = await Process.start(javaPath, ['-jar', installer, '--installClient', dir.root], workingDirectory: tmp.path);
      final log = StringBuffer();
      proc.stdout.transform(utf8.decoder).listen((s) {
        log.write(s);
        final line = s.trim().split('\n').last;
        if (line.isNotEmpty) task?.update(detail: line.length > 120 ? line.substring(0, 120) : line);
      });
      proc.stderr.transform(utf8.decoder).listen(log.write);
      task?.cancel.onCancel(proc.kill);
      final code = await proc.exitCode;
      task?.cancel.throwIfCancelled();
      if (code != 0) {
        await File(p.join(dir.root, 'cml-installer.log')).writeAsString(log.toString());
        throw CmlException('forge_installer', '安装器运行失败（退出码 $code），日志已保存到 cml-installer.log');
      }
      var created = producedId;
      if (created.isEmpty || !await File(dir.versionJson(created)).exists()) {
        final after = (await dir.list()).map((e) => e.id).toSet()..removeAll(before);
        if (after.isEmpty) throw CmlException('forge_installer', '安装器未生成版本');
        created = after.first;
      }
      if (created != id) {
        if (await Directory(dir.versionDir(id)).exists()) await dir.delete(id);
        await dir.rename(created, id);
      }
    } finally {
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
  }

  Future<void> _installLegacyForge(GameDir dir, String id, String installer, Map profile) async {
    final info = (profile['versionInfo'] as Map).cast<String, dynamic>();
    final install = profile['install'] as Map;
    final libPath = MavenName.parse('${install['path']}').path;
    final input = InputFileStream(installer);
    try {
      final zip = ZipDecoder().decodeStream(input);
      final f = zip.findFile('${install['filePath']}');
      if (f == null) throw CmlException('forge_installer', '安装器内缺少通用文件');
      final dest = File(dir.library(libPath));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(f.readBytes()!);
    } finally {
      await input.close();
    }
    info['id'] = id;
    info['inheritsFrom'] ??= '${install['minecraft']}';
    info['jar'] ??= '${install['minecraft']}';
    // legacy forge lists its own libs with "url" fields; strip the ones that need the universal jar (already placed)
    await dir.writeVersionJson(id, info);
  }

  static Map<String, dynamic>? _readZipJson(String zipPath, String name) {
    final input = InputFileStream(zipPath);
    try {
      final f = ZipDecoder().decodeStream(input).findFile(name);
      if (f == null) return null;
      return (jsonDecode(utf8.decode(f.readBytes()!)) as Map).cast<String, dynamic>();
    } finally {
      input.closeSync();
    }
  }
}
