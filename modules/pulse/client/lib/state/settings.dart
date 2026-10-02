import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../native/native.dart';

/// AI voice changer latency presets: (label, block ms, context ms).
const vcLatencyPresets = [
  ('低延迟 ≈0.25 s', 100, 300),
  ('均衡 ≈0.35 s', 200, 300),
  ('高音质 ≈0.6 s', 300, 500),
];

/// Hotkey binding (Windows virtual-key + modifier mask).
class Binding {
  final int vk, mods;
  const Binding(this.vk, this.mods);
  static const none = Binding(0, 0);
  Map<String, dynamic> toJson() => {'vk': vk, 'mods': mods};
  factory Binding.fromJson(Object? j) => j is Map ? Binding((j['vk'] as num?)?.toInt() ?? 0, (j['mods'] as num?)?.toInt() ?? 0) : none;
}

/// A server the user has used, with the pinned identity key (TOFU) and an
/// encrypted session token.
class SavedServer {
  String address;
  String name;
  String username;
  String pinnedKey; // base64 X25519 static key
  String tokenBlob; // DPAPI-encrypted session token (base64), '' = logged out
  int lastUsed;
  SavedServer(this.address, {this.name = '', this.username = '', this.pinnedKey = '', this.tokenBlob = '', this.lastUsed = 0});

  Map<String, dynamic> toJson() =>
      {'address': address, 'name': name, 'user': username, 'pin': pinnedKey, 'tok': tokenBlob, 'used': lastUsed};
  factory SavedServer.fromJson(Map<String, dynamic> j) => SavedServer('${j['address']}',
      name: '${j['name'] ?? ''}',
      username: '${j['user'] ?? ''}',
      pinnedKey: '${j['pin'] ?? ''}',
      tokenBlob: '${j['tok'] ?? ''}',
      lastUsed: (j['used'] as num?)?.toInt() ?? 0);
}

/// All client preferences, persisted as JSON in %APPDATA%\Pulse\settings.json.
/// Session tokens inside are encrypted with DPAPI (only this Windows user can
/// decrypt them); if DPAPI is unavailable tokens are not persisted at all.
class Settings {
  // appearance
  String theme = 'dark';
  int accent = 0;
  double uiScale = 1.0;
  bool compact = false;
  bool showSeconds = false;
  bool closeToTray = true;

  // "who is speaking" overlay
  bool overlay = true; // shown while in a voice channel (closing it with × turns this off)
  bool overlaySpeakingOnly = false;
  double overlayOpacity = 0.85;
  double overlayScale = 1.0;
  bool overlayLocked = false; // click-through
  bool overlayHideFocused = false; // hide while Pulse itself is in the foreground (off: always visible)
  bool trayHintShown = false;

  // audio devices ('' = system default)
  String inputDevice = '';
  String outputDevice = '';
  double inputGain = 1.0;
  double outputVolume = 1.0;
  double soundVolume = 0.6;
  bool sounds = true;
  bool warnMutedTalk = true;

  // voice processing
  int inputMode = InputMode.vad;
  double vadThreshold = 0.5;
  int noiseSuppression = 2;
  int bitrate = 64000;
  int pttReleaseMs = 200;

  // hotkeys
  bool globalHotkeys = true;
  Binding pttKey = const Binding(0xC0, 0); // ` key
  Binding muteKey = const Binding(0x4D, 3); // Ctrl+Shift+M
  Binding deafenKey = const Binding(0x44, 3); // Ctrl+Shift+D
  Binding vcKey = Binding.none;
  Binding overlayKey = Binding.none;

  // voice changer
  int vcMode = VcMode.off;
  double vcPitch = 0;
  bool vcRobot = false;
  String vcProvider = 'auto';
  String vcModel = ''; // '' = built-in base voice
  int vcSpeaker = 0;
  int vcBlockMs = 200;
  int vcExtraMs = 300;
  int vcKeepLoadedMin = 10; // keep AI models loaded after switching away (0 = unload now, -1 = forever)

  // notifications
  bool notifyMentions = true;
  bool notifyAll = false;

  // per-user local volume (server address|user id)
  Map<String, double> userVolumes = {};

  List<SavedServer> servers = [];
  String lastServer = '';

  late File _file;
  Native? native;

  static Future<Settings> load(Native native) async {
    final s = Settings()..native = native;
    Directory dir;
    try {
      final base = Platform.environment['APPDATA'];
      dir = base != null ? Directory('$base\\Pulse') : await getApplicationSupportDirectory();
    } catch (_) {
      dir = Directory.systemTemp;
    }
    dir.createSync(recursive: true);
    s._file = File('${dir.path}${Platform.pathSeparator}settings.json');
    if (s._file.existsSync()) {
      try {
        s._fromJson(jsonDecode(s._file.readAsStringSync()) as Map<String, dynamic>);
      } catch (_) {}
    }
    return s;
  }

  /// Throw-away settings in a fresh temp directory (tests).
  static Settings memory() {
    final dir = Directory.systemTemp.createTempSync('pulse_settings');
    return Settings().._file = File('${dir.path}${Platform.pathSeparator}settings.json');
  }

  String get directory => _file.parent.path;

  void _fromJson(Map<String, dynamic> j) {
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    double dv(String k, double d) => j[k] is num ? (j[k] as num).toDouble() : d;
    theme = v('theme', theme);
    accent = v('accent', accent);
    uiScale = dv('uiScale', uiScale);
    compact = v('compact', compact);
    showSeconds = v('showSeconds', showSeconds);
    closeToTray = v('closeToTray', closeToTray);
    overlay = v('overlay', overlay);
    overlaySpeakingOnly = v('overlaySpeakingOnly', overlaySpeakingOnly);
    overlayOpacity = dv('overlayOpacity', overlayOpacity);
    overlayScale = dv('overlayScale', overlayScale);
    overlayLocked = v('overlayLocked', overlayLocked);
    overlayHideFocused = v('overlayHideFocused', overlayHideFocused);
    trayHintShown = v('trayHintShown', trayHintShown);
    inputDevice = v('inputDevice', inputDevice);
    outputDevice = v('outputDevice', outputDevice);
    inputGain = dv('inputGain', inputGain);
    outputVolume = dv('outputVolume', outputVolume);
    soundVolume = dv('soundVolume', soundVolume);
    sounds = v('sounds', sounds);
    warnMutedTalk = v('warnMutedTalk', warnMutedTalk);
    inputMode = v('inputMode', inputMode);
    vadThreshold = dv('vadThreshold', vadThreshold);
    noiseSuppression = v('noiseSuppression', noiseSuppression);
    bitrate = v('bitrate', bitrate);
    pttReleaseMs = v('pttReleaseMs', pttReleaseMs);
    globalHotkeys = v('globalHotkeys', globalHotkeys);
    if (j.containsKey('pttKey')) pttKey = Binding.fromJson(j['pttKey']);
    if (j.containsKey('muteKey')) muteKey = Binding.fromJson(j['muteKey']);
    if (j.containsKey('deafenKey')) deafenKey = Binding.fromJson(j['deafenKey']);
    if (j.containsKey('vcKey')) vcKey = Binding.fromJson(j['vcKey']);
    if (j.containsKey('overlayKey')) overlayKey = Binding.fromJson(j['overlayKey']);
    vcMode = v('vcMode', vcMode);
    vcPitch = dv('vcPitch', vcPitch);
    vcRobot = v('vcRobot', vcRobot);
    vcProvider = v('vcProvider', vcProvider);
    vcModel = v('vcModel', vcModel);
    vcSpeaker = v('vcSpeaker', vcSpeaker);
    vcBlockMs = v('vcBlockMs', vcBlockMs);
    vcExtraMs = v('vcExtraMs', vcExtraMs);
    vcKeepLoadedMin = v('vcKeepLoadedMin', vcKeepLoadedMin);
    notifyMentions = v('notifyMentions', notifyMentions);
    notifyAll = v('notifyAll', notifyAll);
    final uv = j['userVolumes'];
    if (uv is Map) userVolumes = {for (final e in uv.entries) '${e.key}': (e.value as num).toDouble()};
    final sv = j['servers'];
    if (sv is List) servers = [for (final x in sv) if (x is Map<String, dynamic>) SavedServer.fromJson(x)];
    lastServer = v('lastServer', lastServer);
  }

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'accent': accent,
        'uiScale': uiScale,
        'compact': compact,
        'showSeconds': showSeconds,
        'closeToTray': closeToTray,
        'overlay': overlay,
        'overlaySpeakingOnly': overlaySpeakingOnly,
        'overlayOpacity': overlayOpacity,
        'overlayScale': overlayScale,
        'overlayLocked': overlayLocked,
        'overlayHideFocused': overlayHideFocused,
        'trayHintShown': trayHintShown,
        'inputDevice': inputDevice,
        'outputDevice': outputDevice,
        'inputGain': inputGain,
        'outputVolume': outputVolume,
        'soundVolume': soundVolume,
        'sounds': sounds,
        'warnMutedTalk': warnMutedTalk,
        'inputMode': inputMode,
        'vadThreshold': vadThreshold,
        'noiseSuppression': noiseSuppression,
        'bitrate': bitrate,
        'pttReleaseMs': pttReleaseMs,
        'globalHotkeys': globalHotkeys,
        'pttKey': pttKey.toJson(),
        'muteKey': muteKey.toJson(),
        'deafenKey': deafenKey.toJson(),
        'vcKey': vcKey.toJson(),
        'overlayKey': overlayKey.toJson(),
        'vcMode': vcMode,
        'vcPitch': vcPitch,
        'vcRobot': vcRobot,
        'vcProvider': vcProvider,
        'vcModel': vcModel,
        'vcSpeaker': vcSpeaker,
        'vcBlockMs': vcBlockMs,
        'vcExtraMs': vcExtraMs,
        'vcKeepLoadedMin': vcKeepLoadedMin,
        'notifyMentions': notifyMentions,
        'notifyAll': notifyAll,
        'userVolumes': userVolumes,
        'servers': [for (final s in servers) s.toJson()],
        'lastServer': lastServer,
      };

  void save() {
    try {
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()), flush: true);
      tmp.renameSync(_file.path);
    } catch (_) {}
  }

  SavedServer? find(String address) {
    final a = address.trim().toLowerCase();
    for (final s in servers) {
      if (s.address.toLowerCase() == a) return s;
    }
    return null;
  }

  /// Adds [s] to the saved list (only after a successful connection).
  void remember(SavedServer s) {
    if (!servers.contains(s)) servers.add(s);
  }

  String? tokenFor(SavedServer s) {
    if (s.tokenBlob.isEmpty) return null;
    try {
      final plain = native?.unprotect(base64.decode(s.tokenBlob));
      return plain == null ? null : utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  void setToken(SavedServer s, String? token) {
    if (token == null) {
      s.tokenBlob = '';
      return;
    }
    final enc = native?.protect(Uint8List.fromList(utf8.encode(token)));
    s.tokenBlob = enc == null ? '' : base64.encode(enc);
  }
}
