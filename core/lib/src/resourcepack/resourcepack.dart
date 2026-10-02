import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../common/errors.dart';
import 'bedrock_converter.dart';
import 'java_migrator.dart';
import 'optifine_migrator.dart';
import 'pack_files.dart';
import 'sky_converter.dart';

export 'pack_files.dart' show ConvertLog, ConvertNote;

/// A conversion target.
class PackTarget {
  final String label;

  /// Java timeline version id, or null for Bedrock.
  final String? javaVersion;
  const PackTarget(this.label, this.javaVersion);
  bool get bedrock => javaVersion == null;

  @override
  bool operator ==(Object other) => other is PackTarget && other.javaVersion == javaVersion;
  @override
  int get hashCode => javaVersion.hashCode;

  static List<PackTarget> get all {
    final tl = JavaPackTimeline.instance;
    return [
      const PackTarget('基岩版（.mcpack）', null),
      for (final v in tl.versions.reversed) PackTarget('Java $v（pack_format ${tl.formatOf(v)}）', v),
    ];
  }
}

/// Sky handling for Java targets.
enum SkyMode {
  keep('保持不变'),
  addNuit('OptiFine 天空 → 同时生成 Nuit 天空'),
  addOptifine('Nuit 天空 → 同时生成 OptiFine 天空'),
  both('两种格式互相补全');

  final String label;
  const SkyMode(this.label);
}

class PackConvertReport {
  final String output;
  final String from;
  final String to;
  final ConvertLog log;
  PackConvertReport(this.output, this.from, this.to, this.log);
}

/// "资源包转换": Java ⇄ Java (any version, both directions), Java ⇄ Bedrock, OptiFine ⇄ Nuit skies.
/// Everything that has a counterpart is converted; what cannot be is listed in the report.
abstract class ResourcePackConverter {
  /// Reads a pack from a .zip / .mcpack / folder.
  static Future<PackFiles> read(String input) async {
    final pack = PackFiles();
    if (await Directory(input).exists()) {
      await for (final e in Directory(input).list(recursive: true)) {
        if (e is File) pack[p.relative(e.path, from: input).replaceAll('\\', '/')] = await e.readAsBytes();
      }
    } else {
      final inp = InputFileStream(input);
      try {
        for (final f in ZipDecoder().decodeStream(inp).files) {
          if (f.isFile) pack[f.name.replaceAll('\\', '/')] = Uint8List.fromList(f.readBytes()!);
        }
      } finally {
        await inp.close();
      }
    }
    // strip a single wrapping folder
    if (!pack.has('pack.mcmeta') && !pack.has('manifest.json')) {
      final roots = [
        for (final k in pack.paths)
          if (k.endsWith('/pack.mcmeta') || k.endsWith('/manifest.json')) k
      ]..sort((a, b) => a.length.compareTo(b.length));
      if (roots.isEmpty) throw const CmlException('not_pack', '不是资源包（缺少 pack.mcmeta 或 manifest.json）');
      final prefix = roots.first.substring(0, roots.first.lastIndexOf('/') + 1);
      final stripped = PackFiles();
      for (final k in pack.paths) {
        if (k.startsWith(prefix)) stripped[k.substring(prefix.length)] = pack[k]!;
      }
      return stripped;
    }
    return pack;
  }

  static bool isBedrock(PackFiles pack) => pack.has('manifest.json') && !pack.has('pack.mcmeta');

  /// Detected Java timeline version of a Java pack.
  static String detectJavaVersion(PackFiles pack) {
    final tl = JavaPackTimeline.instance;
    final meta = pack.json('pack.mcmeta');
    final packMap = meta is Map ? meta['pack'] as Map? : null;
    num? f = packMap?['pack_format'] as num?;
    final minF = packMap?['min_format'];
    if (f == null && minF != null) f = minF is List ? minF.first as num : minF as num;
    if (f != null) return tl.versionForFormat(f);
    // no format: guess from layout
    if (pack.paths.any((k) => k.startsWith('assets/minecraft/textures/blocks/'))) return '1.12.2';
    return tl.versions.last;
  }

  static String describe(PackFiles pack) => isBedrock(pack) ? '基岩版' : 'Java ${detectJavaVersion(pack)}';

  static Future<PackConvertReport> convert(String input, PackTarget target, {String? outputPath, SkyMode sky = SkyMode.both}) async {
    final pack = await read(input);
    final log = ConvertLog();
    final from = describe(pack);
    final baseName = p.basenameWithoutExtension(input);
    final tl = JavaPackTimeline.instance;
    PackFiles out;

    if (isBedrock(pack)) {
      if (target.bedrock) throw const CmlException('same', '源和目标都是基岩版');
      out = BedrockPackConverter().toJava(pack, log, packFormat: tl.formatOf(target.javaVersion!), targetVersion: target.javaVersion!);
      _sky(out, sky, log);
      _writeMeta(out, target.javaVersion!);
    } else {
      final fromV = detectJavaVersion(pack);
      if (target.bedrock) {
        // complete sky formats first so either kind ends up in the cubemap
        SkyConverter.fabricSkyboxesToNuit(pack, ConvertLog());
        SkyConverter.nuitToOptifine(pack, ConvertLog());
        final meta = pack.json('pack.mcmeta');
        final desc = meta is Map ? _plainText((meta['pack'] as Map?)?['description']) : '';
        out = BedrockPackConverter().toBedrock(pack, log, name: baseName, description: desc);
      } else {
        out = pack;
        JavaPackMigrator().migrate(out, fromV, target.javaVersion!, log);
        OptiFineMigrator.migrate(out, fromV, target.javaVersion!, log);
        _sky(out, sky, log);
        _writeMeta(out, target.javaVersion!);
        if (fromV == target.javaVersion) log.note('源版本与目标版本相同，仅更新元数据与天空格式');
      }
    }

    final ext = target.bedrock ? 'mcpack' : 'zip';
    final label = target.bedrock ? 'bedrock' : target.javaVersion!;
    var outPath = outputPath ?? p.join(p.dirname(input), '$baseName-$label.$ext');
    if (p.equals(outPath, input)) outPath = p.join(p.dirname(input), '$baseName-$label-converted.$ext');
    await _writeZip(out, outPath);
    return PackConvertReport(outPath, from, target.label, log);
  }

  static void _sky(PackFiles pack, SkyMode mode, ConvertLog log) {
    if (mode != SkyMode.keep) SkyConverter.fabricSkyboxesToNuit(pack, log);
    if (mode == SkyMode.addNuit || mode == SkyMode.both) SkyConverter.optifineToNuit(pack, log);
    if (mode == SkyMode.addOptifine || mode == SkyMode.both) SkyConverter.nuitToOptifine(pack, log);
  }

  /// pack.mcmeta for the target: pack_format + supported range / min-max formats.
  static void _writeMeta(PackFiles pack, String version) {
    final tl = JavaPackTimeline.instance;
    final f = tl.formatOf(version);
    final meta = pack.json('pack.mcmeta');
    final m = meta is Map ? Map<String, dynamic>.from(meta) : <String, dynamic>{};
    final packObj = Map<String, dynamic>.from((m['pack'] as Map?) ?? {'description': ''});
    packObj['pack_format'] = f;
    packObj.remove('supported_formats');
    packObj.remove('min_format');
    packObj.remove('max_format');
    if (f >= 65) {
      packObj['min_format'] = f;
      packObj['max_format'] = f;
    } else if (f >= 18) {
      packObj['supported_formats'] = {'min_inclusive': f, 'max_inclusive': f};
    }
    m['pack'] = packObj;
    pack.setJson('pack.mcmeta', m);
  }

  static String _plainText(Object? desc) {
    if (desc == null) return '';
    if (desc is String) return desc.replaceAll(RegExp('§.'), '');
    if (desc is List) return desc.map(_plainText).join();
    if (desc is Map) return '${_plainText(desc['text'])}${_plainText(desc['extra'])}';
    return '$desc';
  }

  static Future<void> _writeZip(PackFiles pack, String out) async {
    await File(out).parent.create(recursive: true);
    final enc = ZipFileEncoder()..create(out);
    try {
      for (final k in pack.paths.toList()..sort()) {
        enc.addArchiveFile(ArchiveFile.bytes(k, pack[k]!));
      }
    } finally {
      await enc.close();
    }
  }
}
