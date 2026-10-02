import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import '../common/task.dart';
import '../net/downloader.dart';
import '../net/http.dart';
import 'game_dir.dart';

/// One OptiFine build from BMCLAPI's list.
class OptiFineBuild {
  final String mcVersion;
  final String type; // HD_U
  final String patch; // I6, pre4 …
  final String filename;
  final String? forge; // "Forge 47.2.18" — compatible Forge build
  OptiFineBuild(this.mcVersion, this.type, this.patch, this.filename, this.forge);

  bool get preview => filename.toLowerCase().contains('preview') || patch.startsWith('pre');

  /// Edition string used in version ids and maven coords, e.g. `HD_U_I6`.
  String get edition => '${type}_$patch';
  String get label => '$type $patch${preview ? '（预览版）' : ''}';
}

/// Installs OptiFine without its installer GUI:
///   1. download the OptiFine jar (BMCLAPI mirrors optifine.net)
///   2. run OptiFine's own `optifine.Patcher` against the vanilla client jar → patched library
///   3. extract `launchwrapper-of` (or reuse Mojang's launchwrapper) and write a version JSON
///      that inherits the vanilla version and launches through `optifine.OptiFineTweaker`.
/// For Forge instances OptiFine is simply added as a mod (Forge loads it through its tweaker).
class OptiFineInstaller {
  final Http http;
  final Downloader dl;
  OptiFineInstaller(this.http, this.dl);

  static const _bmcl = 'https://bmclapi2.bangbang93.com/optifine';

  Future<List<OptiFineBuild>> list(String mc) async {
    final j = await http.getJson(Uri.parse('$_bmcl/$mc'));
    if (j is! List) return [];
    final out = [
      for (final e in j)
        OptiFineBuild('${e['mcversion']}', '${e['type']}', '${e['patch']}', '${e['filename']}', e['forge'] as String?)
    ];
    // newest first; release builds before previews
    out.sort((a, b) {
      if (a.preview != b.preview) return a.preview ? 1 : -1;
      return b.filename.compareTo(a.filename);
    });
    return out;
  }

  /// Downloads the OptiFine jar to [dest].
  Future<void> download(OptiFineBuild b, String dest, {Task? task}) async {
    await File(dest).parent.create(recursive: true);
    final url = '$_bmcl/${b.mcVersion}/${b.type}/${b.patch}';
    await dl.download(DownloadItem(url, dest), cancel: task?.cancel);
    // BMCLAPI answers 200 with an HTML error page for unknown builds
    final head = await File(dest).openRead(0, 2).first;
    if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4b) {
      await File(dest).delete();
      throw CmlException('optifine_dl', 'OptiFine ${b.label} 下载失败');
    }
  }

  /// Installs OptiFine as its own version on top of vanilla [b.mcVersion] (which must be installed).
  Future<String> install(GameDir dir, OptiFineBuild b, {required String javaPath, String? id, Task? task}) async {
    id ??= '${b.mcVersion}-OptiFine_${b.edition}';
    final mc = b.mcVersion;
    final vanillaJar = dir.versionJar(mc);
    if (!await File(vanillaJar).exists()) throw CmlException('optifine_base', '请先安装 Minecraft $mc');
    final tmp = await Directory.systemTemp.createTemp('cml-optifine');
    try {
      final ofJar = p.join(tmp.path, b.filename);
      task?.update(detail: '下载 OptiFine ${b.label}', progress: -1);
      await download(b, ofJar, task: task);

      // patched library
      final libVer = '${mc}_${b.edition}';
      final libPath = dir.library('optifine/OptiFine/$libVer/OptiFine-$libVer.jar');
      await File(libPath).parent.create(recursive: true);
      task?.update(detail: '修补游戏文件', progress: -1);
      final r = await Process.run(javaPath, ['-cp', ofJar, 'optifine.Patcher', vanillaJar, ofJar, libPath]);
      if (r.exitCode != 0 || !await File(libPath).exists()) {
        throw CmlException('optifine_patch', 'OptiFine 修补失败（退出码 ${r.exitCode}）：${'${r.stderr}'.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')}');
      }

      // launchwrapper
      final (lwName, lwPath) = await _launchwrapper(dir, ofJar);
      final libraries = <Map<String, Object?>>[
        {'name': 'optifine:OptiFine:$libVer'},
        if (lwPath != null) {'name': lwName} else {'name': 'net.minecraft:launchwrapper:1.12'},
      ];

      final parent = await dir.readVersionJson(mc);
      final modern = parent['arguments'] is Map;
      final json = <String, Object?>{
        'id': id,
        'inheritsFrom': mc,
        'type': 'release',
        'time': DateTime.now().toIso8601String(),
        'releaseTime': parent['releaseTime'],
        'mainClass': 'net.minecraft.launchwrapper.Launch',
        'libraries': libraries,
        if (modern)
          'arguments': {
            'game': ['--tweakClass', 'optifine.OptiFineTweaker']
          }
        else
          'minecraftArguments': '${parent['minecraftArguments'] ?? ''} --tweakClass optifine.OptiFineTweaker'.trim(),
        // launch the vanilla client jar; OptiFine classes come from the library ahead of it
        'jar': mc,
      };
      await Directory(dir.versionDir(id)).create(recursive: true);
      await dir.writeVersionJson(id, json);
      // a copy of the client jar keeps instances self-contained (matches the official installer)
      await File(vanillaJar).copy(dir.versionJar(id));
      return id;
    } finally {
      await tmp.delete(recursive: true).catchError((_) => tmp);
    }
  }

  /// Extracts `launchwrapper-of-X.jar` from the OptiFine jar into libraries. Returns (maven name, path or null).
  Future<(String, String?)> _launchwrapper(GameDir dir, String ofJar) async {
    final input = InputFileStream(ofJar);
    try {
      final z = ZipDecoder().decodeStream(input);
      final verFile = z.findFile('launchwrapper-of.txt');
      if (verFile == null) return ('net.minecraft:launchwrapper:1.12', null);
      final ver = utf8.decode(verFile.readBytes()!).trim();
      final jar = z.findFile('launchwrapper-of-$ver.jar');
      if (jar == null) return ('net.minecraft:launchwrapper:1.12', null);
      final dest = dir.library('optifine/launchwrapper-of/$ver/launchwrapper-of-$ver.jar');
      await File(dest).parent.create(recursive: true);
      await File(dest).writeAsBytes(jar.readBytes()!);
      return ('optifine:launchwrapper-of:$ver', dest);
    } finally {
      await input.close();
    }
  }

  /// Adds OptiFine to a Forge instance as a mod.
  Future<String> installAsMod(OptiFineBuild b, String modsDir, {Task? task}) async {
    final dest = p.join(modsDir, b.filename);
    await download(b, dest, task: task);
    return dest;
  }

}
