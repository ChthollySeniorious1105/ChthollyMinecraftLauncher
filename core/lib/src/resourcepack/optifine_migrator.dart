import 'java_migrator.dart';
import 'pack_files.dart';

/// OptiFine / MCPatcher feature migration across Minecraft versions:
///   * `mcpatcher/` → `optifine/` (1.13+ only reads `optifine/`) and back
///   * CTM `matchTiles` / `matchBlocks`, CIT `items` / `texture` / `model`, random entity paths,
///     emissive and custom-animation `to=`/`from=` references follow vanilla's texture renames
///   * CTM tile paths `textures/blocks/…` ⇄ `textures/block/…`
class OptiFineMigrator {
  static const _root = 'assets/minecraft/';

  /// Item / block id renames of 1.13's flattening that matter for CTM/CIT (subset; numeric ids are dropped).
  static const _flatIds = {
    'grass': 'grass_block', 'tallgrass': 'short_grass', 'deadbush': 'dead_bush', 'web': 'cobweb', 'planks': 'oak_planks',
    'stonebrick': 'stone_bricks', 'brick_block': 'bricks', 'nether_brick': 'nether_bricks', 'end_bricks': 'end_stone_bricks',
    'hardened_clay': 'terracotta', 'stained_hardened_clay': 'white_terracotta', 'wool': 'white_wool', 'stained_glass': 'white_stained_glass',
    'stained_glass_pane': 'white_stained_glass_pane', 'carpet': 'white_carpet', 'concrete': 'white_concrete', 'concrete_powder': 'white_concrete_powder',
    'log': 'oak_log', 'log2': 'acacia_log', 'leaves': 'oak_leaves', 'leaves2': 'acacia_leaves', 'sapling': 'oak_sapling', 'red_flower': 'poppy',
    'yellow_flower': 'dandelion', 'double_plant': 'sunflower', 'snow_layer': 'snow', 'snow': 'snow_block', 'quartz_ore': 'nether_quartz_ore',
    'lit_pumpkin': 'jack_o_lantern', 'pumpkin': 'carved_pumpkin', 'melon_block': 'melon', 'mob_spawner': 'spawner', 'noteblock': 'note_block',
    'trapdoor': 'oak_trapdoor', 'fence': 'oak_fence', 'fence_gate': 'oak_fence_gate', 'wooden_door': 'oak_door', 'wooden_slab': 'oak_slab',
    'stone_slab': 'smooth_stone_slab', 'monster_egg': 'infested_stone', 'golden_rail': 'powered_rail', 'waterlily': 'lily_pad',
    'reeds': 'sugar_cane', 'slime': 'slime_block', 'magma': 'magma_block', 'red_nether_brick': 'red_nether_bricks',
    'silver_shulker_box': 'light_gray_shulker_box', 'silver_glazed_terracotta': 'light_gray_glazed_terracotta', 'portal': 'nether_portal',
    'fish': 'cod', 'cooked_fish': 'cooked_cod', 'speckled_melon': 'glistering_melon_slice', 'melon': 'melon_slice', 'reeds_item': 'sugar_cane',
    'wooden_sword': 'wooden_sword', 'golden_apple': 'golden_apple', 'fireworks': 'firework_rocket', 'firework_charge': 'firework_star',
    'boat': 'oak_boat', 'netherbrick': 'nether_brick', 'chorus_fruit_popped': 'popped_chorus_fruit', 'record_13': 'music_disc_13',
    'record_cat': 'music_disc_cat', 'record_blocks': 'music_disc_blocks', 'record_chirp': 'music_disc_chirp', 'record_far': 'music_disc_far',
    'record_mall': 'music_disc_mall', 'record_mellohi': 'music_disc_mellohi', 'record_stal': 'music_disc_stal', 'record_strad': 'music_disc_strad',
    'record_ward': 'music_disc_ward', 'record_11': 'music_disc_11', 'record_wait': 'music_disc_wait', 'skull': 'skeleton_skull', 'sign': 'oak_sign',
  };

  /// Applies OptiFine-related fixes for a move between two timeline versions.
  static void migrate(PackFiles pack, String from, String to, ConvertLog log) {
    final tl = JavaPackTimeline.instance;
    final a = tl.versions.indexOf(from), b = tl.versions.indexOf(to);
    final i113 = tl.versions.indexOf('1.13.2');
    final crossesForward = a < i113 && b >= i113;
    final crossesBackward = a >= i113 && b < i113;

    // folder rename
    if (b >= i113) {
      var moved = 0;
      for (final p in pack.paths.toList()) {
        if (p.startsWith('${_root}mcpatcher/')) {
          pack.move(p, '${_root}optifine/${p.substring('${_root}mcpatcher/'.length)}');
          moved++;
        }
      }
      if (moved > 0) log.note('mcpatcher/ 已更名为 optifine/（$moved 个文件）');
    } else if (crossesBackward) {
      // 1.12 OptiFine reads both; keep optifine/
    }

    // texture-id renames accumulated over the whole range (for property references)
    final texIds = _texIdRenames(tl, a, b);
    if (texIds.isEmpty && !crossesForward && !crossesBackward) return;
    var changed = 0;
    for (final p in pack.paths.toList()) {
      if (!p.startsWith('${_root}optifine/') && !p.startsWith('${_root}mcpatcher/')) continue;
      if (!p.endsWith('.properties')) continue;
      final props = pack.properties(p);
      if (props == null) continue;
      var dirty = false;
      for (final k in props.keys.toList()) {
        final v = props[k]!;
        String? nv;
        if (k == 'matchTiles' || k == 'connectTiles') {
          nv = v.split(RegExp(r'\s+')).map((t) => _renameTile(t, texIds)).join(' ');
        } else if (k == 'matchBlocks' || k == 'connectBlocks' || k == 'items' || k == 'matchItems') {
          if (crossesForward) {
            nv = v.split(RegExp(r'\s+')).map((t) => _renameId(t, _flatIds)).join(' ');
          } else if (crossesBackward) {
            final inv = {for (final e in _flatIds.entries) e.value: e.key};
            nv = v.split(RegExp(r'\s+')).map((t) => _renameId(t, inv)).join(' ');
          }
        } else if (k == 'texture' || k.startsWith('texture.') || k == 'from' || k == 'to' || k == 'source' || k == 'model' || k.startsWith('model.')) {
          nv = _renamePathRef(v, texIds);
        } else if (k == 'tiles') {
          nv = v.split(RegExp(r'\s+')).map((t) => t.contains('/') ? _renamePathRef(t, texIds) : t).join(' ');
        }
        if (nv != null && nv != v) {
          props[k] = nv;
          dirty = true;
        }
      }
      // filename-implied matchTiles (ctm/xxx/<tile>.properties)
      if (dirty) {
        pack.setText(p, writeProperties(props));
        changed++;
      }
    }
    // random entities: optifine/random/entity/<path> mirrors textures/entity/<path>
    for (final p in pack.paths.toList()) {
      final m = RegExp(r'^assets/minecraft/optifine/(random|mob)/(.+?)(\d*)\.(png|properties)$').firstMatch(p);
      if (m == null) continue;
      final rel = m.group(2)!;
      final renamed = texIds[rel] ?? texIds['entity/$rel'];
      if (renamed == null) continue;
      pack.move(p, '${_root}optifine/random/$renamed${m.group(3)}.${m.group(4)}');
      changed++;
    }
    if (changed > 0) log.count('更新 OptiFine 配置', changed);
  }

  static Map<String, String> _texIdRenames(JavaPackTimeline tl, int a, int b) {
    final out = <String, String>{};
    String? id(String p) => p.startsWith('textures/') && p.endsWith('.png') ? p.substring(9, p.length - 4) : null;
    if (b > a) {
      for (var i = a; i < b; i++) {
        for (final e in tl.steps[i].rename.entries) {
          final x = id(e.key), y = id(e.value);
          if (x == null || y == null) continue;
          // chain: if something already maps to x, extend it
          for (final k in out.keys.toList()) {
            if (out[k] == x) out[k] = y;
          }
          out.putIfAbsent(x, () => y);
        }
      }
    } else {
      for (var i = a - 1; i >= b; i--) {
        for (final e in tl.steps[i].rename.entries) {
          final x = id(e.value), y = id(e.key);
          if (x == null || y == null) continue;
          for (final k in out.keys.toList()) {
            if (out[k] == x) out[k] = y;
          }
          out.putIfAbsent(x, () => y);
        }
      }
    }
    return out;
  }

  static String _renameTile(String t, Map<String, String> texIds) {
    // short tile name "dirt" means textures/block(s)/dirt
    if (!t.contains('/') && !t.contains(':')) {
      for (final folder in ['block', 'blocks']) {
        final r = texIds['$folder/$t'];
        if (r != null) return r.split('/').last;
      }
      return t;
    }
    return _renamePathRef(t, texIds);
  }

  static String _renamePathRef(String v, Map<String, String> texIds) {
    final m = RegExp(r'^(minecraft:)?(textures/)?(.+?)(\.png)?$').firstMatch(v.trim());
    if (m == null) return v;
    final r = texIds[m.group(3)!];
    if (r == null) return v;
    return '${m.group(1) ?? ''}${m.group(2) ?? ''}$r${m.group(4) ?? ''}';
  }

  static const _colors = ['white', 'orange', 'magenta', 'light_blue', 'yellow', 'lime', 'pink', 'gray', 'light_gray', 'cyan', 'purple', 'blue', 'brown', 'green', 'red', 'black'];

  /// 1.12 block name → 1.13 suffix for colour-variant blocks.
  static const _coloredBlocks = {
    'wool': 'wool', 'stained_glass': 'stained_glass', 'stained_glass_pane': 'stained_glass_pane', 'carpet': 'carpet',
    'concrete': 'concrete', 'concrete_powder': 'concrete_powder', 'stained_hardened_clay': 'terracotta', 'bed': 'bed',
  };

  /// `stained_glass:color=black` ⇄ `black_stained_glass` (direction picked from [map]).
  static String? _colorFlatten(String token, Map<String, String> map) {
    final forward = map.containsKey('stained_glass');
    var t = token;
    var ns = '';
    if (t.startsWith('minecraft:')) {
      ns = 'minecraft:';
      t = t.substring(10);
    }
    if (forward) {
      final m = RegExp(r'^([a-z_]+):color=([a-z_]+)(.*)$').firstMatch(t);
      if (m == null || !_coloredBlocks.containsKey(m.group(1))) return null;
      final c = m.group(2) == 'silver' ? 'light_gray' : m.group(2)!;
      if (!_colors.contains(c)) return null;
      return '$ns${c}_${_coloredBlocks[m.group(1)]}${m.group(3)}';
    }
    for (final e in _coloredBlocks.entries) {
      for (final c in _colors) {
        final name = '${c}_${e.value}';
        if (t == name || t.startsWith('$name:')) {
          final legacyColor = c == 'light_gray' ? 'silver' : c;
          return '$ns${e.key}:color=$legacyColor${t.substring(name.length)}';
        }
      }
    }
    return null;
  }

  static String _renameId(String token, Map<String, String> map) {
    final colored = _colorFlatten(token, map);
    if (colored != null) return colored;
    // minecraft:stone:variant=granite / stone:1 / 35:14 (numeric ids are left alone)
    final parts = token.split(':');
    var i = 0;
    var ns = '';
    if (parts.length > 1 && !parts[0].contains('=') && parts[0] == 'minecraft') {
      ns = 'minecraft:';
      i = 1;
    }
    if (i >= parts.length) return token;
    final r = map[parts[i]];
    if (r == null) return token;
    parts[i] = r;
    return ns.isEmpty ? parts.join(':') : 'minecraft:${parts.sublist(1).join(':')}';
  }
}
