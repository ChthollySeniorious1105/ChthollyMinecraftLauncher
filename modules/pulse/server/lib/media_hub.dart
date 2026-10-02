import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pulse_shared/pulse_shared.dart';

/// Screen share relay running in its own isolate. It owns the encryption state of
/// every media connection: the main isolate forwards sealed frames from streamers
/// and gets back sealed frames for each viewer, so ChaCha20-Poly1305 for video
/// (megabytes per second × viewers) never competes with voice relay.
///
/// main → hub:  ['add', conn, uid, channelState] | ['rm', conn] | ['in', conn, kind, sealed]
///              ['route', streamerUid, [viewer conn ids]] | ['slow', conn, bool]
/// hub → main:  ['out', conn, frame, streamerUid] | ['bad', conn] | ['skipped', conn, streamerUid]
///
/// Frames are sealed with consecutive counters, so the main isolate must write every
/// frame it gets; congestion is handled here instead: while a viewer is marked slow
/// its frames are skipped, and after a skip it only resumes at the next keyframe.
class MediaHub {
  final void Function(int conn, Uint8List frame) onOut;
  final void Function(int conn) onBad;
  final void Function(int conn, int streamer) onSkipped;
  MediaHub({required this.onOut, required this.onBad, required this.onSkipped});

  Isolate? _iso;
  ReceivePort? _port;
  SendPort? _to;

  Future<void> start() async {
    final port = ReceivePort();
    _port = port;
    final ready = Completer<SendPort>();
    port.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is List && m.isNotEmpty) {
        switch (m[0]) {
          case 'out':
            onOut(m[1] as int, m[2] as Uint8List);
          case 'bad':
            onBad(m[1] as int);
          case 'skipped':
            onSkipped(m[1] as int, m[2] as int);
        }
      }
    });
    _iso = await Isolate.spawn(_hubMain, port.sendPort);
    _to = await ready.future;
  }

  void add(int conn, int uid, List<Object> state) => _to?.send(['add', conn, uid, state]);
  void remove(int conn) => _to?.send(['rm', conn]);
  void input(int conn, int kind, Uint8List sealed) => _to?.send(['in', conn, kind, sealed]);
  void route(int streamer, List<int> viewers) => _to?.send(['route', streamer, viewers]);
  void setSlow(int conn, bool slow) => _to?.send(['slow', conn, slow]);

  void stop() {
    _port?.close();
    _iso?.kill(priority: Isolate.immediate);
  }
}

void _hubMain(SendPort out) {
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  final conns = <int, (SecureChannel, int)>{};
  final routes = <int, List<int>>{};
  final slow = <int>{};
  final waitKey = <(int, int)>{}; // (viewer conn, streamer) resumes at the next keyframe
  inbox.listen((m) {
    final l = m as List;
    switch (l[0]) {
      case 'add':
        conns[l[1] as int] = (SecureChannel.restore((l[3] as List).cast<Object>()), l[2] as int);
      case 'rm':
        conns.remove(l[1] as int);
        slow.remove(l[1] as int);
      case 'slow':
        if (l[2] as bool) {
          slow.add(l[1] as int);
        } else {
          slow.remove(l[1] as int);
        }
      case 'route':
        final v = (l[2] as List).cast<int>();
        if (v.isEmpty) {
          routes.remove(l[1] as int);
        } else {
          routes[l[1] as int] = v;
        }
      case 'in':
        final id = l[1] as int;
        final c = conns[id];
        if (c == null) return;
        final kind = l[2] as int;
        Uint8List plain;
        try {
          plain = c.$1.open(kind, l[3] as Uint8List);
        } catch (_) {
          conns.remove(id);
          out.send(['bad', id]);
          return;
        }
        if (kind != kFrameVideo || plain.length < 2) return; // pings etc.
        final viewers = routes[c.$2];
        if (viewers == null) return;
        final key = (plain[0] & kVideoKey) != 0;
        final relay = Uint8List(4 + plain.length);
        ByteData.sublistView(relay).setUint32(0, c.$2);
        relay.setRange(4, relay.length, plain);
        for (final v in viewers) {
          final vc = conns[v];
          if (vc == null) continue;
          final k = (v, c.$2);
          if (slow.contains(v)) {
            if (waitKey.add(k)) out.send(['skipped', v, c.$2]);
            continue;
          }
          if (waitKey.contains(k)) {
            if (!key) continue;
            waitKey.remove(k);
          }
          out.send(['out', v, encodeFrame(kFrameVideo, vc.$1.seal(kFrameVideo, relay)), c.$2]);
        }
    }
  });
}
