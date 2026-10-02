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

class JavaInstall {
  /// Path to java.exe (javaw.exe sits next to it).
  final String path;
  final String version; // e.g. 21.0.4, 1.8.0_402
  final int major;
  final bool is64Bit;
  final String vendor;
  bool manual;

  JavaInstall(this.path, this.version, this.major, this.is64Bit, this.vendor, {this.manual = false});

  String get home => p.dirname(p.dirname(path));

  /// javaw.exe when present (no console window).
  String get windowedPath {
    final w = p.join(p.dirname(path), 'javaw.exe');
    return File(w).existsSync() ? w : path;
  }

  String get label => 'Java $major ($version${is64Bit ? '' : ', 32 位'}) · $vendor';

  Map<String, dynamic> toJson() => {'path': path, 'version': version, 'major': major, 'is64Bit': is64Bit, 'vendor': vendor, 'manual': manual};
  factory JavaInstall.fromJson(Map j) =>
      JavaInstall('${j['path']}', '${j['version']}', (j['major'] as num).toInt(), j['is64Bit'] != false, '${j['vendor']}', manual: j['manual'] == true);

  static int parseMajor(String v) {
    final parts = v.split(RegExp(r'[._\-+]'));
    final a = int.tryParse(parts.first) ?? 0;
    if (a == 1 && parts.length > 1) return int.tryParse(parts[1]) ?? 0;
    return a;
  }
}

/// Finds Java installations and picks one for a Minecraft version.
class JavaManager {
  final String cachePath;
  List<JavaInstall> installs = [];

  JavaManager([String? cachePath]) : cachePath = cachePath ?? p.join(Os.cmlHome, 'java.json');

  /// Where CML-downloaded runtimes live.
  static String get runtimeDir => p.join(Os.cmlHome, 'runtime');

  Future<void> load() async {
    final j = await JsonFile.read(cachePath);
    if (j is List) {
      installs = [for (final e in j) JavaInstall.fromJson(e as Map)];
      installs.removeWhere((i) => !File(i.path).existsSync());
    }
  }

  Future<void> save() => JsonFile.write(cachePath, [for (final i in installs) i.toJson()]);

  /// Full scan ("自动扫描 Java"). Keeps manually-added entries.
  Future<List<JavaInstall>> scan({List<String> extraRoots = const []}) async {
    final candidates = <String>{};
    void addHome(String home) {
      final exe = p.join(home, 'bin', 'java.exe');
      if (File(exe).existsSync()) candidates.add(p.normalize(exe));
    }

    // JAVA_HOME and PATH
    final jh = Platform.environment['JAVA_HOME'];
    if (jh != null) addHome(jh);
    for (final d in (Platform.environment['PATH'] ?? '').split(';')) {
      final exe = p.join(d.replaceAll('"', ''), 'java.exe');
      if (d.isNotEmpty && File(exe).existsSync()) candidates.add(p.normalize(exe));
    }

    // Registry (JavaSoft / vendor keys)
    candidates.addAll(await _registryHomes().then((hs) => [for (final h in hs) p.join(h, 'bin', 'java.exe')].where((e) => File(e).existsSync())));

    // Common folders, two levels deep
    final drives = [for (final c in 'CDEFGH'.split('')) '$c:\\'].where((d) => Directory(d).existsSync());
    final roots = <String>[
      for (final pf in ['ProgramFiles', 'ProgramFiles(x86)', 'ProgramW6432']) ?Platform.environment[pf],
      for (final d in drives) ...[p.join(d, 'Java'), p.join(d, 'Program Files', 'Java'), d],
      p.join(Os.appData, '.minecraft', 'runtime'),
      p.join(Os.localAppData, 'Packages', 'Microsoft.4297127D64EC6_8wekyb3d8bbwe', 'LocalCache', 'Local', 'runtime'),
      p.join(Platform.environment['USERPROFILE'] ?? '', '.jdks'),
      runtimeDir,
      ...extraRoots,
    ];
    for (final r in roots) {
      await _walk(r, 0, candidates, isDriveRoot: r.length <= 3);
    }

    final found = <JavaInstall>[];
    for (final exe in candidates) {
      final j = await probe(exe);
      if (j != null && !found.any((f) => p.equals(f.path, j.path))) found.add(j);
    }
    for (final m in installs.where((i) => i.manual)) {
      if (!found.any((f) => p.equals(f.path, m.path))) found.add(m);
    }
    found.sort((a, b) => b.major != a.major ? b.major.compareTo(a.major) : a.path.compareTo(b.path));
    installs = found;
    await save();
    return installs;
  }

  Future<void> _walk(String dir, int depth, Set<String> out, {bool isDriveRoot = false}) async {
    final d = Directory(dir);
    if (!await d.exists()) return;
    final exe = p.join(dir, 'bin', 'java.exe');
    if (await File(exe).exists()) {
      out.add(p.normalize(exe));
      return;
    }
    if (depth >= (isDriveRoot ? 1 : 4)) return;
    try {
      await for (final e in d.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path).toLowerCase();
        if (isDriveRoot && !_looksJava(name)) continue;
        if (name.startsWith(r'$') || name == 'windows' || name == 'node_modules') continue;
        await _walk(e.path, depth + 1, out);
      }
    } catch (_) {
      // permission denied etc.
    }
  }

  static bool _looksJava(String n) =>
      n.contains('java') || n.contains('jdk') || n.contains('jre') || n.contains('zulu') || n.contains('graalvm') || n.contains('runtime') || n.contains('minecraft') || n.contains('mc');

  Future<List<String>> _registryHomes() async {
    if (!Platform.isWindows) return [];
    final out = <String>[];
    for (final key in [
      r'HKLM\SOFTWARE\JavaSoft',
      r'HKLM\SOFTWARE\WOW6432Node\JavaSoft',
      r'HKLM\SOFTWARE\Eclipse Adoptium',
      r'HKLM\SOFTWARE\Eclipse Foundation',
      r'HKLM\SOFTWARE\Azul Systems\Zulu',
      r'HKLM\SOFTWARE\Microsoft\JDK',
      r'HKLM\SOFTWARE\BellSoft\Liberica',
    ]) {
      try {
        final r = await Process.run('reg', ['query', key, '/s'], stdoutEncoding: const SystemEncoding());
        for (final m in RegExp(r'(?:JavaHome|Path|InstallationPath)\s+REG_SZ\s+(.+)', caseSensitive: false).allMatches('${r.stdout}')) {
          out.add(m.group(1)!.trim());
        }
      } catch (_) {}
    }
    return out;
  }

  /// Runs `java -XshowSettings:properties -version` and parses the output.
  static Future<JavaInstall?> probe(String exe) async {
    try {
      final r = await Process.run(exe, ['-XshowSettings:properties', '-version'], stderrEncoding: const SystemEncoding()).timeout(const Duration(seconds: 15));
      final out = '${r.stderr}\n${r.stdout}';
      String? prop(String k) => RegExp('^\\s*${RegExp.escape(k)} = (.*)\$', multiLine: true).firstMatch(out)?.group(1)?.trim();
      final version = prop('java.version') ?? RegExp(r'version "([^"]+)"').firstMatch(out)?.group(1);
      if (version == null) return null;
      final bits = prop('sun.arch.data.model');
      final arch = prop('os.arch') ?? '';
      final vendor = prop('java.vendor') ?? prop('java.vm.vendor') ?? '未知';
      return JavaInstall(p.normalize(exe), version, JavaInstall.parseMajor(version), bits != null ? bits == '64' : arch.contains('64'), vendor);
    } catch (_) {
      return null;
    }
  }

  Future<JavaInstall?> addManual(String exe) async {
    final j = await probe(exe);
    if (j == null) return null;
    j.manual = true;
    installs.removeWhere((i) => p.equals(i.path, j.path));
    installs.add(j);
    await save();
    return j;
  }

  /// Best Java for [requiredMajor]: exact major preferred, then the lowest newer one
  /// (except Java 8-only versions, which break on 9+ for Forge ≤1.16), 64-bit preferred.
  JavaInstall? pick(int requiredMajor, {bool strictLegacy = false}) {
    int score(JavaInstall j) {
      var s = 0;
      if (j.major == requiredMajor) {
        s += 1000;
      } else if (j.major > requiredMajor) {
        if (requiredMajor <= 8 && strictLegacy) return -1;
        s += 500 - (j.major - requiredMajor) * 10;
      } else {
        return -1;
      }
      if (j.is64Bit) s += 50;
      if (p.isWithin(runtimeDir, j.path)) s += 5;
      return s;
    }

    final ranked = [for (final j in installs) (j, score(j))].where((e) => e.$2 >= 0).toList()..sort((a, b) => b.$2.compareTo(a.$2));
    return ranked.firstOrNull?.$1;
  }
}

/// A downloadable Java runtime.
class JavaPackage {
  final int major;
  final String version;
  final String url;
  final String? sha256;
  final int size;
  final String name;
  JavaPackage(this.major, this.version, this.url, this.name, {this.sha256, this.size = 0});
}

/// Downloads JREs from Adoptium (official) with a mirror option.
class JavaDownloader {
  final Http http;
  final Downloader dl;
  JavaDownloader(this.http, this.dl);

  static const majors = [8, 11, 17, 21, 25];

  /// Latest Temurin JRE (falls back to JDK when no JRE build exists) for [major].
  Future<JavaPackage> latest(int major) async {
    final arch = Os.arch == 'arm64' ? 'aarch64' : (Os.arch == 'x86' ? 'x32' : 'x64');
    for (final type in ['jre', 'jdk']) {
      final u = Uri.parse('https://api.adoptium.net/v3/assets/latest/$major/hotspot?architecture=$arch&image_type=$type&os=windows&vendor=eclipse');
      try {
        final j = await http.getJson(u) as List;
        if (j.isEmpty) continue;
        final b = j.first['binary'];
        final pkg = b['package'];
        return JavaPackage(major, '${j.first['version']['openjdk_version']}', '${pkg['link']}', '${pkg['name']}',
            sha256: pkg['checksum'] as String?, size: (pkg['size'] as num?)?.toInt() ?? 0);
      } catch (_) {}
    }
    throw CmlException('java_list', '无法获取 Java $major 的下载信息');
  }

  /// Tsinghua TUNA mirrors Adoptium's GitHub release assets.
  static String? mirrorOf(String url) {
    final m = RegExp(r'github\.com/adoptium/temurin(\d+)-binaries/releases/download/[^/]+/(.+)$').firstMatch(url);
    if (m == null) return null;
    return 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/${m.group(1)}/${url.contains('-jre_') ? 'jre' : 'jdk'}/x64/windows/${m.group(2)}';
  }

  /// Downloads and unpacks into [JavaManager.runtimeDir]; returns java.exe path.
  Future<String> install(JavaPackage pkg, {Task? task}) async {
    final dest = p.join(JavaManager.runtimeDir, 'java-${pkg.major}');
    final zip = p.join(JavaManager.runtimeDir, pkg.name);
    final mirror = mirrorOf(pkg.url);
    final urls = dl.source == DownloadSource.official ? [pkg.url] : [?mirror, pkg.url];
    task?.update(detail: '下载 Java ${pkg.version}', progress: -1);
    Object? err;
    var ok = false;
    for (final u in urls) {
      try {
        await _downloadWithProgress(u, zip, pkg.size, task);
        ok = true;
        break;
      } catch (e) {
        if (e is CancelledException) rethrow;
        err = e;
      }
    }
    if (!ok) throw CmlException('java_download', 'Java 下载失败', err);

    task?.update(detail: '解压中', progress: -1);
    final tmp = Directory('$dest.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    await extractFileToDisk(zip, tmp.path);
    await File(zip).delete();
    // archive contains a single top-level folder (jdk-21.0.4+7-jre)
    final top = await tmp.list().where((e) => e is Directory).cast<Directory>().toList();
    final home = top.length == 1 ? top.first : tmp;
    final old = Directory(dest);
    if (await old.exists()) await old.delete(recursive: true);
    await home.rename(dest);
    if (await tmp.exists()) await tmp.delete(recursive: true);
    return p.join(dest, 'bin', 'java.exe');
  }

  Future<void> _downloadWithProgress(String url, String path, int size, Task? task) async {
    final res = await http.send('GET', Uri.parse(url), cancel: task?.cancel);
    if (res.statusCode >= 400) {
      await res.drain<void>();
      throw HttpStatusException(Uri.parse(url), res.statusCode, '', null);
    }
    final total = size > 0 ? size : res.contentLength;
    await File(path).parent.create(recursive: true);
    final sink = File(path).openWrite();
    var n = 0;
    final sw = Stopwatch()..start();
    try {
      await for (final c in res) {
        task?.cancel.throwIfCancelled();
        sink.add(c);
        n += c.length;
        if (total > 0) task?.update(progress: n / total, speed: sw.elapsedMilliseconds > 0 ? n * 1000 ~/ sw.elapsedMilliseconds : 0);
      }
    } finally {
      await sink.close();
    }
  }
}

/// Mojang's own runtimes (`java-runtime-delta` etc.) — used when a version JSON names a component.
class MojangRuntime {
  static const manifest = 'https://launchermeta.mojang.com/v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json';

  static Future<String> install(Http http, Downloader dl, String component, {Task? task}) async {
    final platform = Os.arch == 'arm64' ? 'windows-arm64' : (Os.arch == 'x86' ? 'windows-x86' : 'windows-x64');
    dynamic all;
    for (final u in Mirrors.candidates(manifest, dl.source)) {
      try {
        all = await http.getJson(Uri.parse(u));
        break;
      } catch (_) {}
    }
    final list = (all?[platform]?[component] as List?) ?? const [];
    if (list.isEmpty) throw CmlException('runtime_missing', '找不到 Mojang Java 运行时 $component');
    final mUrl = '${list.first['manifest']['url']}';
    final files = (await http.getJson(Uri.parse(Mirrors.candidates(mUrl, dl.source).first)) as Map)['files'] as Map;
    final dest = p.join(JavaManager.runtimeDir, component);
    final items = <DownloadItem>[];
    for (final e in files.entries) {
      final f = e.value as Map;
      final target = p.join(dest, e.key as String);
      if (f['type'] == 'directory') {
        await Directory(target).create(recursive: true);
      } else if (f['type'] == 'file') {
        final raw = f['downloads']['raw'];
        items.add(DownloadItem('${raw['url']}', target, sha1: raw['sha1'] as String?, size: (raw['size'] as num).toInt()));
      }
    }
    await dl.downloadAll(items, cancel: task?.cancel, onProgress: (d, t, _) => task?.update(progress: d / t, detail: 'Java 运行时 $d / $t'));
    return p.join(dest, 'bin', 'java.exe');
  }
}

String jsonPretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
