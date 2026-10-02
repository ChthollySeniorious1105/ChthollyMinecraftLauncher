import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'data/texture_map_data.dart';
import 'java_migrator.dart';
import 'pack_files.dart';

/// Java texture id (e.g. `block/oak_planks`) ⇄ Bedrock texture path (e.g. `blocks/planks_oak`).
class TextureMap {
  TextureMap._();
  static final instance = TextureMap._().._load();

  final j2b = <String, String>{};
  final b2j = <String, String>{};

  /// Bedrock path → terrain atlas key (for flipbook_textures.json).
  final atlasKey = <String, String>{};

  void _load() {
    final text = utf8.decode(const GZipDecoder().decodeBytes(base64.decode(javaBedrockTexturesGz)));
    for (final l in const LineSplitter().convert(text)) {
      final t = l.split('\t');
      if (t.length < 2) continue;
      j2b[t[0]] = t[1];
      b2j.putIfAbsent(t[1], () => t[0]);
      if (t.length > 2 && t[2].isNotEmpty) atlasKey[t[1]] = t[2];
    }
  }

  /// Fallback for ids missing from the table: same relative path under the Bedrock folder name.
  String toBedrock(String javaId) {
    final hit = j2b[javaId];
    if (hit != null) return hit;
    final top = javaId.split('/').first;
    final rest = javaId.substring(top.length + 1);
    return '${switch (top) { 'block' => 'blocks', 'item' => 'items', _ => top }}/$rest';
  }

  String toJava(String bedrockPath) {
    final hit = b2j[bedrockPath];
    if (hit != null) return hit;
    final top = bedrockPath.split('/').first;
    final rest = bedrockPath.substring(top.length + 1);
    return '${switch (top) { 'blocks' => 'block', 'items' => 'item', _ => top }}/$rest';
  }
}

/// Java ⇄ Bedrock resource pack conversion.
///
/// Converted: block/item/entity/environment/colormap/painting/particle/misc textures (path mapping table
/// built from both editions' vanilla packs), block/item animations (.mcmeta ⇄ flipbook_textures.json),
/// pack icon, name & description (pack.mcmeta ⇄ manifest.json + texts), languages (.json ⇄ .lang),
/// sounds (.ogg + sounds.json ⇄ sound_definitions.json), custom skies (OptiFine/Nuit → Bedrock cubemap
/// and back), sun/moon textures.
/// Not convertible (reported): Java block/item models and shaders, Bedrock entity geometry/materials/UI.
class BedrockPackConverter {
  final TextureMap map = TextureMap.instance;
  static const _jroot = 'assets/minecraft/';

  // ======================================================== Java → Bedrock

  PackFiles toBedrock(PackFiles java, ConvertLog log, {required String name, String description = ''}) {
    final out = PackFiles();
    // Java packs are migrated to the newest layout first so a single table applies.
    final tl = JavaPackTimeline.instance;
    final meta = java.json('pack.mcmeta');
    final fmt = (meta is Map ? ((meta['pack'] as Map?)?['pack_format'] as num?) : null) ?? tl.formatOf(tl.versions.last);
    final from = tl.versionForFormat(fmt);
    if (from != tl.versions.last) JavaPackMigrator().migrate(java, from, tl.versions.last, ConvertLog());

    // ---- textures
    final flipbooks = <Map<String, Object?>>[];
    var textures = 0;
    for (final p in java.paths.toList()..sort()) {
      if (!p.startsWith('${_jroot}textures/') || !p.endsWith('.png')) continue;
      final id = p.substring('${_jroot}textures/'.length, p.length - 4);
      if (id.startsWith('gui/') || id.startsWith('font/') || id.startsWith('effect/')) continue;
      final bed = map.toBedrock(id);
      out['textures/$bed.png'] = java[p]!;
      textures++;
      // animation
      final mc = java.json('$p.mcmeta');
      if (mc is Map && mc['animation'] is Map && (id.startsWith('block/') || id.startsWith('item/'))) {
        final a = mc['animation'] as Map;
        final fb = <String, Object?>{
          'flipbook_texture': 'textures/$bed',
          'atlas_tile': map.atlasKey[bed] ?? bed.split('/').last,
          'ticks_per_frame': (a['frametime'] as num?)?.toInt() ?? 1,
        };
        final frames = a['frames'];
        if (frames is List && frames.isNotEmpty) {
          final simple = <int>[];
          var uniformTime = true;
          for (final f in frames) {
            if (f is num) {
              simple.add(f.toInt());
            } else if (f is Map) {
              simple.add((f['index'] as num).toInt());
              if (f['time'] != null && f['time'] != a['frametime']) uniformTime = false;
            }
          }
          fb['frames'] = simple;
          if (!uniformTime) log.warn('${id.split('/').last} 的动画含每帧时长，基岩版不支持，已按统一时长转换');
        }
        if (a['interpolate'] == true) fb['blend_frames'] = true;
        flipbooks.add(fb);
      }
    }
    if (flipbooks.isNotEmpty) out.setJson('textures/flipbook_textures.json', flipbooks);
    log.count('转换贴图', textures);
    if (flipbooks.isNotEmpty) log.count('转换动画', flipbooks.length);

    // ---- celestial: Bedrock uses sun.png and an 4×2 moon_phases atlas
    final sun = java.image('${_jroot}textures/environment/celestial/sun.png') ?? java.image('${_jroot}textures/environment/sun.png');
    if (sun != null) out.setPng('textures/environment/sun.png', sun);
    final moon = _assembleMoon(java);
    if (moon != null) out.setPng('textures/environment/moon_phases.png', moon);
    final endSky = java.image('${_jroot}textures/environment/end_sky.png');
    if (endSky != null) out.setPng('textures/environment/end_sky.png', endSky);

    // ---- custom sky (OptiFine) → Bedrock overworld cubemap
    _skyToBedrock(java, out, log);

    // ---- languages
    var langs = 0;
    for (final p in java.paths) {
      final m = RegExp(r'^assets/minecraft/lang/([a-z_]+)\.(json|lang)$').firstMatch(p);
      if (m == null) continue;
      final code = _bedrockLang(m.group(1)!);
      final entries = m.group(2) == 'json' ? ((java.json(p) as Map?) ?? {}).map((k, v) => MapEntry('$k', '$v')) : parseProperties(java.text(p)!);
      // Bedrock keys differ for most strings; carry over the ones with the same key, keep the rest as-is
      out.setText('texts/$code.lang', [for (final e in entries.entries) '${e.key}=${e.value.replaceAll('\n', r'\n')}'].join('\n'));
      langs++;
    }
    if (langs > 0) {
      out.setJson('texts/languages.json', [for (final p in out.paths) if (p.startsWith('texts/') && p.endsWith('.lang')) p.substring(6, p.length - 5)]);
      log.count('转换语言文件', langs);
      log.warn('Java 与基岩版的翻译键大多不同，语言文件只对相同键生效');
    }

    // ---- sounds
    _soundsToBedrock(java, out, log);

    // ---- manifest / icon / texts
    final icon = java['pack.png'];
    if (icon != null) out['pack_icon.png'] = icon;
    out.setJson('manifest.json', {
      'format_version': 2,
      'header': {
        'name': name,
        'description': description,
        'uuid': _uuid(),
        'version': [1, 0, 0],
        'min_engine_version': [1, 21, 0],
      },
      'modules': [
        {'type': 'resources', 'uuid': _uuid(), 'version': [1, 0, 0]}
      ],
      'metadata': {'generated_with': {'ChthollyMinecraftLauncher': ['0.1.0']}},
    });

    // ---- report what could not be carried
    final models = java.paths.where((p) => p.contains('/models/') && p.endsWith('.json')).length;
    if (models > 0) log.warn('$models 个 Java 方块/物品模型无法转换（基岩版使用完全不同的几何体系统），对应方块会显示原版形状');
    if (java.paths.any((p) => p.contains('/shaders/'))) log.warn('Java 核心着色器无法转换到基岩版');
    final gui = java.paths.where((p) => p.startsWith('${_jroot}textures/gui/')).length;
    if (gui > 0) log.warn('$gui 个 GUI 贴图未转换（两版界面布局不同）');
    if (java.paths.any((p) => p.contains('/optifine/ctm/'))) log.warn('OptiFine 连接纹理（CTM）在基岩版没有对应功能');
    if (java.paths.any((p) => p.contains('/optifine/cit/'))) log.warn('OptiFine 自定义物品纹理（CIT）在基岩版没有对应功能');
    return out;
  }

  img.Image? _assembleMoon(PackFiles java) {
    final old = java.image('${_jroot}textures/environment/moon_phases.png');
    if (old != null) return old;
    const order = ['full_moon', 'waning_gibbous', 'third_quarter', 'waning_crescent', 'new_moon', 'waxing_crescent', 'first_quarter', 'waxing_gibbous'];
    final parts = [for (final o in order) java.image('${_jroot}textures/environment/celestial/moon/$o.png')];
    if (parts.every((p) => p == null)) return null;
    final s = parts.firstWhere((p) => p != null)!.width;
    final atlas = img.Image(width: s * 4, height: s * 2, numChannels: 4);
    for (var i = 0; i < 8; i++) {
      final p = parts[i];
      if (p != null) img.compositeImage(atlas, p, dstX: (i % 4) * s, dstY: (i ~/ 4) * s, blend: img.BlendMode.direct);
    }
    return atlas;
  }

  // Bedrock cubemap faces: cubemap_0..5 = south(+Z) / east(+X) / north(-Z) / west(-X) / up / down.
  // (Community-documented order; not yet verified in-game by CML.)
  static const _bedFaces = ['south', 'east', 'north', 'west', 'up', 'down'];
  // OptiFine / Nuit 3×2 layout: row0 bottom, top, south; row1 west, north, east
  static const _ofCells = {'down': (0, 0), 'up': (1, 0), 'south': (2, 0), 'west': (0, 1), 'north': (1, 1), 'east': (2, 1)};

  void _skyToBedrock(PackFiles java, PackFiles out, ConvertLog log) {
    String? src;
    for (final base in ['optifine', 'mcpatcher']) {
      final props = java.properties('$_jroot$base/sky/world0/sky1.properties');
      if (props == null) continue;
      final dir = '$_jroot$base/sky/world0';
      final s = props['source'];
      src = s == null ? '$dir/sky1.png' : (s.startsWith('./') ? '$dir/${s.substring(2)}' : '$_jroot$s');
      break;
    }
    if (src == null) {
      final nuit = java.paths.where((p) => p.startsWith('assets/nuit/sky/') && p.endsWith('.json')).toList()..sort();
      for (final p in nuit) {
        final j = java.json(p);
        if (j is Map && '${j['type']}'.endsWith('square-textured')) {
          final t = '${j['texture']}';
          src = 'assets/${t.contains(':') ? t.split(':').first : 'minecraft'}/${t.split(':').last}';
          break;
        }
      }
    }
    final sky = src == null ? null : java.image(src);
    if (sky == null) return;
    final fw = sky.width ~/ 3, fh = sky.height ~/ 2;
    for (var i = 0; i < 6; i++) {
      final (cx, cy) = _ofCells[_bedFaces[i]]!;
      var face = img.copyCrop(sky, x: cx * fw, y: cy * fh, width: fw, height: fh);
      if (_bedFaces[i] == 'up' || _bedFaces[i] == 'down') face = img.copyRotate(face, angle: 180);
      out.setPng('textures/environment/overworld_cubemap/cubemap_$i.png', face);
    }
    log.note('已把第一层自定义天空转换为基岩版天空盒（overworld_cubemap）；基岩版天空盒不支持时间渐变与多层叠加');
    log.count('转换天空层');
  }

  void _soundsToBedrock(PackFiles java, PackFiles out, ConvertLog log) {
    var n = 0;
    for (final p in java.paths) {
      if (!p.startsWith('${_jroot}sounds/') || !p.endsWith('.ogg')) continue;
      out['sounds/${p.substring('${_jroot}sounds/'.length)}'] = java[p]!;
      n++;
    }
    final sj = java.json('${_jroot}sounds.json');
    if (sj is Map) {
      final defs = <String, Object?>{};
      for (final e in sj.entries) {
        final v = e.value as Map;
        defs['${e.key}'] = {
          'category': _soundCategory('${v['category'] ?? 'neutral'}'),
          'sounds': [
            for (final s in v['sounds'] as List? ?? [])
              if (s is String)
                'sounds/$s'
              else if (s is Map && s['type'] != 'event')
                {
                  'name': 'sounds/${s['name']}',
                  if (s['volume'] != null) 'volume': s['volume'],
                  if (s['pitch'] != null) 'pitch': s['pitch'],
                  if (s['weight'] != null) 'weight': s['weight'],
                  if (s['stream'] == true) 'stream': true,
                }
          ],
        };
      }
      out.setJson('sounds/sound_definitions.json', {'format_version': '1.14.0', 'sound_definitions': defs});
    }
    if (n > 0) {
      log.count('转换音效', n);
      log.note('音效文件按相同路径放入基岩版包；Java 与基岩版大部分音效路径一致，会直接替换原版音效');
    }
  }

  static String _soundCategory(String c) => switch (c) {
        'master' || 'ambient' => 'ambient',
        'music' => 'music',
        'record' => 'record',
        'weather' => 'weather',
        'block' || 'blocks' => 'block',
        'hostile' => 'hostile',
        'neutral' => 'neutral',
        'player' || 'players' => 'player',
        'voice' => 'ui',
        _ => 'neutral',
      };

  static String _bedrockLang(String java) {
    final p = java.split('_');
    return p.length == 2 ? '${p[0]}_${p[1].toUpperCase()}' : java;
  }

  // ======================================================== Bedrock → Java

  PackFiles toJava(PackFiles bed, ConvertLog log, {required int packFormat, required String targetVersion}) {
    final out = PackFiles();
    final manifest = bed.json('manifest.json');
    final header = manifest is Map ? (manifest['header'] as Map? ?? {}) : {};
    var name = '${header['name'] ?? 'Converted pack'}';
    var desc = '${header['description'] ?? ''}';
    // pack names are often lang keys
    final enLang = bed.text('texts/zh_CN.lang') ?? bed.text('texts/en_US.lang');
    if (enLang != null) {
      final l = parseProperties(enLang);
      name = l[name] ?? name;
      desc = l[desc] ?? desc;
    }

    // ---- textures (png and tga)
    var textures = 0;
    for (final p in bed.paths.toList()..sort()) {
      if (!p.startsWith('textures/')) continue;
      final lower = p.toLowerCase();
      if (!lower.endsWith('.png') && !lower.endsWith('.tga')) continue;
      final rel = p.substring(9, p.length - 4);
      if (rel.startsWith('ui/') || rel.startsWith('gui/') || rel.startsWith('environment/overworld_cubemap/')) continue;
      final jid = map.toJava(rel);
      final target = '${_jroot}textures/$jid.png';
      if (out.has(target) && lower.endsWith('.tga')) continue;
      if (lower.endsWith('.tga')) {
        final im = bed.image(p);
        if (im == null) continue;
        out.setPng(target, im);
      } else {
        out[target] = bed[p]!;
      }
      textures++;
    }
    log.count('转换贴图', textures);

    // ---- flipbooks → .mcmeta (Bedrock flipbooks are vertical strips like Java)
    final fb = bed.json('textures/flipbook_textures.json');
    if (fb is List) {
      var n = 0;
      for (final f in fb) {
        if (f is! Map) continue;
        final path = '${f['flipbook_texture']}'.replaceFirst('textures/', '');
        final target = '${_jroot}textures/${map.toJava(path)}.png.mcmeta';
        final anim = <String, Object?>{'frametime': (f['ticks_per_frame'] as num?)?.toInt() ?? 1};
        if (f['frames'] is List) anim['frames'] = f['frames'];
        if (f['blend_frames'] == true) anim['interpolate'] = true;
        out.setJson(target, {'animation': anim});
        n++;
      }
      if (n > 0) log.count('转换动画', n);
    }

    // ---- celestial
    final moon = bed.image('textures/environment/moon_phases.png');
    final sun = bed['textures/environment/sun.png'];
    final modernCelestial = JavaPackTimeline.instance.versions.indexOf(targetVersion) >= JavaPackTimeline.instance.versions.indexOf('1.21.11');
    if (sun != null) {
      out.remove('${_jroot}textures/environment/sun.png');
      out[modernCelestial ? '${_jroot}textures/environment/celestial/sun.png' : '${_jroot}textures/environment/sun.png'] = sun;
    }
    if (moon != null) {
      out.remove('${_jroot}textures/environment/moon_phases.png');
      if (modernCelestial) {
        const order = ['full_moon', 'waning_gibbous', 'third_quarter', 'waning_crescent', 'new_moon', 'waxing_crescent', 'first_quarter', 'waxing_gibbous'];
        final s = moon.width ~/ 4;
        for (var i = 0; i < 8; i++) {
          out.setPng('${_jroot}textures/environment/celestial/moon/${order[i]}.png', img.copyCrop(moon, x: (i % 4) * s, y: (i ~/ 4) * s, width: s, height: s));
        }
      } else {
        out.setPng('${_jroot}textures/environment/moon_phases.png', moon);
      }
    }

    // ---- cubemap sky → OptiFine sky + Nuit
    final faces = [for (var i = 0; i < 6; i++) bed.image('textures/environment/overworld_cubemap/cubemap_$i.png')];
    if (faces.every((f) => f != null)) {
      final fw = faces[0]!.width, fh = faces[0]!.height;
      final sky = img.Image(width: fw * 3, height: fh * 2, numChannels: 4);
      for (var i = 0; i < 6; i++) {
        var f = faces[i]!;
        if (f.width != fw || f.height != fh) f = img.copyResize(f, width: fw, height: fh);
        if (_bedFaces[i] == 'up' || _bedFaces[i] == 'down') f = img.copyRotate(f, angle: 180);
        final (cx, cy) = _ofCells[_bedFaces[i]]!;
        img.compositeImage(sky, f, dstX: cx * fw, dstY: cy * fh, blend: img.BlendMode.direct);
      }
      out.setPng('${_jroot}optifine/sky/world0/sky1.png', sky);
      out.setText('${_jroot}optifine/sky/world0/sky1.properties', writeProperties({'source': './sky1.png', 'blend': 'replace', 'rotate': 'false'}));
      out.setPng('assets/nuit/sky/cml/world0_sky1.png', sky);
      out.setJson('assets/nuit/sky/cml/world0_sky1.json', {
        'schemaVersion': 1,
        'type': 'square-textured',
        'texture': 'nuit:sky/cml/world0_sky1.png',
        'properties': {'blend': 'replace', 'rotation': {'speed': 0, 'axis': {'0': [0, 0, 0]}}},
        'conditions': {'dimensions': {'entries': ['minecraft:overworld']}},
      });
      log.count('转换天空层');
      log.note('基岩版天空盒已转换为 OptiFine 自定义天空和 Nuit 天空（需要安装其中之一才会显示）');
    }

    // ---- languages
    for (final p in bed.paths) {
      final m = RegExp(r'^texts/([A-Za-z_]+)\.lang$').firstMatch(p);
      if (m == null) continue;
      final entries = parseProperties(bed.text(p)!);
      entries.updateAll((k, v) => v.replaceAll(RegExp(r'\s*#.*$'), ''));
      out.setJson('${_jroot}lang/${m.group(1)!.toLowerCase()}.json', entries);
    }

    // ---- sounds
    var sounds = 0;
    for (final p in bed.paths) {
      if (p.startsWith('sounds/') && (p.endsWith('.ogg') || p.endsWith('.fsb'))) {
        if (p.endsWith('.fsb')) continue;
        out['${_jroot}sounds/${p.substring(7)}'] = bed[p]!;
        sounds++;
      }
    }
    final sd = bed.json('sounds/sound_definitions.json');
    final defs = sd is Map ? (sd['sound_definitions'] as Map? ?? sd) : null;
    if (defs != null) {
      final js = <String, Object?>{};
      for (final e in defs.entries) {
        final v = e.value;
        if (v is! Map) continue;
        js['${e.key}'] = {
          'replace': true,
          'sounds': [
            for (final s in v['sounds'] as List? ?? [])
              if (s is String)
                s.replaceFirst('sounds/', '')
              else if (s is Map)
                {
                  'name': '${s['name']}'.replaceFirst('sounds/', ''),
                  if (s['volume'] != null) 'volume': s['volume'],
                  if (s['pitch'] != null) 'pitch': s['pitch'],
                  if (s['weight'] != null) 'weight': s['weight'],
                  if (s['stream'] == true) 'stream': true,
                }
          ],
        };
      }
      out.setJson('${_jroot}sounds.json', js);
    }
    if (sounds > 0) log.count('转换音效', sounds);

    // ---- pack.mcmeta / icon
    final icon = bed['pack_icon.png'];
    if (icon != null) out['pack.png'] = icon;
    out.setJson('pack.mcmeta', {
      'pack': {'pack_format': packFormat, 'description': desc.isEmpty ? name : desc}
    });

    // migrate from the newest layout down to the requested version
    final tl = JavaPackTimeline.instance;
    if (targetVersion != tl.versions.last) JavaPackMigrator().migrate(out, tl.versions.last, targetVersion, ConvertLog());

    final geo = bed.paths.where((p) => p.startsWith('models/') || p.startsWith('entity/') || p.startsWith('render_controllers/') || p.startsWith('animations/')).length;
    if (geo > 0) log.warn('$geo 个基岩版模型 / 实体 / 动画文件无法转换（Java 版不支持自定义实体几何体，除非安装相应模组）');
    if (bed.paths.any((p) => p.startsWith('ui/'))) log.warn('基岩版 UI（JSON UI）无法转换');
    if (bed.paths.any((p) => p.endsWith('.fsb'))) log.warn('部分音效为 FSB 格式，无法转换');
    if (bed.paths.any((p) => p.contains('texture_set.json') || p.endsWith('_mer.png') || p.endsWith('_normal.png'))) {
      log.warn('基岩版光追 / PBR 贴图（texture_set、MER、法线）已原样保留但 Java 原版不会使用');
    }
    return out;
  }

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${[for (var i = 0; i < 4; i++) h(i)].join()}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${[for (var i = 10; i < 16; i++) h(i)].join()}';
  }
}
