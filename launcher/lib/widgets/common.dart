import 'package:flutter/material.dart';

import '../theme.dart';

/// Page section card with a title and optional trailing actions.
class Section extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets padding;
  const Section({super.key, required this.title, required this.child, this.icon, this.subtitle, this.actions = const [], this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (icon != null) ...[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, size: 18, color: t.colorScheme.primary),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(width: 4, height: 18, decoration: BoxDecoration(gradient: CmlColors.of(context).hero, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null) Text(subtitle!, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor)),
                ]),
              ),
              ...actions,
            ]),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Label + control row used on settings pages.
class FieldRow extends StatelessWidget {
  final String label;
  final String? help;
  final Widget child;
  const FieldRow(this.label, this.child, {super.key, this.help});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 180,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            if (help != null) Text(help!, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor, fontSize: 11), maxLines: 2),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ]),
    );
  }
}

class SwitchRow extends StatelessWidget {
  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow(this.label, this.value, this.onChanged, {super.key, this.help});

  @override
  Widget build(BuildContext context) => FieldRow(label, Align(alignment: Alignment.centerLeft, child: Switch(value: value, onChanged: onChanged)), help: help);
}

/// Empty / placeholder state.
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyHint(this.icon, this.text, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: t.colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: t.colorScheme.primary.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.hintColor, height: 1.6)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}

/// Small coloured label.
class Pill extends StatelessWidget {
  final String text;
  final Color? color;
  const Pill(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
    );
  }
}

/// Scrollable page body with consistent padding.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 18),
        itemBuilder: (_, i) => children[i],
      );
}

/// Small metric tile (icon, value, label).
class StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  final double? progress;
  const StatTile({super.key, required this.icon, required this.value, required this.label, this.color, this.progress});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = color ?? t.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: c, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label, style: t.textTheme.bodySmall?.copyWith(color: t.hintColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress, minHeight: 4, borderRadius: BorderRadius.circular(2), color: c),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
