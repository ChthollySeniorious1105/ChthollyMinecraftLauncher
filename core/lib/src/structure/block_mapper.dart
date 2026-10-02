import 'dart:convert';

import 'package:archive/archive.dart';

import 'data/block_map_data.dart';
import 'structure.dart';

/// Java ⇄ Bedrock block state translation (GeyserMC mapping data).
///
/// Java → Bedrock is a direct table lookup. Bedrock → Java uses the reverse table;
/// when several Java states map to one Bedrock state the first (canonical) one wins,
/// and Java-only properties such as `waterlogged` default to the table's first entry.
class BlockMapper {
  BlockMapper._() {
    _load();
  }
  static final BlockMapper instance = BlockMapper._();

  final Map<String, BlockState> _j2b = {};
  final Map<String, BlockState> _b2j = {};
  final Map<String, String> _b2jName = {};

  void _load() {
    final text = utf8.decode(const GZipDecoder().decodeBytes(base64.decode(javaBedrockBlocksGz)));
    for (final line in const LineSplitter().convert(text)) {
      final t = line.split('\t');
      if (t.length < 2) continue;
      final java = BlockState.parse(t[0]);
      final props = <String, String>{};
      if (t.length > 2 && t[2].isNotEmpty) {
        (jsonDecode(t[2]) as Map).forEach((k, v) => props['$k'] = '$v');
      }
      final bedrock = BlockState(t[1], props);
      _j2b[java.toString()] = bedrock;
      _b2j.putIfAbsent(_bkey(bedrock), () => java);
      _b2jName.putIfAbsent(bedrock.name, () => java.name);
    }
  }

  static String _bkey(BlockState b) => '${b.name}|${(b.props.keys.toList()..sort()).map((k) => '$k=${b.props[k]}').join(',')}';

  /// Java → Bedrock. Unknown blocks keep their name (props dropped) so the structure still loads.
  BlockState toBedrock(BlockState java) {
    final hit = _j2b[java.toString()];
    if (hit != null) return hit;
    // fill missing Java defaults by matching a state with the same name and a superset of props
    if (java.props.isNotEmpty) {
      for (final e in _j2b.entries) {
        if (!e.key.startsWith('${java.name}[')) continue;
        final cand = BlockState.parse(e.key);
        if (java.props.entries.every((p) => cand.props[p.key] == p.value)) return e.value;
      }
    }
    final byName = _j2b[java.name];
    if (byName != null) return byName;
    return BlockState(java.name);
  }

  /// Bedrock → Java.
  BlockState toJava(BlockState bedrock) {
    final props = Map.of(bedrock.props)..remove('minecraft:vertical_half_if_exists');
    final hit = _b2j[_bkey(BlockState(bedrock.name, props))];
    if (hit != null) return hit;
    // tolerate extra/unknown bedrock states (newer versions add properties)
    BlockState? best;
    var bestScore = -1;
    final prefix = '${bedrock.name}|';
    for (final e in _b2j.entries) {
      if (!e.key.startsWith(prefix)) continue;
      final cand = e.key.substring(prefix.length);
      final candProps = cand.isEmpty ? <String, String>{} : {for (final kv in cand.split(',')) kv.split('=')[0]: kv.split('=')[1]};
      var score = 0;
      props.forEach((k, v) {
        if (candProps[k] == v) score++;
      });
      if (score > bestScore) {
        bestScore = score;
        best = e.value;
      }
    }
    if (best != null) return best;
    return BlockState(_b2jName[bedrock.name] ?? bedrock.name);
  }

  /// Converts every palette entry of [s] in place to the target naming.
  void convert(Structure s, BlockNaming to) {
    if (s.naming == to) return;
    for (var i = 0; i < s.palette.length; i++) {
      s.palette[i] = to == BlockNaming.bedrock ? toBedrock(s.palette[i]) : toJava(s.palette[i]);
    }
    s.naming = to;
  }
}
