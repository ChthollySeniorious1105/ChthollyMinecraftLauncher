import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/json_file.dart';
import '../common/os.dart';
import '../common/task.dart';
import '../net/http.dart';
import '../net/source.dart';

class GithubAsset {
  final String name;
  final String url;
  final int size;
  final String? digest; // "sha256:…" when GitHub provides it
  GithubAsset(this.name, this.url, this.size, this.digest);
}

class GithubRelease {
  final String tag;
  final String name;
  final String body;
  final DateTime published;
  final List<GithubAsset> assets;
  GithubRelease(this.tag, this.name, this.body, this.published, this.assets);

  static GithubRelease fromJson(Map j) => GithubRelease(
        '${j['tag_name']}',
        '${j['name'] ?? j['tag_name']}',
        '${j['body'] ?? ''}',
        DateTime.tryParse('${j['published_at']}') ?? DateTime(2000),
        [
          for (final a in j['assets'] as List? ?? [])
            GithubAsset('${a['name']}', '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0, a['digest'] as String?)
        ],
      );
}

/// A tool that CML keeps in sync with a GitHub repository's latest release
/// (mihomo, Chunker CLI, Clash Verge Rev, CML itself).
abstract class GithubComponent {
  final Http http;
  GithubComponent(this.http);

  String get id;
  String get displayName;
  String get repo; // owner/name

  /// Picks the asset for this machine.
  GithubAsset? pickAsset(GithubRelease r);

  /// Unpacks/installs the downloaded [file] into [installDir].
  Future<void> install(File file, GithubAsset asset, Task? task);

  String get installDir => p.join(Os.cmlHome, 'tools', id);
  String get _stateFile => p.join(installDir, 'cml-component.json');

  Future<String?> installedVersion() async {
    final j = await JsonFile.read(_stateFile);
    return j is Map ? j['version'] as String? : null;
  }

  Future<GithubRelease> latest() async {
    try {
      final j = await http.getJson(Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'});
      return GithubRelease.fromJson(j as Map);
    } on HttpStatusException catch (e) {
      if (e.status == 403 || e.status == 429) throw CmlException('github_rate', 'GitHub API 访问次数已达上限，请稍后再试', e);
      rethrow;
    }
  }

  /// Returns the release when an update is available, else null.
  Future<GithubRelease?> checkUpdate() async {
    final r = await latest();
    final cur = await installedVersion();
    return cur == r.tag ? null : r;
  }

  /// Downloads + installs [r] (or latest).
  Future<String> update({GithubRelease? release, Task? task}) async {
    final r = release ?? await latest();
    final asset = pickAsset(r) ?? (throw CmlException('asset_missing', '$displayName ${r.tag} 没有适用于本机的文件'));
    final tmpDir = Directory(p.join(Os.cmlHome, 'tools', '.download'));
    await tmpDir.create(recursive: true);
    final file = File(p.join(tmpDir.path, asset.name));
    task?.update(detail: '下载 $displayName ${r.tag}', progress: 0);
    await _download(asset, file, task);
    task?.update(detail: '安装 $displayName ${r.tag}', progress: -1);
    await Directory(installDir).create(recursive: true);
    await install(file, asset, task);
    await file.delete().catchError((_) => file);
    await JsonFile.write(_stateFile, {'version': r.tag, 'asset': asset.name, 'installed': DateTime.now().toIso8601String()});
    return r.tag;
  }

  Future<void> _download(GithubAsset a, File out, Task? task) async {
    final urls = {Mirrors.github(a.url), a.url}.toList();
    Object? err;
    for (final u in urls) {
      try {
        final res = await http.send('GET', Uri.parse(u), cancel: task?.cancel);
        if (res.statusCode >= 400) {
          await res.drain<void>();
          throw HttpStatusException(Uri.parse(u), res.statusCode, '', null);
        }
        final sink = out.openWrite();
        var n = 0;
        final sw = Stopwatch()..start();
        try {
          await for (final c in res) {
            task?.cancel.throwIfCancelled();
            sink.add(c);
            n += c.length;
            if (a.size > 0) task?.update(progress: n / a.size, speed: sw.elapsedMilliseconds > 0 ? n * 1000 ~/ sw.elapsedMilliseconds : 0);
          }
        } finally {
          await sink.close();
        }
        if (a.size > 0 && n != a.size) throw CmlException('size', '下载不完整');
        if (a.digest != null && a.digest!.startsWith('sha256:')) {
          final got = await _sha256(out);
          if (got != a.digest!.substring(7)) throw CmlException('sha256', '$displayName 文件校验失败');
        }
        return;
      } catch (e) {
        if (e is CancelledException) rethrow;
        err = e;
      }
    }
    throw CmlException('download', '$displayName 下载失败', err);
  }

  static Future<String> _sha256(File f) async {
    final r = await Process.run('certutil', ['-hashfile', f.path, 'SHA256']);
    final line = '${r.stdout}'.split('\n').map((l) => l.trim().replaceAll(' ', '')).firstWhere((l) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(l), orElse: () => '');
    return line.toLowerCase();
  }

  static Future<void> unzipTo(File zip, String dir) async {
    final input = InputFileStream(zip.path);
    try {
      final a = ZipDecoder().decodeStream(input);
      for (final f in a.files) {
        if (!f.isFile || f.name.contains('..')) continue;
        final out = File(p.join(dir, f.name));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.readBytes()!);
      }
    } finally {
      await input.close();
    }
  }
}
