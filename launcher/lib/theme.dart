import 'package:flutter/material.dart';

import 'i18n/i18n.dart';

/// A selectable launcher theme.
class CmlTheme {
  final String id;
  final String name;
  final Color seed;

  /// Secondary gradient colour for hero banners.
  final Color accent2;
  const CmlTheme(this.id, this.name, this.seed, this.accent2);
}

List<CmlTheme> get cmlThemes => <CmlTheme>[
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
];

CmlTheme themeById(String id) => cmlThemes.firstWhere((t) => t.id == id, orElse: () => cmlThemes.first);

/// Extra colours not covered by ColorScheme.
class CmlColors extends ThemeExtension<CmlColors> {
  final Color gradientA, gradientB, sidebar, cardBorder, pageBg1, pageBg2;
  const CmlColors({required this.gradientA, required this.gradientB, required this.sidebar, required this.cardBorder, required this.pageBg1, required this.pageBg2});

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
    );
  }

  static CmlColors of(BuildContext c) => Theme.of(c).extension<CmlColors>()!;
}

ThemeData buildTheme(CmlTheme t, {required bool dark, Color? accent}) {
  final seed = accent ?? t.seed;
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: dark ? Brightness.dark : Brightness.light);
  final surface = dark ? Color.alphaBlend(seed.withValues(alpha: 0.05), const Color(0xFF121418)) : Color.alphaBlend(seed.withValues(alpha: 0.035), const Color(0xFFF7F8FA));
  final card = dark ? Color.alphaBlend(seed.withValues(alpha: 0.06), const Color(0xFF1B1E24)) : Colors.white;
  final border = dark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06);
  final base = ThemeData(
    colorScheme: scheme.copyWith(surface: surface),
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
        sidebar: dark ? Color.alphaBlend(seed.withValues(alpha: 0.04), const Color(0xFF0E1013)) : Colors.white,
        cardBorder: border,
        pageBg1: surface,
        pageBg2: dark ? Color.alphaBlend(t.accent2.withValues(alpha: 0.05), surface) : Color.alphaBlend(t.accent2.withValues(alpha: 0.06), surface),
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
      fillColor: dark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF3F5F8),
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
