import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'protocol.dart';
import 'secure.dart';

/// Client side of file transfers over an auxiliary connection (see protocol.dart).
///
/// Each transfer runs in its own isolate: ChaCha20-Poly1305 in Dart does ~50 MB/s,
/// so a 2 GB file would otherwise block the caller (the UI) for a long time.
/// The auxiliary connection repeats the key exchange and checks the server's
/// static key against [pinnedKey], so it cannot be redirected to another server.
class TransferException implements Exception {
  final String message;
  const TransferException(this.message);
  @override
  String toString() => message;
}

/// Lets the caller abort a running transfer.
class TransferHandle {
  SendPort? _port;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _port?.send('cancel');
  }

  bool get cancelled => _cancelled;
}

/// Splits "host:port", "host" or "[v6]:port".
(String, int) parseHostPort(String input) {
  var s = input.trim();
  if (s.contains('://')) s = s.substring(s.indexOf('://') + 3);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end > 0) {
      final rest = s.substring(end + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
      return (s.substring(1, end), port ?? kDefaultPort);
    }
  }
  final i = s.lastIndexOf(':');
  if (i > 0 && s.indexOf(':') == i) return (s.substring(0, i), int.tryParse(s.substring(i + 1)) ?? kDefaultPort);
  return (s, kDefaultPort);
}

/// Uploads [path] starting at byte [offset]. [onProgress] gets the total bytes on the server.
Future<void> uploadFile({
  required String address,
  required String pinnedKey,
  required String ticket,
  required String path,
  int offset = 0,
  void Function(int done)? onProgress,
  TransferHandle? handle,
}) =>
    _run(['upload', address, pinnedKey, ticket, path, offset], onProgress, handle);

/// Downloads into [path]; with [offset] > 0 the existing file is continued (resume).
Future<void> downloadFile({
  required String address,
  required String pinnedKey,
  required String ticket,
  required String path,
  int offset = 0,
  void Function(int done, int total)? onProgress,
  TransferHandle? handle,
}) {
  var total = 0;
  return _run(['download', address, pinnedKey, ticket, path, offset], (d) {
    if (d < 0) {
      total = -d - 1;
    } else {
      onProgress?.call(d, total);
    }
  }, handle);
}

Future<void> _run(List<Object> args, void Function(int)? onProgress, TransferHandle? handle) async {
  final port = ReceivePort();
  final done = Completer<void>();
  final iso = await Isolate.spawn(_worker, [port.sendPort, ...args], errorsAreFatal: true, onExit: port.sendPort);
  port.listen((m) {
    if (m is SendPort) {
      handle?._port = m;
      if (handle?._cancelled ?? false) m.send('cancel');
    } else if (m is int) {
      onProgress?.call(m);
    } else if (m is List && m.isNotEmpty && m[0] == 'ok') {
      if (!done.isCompleted) done.complete();
    } else if (m is List && m.isNotEmpty && m[0] == 'err') {
      if (!done.isCompleted) done.completeError(TransferException('${m[1]}'));
    } else if (m == null) {
      // isolate exited
      if (!done.isCompleted) done.completeError(const TransferException('传输意外中断'));
    }
  });
  try {
    await done.future;
  } finally {
    port.close();
    iso.kill(priority: Isolate.immediate);
  }
}

Future<void> _worker(List<Object> a) async {
  final out = a[0] as SendPort;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final job = _Job(a[1] as String, a[2] as String, a[3] as String, a[4] as String, a[5] as String, a[6] as int, out);
  inbox.listen((m) {
    if (m == 'cancel') job.cancel();
  });
  try {
    await job.run();
    out.send(['ok']);
  } catch (e) {
    out.send(['err', job.cancelled ? '已取消' : (e is TransferException ? e.message : '传输失败：$e')]);
  } finally {
    job.socket?.destroy();
    inbox.close();
  }
}

class _Job {
  final String kind, address, pinnedKey, ticket, path;
  final int offset;
  final SendPort out;
  _Job(this.kind, this.address, this.pinnedKey, this.ticket, this.path, this.offset, this.out);

  Socket? socket;
  SecureChannel? channel;
  final _frames = StreamController<Frame>();
  late final StreamIterator<Frame> _it = StreamIterator(_frames.stream);
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    socket?.destroy();
    if (!_frames.isClosed) _frames.addError(const TransferException('已取消'));
  }

  Future<Frame> _next({Duration timeout = const Duration(seconds: 30)}) async {
    final ok = await _it.moveNext().timeout(timeout, onTimeout: () => throw const TransferException('服务器无响应'));
    if (!ok) throw const TransferException('连接已断开');
    return _it.current;
  }

  Future<Map<String, dynamic>> _nextJson() async {
    while (true) {
      final f = await _next();
      final plain = channel!.open(f.kind, f.payload);
      if (f.kind != kFrameJson) continue;
      final m = Frame(f.kind, plain).json;
      if (m['t'] == Msg.auxError) throw TransferException(asStr(m['msg'], '服务器拒绝了传输'));
      return m;
    }
  }

  void _send(int kind, List<int> plain) => socket!.add(encodeFrame(kind, channel!.seal(kind, plain)));

  Future<void> run() async {
    final (host, port) = parseHostPort(address);
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 10))
        .catchError((Object e) => throw TransferException('无法连接服务器：$e'));
    socket = s;
    final dec = FrameDecoder();
    s.listen((d) {
      try {
        for (final f in dec.add(d)) {
          _frames.add(f);
        }
      } catch (_) {
        _frames.addError(const TransferException('数据错误'));
      }
    }, onDone: () => _frames.close(), onError: (Object e) {
      if (!_frames.isClosed) _frames.addError(TransferException('连接错误：$e'));
    }, cancelOnError: true);
    final hs = ClientHandshake();
    s.add(encodeJson(hs.hello()));
    final (ch, spk) = hs.finish((await _next()).json);
    if (base64.encode(spk) != pinnedKey) throw const TransferException('服务器身份不匹配，已拒绝传输');
    channel = ch;
    _send(kFrameJson, utf8.encode(jsonEncode({'t': Msg.aux, 'ticket': ticket, 'kind': kind, 'offset': offset})));
    final ready = await _nextJson();
    if (ready['t'] != Msg.auxReady) throw const TransferException('服务器响应无效');
    if (kind == 'upload') {
      await _upload(asInt(ready['offset']), asInt(ready['size']));
    } else {
      await _download(asInt(ready['size']));
    }
  }

  Future<void> _upload(int start, int size) async {
    final f = await File(path).open();
    try {
      if (await f.length() != size) throw const TransferException('文件在上传过程中被修改');
      await f.setPosition(start);
      var pos = start, n = 0;
      var lastReport = DateTime(2000);
      out.send(pos);
      while (pos < size) {
        if (cancelled) throw const TransferException('已取消');
        final chunk = await f.read(kFileChunk);
        if (chunk.isEmpty) throw const TransferException('读取文件失败');
        _send(kFrameData, chunk);
        pos += chunk.length;
        if (++n % 8 == 0) await socket!.flush();
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 100 || pos == size) {
          lastReport = now;
          out.send(pos);
        }
      }
      await socket!.flush();
    } finally {
      await f.close();
    }
    final m = await _nextJson();
    if (m['t'] != Msg.auxDone) throw const TransferException('上传未完成');
  }

  Future<void> _download(int size) async {
    out.send(-size - 1); // total size
    final f = await File(path).open(mode: offset > 0 ? FileMode.append : FileMode.write);
    try {
      if (offset > 0) {
        await f.truncate(offset);
        await f.setPosition(offset);
      }
      var pos = offset;
      var lastReport = DateTime(2000);
      out.send(pos);
      while (pos < size) {
        final fr = await _next();
        final plain = channel!.open(fr.kind, fr.payload);
        if (fr.kind == kFrameJson) {
          final m = Frame(fr.kind, plain).json;
          if (m['t'] == Msg.auxError) throw TransferException(asStr(m['msg'], '下载失败'));
          continue;
        }
        if (fr.kind != kFrameData) continue;
        if (pos + plain.length > size) throw const TransferException('数据超出文件大小');
        await f.writeFrom(plain);
        pos += plain.length;
        final now = DateTime.now();
        if (now.difference(lastReport).inMilliseconds > 100 || pos == size) {
          lastReport = now;
          out.send(pos);
        }
      }
      await f.flush();
    } finally {
      await f.close();
    }
  }
}
