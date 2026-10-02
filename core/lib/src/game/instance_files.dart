import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash.dart';

class ScreenshotInfo {
  final File file;
  final DateTime time;
  final int size;
  ScreenshotInfo(this.file, this.time, this.size);
}

/// A log or crash report of an instance.
class LogFile {
  final File file;
  final DateTime time;
  final int size;
  final bool crash;
  LogFile(this.file, this.time, this.size, {this.crash = false});
  String get name => p.basename(file.path);
}

/// Screenshots, logs and crash reports of a game directory.
abstract class InstanceFiles {
  static Future<List<ScreenshotInfo>> screenshots(String gameDir) async {
    final d = Directory(p.join(gameDir, 'screenshots'));
    if (!await d.exists()) return [];
    final out = <ScreenshotInfo>[];
    await for (final e in d.list()) {
      if (e is! File) continue;
      final l = e.path.toLowerCase();
      if (!l.endsWith('.png') && !l.endsWith('.jpg')) continue;
      final st = await e.stat();
      out.add(ScreenshotInfo(e, st.modified, st.size));
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  static Future<List<LogFile>> logs(String gameDir) async {
    final out = <LogFile>[];
    for (final (sub, crash) in [('logs', false), ('crash-reports', true)]) {
      final d = Directory(p.join(gameDir, sub));
      if (!await d.exists()) continue;
      await for (final e in d.list()) {
        if (e is! File) continue;
        final l = e.path.toLowerCase();
        if (!(l.endsWith('.log') || l.endsWith('.txt') || l.endsWith('.log.gz'))) continue;
        final st = await e.stat();
        out.add(LogFile(e, st.modified, st.size, crash: crash));
      }
    }
    // hs_err_pid*.log JVM crashes land in the game dir root
    final root = Directory(gameDir);
    if (await root.exists()) {
      await for (final e in root.list()) {
        if (e is File && p.basename(e.path).startsWith('hs_err_pid')) {
          final st = await e.stat();
          out.add(LogFile(e, st.modified, st.size, crash: true));
        }
      }
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// Reads a log (gz supported), capped to the last [maxBytes].
  static Future<String> read(LogFile f, {int maxBytes = 2 << 20}) async {
    List<int> bytes = await f.file.readAsBytes();
    if (f.file.path.toLowerCase().endsWith('.gz')) bytes = gzip.decode(bytes);
    if (bytes.length > maxBytes) bytes = bytes.sublist(bytes.length - maxBytes);
    // Minecraft writes UTF-8; fall back to the system code page (GBK) for older logs
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return const SystemEncoding().decode(bytes);
    }
  }

  /// Crash cause for a log (one sentence).
  static String? diagnose(String text) => CrashAnalyzer.analyze(text);

  /// Full analysis of one log.
  static CrashReport analyze(String text) => CrashAnalyzer.analyzeText(text);

}
