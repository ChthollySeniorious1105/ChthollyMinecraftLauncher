import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../common/errors.dart';
import 'http.dart';
import 'source.dart';

/// One file to fetch.
class DownloadItem {
  /// Official URL; mirrors are derived via [Mirrors].
  final String url;
  final String path;
  final String? sha1;
  final int size;

  /// Extra URLs tried after the derived candidates.
  final List<String> fallbacks;

  const DownloadItem(this.url, this.path, {this.sha1, this.size = 0, this.fallbacks = const []});

  @override
  String toString() => path;
}

/// Parallel downloader with SHA1 verification, retries and mirror fallback.
///
/// Files that already exist with a matching hash (or matching size when no hash is known)
/// are skipped, so re-running an install only fetches what is missing or damaged.
class Downloader {
  final Http http;
  DownloadSource source;
  int concurrency;
  int retries;

  Downloader(this.http, {this.source = DownloadSource.auto, this.concurrency = 32, this.retries = 3});

  /// Downloads all [items]. [onProgress] receives (doneFiles, totalFiles, bytesDone).
  Future<void> downloadAll(
    List<DownloadItem> items, {
    CancelToken? cancel,
    void Function(int done, int total, int bytes)? onProgress,
  }) async {
    // de-duplicate by path (assets are often shared)
    final seen = <String>{};
    final queue = [for (final i in items) if (seen.add(i.path.toLowerCase())) i];
    var done = 0, bytes = 0, next = 0;
    final failures = <(DownloadItem, Object)>[];

    Future<void> worker() async {
      while (true) {
        cancel?.throwIfCancelled();
        if (next >= queue.length) return;
        final item = queue[next++];
        try {
          bytes += await download(item, cancel: cancel);
        } on CancelledException {
          rethrow;
        } catch (e) {
          failures.add((item, e));
        }
        done++;
        onProgress?.call(done, queue.length, bytes);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency.clamp(1, 128); i++) worker()]);
    if (failures.isNotEmpty) {
      final first = failures.first;
      throw CmlException('download', '有 ${failures.length} 个文件下载失败，例如 ${first.$1.path}', first.$2);
    }
  }

  /// Downloads a single item; returns bytes transferred (0 when already valid).
  Future<int> download(DownloadItem item, {CancelToken? cancel}) async {
    final f = File(item.path);
    if (await isValid(f, item.sha1, item.size)) return 0;
    final urls = [...Mirrors.candidates(item.url, source), ...item.fallbacks];
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 0; attempt < retries; attempt++) {
        cancel?.throwIfCancelled();
        try {
          return await _fetch(Uri.parse(url), f, item.sha1, cancel);
        } on CancelledException {
          rethrow;
        } on HttpStatusException catch (e) {
          lastError = e;
          if (e.status == 404 || e.status == 403) break; // try next mirror
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    throw CmlException('download', '下载失败：${item.url}', lastError);
  }

  Future<int> _fetch(Uri url, File f, String? sha1, CancelToken? cancel) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.cmldl');
    final res = await http.send('GET', url, cancel: cancel);
    if (res.statusCode >= 400) {
      await res.drain<void>();
      throw HttpStatusException(url, res.statusCode, '', null);
    }
    final sink = tmp.openWrite();
    final digest = _DigestSink();
    final hasher = sha1Hasher(digest);
    var n = 0;
    try {
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        cancel?.throwIfCancelled();
        sink.add(chunk);
        hasher.add(chunk);
        n += chunk.length;
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    hasher.close();
    if (sha1 != null && sha1.isNotEmpty && digest.value.toString() != sha1.toLowerCase()) {
      await tmp.delete().catchError((_) => tmp);
      throw CmlException('sha1', '文件校验失败：${f.path}');
    }
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
    return n;
  }

  static ByteConversionSink sha1Hasher(Sink<Digest> out) => sha1.startChunkedConversion(out);

  static Future<bool> isValid(File f, String? hash, int size) async {
    if (!await f.exists()) return false;
    if (hash != null && hash.isNotEmpty) return (await fileSha1(f)) == hash.toLowerCase();
    if (size > 0) return await f.length() == size;
    return await f.length() > 0;
  }

  static Future<String> fileSha1(File f) async => (await sha1.bind(f.openRead()).first).toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
