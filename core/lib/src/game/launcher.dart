import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/os.dart';
import 'game_dir.dart';
import 'installer.dart';
import 'version.dart';

/// Identity passed to the game.
class LaunchIdentity {
  final String name;
  final String uuid; // without dashes
  final String accessToken;
  final String xuid;
  final String userType; // 'msa'
  const LaunchIdentity({required this.name, required this.uuid, required this.accessToken, this.xuid = '0', this.userType = 'msa'});
}

class LaunchOptions {
  final String javaPath;
  final int maxMemoryMb;
  final int minMemoryMb;
  final bool isolated;
  final int? width, height;
  final bool fullscreen;
  final String extraJvmArgs;
  final String extraGameArgs;

  /// Quick play: auto-join a server `host:port` on start.
  final String? joinServer;

  /// Quick play: open a singleplayer world by folder name.
  final String? joinWorld;
  final String launcherName;
  final String windowTitle;

  /// Optional wrapper/pre-launch command.
  final String? preLaunchCommand;

  const LaunchOptions({
    required this.javaPath,
    required this.maxMemoryMb,
    this.minMemoryMb = 256,
    this.isolated = true,
    this.width,
    this.height,
    this.fullscreen = false,
    this.extraJvmArgs = '',
    this.extraGameArgs = '',
    this.joinServer,
    this.joinWorld,
    this.launcherName = 'CML',
    this.windowTitle = '',
    this.preLaunchCommand,
  });
}

/// Builds the java command line for a resolved version.
class LaunchCommand {
  final String java;
  final List<String> args;
  final String workingDir;
  final Map<String, String> env;
  LaunchCommand(this.java, this.args, this.workingDir, this.env);

  /// Command line with the access token masked, for logs / "导出启动脚本".
  String masked(String token) => [java, ...args].map((a) => a.contains(' ') ? '"$a"' : a).join(' ').replaceAll(token, '********');

  /// A .bat script that starts the game without CML.
  String toBatch() {
    final b = StringBuffer('@echo off\r\nchcp 65001 >nul\r\ncd /d "$workingDir"\r\n');
    b.write('"$java" ');
    b.write(args.map((a) => a.contains(' ') || a.contains('&') ? '"${a.replaceAll('"', r'\"')}"' : a).join(' '));
    b.write('\r\npause\r\n');
    return b.toString();
  }
}

class Launcher {
  /// Resolves `${…}` placeholders and rules into a full command line.
  static Future<LaunchCommand> build(GameDir dir, String id, LaunchIdentity who, LaunchOptions o) async {
    final v = await dir.load(id);
    final gameDir = dir.gameDirFor(id, isolated: o.isolated);
    await Directory(gameDir).create(recursive: true);
    final natives = await GameInstaller.extractNatives(dir, id, v);

    final cp = <String>[];
    final seen = <String>{};
    for (final l in v.libraries) {
      if (!l.applies || !l.onClasspath) continue;
      if (l.nativeClassifier != null && l.artifact == null && l.classifiers.isNotEmpty) continue; // natives-only entry
      final path = dir.library(l.path);
      if (seen.add(path.toLowerCase()) && await File(path).exists()) cp.add(path);
    }
    final jar = dir.versionJar(await File(dir.versionJar(id)).exists() ? id : v.jar);
    if (!await File(jar).exists()) throw CmlException('jar_missing', '缺少游戏本体 ${p.basename(jar)}，请先补全文件');
    cp.add(jar);

    final assetsRoot = dir.assetsDir;
    final assetId = v.assetIndex?.id ?? v.assets ?? 'legacy';
    final legacyAssets = assetId == 'legacy' || assetId == 'pre-1.6';
    final vars = <String, String>{
      'auth_player_name': who.name,
      'version_name': id,
      'game_directory': gameDir,
      'assets_root': assetsRoot,
      'game_assets': legacyAssets ? p.join(dir.versionDir(id), 'resources') : p.join(assetsRoot, 'virtual', assetId),
      'assets_index_name': assetId,
      'auth_uuid': who.uuid,
      'auth_access_token': who.accessToken,
      'auth_session': 'token:${who.accessToken}:${who.uuid}',
      'auth_xuid': who.xuid,
      'clientid': '',
      'user_type': who.userType,
      'user_properties': '{}',
      'version_type': o.launcherName,
      'natives_directory': natives,
      'launcher_name': o.launcherName,
      'launcher_version': '0.1',
      'classpath': cp.join(Os.classpathSeparator),
      'classpath_separator': Os.classpathSeparator,
      'library_directory': dir.librariesDir,
      'resolution_width': '${o.width ?? 854}',
      'resolution_height': '${o.height ?? 480}',
      'quickPlayMultiplayer': o.joinServer ?? '',
      'quickPlaySingleplayer': o.joinWorld ?? '',
      'quickPlayPath': p.join(gameDir, 'quickPlay', 'log.json'),
      'primary_jar_name': p.basename(jar),
    };
    String sub(String s) => s.replaceAllMapped(RegExp(r'\$\{([A-Za-z0-9_]+)\}'), (m) => vars[m.group(1)] ?? m.group(0)!);

    final features = LaunchFeatures(
      customResolution: o.width != null && o.height != null,
      quickPlayMultiplayer: o.joinServer != null,
      quickPlaySingleplayer: o.joinWorld != null,
    );

    final jvm = <String>[
      '-Xmx${o.maxMemoryMb}m',
      '-Xms${o.minMemoryMb.clamp(64, o.maxMemoryMb)}m',
      '-Dfile.encoding=UTF-8',
      '-Dstdout.encoding=UTF-8',
      '-Dstderr.encoding=UTF-8',
      '-Dlog4j2.formatMsgNoLookups=true',
      '-XX:+UseG1GC',
      '-XX:-UseAdaptiveSizePolicy',
      '-XX:-OmitStackTraceInFastThrow',
      '-Dfml.ignoreInvalidMinecraftCertificates=true',
      '-Dfml.ignorePatchDiscrepancies=true',
      '-XX:HeapDumpPath=MojangTricksIntelDriversForPerformance_javaw.exe_minecraft.exe.heapdump',
    ];
    if (v.jvmArgs.isEmpty) {
      jvm.addAll(['-Djava.library.path=$natives', '-cp', vars['classpath']!]);
    } else {
      jvm.addAll(_expand(v.jvmArgs, features).map(sub));
    }
    if (v.loggingArgument != null && v.loggingId != null) {
      final cfg = p.join(assetsRoot, 'log_configs', v.loggingId!);
      if (await File(cfg).exists()) jvm.add(v.loggingArgument!.replaceAll(r'${path}', cfg));
    }
    jvm.addAll(splitArgs(o.extraJvmArgs));

    final game = <String>[];
    if (v.usesLegacyArgs) {
      game.addAll(splitArgs(v.legacyArgs!).map(sub));
    } else {
      game.addAll(_expand(v.gameArgs, features).map(sub));
    }
    if (o.width != null && o.height != null && v.usesLegacyArgs) game.addAll(['--width', '${o.width}', '--height', '${o.height}']);
    if (o.fullscreen) game.add('--fullscreen');
    if (o.joinServer != null && !_hasQuickPlay(v)) {
      final hp = o.joinServer!.split(':');
      game.addAll(['--server', hp[0], '--port', hp.length > 1 ? hp[1] : '25565']);
    }
    game.addAll(splitArgs(o.extraGameArgs));

    final args = <String>[...jvm, v.mainClass, ...game];
    return LaunchCommand(o.javaPath, args, gameDir, {
      'APPDATA': Os.appData,
    });
  }

  static bool _hasQuickPlay(GameVersion v) => v.gameArgs.any((a) => jsonEncode(a).contains('quickPlayMultiplayer'));

  static List<String> _expand(List<Object> args, LaunchFeatures f) {
    final out = <String>[];
    for (final a in args) {
      if (a is String) {
        out.add(a);
      } else if (a is Map) {
        if (!Rules.allows(a['rules'], f)) continue;
        final val = a['value'];
        if (val is String) out.add(val);
        if (val is List) out.addAll(val.map((e) => '$e'));
      }
    }
    return out;
  }

  /// Splits a user-entered argument string, honouring double quotes.
  static List<String> splitArgs(String s) {
    final out = <String>[];
    final cur = StringBuffer();
    var q = false;
    var has = false;
    for (final ch in s.split('')) {
      if (ch == '"') {
        q = !q;
        has = true;
      } else if (!q && (ch == ' ' || ch == '\n' || ch == '\t')) {
        if (has || cur.isNotEmpty) out.add(cur.toString());
        cur.clear();
        has = false;
      } else {
        cur.write(ch);
      }
    }
    if (has || cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  /// Starts the game. Lines from stdout/stderr go to [onLog].
  static Future<GameProcess> start(LaunchCommand cmd, {void Function(String line)? onLog, String? preLaunchCommand}) async {
    if (preLaunchCommand != null && preLaunchCommand.trim().isNotEmpty) {
      final r = await Process.run('cmd', ['/c', preLaunchCommand], workingDirectory: cmd.workingDir);
      onLog?.call('[CML] 启动前命令退出码 ${r.exitCode}');
    }
    // prefer javaw to avoid a console window; keep java.exe when explicitly chosen
    final proc = await Process.start(cmd.java, cmd.args, workingDirectory: cmd.workingDir, environment: cmd.env);
    final gp = GameProcess(proc);
    for (final s in [proc.stdout, proc.stderr]) {
      s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((l) {
        gp._onLine(l);
        onLog?.call(l);
      });
    }
    return gp;
  }
}

/// A running game.
class GameProcess {
  final Process process;
  final _ready = Completer<void>();
  final List<String> tail = [];
  final DateTime started = DateTime.now();
  GameProcess(this.process);

  int get pid => process.pid;
  Future<int> get exitCode => process.exitCode;

  /// Completes once the game window is likely up (LWJGL/sound/"Setting user" lines), or after 60s.
  Future<void> get ready => _ready.future.timeout(const Duration(seconds: 60), onTimeout: () {});

  void _onLine(String l) {
    tail.add(l);
    if (tail.length > 400) tail.removeAt(0);
    if (!_ready.isCompleted &&
        (l.contains('Setting user:') || l.contains('LWJGL Version') || l.contains('Backend library:') || l.contains('OpenAL initialized'))) {
      _ready.complete();
    }
  }

  void kill() => process.kill();

  /// Crash analysis from the last log lines.
  String? diagnose() => CrashAnalyzer.analyze(tail.join('\n'));
}

/// Recognises common crash causes (subset of PCL's analyzer).
abstract class CrashAnalyzer {
  static String? analyze(String log) {
    const rules = <(String, String)>[
      ('java.lang.OutOfMemoryError', '内存不足：请增加分配给游戏的内存，或减少 Mod/光影。'),
      ('UnsupportedClassVersionError', 'Java 版本过低：请在设置中选择更高版本的 Java。'),
      ('has been compiled by a more recent version of the Java Runtime', 'Java 版本过低：请在设置中选择更高版本的 Java。'),
      ('Could not reserve enough space', '内存分配过多或使用了 32 位 Java：请降低内存或改用 64 位 Java。'),
      ('Pixel format not accelerated', '显卡驱动不支持 OpenGL：请更新显卡驱动。'),
      ('GLFW error 65542', '显卡驱动不支持 OpenGL：请更新显卡驱动。'),
      ('Couldn\'t set pixel format', '显卡驱动不支持 OpenGL：请更新显卡驱动。'),
      ('Mixin apply failed', 'Mod 冲突（Mixin 注入失败）：请检查最近添加的 Mod。'),
      ('DuplicateModsFoundException', '存在重复的 Mod：请删除 mods 文件夹中重复的文件。'),
      ('Found duplicate mods', '存在重复的 Mod：请删除 mods 文件夹中重复的文件。'),
      ('ModResolutionException', 'Mod 缺少前置或版本不兼容：请查看日志中提到的 Mod 依赖。'),
      ('Incompatible mods found', 'Mod 版本不兼容：请查看日志中提到的 Mod。'),
      ('MissingModsException', '缺少前置 Mod：请安装日志中提到的依赖。'),
      ('java.lang.ClassNotFoundException', '游戏文件缺失或 Mod 与当前版本不兼容：请尝试补全文件。'),
      ('Invalid session', '登录已失效：请重新登录微软账号。'),
      ('Failed to verify username', '登录已失效：请重新登录微软账号。'),
      ('EXCEPTION_ACCESS_VIOLATION', '原生代码崩溃：常见于显卡驱动或光影问题，请更新驱动或关闭光影。'),
      ('The directory name is invalid', '游戏路径包含特殊字符：请把游戏移动到纯英文路径。'),
    ];
    for (final r in rules) {
      if (log.contains(r.$1)) return r.$2;
    }
    return null;
  }
}
