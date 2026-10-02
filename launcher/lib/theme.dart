import 'dart:convert';
import 'dart:io';

import 'package:cml_core/cml_core.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'i18n/i18n.dart';

/// A selectable launcher theme.
///
/// Most themes are a seed + gradient colour and follow the light / dark switch. Themes with a
/// [fixed] brightness (Dracula, sepia paper …) always use it and may pin their own page / card colours.
/// This catalogue is the only theme source for CML and everything it embeds (Aurora, Pulse) or
/// launches (DesktopPet, LiteEditor, LiteReader, LumiKeyMapper — via `%APPDATA%\CML\theme.json`).
class CmlTheme {
  final String id;
  final String name;
  final String group;
  final Color seed;

  /// Secondary gradient colour for hero banners.
  final Color accent2;
  final Brightness? fixed;
  final Color? bg, surface, text;
  const CmlTheme(this.id, this.name, this.seed, this.accent2, {this.group = 'mc', this.fixed, this.bg, this.surface, this.text});

  bool isDark(bool darkSetting) => fixed == null ? darkSetting : fixed == Brightness.dark;
}

/// Theme groups in the order shown in settings.
Map<String, String> get cmlThemeGroups => {
      'mc': trGlobal('Minecraft'),
      'fresh': trGlobal('明亮清新'),
      'sweet': trGlobal('甜美缤纷'),
      'nature': trGlobal('自然'),
      'night': trGlobal('深邃暗色'),
      'eye': trGlobal('护眼阅读'),
    };

const _d = Brightness.dark, _l = Brightness.light;

List<CmlTheme> get cmlThemes => <CmlTheme>[
  // ---- Minecraft (follow the light / dark switch) ----
  CmlTheme('chtholly', trGlobal('珂朵莉蓝'), Color(0xFF4FA3D9), Color(0xFF7FD3C8)),
  CmlTheme('flower', trGlobal('七色花'), Color(0xFF7C5CFF), Color(0xFFFF7AA2)),
  CmlTheme('pcl', trGlobal('经典蓝'), Color(0xFF1370F3), Color(0xFF52A8FF)),
  CmlTheme('grass', trGlobal('草方块'), Color(0xFF5DA130), Color(0xFFB8D86B)),
  CmlTheme('nether', trGlobal('下界'), Color(0xFFB2362F), Color(0xFFF08A4B)),
  CmlTheme('end', trGlobal('末地'), Color(0xFF8E6BBF), Color(0xFFE2D98B)),
  CmlTheme('amethyst', trGlobal('紫水晶'), Color(0xFF9A5CC6), Color(0xFFD7A6FF)),
  CmlTheme('gold', trGlobal('金块'), Color(0xFFE0A526), Color(0xFFFFD66B)),
  CmlTheme('diamond', trGlobal('钻石'), Color(0xFF2CC6C1), Color(0xFF7BE8FF)),
  CmlTheme('sakura', trGlobal('樱花'), Color(0xFFE88BAA), Color(0xFFFFC2D4)),
  CmlTheme('redstone', trGlobal('红石'), Color(0xFFE53935), Color(0xFFFF8A65)),
  CmlTheme('deepslate', trGlobal('深板岩'), Color(0xFF5E6B78), Color(0xFF9AA8B5)),
  CmlTheme('emerald', trGlobal('绿宝石'), Color(0xFF17B169), Color(0xFF8BE3B0)),
  CmlTheme('lapis', trGlobal('青金石'), Color(0xFF2A4FB8), Color(0xFF6E8BF0)),
  CmlTheme('copper', trGlobal('铜块'), Color(0xFFC46A3C), Color(0xFF5FB8A0)),
  CmlTheme('cherry', trGlobal('樱花林'), Color(0xFFE47FA8), Color(0xFFB7E08A)),
  CmlTheme('ocean_mc', trGlobal('海晶石'), Color(0xFF3AA6A0), Color(0xFF9FE3D6)),
  CmlTheme('honey', trGlobal('蜂蜜块'), Color(0xFFE59A14), Color(0xFFFFD25E)),
  CmlTheme('sculk', trGlobal('幽匿'), Color(0xFF1E8C9A), Color(0xFF52E0E8)),
  CmlTheme('mushroom', trGlobal('蘑菇岛'), Color(0xFF9C5A8A), Color(0xFFE07A5F)),
  // ---- 明亮清新 ----
  CmlTheme('daylight', trGlobal('晴空'), Color(0xFF4F6BFF), Color(0xFF00B3C7), group: 'fresh', fixed: _l, bg: Color(0xFFF4F6FB)),
  CmlTheme('mint', trGlobal('薄荷'), Color(0xFF10A37F), Color(0xFF3BB2E6), group: 'fresh', fixed: _l, bg: Color(0xFFF0FAF6)),
  CmlTheme('porcelain', trGlobal('青花瓷'), Color(0xFF1E4FA3), Color(0xFF4A8FD8), group: 'fresh', fixed: _l, bg: Color(0xFFF3F7FC)),
  CmlTheme('seasalt', trGlobal('海盐'), Color(0xFF2A9AA8), Color(0xFF7FD0DA), group: 'fresh', fixed: _l, bg: Color(0xFFEEF7F8)),
  CmlTheme('snow', trGlobal('雪原'), Color(0xFF3A6DF0), Color(0xFF00ACC1), group: 'fresh', fixed: _l, bg: Color(0xFFF4F6F8)),
  CmlTheme('paper', trGlobal('米白极简'), Color(0xFF4A4A48), Color(0xFF9A9A96), group: 'fresh', fixed: _l, bg: Color(0xFFF6F5F2)),
  CmlTheme('ink_wash', trGlobal('水墨'), Color(0xFF3D3D38), Color(0xFFB23A2A), group: 'fresh', fixed: _l, bg: Color(0xFFF2F1EC), surface: Color(0xFFFBFAF6)),
  CmlTheme('solarlight', trGlobal('日晖'), Color(0xFF268BD2), Color(0xFF2AA198), group: 'fresh', fixed: _l, bg: Color(0xFFFDF6E3), surface: Color(0xFFFFFBEF), text: Color(0xFF40515A)),
  // ---- 甜美缤纷 ----
  CmlTheme('lavender', trGlobal('薰衣草'), Color(0xFF7C4DFF), Color(0xFFE05FB3), group: 'sweet', fixed: _l, bg: Color(0xFFF6F3FF)),
  CmlTheme('candy', trGlobal('糖果'), Color(0xFFFF4FA3), Color(0xFF6C63FF), group: 'sweet', fixed: _l, bg: Color(0xFFFFF4FB)),
  CmlTheme('peach', trGlobal('蜜桃乌龙'), Color(0xFFE8664A), Color(0xFFFFB08A), group: 'sweet', fixed: _l, bg: Color(0xFFFFF3EE)),
  CmlTheme('sunrise', trGlobal('朝霞'), Color(0xFFF97316), Color(0xFFE11D48), group: 'sweet', fixed: _l, bg: Color(0xFFFFF8F1)),
  CmlTheme('grape', trGlobal('葡萄汽水'), Color(0xFFA347C7), Color(0xFFFF8BD1), group: 'sweet', fixed: _l, bg: Color(0xFFF6EFFA)),
  CmlTheme('rose_gold', trGlobal('玫瑰金'), Color(0xFFB76E79), Color(0xFFC9A227), group: 'sweet', fixed: _l, bg: Color(0xFFFFF5F3)),
  CmlTheme('aurora', trGlobal('极光'), Color(0xFF22D3EE), Color(0xFFA855F7), group: 'sweet', fixed: _d, bg: Color(0xFF0A1224), surface: Color(0xFF111C36)),
  CmlTheme('galaxy', trGlobal('银河'), Color(0xFF8B7BFF), Color(0xFFFF8BD1), group: 'sweet', fixed: _d, bg: Color(0xFF0D0B1F), surface: Color(0xFF17143A)),
  CmlTheme('sunset', trGlobal('落日熔金'), Color(0xFFFF7A59), Color(0xFFFFC15E), group: 'sweet', fixed: _d, bg: Color(0xFF1D0F1C), surface: Color(0xFF2A1628)),
  CmlTheme('royal', trGlobal('皇家紫金'), Color(0xFFC084FC), Color(0xFFFBBF24), group: 'sweet', fixed: _d, bg: Color(0xFF140C24), surface: Color(0xFF1F1436)),
  // ---- 自然 ----
  CmlTheme('matcha', trGlobal('抹茶拿铁'), Color(0xFF7A9A3A), Color(0xFFC9B27A), group: 'nature', fixed: _l, bg: Color(0xFFF3F5EA)),
  CmlTheme('bamboo', trGlobal('竹林'), Color(0xFF4A9A5A), Color(0xFF8D6E63), group: 'nature', fixed: _l, bg: Color(0xFFEEF5EE)),
  CmlTheme('autumn', trGlobal('秋日枫叶'), Color(0xFFC8502A), Color(0xFFF2A65A), group: 'nature', fixed: _l, bg: Color(0xFFFBF2EA)),
  CmlTheme('desert', trGlobal('沙漠'), Color(0xFFB8894A), Color(0xFF00897B), group: 'nature', fixed: _l, bg: Color(0xFFF8F2E8)),
  CmlTheme('forest', trGlobal('暗夜森林'), Color(0xFF4ADE80), Color(0xFFA3E635), group: 'nature', fixed: _d, bg: Color(0xFF0F1A14), surface: Color(0xFF16261D)),
  CmlTheme('deepsea', trGlobal('深海'), Color(0xFF29B6F6), Color(0xFF26C6DA), group: 'nature', fixed: _d, bg: Color(0xFF07161F), surface: Color(0xFF0D2230)),
  CmlTheme('glacier', trGlobal('冰川'), Color(0xFF80D8FF), Color(0xFFB3E5FC), group: 'nature', fixed: _d, bg: Color(0xFF02111C), surface: Color(0xFF0B2536)),
  CmlTheme('lava', trGlobal('熔岩'), Color(0xFFFF5722), Color(0xFFFFEB3B), group: 'nature', fixed: _d, bg: Color(0xFF120404), surface: Color(0xFF2A0A04)),
  // ---- 深邃暗色 ----
  CmlTheme('midnight', trGlobal('午夜星河'), Color(0xFF7C5CFF), Color(0xFF20C4D8), group: 'night', fixed: _d, bg: Color(0xFF0F1220), surface: Color(0xFF171B2E)),
  CmlTheme('graphite', trGlobal('石墨'), Color(0xFF8AB4F8), Color(0xFF81C995), group: 'night', fixed: _d, bg: Color(0xFF161616), surface: Color(0xFF1F1F1F)),
  CmlTheme('obsidian', trGlobal('黑曜石'), Color(0xFFA78BFA), Color(0xFFF472B6), group: 'night', fixed: _d, bg: Color(0xFF08080B), surface: Color(0xFF121217)),
  CmlTheme('nord', trGlobal('北境'), Color(0xFF88C0D0), Color(0xFFA3BE8C), group: 'night', fixed: _d, bg: Color(0xFF2E3440), surface: Color(0xFF3B4252), text: Color(0xFFECEFF4)),
  CmlTheme('dracula', trGlobal('德古拉'), Color(0xFFBD93F9), Color(0xFFFF79C6), group: 'night', fixed: _d, bg: Color(0xFF1E1F29), surface: Color(0xFF282A36), text: Color(0xFFF8F8F2)),
  CmlTheme('tokyo', trGlobal('东京夜'), Color(0xFF7AA2F7), Color(0xFFBB9AF7), group: 'night', fixed: _d, bg: Color(0xFF16161E), surface: Color(0xFF1F2030), text: Color(0xFFC0CAF5)),
  CmlTheme('mocha', trGlobal('摩卡'), Color(0xFFCBA6F7), Color(0xFFF5C2E7), group: 'night', fixed: _d, bg: Color(0xFF181825), surface: Color(0xFF1E1E2E), text: Color(0xFFCDD6F4)),
  CmlTheme('gruvbox', trGlobal('复古暖色'), Color(0xFFFE8019), Color(0xFFFABD2F), group: 'night', fixed: _d, bg: Color(0xFF282828), surface: Color(0xFF32302F), text: Color(0xFFEBDBB2)),
  CmlTheme('cyberpunk', trGlobal('赛博朋克'), Color(0xFFFF2BD6), Color(0xFF00F0FF), group: 'night', fixed: _d, bg: Color(0xFF0B0716), surface: Color(0xFF160F2A)),
  CmlTheme('neon', trGlobal('霓虹'), Color(0xFF39FF14), Color(0xFFFF2E97), group: 'night', fixed: _d, bg: Color(0xFF050510), surface: Color(0xFF0E0E22)),
  CmlTheme('wine', trGlobal('勃艮第'), Color(0xFFF43F5E), Color(0xFFFB923C), group: 'night', fixed: _d, bg: Color(0xFF1A0F14), surface: Color(0xFF26161E)),
  CmlTheme('coffee', trGlobal('深焙咖啡'), Color(0xFFD4A373), Color(0xFFE9C46A), group: 'night', fixed: _d, bg: Color(0xFF1B1510), surface: Color(0xFF261E17)),
  CmlTheme('contrast', trGlobal('高对比度'), Color(0xFFFFD400), Color(0xFF00E5FF), group: 'night', fixed: _d, bg: Color(0xFF000000), surface: Color(0xFF0D0D0D), text: Color(0xFFFFFFFF)),
  // ---- 护眼阅读 ----
  CmlTheme('sepia', trGlobal('羊皮纸'), Color(0xFFA0622D), Color(0xFF6B8E23), group: 'eye', fixed: _l, bg: Color(0xFFF1E7D0), surface: Color(0xFFF8F0DC), text: Color(0xFF4A3A24)),
  CmlTheme('green_eye', trGlobal('豆沙绿'), Color(0xFF2F7D4A), Color(0xFF5B8C3A), group: 'eye', fixed: _l, bg: Color(0xFFCFE6CF), surface: Color(0xFFDCEFD9), text: Color(0xFF23402A)),
  CmlTheme('kraft', trGlobal('牛皮纸'), Color(0xFF8B5A2B), Color(0xFF556B2F), group: 'eye', fixed: _l, bg: Color(0xFFE3D3B6), surface: Color(0xFFECDFC6), text: Color(0xFF3F3121)),
  CmlTheme('night_read', trGlobal('夜读'), Color(0xFFC9A36A), Color(0xFF8AA37B), group: 'eye', fixed: _d, bg: Color(0xFF121212), surface: Color(0xFF1B1B1B), text: Color(0xFFB8B2A7)),
  CmlTheme('moss', trGlobal('青苔'), Color(0xFF9CCC65), Color(0xFFD4B86A), group: 'eye', fixed: _d, bg: Color(0xFF1B2119), surface: Color(0xFF232B20), text: Color(0xFFCFD8C4)),
  CmlTheme('amber', trGlobal('琥珀暖光'), Color(0xFFF0A64A), Color(0xFFD98A3A), group: 'eye', fixed: _d, bg: Color(0xFF1C160D), surface: Color(0xFF271E12), text: Color(0xFFF0DCB8)),
];

CmlTheme themeById(String id) => cmlThemes.firstWhere((t) => t.id == id, orElse: () => cmlThemes.first);

/// Resolved colours of the active theme — what embedded modules (Aurora, Pulse) and external apps
/// (via theme.json) use to look like CML. Read it with [CmlPalette.of].
class CmlPalette {
  final String id;
  final String name;
  final bool dark;
  final Color bg, surface, panel, text, muted, line, field, accent, accent2, onAccent, paper, ink;
  const CmlPalette({
    required this.id,
    required this.name,
    required this.dark,
    required this.bg,
    required this.surface,
    required this.panel,
    required this.text,
    required this.muted,
    required this.line,
    required this.field,
    required this.accent,
    required this.accent2,
    required this.onAccent,
    required this.paper,
    required this.ink,
  });

  Brightness get brightness => dark ? Brightness.dark : Brightness.light;

  static CmlPalette of(BuildContext c) => CmlColors.of(c).palette;

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// The `%APPDATA%\CML\theme.json` payload (docs/THEME_BRIDGE.md).
  Map<String, Object> toBridgeJson() => {
        'version': 1,
        'id': id,
        'name': name,
        'dark': dark,
        'bg': _hex(bg),
        'surface': _hex(surface),
        'panel': _hex(panel),
        'text': _hex(text),
        'muted': _hex(muted),
        'line': _hex(line),
        'field': _hex(field),
        'accent': _hex(accent),
        'accent2': _hex(accent2),
        'onAccent': _hex(onAccent),
        'paper': _hex(paper),
        'ink': _hex(ink),
        'art': [_hex(accent), _hex(accent2)],
      };
}

/// Builds the palette for [t]; [accent] overrides the seed colour.
CmlPalette resolvePalette(CmlTheme t, {required bool darkSetting, Color? accent}) {
  final dark = t.isDark(darkSetting);
  final seed = accent ?? t.seed;
  final bg = t.bg ?? (dark ? Color.alphaBlend(seed.withValues(alpha: 0.05), const Color(0xFF121418)) : Color.alphaBlend(seed.withValues(alpha: 0.035), const Color(0xFFF7F8FA)));
  final surface = t.surface ?? (dark ? Color.alphaBlend(seed.withValues(alpha: 0.06), Color.lerp(bg, Colors.white, 0.05)!) : Colors.white);
  final text = t.text ?? (dark ? const Color(0xFFE6E8EC) : const Color(0xFF1D2233));
  final line = dark ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), bg) : Color.alphaBlend(Colors.black.withValues(alpha: 0.08), bg);
  return CmlPalette(
    id: t.id,
    name: t.name,
    dark: dark,
    bg: bg,
    surface: surface,
    panel: dark ? Color.lerp(bg, Colors.black, 0.25)! : surface,
    text: text,
    muted: Color.lerp(text, bg, 0.42)!,
    line: line,
    field: dark ? Color.alphaBlend(Colors.white.withValues(alpha: 0.05), surface) : Color.alphaBlend(seed.withValues(alpha: 0.04), const Color(0xFFF3F5F8)),
    accent: seed,
    accent2: t.accent2,
    // text on the raw seed colour (external apps paint buttons with `accent`, not the M3 primary)
    onAccent: seed.computeLuminance() > 0.45 ? const Color(0xFF111111) : Colors.white,
    paper: dark ? Color.lerp(surface, Colors.black, 0.1)! : (t.surface ?? Colors.white),
    ink: text,
  );
}

/// Extra colours not covered by ColorScheme.
class CmlColors extends ThemeExtension<CmlColors> {
  final Color gradientA, gradientB, sidebar, cardBorder, pageBg1, pageBg2;
  final CmlPalette palette;
  const CmlColors({required this.gradientA, required this.gradientB, required this.sidebar, required this.cardBorder, required this.pageBg1, required this.pageBg2, required this.palette});

  LinearGradient get hero => LinearGradient(colors: [gradientA, gradientB], begin: Alignment.topLeft, end: Alignment.bottomRight);

  @override
  CmlColors copyWith() => this;
  @override
  CmlColors lerp(CmlColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CmlColors(
      gradientA: l(gradientA, other.gradientA),
      gradientB: l(gradientB, other.gradientB),
      sidebar: l(sidebar, other.sidebar),
      cardBorder: l(cardBorder, other.cardBorder),
      pageBg1: l(pageBg1, other.pageBg1),
      pageBg2: l(pageBg2, other.pageBg2),
      palette: t < 0.5 ? palette : other.palette,
    );
  }

  static CmlColors of(BuildContext c) => Theme.of(c).extension<CmlColors>()!;
}

ThemeData buildTheme(CmlTheme t, {required bool dark, Color? accent}) {
  final pal = resolvePalette(t, darkSetting: dark, accent: accent);
  final isDark = pal.dark;
  final seed = pal.accent;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: isDark ? Brightness.dark : Brightness.light)
      .copyWith(surface: pal.bg, onSurface: t.text ?? (t.fixed != null ? pal.text : null));
  final surface = pal.bg;
  final card = pal.surface;
  final border = isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06);
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Microsoft YaHei UI',
    fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI', 'PingFang SC'],
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
  );
  final radius = BorderRadius.circular(14);
  return base.copyWith(
    scaffoldBackgroundColor: surface,
    extensions: [
      CmlColors(
        gradientA: seed,
        gradientB: t.accent2,
        sidebar: t.fixed != null ? (isDark ? Color.lerp(surface, Colors.black, 0.3)! : card) : (isDark ? Color.alphaBlend(seed.withValues(alpha: 0.04), const Color(0xFF0E1013)) : Colors.white),
        cardBorder: border,
        pageBg1: surface,
        pageBg2: isDark ? Color.alphaBlend(t.accent2.withValues(alpha: 0.05), surface) : Color.alphaBlend(t.accent2.withValues(alpha: 0.06), surface),
        palette: pal,
      ),
    ],
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: border)),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(backgroundColor: card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: pal.field,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: scheme.primary, width: 1.6)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), side: BorderSide(color: border.withValues(alpha: 0.18)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), side: BorderSide(color: border)),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      indicator: UnderlineTabIndicator(borderSide: BorderSide(color: scheme.primary, width: 3), borderRadius: BorderRadius.circular(3)),
    ),
    snackBarTheme: SnackBarThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    scrollbarTheme: ScrollbarThemeData(radius: const Radius.circular(8), thickness: const WidgetStatePropertyAll(6), thumbColor: WidgetStatePropertyAll(scheme.onSurface.withValues(alpha: 0.18))),
    progressIndicatorTheme: ProgressIndicatorThemeData(linearTrackColor: scheme.primary.withValues(alpha: 0.12)),
  );
}

/// Writes `%APPDATA%\CML\theme.json` when the effective palette changes, so launched apps follow CML.
abstract class ThemeBridge {
  static String _last = '';
  static String get path => p.join(Os.cmlHome, 'theme.json');

  static void publish(CmlPalette pal) {
    final s = const JsonEncoder.withIndent('  ').convert(pal.toBridgeJson());
    if (s == _last) return;
    _last = s;
    try {
      Directory(Os.cmlHome).createSync(recursive: true);
      final tmp = File('$path.tmp')..writeAsStringSync(s);
      tmp.renameSync(path);
    } catch (_) {
      _last = '';
    }
  }
}
