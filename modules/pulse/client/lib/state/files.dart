import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pulse_shared/pulse_shared.dart';

import 'app_state.dart';

/// A file picked in the composer, uploaded right away (before the message is sent).
class PendingUpload {
  final String nonce;
  final int ch;
  final String path, name;
  final int size;
  String? id; // server file id once the ticket arrived
  int done = 0;
  String? error;
  bool finished = false;
  TransferHandle handle = TransferHandle();
  Uint8List? preview; // local thumbnail (images)
  PendingUpload(this.nonce, this.ch, this.path, this.name, this.size);
  double get progress => size == 0 ? 1 : done / size;
}

/// A running / finished download.
class DownloadTask {
  final String id, name, path;
  int done = 0, total = 0;
  String? error;
  bool finished = false;
  TransferHandle handle = TransferHandle();
  DownloadTask(this.id, this.name, this.path);
}

/// Attachments: uploads (composer), downloads (to the Downloads folder) and
/// image thumbnails. Bulk data goes over separate encrypted connections in
/// background isolates (see transfer.dart) so voice and chat stay smooth.
class FileManager extends ChangeNotifier {
  final AppState app;
  FileManager(this.app);

  final Map<String, PendingUpload> uploads = {}; // by nonce
  final Map<String, DownloadTask> downloads = {}; // by file id
  final Map<String, Uint8List> _thumbs = {};
  final Set<String> _thumbReq = {};
  int _n = 0;

  void start() {}

  /// Uploads of a channel's composer.
  List<PendingUpload> composer(int ch) => uploads.values.where((u) => u.ch == ch).toList();

  bool readyToSend(int ch) => composer(ch).every((u) => u.finished && u.error == null && u.id != null);

  String? get _pin => app.saved?.pinnedKey;

  int get maxBytes => app.fileMaxMB * 1024 * 1024 < kMaxFileBytes ? app.fileMaxMB * 1024 * 1024 : kMaxFileBytes;

  /// Adds files to the composer of [ch] and starts uploading them.
  Future<void> add(int ch, List<String> paths) async {
    for (final p in paths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      if (composer(ch).length >= kMaxAttachments) {
        app.toast('每条消息最多 $kMaxAttachments 个附件');
        break;
      }
      final size = f.lengthSync();
      final name = f.uri.pathSegments.last;
      if (size > maxBytes) {
        app.toast('「$name」过大：单个文件最大 ${formatBytes(maxBytes)}');
        continue;
      }
      final u = PendingUpload('u${DateTime.now().microsecondsSinceEpoch}-${_n++}', ch, p, name, size);
      uploads[u.nonce] = u;
      notifyListeners();
      String? thumb;
      var w = 0, h = 0;
      if (isImageName(name) && size < 40 * 1024 * 1024) {
        final t = await _makeThumb(p);
        if (t != null) {
          (thumb, w, h) = (base64.encode(t.$1), t.$2, t.$3);
          u.preview = t.$1;
        }
      }
      app.conn.send({
        't': Msg.uploadRequest,
        'ch': ch,
        'name': name,
        'size': size,
        'nonce': u.nonce,
        'thumb': ?thumb,
        if (thumb != null) 'w': w,
        if (thumb != null) 'h': h,
      });
      notifyListeners();
    }
  }

  /// Adds in-memory bytes (pasted image) by writing them to a temp file first.
  Future<void> addBytes(int ch, Uint8List bytes, String name) async {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}pulse_paste')..createSync(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}${DateTime.now().millisecondsSinceEpoch}_$name');
    await f.writeAsBytes(bytes, flush: true);
    await add(ch, [f.path]);
  }

  void onUploadTicket(Map<String, dynamic> m) {
    final u = uploads[asStr(m['nonce'])];
    if (u == null) {
      app.conn.send({'t': Msg.uploadCancel, 'id': asStr(m['id'])});
      return;
    }
    u.id = asStr(m['id']);
    final pin = _pin, addr = app.address;
    if (pin == null || addr == null) return;
    if (u.size == 0) {
      u.finished = true;
      notifyListeners();
      return;
    }
    var last = DateTime(2000);
    uploadFile(
      address: addr,
      pinnedKey: pin,
      ticket: asStr(m['ticket']),
      path: u.path,
      offset: asInt(m['offset']),
      handle: u.handle,
      onProgress: (d) {
        u.done = d;
        final now = DateTime.now();
        if (now.difference(last).inMilliseconds > 150) {
          last = now;
          notifyListeners();
        }
      },
    ).then((_) {
      u.finished = true;
      u.done = u.size;
      notifyListeners();
    }, onError: (Object e) {
      if (u.handle.cancelled) return;
      u.error = '$e';
      notifyListeners();
    });
  }

  void onUploadError(String nonce, String msg) {
    final u = uploads[nonce];
    if (u == null) return;
    u.error = msg;
    notifyListeners();
  }

  /// Retries a failed upload (continues where it stopped).
  void retry(PendingUpload u) {
    u.error = null;
    u.handle = TransferHandle();
    app.conn.send({'t': Msg.uploadRequest, 'ch': u.ch, 'name': u.name, 'size': u.size, 'nonce': u.nonce, 'resume': ?u.id});
    notifyListeners();
  }

  void remove(PendingUpload u) {
    u.handle.cancel();
    uploads.remove(u.nonce);
    if (u.id != null) app.conn.send({'t': Msg.uploadCancel, 'id': u.id});
    notifyListeners();
  }

  /// Ids for sending and clears the composer.
  List<String> take(int ch) {
    final list = composer(ch);
    for (final u in list) {
      uploads.remove(u.nonce);
    }
    notifyListeners();
    return [for (final u in list) u.id!];
  }

  // ---- thumbnails

  Uint8List? thumb(Attachment a) {
    if (!a.thumb || a.expired) return null;
    final t = _thumbs[a.id];
    if (t != null) return t;
    if (_thumbReq.add(a.id)) app.conn.send({'t': Msg.getThumb, 'id': a.id});
    return null;
  }

  void onThumb(String id, String data) {
    try {
      final b = base64.decode(data);
      if (avatarImageType(b) == null) return;
      _thumbs[id] = b;
      if (_thumbs.length > 300) _thumbs.remove(_thumbs.keys.first);
      notifyListeners();
    } catch (_) {}
  }

  /// JPEG thumbnail (max 400 px) computed in a background isolate: (bytes, original w, original h).
  static Future<(Uint8List, int, int)?> _makeThumb(String path) => Isolate.run(() {
        try {
          final src = img.decodeImage(File(path).readAsBytesSync());
          if (src == null) return null;
          final scale = 400 / (src.width > src.height ? src.width : src.height);
          final t = scale < 1 ? img.copyResize(src, width: (src.width * scale).round(), height: (src.height * scale).round()) : src;
          var q = 80;
          var out = img.encodeJpg(t, quality: q);
          while (out.length > kMaxThumbBytes && q > 30) {
            q -= 15;
            out = img.encodeJpg(t, quality: q);
          }
          if (out.length > kMaxThumbBytes) return null;
          return (out, src.width, src.height);
        } catch (_) {
          return null;
        }
      });

  // ---- downloads

  static String downloadsDir() {
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final d = Directory('$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Pulse');
    d.createSync(recursive: true);
    return d.path;
  }

  /// Free file name in the downloads folder ("a.png", "a (1).png", ...).
  static String _target(String name) {
    final dir = downloadsDir();
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var p = '$dir${Platform.pathSeparator}$name';
    for (var i = 1; File(p).existsSync() || File('$p.part').existsSync(); i++) {
      p = '$dir${Platform.pathSeparator}$base ($i)$ext';
    }
    return p;
  }

  /// Starts downloading an attachment; [open] opens it when finished.
  void download(Attachment a, {bool open = false}) {
    final ex = downloads[a.id];
    if (ex != null && ex.error == null) {
      if (ex.finished) _open(ex.path, folder: !open);
      return;
    }
    final task = ex ?? DownloadTask(a.id, a.name, _target(sanitizeFileName(a.name)));
    task
      ..error = null
      ..handle = TransferHandle();
    _openWhenDone[a.id] = open;
    downloads[a.id] = task;
    app.conn.send({'t': Msg.fileRequest, 'id': a.id});
    notifyListeners();
  }

  final Map<String, bool> _openWhenDone = {};

  void onFileTicket(Map<String, dynamic> m) {
    final t = downloads[asStr(m['id'])];
    final pin = _pin, addr = app.address;
    if (t == null || pin == null || addr == null) return;
    final part = File('${t.path}.part');
    final offset = part.existsSync() ? part.lengthSync() : 0;
    t.total = asInt(m['size']);
    var last = DateTime(2000);
    downloadFile(
      address: addr,
      pinnedKey: pin,
      ticket: asStr(m['ticket']),
      path: part.path,
      offset: offset > t.total ? 0 : offset,
      handle: t.handle,
      onProgress: (d, total) {
        t.done = d;
        t.total = total;
        final now = DateTime.now();
        if (now.difference(last).inMilliseconds > 150) {
          last = now;
          notifyListeners();
        }
      },
    ).then((_) {
      part.renameSync(t.path);
      t.finished = true;
      notifyListeners();
      if (_openWhenDone.remove(t.id) ?? false) {
        _open(t.path);
      } else {
        app.toast('已下载到 ${t.path}');
      }
    }, onError: (Object e) {
      t.error = t.handle.cancelled ? '已取消' : '$e';
      notifyListeners();
    });
  }

  void onFileError(String id, String msg) {
    final t = downloads[id];
    if (t == null) return;
    t.error = msg;
    notifyListeners();
  }

  void cancelDownload(String id) {
    final t = downloads.remove(id);
    if (t == null) return;
    t.handle.cancel();
    try {
      File('${t.path}.part').deleteSync();
    } catch (_) {}
    notifyListeners();
  }

  static void _open(String path, {bool folder = false}) {
    if (!Platform.isWindows) return;
    if (folder) {
      Process.run('explorer.exe', ['/select,', path]);
    } else {
      // "start" via cmd needs an empty title argument; quotes keep spaces intact
      Process.run('cmd', ['/c', 'start', '', path]);
    }
  }

  void showInFolder(String id) {
    final t = downloads[id];
    if (t != null && t.finished) _open(t.path, folder: true);
  }

  @visibleForTesting
  Map<String, Uint8List> get thumbs => _thumbs;
}
