import 'dart:io';

import 'package:path/path.dart' as p;

import '../addons/addons.dart';
import '../auth/account_store.dart';
import '../auth/microsoft.dart';
import '../common/errors.dart';
import '../common/task.dart';
import '../config/favorites.dart';
import '../config/settings.dart';
import '../content/content_api.dart';
import '../content/content_installer.dart';
import '../content/exporter.dart';
import '../content/updater.dart';
import '../game/game_dir.dart';
import '../game/installer.dart';
import '../game/launcher.dart';
import '../game/loaders.dart';
import '../game/optifine.dart';
import '../game/version.dart';
import '../java/java.dart';
import '../memory/memory.dart';
import '../net/downloader.dart';
import '../net/http.dart';
import '../net/source.dart';
import '../proxy/proxy.dart';
import '../tools/chunker.dart';
import '../tunnel/client.dart';
import '../update/self_update.dart';

/// Wires every service together; the Flutter UI holds a single instance.
class CmlContext {
  final LauncherSettings settings = LauncherSettings();
  final Http http = Http();
  late final Downloader downloader = Downloader(http);
  late final GameInstaller installer = GameInstaller(http, downloader);
  late final LoaderInstaller loaders = LoaderInstaller(http, downloader);
  late final OptiFineInstaller optifine = OptiFineInstaller(http, downloader);
  late final ContentUpdater contentUpdater = ContentUpdater(content, downloader);
  late final InstanceExporter exporter = InstanceExporter(content);
  late final ContentApi content = ContentApi(http);
  late final ContentInstaller contentInstaller = ContentInstaller(content, downloader, installer, loaders);
  late final MicrosoftAuth auth = MicrosoftAuth(http);
  final AccountStore accounts = AccountStore();
  final JavaManager java = JavaManager();
  late final JavaDownloader javaDownloader = JavaDownloader(http, downloader);
  late final ProxyService proxy = ProxyService(http);
  late final ChunkerTool chunker = ChunkerTool(http);
  late final ClashVergeApp clashVerge = ClashVergeApp(http);
  late final SelfUpdater updater = SelfUpdater(http);
  late final AddonManager addons = AddonManager(http);
  final KnownServers knownServers = KnownServers();
  final Favorites favorites = Favorites();

  GameDir get gameDir => GameDir(settings.gameDir);

  Future<void> init() async {
    await settings.load();
    await accounts.load();
    await java.load();
    await proxy.load();
    await knownServers.load();
    await favorites.load();
    applySettings();
    if (java.installs.isEmpty) await java.scan();
  }

  /// Pushes settings into services. Call after changing settings.
  void applySettings() {
    downloader
      ..source = settings.downloadSource
      ..concurrency = settings.downloadThreads;
    content
      ..source = settings.contentSource
      ..curseforgeKey = settings.curseforgeKey;
    auth.verifySsl = settings.verifyLoginSsl;
    if (settings.msaClientId.isNotEmpty) MsaConfig.clientId = settings.msaClientId;
    Mirrors.githubPrefix = settings.githubMirror;
    http.setProxy(settings.useBuiltInProxy && proxy.running ? proxy.proxyAddress : null);
  }

  /// Picks Java for [v] honouring instance → global → automatic.
  Future<JavaInstall> javaFor(GameVersion v, InstanceSettings inst, {Task? task}) async {
    final chosen = inst.javaPath ?? settings.javaPath;
    if (chosen != null && chosen.isNotEmpty) {
      final j = java.installs.where((i) => p.equals(i.path, chosen)).firstOrNull ?? await JavaManager.probe(chosen);
      if (j != null) return j;
    }
    final need = v.requiredJava;
    final strict = need <= 8 && v.loaders.any((l) => l == ModLoader.forge);
    final picked = java.pick(need, strictLegacy: strict);
    if (picked != null) return picked;
    // none installed: download automatically
    task?.update(detail: '未找到 Java $need，正在自动下载', progress: -1);
    final major = JavaDownloader.majors.firstWhere((m) => m >= need, orElse: () => need);
    final exe = await javaDownloader.install(await javaDownloader.latest(major), task: task);
    final j = await java.addManual(exe);
    if (j == null) throw CmlException('java_missing', '无法使用下载的 Java $major');
    return j;
  }

  /// Full launch: refresh account → complete files → choose Java/memory → start.
  Future<GameProcess> launch(String versionId, {void Function(String)? onLog, Task? task, String? joinServer}) async {
    var acc = accounts.selected ?? (throw const CmlException('no_account', '请先登录微软账号'));
    task?.update(detail: '检查账号', progress: -1);
    acc = await auth.ensureValid(acc);
    accounts.upsert(acc);
    await accounts.save();

    final dir = gameDir;
    task?.update(detail: '补全游戏文件', progress: 0);
    await installer.completeFiles(dir, versionId, task: task);
    final v = await dir.load(versionId);
    final inst = await InstanceSettings.load(dir.instanceConfig(versionId));
    final isolate = inst.isolate ?? settings.isolateVersions;
    final javaInst = await javaFor(v, inst, task: task);

    var mem = inst.memoryMb ?? settings.memoryMb;
    if (inst.autoMemory ?? settings.autoMemory) {
      final mods = await _countMods(p.join(dir.gameDirFor(versionId, isolated: isolate), 'mods'));
      mem = Memory.autoAllocateMb(modCount: mods, modern: v.requiredJava >= 17, is64BitJava: javaInst.is64Bit);
    }
    if (settings.optimizeMemoryBeforeLaunch) {
      task?.update(detail: '优化内存', progress: -1);
      await Memory.optimize(purgeStandby: settings.purgeStandbyMemory);
    }

    task?.update(detail: '启动游戏', progress: -1);
    final cmd = await Launcher.build(
      dir,
      versionId,
      LaunchIdentity(name: acc.name, uuid: acc.uuid, accessToken: acc.mcToken, xuid: acc.xuid),
      LaunchOptions(
        javaPath: javaInst.windowedPath,
        maxMemoryMb: mem,
        isolated: isolate,
        width: settings.windowWidth,
        height: settings.windowHeight,
        fullscreen: settings.fullscreen,
        extraJvmArgs: [settings.jvmArgs, inst.jvmArgs ?? ''].join(' ').trim(),
        extraGameArgs: [settings.gameArgs, inst.gameArgs ?? ''].join(' ').trim(),
        joinServer: joinServer ?? inst.joinServer,
        windowTitle: settings.windowTitle,
      ),
    );
    onLog?.call('[CML] Java: ${javaInst.label}');
    onLog?.call('[CML] 内存: $mem MB');
    onLog?.call('[CML] ${cmd.masked(acc.mcToken)}');
    settings.selectedVersion = versionId;
    await settings.save();
    return Launcher.start(cmd, onLog: onLog, preLaunchCommand: settings.preLaunchCommand);
  }

  static Future<int> _countMods(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) return 0;
    return d.list().where((e) => e is File && e.path.toLowerCase().endsWith('.jar')).length;
  }

  void dispose() => http.close();
}
