import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:brotli/brotli.dart';

import '../nbt/nbt.dart';
import 'brotli_store.dart';
import 'structure.dart';

/// Formats CML can read/write.
enum StructureFormat {
  schem('Sponge Schematic', 'schem', BlockNaming.java),
  litematic('Litematica', 'litematic', BlockNaming.java),
  schematic('MCEdit Schematic（旧版）', 'schematic', BlockNaming.java),
  nbt('原版结构 NBT', 'nbt', BlockNaming.java),
  mcstructure('基岩版结构', 'mcstructure', BlockNaming.bedrock),
  bdx('BDX（FastBuilder）', 'bdx', BlockNaming.bedrock);

  final String label;
  final String ext;
  final BlockNaming naming;
  const StructureFormat(this.label, this.ext, this.naming);

  static StructureFormat? fromPath(String path) {
    final e = path.toLowerCase().split('.').last;
    for (final f in values) {
      if (f.ext == e) return f;
    }
    return null;
  }
}

/// Readers/writers for every [StructureFormat].
abstract class StructureIO {
  static Structure read(Uint8List bytes, StructureFormat f) => switch (f) {
        StructureFormat.schem => _readSchem(bytes),
        StructureFormat.litematic => _readLitematic(bytes),
        StructureFormat.schematic => _readMcedit(bytes),
        StructureFormat.nbt => _readVanillaNbt(bytes),
        StructureFormat.mcstructure => _readMcstructure(bytes),
        StructureFormat.bdx => _readBdx(bytes),
      };

  static Uint8List write(Structure s, StructureFormat f) => switch (f) {
        StructureFormat.schem => _writeSchem(s),
        StructureFormat.litematic => _writeLitematic(s),
        StructureFormat.schematic => _writeMcedit(s),
        StructureFormat.nbt => _writeVanillaNbt(s),
        StructureFormat.mcstructure => _writeMcstructure(s),
        StructureFormat.bdx => _writeBdx(s),
      };

  // ======================= Sponge .schem (v1/v2/v3) =======================

  static Structure _readSchem(Uint8List bytes) {
    var root = Nbt.decodeAuto(bytes).tag;
    if (root.has('Schematic')) root = root.getCompound('Schematic')!; // v3 wraps in "Schematic"
    final version = root.getInt('Version') ?? 2;
    final w = root.getInt('Width')!, h = root.getInt('Height')!, l = root.getInt('Length')!;
    final blocksTag = version >= 3 ? root.getCompound('Blocks')! : root;
    final paletteTag = blocksTag.getCompound('Palette')!;
    final data = version >= 3 ? blocksTag.getBytes('Data')! : root.getBytes('BlockData')!;
    final pal = List<BlockState>.filled(paletteTag.value.length, BlockState.air, growable: true);
    var maxId = 0;
    paletteTag.value.forEach((k, v) {
      final id = (v as IntTag).value;
      if (id >= pal.length) pal.length = id + 1;
      pal[id] = BlockState.parse(k);
      maxId = math.max(maxId, id);
    });
    final meta = root.getCompound('Metadata');
    final s = Structure(w, h, l,
        palette: pal, dataVersion: root.getInt('DataVersion') ?? 3955, name: meta?.getString('Name') ?? '', author: meta?.getString('Author') ?? '');
    final off = root.getInts('Offset');
    if (off != null && off.length == 3) s.origin = [off[0], off[1], off[2]];
    // varint stream, index order y,z,x — same as Structure
    var i = 0, p = 0;
    while (i < s.volume && p < data.length) {
      var v = 0, shift = 0;
      while (true) {
        final b = data[p++];
        v |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) break;
        shift += 7;
      }
      s.blocks[i++] = v;
    }
    final be = version >= 3 ? blocksTag.getList('BlockEntities') : (root.getList('BlockEntities') ?? root.getList('TileEntities'));
    for (final t in be?.value ?? const <Tag>[]) {
      final c = t as CompoundTag;
      final pos = c.getInts('Pos');
      if (pos == null) continue;
      final copy = version >= 3 ? (c.getCompound('Data') ?? CompoundTag()) : (CompoundTag(Map.of(c.value))..remove('Pos'));
      final id = c.getString('Id') ?? c.getString('id');
      if (id != null) copy['id'] = StringTag(id);
      if (pos[0] < w && pos[1] < h && pos[2] < l) s.blockEntities[s.index(pos[0], pos[1], pos[2])] = copy;
    }
    final ents = root.getList('Entities');
    for (final t in ents?.value ?? const <Tag>[]) {
      final c = t as CompoundTag;
      final data = version >= 3 ? (c.getCompound('Data') ?? CompoundTag()) : CompoundTag(Map.of(c.value));
      final pos = c.getList('Pos');
      if (pos != null) data['Pos'] = pos;
      final id = c.getString('Id');
      if (id != null) data['id'] = StringTag(id);
      s.entities.add(data);
    }
    return s;
  }

  static Uint8List _writeSchem(Structure s) {
    final pal = CompoundTag();
    for (var i = 0; i < s.palette.length; i++) {
      pal[s.palette[i].toString()] = IntTag(i);
    }
    final data = BytesBuilder();
    for (var b in s.blocks) {
      if (b < 0) b = s.idOf(BlockState.air);
      while (b & ~0x7f != 0) {
        data.addByte((b & 0x7f) | 0x80);
        b = b >>> 7;
      }
      data.addByte(b);
    }
    // palette may have grown via idOf(air)
    for (var i = pal.value.length; i < s.palette.length; i++) {
      pal[s.palette[i].toString()] = IntTag(i);
    }
    final be = ListTag(TagId.compound);
    s.blockEntities.forEach((idx, nbt) {
      final (x, y, z) = s.pos(idx);
      final d = CompoundTag(Map.of(nbt.value));
      final id = (d.remove('id') as StringTag?)?.value ?? s.palette[s.blocks[idx]].name;
      d.remove('x');
      d.remove('y');
      d.remove('z');
      be.add(CompoundTag({'Pos': IntArrayTag(Int32List.fromList([x, y, z])), 'Id': StringTag(id), 'Data': d}));
    });
    final ents = ListTag(TagId.compound);
    for (final e in s.entities) {
      final d = CompoundTag(Map.of(e.value));
      final pos = d.remove('Pos');
      final id = (d.remove('id') as StringTag?)?.value ?? 'minecraft:armor_stand';
      ents.add(CompoundTag({'Pos': ?pos, 'Id': StringTag(id), 'Data': d}));
    }
    final schem = CompoundTag({
      'Version': IntTag(3),
      'DataVersion': IntTag(s.dataVersion),
      'Width': ShortTag(s.sx),
      'Height': ShortTag(s.sy),
      'Length': ShortTag(s.sz),
      'Offset': IntArrayTag(Int32List.fromList(s.origin)),
      'Metadata': CompoundTag({
        'Name': StringTag(s.name),
        'Author': StringTag(s.author),
        'Date': LongTag(DateTime.now().millisecondsSinceEpoch),
        'WorldEdit': CompoundTag({'Origin': IntArrayTag(Int32List(3))}),
      }),
      'Blocks': CompoundTag({'Palette': pal, 'Data': ByteArrayTag(data.takeBytes()), 'BlockEntities': be}),
      'Entities': ents,
    });
    return Nbt.compress(Nbt.encode(CompoundTag({'Schematic': schem})), NbtCompression.gzip);
  }

  // ======================= Litematica =======================

  static Structure _readLitematic(Uint8List bytes) {
    final root = Nbt.decodeAuto(bytes).tag;
    final regions = root.getCompound('Regions')!;
    final meta = root.getCompound('Metadata');
    // merge all regions into one bounding box
    var minX = 1 << 30, minY = 1 << 30, minZ = 1 << 30, maxX = -(1 << 30), maxY = -(1 << 30), maxZ = -(1 << 30);
    final rs = <(CompoundTag, int, int, int, int, int, int)>[];
    regions.value.forEach((_, t) {
      final r = t as CompoundTag;
      final pos = r.getCompound('Position')!, size = r.getCompound('Size')!;
      final px = pos.getInt('x')!, py = pos.getInt('y')!, pz = pos.getInt('z')!;
      final sx = size.getInt('x')!, sy = size.getInt('y')!, sz = size.getInt('z')!;
      // negative sizes extend towards negative axis
      final x0 = sx < 0 ? px + sx + 1 : px, y0 = sy < 0 ? py + sy + 1 : py, z0 = sz < 0 ? pz + sz + 1 : pz;
      rs.add((r, x0, y0, z0, sx.abs(), sy.abs(), sz.abs()));
      minX = math.min(minX, x0);
      minY = math.min(minY, y0);
      minZ = math.min(minZ, z0);
      maxX = math.max(maxX, x0 + sx.abs());
      maxY = math.max(maxY, y0 + sy.abs());
      maxZ = math.max(maxZ, z0 + sz.abs());
    });
    final s = Structure(maxX - minX, maxY - minY, maxZ - minZ,
        dataVersion: root.getInt('MinecraftDataVersion') ?? 3955, name: meta?.getString('Name') ?? '', author: meta?.getString('Author') ?? '');
    for (final (r, x0, y0, z0, w, h, l) in rs) {
      final palList = r.getList('BlockStatePalette')!;
      final pal = <int>[];
      for (final t in palList.value) {
        final c = t as CompoundTag;
        final props = <String, String>{};
        c.getCompound('Properties')?.value.forEach((k, v) => props[k] = (v as StringTag).value);
        pal.add(s.idOf(BlockState(c.getString('Name')!, props)));
      }
      final longs = r.getLongs('BlockStates')!;
      final bits = math.max(2, _bitsFor(palList.length));
      final mask = (1 << bits) - 1;
      final vol = w * h * l;
      for (var i = 0; i < vol; i++) {
        // litematica packs tightly across long boundaries; index order y,z,x
        final bitIndex = i * bits;
        final li = bitIndex >> 6, off = bitIndex & 63;
        int v;
        if (off + bits <= 64) {
          v = (longs[li] >>> off) & mask;
        } else {
          final lo = longs[li] >>> off;
          final hi = longs[li + 1] << (64 - off);
          v = (lo | hi) & mask;
        }
        final x = i % w, z = (i ~/ w) % l, y = i ~/ (w * l);
        s.blocks[s.index(x + x0 - minX, y + y0 - minY, z + z0 - minZ)] = pal[v];
      }
      for (final t in r.getList('TileEntities')?.value ?? const <Tag>[]) {
        final c = CompoundTag(Map.of((t as CompoundTag).value));
        final x = c.getInt('x')!, y = c.getInt('y')!, z = c.getInt('z')!;
        s.blockEntities[s.index(x + x0 - minX, y + y0 - minY, z + z0 - minZ)] = c;
      }
      for (final t in r.getList('Entities')?.value ?? const <Tag>[]) {
        final c = CompoundTag(Map.of((t as CompoundTag).value));
        final pos = c.getList('Pos');
        if (pos != null && pos.length == 3) {
          c['Pos'] = ListTag(TagId.double_, [
            DoubleTag((pos[0] as DoubleTag).value + x0 - minX),
            DoubleTag((pos[1] as DoubleTag).value + y0 - minY),
            DoubleTag((pos[2] as DoubleTag).value + z0 - minZ),
          ]);
        }
        s.entities.add(c);
      }
    }
    return s;
  }

  static int _bitsFor(int n) {
    var b = 0;
    while ((1 << b) < n) {
      b++;
    }
    return b;
  }

  static Uint8List _writeLitematic(Structure s) {
    // litematica requires air at palette index 0
    final remap = Int32List(s.palette.length);
    final pal = <BlockState>[BlockState.air];
    final seen = <String, int>{BlockState.air.toString(): 0};
    for (var i = 0; i < s.palette.length; i++) {
      final st = s.palette[i] == BlockState.structureVoid ? BlockState.air : s.palette[i];
      remap[i] = seen.putIfAbsent(st.toString(), () {
        pal.add(st);
        return pal.length - 1;
      });
    }
    final bits = math.max(2, _bitsFor(pal.length));
    final longs = Int64List(((s.volume * bits) + 63) >> 6);
    for (var i = 0; i < s.volume; i++) {
      final b = s.blocks[i];
      final v = b < 0 ? 0 : remap[b];
      final bitIndex = i * bits;
      final li = bitIndex >> 6, off = bitIndex & 63;
      longs[li] |= v << off;
      if (off + bits > 64) longs[li + 1] |= v >>> (64 - off);
    }
    final palList = ListTag(TagId.compound, [
      for (final p in pal)
        CompoundTag({
          'Name': StringTag(p.name),
          if (p.props.isNotEmpty) 'Properties': CompoundTag({for (final e in p.props.entries) e.key: StringTag(e.value)}),
        })
    ]);
    final tiles = ListTag(TagId.compound);
    s.blockEntities.forEach((idx, nbt) {
      final (x, y, z) = s.pos(idx);
      tiles.add(CompoundTag(Map.of(nbt.value))
        ..['x'] = IntTag(x)
        ..['y'] = IntTag(y)
        ..['z'] = IntTag(z));
    });
    final now = LongTag(DateTime.now().millisecondsSinceEpoch);
    CompoundTag vec(int x, int y, int z) => CompoundTag({'x': IntTag(x), 'y': IntTag(y), 'z': IntTag(z)});
    final region = CompoundTag({
      'Position': vec(0, 0, 0),
      'Size': vec(s.sx, s.sy, s.sz),
      'BlockStatePalette': palList,
      'BlockStates': LongArrayTag(longs),
      'TileEntities': tiles,
      'Entities': ListTag(TagId.compound, [...s.entities]),
      'PendingBlockTicks': ListTag(TagId.compound),
      'PendingFluidTicks': ListTag(TagId.compound),
    });
    final root = CompoundTag({
      'Version': IntTag(6),
      'SubVersion': IntTag(1),
      'MinecraftDataVersion': IntTag(s.dataVersion),
      'Metadata': CompoundTag({
        'Name': StringTag(s.name.isEmpty ? 'CML' : s.name),
        'Author': StringTag(s.author),
        'Description': StringTag(''),
        'RegionCount': IntTag(1),
        'TotalVolume': IntTag(s.volume),
        'TotalBlocks': IntTag(s.blockCount),
        'TimeCreated': now,
        'TimeModified': now,
        'EnclosingSize': vec(s.sx, s.sy, s.sz),
      }),
      'Regions': CompoundTag({(s.name.isEmpty ? 'main' : s.name): region}),
    });
    return Nbt.compress(Nbt.encode(root), NbtCompression.gzip);
  }

  // ======================= MCEdit .schematic (numeric ids) =======================

  static Structure _readMcedit(Uint8List bytes) {
    final root = Nbt.decodeAuto(bytes).tag;
    if (root.has('BlockData') || root.has('Palette') || root.has('Blocks') && root['Blocks'] is CompoundTag) {
      return _readSchem(bytes); // some tools save Sponge data with .schematic
    }
    final w = root.getInt('Width')!, h = root.getInt('Height')!, l = root.getInt('Length')!;
    final ids = root.getBytes('Blocks')!, data = root.getBytes('Data')!;
    final add = root.getBytes('AddBlocks');
    final s = Structure(w, h, l, dataVersion: 1343);
    final cache = <int, int>{};
    for (var i = 0; i < s.volume; i++) {
      var id = ids[i];
      if (add != null) id |= ((i & 1) == 0 ? (add[i >> 1] & 0x0f) : (add[i >> 1] >> 4) & 0x0f) << 8;
      final key = (id << 4) | (data[i] & 0xf);
      s.blocks[i] = cache.putIfAbsent(key, () => s.idOf(LegacyBlocks.toModern(id, data[i] & 0xf)));
    }
    for (final t in root.getList('TileEntities')?.value ?? const <Tag>[]) {
      final c = CompoundTag(Map.of((t as CompoundTag).value));
      final x = c.getInt('x'), y = c.getInt('y'), z = c.getInt('z');
      if (x != null && y != null && z != null && x < w && y < h && z < l) s.blockEntities[s.index(x, y, z)] = c;
    }
    for (final t in root.getList('Entities')?.value ?? const <Tag>[]) {
      s.entities.add(t as CompoundTag);
    }
    return s;
  }

  static Uint8List _writeMcedit(Structure s) {
    final ids = Uint8List(s.volume), data = Uint8List(s.volume);
    final mapped = [for (final p in s.palette) LegacyBlocks.fromModern(p)];
    for (var i = 0; i < s.volume; i++) {
      final b = s.blocks[i];
      if (b < 0) continue;
      final (id, d) = mapped[b];
      ids[i] = id & 0xff;
      data[i] = d;
    }
    final tiles = ListTag(TagId.compound);
    s.blockEntities.forEach((idx, nbt) {
      final (x, y, z) = s.pos(idx);
      tiles.add(CompoundTag(Map.of(nbt.value))
        ..['x'] = IntTag(x)
        ..['y'] = IntTag(y)
        ..['z'] = IntTag(z));
    });
    final root = CompoundTag({
      'Width': ShortTag(s.sx),
      'Height': ShortTag(s.sy),
      'Length': ShortTag(s.sz),
      'Materials': StringTag('Alpha'),
      'Blocks': ByteArrayTag(ids),
      'Data': ByteArrayTag(data),
      'TileEntities': tiles,
      'Entities': ListTag(TagId.compound),
    });
    return Nbt.compress(Nbt.encode(root, name: 'Schematic'), NbtCompression.gzip);
  }

  // ======================= Vanilla structure block .nbt =======================

  static Structure _readVanillaNbt(Uint8List bytes) {
    final root = Nbt.decodeAuto(bytes).tag;
    final size = root.getList('size')!;
    final s = Structure((size[0] as IntTag).value, (size[1] as IntTag).value, (size[2] as IntTag).value,
        dataVersion: root.getInt('DataVersion') ?? 3955);
    s.blocks.fillRange(0, s.volume, s.idOf(BlockState.structureVoid));
    final palList = root.getList('palette') ?? (root.getList('palettes')?.value.firstOrNull as ListTag?);
    final pal = <int>[];
    for (final t in palList?.value ?? const <Tag>[]) {
      final c = t as CompoundTag;
      final props = <String, String>{};
      c.getCompound('Properties')?.value.forEach((k, v) => props[k] = (v as StringTag).value);
      pal.add(s.idOf(BlockState(c.getString('Name')!, props)));
    }
    for (final t in root.getList('blocks')?.value ?? const <Tag>[]) {
      final c = t as CompoundTag;
      final pos = c.getList('pos')!;
      final idx = s.index((pos[0] as IntTag).value, (pos[1] as IntTag).value, (pos[2] as IntTag).value);
      s.blocks[idx] = pal[c.getInt('state')!];
      final nbt = c.getCompound('nbt');
      if (nbt != null) s.blockEntities[idx] = nbt;
    }
    for (final t in root.getList('entities')?.value ?? const <Tag>[]) {
      final c = t as CompoundTag;
      final n = c.getCompound('nbt');
      if (n == null) continue;
      final e = CompoundTag(Map.of(n.value));
      final pos = c.getList('pos');
      if (pos != null) e['Pos'] = pos;
      s.entities.add(e);
    }
    return s;
  }

  static Uint8List _writeVanillaNbt(Structure s) {
    final voidId = s.palette.indexOf(BlockState.structureVoid);
    final pal = ListTag(TagId.compound);
    final remap = Int32List(s.palette.length)..fillRange(0, s.palette.length, -1);
    final blocks = ListTag(TagId.compound);
    for (var i = 0; i < s.volume; i++) {
      final b = s.blocks[i];
      if (b < 0 || b == voidId) continue;
      if (remap[b] < 0) {
        final p = s.palette[b];
        pal.add(CompoundTag({
          'Name': StringTag(p.name),
          if (p.props.isNotEmpty) 'Properties': CompoundTag({for (final e in p.props.entries) e.key: StringTag(e.value)}),
        }));
        remap[b] = pal.length - 1;
      }
      final (x, y, z) = s.pos(i);
      final be = s.blockEntities[i];
      blocks.add(CompoundTag({
        'pos': ListTag(TagId.int_, [IntTag(x), IntTag(y), IntTag(z)]),
        'state': IntTag(remap[b]),
        'nbt': ?be,
      }));
    }
    final ents = ListTag(TagId.compound);
    for (final e in s.entities) {
      final pos = e.getList('Pos');
      if (pos == null || pos.length != 3) continue;
      final px = (pos[0] as DoubleTag).value, py = (pos[1] as DoubleTag).value, pz = (pos[2] as DoubleTag).value;
      ents.add(CompoundTag({
        'pos': pos,
        'blockPos': ListTag(TagId.int_, [IntTag(px.floor()), IntTag(py.floor()), IntTag(pz.floor())]),
        'nbt': e,
      }));
    }
    final root = CompoundTag({
      'DataVersion': IntTag(s.dataVersion),
      'size': ListTag(TagId.int_, [IntTag(s.sx), IntTag(s.sy), IntTag(s.sz)]),
      'palette': pal,
      'blocks': blocks,
      'entities': ents,
    });
    return Nbt.compress(Nbt.encode(root), NbtCompression.gzip);
  }

  // ======================= Bedrock .mcstructure =======================

  static Structure _readMcstructure(Uint8List bytes) {
    final root = Nbt.decode(bytes, flavor: NbtFlavor.bedrock).tag;
    final size = root.getList('size')!;
    final w = (size[0] as IntTag).value, h = (size[1] as IntTag).value, l = (size[2] as IntTag).value;
    final s = Structure(w, h, l, naming: BlockNaming.bedrock);
    final origin = root.getList('structure_world_origin');
    if (origin != null && origin.length == 3) s.origin = [for (final t in origin.value) (t as IntTag).value];
    final st = root.getCompound('structure')!;
    final layers = st.getList('block_indices')!;
    final def = st.getCompound('palette')!.getCompound('default')!;
    final pal = <int>[];
    for (final t in def.getList('block_palette')!.value) {
      final c = t as CompoundTag;
      final props = <String, String>{};
      c.getCompound('states')?.value.forEach((k, v) => props[k] = '${v.plain is int && v is ByteTag ? (v.value != 0) : v.plain}');
      pal.add(s.idOf(BlockState(c.getString('name')!, props)));
    }
    // mcstructure index order is x,y,z (z fastest)
    final primary = layers[0] as ListTag;
    final secondary = layers.length > 1 ? layers[1] as ListTag : null;
    final hasSecond = secondary != null && secondary.value.any((t) => (t as IntTag).value >= 0);
    if (hasSecond) s.layer2 = Int32List(s.volume)..fillRange(0, s.volume, -1);
    final voidId = s.idOf(BlockState.structureVoid);
    for (var x = 0, i = 0; x < w; x++) {
      for (var y = 0; y < h; y++) {
        for (var z = 0; z < l; z++, i++) {
          final v = (primary[i] as IntTag).value;
          final idx = s.index(x, y, z);
          s.blocks[idx] = v < 0 ? voidId : pal[v];
          if (hasSecond) {
            final v2 = (secondary[i] as IntTag).value;
            if (v2 >= 0) s.layer2![idx] = pal[v2];
          }
        }
      }
    }
    final posData = def.getCompound('block_position_data');
    posData?.value.forEach((k, v) {
      final be = (v as CompoundTag).getCompound('block_entity_data');
      final i = int.tryParse(k);
      if (be == null || i == null) return;
      final x = i ~/ (h * l), y = (i ~/ l) % h, z = i % l;
      s.blockEntities[s.index(x, y, z)] = be;
    });
    for (final t in st.getList('entities')?.value ?? const <Tag>[]) {
      s.entities.add(t as CompoundTag);
    }
    return s;
  }

  static Uint8List _writeMcstructure(Structure s) {
    final pal = ListTag(TagId.compound);
    final remap = Int32List(s.palette.length)..fillRange(0, s.palette.length, -1);
    final voidId = s.palette.indexOf(BlockState.structureVoid);
    int palIndex(int b) {
      if (remap[b] >= 0) return remap[b];
      final p = s.palette[b];
      pal.add(CompoundTag({
        'name': StringTag(p.name),
        'states': CompoundTag({for (final e in p.props.entries) e.key: _bedrockStateTag(e.value)}),
        'version': IntTag(18168865), // 1.21.40.1 block version
      }));
      return remap[b] = pal.length - 1;
    }

    final l1 = ListTag(TagId.int_), l2 = ListTag(TagId.int_);
    final posData = CompoundTag();
    for (var x = 0, i = 0; x < s.sx; x++) {
      for (var y = 0; y < s.sy; y++) {
        for (var z = 0; z < s.sz; z++, i++) {
          final idx = s.index(x, y, z);
          final b = s.blocks[idx];
          l1.add(IntTag(b < 0 || b == voidId ? -1 : palIndex(b)));
          final b2 = s.layer2?[idx] ?? -1;
          l2.add(IntTag(b2 < 0 ? -1 : palIndex(b2)));
          final be = s.blockEntities[idx];
          if (be != null) {
            posData['$i'] = CompoundTag({
              'block_entity_data': CompoundTag(Map.of(be.value))
                ..['x'] = IntTag(x + s.origin[0])
                ..['y'] = IntTag(y + s.origin[1])
                ..['z'] = IntTag(z + s.origin[2])
            });
          }
        }
      }
    }
    final root = CompoundTag({
      'format_version': IntTag(1),
      'size': ListTag(TagId.int_, [IntTag(s.sx), IntTag(s.sy), IntTag(s.sz)]),
      'structure': CompoundTag({
        'block_indices': ListTag(TagId.list, [l1, l2]),
        'entities': ListTag(TagId.compound, [...s.entities]),
        'palette': CompoundTag({
          'default': CompoundTag({'block_palette': pal, 'block_position_data': posData}),
        }),
      }),
      'structure_world_origin': ListTag(TagId.int_, [for (final o in s.origin) IntTag(o)]),
    });
    return Nbt.encode(root, flavor: NbtFlavor.bedrock);
  }

  static Tag _bedrockStateTag(String v) {
    if (v == 'true') return ByteTag(1);
    if (v == 'false') return ByteTag(0);
    final i = int.tryParse(v);
    return i != null ? IntTag(i) : StringTag(v);
  }

  // ======================= BDX (PhoenixBuilder / FastBuilder) =======================

  /// BDX = "BD@" + brotli("BDX\0" + author + "\0" + ops… + "XE"). Bedrock block names.
  static Structure _readBdx(Uint8List bytes) {
    if (bytes.length < 3 || bytes[0] != 0x42 || bytes[1] != 0x44 || bytes[2] != 0x40) throw const FormatException('不是 BDX 文件');
    final d = Uint8List.fromList(brotli.decode(bytes.sublist(3)));
    if (d[0] != 0x42 || d[1] != 0x44 || d[2] != 0x58 || d[3] != 0) throw const FormatException('BDX 内部头错误');
    final bd = ByteData.sublistView(d);
    var p = 4;
    String str() {
      final st = p;
      while (d[p] != 0) {
        p++;
      }
      final s = utf8.decode(d.sublist(st, p), allowMalformed: true);
      p++;
      return s;
    }

    final author = str();
    final strings = <String>[];
    final placed = <(int, int, int, BlockState, CompoundTag?)>[];
    var x = 0, y = 0, z = 0;
    int u16() => bd.getUint16((p += 2) - 2);
    int i16() => bd.getInt16((p += 2) - 2);
    int u32() => bd.getUint32((p += 4) - 4);
    int i32() => bd.getInt32((p += 4) - 4);
    void put(BlockState b, [CompoundTag? nbt]) => placed.add((x, y, z, b, nbt));
    BlockState legacy(int nameId, int data) {
      final name = strings[nameId];
      return BlockState(name.contains(':') ? name : 'minecraft:$name', data == 0 ? const {} : {'__data': '$data'});
    }

    CompoundTag cmdData() {
      final mode = u32();
      final cmd = str(), customName = str(), lastOutput = str();
      final tickDelay = u32();
      final first = d[p++], track = d[p++], cond = d[p++], redstone = d[p++];
      return CompoundTag({
        'id': StringTag('CommandBlock'),
        'Command': StringTag(cmd),
        'CustomName': StringTag(customName),
        'LastOutput': StringTag(lastOutput),
        'TickDelay': IntTag(tickDelay),
        'ExecuteOnFirstTick': ByteTag(first),
        'TrackOutput': ByteTag(track),
        'conditionalMode': ByteTag(cond),
        'auto': ByteTag(redstone == 0 ? 1 : 0),
        'LPCommandMode': IntTag(mode),
      });
    }

    var runtimeIdPoolWarned = false;
    loop:
    while (p < d.length) {
      final op = d[p++];
      switch (op) {
        case 88: // 'X' end
          break loop;
        case 1:
          strings.add(str());
        case 5: // block name id + states string id
          final n = u16(), st = u16();
          put(_bdxState(strings[n], strings[st]));
        case 6:
          z += u16();
        case 7:
          final n = u16(), data = u16();
          put(legacy(n, data));
        case 8:
          z++;
        case 9: // NOP
          break;
        case 12:
          z += u32();
        case 13: // deprecated: name id + inline states string
          final n = u16();
          put(_bdxState(strings[n], str()));
        case 14:
          x++;
        case 15:
          x--;
        case 16:
          y++;
        case 17:
          y--;
        case 18:
          z++;
        case 19:
          z--;
        case 20:
          x += i16();
        case 21:
          x += i32();
        case 22:
          y += i16();
        case 23:
          y += i32();
        case 24:
          z += i16();
        case 25:
          z += i32();
        case 26: // set command block data at current position
          final c = cmdData();
          if (placed.isNotEmpty && placed.last.$1 == x && placed.last.$2 == y && placed.last.$3 == z) {
            final last = placed.removeLast();
            placed.add((x, y, z, last.$4, c));
          }
        case 27:
          final n = u16(), data = u16();
          put(legacy(n, data), cmdData());
        case 28:
          x += bd.getInt8(p++);
        case 29:
          y += bd.getInt8(p++);
        case 30:
          z += bd.getInt8(p++);
        case 31: // runtime id pool – Bedrock runtime ids are version-specific; we cannot resolve them
          p++;
          runtimeIdPoolWarned = true;
        case 32 || 33:
          u16();
          runtimeIdPoolWarned = true;
        case 34:
          u16();
          cmdData();
          runtimeIdPoolWarned = true;
        case 35:
          u32();
          cmdData();
          runtimeIdPoolWarned = true;
        case 36: // command block with data (block data = facing)
          final data = u16();
          final c = cmdData();
          final mode = (c.getInt('LPCommandMode') ?? 0);
          put(BlockState(switch (mode) { 1 => 'minecraft:repeating_command_block', 2 => 'minecraft:chain_command_block', _ => 'minecraft:command_block' }, {'__data': '$data'}), c);
        case 37 || 38:
          if (op == 37) {
            u16();
          } else {
            u32();
          }
          final slots = d[p++];
          for (var i = 0; i < slots; i++) {
            str();
            p += 4;
          }
          runtimeIdPoolWarned = true;
        case 39:
          final n = u32();
          p += n;
        case 40: // block + chest data
          final n = u16(), data = u16();
          final slots = d[p++];
          final items = ListTag(TagId.compound);
          for (var i = 0; i < slots; i++) {
            final name = str();
            final count = d[p++];
            final dmg = u16();
            final slot = d[p++];
            items.add(CompoundTag({'Name': StringTag(name.contains(':') ? name : 'minecraft:$name'), 'Count': ByteTag(count), 'Damage': ShortTag(dmg), 'Slot': ByteTag(slot)}));
          }
          put(legacy(n, data), CompoundTag({'Items': items}));
        case 41: // block + states + NBT (little-endian bedrock NBT)
          final n = u16(), st = u16();
          u16();
          final r = NbtReader(d, NbtFlavor.bedrock, p);
          final nbt = r.readRoot().tag;
          p = r.pos;
          put(_bdxState(strings[n], strings[st]), nbt);
        default:
          throw FormatException('未知 BDX 指令 $op（位置 $p）');
      }
    }
    if (placed.isEmpty) {
      if (runtimeIdPoolWarned) throw const FormatException('该 BDX 使用运行时方块 ID，无法离线解析');
      return Structure(1, 1, 1, naming: BlockNaming.bedrock, author: author);
    }
    var minX = placed.first.$1, minY = placed.first.$2, minZ = placed.first.$3, maxX = minX, maxY = minY, maxZ = minZ;
    for (final b in placed) {
      minX = math.min(minX, b.$1);
      maxX = math.max(maxX, b.$1);
      minY = math.min(minY, b.$2);
      maxY = math.max(maxY, b.$2);
      minZ = math.min(minZ, b.$3);
      maxZ = math.max(maxZ, b.$3);
    }
    final s = Structure(maxX - minX + 1, maxY - minY + 1, maxZ - minZ + 1, naming: BlockNaming.bedrock, author: author);
    s.blocks.fillRange(0, s.volume, s.idOf(BlockState.structureVoid));
    for (final b in placed) {
      final idx = s.index(b.$1 - minX, b.$2 - minY, b.$3 - minZ);
      s.blocks[idx] = s.idOf(LegacyBlocks.resolveBedrockData(b.$4));
      if (b.$5 != null) s.blockEntities[idx] = b.$5!;
    }
    return s;
  }

  static BlockState _bdxState(String name, String states) {
    final n = name.contains(':') ? name : 'minecraft:$name';
    final t = states.trim();
    if (t.isEmpty || t == '[]' || t == '{}') return BlockState(n);
    return BlockState.parse('$n${t.startsWith('[') ? t : '[$t]'}');
  }

  static Uint8List _writeBdx(Structure s) {
    final out = BytesBuilder();
    out.add(utf8.encode('BDX'));
    out.addByte(0);
    out.add(utf8.encode(s.author.isEmpty ? 'ChthollyMinecraftLauncher' : s.author));
    out.addByte(0);
    final strIds = <String, int>{};
    final scratch = ByteData(4);
    void u16(int v) {
      scratch.setUint16(0, v);
      out.add(Uint8List.fromList(scratch.buffer.asUint8List(0, 2)));
    }

    void i32(int v) {
      scratch.setInt32(0, v);
      out.add(Uint8List.fromList(scratch.buffer.asUint8List(0, 4)));
    }

    int sid(String v) => strIds.putIfAbsent(v, () {
          out.addByte(1);
          out.add(utf8.encode(v));
          out.addByte(0);
          return strIds.length;
        });

    void move(int op8, int op32, int delta) {
      if (delta == 0) return;
      if (delta >= -128 && delta <= 127) {
        out.addByte(op8);
        out.addByte(delta & 0xff);
      } else {
        out.addByte(op32);
        i32(delta);
      }
    }

    final voidId = s.palette.indexOf(BlockState.structureVoid);
    var cx = 0, cy = 0, cz = 0;
    for (var x = 0; x < s.sx; x++) {
      for (var y = 0; y < s.sy; y++) {
        for (var z = 0; z < s.sz; z++) {
          final b = s.blocks[s.index(x, y, z)];
          if (b < 0 || b == voidId || s.palette[b].isAir) continue;
          move(28, 21, x - cx);
          move(29, 23, y - cy);
          move(30, 25, z - cz);
          cx = x;
          cy = y;
          cz = z;
          final st = s.palette[b];
          final name = st.name.startsWith('minecraft:') ? st.name.substring(10) : st.name;
          final n = sid(name);
          final states = sid(st.toBedrockStates());
          out.addByte(5);
          u16(n);
          u16(states);
        }
      }
    }
    out.add(utf8.encode('XE'));
    return Uint8List.fromList([0x42, 0x44, 0x40, ...brotliStore(out.takeBytes())]);
  }
}

/// Pre-1.13 numeric block ids (MCEdit .schematic and BDX legacy data values).
abstract class LegacyBlocks {
  static const _names = <int, String>{
    0: 'air', 1: 'stone', 2: 'grass_block', 3: 'dirt', 4: 'cobblestone', 5: 'oak_planks', 6: 'oak_sapling', 7: 'bedrock',
    8: 'water', 9: 'water', 10: 'lava', 11: 'lava', 12: 'sand', 13: 'gravel', 14: 'gold_ore', 15: 'iron_ore', 16: 'coal_ore',
    17: 'oak_log', 18: 'oak_leaves', 19: 'sponge', 20: 'glass', 21: 'lapis_ore', 22: 'lapis_block', 23: 'dispenser',
    24: 'sandstone', 25: 'note_block', 26: 'red_bed', 27: 'powered_rail', 28: 'detector_rail', 29: 'sticky_piston', 30: 'cobweb',
    31: 'short_grass', 32: 'dead_bush', 33: 'piston', 35: 'white_wool', 37: 'dandelion', 38: 'poppy', 39: 'brown_mushroom',
    40: 'red_mushroom', 41: 'gold_block', 42: 'iron_block', 43: 'smooth_stone_slab', 44: 'smooth_stone_slab', 45: 'bricks',
    46: 'tnt', 47: 'bookshelf', 48: 'mossy_cobblestone', 49: 'obsidian', 50: 'torch', 51: 'fire', 52: 'spawner',
    53: 'oak_stairs', 54: 'chest', 55: 'redstone_wire', 56: 'diamond_ore', 57: 'diamond_block', 58: 'crafting_table',
    59: 'wheat', 60: 'farmland', 61: 'furnace', 62: 'furnace', 63: 'oak_sign', 64: 'oak_door', 65: 'ladder', 66: 'rail',
    67: 'cobblestone_stairs', 68: 'oak_wall_sign', 69: 'lever', 70: 'stone_pressure_plate', 71: 'iron_door',
    72: 'oak_pressure_plate', 73: 'redstone_ore', 74: 'redstone_ore', 75: 'redstone_torch', 76: 'redstone_torch',
    77: 'stone_button', 78: 'snow', 79: 'ice', 80: 'snow_block', 81: 'cactus', 82: 'clay', 83: 'sugar_cane', 84: 'jukebox',
    85: 'oak_fence', 86: 'carved_pumpkin', 87: 'netherrack', 88: 'soul_sand', 89: 'glowstone', 90: 'nether_portal',
    91: 'jack_o_lantern', 92: 'cake', 93: 'repeater', 94: 'repeater', 95: 'white_stained_glass', 96: 'oak_trapdoor',
    97: 'infested_stone', 98: 'stone_bricks', 99: 'brown_mushroom_block', 100: 'red_mushroom_block', 101: 'iron_bars',
    102: 'glass_pane', 103: 'melon', 104: 'pumpkin_stem', 105: 'melon_stem', 106: 'vine', 107: 'oak_fence_gate',
    108: 'brick_stairs', 109: 'stone_brick_stairs', 110: 'mycelium', 111: 'lily_pad', 112: 'nether_bricks',
    113: 'nether_brick_fence', 114: 'nether_brick_stairs', 115: 'nether_wart', 116: 'enchanting_table', 117: 'brewing_stand',
    118: 'cauldron', 119: 'end_portal', 120: 'end_portal_frame', 121: 'end_stone', 122: 'dragon_egg', 123: 'redstone_lamp',
    124: 'redstone_lamp', 125: 'oak_slab', 126: 'oak_slab', 127: 'cocoa', 128: 'sandstone_stairs', 129: 'emerald_ore',
    130: 'ender_chest', 131: 'tripwire_hook', 132: 'tripwire', 133: 'emerald_block', 134: 'spruce_stairs', 135: 'birch_stairs',
    136: 'jungle_stairs', 137: 'command_block', 138: 'beacon', 139: 'cobblestone_wall', 140: 'flower_pot', 141: 'carrots',
    142: 'potatoes', 143: 'oak_button', 144: 'skeleton_skull', 145: 'anvil', 146: 'trapped_chest',
    147: 'light_weighted_pressure_plate', 148: 'heavy_weighted_pressure_plate', 149: 'comparator', 150: 'comparator',
    151: 'daylight_detector', 152: 'redstone_block', 153: 'nether_quartz_ore', 154: 'hopper', 155: 'quartz_block',
    156: 'quartz_stairs', 157: 'activator_rail', 158: 'dropper', 159: 'white_terracotta', 160: 'white_stained_glass_pane',
    161: 'acacia_leaves', 162: 'acacia_log', 163: 'acacia_stairs', 164: 'dark_oak_stairs', 165: 'slime_block', 166: 'barrier',
    167: 'iron_trapdoor', 168: 'prismarine', 169: 'sea_lantern', 170: 'hay_block', 171: 'white_carpet', 172: 'terracotta',
    173: 'coal_block', 174: 'packed_ice', 175: 'sunflower', 176: 'white_banner', 177: 'white_wall_banner',
    178: 'daylight_detector', 179: 'red_sandstone', 180: 'red_sandstone_stairs', 181: 'red_sandstone_slab',
    182: 'red_sandstone_slab', 183: 'spruce_fence_gate', 184: 'birch_fence_gate', 185: 'jungle_fence_gate',
    186: 'dark_oak_fence_gate', 187: 'acacia_fence_gate', 188: 'spruce_fence', 189: 'birch_fence', 190: 'jungle_fence',
    191: 'dark_oak_fence', 192: 'acacia_fence', 193: 'spruce_door', 194: 'birch_door', 195: 'jungle_door', 196: 'acacia_door',
    197: 'dark_oak_door', 198: 'end_rod', 199: 'chorus_plant', 200: 'chorus_flower', 201: 'purpur_block', 202: 'purpur_pillar',
    203: 'purpur_stairs', 204: 'purpur_slab', 205: 'purpur_slab', 206: 'end_stone_bricks', 207: 'beetroots', 208: 'dirt_path',
    209: 'end_gateway', 210: 'repeating_command_block', 211: 'chain_command_block', 212: 'frosted_ice', 213: 'magma_block',
    214: 'nether_wart_block', 215: 'red_nether_bricks', 216: 'bone_block', 217: 'structure_void', 218: 'observer',
    219: 'white_shulker_box', 235: 'white_glazed_terracotta', 251: 'white_concrete', 252: 'white_concrete_powder',
    255: 'structure_block',
  };

  static const _colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray', 'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'];
  static const _colored = {35: 'wool', 95: 'stained_glass', 159: 'terracotta', 160: 'stained_glass_pane', 171: 'carpet', 251: 'concrete', 252: 'concrete_powder'};

  /// Best-effort numeric id + data → modern Java block state. Data-driven variants (colours, wood, stone types)
  /// are resolved; orientation data is dropped.
  static BlockState toModern(int id, int data) {
    final c = _colored[id];
    if (c != null) return BlockState('minecraft:${_colors[data & 15]}_$c');
    if (id >= 219 && id <= 234) return BlockState('minecraft:${_colors[id - 219]}_shulker_box');
    if (id >= 235 && id <= 250) return BlockState('minecraft:${_colors[id - 235]}_glazed_terracotta');
    const woods = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak'];
    switch (id) {
      case 1:
        return BlockState('minecraft:${const ['stone', 'granite', 'polished_granite', 'diorite', 'polished_diorite', 'andesite', 'polished_andesite'][data % 7]}');
      case 3:
        return BlockState('minecraft:${const ['dirt', 'coarse_dirt', 'podzol'][data % 3]}');
      case 5:
        return BlockState('minecraft:${woods[data % 6]}_planks');
      case 6:
        return BlockState('minecraft:${woods[(data & 7) % 6]}_sapling');
      case 12:
        return BlockState(data == 1 ? 'minecraft:red_sand' : 'minecraft:sand');
      case 17:
        return BlockState('minecraft:${woods[data & 3]}_log', {'axis': const ['y', 'x', 'z', 'y'][(data >> 2) & 3]});
      case 18:
        return BlockState('minecraft:${woods[data & 3]}_leaves', {'persistent': 'true'});
      case 162:
        return BlockState('minecraft:${woods[4 + (data & 1)]}_log', {'axis': const ['y', 'x', 'z', 'y'][(data >> 2) & 3]});
      case 161:
        return BlockState('minecraft:${woods[4 + (data & 1)]}_leaves', {'persistent': 'true'});
      case 24:
        return BlockState('minecraft:${const ['sandstone', 'chiseled_sandstone', 'cut_sandstone'][data % 3]}');
      case 98:
        return BlockState('minecraft:${const ['stone_bricks', 'mossy_stone_bricks', 'cracked_stone_bricks', 'chiseled_stone_bricks'][data % 4]}');
      case 155:
        return BlockState('minecraft:${const ['quartz_block', 'chiseled_quartz_block', 'quartz_pillar', 'quartz_pillar', 'quartz_pillar'][data % 5]}');
      case 168:
        return BlockState('minecraft:${const ['prismarine', 'prismarine_bricks', 'dark_prismarine'][data % 3]}');
      case 43:
        return BlockState('minecraft:${const ['smooth_stone', 'sandstone', 'oak_planks', 'cobblestone', 'bricks', 'stone_bricks', 'nether_bricks', 'quartz_block'][data & 7]}');
      case 44:
        return BlockState('minecraft:${const ['smooth_stone', 'sandstone', 'petrified_oak', 'cobblestone', 'brick', 'stone_brick', 'nether_brick', 'quartz'][data & 7]}_slab', {'type': data & 8 != 0 ? 'top' : 'bottom'});
      case 126:
        return BlockState('minecraft:${woods[(data & 7) % 6]}_slab', {'type': data & 8 != 0 ? 'top' : 'bottom'});
      case 125:
        return BlockState('minecraft:${woods[(data & 7) % 6]}_planks');
      case 38:
        return BlockState('minecraft:${const ['poppy', 'blue_orchid', 'allium', 'azure_bluet', 'red_tulip', 'orange_tulip', 'white_tulip', 'pink_tulip', 'oxeye_daisy'][data % 9]}');
      case 31:
        return BlockState(data == 2 ? 'minecraft:fern' : 'minecraft:short_grass');
      case 8 || 9:
        return BlockState('minecraft:water', {'level': '${data & 15}'});
      case 10 || 11:
        return BlockState('minecraft:lava', {'level': '${data & 15}'});
      case 139:
        return BlockState(data == 1 ? 'minecraft:mossy_cobblestone_wall' : 'minecraft:cobblestone_wall');
      case 19:
        return BlockState(data == 1 ? 'minecraft:wet_sponge' : 'minecraft:sponge');
      case 179:
        return BlockState('minecraft:${const ['red_sandstone', 'chiseled_red_sandstone', 'cut_red_sandstone'][data % 3]}');
    }
    final n = _names[id];
    return n == null ? BlockState.air : BlockState('minecraft:$n');
  }

  /// Modern Java state → numeric id/data (for writing .schematic). Unknown blocks become stone.
  static (int, int) fromModern(BlockState s) {
    final name = s.name.replaceFirst('minecraft:', '');
    for (final e in _colored.entries) {
      if (name.endsWith('_${e.value}')) {
        final col = name.substring(0, name.length - e.value.length - 1);
        final i = _colors.indexOf(col);
        if (i >= 0) return (e.key, i);
      }
    }
    if (s.isAir || name == 'structure_void') return (0, 0);
    for (final e in _names.entries) {
      if (e.value == name) return (e.key, 0);
    }
    const woods = ['oak', 'spruce', 'birch', 'jungle', 'acacia', 'dark_oak'];
    for (var i = 0; i < woods.length; i++) {
      if (name == '${woods[i]}_planks') return (5, i);
      if (name == '${woods[i]}_log') return i < 4 ? (17, i) : (162, i - 4);
    }
    const stones = ['stone', 'granite', 'polished_granite', 'diorite', 'polished_diorite', 'andesite', 'polished_andesite'];
    final si = stones.indexOf(name);
    if (si >= 0) return (1, si);
    return (1, 0);
  }

  /// Bedrock legacy data values in BDX op 7: `wool` + data → `white_wool` etc.
  static BlockState resolveBedrockData(BlockState b) {
    final data = int.tryParse(b.props['__data'] ?? '');
    if (data == null) return b;
    final name = b.name.replaceFirst('minecraft:', '');
    const bedrockColored = {'wool', 'concrete', 'concrete_powder', 'stained_glass', 'stained_glass_pane', 'carpet', 'shulker_box', 'stained_hardened_clay'};
    if (bedrockColored.contains(name)) {
      final c = _colors[data & 15];
      return BlockState('minecraft:${c}_${name == 'stained_hardened_clay' ? 'terracotta' : name}');
    }
    if (name.endsWith('command_block')) {
      return BlockState(b.name, {'facing_direction': '${data & 7}', 'conditional_bit': '${data & 8 != 0}'});
    }
    return BlockState(b.name);
  }
}
