import 'package:flutter/material.dart';

/// App-wide visual theme. Each theme is a palette plus a background gradient.
class AuroraTheme {
  final String id;
  final String name;
  final Brightness brightness;
  final Color primary;
  final Color accent;
  final List<Color> background;
  final Color surface;
  final Color table; // game table felt
  const AuroraTheme(this.id, this.name, this.brightness, this.primary, this.accent,
      this.background, this.surface, this.table);

  bool get dark => brightness == Brightness.dark;

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: accent,
      surface: surface,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamilyFallback: const [
        'Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC', 'Segoe UI Symbol', 'Segoe UI Emoji',
        'Apple Color Emoji', 'Noto Color Emoji', 'sans-serif',
      ],
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: dark ? 0.82 : 0.9),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface.withValues(alpha: 0.6),
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface.withValues(alpha: 0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  BoxDecoration get backgroundDecoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: background,
        ),
      );
}

const _d = Brightness.dark;
const _l = Brightness.light;

/// Theme catalogue. The first one is the default (night blue + gold).
const List<AuroraTheme> auroraThemes = [
  AuroraTheme('majsoul', '夜空', _d, Color(0xFFD4AF37), Color(0xFF6FA8DC),
      [Color(0xFF0B1330), Color(0xFF1B2A5C), Color(0xFF2E1F4F)], Color(0xFF16204A), Color(0xFF1F4E5A)),
  AuroraTheme('aurora', '极光', _d, Color(0xFF4DE8B0), Color(0xFFB57BFF),
      [Color(0xFF041A24), Color(0xFF0B3B45), Color(0xFF2B1850)], Color(0xFF0E2A33), Color(0xFF15463F)),
  AuroraTheme('sakura', '樱花', _l, Color(0xFFE57399), Color(0xFF9C6ADE),
      [Color(0xFFFFF0F5), Color(0xFFFFD6E5), Color(0xFFF3E1FF)], Color(0xFFFFFAFC), Color(0xFF3F7F6A)),
  AuroraTheme('jade', '翡翠', _d, Color(0xFF3CCB7F), Color(0xFFE8D48A),
      [Color(0xFF06231A), Color(0xFF0D3D2C), Color(0xFF14543C)], Color(0xFF0C3326), Color(0xFF166B47)),
  AuroraTheme('crimson', '朱红宫殿', _d, Color(0xFFE53935), Color(0xFFFFC107),
      [Color(0xFF2A0707), Color(0xFF4A0E0E), Color(0xFF2B1B06)], Color(0xFF3A0C0C), Color(0xFF5B1A1A)),
  AuroraTheme('ocean', '深海', _d, Color(0xFF29B6F6), Color(0xFF80DEEA),
      [Color(0xFF01142A), Color(0xFF02315C), Color(0xFF01496B)], Color(0xFF062A4A), Color(0xFF0B4C6B)),
  AuroraTheme('sunset', '晚霞', _d, Color(0xFFFF8A50), Color(0xFFFFD54F),
      [Color(0xFF2B0F3A), Color(0xFF7A2C4B), Color(0xFFC0583B)], Color(0xFF3E1A3E), Color(0xFF5A3040)),
  AuroraTheme('mint', '薄荷', _l, Color(0xFF26A69A), Color(0xFF7E57C2),
      [Color(0xFFE8FFF8), Color(0xFFCFF5EC), Color(0xFFE0F2F1)], Color(0xFFF7FFFD), Color(0xFF2E7D6B)),
  AuroraTheme('lavender', '薰衣草', _l, Color(0xFF7E57C2), Color(0xFFEC407A),
      [Color(0xFFF5EEFF), Color(0xFFE6DAFF), Color(0xFFFDE7F3)], Color(0xFFFCFAFF), Color(0xFF4F5B93)),
  AuroraTheme('snow', '雪原', _l, Color(0xFF1E88E5), Color(0xFF00ACC1),
      [Color(0xFFF7FBFF), Color(0xFFE3F0FB), Color(0xFFEFF5FA)], Color(0xFFFFFFFF), Color(0xFF3C6E8F)),
  AuroraTheme('ink', '水墨', _l, Color(0xFF37474F), Color(0xFFB71C1C),
      [Color(0xFFF4F1EA), Color(0xFFE6E0D4), Color(0xFFD9D2C3)], Color(0xFFFAF8F3), Color(0xFF5D5A50)),
  AuroraTheme('midnight', '午夜', _d, Color(0xFF90A4AE), Color(0xFF64FFDA),
      [Color(0xFF050608), Color(0xFF101418), Color(0xFF1A1F26)], Color(0xFF14181D), Color(0xFF1F2B2E)),
  AuroraTheme('cyber', '赛博朋克', _d, Color(0xFFFF2BD6), Color(0xFF00F0FF),
      [Color(0xFF0A0014), Color(0xFF1D0038), Color(0xFF00202E)], Color(0xFF160026), Color(0xFF16213E)),
  AuroraTheme('forest', '森林', _d, Color(0xFF8BC34A), Color(0xFFFFB74D),
      [Color(0xFF0E1A0B), Color(0xFF1E3318), Color(0xFF2F4A22)], Color(0xFF1A2A15), Color(0xFF2E5A2A)),
  AuroraTheme('coffee', '咖啡', _d, Color(0xFFD7A86E), Color(0xFFFFE0B2),
      [Color(0xFF1E130C), Color(0xFF3B2618), Color(0xFF4E342E)], Color(0xFF2F1F15), Color(0xFF4A3526)),
  AuroraTheme('lemon', '柠檬', _l, Color(0xFFF9A825), Color(0xFF43A047),
      [Color(0xFFFFFDE7), Color(0xFFFFF59D), Color(0xFFF1F8E9)], Color(0xFFFFFEF5), Color(0xFF558B2F)),
  AuroraTheme('peach', '蜜桃', _l, Color(0xFFFF7043), Color(0xFFAB47BC),
      [Color(0xFFFFF3E0), Color(0xFFFFE0CC), Color(0xFFFFEBEE)], Color(0xFFFFFBF7), Color(0xFF8D5B4C)),
  AuroraTheme('royal', '皇家紫金', _d, Color(0xFFFFD54F), Color(0xFFCE93D8),
      [Color(0xFF1A0833), Color(0xFF32105C), Color(0xFF1B0B3A)], Color(0xFF261045), Color(0xFF3D2266)),
  AuroraTheme('steel', '钢铁', _d, Color(0xFF78909C), Color(0xFFFF7043),
      [Color(0xFF1C2226), Color(0xFF2C353B), Color(0xFF37474F)], Color(0xFF263036), Color(0xFF34464F)),
  AuroraTheme('desert', '沙漠', _l, Color(0xFFBF8040), Color(0xFF00897B),
      [Color(0xFFFFF4E0), Color(0xFFF3DDB3), Color(0xFFE8C99A)], Color(0xFFFFFAF0), Color(0xFF9C7A4A)),
  AuroraTheme('galaxy', '星河', _d, Color(0xFFB388FF), Color(0xFF82B1FF),
      [Color(0xFF07021A), Color(0xFF1A0B3D), Color(0xFF0A1E4A)], Color(0xFF140A33), Color(0xFF231B4F)),
  AuroraTheme('lava', '熔岩', _d, Color(0xFFFF5722), Color(0xFFFFEB3B),
      [Color(0xFF120404), Color(0xFF3A0A00), Color(0xFF5A1500)], Color(0xFF2A0A04), Color(0xFF4A1A0A)),
  AuroraTheme('glacier', '冰川', _d, Color(0xFF80D8FF), Color(0xFFE1F5FE),
      [Color(0xFF02111C), Color(0xFF0A2E40), Color(0xFF14506A)], Color(0xFF0B2536), Color(0xFF1B4C63)),
  AuroraTheme('bamboo', '竹林', _l, Color(0xFF689F38), Color(0xFF8D6E63),
      [Color(0xFFF1F8E9), Color(0xFFDCEDC8), Color(0xFFE8F5E9)], Color(0xFFFAFFF5), Color(0xFF4E7A35)),
  AuroraTheme('rose', '玫瑰金', _l, Color(0xFFB76E79), Color(0xFFC9A227),
      [Color(0xFFFFF5F3), Color(0xFFF7DCD7), Color(0xFFF2E6D8)], Color(0xFFFFFCFB), Color(0xFF8E5A5F)),
  AuroraTheme('matcha', '抹茶', _l, Color(0xFF7CB342), Color(0xFF6D4C41),
      [Color(0xFFF4F9E9), Color(0xFFE3EFC8), Color(0xFFF0EAD6)], Color(0xFFFCFEF7), Color(0xFF5C7F35)),
  AuroraTheme('neon', '霓虹', _d, Color(0xFF76FF03), Color(0xFFFF4081),
      [Color(0xFF000000), Color(0xFF0D0D1A), Color(0xFF001A0D)], Color(0xFF0B0B14), Color(0xFF102010)),
  AuroraTheme('autumn', '秋枫', _d, Color(0xFFFF9800), Color(0xFFD84315),
      [Color(0xFF231105), Color(0xFF4A220A), Color(0xFF3A1A10)], Color(0xFF331A0B), Color(0xFF5A3A1A)),
  AuroraTheme('sky', '晴空', _l, Color(0xFF039BE5), Color(0xFFFFB300),
      [Color(0xFFE1F5FE), Color(0xFFB3E5FC), Color(0xFFFFF8E1)], Color(0xFFF7FCFF), Color(0xFF3A7CA5)),
  AuroraTheme('mono', '黑白', _l, Color(0xFF212121), Color(0xFF757575),
      [Color(0xFFFFFFFF), Color(0xFFF2F2F2), Color(0xFFE6E6E6)], Color(0xFFFFFFFF), Color(0xFF555555)),
  AuroraTheme('dracula', '德古拉', _d, Color(0xFFBD93F9), Color(0xFFFF79C6),
      [Color(0xFF191A21), Color(0xFF282A36), Color(0xFF343746)], Color(0xFF21222C), Color(0xFF3A3C4E)),
  AuroraTheme('nord', '北境', _d, Color(0xFF88C0D0), Color(0xFFA3BE8C),
      [Color(0xFF242933), Color(0xFF2E3440), Color(0xFF3B4252)], Color(0xFF2E3440), Color(0xFF434C5E)),
  AuroraTheme('solar', '日光', _l, Color(0xFF268BD2), Color(0xFFCB4B16),
      [Color(0xFFFDF6E3), Color(0xFFEEE8D5), Color(0xFFF5EFDC)], Color(0xFFFDF6E3), Color(0xFF657B83)),
  AuroraTheme('candy', '糖果', _l, Color(0xFFFF4081), Color(0xFF40C4FF),
      [Color(0xFFFFF0F7), Color(0xFFE3F6FF), Color(0xFFFFFDE0)], Color(0xFFFFFFFF), Color(0xFF7B5EA7)),
  AuroraTheme('emperor', '帝王黄', _d, Color(0xFFFFC400), Color(0xFFE53935),
      [Color(0xFF1F1400), Color(0xFF3D2800), Color(0xFF2A0A00)], Color(0xFF2E1E00), Color(0xFF5A3F00)),
  AuroraTheme('abyss', '深渊', _d, Color(0xFF00BFA5), Color(0xFF651FFF),
      [Color(0xFF000A0A), Color(0xFF001F1F), Color(0xFF0A0020)], Color(0xFF001414), Color(0xFF00302C)),
];

/// Asset path prefix: '' when Aurora runs standalone, 'packages/aurora_client/' when embedded in a host app.
String assetPrefix = '';

/// Set by the host launcher (CML): when non-null every screen uses it and the theme picker is hidden.
AuroraTheme? hostTheme;

AuroraTheme themeById(String id) =>
    hostTheme ?? auroraThemes.firstWhere((t) => t.id == id, orElse: () => auroraThemes.first);
