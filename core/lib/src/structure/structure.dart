import 'dart:typed_data';

import '../nbt/nbt.dart';

/// Block naming convention of a [Structure].
enum BlockNaming { java, bedrock }

/// A block state, e.g. `minecraft:oak_stairs[facing=north,half=bottom]`.
class BlockState {
  final String name;
  final Map<String, String> props;
  const BlockState(this.name, [this.props = const {}]);

  static const air = BlockState('minecraft:air');
  static const structureVoid = BlockState('minecraft:structure_void');

  bool get isAir => name == 'minecraft:air' || name == 'minecraft:cave_air' || name == 'minecraft:void_air';

  /// Parses `name[k=v,…]` (Java) or `name["k":v,…]` (Bedrock states string).
  factory BlockState.parse(String s) {
    s = s.trim();
    final i = s.indexOf('[');
    final name = _ns(i < 0 ? s : s.substring(0, i));
    if (i < 0) return BlockState(name);
    final body = s.substring(i + 1, s.lastIndexOf(']'));
    final props = <String, String>{};
    for (final part in _splitTop(body)) {
      final sep = part.contains('=') ? part.indexOf('=') : part.indexOf(':');
      if (sep < 0) continue;
      props[_unq(part.substring(0, sep))] = _unq(part.substring(sep + 1));
    }
    return BlockState(name, props);
  }

  static String _ns(String n) => n.contains(':') ? n : 'minecraft:$n';
  static String _unq(String s) {
    s = s.trim();
    return s.length >= 2 && s.startsWith('"') && s.endsWith('"') ? s.substring(1, s.length - 1) : s;
  }

  static List<String> _splitTop(String s) {
    final out = <String>[];
    var q = false;
    final cur = StringBuffer();
    for (final c in s.split('')) {
      if (c == '"') q = !q;
      if (c == ',' && !q) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    if (cur.isNotEmpty) out.add(cur.toString());
    return out;
  }

  /// Java form: `minecraft:stone[a=b]`.
  @override
  String toString() => props.isEmpty ? name : '$name[${(props.keys.toList()..sort()).map((k) => '$k=${props[k]}').join(',')}]';

  /// Bedrock states string: `["color":"red","age":3,"open_bit":true]`.
  String toBedrockStates() => '[${props.entries.map((e) => '"${e.key}":${_bedrockValue(e.value)}').join(',')}]';

  static String _bedrockValue(String v) => (v == 'true' || v == 'false' || int.tryParse(v) != null) ? v : '"$v"';

  @override
  bool operator ==(Object other) => other is BlockState && other.toString() == toString();
  @override
  int get hashCode => toString().hashCode;
}

/// Format-neutral block structure. Index order is `(y * sz + z) * sx + x`.
class Structure {
  final int sx, sy, sz;
  final List<BlockState> palette;
  final Int32List blocks;

  /// Optional second layer (Bedrock waterlogging). Same indexing, -1 = none.
  Int32List? layer2;

  /// Block entity NBT by block index (positions are rewritten by writers).
  final Map<int, CompoundTag> blockEntities;

  /// Entities with a relative `Pos` list (doubles).
  final List<CompoundTag> entities;
  BlockNaming naming;
  int dataVersion;
  String name;
  String author;

  /// Where the structure was in the source world (schem Offset / mcstructure origin).
  List<int> origin;

  Structure(this.sx, this.sy, this.sz, {List<BlockState>? palette, this.naming = BlockNaming.java, this.dataVersion = 3955, this.name = '', this.author = '', this.origin = const [0, 0, 0]})
      : palette = palette ?? [BlockState.air],
        blocks = Int32List(sx * sy * sz),
        blockEntities = {},
        entities = [];

  int get volume => sx * sy * sz;
  int index(int x, int y, int z) => (y * sz + z) * sx + x;
  (int, int, int) pos(int i) => (i % sx, i ~/ (sx * sz), (i ~/ sx) % sz);

  final Map<String, int> _lookup = {};

  /// Palette index for [s], adding it if needed.
  int idOf(BlockState s) {
    if (_lookup.isEmpty) {
      for (var i = 0; i < palette.length; i++) {
        _lookup[palette[i].toString()] = i;
      }
    }
    final k = s.toString();
    final hit = _lookup[k];
    if (hit != null) return hit;
    palette.add(s);
    return _lookup[k] = palette.length - 1;
  }

  void set(int x, int y, int z, BlockState s) => blocks[index(x, y, z)] = idOf(s);
  BlockState? get(int x, int y, int z) {
    final v = blocks[index(x, y, z)];
    return v < 0 ? null : palette[v];
  }

  /// Number of non-air blocks.
  int get blockCount {
    final airIds = {for (var i = 0; i < palette.length; i++) if (palette[i].isAir || palette[i] == BlockState.structureVoid) i};
    var n = 0;
    for (final b in blocks) {
      if (b >= 0 && !airIds.contains(b)) n++;
    }
    return n;
  }

  /// Material list: block name → count (air excluded).
  Map<String, int> materials() {
    final counts = List<int>.filled(palette.length, 0);
    for (final b in blocks) {
      if (b >= 0) counts[b]++;
    }
    final out = <String, int>{};
    for (var i = 0; i < palette.length; i++) {
      if (palette[i].isAir || palette[i] == BlockState.structureVoid || counts[i] == 0) continue;
      out.update(palette[i].name, (v) => v + counts[i], ifAbsent: () => counts[i]);
    }
    return Map.fromEntries(out.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }
}
