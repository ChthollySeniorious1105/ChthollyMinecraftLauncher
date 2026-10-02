import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'pack_files.dart';

/// Converts custom skies between OptiFine/MCPatcher (`optifine/sky/worldN/skyM.properties`)
/// and Nuit (`assets/nuit/sky/*.json`, schemaVersion 1).
///
/// OptiFine sky textures and Nuit `square-textured` textures share the same 3×2 cube layout
/// (bottom, top, south / west, north, east), so textures are reused as-is; only the
/// timing / blend / rotation / condition data is translated.
abstract class SkyConverter {
  static const _root = 'assets/minecraft/';

  // ------------------------------------------------------------------ helpers

  /// OptiFine time `hh:mm` → Minecraft tick (06:00 = 0, 12:00 = 6000, 00:00 = 18000).
  static int timeToTick(String hhmm) {
    final p = hhmm.trim().split(':');
    final h = int.tryParse(p[0]) ?? 0, m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    return (((h - 6) * 1000 + (m * 1000 / 60).round()) % 24000 + 24000) % 24000;
  }

  static String tickToTime(int tick) {
    final minutes = ((tick % 24000) * 60 / 1000).round() + 6 * 60;
    final h = (minutes ~/ 60) % 24, m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// OptiFine texture reference → pack path.
  static String _resolve(String ref, String propsDir) {
    ref = ref.trim();
    if (ref.startsWith('./')) return '$propsDir/${ref.substring(2)}';
    if (ref.startsWith('~/')) return '${_root}optifine/${ref.substring(2)}';
    final ns = ref.indexOf(':');
    if (ns > 0) return 'assets/${ref.substring(0, ns)}/${ref.substring(ns + 1)}';
    return '$_root$ref';
  }

  static const _worldDims = {'world0': 'minecraft:overworld', 'world1': 'minecraft:the_end', 'world-1': 'minecraft:the_nether'};
  static const _dimWorlds = {'minecraft:overworld': 'world0', 'minecraft:the_end': 'world1', 'minecraft:the_nether': 'world-1'};

  static const _blendO2N = {
    'add': 'add',
    'subtract': 'subtract',
    'multiply': 'multiply',
    'dodge': 'dodge',
    'burn': 'burn',
    'screen': 'screen',
    'replace': 'replace',
    'overlay': 'screen',
    'alpha': 'normal',
  };
  static const _blendN2O = {
    'add': 'add',
    'subtract': 'subtract',
    'multiply': 'multiply',
    'dodge': 'dodge',
    'burn': 'burn',
    'screen': 'screen',
    'replace': 'replace',
    'normal': 'alpha',
    'alpha': 'alpha',
    'decorations': 'add',
    'disable': 'replace',
  };

  /// Unit axis vector → Euler degrees that rotate the default south axis (0,0,1) onto it.
  static List<double> _axisToEuler(List<double> v) {
    final len = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (len == 0) return [0, 0, 0];
    final x = v[0] / len, y = v[1] / len, z = v[2] / len;
    final pitch = -math.asin(y.clamp(-1.0, 1.0)) * 180 / math.pi;
    final yaw = math.atan2(x, z) * 180 / math.pi;
    double r(double d) => (d * 1000).roundToDouble() / 1000;
    return [r(pitch), r(yaw), 0];
  }

  static List<double> _eulerToAxis(List<num> e) {
    final pitch = -e[0] * math.pi / 180, yaw = e[1] * math.pi / 180;
    double r(double d) => (d * 1000).roundToDouble() / 1000;
    return [r(math.cos(pitch) * math.sin(yaw)), r(math.sin(pitch)), r(math.cos(pitch) * math.cos(yaw))];
  }

  // ------------------------------------------------------------------ OptiFine → Nuit

  /// Converts every OptiFine / MCPatcher sky layer into Nuit JSON. Original files are kept,
  /// so the pack works with both OptiFine and Nuit.
  static void optifineToNuit(PackFiles pack, ConvertLog log) {
    final re = RegExp(r'^assets/minecraft/(optifine|mcpatcher)/sky/(world-?\d+)/(sky\d+)\.properties$');
    final layers = <(String, String, String, Map<String, String>)>[];
    for (final p in pack.paths) {
      final m = re.firstMatch(p);
      if (m == null) continue;
      layers.add((p, m.group(2)!, m.group(3)!, pack.properties(p) ?? {}));
    }
    layers.sort((a, b) {
      final w = a.$2.compareTo(b.$2);
      if (w != 0) return w;
      return int.parse(a.$3.substring(3)).compareTo(int.parse(b.$3.substring(3)));
    });
    var n = 0;
    for (final (path, world, name, props) in layers) {
      final dir = path.substring(0, path.lastIndexOf('/'));
      final srcPath = props['source'] != null ? _resolve(props['source']!, dir) : '$dir/$name.png';
      if (!pack.has(srcPath)) {
        log.warn('天空层 $world/$name 缺少贴图 ${srcPath.replaceFirst(_root, '')}，已跳过');
        continue;
      }
      // copy the texture into the nuit namespace so the JSON can reference it with a plain id
      final texId = 'nuit:sky/cml/$world/$name.png';
      pack['assets/nuit/sky/cml/$world/$name.png'] = pack[srcPath]!;

      final properties = <String, Object?>{'layer': int.parse(name.substring(3))};
      final blend = (props['blend'] ?? 'add').toLowerCase();
      properties['blend'] = _blendO2N[blend] ?? 'add';

      final sfi = props['startFadeIn'], efi = props['endFadeIn'], efo = props['endFadeOut'];
      if (sfi != null && efi != null && efo != null) {
        final a = timeToTick(sfi), b = timeToTick(efi), d = timeToTick(efo);
        // startFadeOut is implied: same distance before endFadeOut as the fade-in length
        final c = (d - ((b - a) % 24000 + 24000) % 24000 + 24000) % 24000;
        final kf = <String, double>{};
        void key(int t, double v) => kf['${t % 24000}'] = v;
        key(a, 0);
        key(b, 1);
        key(c, 1);
        key(d, 0);
        properties['fade'] = {'duration': 24000, 'keyFrames': Map.fromEntries(kf.entries.toList()..sort((x, y) => int.parse(x.key).compareTo(int.parse(y.key))))};
      }

      final rotate = (props['rotate'] ?? 'true').toLowerCase() != 'false';
      final speed = double.tryParse(props['speed'] ?? '1') ?? 1;
      final axis = (props['axis'] ?? '0 0 1').trim().split(RegExp(r'\s+')).map((e) => double.tryParse(e) ?? 0).toList();
      // OptiFine rotates with the sun's celestial angle. Nuit's skyboxRotation:false follows the sun
      // exactly, which matches speed 1; other speeds need Nuit's uniform clock rotation (phase may differ).
      properties['rotation'] = {
        'skyboxRotation': rotate && speed != 1,
        'speed': rotate ? speed : 0,
        'duration': 24000,
        'mapping': {'0': [0.0, 0.0, 0.0]},
        'axis': {'0': _axisToEuler(axis.length == 3 ? axis : [0, 0, 1])},
      };
      if (rotate && speed != 1) log.warn('天空层 $world/$name 使用了 speed=$speed，转换到 Nuit 后起始角度可能与 OptiFine 略有不同');
      final transition = double.tryParse(props['transition'] ?? '');
      if (transition != null) {
        properties['transitionInDuration'] = math.max(1, (transition * 20).round());
        properties['transitionOutDuration'] = math.max(1, (transition * 20).round());
      }

      final conditions = <String, Object?>{};
      final dim = _worldDims[world];
      if (dim != null) conditions['dimensions'] = {'entries': [dim]};
      final weather = props['weather'];
      if (weather != null) {
        final list = <String>{};
        for (final w in weather.split(RegExp(r'\s+'))) {
          switch (w) {
            case 'clear':
              list.add('clear');
            case 'rain':
              list.addAll(['rain', 'rain_biome', 'snow']);
            case 'thunder':
              list.addAll(['thunder', 'rain_thunder', 'snow_thunder']);
          }
        }
        if (list.isNotEmpty) conditions['weather'] = {'entries': list.toList()};
      }
      final biomes = props['biomes'];
      if (biomes != null && biomes.trim().isNotEmpty) {
        final ex = biomes.trim().startsWith('!');
        conditions['biomes'] = {
          'excludes': ex,
          'entries': [for (final b in biomes.replaceFirst('!', '').trim().split(RegExp(r'\s+'))) b.contains(':') ? b : 'minecraft:${b.toLowerCase()}'],
        };
      }
      final heights = props['heights'];
      if (heights != null) {
        final ranges = <Map<String, double>>[];
        for (final r in heights.trim().split(RegExp(r'\s+'))) {
          final m = RegExp(r'^\(?(-?\d+)\)?(?:-\(?(-?\d+)\)?)?$').firstMatch(r);
          if (m == null) continue;
          final lo = double.parse(m.group(1)!);
          ranges.add({'min': lo, 'max': m.group(2) == null ? lo : double.parse(m.group(2)!)});
        }
        if (ranges.isNotEmpty) conditions['yRanges'] = {'entries': ranges};
      }
      if (props['days'] != null) log.warn('天空层 $world/$name 使用了 days（按天显示），Nuit 不支持，已忽略');

      pack.setJson('assets/nuit/sky/cml/${world}_$name.json', {
        'schemaVersion': 1,
        'type': 'square-textured',
        'texture': texId,
        'properties': properties,
        if (conditions.isNotEmpty) 'conditions': conditions,
      });
      n++;
    }
    // sun / moon overrides
    for (final world in _worldDims.keys) {
      for (final which in ['sun', 'moon_phases']) {
        for (final base in ['optifine', 'mcpatcher']) {
          final p = '$_root$base/sky/$world/$which.properties';
          if (!pack.has(p)) continue;
          final props = pack.properties(p)!;
          final dir = p.substring(0, p.lastIndexOf('/'));
          final src = props['source'] != null ? _resolve(props['source']!, dir) : '$dir/$which.png';
          if (!pack.has(src)) continue;
          pack['assets/nuit/sky/cml/$world/$which.png'] = pack[src]!;
          pack.setJson('assets/nuit/sky/cml/${world}_$which.json', {
            'schemaVersion': 1,
            'type': 'decorations',
            if (which == 'sun') 'sun': 'nuit:sky/cml/$world/$which.png' else 'moon': 'nuit:sky/cml/$world/$which.png',
            if (which == 'sun') 'showSun': true else 'showMoon': true,
            'properties': {'blend': _blendO2N[(props['blend'] ?? 'add').toLowerCase()] ?? 'decorations'},
            if (_worldDims[world] != null) 'conditions': {'dimensions': {'entries': [_worldDims[world]]}},
          });
          n++;
        }
      }
    }
    if (n > 0) {
      log.count('转换天空层', n);
      log.note('已把 OptiFine 自定义天空转换为 Nuit 格式（assets/nuit/sky），原 OptiFine 文件保留，两种模组都能使用');
    }
  }

  // ------------------------------------------------------------------ legacy FabricSkyBoxes → Nuit

  /// FabricSkyBoxes (schemaVersion 2, `assets/fabricskyboxes/sky/*.json`) → Nuit schemaVersion 1.
  /// Six separate face textures are stitched into Nuit's 3×2 layout.
  static void fabricSkyboxesToNuit(PackFiles pack, ConvertLog log) {
    final files = [for (final p in pack.paths) if (p.startsWith('assets/fabricskyboxes/sky/') && p.endsWith('.json')) p]..sort();
    var n = 0;
    for (final p in files) {
      final j = pack.json(p);
      if (j is! Map) continue;
      final type = '${j['type'] ?? ''}'.replaceFirst('fabricskyboxes:', '');
      final props = (j['properties'] as Map?) ?? const {};
      final name = p.split('/').last.replaceAll('.json', '');
      final out = <String, Object?>{'schemaVersion': 1};
      final nprops = <String, Object?>{};
      if (props['priority'] != null) nprops['layer'] = props['priority'];
      final fade = props['fade'] as Map?;
      if (fade != null && fade['alwaysOn'] != true && fade['startFadeIn'] != null) {
        final kf = <String, double>{};
        void k(Object? t, double v) {
          if (t is num) kf['${t.toInt() % 24000}'] = v;
        }

        k(fade['startFadeIn'], 0);
        k(fade['endFadeIn'], 1);
        k(fade['startFadeOut'], 1);
        k(fade['endFadeOut'], 0);
        nprops['fade'] = {'duration': 24000, 'keyFrames': Map.fromEntries(kf.entries.toList()..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key))))};
      }
      final rot = props['rotation'] as Map?;
      final shouldRotate = props['shouldRotate'] == true;
      nprops['rotation'] = {
        'skyboxRotation': false,
        'speed': shouldRotate ? ((rot?['speed'] as num?) ?? 1) : 0,
        if (rot?['static'] is List) 'mapping': {'0': rot!['static']},
        'axis': {'0': (rot?['axis'] is List) ? rot!['axis'] : [0, 0, 0]},
      };
      final blend = j['blend'] ?? props['blend'];
      final bt = blend is Map ? '${blend['type'] ?? ''}' : '${blend ?? ''}';
      nprops['blend'] = switch (bt) { 'add' => 'add', 'subtract' => 'subtract', 'multiply' => 'multiply', 'screen' => 'screen', 'replace' => 'replace', 'alpha' => 'normal', 'false' || 'disable' => 'disable', _ => 'normal' };
      final cond = (j['conditions'] as Map?) ?? const {};
      final ncond = <String, Object?>{};
      for (final key in ['worlds', 'biomes', 'weather', 'dimensions']) {
        final v = cond[key];
        if (v is List && v.isNotEmpty) ncond[key == 'worlds' ? 'dimensions' : key] = {'entries': v};
      }
      final heights = cond['heights'];
      if (heights is List && heights.isNotEmpty) ncond['yRanges'] = {'entries': heights};

      if (type == 'square-textured' && j['textures'] is Map) {
        final t = j['textures'] as Map;
        final faces = <String, String>{};
        for (final f in ['bottom', 'top', 'south', 'west', 'north', 'east']) {
          final id = '${t[f] ?? ''}';
          final ns = id.contains(':') ? id.split(':').first : 'minecraft';
          faces[f] = 'assets/$ns/${id.split(':').last}';
        }
        final imgs = {for (final e in faces.entries) e.key: pack.image(e.value)};
        if (imgs.values.any((i) => i == null)) {
          log.warn('FabricSkyBoxes 天空 $name 缺少面贴图，已跳过');
          continue;
        }
        final s = imgs.values.map((i) => i!.width).reduce(math.min);
        final sheet = SkyImages.stitch3x2(imgs.map((k, v) => MapEntry(k, v!)), s);
        pack.setPng('assets/nuit/sky/cml/fsb_$name.png', sheet);
        out['type'] = 'square-textured';
        out['texture'] = 'nuit:sky/cml/fsb_$name.png';
      } else if (type == 'square-textured' || type == 'textured' || type == 'single-sprite-square-textured') {
        final tex = '${j['texture'] ?? (j['textures'] as Map?)?['texture'] ?? ''}';
        if (tex.isEmpty) continue;
        out['type'] = 'square-textured';
        out['texture'] = tex;
      } else if (type == 'monocolor') {
        out['type'] = 'monocolor';
        out['color'] = j['color'];
      } else if (type == 'decorations' || j['decorations'] is Map) {
        final d = (j['decorations'] as Map?) ?? const {};
        out['type'] = 'decorations';
        for (final k in ['sun', 'moon', 'showSun', 'showMoon', 'showStars']) {
          if (d[k] != null) out[k] = d[k];
        }
      } else {
        log.warn('FabricSkyBoxes 天空 $name 的类型 $type 暂不支持');
        continue;
      }
      out['properties'] = nprops;
      if (ncond.isNotEmpty) out['conditions'] = ncond;
      pack.setJson('assets/nuit/sky/cml/fsb_$name.json', out);
      n++;
    }
    if (n > 0) {
      log.count('转换天空层', n);
      log.note('已把旧版 FabricSkyBoxes 天空升级为 Nuit 格式，原文件保留');
    }
  }

  // ------------------------------------------------------------------ Nuit → OptiFine

  static void nuitToOptifine(PackFiles pack, ConvertLog log) {
    final skies = [for (final p in pack.paths) if (p.startsWith('assets/nuit/sky/') && p.endsWith('.json')) p]..sort();
    final counters = <String, int>{};
    var n = 0;
    for (final p in skies) {
      final j = pack.json(p);
      if (j is! Map) continue;
      final type = '${j['type'] ?? ''}'.replaceFirst('nuit:', '');
      final props0 = (j['properties'] as Map?) ?? const {};
      final cond = (j['conditions'] as Map?) ?? const {};
      final dims = [for (final d in ((cond['dimensions'] ?? cond['worlds']) as Map?)?['entries'] as List? ?? const ['minecraft:overworld']) '$d'];
      final world = _dimWorlds[dims.isEmpty ? 'minecraft:overworld' : dims.first] ?? 'world0';
      if (type != 'square-textured' && type != 'textured') {
        if (type == 'monocolor' || type == 'multi-textured' || type == 'decorations') {
          log.warn('Nuit 天空 ${p.split('/').last}（$type）在 OptiFine 中没有对应类型，已跳过');
        }
        continue;
      }
      final tex = '${j['texture'] ?? ''}';
      final ns = tex.contains(':') ? tex.split(':').first : 'minecraft';
      final texPath = 'assets/$ns/${tex.contains(':') ? tex.split(':').last : tex}';
      if (!pack.has(texPath)) {
        log.warn('Nuit 天空 ${p.split('/').last} 的贴图 $tex 不存在，已跳过');
        continue;
      }
      final idx = counters[world] = (counters[world] ?? 0) + 1;
      final dir = '${_root}optifine/sky/$world';
      pack['$dir/sky$idx.png'] = pack[texPath]!;
      final out = <String, String>{'source': './sky$idx.png'};
      out['blend'] = _blendN2O['${props0['blend'] ?? 'normal'}'] ?? 'alpha';
      final fade = props0['fade'] as Map?;
      final kf = (fade?['keyFrames'] as Map?)?.map((k, v) => MapEntry(int.parse('$k'), (v as num).toDouble()));
      if (kf != null && kf.length >= 2) {
        // OptiFine supports one trapezoid: take the first rise to 1 and the first fall to 0 after it
        final ticks = kf.keys.toList()..sort();
        int? sfi, efi, efo;
        for (var i = 0; i < ticks.length; i++) {
          final t = ticks[i], v = kf[t]!, prev = kf[ticks[(i - 1 + ticks.length) % ticks.length]]!;
          if (v >= 1 && prev < 1 && efi == null) {
            efi = t;
            sfi = ticks[(i - 1 + ticks.length) % ticks.length];
          }
          if (v <= 0 && prev > 0 && efi != null && efo == null) efo = t;
        }
        if (sfi != null && efi != null && efo != null) {
          out['startFadeIn'] = tickToTime(sfi);
          out['endFadeIn'] = tickToTime(efi);
          out['endFadeOut'] = tickToTime(efo);
        }
        if (ticks.length > 4) log.warn('Nuit 天空 ${p.split('/').last} 的渐变关键帧多于 4 个，OptiFine 只能保留一次淡入淡出');
      }
      final rot = props0['rotation'] as Map?;
      if (rot != null) {
        final speed = (rot['speed'] as num?)?.toDouble() ?? 1;
        out['rotate'] = speed == 0 ? 'false' : 'true';
        if (speed != 0 && speed != 1) out['speed'] = '$speed';
        final axis = (rot['axis'] as Map?)?.values.firstOrNull;
        if (axis is List && axis.length == 3) {
          final v = _eulerToAxis(axis.cast<num>());
          out['axis'] = v.join(' ');
        }
      }
      final weather = (cond['weather'] as Map?)?['entries'] as List?;
      if (weather != null) {
        final w = <String>{
          for (final e in weather)
            switch ('$e') { 'clear' => 'clear', 'rain' || 'rain_biome' || 'snow' => 'rain', _ => 'thunder' }
        };
        out['weather'] = w.join(' ');
      }
      final biomes = cond['biomes'] as Map?;
      if (biomes != null && (biomes['entries'] as List?)?.isNotEmpty == true) {
        out['biomes'] = '${biomes['excludes'] == true ? '!' : ''}${(biomes['entries'] as List).where((b) => b != 'nuit:default').join(' ')}';
      }
      final y = (cond['yRanges'] as Map?)?['entries'] as List?;
      if (y != null && y.isNotEmpty) {
        String f(num v) => v < 0 ? '(${v.round()})' : '${v.round()}';
        out['heights'] = [for (final r in y) '${f(r['min'] as num)}-${f(r['max'] as num)}'].join(' ');
      }
      final tIn = props0['transitionInDuration'] as num?;
      if (tIn != null) out['transition'] = (tIn / 20).toStringAsFixed(1);
      pack.setText('$dir/sky$idx.properties', writeProperties(out));
      n++;
    }
    if (n > 0) {
      log.count('转换天空层', n);
      log.note('已把 Nuit 天空转换为 OptiFine 自定义天空（optifine/sky），原 Nuit 文件保留');
    }
  }
}

/// Cube-map image helpers shared by the sky converters.
abstract class SkyImages {
  /// OptiFine / Nuit 3×2 sheet: row 0 = bottom, top, south; row 1 = west, north, east.
  static const cells = {'bottom': (0, 0), 'top': (1, 0), 'south': (2, 0), 'west': (0, 1), 'north': (1, 1), 'east': (2, 1)};

  static img.Image stitch3x2(Map<String, img.Image> faces, int size) {
    final out = img.Image(width: size * 3, height: size * 2, numChannels: 4);
    for (final e in faces.entries) {
      final cell = cells[e.key];
      if (cell == null) continue;
      var f = e.value;
      if (f.width != size || f.height != size) f = img.copyResize(f, width: size, height: size, interpolation: img.Interpolation.average);
      img.compositeImage(out, f, dstX: cell.$1 * size, dstY: cell.$2 * size, blend: img.BlendMode.direct);
    }
    return out;
  }
}
