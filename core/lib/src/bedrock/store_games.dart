import 'dart:io';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/os.dart';

/// Microsoft Store / Xbox app games that CML can launch with one click.
class StoreGame {
  final String id;
  final String name;

  /// Package family name.
  final String family;

  /// Application id inside the package (AUMID = family!appId).
  final String appId;

  /// Store product id, for "去商店下载".
  final String storeId;

  const StoreGame(this.id, this.name, this.family, this.appId, this.storeId);

  String get aumid => '$family!$appId';
  String get storeUrl => 'ms-windows-store://pdp/?productid=$storeId';
}

abstract class StoreGames {
  static const bedrock = StoreGame('bedrock', 'Minecraft 基岩版', 'Microsoft.MinecraftUWP_8wekyb3d8bbwe', 'Game', '9NBLGGH2JHXJ');
  static const bedrockPreview = StoreGame('bedrock_preview', 'Minecraft 预览版', 'Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe', 'Game', '9P5X4QVLC2XR');
  static const legends = StoreGame('legends', 'Minecraft Legends', 'Microsoft.BadgerWin10_8wekyb3d8bbwe', 'Game', '9NBG3SQJXMPX');
  static const dungeons = StoreGame('dungeons', 'Minecraft Dungeons', 'Microsoft.Lovika_8wekyb3d8bbwe', 'Game', '9N8NJ74FTHWB');
  static const dungeons2 =
      StoreGame('dungeons2', 'Minecraft Dungeons II', 'Microsoft.MinecraftDungeons2_8wekyb3d8bbwe', 'AppMinecraftDungeonsIIShipping', '9P8NQ9PC3QPF');
  static const education = StoreGame('education', 'Minecraft 教育版', 'Microsoft.MinecraftEducationEdition_8wekyb3d8bbwe', 'Microsoft.MinecraftEducationEdition', '9NBLGGH4R2R6');

  static const all = [bedrock, bedrockPreview, legends, dungeons, dungeons2, education];
}

class StoreGameStatus {
  final StoreGame game;
  final bool installed;
  final String? version;
  final String? installLocation;

  /// Actual AUMID found via Get-StartApps (app ids sometimes differ between builds).
  final String? aumid;
  StoreGameStatus(this.game, this.installed, this.version, this.installLocation, this.aumid);
}

/// Detects and launches Store games.
abstract class StoreLauncher {
  /// Queries all [StoreGames] in one PowerShell call.
  static Future<List<StoreGameStatus>> detect() async {
    final families = StoreGames.all.map((g) => "'${g.family.split('_').first}'").join(',');
    final script = '''
\$ErrorActionPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
\$apps = Get-StartApps
foreach (\$n in @($families)) {
  \$pk = Get-AppxPackage -Name \$n | Select-Object -First 1
  if (\$pk) {
    \$a = (\$apps | Where-Object { \$_.AppID -like "\$(\$pk.PackageFamilyName)!*" } | Select-Object -First 1).AppID
    "\$n|\$(\$pk.Version)|\$(\$pk.InstallLocation)|\$a"
  } else { "\$n|||" }
}
''';
    final r = await Process.run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script], stdoutEncoding: const SystemEncoding());
    final rows = <String, List<String>>{};
    for (final line in '${r.stdout}'.split('\n')) {
      final parts = line.trim().split('|');
      if (parts.length >= 4) rows[parts[0].toLowerCase()] = parts;
    }
    return [
      for (final g in StoreGames.all)
        () {
          final row = rows[g.family.split('_').first.toLowerCase()];
          final installed = row != null && row[1].isNotEmpty;
          return StoreGameStatus(g, installed, installed ? row[1] : null, installed ? row[2] : null, installed && row[3].isNotEmpty ? row[3] : null);
        }()
    ];
  }

  /// Launches via `shell:AppsFolder\<AUMID>` (works for both UWP and GDK packages).
  static Future<void> launch(StoreGameStatus s) async {
    if (!s.installed) throw CmlException('not_installed', '${s.game.name} 未安装，可前往 Microsoft Store 下载');
    final aumid = s.aumid ?? s.game.aumid;
    await Process.start('explorer.exe', ['shell:AppsFolder\\$aumid'], mode: ProcessStartMode.detached);
  }

  static Future<void> openStore(StoreGame g) => Process.start('explorer.exe', [g.storeUrl], mode: ProcessStartMode.detached);

  /// Bedrock join-server deep link (`minecraft://?addExternalServer=Name|host:port`).
  static Future<void> bedrockAddServer(String name, String host, int port) =>
      Process.start('explorer.exe', ['minecraft://?addExternalServer=$name|$host:$port'], mode: ProcessStartMode.detached);
}

/// Locations of Bedrock `com.mojang` folders (UWP and the newer GDK build, plus preview).
abstract class BedrockPaths {
  static List<BedrockRoot> roots() {
    final out = <BedrockRoot>[];
    final pkgs = p.join(Os.localAppData, 'Packages');
    for (final (fam, label) in [
      ('Microsoft.MinecraftUWP_8wekyb3d8bbwe', '基岩版（UWP）'),
      ('Microsoft.MinecraftWindowsBeta_8wekyb3d8bbwe', '预览版（UWP）'),
    ]) {
      final d = p.join(pkgs, fam, 'LocalState', 'games', 'com.mojang');
      if (Directory(d).existsSync()) out.add(BedrockRoot(label, d));
    }
    // GDK builds (1.21.120+): %APPDATA%\Minecraft Bedrock\Users\<id>\games\com.mojang and Shared
    for (final (folder, label) in [('Minecraft Bedrock', '基岩版'), ('Minecraft Bedrock Preview', '预览版')]) {
      final users = Directory(p.join(Os.appData, folder, 'Users'));
      if (!users.existsSync()) continue;
      for (final u in users.listSync().whereType<Directory>()) {
        final d = p.join(u.path, 'games', 'com.mojang');
        if (Directory(d).existsSync()) {
          final who = p.basename(u.path);
          out.add(BedrockRoot(who == 'Shared' ? '$label（共享）' : '$label（$who）', d));
        }
      }
    }
    return out;
  }
}

class BedrockRoot {
  final String label;
  final String comMojang;
  BedrockRoot(this.label, this.comMojang);
  String get worlds => p.join(comMojang, 'minecraftWorlds');
  String get resourcePacks => p.join(comMojang, 'resource_packs');
  String get behaviorPacks => p.join(comMojang, 'behavior_packs');
  String get skinPacks => p.join(comMojang, 'skin_packs');
}
