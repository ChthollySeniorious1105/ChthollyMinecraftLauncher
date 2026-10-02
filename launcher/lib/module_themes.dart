import 'package:aurora_client/embed.dart';
import 'package:flutter/material.dart';
import 'package:pulse_client/embed.dart';

import 'theme.dart';

/// Maps the active CML palette onto the embedded modules' own theme types, so Aurora and Pulse
/// look like part of CML (their built-in theme pickers are hidden while hosted).
abstract class ModuleThemes {
  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  static AuroraTheme aurora(CmlPalette p) => AuroraTheme(
        'cml-${p.id}',
        p.name,
        p.brightness,
        p.accent,
        p.accent2,
        [p.bg, _mix(p.bg, p.accent, p.dark ? 0.10 : 0.07), _mix(p.bg, p.accent2, p.dark ? 0.12 : 0.09)],
        p.surface,
        // game table felt: a calm, slightly darkened accent so cards / tiles stay readable
        _mix(_mix(p.accent, const Color(0xFF1F4E5A), 0.55), Colors.black, p.dark ? 0.25 : 0.05),
      );

  static PulseTheme pulse(CmlPalette p) => PulseTheme(
        id: 'cml-${p.id}',
        name: p.name,
        brightness: p.brightness,
        rail: p.dark ? _mix(p.bg, Colors.black, 0.35) : _mix(p.bg, Colors.black, 0.07),
        sidebar: p.dark ? _mix(p.bg, Colors.black, 0.15) : _mix(p.bg, Colors.black, 0.03),
        chat: p.dark ? p.bg : p.surface,
        input: p.field,
        hover: _mix(p.dark ? p.bg : p.surface, p.accent, p.dark ? 0.14 : 0.08),
        accent: p.accent,
        text: p.text,
        muted: p.muted,
        divider: p.line,
      );
}
