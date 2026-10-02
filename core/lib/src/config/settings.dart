import 'package:path/path.dart' as p;

import '../common/json_file.dart';
import '../common/os.dart';
import '../net/source.dart';

/// Global launcher settings (`%APPDATA%\CML\settings.json`).
class LauncherSettings {
  // ---- game ----
  List<String> gameDirs = [Os.defaultMinecraftDir];
  String gameDir = Os.defaultMinecraftDir;
  String? selectedVersion;

  /// null = automatic per version.
  String? javaPath;
  bool autoMemory = true;
  int memoryMb = 4096;
  bool isolateVersions = true;
  int? windowWidth;
  int? windowHeight;
  bool fullscreen = false;
  String jvmArgs = '';
  String gameArgs = '';
  String preLaunchCommand = '';
  String windowTitle = '';

  /// After launch: 0 keep, 1 minimise, 2 close CML.
  int afterLaunch = 1;
  bool optimizeMemoryBeforeLaunch = false;

  /// Also purge the system standby list when optimising (needs administrator).
  bool purgeStandbyMemory = false;

  // ---- downloads ----
  DownloadSource downloadSource = DownloadSource.auto;
  ContentSource contentSource = ContentSource.mcim;
  int downloadThreads = 32;
  String curseforgeKey = '';
  String githubMirror = '';

  /// Route launcher traffic through the built-in proxy when it is running.
  bool useBuiltInProxy = false;

  // ---- account ----
  bool verifyLoginSsl = true;
  String msaClientId = '';

  // ---- launcher ----
  bool autoUpdate = true;
  bool autoUpdateTools = true;
  String theme = 'chtholly';
  String language = 'zh';
  bool darkMode = false;
  int? accentColor;
  double uiScale = 1.0;
  String backgroundImage = '';

  // ---- multiplayer ----
  List<String> cmlsServers = [];
  String? lastCmlsServer;

  static String get path => p.join(Os.cmlHome, 'settings.json');

  Map<String, dynamic> toJson() => {
        'gameDirs': gameDirs,
        'gameDir': gameDir,
        'selectedVersion': selectedVersion,
        'javaPath': javaPath,
        'autoMemory': autoMemory,
        'memoryMb': memoryMb,
        'isolateVersions': isolateVersions,
        'windowWidth': windowWidth,
        'windowHeight': windowHeight,
        'fullscreen': fullscreen,
        'jvmArgs': jvmArgs,
        'gameArgs': gameArgs,
        'preLaunchCommand': preLaunchCommand,
        'windowTitle': windowTitle,
        'afterLaunch': afterLaunch,
        'optimizeMemoryBeforeLaunch': optimizeMemoryBeforeLaunch,
        'purgeStandbyMemory': purgeStandbyMemory,
        'downloadSource': downloadSource.name,
        'contentSource': contentSource.name,
        'downloadThreads': downloadThreads,
        'curseforgeKey': curseforgeKey,
        'githubMirror': githubMirror,
        'useBuiltInProxy': useBuiltInProxy,
        'verifyLoginSsl': verifyLoginSsl,
        'msaClientId': msaClientId,
        'autoUpdate': autoUpdate,
        'autoUpdateTools': autoUpdateTools,
        'theme': theme,
        'language': language,
        'darkMode': darkMode,
        'accentColor': accentColor,
        'uiScale': uiScale,
        'backgroundImage': backgroundImage,
        'cmlsServers': cmlsServers,
        'lastCmlsServer': lastCmlsServer,
      };

  void fromJson(Map j) {
    T v<T>(String k, T d) => j[k] is T ? j[k] as T : d;
    gameDirs = [for (final x in v<List>('gameDirs', gameDirs)) '$x'];
    gameDir = v('gameDir', gameDir);
    if (!gameDirs.contains(gameDir)) gameDirs.add(gameDir);
    selectedVersion = j['selectedVersion'] as String?;
    javaPath = j['javaPath'] as String?;
    autoMemory = v('autoMemory', autoMemory);
    memoryMb = v('memoryMb', memoryMb);
    isolateVersions = v('isolateVersions', isolateVersions);
    windowWidth = j['windowWidth'] as int?;
    windowHeight = j['windowHeight'] as int?;
    fullscreen = v('fullscreen', fullscreen);
    jvmArgs = v('jvmArgs', jvmArgs);
    gameArgs = v('gameArgs', gameArgs);
    preLaunchCommand = v('preLaunchCommand', preLaunchCommand);
    windowTitle = v('windowTitle', windowTitle);
    afterLaunch = v('afterLaunch', afterLaunch);
    optimizeMemoryBeforeLaunch = v('optimizeMemoryBeforeLaunch', optimizeMemoryBeforeLaunch);
    purgeStandbyMemory = v('purgeStandbyMemory', purgeStandbyMemory);
    downloadSource = DownloadSource.values.firstWhere((e) => e.name == j['downloadSource'], orElse: () => downloadSource);
    contentSource = ContentSource.values.firstWhere((e) => e.name == j['contentSource'], orElse: () => contentSource);
    downloadThreads = v('downloadThreads', downloadThreads);
    curseforgeKey = v('curseforgeKey', curseforgeKey);
    githubMirror = v('githubMirror', githubMirror);
    useBuiltInProxy = v('useBuiltInProxy', useBuiltInProxy);
    verifyLoginSsl = v('verifyLoginSsl', verifyLoginSsl);
    msaClientId = v('msaClientId', msaClientId);
    autoUpdate = v('autoUpdate', autoUpdate);
    autoUpdateTools = v('autoUpdateTools', autoUpdateTools);
    theme = v('theme', theme);
    language = v('language', language);
    darkMode = v('darkMode', darkMode);
    accentColor = j['accentColor'] as int?;
    uiScale = (j['uiScale'] as num?)?.toDouble() ?? uiScale;
    backgroundImage = v('backgroundImage', backgroundImage);
    cmlsServers = [for (final x in v<List>('cmlsServers', cmlsServers)) '$x'];
    lastCmlsServer = j['lastCmlsServer'] as String?;
  }

  Future<void> load() async {
    final j = await JsonFile.read(path);
    if (j is Map) fromJson(j);
  }

  Future<void> save() => JsonFile.write(path, toJson());
}

/// Per-version overrides (`versions/<id>/cml.json`). null fields fall back to [LauncherSettings].
class InstanceSettings {
  String? javaPath;
  bool? autoMemory;
  int? memoryMb;
  bool? isolate;
  String? jvmArgs;
  String? gameArgs;
  String? joinServer;
  String? icon;
  String? note;

  Map<String, dynamic> toJson() => {
        'javaPath': javaPath,
        'autoMemory': autoMemory,
        'memoryMb': memoryMb,
        'isolate': isolate,
        'jvmArgs': jvmArgs,
        'gameArgs': gameArgs,
        'joinServer': joinServer,
        'icon': icon,
        'note': note,
      };

  static Future<InstanceSettings> load(String path) async {
    final j = await JsonFile.read(path);
    final s = InstanceSettings();
    if (j is Map) {
      s
        ..javaPath = j['javaPath'] as String?
        ..autoMemory = j['autoMemory'] as bool?
        ..memoryMb = j['memoryMb'] as int?
        ..isolate = j['isolate'] as bool?
        ..jvmArgs = j['jvmArgs'] as String?
        ..gameArgs = j['gameArgs'] as String?
        ..joinServer = j['joinServer'] as String?
        ..icon = j['icon'] as String?
        ..note = j['note'] as String?;
    }
    return s;
  }

  Future<void> save(String path) => JsonFile.write(path, toJson());
}
