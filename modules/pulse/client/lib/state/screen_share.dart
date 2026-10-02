import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pulse_shared/pulse_shared.dart';

import '../native/native.dart';
import '../native/video_textures.dart';
import '../net/media_link.dart';
import 'app_state.dart';

/// Quality presets: (label, max width, max height, fps, kbps).
const streamPresets = [
  ('流畅 720p 30帧', 1280, 720, 30, 2500),
  ('高清 1080p 30帧', 1920, 1080, 30, 5000),
  ('高清 1080p 60帧', 1920, 1080, 60, 8000),
  ('原画 1440p 60帧', 2560, 1440, 60, 14000),
  ('省流 480p 15帧', 854, 480, 15, 1000),
];

/// Screen sharing (sending) and watching others' streams.
///
/// Video never touches the main connection: a separate media connection (own
/// isolate, see media_link.dart) carries H.264 access units. The native engine
/// captures + encodes (Windows Graphics Capture → Media Foundation H.264) and
/// decodes; frames reach Flutter through a texture registered by the runner.
class ScreenShare extends ChangeNotifier {
  final AppState app;
  ScreenShare(this.app);

  final textures = VideoTextures();
  MediaLink? _link;
  bool _linkConnecting = false;
  final List<void Function()> _onLinkReady = [];

  // ---- sending
  bool sharing = false;
  bool starting = false;
  String source = '';
  String sourceName = '';
  int preset = 1;
  Map<String, dynamic> status = {};
  Timer? _statusTimer;

  // ---- watching: streamer uid -> texture id (null while creating)
  final Map<int, int?> watching = {};
  final Map<int, (int, int)> sizes = {}; // decoded frame size per streamer
  int? focused; // stream shown large
  bool get hasPreview => sharing && watching.containsKey(app.me);

  Native get _n => app.native;

  // ---------------------------------------------------------------- media link

  void _withLink(void Function() f) {
    if (_link != null && !_linkConnecting) return f();
    _onLinkReady.add(f);
    if (_linkConnecting) return;
    _linkConnecting = true;
    app.conn.send({'t': Msg.mediaRequest});
  }

  void onMediaTicket(String ticket) {
    final addr = app.address, pin = app.saved?.pinnedKey;
    if (addr == null || pin == null) return;
    MediaLink.connect(address: addr, pinnedKey: pin, ticket: ticket, onMessage: _onLink).then((l) {
      _link = l;
    }, onError: (Object e) {
      _linkConnecting = false;
      _onLinkReady.clear();
      app.toast('无法建立屏幕共享连接：$e');
    });
  }

  void _onLink(Object m) {
    if (m == 'ready') {
      _linkConnecting = false;
      final l = List.of(_onLinkReady);
      _onLinkReady.clear();
      for (final f in l) {
        f();
      }
      return;
    }
    final l = m as List;
    switch (l[0]) {
      case 'frame':
        final uid = l[1] as int;
        if (watching.containsKey(uid)) _n.videoPush(uid, l[3] as Uint8List, keyframe: ((l[2] as int) & kVideoKey) != 0);
      case 'need_key':
        _n.screenKeyframe();
      case 'closed':
        final had = _link != null;
        _link = null;
        _linkConnecting = false;
        _onLinkReady.clear();
        if (had && (sharing || watching.isNotEmpty) && app.authed) {
          // reconnect and resume
          final w = watching.keys.where((u) => u != app.me).toList();
          _withLink(() {
            if (sharing) _n.screenKeyframe();
            for (final u in w) {
              app.conn.send({'t': Msg.watch, 'uid': u, 'on': true});
            }
          });
        }
    }
  }

  // ---------------------------------------------------------------- sharing

  bool get canShare => app.voiceChannel != null && (app.channels[app.voiceChannel]?.can(Perm.stream) ?? false) && _n.available;

  Map<String, dynamic> sources() => _n.screenSources();

  /// Starts sharing [id] (`m:0` monitor / `w:<hwnd>` window).
  void start(String id, String name, int presetIndex) {
    if (!canShare) return app.toast('请先加入语音频道（需要“屏幕共享”权限）');
    preset = presetIndex.clamp(0, streamPresets.length - 1);
    final (_, w, h, fps, kbps) = streamPresets[preset];
    source = id;
    sourceName = name;
    starting = true;
    notifyListeners();
    _withLink(() {
      if (!_n.screenStart(id, maxW: w, maxH: h, fps: fps, kbps: kbps)) {
        starting = false;
        app.toast('无法开始屏幕共享');
        notifyListeners();
      }
    });
  }

  void stop() {
    if (!sharing && !starting) return;
    _n.screenStop();
    _stopped();
  }

  void _stopped() {
    final was = sharing;
    sharing = false;
    starting = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    if (was) app.conn.send({'t': Msg.streamStop});
    _unwatchLocal(app.me);
    _maybeCloseLink();
    notifyListeners();
  }

  void setPreset(int i) {
    preset = i.clamp(0, streamPresets.length - 1);
    if (sharing) start(source, sourceName, preset); // restart with new size / fps
  }

  void keyframeRequested() => _n.screenKeyframe();

  /// Local preview of my own stream (decodes my own packets).
  void togglePreview() {
    if (watching.containsKey(app.me)) {
      _unwatchLocal(app.me);
    } else if (sharing) {
      _openDecoder(app.me);
      _n.screenKeyframe();
    }
    notifyListeners();
  }

  void onNative(NativeEvent e) {
    switch (e.type) {
      case NativeEv.videoPacket:
        final key = (e.a & 1) != 0;
        _link?.sendVideo(e.data, key: key);
        if (watching.containsKey(app.me)) _n.videoPush(app.me, e.data, keyframe: key);
      case NativeEv.screen:
        if (e.a == 1) {
          starting = false;
          try {
            status = jsonDecode(e.text) as Map<String, dynamic>;
          } catch (_) {}
          if (!sharing) {
            sharing = true;
            app.native.playSound(Sound.join);
          }
          app.conn.send({
            't': Msg.streamStart,
            'w': asInt(status['w']),
            'h': asInt(status['h']),
            'fps': streamPresets[preset].$4,
            'title': sourceName,
          });
          _statusTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
            status = _n.screenStatus();
            notifyListeners();
          });
        } else {
          if (e.a == -1) app.toast('屏幕共享失败：${e.text}');
          if (e.a == 0 && e.text.isNotEmpty && sharing) app.toast('屏幕共享已停止：${e.text}');
          _stopped();
        }
        notifyListeners();
      case NativeEv.videoSize:
        sizes[e.a] = (e.b >> 16, e.b & 0xFFFF);
        notifyListeners();
    }
  }

  // ---------------------------------------------------------------- watching

  void watch(int uid) {
    if (uid == app.me) return togglePreview();
    if (watching.containsKey(uid)) {
      focused = uid;
      notifyListeners();
      return;
    }
    _openDecoder(uid);
    focused = uid;
    notifyListeners();
    _withLink(() => app.conn.send({'t': Msg.watch, 'uid': uid, 'on': true}));
  }

  void _openDecoder(int uid) {
    watching[uid] = null;
    _n.videoOpen(uid);
    textures.create(uid).then((tid) {
      if (!watching.containsKey(uid)) {
        textures.dispose(uid);
        return;
      }
      watching[uid] = tid;
      notifyListeners();
    });
  }

  void unwatch(int uid) {
    if (uid != app.me) app.conn.send({'t': Msg.watch, 'uid': uid, 'on': false});
    _unwatchLocal(uid);
    _maybeCloseLink();
    notifyListeners();
  }

  void _unwatchLocal(int uid) {
    if (!watching.containsKey(uid)) return;
    watching.remove(uid);
    sizes.remove(uid);
    if (focused == uid) focused = watching.keys.firstOrNull;
    _n.videoClose(uid);
    textures.dispose(uid);
  }

  void _maybeCloseLink() {
    if (sharing || starting || watching.keys.any((u) => u != app.me)) return;
    _link?.close();
    _link = null;
  }

  /// Server stream list changed: drop streams that ended.
  void onStreams() {
    for (final uid in watching.keys.toList()) {
      if (uid != app.me && !app.streams.containsKey(uid)) _unwatchLocal(uid);
    }
    _maybeCloseLink();
    notifyListeners();
  }

  void leftVoice() {
    stop();
    for (final uid in watching.keys.toList()) {
      unwatch(uid);
    }
  }

  void reset() {
    if (sharing || starting) _n.screenStop();
    sharing = false;
    starting = false;
    _statusTimer?.cancel();
    _statusTimer = null;
    for (final uid in watching.keys.toList()) {
      _unwatchLocal(uid);
    }
    _link?.close();
    _link = null;
    _linkConnecting = false;
    _onLinkReady.clear();
  }
}
