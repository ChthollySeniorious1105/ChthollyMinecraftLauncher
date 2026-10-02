import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../common/errors.dart';
import 'block_mapper.dart';
import 'formats.dart';
import 'structure.dart';

class ConvertReport {
  final String output;
  final int sx, sy, sz;
  final int blocks;
  final int paletteSize;
  final int blockEntities;
  final bool crossEdition;
  ConvertReport(this.output, this.sx, this.sy, this.sz, this.blocks, this.paletteSize, this.blockEntities, this.crossEdition);
}

/// High-level "建筑文件格式转换".
abstract class StructureConverter {
  static Structure load(String path) {
    final f = StructureFormat.fromPath(path) ?? (throw CmlException('format', '不支持的文件类型：${p.extension(path)}'));
    try {
      return StructureIO.read(File(path).readAsBytesSync(), f);
    } on FormatException catch (e) {
      throw CmlException('structure_read', '无法读取 ${p.basename(path)}：${e.message}', e);
    } catch (e) {
      throw CmlException('structure_read', '无法读取 ${p.basename(path)}（文件损坏或格式不符）', e);
    }
  }

  static Uint8List encode(Structure s, StructureFormat to) {
    BlockMapper.instance.convert(s, to.naming);
    return StructureIO.write(s, to);
  }

  /// Converts [input] to [to], writing next to it (or into [outDir]). Returns a report.
  static Future<ConvertReport> convertFile(String input, StructureFormat to, {String? outDir}) async {
    final s = load(input);
    final cross = s.naming != to.naming;
    final bytes = encode(s, to);
    final out = p.join(outDir ?? p.dirname(input), '${p.basenameWithoutExtension(input)}.${to.ext}');
    final target = await File(out).exists() && p.equals(out, input) ? p.join(p.dirname(out), '${p.basenameWithoutExtension(input)}_converted.${to.ext}') : out;
    await File(target).writeAsBytes(bytes);
    return ConvertReport(target, s.sx, s.sy, s.sz, s.blockCount, s.palette.length, s.blockEntities.length, cross);
  }
}
