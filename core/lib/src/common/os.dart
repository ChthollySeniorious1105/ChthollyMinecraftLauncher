import 'dart:io';

import 'package:path/path.dart' as p;

/// Platform helpers. CML targets Windows; other OS values exist so version JSON rules evaluate correctly.
abstract class Os {
  static String get name => Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'osx' : 'linux');

  /// 'x86', 'x86_64' or 'arm64'
  static String get arch {
    final a = (Platform.environment['PROCESSOR_ARCHITEW6432'] ?? Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toUpperCase();
    if (a == 'ARM64') return 'arm64';
    if (a == 'X86') return 'x86';
    return 'x86_64';
  }

  static String get osVersion => Platform.operatingSystemVersion;

  static String get appData => Platform.environment['APPDATA'] ?? p.join(Platform.environment['HOME'] ?? '.', '.config');
  static String get localAppData => Platform.environment['LOCALAPPDATA'] ?? appData;

  /// %APPDATA%\CML
  static String get cmlHome => p.join(appData, 'CML');

  static String get defaultMinecraftDir => Platform.isWindows ? p.join(appData, '.minecraft') : p.join(Platform.environment['HOME'] ?? '.', '.minecraft');

  static String get classpathSeparator => Platform.isWindows ? ';' : ':';
}
