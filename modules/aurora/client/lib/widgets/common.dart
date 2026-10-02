import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/themes.dart';

/// Player avatar from assets/avatars/animal-NNN.png. id 0 = system/bot icon.
class Avatar extends StatelessWidget {
  final int id;
  final double size;
  final bool speaking;
  final bool bot;
  final bool dim;
  const Avatar(this.id, {super.key, this.size = 40, this.speaking = false, this.bot = false, this.dim = false});

  static String path(int id) => '${assetPrefix}assets/avatars/animal-${id.toString().padLeft(3, '0')}.png';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget img;
    if (id >= 1 && id <= 500) {
      img = Image.asset(path(id), width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium);
    } else {
      img = Container(
        width: size,
        height: size,
        color: cs.primaryContainer,
        child: Icon(bot ? Icons.smart_toy : Icons.campaign, size: size * 0.6, color: cs.onPrimaryContainer),
      );
    }
    if (dim) img = Opacity(opacity: 0.45, child: img);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: speaking ? Colors.greenAccent : cs.secondary.withValues(alpha: 0.6),
          width: speaking ? 3 : 1.5,
        ),
        boxShadow: speaking ? [const BoxShadow(color: Colors.greenAccent, blurRadius: 8)] : null,
      ),
      child: ClipOval(child: img),
    );
  }
}

/// Compact player tag used by game boards: avatar + name + optional extra line.
class PlayerTag extends StatelessWidget {
  final String name;
  final int avatar;
  final bool active;
  final bool bot;
  final String? sub;
  final double size;
  final Widget? trailing;
  const PlayerTag({super.key, required this.name, required this.avatar, this.active = false, this.bot = false, this.sub, this.size = 36, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // In very narrow slots, scale the whole tag down instead of overflowing.
    return LayoutBuilder(builder: (context, c) {
      final tag = _tag(cs);
      if (!c.maxWidth.isFinite || c.maxWidth >= size * 4) return tag;
      return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: tag);
    });
  }

  Widget _tag(ColorScheme cs) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (active ? cs.primary : cs.surface).withValues(alpha: active ? 0.35 : 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: active ? cs.primary : cs.outline.withValues(alpha: 0.3), width: active ? 2 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Avatar(avatar, size: size, bot: bot),
        const SizedBox(width: 6),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: size * 0.36)),
            if (sub != null)
              Text(sub!,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(fontSize: size * 0.3, color: cs.onSurface.withValues(alpha: 0.75))),
          ]),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ]),
    );
  }
}

/// Font fallback for text drawn by CustomPainters (they don't inherit the theme).
const List<String> kFontFallback = [
  'Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC', 'Segoe UI Symbol', 'Segoe UI Emoji',
  'Apple Color Emoji', 'Noto Color Emoji',
];

typedef BoardBuilder = Widget Function(GameContext g);

/// Everything a game board needs.
class GameContext {
  final AppState app;
  final GameState state;

  /// Rendering a recorded replay: [act] does nothing.
  final bool replay;

  /// Room options override (replays / single-player games have no room).
  final Map<String, dynamic>? optionsOverride;
  const GameContext(this.app, this.state, {this.replay = false, this.optionsOverride});

  Map<String, dynamic> get view => state.view;
  int get seat => state.seat;
  int get players => state.names.length;
  bool get spectator => state.seat < 0;
  bool get over => state.over;
  String name(int s) => s >= 0 && s < state.names.length ? state.names[s] : '?';
  int avatar(int s) => s >= 0 && s < state.avatars.length ? state.avatars[s] : 0;
  bool bot(int s) => s >= 0 && s < state.bots.length && state.bots[s];
  void act(Map<String, dynamic> a) {
    if (!replay) app.action(a);
  }
  /// Felt colour of the current theme, for board backgrounds.
  Color get table => themeById(app.themeId).table;
  Map<String, dynamic> get options =>
      optionsOverride ?? app.local?.options ?? (app.room?['options'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Seats ordered so that "me" is first (or seat 0 for spectators).
  List<int> seatsFromMe() {
    final base = seat < 0 ? 0 : seat;
    return [for (var i = 0; i < players; i++) (base + i) % players];
  }

  PlayerTag tag(int s, {bool active = false, String? sub, double size = 36, Widget? trailing}) =>
      PlayerTag(name: name(s), avatar: avatar(s), active: active, bot: bot(s), sub: sub, size: size, trailing: trailing);
}

/// A banner for the end-of-game result. Boards often float it over the
/// table, so it can be collapsed to a small pill (tap to expand again) to see
/// what's underneath.
class ResultBanner extends StatefulWidget {
  final String text;
  final Widget? child;
  const ResultBanner(this.text, {super.key, this.child});
  @override
  State<ResultBanner> createState() => _ResultBannerState();
}

class _ResultBannerState extends State<ResultBanner> {
  bool _collapsed = false;

  @override
  void didUpdateWidget(covariant ResultBanner old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _collapsed = false; // a new result: show it
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_collapsed) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: cs.surface.withValues(alpha: 0.92),
          shape: StadiumBorder(side: BorderSide(color: cs.primary, width: 1.5)),
          elevation: 3,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _collapsed = false),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.emoji_events, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.primary)),
                ),
                const SizedBox(width: 4),
                Icon(Icons.unfold_more, size: 16, color: cs.primary),
              ]),
            ),
          ),
        ),
      );
    }
    // The collapse button sits on the banner's top-right corner (in the
    // margin), so it takes no width from the content.
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 16, color: Colors.black38)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.text,
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.primary)),
          if (widget.child != null) ...[const SizedBox(height: 8), widget.child!],
        ]),
      ),
      Positioned(
        right: 0,
        top: 0,
        child: Tooltip(
          message: '收起，查看牌桌',
          child: Material(
            color: cs.primary,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _collapsed = true),
              child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.unfold_less, size: 16, color: cs.onPrimary)),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Status line at the top of a board ("轮到 xxx").
class StatusBar extends StatelessWidget {
  final String text;
  final bool highlight;
  const StatusBar(this.text, {super.key, this.highlight = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: (highlight ? cs.primary : cs.surface).withValues(alpha: highlight ? 0.85 : 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, color: highlight ? cs.onPrimary : cs.onSurface)),
    );
  }
}
