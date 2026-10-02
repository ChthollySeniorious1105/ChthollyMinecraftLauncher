import 'package:flutter/material.dart';

/// A Pulse theme: Discord-like layout colours (server rail, sidebar, chat area)
/// plus accent. Every widget reads colours from [PulseColors] via
/// `PulseColors.of(context)`, so adding a theme is just one entry below.
class PulseTheme {
  final String id;
  final String name;
  final Brightness brightness;
  final Color rail; // far-left strip
  final Color sidebar; // channel list / member list
  final Color chat; // main message area
  final Color input; // composer + text fields
  final Color hover; // list hover / selected
  final Color accent;
  final Color text;
  final Color muted; // secondary text
  final Color divider;
  final Color online, idle, dnd;
  final Color danger;

  const PulseTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.rail,
    required this.sidebar,
    required this.chat,
    required this.input,
    required this.hover,
    required this.accent,
    required this.text,
    required this.muted,
    required this.divider,
    this.online = const Color(0xFF23A55A),
    this.idle = const Color(0xFFF0B232),
    this.dnd = const Color(0xFFF23F43),
    this.danger = const Color(0xFFDA373C),
  });

  bool get dark => brightness == Brightness.dark;

  Color get onAccent => accent.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white;

  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      onPrimary: onAccent,
      surface: chat,
      onSurface: text,
      error: danger,
    );
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: chat,
      fontFamily: 'Microsoft YaHei UI',
      fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI', 'Segoe UI Emoji', 'Segoe UI Symbol', 'sans-serif'],
      visualDensity: VisualDensity.compact,
      extensions: [PulseColors(this)],
    );
    return base.copyWith(
      dividerColor: divider,
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      iconTheme: IconThemeData(color: muted, size: 20),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: dark ? const Color(0xFF111214) : const Color(0xFF2B2D31), borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: chat,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: dark ? Color.lerp(rail, Colors.black, 0.2) : Colors.white,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        isDense: true,
        hintStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: accent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: text)),
      sliderTheme: SliderThemeData(activeTrackColor: accent, thumbColor: Colors.white, inactiveTrackColor: divider, trackHeight: 6),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? online : muted.withValues(alpha: 0.5)),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(dark ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.25)),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF111214) : const Color(0xFF313338),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class PulseColors extends ThemeExtension<PulseColors> {
  final PulseTheme t;
  const PulseColors(this.t);

  static PulseTheme of(BuildContext context) => Theme.of(context).extension<PulseColors>()!.t;

  @override
  PulseColors copyWith() => this;
  @override
  PulseColors lerp(covariant PulseColors? other, double v) => v < 0.5 ? this : (other ?? this);
}

const _d = Brightness.dark, _l = Brightness.light;

/// Theme catalogue (first = default).
const List<PulseTheme> pulseThemes = [
  PulseTheme(id: 'dark', name: '暗夜（默认）', brightness: _d, rail: Color(0xFF1E1F22), sidebar: Color(0xFF2B2D31), chat: Color(0xFF313338),
      input: Color(0xFF383A40), hover: Color(0xFF404249), accent: Color(0xFF5865F2), text: Color(0xFFDBDEE1), muted: Color(0xFF949BA4),
      divider: Color(0xFF3F4147)),
  PulseTheme(id: 'midnight', name: '午夜纯黑', brightness: _d, rail: Color(0xFF000000), sidebar: Color(0xFF0B0B0D), chat: Color(0xFF111113),
      input: Color(0xFF1C1C1F), hover: Color(0xFF26262A), accent: Color(0xFF7289DA), text: Color(0xFFE6E6E6), muted: Color(0xFF8A8A92),
      divider: Color(0xFF232326)),
  PulseTheme(id: 'light', name: '明亮', brightness: _l, rail: Color(0xFFE3E5E8), sidebar: Color(0xFFF2F3F5), chat: Color(0xFFFFFFFF),
      input: Color(0xFFEBEDEF), hover: Color(0xFFE0E1E5), accent: Color(0xFF5865F2), text: Color(0xFF2E3338), muted: Color(0xFF5C5E66),
      divider: Color(0xFFE1E2E4)),
  PulseTheme(id: 'nord', name: '北境', brightness: _d, rail: Color(0xFF242933), sidebar: Color(0xFF2E3440), chat: Color(0xFF3B4252),
      input: Color(0xFF434C5E), hover: Color(0xFF4C566A), accent: Color(0xFF88C0D0), text: Color(0xFFECEFF4), muted: Color(0xFFA5ADBA),
      divider: Color(0xFF4C566A), online: Color(0xFFA3BE8C), idle: Color(0xFFEBCB8B), dnd: Color(0xFFBF616A)),
  PulseTheme(id: 'dracula', name: '德古拉', brightness: _d, rail: Color(0xFF191A21), sidebar: Color(0xFF21222C), chat: Color(0xFF282A36),
      input: Color(0xFF343746), hover: Color(0xFF3C3F52), accent: Color(0xFFBD93F9), text: Color(0xFFF8F8F2), muted: Color(0xFF9EA2BF),
      divider: Color(0xFF44475A), online: Color(0xFF50FA7B), idle: Color(0xFFF1FA8C), dnd: Color(0xFFFF5555)),
  PulseTheme(id: 'mocha', name: '摩卡', brightness: _d, rail: Color(0xFF11111B), sidebar: Color(0xFF181825), chat: Color(0xFF1E1E2E),
      input: Color(0xFF313244), hover: Color(0xFF45475A), accent: Color(0xFFCBA6F7), text: Color(0xFFCDD6F4), muted: Color(0xFFA6ADC8),
      divider: Color(0xFF313244), online: Color(0xFFA6E3A1), idle: Color(0xFFF9E2AF), dnd: Color(0xFFF38BA8)),
  PulseTheme(id: 'latte', name: '拿铁', brightness: _l, rail: Color(0xFFDCE0E8), sidebar: Color(0xFFE6E9EF), chat: Color(0xFFEFF1F5),
      input: Color(0xFFCCD0DA), hover: Color(0xFFBCC0CC), accent: Color(0xFF8839EF), text: Color(0xFF4C4F69), muted: Color(0xFF6C6F85),
      divider: Color(0xFFCCD0DA), online: Color(0xFF40A02B), idle: Color(0xFFDF8E1D), dnd: Color(0xFFD20F39)),
  PulseTheme(id: 'solarized', name: '日光暗色', brightness: _d, rail: Color(0xFF001E26), sidebar: Color(0xFF002B36), chat: Color(0xFF073642),
      input: Color(0xFF0A4555), hover: Color(0xFF125566), accent: Color(0xFF268BD2), text: Color(0xFFEEE8D5), muted: Color(0xFF93A1A1),
      divider: Color(0xFF0E4B5A), online: Color(0xFF859900), idle: Color(0xFFB58900), dnd: Color(0xFFDC322F)),
  PulseTheme(id: 'solarlight', name: '日光亮色', brightness: _l, rail: Color(0xFFE4DCC4), sidebar: Color(0xFFEEE8D5), chat: Color(0xFFFDF6E3),
      input: Color(0xFFE9E2CB), hover: Color(0xFFE0D8BE), accent: Color(0xFF268BD2), text: Color(0xFF586E75), muted: Color(0xFF7D8F91),
      divider: Color(0xFFDDD6BF), online: Color(0xFF859900), idle: Color(0xFFB58900), dnd: Color(0xFFDC322F)),
  PulseTheme(id: 'forest', name: '森林', brightness: _d, rail: Color(0xFF0F1A13), sidebar: Color(0xFF16241B), chat: Color(0xFF1C2E22),
      input: Color(0xFF243A2B), hover: Color(0xFF2C4735), accent: Color(0xFF4CC38A), text: Color(0xFFE2EFE6), muted: Color(0xFF94AE9D),
      divider: Color(0xFF2A3F31)),
  PulseTheme(id: 'ocean', name: '深海', brightness: _d, rail: Color(0xFF071421), sidebar: Color(0xFF0B1D2F), chat: Color(0xFF10263C),
      input: Color(0xFF16314C), hover: Color(0xFF1D3C5C), accent: Color(0xFF38BDF8), text: Color(0xFFE0F2FE), muted: Color(0xFF8DA9C4),
      divider: Color(0xFF1C3652)),
  PulseTheme(id: 'sakura', name: '樱花', brightness: _l, rail: Color(0xFFF6DDE6), sidebar: Color(0xFFFBEAF0), chat: Color(0xFFFFF7FA),
      input: Color(0xFFF7E1EA), hover: Color(0xFFF2D3DF), accent: Color(0xFFE0558A), text: Color(0xFF4A2B38), muted: Color(0xFF8E6878),
      divider: Color(0xFFF0D5E0)),
  PulseTheme(id: 'cyber', name: '赛博朋克', brightness: _d, rail: Color(0xFF07020F), sidebar: Color(0xFF0E0420), chat: Color(0xFF14082B),
      input: Color(0xFF1E0D3D), hover: Color(0xFF2A1352), accent: Color(0xFFFF2BD6), text: Color(0xFFF2E9FF), muted: Color(0xFF9F8CC7),
      divider: Color(0xFF2B1650), online: Color(0xFF00F0FF), idle: Color(0xFFFFE600), dnd: Color(0xFFFF3860)),
  PulseTheme(id: 'sunset', name: '晚霞', brightness: _d, rail: Color(0xFF1F0E14), sidebar: Color(0xFF2B131C), chat: Color(0xFF351923),
      input: Color(0xFF45212E), hover: Color(0xFF552A39), accent: Color(0xFFFF8A4C), text: Color(0xFFFCE8DF), muted: Color(0xFFC59A92),
      divider: Color(0xFF4A2632)),
  PulseTheme(id: 'mint', name: '薄荷', brightness: _l, rail: Color(0xFFD5EFE6), sidebar: Color(0xFFE6F7F1), chat: Color(0xFFF6FFFB),
      input: Color(0xFFDDF2EA), hover: Color(0xFFCBEADF), accent: Color(0xFF14A37F), text: Color(0xFF1D3B33), muted: Color(0xFF5B7C73),
      divider: Color(0xFFD3EBE2)),
  PulseTheme(id: 'gruvbox', name: '复古暖色', brightness: _d, rail: Color(0xFF1D2021), sidebar: Color(0xFF282828), chat: Color(0xFF32302F),
      input: Color(0xFF3C3836), hover: Color(0xFF504945), accent: Color(0xFFFE8019), text: Color(0xFFEBDBB2), muted: Color(0xFFA89984),
      divider: Color(0xFF45403D), online: Color(0xFFB8BB26), idle: Color(0xFFFABD2F), dnd: Color(0xFFFB4934)),
  PulseTheme(id: 'contrast', name: '高对比度', brightness: _d, rail: Color(0xFF000000), sidebar: Color(0xFF000000), chat: Color(0xFF000000),
      input: Color(0xFF1A1A1A), hover: Color(0xFF333333), accent: Color(0xFFFFD400), text: Color(0xFFFFFFFF), muted: Color(0xFFCCCCCC),
      divider: Color(0xFFFFFFFF), online: Color(0xFF00FF66), idle: Color(0xFFFFD400), dnd: Color(0xFFFF4040)),
];

/// Set by the host launcher (CML): when non-null it replaces the chosen theme and the picker is hidden.
PulseTheme? hostTheme;

PulseTheme themeById(String id) => hostTheme ?? pulseThemes.firstWhere((t) => t.id == id, orElse: () => pulseThemes.first);

/// Accent presets offered in settings (0 = theme default).
const List<int> accentPresets = [0, 0xFF5865F2, 0xFF3BA55C, 0xFFED4245, 0xFFFAA61A, 0xFFEB459E, 0xFF00A8FC, 0xFF9B59B6, 0xFF1ABC9C, 0xFFE67E22];

/// Palette for default avatars (user.avatar index).
const List<Color> avatarColors = [
  Color(0xFF5865F2), Color(0xFF3BA55C), Color(0xFFED4245), Color(0xFFFAA61A), Color(0xFFEB459E), Color(0xFF00A8FC),
  Color(0xFF9B59B6), Color(0xFF1ABC9C), Color(0xFFE67E22), Color(0xFF747F8D), Color(0xFF2ECC71), Color(0xFFE91E63),
  Color(0xFF3498DB), Color(0xFFF1C40F), Color(0xFF8E44AD), Color(0xFF16A085),
];

extension WithAccent on PulseTheme {
  /// Same theme with the accent overridden by the user's choice.
  PulseTheme withAccent(int argb) => argb == 0
      ? this
      : PulseTheme(
          id: id, name: name, brightness: brightness, rail: rail, sidebar: sidebar, chat: chat, input: input, hover: hover,
          accent: Color(argb), text: text, muted: muted, divider: divider, online: online, idle: idle, dnd: dnd, danger: danger);
}
