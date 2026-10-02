import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../net/downloader.dart';
import 'content_api.dart';
import 'content_installer.dart';

/// CurseForge file fingerprint: MurmurHash2 (seed 1) over the file with whitespace bytes
/// (9, 10, 13, 32) removed.
int curseforgeFingerprint(Uint8List data) {
  final b = BytesBuilder(copy: false);
  final buf = Uint8List(data.length);
  var n = 0;
  for (final x in data) {
    if (x != 9 && x != 10 && x != 13 && x != 32) buf[n++] = x;
  }
  b.add(Uint8List.sublistView(buf, 0, n));
  return _murmur2(b.takeBytes(), 1);
}

int _murmur2(Uint8List d, int seed) {
  const m = 0x5bd1e995;
  const r = 24;
  final len = d.length;
  var h = (seed ^ len) & 0xffffffff;
  int mul(int a, int b) => ((a & 0xffff) * b + ((((a >>> 16) * b) & 0xffff) << 16)) & 0xffffffff;
  var i = 0;
  while (len - i >= 4) {
    var k = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
    k = mul(k & 0xffffffff, m);
    k ^= k >>> r;
    k = mul(k, m);
    h = mul(h, m);
    h ^= k;
    i += 4;
  }
  switch (len - i) {
    case 3:
      h ^= d[i + 2] << 16;
      h ^= d[i + 1] << 8;
      h ^= d[i];
      h = mul(h, m);
    case 2:
      h ^= d[i + 1] << 8;
      h ^= d[i];
      h = mul(h, m);
    case 1:
      h ^= d[i];
      h = mul(h, m);
  }
  h ^= h >>> 13;
  h = mul(h, m);
  h ^= h >>> 15;
  return h & 0xffffffff;
}

/// A local file with an available update.
class ContentUpdate {
  final LocalContent local;
  final ContentPlatform platform;
  final String projectId;
  final String currentVersion;
  final ContentVersion latest;
  bool selected = true;
  ContentUpdate(this.local, this.platform, this.projectId, this.currentVersion, this.latest);
}

class UpdateScan {
  final List<ContentUpdate> updates;
  final int checked;

  /// Files neither platform recognised (custom / removed mods).
  final List<LocalContent> unknown;
  UpdateScan(this.updates, this.checked, this.unknown);
}

/// "检查更新" for mods / resource packs / shaders in an instance.
class ContentUpdater {
  final ContentApi api;
  final Downloader dl;
  ContentUpdater(this.api, this.dl);

  Future<UpdateScan> check(String folder, {required String gameVersion, String? loader, bool includeBeta = false, Task? task}) async {
    final files = [for (final f in await LocalContent.list(folder)) if (f.enabled) f];
    if (files.isEmpty) return UpdateScan([], 0, []);
    task?.update(detail: '计算文件指纹', progress: -1);
    final sha = <String, LocalContent>{};
    for (final f in files) {
      sha[await Downloader.fileSha1(f.file)] = f;
    }

    final updates = <ContentUpdate>[];
    final known = <LocalContent>{};

    // ---- Modrinth: exact hash → current version, then /version_files/update for the newest compatible one
    task?.update(detail: '查询 Modrinth');
    try {
      final current = await api.mrVersionsByHash(sha.keys.toList());
      final latest = await api.mrLatestByHash(sha.keys.toList(), gameVersion: gameVersion, loader: loader);
      for (final e in current.entries) {
        final lf = sha[e.key]!;
        known.add(lf);
        final l = latest[e.key];
        if (l == null || l.id == e.value.id) continue;
        if (!includeBeta && l.channel != 'release' && e.value.channel == 'release') continue;
        if (!l.published.isAfter(e.value.published)) continue;
        updates.add(ContentUpdate(lf, ContentPlatform.modrinth, e.value.projectId, e.value.versionNumber, l));
      }
    } catch (e) {
      if (e is CancelledException) rethrow;
    }

    // ---- CurseForge: fingerprint match, then newest file for the game version / loader
    final rest = [for (final f in files) if (!known.contains(f)) f];
    if (rest.isNotEmpty) {
      task?.update(detail: '查询 CurseForge');
      final fp = <int, LocalContent>{};
      for (final f in rest) {
        fp[curseforgeFingerprint(await f.file.readAsBytes())] = f;
      }
      try {
        final matches = await api.cfMatchFingerprints(fp.keys.toList());
        for (final m in matches) {
          final lf = fp[m.$1];
          if (lf == null) continue;
          known.add(lf);
          final cur = m.$2;
          final candidates = await api.cfModFiles(cur.projectId, gameVersion: gameVersion, loader: loader);
          final newer = candidates.where((c) => c.published.isAfter(cur.published) && (includeBeta || c.channel == 'release' || cur.channel != 'release')).toList()
            ..sort((a, b) => b.published.compareTo(a.published));
          if (newer.isNotEmpty) updates.add(ContentUpdate(lf, ContentPlatform.curseforge, cur.projectId, cur.name, newer.first));
        }
      } catch (e) {
        if (e is CancelledException) rethrow;
      }
    }
    updates.sort((a, b) => a.local.displayName.toLowerCase().compareTo(b.local.displayName.toLowerCase()));
    return UpdateScan(updates, files.length, [for (final f in files) if (!known.contains(f)) f]);
  }

  /// Downloads the new files and moves the old ones to `<folder>/.cml-old/` (restorable).
  Future<int> apply(List<ContentUpdate> updates, {Task? task}) async {
    var done = 0;
    for (final u in updates.where((u) => u.selected)) {
      task?.update(detail: u.latest.primaryFile.filename, progress: done / updates.length);
      final folder = p.dirname(u.local.file.path);
      final f = u.latest.primaryFile;
      final urls = api.fileUrls(f.url);
      final dest = p.join(folder, f.filename);
      await dl.download(DownloadItem(urls.first, '$dest.cmlnew', sha1: f.sha1, size: f.size, fallbacks: urls.skip(1).toList()), cancel: task?.cancel);
      final backup = Directory(p.join(folder, '.cml-old'));
      await backup.create(recursive: true);
      final old = u.local.file;
      if (await old.exists()) await old.rename(p.join(backup.path, p.basename(old.path)));
      final target = File(dest);
      if (await target.exists()) await target.delete();
      await File('$dest.cmlnew').rename(dest);
      done++;
    }
    return done;
  }
}
