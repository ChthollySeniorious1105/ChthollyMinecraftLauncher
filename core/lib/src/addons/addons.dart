import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import '../common/task.dart';
import '../net/http.dart';
import '../net/source.dart';
import '../tools/github_component.dart';
import '../update/self_update.dart';

/// An optional package ("分包") that is not part of the main CML zip — the large AI model weights.
/// Published as release assets next to the CML zip:
///
///   `CML-addon-<id>-<version>.zip`     the files, unpacked into [AddonManager.dirOf]
///   cml-addons.json                   manifest: {"addons":[{id, version, asset, size, sha256}]}
class AddonInfo {
  final String id;
  final String name;
  final String description;

  /// Approximate download size shown before the manifest is fetched.
  final String sizeHint;
  const AddonInfo(this.id, this.name, this.description, {required this.sizeHint});
}

/// Known addons. The ids are part of the release asset names — never rename them.
abstract class Addons {
  static const pulseModels = AddonInfo('pulse-ai-models', 'Pulse AI 变声基础模型', 'HuBERT / RMVPE / RVC 基础模型权重，Pulse 的 AI 变声需要它', sizeHint: '约 810 MB');
  static const pulseVoices = AddonInfo('pulse-ai-voices', 'Pulse AI 音色包', '额外的 RVC v2 音色模型（可选，安装后在 Pulse 变声器中选择）', sizeHint: '约 960 MB');

  static const all = [pulseModels, pulseVoices];

  static AddonInfo? byId(String id) => all.where((a) => a.id == id).firstOrNull;
}

/// Tools and apps shipped inside the main CML zip, next to cml.exe:
///
///   tools\bedrocktool\bedrocktool.exe   tools\netease\NeMcDecrypter.exe
///   tools\lumikeymapper\LumiKeyMapper.exe
///   apps\runtime\electron.exe + apps\<desktoppet|liteeditor|litereader>\app   (one shared Electron runtime)
///
/// `CML_BUNDLE_DIR` overrides the base folder (development: point it at a built dist\CML).
abstract class Bundled {
  static String get base => Platform.environment['CML_BUNDLE_DIR'] ?? p.dirname(Platform.resolvedExecutable);
  static String tool(String id) => p.join(base, 'tools', id);
  static String app(String id) => p.join(base, 'apps', id, 'app');
  static String get electron => p.join(base, 'apps', 'runtime', 'electron.exe');

  static String get bedrocktool => p.join(tool('bedrocktool'), 'bedrocktool.exe');
  static String get neteaseDecrypter => p.join(tool('netease'), 'NeMcDecrypter.exe');
  static String get lumiKeyMapper => p.join(tool('lumikeymapper'), 'LumiKeyMapper.exe');

  static Map<String, String> get themeEnv => {'CML_THEME_FILE': p.join(Os.cmlHome, 'theme.json')};

  static bool hasApp(String id) => File(electron).existsSync() && Directory(app(id)).existsSync();

  /// Starts a bundled Electron app (`desktoppet`, `liteeditor`, `litereader`) detached.
  static Future<Process> launchApp(String id, {List<String> args = const []}) async {
    if (!hasApp(id)) throw CmlException('app_missing', '找不到内置应用 $id，请重新安装 CML');
    final dir = app(id);
    return Process.start(electron, [dir, ...args], workingDirectory: dir, mode: ProcessStartMode.detached, environment: themeEnv);
  }

  /// Starts a bundled GUI exe detached with the theme bridge.
  static Future<Process> launchExe(String exe, {List<String> args = const []}) async {
    if (!File(exe).existsSync()) throw CmlException('tool_missing', '找不到 ${p.basename(exe)}，请重新安装 CML');
    return Process.start(exe, args, workingDirectory: p.dirname(exe), mode: ProcessStartMode.detached, environment: themeEnv);
  }
}

class AddonRelease {
  final String id;
  final String version;
  final GithubAsset asset;
  final String? sha256;
  AddonRelease(this.id, this.version, this.asset, this.sha256);
}

/// Installs, updates and removes addons under `%APPDATA%\CML\addons\<id>`, so they survive CML self-updates.
class AddonManager {
  final Http http;
  final String repo;
  AddonManager(this.http, {String? repo}) : repo = repo ?? SelfUpdater.defaultRepo;

  /// Root for all addons; `CML_ADDONS_DIR` (portable installs) or [rootOverride] (tests) replace it.
  static String? rootOverride;
  static String get root => rootOverride ?? Platform.environment['CML_ADDONS_DIR'] ?? p.join(Os.cmlHome, 'addons');
  static String dirOf(String id) => p.join(root, id);
  static File _state(String id) => File(p.join(dirOf(id), 'cml-addon.json'));

  static bool isInstalled(String id) => _state(id).existsSync();

  static Future<String?> installedVersion(String id) async {
    final j = await JsonFile.read(_state(id).path);
    return j is Map ? j['version'] as String? : null;
  }

  /// Reads `cml-addons.json` from the latest release.
  Future<Map<String, AddonRelease>> available() async {
    final j = await http.getJson(Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'});
    final rel = GithubRelease.fromJson(j as Map);
    final manifestAsset = rel.assets.where((a) => a.name == 'cml-addons.json').firstOrNull;
    final out = <String, AddonRelease>{};
    if (manifestAsset == null) {
      // older releases: infer from asset names
      for (final a in rel.assets) {
        final m = RegExp(r'^CML-addon-([a-z0-9\-]+?)-(\d[\w.\-]*)\.zip$').firstMatch(a.name);
        if (m != null) out[m.group(1)!] = AddonRelease(m.group(1)!, m.group(2)!, a, a.digest?.replaceFirst('sha256:', ''));
      }
      return out;
    }
    final m = parseManifest(utf8.decode(await http.bytes(Uri.parse(Mirrors.github(manifestAsset.url)))));
    for (final e in (m['addons'] as List? ?? const [])) {
      final asset = rel.assets.where((a) => a.name == e['asset']).firstOrNull;
      if (asset == null) continue;
      out['${e['id']}'] = AddonRelease('${e['id']}', '${e['version']}', asset, e['sha256'] as String? ?? asset.digest?.replaceFirst('sha256:', ''));
    }
    return out;
  }

  /// Parses `cml-addons.json` (tolerates the UTF-8 BOM PowerShell writes).
  static Map parseManifest(String text) => jsonDecode(text.startsWith('﻿') ? text.substring(1) : text) as Map;

  /// Downloads and installs [r], replacing any previous version.
  Future<void> install(AddonRelease r, {Task? task}) async {
    final tmp = Directory(p.join(root, '.download'));
    await tmp.create(recursive: true);
    final file = File(p.join(tmp.path, r.asset.name));
    task?.update(detail: '下载 ${r.id} ${r.version}', progress: 0);
    await _download(r, file, task);
    await installZip(r.id, r.version, file, task: task);
    await file.delete().catchError((_) => file);
  }

  /// Installs a local addon zip (offline installs / "从文件安装").
  static Future<void> installZip(String id, String version, File zip, {Task? task}) async {
    task?.update(detail: '安装 $id', progress: -1);
    final dir = Directory(dirOf(id));
    final staging = Directory('${dir.path}.new');
    if (await staging.exists()) await staging.delete(recursive: true);
    await GithubComponent.unzipTo(zip, staging.path);
    // layout is kept as-is: models\… / voices\… are addressed by sub-folder
    if (await dir.exists()) await dir.delete(recursive: true);
    await staging.rename(dir.path);
    await JsonFile.write(_state(id).path, {'id': id, 'version': version, 'installed': DateTime.now().toIso8601String()});
  }

  static Future<void> uninstall(String id) async {
    final d = Directory(dirOf(id));
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> _download(AddonRelease r, File out, Task? task) async {
    final urls = {Mirrors.github(r.asset.url), r.asset.url}.toList();
    Object? err;
    for (final u in urls) {
      try {
        final res = await http.send('GET', Uri.parse(u), cancel: task?.cancel);
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw HttpStatusException(Uri.parse(u), res.statusCode, '', null);
        }
        final sink = out.openWrite();
        final hashSink = _DigestSink();
        final hasher = sha256.startChunkedConversion(hashSink);
        var n = 0;
        final sw = Stopwatch()..start();
        try {
          await for (final c in res) {
            task?.cancel.throwIfCancelled();
            sink.add(c);
            hasher.add(c);
            n += c.length;
            if (r.asset.size > 0) task?.update(progress: n / r.asset.size, speed: sw.elapsedMilliseconds > 0 ? n * 1000 ~/ sw.elapsedMilliseconds : 0);
          }
        } finally {
          await sink.close();
          hasher.close();
        }
        if (r.asset.size > 0 && n != r.asset.size) throw const CmlException('size', '下载不完整');
        if (r.sha256 != null && r.sha256!.isNotEmpty && hashSink.value.toString() != r.sha256!.toLowerCase()) {
          throw CmlException('sha256', '${r.id} 文件校验失败');
        }
        return;
      } catch (e) {
        if (e is CancelledException) rethrow;
        err = e;
      }
    }
    throw CmlException('download', '${r.id} 下载失败', err);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
