import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

import 'data/pack_rules_data.dart';
import 'pack_files.dart';

/// One step of vanilla asset changes between two adjacent versions (derived from client jars).
class PackStep {
  final String from, to;
  final Map<String, String> rename;
  final List<({String src, List<List<Object>> parts})> slices;
  final List<({String dst, int w, int h, List<List<Object>> parts})> merges;
  final List<String> removed, added;

  /// Vanilla `.mcmeta` for new GUI sprites (nine-slice scaling) keyed by path.
  final Map<String, String> meta;
  PackStep(this.from, this.to, this.rename, this.slices, this.merges, this.removed, this.added, this.meta);
}

/// Java edition version timeline with pack formats.
class JavaPackTimeline {
  JavaPackTimeline._();
  static final instance = JavaPackTimeline._().._load();

  late final List<String> versions;
  late final Map<String, int?> formats;
  late final List<PackStep> steps;

  void _load() {
    final j = jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(base64.decode(packRulesGz)))) as Map;
    versions = [for (final v in j['versions'] as List) '$v'];
    formats = {for (final e in (j['formats'] as Map).entries) '${e.key}': (e.value as num?)?.toInt()};
    steps = [
      for (final s in j['steps'] as List)
        PackStep(
          '${s['from']}',
          '${s['to']}',
          {for (final e in (s['rename'] as Map).entries) '${e.key}': '${e.value}'},
          [for (final x in s['slice'] as List) (src: '${x['src']}', parts: [for (final p in x['parts'] as List) (p as List).cast<Object>()])],
          [
            for (final x in s['merge'] as List)
              (dst: '${x['dst']}', w: (x['w'] as num).toInt(), h: (x['h'] as num).toInt(), parts: [for (final p in x['parts'] as List) (p as List).cast<Object>()])
          ],
          [for (final x in s['removed'] as List) '$x'],
          [for (final x in s['added'] as List) '$x'],
          {for (final e in ((s['meta'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        )
    ];
  }

  /// Pack format for a timeline version (1.8.9 → 1, 1.12.2 → 3, 1.13.2 → 4).
  int formatOf(String v) => formats[v] ?? const {'1.8.9': 1, '1.12.2': 3, '1.13.2': 4}[v] ?? 1;

  /// Closest timeline version for a pack_format.
  String versionForFormat(num f) {
    var best = versions.first;
    for (final v in versions) {
      if (formatOf(v) <= f) best = v;
    }
    return best;
  }
}

/// Converts a Java resource pack between Minecraft versions by replaying vanilla's own asset moves.
class JavaPackMigrator {
  final JavaPackTimeline t = JavaPackTimeline.instance;

  /// Migrates [pack] (in place) from [fromVersion] to [toVersion] (timeline ids).
  void migrate(PackFiles pack, String fromVersion, String toVersion, ConvertLog log) {
    final a = t.versions.indexOf(fromVersion), b = t.versions.indexOf(toVersion);
    if (a < 0 || b < 0 || a == b) return;
    final namespaces = _namespaces(pack);
    if (b > a) {
      for (var i = a; i < b; i++) {
        _forward(pack, t.steps[i], namespaces, log);
      }
    } else {
      for (var i = a - 1; i >= b; i--) {
        _backward(pack, t.steps[i], namespaces, log);
      }
    }
  }

  static Set<String> _namespaces(PackFiles p) => {
        for (final k in p.paths)
          if (k.startsWith('assets/') && k.split('/').length > 2) k.split('/')[1]
      };

  // ------------------------------------------------------------------ forward

  void _forward(PackFiles pack, PackStep s, Set<String> ns, ConvertLog log) {
    const root = 'assets/minecraft/';
    // 1) merges first (they read pieces that renames may move)
    for (final m in s.merges) {
      final have = [for (final part in m.parts) if (pack.has('$root${part[0]}')) part];
      if (have.isEmpty || pack.has('$root${m.dst}')) continue;
      final base = img.Image(width: m.w, height: m.h, numChannels: 4);
      var scale = 1;
      for (final part in have) {
        final im = pack.image('$root${part[0]}');
        if (im == null) continue;
        scale = (im.width / (part[3] as int)).round().clamp(1, 64);
        break;
      }
      final out = scale == 1 ? base : img.Image(width: m.w * scale, height: m.h * scale, numChannels: 4);
      for (final part in have) {
        final im = pack.image('$root${part[0]}');
        if (im == null) continue;
        img.compositeImage(out, im, dstX: (part[1] as int) * scale, dstY: (part[2] as int) * scale, blend: img.BlendMode.direct);
        pack.remove('$root${part[0]}');
      }
      pack.setPng('$root${m.dst}', out);
      log.count('合并贴图');
    }
    // 2) slices: cut new sprites out of old atlases (scaled for HD packs)
    for (final sl in s.slices) {
      final src = pack.image('$root${sl.src}');
      if (src == null) continue;
      final baseW = sl.parts.first[5] as int;
      final scale = src.width / baseW;
      for (final part in sl.parts) {
        final dst = '$root${part[0]}';
        if (pack.has(dst)) continue;
        final x = ((part[1] as int) * scale).round(), y = ((part[2] as int) * scale).round();
        final w = ((part[3] as int) * scale).round(), h = ((part[4] as int) * scale).round();
        if (x + w > src.width || y + h > src.height || w <= 0 || h <= 0) continue;
        pack.setPng(dst, img.copyCrop(src, x: x, y: y, width: w, height: h));
        final meta = s.meta['${part[0]}.mcmeta'];
        if (meta != null && !pack.has('$dst.mcmeta')) pack.setText('$dst.mcmeta', meta);
        log.count('切分贴图');
      }
      // keep the old atlas: other mods / older layers may still read it
    }
    // 3) renames (texture + mcmeta + models + blockstates…)
    final texRefs = <String, String>{};
    for (final e in s.rename.entries) {
      final from = '$root${e.key}', to = '$root${e.value}';
      if (!pack.has(from) || pack.has(to)) continue;
      pack.move(from, to);
      log.count('重命名文件');
      _collectRef(e.key, e.value, texRefs);
    }
    // texture refs for sliced sprites are new ids, nothing to rewrite
    if (texRefs.isNotEmpty) _rewriteRefs(pack, texRefs, ns, log);
  }

  // ------------------------------------------------------------------ backward

  void _backward(PackFiles pack, PackStep s, Set<String> ns, ConvertLog log) {
    const root = 'assets/minecraft/';
    final texRefs = <String, String>{};
    for (final e in s.rename.entries) {
      final from = '$root${e.value}', to = '$root${e.key}';
      if (!pack.has(from) || pack.has(to)) continue;
      pack.move(from, to);
      log.count('重命名文件');
      _collectRef(e.value, e.key, texRefs);
    }
    if (texRefs.isNotEmpty) _rewriteRefs(pack, texRefs, ns, log);
    // re-assemble old atlases from new sprites (paint onto the existing atlas if the pack has one)
    for (final sl in s.slices) {
      final pieces = [for (final part in sl.parts) if (pack.has('$root${part[0]}')) part];
      if (pieces.isEmpty) continue;
      final baseW = sl.parts.first[5] as int, baseH = sl.parts.first[6] as int;
      final first = pack.image('$root${pieces.first[0]}')!;
      final scale = (first.width / (pieces.first[3] as int)).round().clamp(1, 64);
      final atlas = pack.image('$root${sl.src}') ?? img.Image(width: baseW * scale, height: baseH * scale, numChannels: 4);
      final atlasScale = atlas.width ~/ baseW;
      for (final part in pieces) {
        var im = pack.image('$root${part[0]}');
        if (im == null) continue;
        final w = (part[3] as int) * atlasScale, h = (part[4] as int) * atlasScale;
        if (im.width != w || im.height != h) im = img.copyResize(im, width: w, height: h, interpolation: img.Interpolation.nearest);
        img.compositeImage(atlas, im, dstX: (part[1] as int) * atlasScale, dstY: (part[2] as int) * atlasScale, blend: img.BlendMode.direct);
      }
      pack.setPng('$root${sl.src}', atlas);
      log.count('拼合贴图');
    }
    // undo merges: cut the old small textures back out
    for (final m in s.merges) {
      final big = pack.image('$root${m.dst}');
      if (big == null) continue;
      final scale = big.width / m.w;
      for (final part in m.parts) {
        final dst = '$root${part[0]}';
        if (pack.has(dst)) continue;
        pack.setPng(dst, img.copyCrop(big, x: ((part[1] as int) * scale).round(), y: ((part[2] as int) * scale).round(), width: ((part[3] as int) * scale).round(), height: ((part[4] as int) * scale).round()));
      }
      log.count('切分贴图');
    }
  }

  // ------------------------------------------------------------------ references

  /// `textures/block/foo.png` → resource id `block/foo` (for model / atlas / item references).
  static void _collectRef(String from, String to, Map<String, String> refs) {
    String? id(String p) {
      if (p.startsWith('textures/') && p.endsWith('.png')) return p.substring(9, p.length - 4);
      if (p.startsWith('models/') && p.endsWith('.json')) return p.substring(7, p.length - 5);
      return null;
    }

    final a = id(from), b = id(to);
    if (a != null && b != null && a != b) refs[a] = b;
  }

  /// Rewrites texture / model ids inside every JSON of the pack (all namespaces).
  static void _rewriteRefs(PackFiles pack, Map<String, String> refs, Set<String> ns, ConvertLog log) {
    final re = RegExp(r'"((?:minecraft:)?)([a-z0-9_./-]+)"');
    for (final p in pack.paths.toList()) {
      if (!p.endsWith('.json') || !p.startsWith('assets/')) continue;
      final kind = p.split('/').length > 2 ? p.split('/')[2] : '';
      if (!const {'models', 'blockstates', 'items', 'atlases', 'equipment', 'particles'}.contains(kind)) continue;
      final t = pack.text(p)!;
      var changed = false;
      final out = t.replaceAllMapped(re, (m) {
        final r = refs[m.group(2)!];
        if (r == null) return m.group(0)!;
        changed = true;
        return '"${m.group(1)}$r"';
      });
      if (changed) {
        pack.setText(p, out);
        log.count('更新引用');
      }
    }
  }
}
