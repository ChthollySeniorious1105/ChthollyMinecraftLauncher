import 'dart:io';
import 'dart:typed_data';

import 'package:cml_core/cml_core.dart';
import 'package:cml_core/src/resourcepack/pack_files.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Uint8List png(int w, int h, [int r = 200, int g = 100, int b = 50]) {
  final i = img.Image(width: w, height: h, numChannels: 4);
  img.fill(i, color: img.ColorRgba8(r, g, b, 255));
  return Uint8List.fromList(img.encodePng(i));
}

Future<String> writePack(Directory d, String name, Map<String, Object> files) async {
  final dir = Directory(p.join(d.path, name));
  for (final e in files.entries) {
    final f = File(p.join(dir.path, e.key));
    await f.parent.create(recursive: true);
    final v = e.value;
    if (v is String) {
      await f.writeAsString(v);
    } else {
      await f.writeAsBytes(v as List<int>);
    }
  }
  return dir.path;
}

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('cml-rp'));
  tearDown(() async => tmp.delete(recursive: true));

  test('timeline loads', () {
    final t = JavaPackTimeline.instance;
    expect(t.versions.first, '1.8.9');
    expect(t.formatOf('1.20.1'), 15);
    expect(t.versionForFormat(15), '1.20.1');
    expect(t.versionForFormat(3), '1.12.2');
  });

  test('1.12 → 1.21 → 1.12 round trip keeps textures, models and animations', () async {
    final src = await writePack(tmp, 'old', {
      'pack.mcmeta': '{"pack":{"pack_format":3,"description":"test"}}',
      'assets/minecraft/textures/blocks/planks_oak.png': png(16, 16),
      'assets/minecraft/textures/blocks/sea_lantern.png': png(16, 80),
      'assets/minecraft/textures/blocks/sea_lantern.png.mcmeta': '{"animation":{"frametime":5}}',
      'assets/minecraft/textures/items/fish_cod_raw.png': png(16, 16, 1, 2, 3),
      'assets/minecraft/models/block/custom.json': '{"textures":{"all":"blocks/planks_oak"}}',
    });
    final r = await ResourcePackConverter.convert(src, PackTarget.all.firstWhere((t) => t.javaVersion == '1.21.1'), sky: SkyMode.keep);
    final out = await ResourcePackConverter.read(r.output);
    expect(out.has('assets/minecraft/textures/block/oak_planks.png'), isTrue);
    expect(out.has('assets/minecraft/textures/block/sea_lantern.png.mcmeta'), isTrue);
    expect(out.has('assets/minecraft/textures/item/cod.png'), isTrue);
    expect(out.text('assets/minecraft/models/block/custom.json'), contains('block/oak_planks'));
    expect((out.json('pack.mcmeta') as Map)['pack']['pack_format'], 34);

    final back = await ResourcePackConverter.convert(r.output, PackTarget.all.firstWhere((t) => t.javaVersion == '1.12.2'), sky: SkyMode.keep);
    final b = await ResourcePackConverter.read(back.output);
    expect(b.has('assets/minecraft/textures/blocks/planks_oak.png'), isTrue);
    expect(b.text('assets/minecraft/models/block/custom.json'), contains('blocks/planks_oak'));
  });

  test('1.20.1 gui atlas is sliced into 1.20.2 sprites and re-assembled backwards', () async {
    // a 2x HD widgets.png
    final w = img.Image(width: 512, height: 512, numChannels: 4);
    img.fill(w, color: img.ColorRgba8(10, 200, 30, 255));
    final src = await writePack(tmp, 'gui', {
      'pack.mcmeta': '{"pack":{"pack_format":15,"description":"gui"}}',
      'assets/minecraft/textures/gui/widgets.png': Uint8List.fromList(img.encodePng(w)),
    });
    final r = await ResourcePackConverter.convert(src, PackTarget.all.firstWhere((t) => t.javaVersion == '1.20.2'), sky: SkyMode.keep);
    final out = await ResourcePackConverter.read(r.output);
    final sprites = out.paths.where((k) => k.startsWith('assets/minecraft/textures/gui/sprites/')).toList();
    expect(sprites, isNotEmpty);
    final one = out.image(sprites.firstWhere((k) => k.endsWith('.png')))!;
    expect(one.getPixel(0, 0).g, 200); // pixels come from the pack, scaled 2x
    expect(r.log.counts['切分贴图'], greaterThan(0));
  });

  test('OptiFine sky → Nuit → OptiFine', () async {
    final src = await writePack(tmp, 'sky', {
      'pack.mcmeta': '{"pack":{"pack_format":34,"description":"sky"}}',
      'assets/minecraft/optifine/sky/world0/sky1.png': png(384, 256),
      'assets/minecraft/optifine/sky/world0/sky1.properties':
          'startFadeIn=18:00\nendFadeIn=19:00\nendFadeOut=06:00\nblend=add\nrotate=true\naxis=0 0 1\nweather=clear\nbiomes=plains desert\nheights=60-(256)\n',
    });
    final r = await ResourcePackConverter.convert(src, PackTarget.all.firstWhere((t) => t.javaVersion == '1.21.1'));
    final out = await ResourcePackConverter.read(r.output);
    final js = out.paths.where((k) => k.startsWith('assets/nuit/sky/') && k.endsWith('.json')).toList();
    expect(js, hasLength(1));
    final j = out.json(js.first) as Map;
    expect(j['type'], 'square-textured');
    final kf = j['properties']['fade']['keyFrames'] as Map;
    expect(kf.keys, containsAll(['12000', '13000', '0']));
    expect(kf['13000'], 1.0);
    expect(j['conditions']['biomes']['entries'], ['minecraft:plains', 'minecraft:desert']);
    expect(out.has('assets/minecraft/optifine/sky/world0/sky1.properties'), isTrue);
    expect(SkyConverter.timeToTick('06:00'), 0);
    expect(SkyConverter.timeToTick('00:00'), 18000);
    expect(SkyConverter.tickToTime(12000), '18:00');
  });

  test('Java → Bedrock → Java', () async {
    final src = await writePack(tmp, 'j2b', {
      'pack.mcmeta': '{"pack":{"pack_format":34,"description":"hello"}}',
      'pack.png': png(64, 64),
      'assets/minecraft/textures/block/oak_planks.png': png(16, 16, 9, 9, 9),
      'assets/minecraft/textures/block/sea_lantern.png': png(16, 80),
      'assets/minecraft/textures/block/sea_lantern.png.mcmeta': '{"animation":{"frametime":5}}',
      'assets/minecraft/textures/environment/sun.png': png(32, 32),
      'assets/minecraft/optifine/sky/world0/sky1.png': png(384, 256, 1, 2, 3),
      'assets/minecraft/optifine/sky/world0/sky1.properties': 'blend=replace\n',
      'assets/minecraft/sounds/random/click.ogg': [1, 2, 3],
    });
    final r = await ResourcePackConverter.convert(src, PackTarget.all.first);
    expect(r.output, endsWith('.mcpack'));
    final bed = await ResourcePackConverter.read(r.output);
    expect(bed.has('manifest.json'), isTrue);
    expect(bed.has('pack_icon.png'), isTrue);
    expect(bed.has('textures/blocks/planks_oak.png'), isTrue);
    final fb = bed.json('textures/flipbook_textures.json') as List;
    expect(fb.single['atlas_tile'], 'sea_lantern');
    expect(fb.single['ticks_per_frame'], 5);
    for (var i = 0; i < 6; i++) {
      expect(bed.has('textures/environment/overworld_cubemap/cubemap_$i.png'), isTrue);
    }
    expect(bed.has('sounds/random/click.ogg'), isTrue);

    final back = await ResourcePackConverter.convert(r.output, PackTarget.all.firstWhere((t) => t.javaVersion == '1.21.1'));
    final j = await ResourcePackConverter.read(back.output);
    expect(j.has('assets/minecraft/textures/block/oak_planks.png'), isTrue);
    expect(j.json('assets/minecraft/textures/block/sea_lantern.png.mcmeta'), {
      'animation': {'frametime': 5}
    });
    final sky = j.image('assets/minecraft/optifine/sky/world0/sky1.png')!;
    expect([sky.width, sky.height], [384, 256]);
    expect(j.has('assets/nuit/sky/cml/world0_sky1.json'), isTrue);
    expect((j.json('pack.mcmeta') as Map)['pack']['pack_format'], 34);
  });

  test('lenient json and properties', () {
    expect(stripJsonComments('{// c\n"a": 1, /* x */ "b": [1,2,],}'), contains('"a": 1'));
    final pf = PackFiles()..setText('x.json', '{// c\n"a": 1,}');
    expect(pf.json('x.json'), {'a': 1});
    expect(parseProperties('a=1\nb : two\\\n three\n# c\nname=\\u00a74x'), {'a': '1', 'b': 'twothree', 'name': '§4x'});
  });

  test('texture map has common entries', () {
    final m = TextureMap.instance;
    expect(m.toBedrock('block/oak_planks'), 'blocks/planks_oak');
    expect(m.toJava('blocks/planks_oak'), 'block/oak_planks');
    expect(m.atlasKey['blocks/water_still'], 'still_water');
  });
}
