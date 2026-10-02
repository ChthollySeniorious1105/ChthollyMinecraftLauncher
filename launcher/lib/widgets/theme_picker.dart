import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme.dart';

/// Grouped theme gallery: each tile previews the theme's page, card and gradient colours.
class ThemePicker extends StatelessWidget {
  final String selected;
  final bool dark;
  final ValueChanged<String> onSelected;
  const ThemePicker({super.key, required this.selected, required this.dark, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final groups = cmlThemeGroups;
    final all = cmlThemes;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(g.value, style: t.textTheme.labelMedium?.copyWith(color: t.hintColor, fontWeight: FontWeight.w600)),
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final th in all.where((x) => x.group == g.key)) _ThemeTile(th, dark: dark, selected: th.id == selected, onTap: () => onSelected(th.id)),
        ]),
      ],
    ]);
  }
}

class _ThemeTile extends StatelessWidget {
  final CmlTheme theme;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeTile(this.theme, {required this.dark, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = resolvePalette(theme, darkSetting: dark);
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: theme.fixed == null ? trGlobal('跟随深浅色切换') : (theme.fixed == Brightness.dark ? trGlobal('固定深色') : trGlobal('固定浅色')),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 104,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5), width: selected ? 2 : 1),
          ),
          child: Column(children: [
            Container(
              height: 46,
              decoration: BoxDecoration(color: pal.bg, borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(6),
              child: Row(children: [
                Container(width: 14, decoration: BoxDecoration(color: pal.panel, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [pal.accent, pal.accent2]), borderRadius: BorderRadius.circular(3)),
                    ),
                    const SizedBox(height: 4),
                    Expanded(child: Container(decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(3)))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) Icon(Icons.check_circle, size: 13, color: cs.primary),
              if (selected) const SizedBox(width: 3),
              Flexible(child: Text(theme.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
            ]),
          ]),
        ),
      ),
    );
  }
}
