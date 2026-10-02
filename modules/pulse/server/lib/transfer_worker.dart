import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pulse_shared/pulse_shared.dart';

/// Runs one file transfer of an auxiliary connection in a separate isolate, so
/// ChaCha20-Poly1305 (pure Dart, ~50 MB/s) and disk I/O never stall voice relay
/// on the main isolate. The main isolate keeps the socket (sockets can't move
/// between isolates) and only shuffles opaque sealed frames:
///
///   upload:   main → worker  sealed kFrameData payloads (Uint8List)
///             worker → main  ['ack', bytesOnDisk] after each chunk, ['frame', bytes] (sealed aux_done), ['done'] / ['err', msg]
///   download: worker → main  ['frame', bytes] sealed kFrameData frames (already framed, ready for socket.add)
///             main → worker  'more' (one credit per frame written to the socket)
class TransferWorker {
  final Isolate _iso;
  final ReceivePort _port;
  final SendPort _to;
  TransferWorker._(this._iso, this._port, this._to);

  /// [onMessage] receives the worker's messages; the worker exits after 'done' / 'err'.
  static Future<TransferWorker> start({
    required bool upload,
    required List<Object> channelState,
    required String path,
    required int offset,
    required int size,
    required String id,
    required void Function(Object? msg) onMessage,
  }) async {
    final port = ReceivePort();
    final ready = Completer<SendPort>();
    port.listen((m) {
      if (m is SendPort && !ready.isCompleted) {
        ready.complete(m);
      } else {
        onMessage(m);
      }
    });
    final iso = await Isolate.spawn(_main, [port.sendPort, upload, channelState, path, offset, size, id], onExit: port.sendPort);
    return TransferWorker._(iso, port, await ready.future);
  }

  void send(Object m) => _to.send(m);

  void kill() {
    _port.close();
    _iso.kill(priority: Isolate.immediate);
  }
}

Future<void> _main(List<Object> a) async {
  final out = a[0] as SendPort;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final upload = a[1] as bool;
  final ch = SecureChannel.restore(a[2] as List<Object>);
  final path = a[3] as String;
  var pos = a[4] as int;
  final size = a[5] as int;
  final id = a[6] as String;
  RandomAccessFile? f;
  try {
    if (upload) {
      final w = await File(path).open(mode: pos > 0 ? FileMode.append : FileMode.write);
      f = w;
      await w.truncate(pos);
      await w.setPosition(pos);
      await for (final m in inbox) {
        if (m is! Uint8List) {
          if (m == 'stop') break;
          continue;
        }
        final plain = ch.open(kFrameData, m);
        if (pos + plain.length > size) throw const FormatException('数据超出声明的文件大小');
        await w.writeFrom(plain);
        pos += plain.length;
        out.send(['ack', pos]);
        if (pos == size) {
          await w.flush();
          await w.close();
          f = null;
          out.send(['frame', encodeFrame(kFrameJson, ch.seal(kFrameJson, utf8.encode(jsonEncode({'t': Msg.auxDone, 'id': id}))))]);
          out.send(['done']);
          break;
        }
      }
    } else {
      final r = await File(path).open();
      f = r;
      await r.setPosition(pos);
      var credit = 16;
      final more = StreamController<void>();
      inbox.listen((m) {
        if (more.isClosed) return;
        if (m == 'more') more.add(null);
        if (m == 'stop') more.close();
      });
      final it = StreamIterator(more.stream);
      while (pos < size) {
        while (credit <= 0) {
          if (!await it.moveNext()) throw const FormatException('stopped');
          credit++;
        }
        final chunk = await r.read(kFileChunk);
        if (chunk.isEmpty) throw const FormatException('文件读取失败');
        out.send(['frame', encodeFrame(kFrameData, ch.seal(kFrameData, chunk))]);
        pos += chunk.length;
        credit--;
      }
      out.send(['done']);
      unawaited(more.close()); // the paused iterator would never let close() complete
    }
  } catch (e) {
    final msg = e is FormatException ? e.message : '$e';
    try {
      out.send(['frame', encodeFrame(kFrameJson, ch.seal(kFrameJson, utf8.encode(jsonEncode({'t': Msg.auxError, 'msg': msg}))))]);
    } catch (_) {}
    out.send(['err', msg]);
  } finally {
    await f?.close();
    inbox.close();
  }
}
