import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:cml_core/cml_core.dart';
import 'package:cml_core/src/structure/brotli_store.dart';
import 'package:test/test.dart';

Structure sample() {
  final s = Structure(3, 2, 4, name: 'test');
  s.set(0, 0, 0, const BlockState('minecraft:stone'));
  s.set(1, 0, 0, const BlockState('minecraft:oak_stairs', {'facing': 'east', 'half': 'bottom', 'shape': 'straight', 'waterlogged': 'false'}));
  s.set(2, 1, 3, const BlockState('minecraft:red_wool'));
  s.set(1, 1, 2, const BlockState('minecraft:chest', {'facing': 'north', 'type': 'single', 'waterlogged': 'false'}));
  s.blockEntities[s.index(1, 1, 2)] = CompoundTag({'id': StringTag('minecraft:chest'), 'Items': ListTag(TagId.compound)});
  return s;
}

void expectSameBlocks(Structure a, Structure b) {
  expect([b.sx, b.sy, b.sz], [a.sx, a.sy, a.sz]);
  for (var x = 0; x < a.sx; x++) {
    for (var y = 0; y < a.sy; y++) {
      for (var z = 0; z < a.sz; z++) {
        final ea = a.get(x, y, z)!, eb = b.get(x, y, z)!;
        if (ea.isAir && (eb.isAir || eb == BlockState.structureVoid)) continue;
        expect(eb.toString(), ea.toString(), reason: 'at $x,$y,$z');
      }
    }
  }
}

void main() {
  group('NBT', () {
    test('java round trip', () {
      final t = CompoundTag({
        'a': ByteTag(-3),
        's': StringTag('中文 \u0000 ok 😀'),
        'l': ListTag(TagId.int_, [IntTag(1), IntTag(2)]),
        'la': LongArrayTag(Int64List.fromList([1 << 40, -1])),
      });
      final r = Nbt.decode(Nbt.encode(t, name: 'root'));
      expect(r.name, 'root');
      expect(r.tag.getString('s'), '中文 \u0000 ok 😀');
      expect(r.tag.getLongs('la'), [1 << 40, -1]);
    });

    test('bedrock level.dat round trip', () {
      final root = NamedTag('', CompoundTag({'LevelName': StringTag('世界'), 'GameType': IntTag(1)}));
      final (v, back) = Nbt.decodeBedrockLevelDat(Nbt.encodeBedrockLevelDat(10, root));
      expect(v, 10);
      expect(back.tag.getString('LevelName'), '世界');
    });
  });

  group('structures', () {
    for (final f in [StructureFormat.schem, StructureFormat.litematic, StructureFormat.nbt]) {
      test('${f.ext} round trip', () {
        final s = sample();
        final back = StructureIO.read(StructureIO.write(s, f), f);
        expectSameBlocks(s, back);
        expect(back.blockEntities.length, 1);
      });
    }

    test('litematic packing across long boundaries', () {
      // 37 palette entries → 6 bits, crosses 64-bit boundaries
      final s = Structure(7, 5, 3);
      final names = ['stone', 'dirt', 'glass', 'sand', 'gravel', 'oak_planks', 'bricks', 'tnt', 'obsidian', 'ice'];
      var n = 0;
      for (var y = 0; y < 5; y++) {
        for (var z = 0; z < 3; z++) {
          for (var x = 0; x < 7; x++) {
            s.set(x, y, z, BlockState('minecraft:${names[n % names.length]}', {'v': '${n % 4}'}));
            n++;
          }
        }
      }
      expectSameBlocks(s, StructureIO.read(StructureIO.write(s, StructureFormat.litematic), StructureFormat.litematic));
    });

    test('java → mcstructure → java keeps blocks', () {
      final s = sample();
      final bytes = StructureConverter.encode(s, StructureFormat.mcstructure);
      final b = StructureIO.read(bytes, StructureFormat.mcstructure);
      expect(b.naming, BlockNaming.bedrock);
      expect(b.get(2, 1, 3)!.name, 'minecraft:red_wool');
      expect(b.get(1, 0, 0)!.name, 'minecraft:oak_stairs');
      expect(b.get(1, 0, 0)!.props['weirdo_direction'], '0');
      BlockMapper.instance.convert(b, BlockNaming.java);
      expect(b.get(1, 0, 0)!.props['facing'], 'east');
      expect(b.get(0, 0, 0)!.name, 'minecraft:stone');
    });

    test('bdx round trip', () {
      final s = sample();
      final bytes = StructureConverter.encode(s, StructureFormat.bdx);
      expect(String.fromCharCodes(bytes.sublist(0, 3)), 'BD@');
      final b = StructureIO.read(bytes, StructureFormat.bdx);
      expect(b.blockCount, s.blockCount);
      final names = b.materials().keys.toSet();
      expect(names, containsAll(['minecraft:stone', 'minecraft:red_wool', 'minecraft:oak_stairs', 'minecraft:chest']));
    });

    test('mcedit legacy ids', () {
      final s = Structure(2, 1, 1);
      s.set(0, 0, 0, const BlockState('minecraft:red_wool'));
      s.set(1, 0, 0, const BlockState('minecraft:granite'));
      final b = StructureIO.read(StructureIO.write(s, StructureFormat.schematic), StructureFormat.schematic);
      expect(b.get(0, 0, 0)!.name, 'minecraft:red_wool');
      expect(b.get(1, 0, 0)!.name, 'minecraft:granite');
    });

    test('brotli store encoder is decodable', () {
      final data = Uint8List.fromList(List.generate(200000, (i) => i * 7 & 0xff));
      expect(brotli.decode(brotliStore(data)), data);
      expect(brotli.decode(brotliStore(const [])), isEmpty);
    });
  });

  group('favorites', () {
    test('folders, toggle, rename, persistence', () async {
      final dir = await Directory.systemTemp.createTemp('cml-fav');
      final path = '${dir.path}/fav.json';
      final f = Favorites(path);
      await f.load();
      expect(f.folders.single.name, '收藏');
      await f.toggle('D:/MC/.minecraft', '1.21.1');
      expect(f.isFavorite('d:/mc/.minecraft', '1.21.1'), isTrue);
      final pvp = await f.addFolder('PVP');
      await f.setFolders('D:/MC/.minecraft', '1.8.9', {pvp, f.defaultFolder});
      await f.onRenamed('D:/MC/.minecraft', '1.8.9', '1.8.9-OptiFine');
      final g = Favorites(path);
      await g.load();
      expect(g.folders.map((e) => e.name), ['收藏', 'PVP']);
      expect(g.foldersOf('D:/MC/.minecraft', '1.8.9-OptiFine').length, 2);
      await g.onDeleted('D:/MC/.minecraft', '1.8.9-OptiFine');
      expect(g.isFavorite('D:/MC/.minecraft', '1.8.9-OptiFine'), isFalse);
      await g.removeFolder(g.defaultFolder);
      expect(g.folders.length, 2, reason: 'default folder cannot be removed');
      await dir.delete(recursive: true);
    });
  });

  group('launch', () {
    test('splitArgs honours quotes', () {
      expect(Launcher.splitArgs('-Xss2m "-Dfoo=a b" -XX:+X'), ['-Xss2m', '-Dfoo=a b', '-XX:+X']);
    });

    test('maven path', () {
      expect(MavenName.parse('org.lwjgl:lwjgl:3.3.3:natives-windows').path, 'org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-windows.jar');
      expect(MavenName.parse('de.oceanlabs.mcp:mcp_config:1.20.1@zip').path, 'de/oceanlabs/mcp/mcp_config/1.20.1/mcp_config-1.20.1.zip');
    });

    test('neoforge mc mapping', () {
      expect(LoaderInstaller.neoForgeMc('21.1.65'), '1.21.1');
      expect(LoaderInstaller.neoForgeMc('21.0.10-beta'), '1.21');
      expect(LoaderInstaller.neoForgeMc('20.4.237'), '1.20.4');
      expect(LoaderInstaller.neoForgeMc('26.1.0.5'), '26.1');
    });

    test('rules', () {
      expect(Rules.allows([{'action': 'allow'}, {'action': 'disallow', 'os': {'name': 'osx'}}]), isTrue);
      expect(Rules.allows([{'action': 'allow', 'os': {'name': 'osx'}}]), isFalse);
    });

    test('crash analyzer', () {
      expect(CrashAnalyzer.analyze('java.lang.OutOfMemoryError: Java heap space'), contains('内存'));
    });

    test('auto memory', () {
      final mb = Memory.autoAllocateMb(modCount: 100, modern: true, mem: MemoryInfo(16384, 10000, 40));
      expect(mb, inInclusiveRange(4096, 9830));
      expect(Memory.autoAllocateMb(modCount: 0, modern: true, mem: MemoryInfo(4096, 1500, 70)), 1024);
    });
  });
}
