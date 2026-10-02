import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Event types from pulse_native.h.
abstract class NativeEv {
  static const packet = 1, speaking = 2, hotkey = 3, hotkeyCaptured = 4, vcStatus = 5, log = 6, device = 7, mutedTalk = 8, overlay = 9;
  static const videoPacket = 10, screen = 11, videoSize = 12;
}

abstract class HotkeySlot {
  static const ptt = 0, mute = 1, deafen = 2, voiceChanger = 3, overlay = 4;
}

abstract class InputMode {
  static const vad = 0, ptt = 1, open = 2;
}

abstract class VcMode {
  static const off = 0, dsp = 1, ai = 2;
}

abstract class VcState {
  static const off = 0, loading = 1, running = 2, error = 3;
}

abstract class Sound {
  static const join = 0, leave = 1, mute = 2, unmute = 3, message = 4, deafen = 5, undeafen = 6, test = 7, mention = 8;
}

class NativeEvent {
  final int type, a, b;
  final Uint8List data;
  NativeEvent(this.type, this.a, this.b, this.data);
  String get text => utf8.decode(data, allowMalformed: true);
}

class AudioDevice {
  final String id, name;
  final bool isDefault;
  AudioDevice(this.id, this.name, this.isDefault);
}

typedef _EvC = Void Function(Int32, Int32, Int32, Pointer<Uint8>, Int32);

/// dart:ffi bindings for pulse_native.dll (see client/native/include/pulse_native.h).
/// When the DLL is missing (e.g. widget tests) [available] is false and every
/// call is a no-op, so the UI still works without audio.
class Native {
  static const abiVersion = 4;

  final DynamicLibrary? _lib;
  final String? loadError;
  final _events = StreamController<NativeEvent>.broadcast();
  NativeCallable<_EvC>? _cb;

  Stream<NativeEvent> get events => _events.stream;
  bool get available => _lib != null;

  Native._(this._lib, this.loadError);

  static Native load() {
    if (!Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) {
      return Native._(null, '仅支持 Windows');
    }
    try {
      final dir = File(Platform.resolvedExecutable).parent.path;
      final lib = DynamicLibrary.open('$dir\\pulse_native.dll');
      final n = Native._(lib, null);
      final v = n._abi();
      if (v != abiVersion) return Native._(null, 'pulse_native.dll 版本不匹配（$v，需要 $abiVersion）');
      return n;
    } catch (e) {
      return Native._(null, '无法加载 pulse_native.dll：$e');
    }
  }

  late final int Function() _abi = _lib!.lookupFunction<Int32 Function(), int Function()>('pn_abi_version');
  late final _init = _lib!.lookupFunction<Int32 Function(Pointer<NativeFunction<_EvC>>, Pointer<Utf8>),
      int Function(Pointer<NativeFunction<_EvC>>, Pointer<Utf8>)>('pn_init');
  late final _shutdown = _lib!.lookupFunction<Void Function(), void Function()>('pn_shutdown');
  late final _free = _lib!.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('pn_free');
  late final _listDevices = _lib!.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('pn_list_devices');
  late final _setDevice = _lib!.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('pn_set_device');
  late final _captureStart = _lib!.lookupFunction<Int32 Function(), int Function()>('pn_capture_start');
  late final _captureStop = _lib!.lookupFunction<Void Function(), void Function()>('pn_capture_stop');
  late final _playbackStart = _lib!.lookupFunction<Int32 Function(), int Function()>('pn_playback_start');
  late final _playbackStop = _lib!.lookupFunction<Void Function(), void Function()>('pn_playback_stop');
  late final _setI = <String, void Function(int)>{};
  late final _setF = <String, void Function(double)>{};
  late final _playPush = _lib!.lookupFunction<Void Function(Uint32, Pointer<Uint8>, Int32), void Function(int, Pointer<Uint8>, int)>(
      'pn_play_push');
  late final _playRemove = _lib!.lookupFunction<Void Function(Uint32), void Function(int)>('pn_play_remove');
  late final _playClear = _lib!.lookupFunction<Void Function(), void Function()>('pn_play_clear');
  late final _userVolume = _lib!.lookupFunction<Void Function(Uint32, Float), void Function(int, double)>('pn_set_user_volume');
  late final _levels = _lib!.lookupFunction<Int32 Function(Pointer<Float>, Int32), int Function(Pointer<Float>, int)>('pn_get_levels');
  late final _userLevels = _lib!.lookupFunction<Int32 Function(Pointer<Uint32>, Pointer<Float>, Int32),
      int Function(Pointer<Uint32>, Pointer<Float>, int)>('pn_get_user_levels');
  late final _hotkeysEnable = _lib!.lookupFunction<Int32 Function(Int32), int Function(int)>('pn_hotkeys_enable');
  late final _hotkeySet = _lib!.lookupFunction<Void Function(Int32, Int32, Int32), void Function(int, int, int)>('pn_hotkey_set');
  late final _keyName = _lib!.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('pn_key_name');
  late final _gpuInfo = _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('pn_gpu_info');
  late final _vcConfig = _lib!.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32, Int32, Int32),
      int Function(Pointer<Utf8>, Pointer<Utf8>, int, int, int)>('pn_vc_ai_config');
  late final _vcUnload = _lib!.lookupFunction<Void Function(), void Function()>('pn_vc_ai_unload');
  late final _vcStatus = _lib!.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('pn_vc_status');
  late final _protect = _lib!.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, Int32, Pointer<Int32>),
      Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Int32>)>('pn_protect');
  late final _unprotect = _lib!.lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>, Int32, Pointer<Int32>),
      Pointer<Uint8> Function(Pointer<Uint8>, int, Pointer<Int32>)>('pn_unprotect');

  void Function(int) _i(String name) =>
      _setI[name] ??= _lib!.lookupFunction<Void Function(Int32), void Function(int)>(name);
  void Function(double) _f(String name) =>
      _setF[name] ??= _lib!.lookupFunction<Void Function(Float), void Function(double)>(name);

  bool init() {
    if (_lib == null) return false;
    _cb = NativeCallable<_EvC>.listener((int t, int a, int b, Pointer<Uint8> data, int len) {
      final bytes = len > 0 ? Uint8List.fromList(data.asTypedList(len)) : Uint8List(0);
      if (data != nullptr) _free(data.cast());
      _events.add(NativeEvent(t, a, b, bytes));
    });
    final dir = '${File(Platform.resolvedExecutable).parent.path}\\'.toNativeUtf8();
    try {
      return _init(_cb!.nativeFunction, dir) == 0;
    } finally {
      malloc.free(dir);
    }
  }

  void shutdown() {
    if (_lib == null) return;
    _shutdown();
    _cb?.close();
    _cb = null;
  }

  String _takeString(Pointer<Utf8> p) {
    if (p == nullptr) return '';
    final s = p.toDartString();
    _free(p.cast());
    return s;
  }

  List<AudioDevice> devices({required bool capture}) {
    if (_lib == null) return const [];
    try {
      final list = jsonDecode(_takeString(_listDevices(capture ? 0 : 1))) as List;
      return [for (final d in list) AudioDevice('${d['id']}', '${d['name']}', d['default'] == true)];
    } catch (_) {
      return const [];
    }
  }

  int setDevice({required bool capture, required String id}) {
    if (_lib == null) return -1;
    final p = id.toNativeUtf8();
    try {
      return _setDevice(capture ? 0 : 1, p);
    } finally {
      malloc.free(p);
    }
  }

  int startCapture() => _lib == null ? -1 : _captureStart();
  void stopCapture() => _lib == null ? null : _captureStop();
  int startPlayback() => _lib == null ? -1 : _playbackStart();
  void stopPlayback() => _lib == null ? null : _playbackStop();

  void _seti(String n, int v) {
    if (_lib != null) _i(n)(v);
  }

  void _setf(String n, double v) {
    if (_lib != null) _f(n)(v);
  }

  void setTransmit(bool on) => _seti('pn_set_transmit', on ? 1 : 0);
  void setMute(bool on) => _seti('pn_set_mute', on ? 1 : 0);
  void setInputMode(int m) => _seti('pn_set_input_mode', m);
  void setPtt(bool held) => _seti('pn_set_ptt', held ? 1 : 0);
  void setInputGain(double v) => _setf('pn_set_input_gain', v);
  void setVadThreshold(double v) => _setf('pn_set_vad_threshold', v);
  void setNoiseSuppression(int level) => _seti('pn_set_noise_suppression', level);
  void setBitrate(int bps) => _seti('pn_set_bitrate', bps);
  void setMonitor(bool on) => _seti('pn_set_monitor', on ? 1 : 0);
  void setPttReleaseMs(int ms) => _seti('pn_set_ptt_release_ms', ms);
  void setOutputVolume(double v) => _setf('pn_set_output_volume', v);
  void setDeafen(bool on) => _seti('pn_set_deafen', on ? 1 : 0);
  void playSound(int kind) => _seti('pn_play_sound', kind);
  void setSoundVolume(double v) => _setf('pn_set_sound_volume', v);
  void setVcMode(int m) => _seti('pn_vc_set_mode', m);
  void setVcPitch(double st) => _setf('pn_vc_set_pitch', st);
  void setVcRobot(bool on) => _seti('pn_vc_set_robot', on ? 1 : 0);
  void setVcSpeaker(int sid) => _seti('pn_vc_set_speaker', sid);
  void hotkeyCapture(bool on) => _seti('pn_hotkey_capture', on ? 1 : 0);

  // ---- speaker overlay
  late final _ovlShow = _lib?.lookupFunction<Void Function(Int32), void Function(int)>('pn_overlay_show');
  late final _ovlConfig = _lib?.lookupFunction<Void Function(Int32, Float, Float, Int32, Int32), void Function(int, double, double, int, int)>(
      'pn_overlay_config');
  late final _ovlBegin = _lib?.lookupFunction<Void Function(Pointer<Utf8>, Uint32), void Function(Pointer<Utf8>, int)>('pn_overlay_roster_begin');
  late final _ovlAdd = _lib?.lookupFunction<Void Function(Uint32, Pointer<Utf8>, Uint32, Int32), void Function(int, Pointer<Utf8>, int, int)>(
      'pn_overlay_roster_add');
  late final _ovlCommit = _lib?.lookupFunction<Void Function(), void Function()>('pn_overlay_roster_commit');
  late final _ovlAvatar = _lib?.lookupFunction<Void Function(Uint32, Pointer<Uint8>, Int32), void Function(int, Pointer<Uint8>, int)>(
      'pn_overlay_avatar');
  late final _ovlReset = _lib?.lookupFunction<Void Function(), void Function()>('pn_overlay_reset_position');

  void overlayShow(bool on) => _ovlShow?.call(on ? 1 : 0);
  void overlayConfig({required bool speakingOnly, required double opacity, required double scale, required bool locked, required bool hideFocused}) =>
      _ovlConfig?.call(speakingOnly ? 1 : 0, opacity, scale, locked ? 1 : 0, hideFocused ? 1 : 0);
  void overlayResetPosition() => _ovlReset?.call();

  /// Replaces the overlay roster: (id, name, argb, flags) with flags 1 mute, 2 deaf, 4 server mute.
  void overlayRoster(String title, int me, List<(int, String, int, int)> users) {
    final begin = _ovlBegin, add = _ovlAdd, commit = _ovlCommit;
    if (begin == null || add == null || commit == null) return;
    final t = title.toNativeUtf8();
    begin(t, me);
    malloc.free(t);
    for (final (id, name, argb, flags) in users) {
      final n = name.toNativeUtf8();
      add(id, n, argb, flags);
      malloc.free(n);
    }
    commit();
  }

  void overlayAvatar(int id, Uint8List? bytes) {
    final f = _ovlAvatar;
    if (f == null) return;
    if (bytes == null || bytes.isEmpty) return f(id, nullptr, 0);
    final p = malloc<Uint8>(bytes.length);
    p.asTypedList(bytes.length).setAll(0, bytes);
    f(id, p, bytes.length);
    malloc.free(p);
  }

  late final _flash = _lib?.lookupFunction<Void Function(), void Function()>('pn_flash_window');
  void flashWindow() => _flash?.call();

  late final _prewarm = _lib?.lookupFunction<Void Function(Pointer<Int32>, Int32), void Function(Pointer<Int32>, int)>('pn_vc_ai_prewarm');

  /// Latency presets compiled in the background so switching between them is instant.
  void prewarmAi(List<(int, int)> presets) {
    final f = _prewarm;
    if (f == null) return;
    final p = malloc<Int32>(presets.length * 2 + 1);
    for (var i = 0; i < presets.length; i++) {
      p[2 * i] = presets[i].$1;
      p[2 * i + 1] = presets[i].$2;
    }
    f(p, presets.length);
    malloc.free(p);
  }

  void setUserVolume(int user, double v) {
    if (_lib != null) _userVolume(user, v);
  }

  /// Received voice frame: [u16 seq][opus].
  void pushVoice(int user, Uint8List data) {
    if (_lib == null || data.length < 3) return;
    final p = malloc<Uint8>(data.length);
    p.asTypedList(data.length).setAll(0, data);
    _playPush(user, p, data.length);
    malloc.free(p);
  }

  void removeSpeaker(int user) => _lib == null ? null : _playRemove(user);
  void clearSpeakers() => _lib == null ? null : _playClear();

  final Pointer<Float> _lv = malloc<Float>(5);

  /// [mic, tx, vad, out, gate]
  List<double> levels() {
    if (_lib == null) return const [0, 0, 0, 0, 0];
    final n = _levels(_lv, 5);
    return [for (var i = 0; i < n; i++) _lv[i]];
  }

  final Pointer<Uint32> _uu = malloc<Uint32>(64);
  final Pointer<Float> _ul = malloc<Float>(64);

  Map<int, double> userLevels() {
    if (_lib == null) return const {};
    final n = _userLevels(_uu, _ul, 64);
    return {for (var i = 0; i < n; i++) _uu[i]: _ul[i]};
  }

  bool enableHotkeys(bool on) => _lib != null && _hotkeysEnable(on ? 1 : 0) == 0;
  void setHotkey(int slot, int vk, int mods) => _lib == null ? null : _hotkeySet(slot, vk, mods);

  String keyName(int vk) => _lib == null ? (vk == 0 ? '' : 'VK $vk') : _takeString(_keyName(vk));

  Map<String, dynamic> gpuInfo() {
    if (_lib == null) return {'adapters': [], 'providers': [], 'ortError': loadError ?? ''};
    try {
      return jsonDecode(_takeString(_gpuInfo())) as Map<String, dynamic>;
    } catch (_) {
      return {'adapters': [], 'providers': []};
    }
  }

  void configureAi({required String provider, String model = '', int blockMs = 200, int extraMs = 300, int speaker = 0}) {
    if (_lib == null) return;
    final p = provider.toNativeUtf8(), m = model.toNativeUtf8();
    try {
      _vcConfig(p, m, blockMs, extraMs, speaker);
    } finally {
      malloc.free(p);
      malloc.free(m);
    }
  }

  void unloadAi() => _lib == null ? null : _vcUnload();

  Map<String, dynamic> vcStatus() {
    if (_lib == null) return {'state': 0};
    try {
      return jsonDecode(_takeString(_vcStatus())) as Map<String, dynamic>;
    } catch (_) {
      return {'state': 0};
    }
  }

  Uint8List? _dpapi(Uint8List data, bool protect) {
    if (_lib == null) return null;
    final p = malloc<Uint8>(data.isEmpty ? 1 : data.length);
    final outLen = malloc<Int32>();
    try {
      p.asTypedList(data.length).setAll(0, data);
      final r = protect ? _protect(p, data.length, outLen) : _unprotect(p, data.length, outLen);
      if (r == nullptr) return null;
      final out = Uint8List.fromList(r.asTypedList(outLen.value));
      _free(r.cast());
      return out;
    } finally {
      malloc.free(p);
      malloc.free(outLen);
    }
  }

  // ---- screen sharing (capture + H.264 encode) and decoding of remote streams

  late final _scrSources = _lib?.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('pn_screen_sources');
  late final _scrThumb = _lib?.lookupFunction<Pointer<Uint8> Function(Pointer<Utf8>, Int32, Int32, Pointer<Int32>, Pointer<Int32>),
      Pointer<Uint8> Function(Pointer<Utf8>, int, int, Pointer<Int32>, Pointer<Int32>)>('pn_screen_thumbnail');
  late final _scrStart = _lib?.lookupFunction<Int32 Function(Pointer<Utf8>, Int32, Int32, Int32, Int32), int Function(Pointer<Utf8>, int, int, int, int)>(
      'pn_screen_start');
  late final _scrStatus = _lib?.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('pn_screen_status');
  late final _vidOpen = _lib?.lookupFunction<Int32 Function(Uint32), int Function(int)>('pn_video_open');
  late final _vidClose = _lib?.lookupFunction<Void Function(Uint32), void Function(int)>('pn_video_close');
  late final _vidPush = _lib?.lookupFunction<Void Function(Uint32, Pointer<Uint8>, Int32, Int32), void Function(int, Pointer<Uint8>, int, int)>(
      'pn_video_push');
  late final _vidStats = _lib?.lookupFunction<Pointer<Utf8> Function(Uint32), Pointer<Utf8> Function(int)>('pn_video_stats');

  Map<String, dynamic> _json(Pointer<Utf8> Function()? f) {
    if (f == null) return {};
    try {
      return jsonDecode(_takeString(f())) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// {"monitors": [{id, name, w, h, primary}], "windows": [{id, title, exe}]}
  Map<String, dynamic> screenSources() => _json(_scrSources);

  /// RGBA thumbnail of a source.
  (Uint8List, int, int)? screenThumbnail(String id, {int maxW = 320, int maxH = 180}) {
    final f = _scrThumb;
    if (f == null) return null;
    final p = id.toNativeUtf8();
    final w = malloc<Int32>(), h = malloc<Int32>();
    try {
      final r = f(p, maxW, maxH, w, h);
      if (r == nullptr) return null;
      final out = Uint8List.fromList(r.asTypedList(w.value * h.value * 4));
      _free(r.cast());
      return (out, w.value, h.value);
    } finally {
      malloc.free(p);
      malloc.free(w);
      malloc.free(h);
    }
  }

  /// Starts capture + encoding; the result arrives as [NativeEv.screen].
  bool screenStart(String id, {int maxW = 1920, int maxH = 1080, int fps = 30, int kbps = 5000}) {
    final f = _scrStart;
    if (f == null) return false;
    final p = id.toNativeUtf8();
    try {
      return f(p, maxW, maxH, fps, kbps) == 0;
    } finally {
      malloc.free(p);
    }
  }

  void screenStop() => _seti0('pn_screen_stop');
  void screenKeyframe() => _seti0('pn_screen_keyframe');
  void screenSetBitrate(int kbps) => _seti('pn_screen_set_bitrate', kbps);
  Map<String, dynamic> screenStatus() => _json(_scrStatus);

  void _seti0(String n) {
    if (_lib == null) return;
    (_void[n] ??= _lib.lookupFunction<Void Function(), void Function()>(n))();
  }

  final _void = <String, void Function()>{};

  bool videoOpen(int id) => (_vidOpen?.call(id) ?? -1) == 0;
  void videoClose(int id) => _vidClose?.call(id);

  /// One complete H.264 access unit (Annex-B) of stream [id].
  void videoPush(int id, Uint8List au, {required bool keyframe}) {
    final f = _vidPush;
    if (f == null || au.isEmpty) return;
    final p = malloc<Uint8>(au.length);
    p.asTypedList(au.length).setAll(0, au);
    f(id, p, au.length, keyframe ? 1 : 0);
    malloc.free(p);
  }

  Map<String, dynamic> videoStats(int id) {
    final f = _vidStats;
    return f == null ? {} : _json(() => f(id));
  }

  /// Encrypts with Windows DPAPI (bound to the current Windows user).
  Uint8List? protect(Uint8List data) => _dpapi(data, true);
  Uint8List? unprotect(Uint8List data) => _dpapi(data, false);
}
