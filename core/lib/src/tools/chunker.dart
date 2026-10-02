import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/os.dart';
import '../common/task.dart';
import '../java/java.dart';
import 'github_component.dart';

/// Chunker (HiveGamesOSS/Chunker) — Java ⇄ Bedrock world conversion, tracked from GitHub releases.
/// Uses the platform-independent CLI jar with a CML-managed Java 17+.
class ChunkerTool extends GithubComponent {
  ChunkerTool(super.http);

  @override
  String get id => 'chunker';
  @override
  String get displayName => 'Chunker';
  @override
  String get repo => 'HiveGamesOSS/Chunker';

  @override
  GithubAsset? pickAsset(GithubRelease r) => r.assets.where((a) => RegExp(r'^chunker-cli-.*\.jar$').hasMatch(a.name)).firstOrNull;

  @override
  Future<void> install(File file, GithubAsset asset, Task? task) async {
    final dest = File(jarPath);
    if (await dest.exists()) await dest.delete();
    await file.copy(dest.path);
  }

  String get jarPath => p.join(installDir, 'chunker-cli.jar');
  bool get installed => File(jarPath).existsSync();

  /// Output formats like `JAVA_1_21_5`, `BEDROCK_1_21_90`. Parsed from Chunker's error listing.
  Future<List<String>> formats(String java) async {
    final r = await Process.run(java, ['-jar', jarPath, '-f', '?', '-i', '.', '-o', '.'], stdoutEncoding: utf8, stderrEncoding: utf8);
    final all = '${r.stdout}\n${r.stderr}';
    final s = {for (final m in RegExp(r'\b(?:JAVA|BEDROCK)_\d+(?:_\d+)*\b').allMatches(all)) m.group(0)!}.toList();
    s.sort(_compareFormats);
    return s;
  }

  static int _compareFormats(String a, String b) {
    final ea = a.split('_').first, eb = b.split('_').first;
    if (ea != eb) return ea.compareTo(eb);
    final na = a.split('_').skip(1).map(int.parse).toList(), nb = b.split('_').skip(1).map(int.parse).toList();
    for (var i = 0; i < 4; i++) {
      final x = i < na.length ? na[i] : 0, y = i < nb.length ? nb[i] : 0;
      if (x != y) return y.compareTo(x); // newest first
    }
    return 0;
  }

  /// Converts the world at [input] into [output] as [format] (e.g. `BEDROCK_1_21_90`, `JAVA_1_21_5`).
  Future<void> convert({
    required JavaInstall java,
    required String input,
    required String output,
    required String format,
    int maxMemoryMb = 4096,
    Task? task,
  }) async {
    if (!installed) throw const CmlException('chunker_missing', 'Chunker 尚未安装，请先在 工具 → Chunker 中下载');
    if (java.major < 17) throw const CmlException('chunker_java', 'Chunker 需要 Java 17 或更高版本');
    await Directory(output).create(recursive: true);
    final proc = await Process.start(java.path, ['-Xmx${maxMemoryMb}m', '-jar', jarPath, '-i', input, '-o', output, '-f', format],
        workingDirectory: installDir);
    task?.cancel.onCancel(proc.kill);
    final log = StringBuffer();
    void onLine(String l) {
      log.writeln(l);
      final m = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(l);
      if (m != null) {
        task?.update(progress: double.parse(m.group(1)!) / 100, detail: l.trim());
      } else if (l.trim().isNotEmpty) {
        task?.update(detail: l.trim().length > 120 ? l.trim().substring(0, 120) : l.trim());
      }
    }

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
    final code = await proc.exitCode;
    task?.cancel.throwIfCancelled();
    if (code != 0) {
      final logFile = p.join(Os.cmlHome, 'logs', 'chunker-${DateTime.now().millisecondsSinceEpoch}.log');
      await File(logFile).parent.create(recursive: true);
      await File(logFile).writeAsString(log.toString());
      throw CmlException('chunker_failed', 'Chunker 转换失败（退出码 $code），日志：$logFile');
    }
  }
}
