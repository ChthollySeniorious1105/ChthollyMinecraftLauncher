import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pulse_shared/pulse_shared.dart';

/// Screen share media connection, run in its own isolate: the socket, handshake
/// and ChaCha20-Poly1305 for video (several MB/s) stay off the UI isolate.
///
/// UI → isolate:  ['video', Uint8List [flags][AU]] | 'close'
/// isolate → UI:  'ready' | ['frame', streamerUid, flags, Uint8List AU] | ['closed', reason]
///
/// Outgoing video is dropped while more than [_maxBacklog] bytes are unsent (a slow
/// uplink must not build up seconds of delay); after a drop only a keyframe resumes
/// the stream and ['need_key'] asks the encoder for one.
class MediaLink {
  final SendPort _to;
  final ReceivePort _port;
  final Isolate _iso;
  MediaLink._(this._to, this._port, this._iso);

  static Future<MediaLink> connect({
    required String address,
    required String pinnedKey,
    required String ticket,
    required void Function(Object msg) onMessage,
  }) async {
    final port = ReceivePort();
    final ready = Completer<SendPort>();
    port.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m == null) {
        onMessage(['closed', '连接已断开']);
      } else {
        onMessage(m as Object);
      }
    });
    final iso = await Isolate.spawn(_main, [port.sendPort, address, pinnedKey, ticket], onExit: port.sendPort);
    return MediaLink._(await ready.future, port, iso);
  }

  void sendVideo(Uint8List au, {required bool key}) {
    final b = Uint8List(au.length + 1);
    b[0] = key ? kVideoKey : 0;
    b.setRange(1, b.length, au);
    _to.send(['video', b]);
  }

  void close() {
    _to.send('close');
    Timer(const Duration(seconds: 1), () {
      _port.close();
      _iso.kill(priority: Isolate.immediate);
    });
  }
}

const _maxBacklog = 2 * 1024 * 1024;

Future<void> _main(List<Object> a) async {
  final out = a[0] as SendPort;
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final (host, port) = parseHostPort(a[1] as String);
  Socket s;
  try {
    s = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
  } catch (e) {
    out.send(['closed', '无法连接服务器：$e']);
    return;
  }
  try {
    s.setOption(SocketOption.tcpNoDelay, true);
  } catch (_) {}
  final dec = FrameDecoder(maxFrame: kMaxMediaFrame);
  final hs = ClientHandshake();
  SecureChannel? ch;
  var ready = false;
  var queued = 0;
  var flushing = false;
  var waitKey = false;
  final queue = <Uint8List>[];

  void pump() {
    if (queue.isEmpty) {
      flushing = false;
      return;
    }
    flushing = true;
    final batch = List.of(queue);
    queue.clear();
    var n = 0;
    for (final f in batch) {
      s.add(f);
      n += f.length;
    }
    s.flush().then((_) {
      queued -= n;
      pump();
    }, onError: (_) {});
  }

  void write(int kind, List<int> plain) {
    final f = encodeFrame(kind, ch!.seal(kind, plain));
    queue.add(f);
    queued += f.length;
    if (!flushing) pump();
  }

  var done = false;
  void finish(String why) {
    if (done) return;
    done = true;
    out.send(['closed', why]);
    s.destroy();
    inbox.close();
  }

  Timer? ping;
  s.listen((d) {
    try {
      for (final f in dec.add(d)) {
        if (ch == null) {
          final (c, spk) = hs.finish(f.json);
          if (base64.encode(spk) != a[2]) return finish('服务器身份不匹配');
          ch = c;
          write(kFrameJson, utf8.encode(jsonEncode({'t': Msg.aux, 'ticket': a[3], 'kind': 'media'})));
          continue;
        }
        final p = ch!.open(f.kind, f.payload);
        if (f.kind == kFrameJson) {
          final m = Frame(f.kind, p).json;
          if (m['t'] == Msg.auxReady && !ready) {
            ready = true;
            out.send('ready');
            // keep the connection alive (server idle timeout 60 s)
            ping = Timer.periodic(const Duration(seconds: 15), (_) => write(kFrameJson, utf8.encode('{"t":"ping"}')));
          } else if (m['t'] == Msg.auxError) {
            return finish(asStr(m['msg'], '服务器拒绝了连接'));
          }
        } else if (f.kind == kFrameVideo && p.length > 5) {
          out.send(['frame', ByteData.sublistView(p).getUint32(0), p[4], Uint8List.sublistView(p, 5)]);
        }
      }
    } catch (e) {
      finish('媒体连接错误');
    }
  }, onDone: () => finish('媒体连接已断开'), onError: (_) => finish('媒体连接错误'), cancelOnError: true);
  s.add(encodeJson(hs.hello()));

  await for (final m in inbox) {
    if (m == 'close') break;
    if (m is List && m[0] == 'video' && ready) {
      final b = m[1] as Uint8List;
      final key = (b[0] & kVideoKey) != 0;
      if (queued > _maxBacklog) {
        if (!waitKey) out.send(['need_key']);
        waitKey = true;
        continue;
      }
      if (waitKey && !key) continue;
      waitKey = false;
      write(kFrameVideo, b);
    }
  }
  ping?.cancel();
  finish('已关闭');
}
