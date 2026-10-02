import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../tools/github_component.dart';

/// Launcher self-update from GitHub releases ("启动器自动更新").
///
/// Release assets expected: `CML-<version>-windows-x64.zip` containing `cml.exe` and its files.
/// The update is unpacked next to the install, then a small batch script waits for CML to exit,
/// swaps the folders and restarts it.
class SelfUpdater extends GithubComponent {
  /// GitHub repository CML is published under; override with `--dart-define=CML_REPO=owner/name`.
  static const defaultRepo = String.fromEnvironment('CML_REPO', defaultValue: 'chtholly-games/ChthollyMinecraftLauncher');

  /// Version of this build (`--dart-define=CML_VERSION=x.y.z`).
  static const currentVersion = String.fromEnvironment('CML_VERSION', defaultValue: '0.1.0');

  final String repoName;
  SelfUpdater(super.http, {String? repo}) : repoName = repo ?? defaultRepo;

  @override
  String get id => 'cml-update';
  @override
  String get displayName => 'CML';
  @override
  String get repo => repoName;

  @override
  GithubAsset? pickAsset(GithubRelease r) => r.assets.where((a) => RegExp(r'^CML-.*-windows-x64\.zip$').hasMatch(a.name)).firstOrNull;

  /// True when [tag] (e.g. `v0.2.0`) is newer than [currentVersion].
  static bool isNewer(String tag, [String current = currentVersion]) {
    List<int> parts(String v) => v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.\-+]')).map((e) => int.tryParse(e) ?? 0).toList();
    final a = parts(tag), b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  @override
  Future<GithubRelease?> checkUpdate() async {
    final r = await latest();
    return isNewer(r.tag) ? r : null;
  }

  String get appDir => p.dirname(Platform.resolvedExecutable);

  @override
  Future<void> install(File file, GithubAsset asset, Task? task) async {
    final staging = p.join(p.dirname(appDir), '.cml-update');
    if (await Directory(staging).exists()) await Directory(staging).delete(recursive: true);
    await GithubComponent.unzipTo(file, staging);
    // zip may contain a top-level folder
    var src = staging;
    final entries = await Directory(staging).list().toList();
    if (entries.length == 1 && entries.first is Directory) src = entries.first.path;
    if (!await File(p.join(src, 'cml.exe')).exists()) throw const CmlException('update_bad', '更新包中没有 cml.exe');
    _pendingSource = src;
  }

  String? _pendingSource;

  /// Writes the swap script and exits CML. Call after [update] succeeded and the user confirmed.
  /// The script runs in a visible console window titled "CML 更新", so the user can see what happens.
  Future<Never> applyAndRestart() async {
    final src = _pendingSource ?? (throw const CmlException('update_none', '没有待安装的更新'));
    final script = p.join(p.dirname(appDir), 'cml-update.bat');
    await File(script).writeAsString([
      '@echo off',
      'chcp 65001 >nul',
      'title CML 更新',
      'echo 正在等待 CML 退出...',
      ':wait',
      'tasklist /FI "PID eq $pid" | find "$pid" >nul && (timeout /t 1 >nul & goto wait)',
      'echo 正在复制新版本文件到 $appDir',
      'robocopy "$src" "$appDir" /E /MOVE /R:3 /W:1',
      'echo 更新完成，正在重新启动 CML',
      'start "" "${p.join(appDir, 'cml.exe')}"',
      'timeout /t 3 >nul',
    ].join(String.fromCharCodes([13, 10])));
    await Process.start('cmd', ['/c', 'start', 'CML 更新', script], mode: ProcessStartMode.detached);
    exit(0);
  }
}
