import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'common.dart';

/// Shared 雀魂-style mahjong table kit used by every mahjong board.
///
/// * [MjTableBackground]  green felt with vignette + subtle cloth texture.
/// * [MjHand]             my hand: hover lift, 单击 or 双击 (select, then tap
///                        again) discard per [MjAutoState.doubleTap], swipe up
///                        to discard, drawn tile slides in.
/// * [MjDiscardFly]       the newest river tile flies in from its owner's hand.
/// * [MjActionBar]        big round 雀魂 buttons (吃/碰/杠/立直/和/自摸/跳过)
///                        that pop in with a bounce; 和/自摸 glow.
/// * [MjCallBanner]       full-width "碰!" "立直!" "自摸!" flash when anyone acts.
/// * [MjTurnGlow]         pulsing ring around the active player's name plate.
/// * [MjCenterPanel]      dark rounded square showing round, wall count, seat
///                        winds with the active seat's wind lit and a countdown.
/// Boards keep their own layout and data; they only compose these pieces.

// --------------------------------------------------------------- colours
class MjColors {
  static const win = Color(0xFFE53935);
  static const winGlow = Color(0xFFFFC107);
  static const call = Color(0xFF1E88E5);
  static const riichi = Color(0xFFFFB300);
  static const kan = Color(0xFF8E24AA);
  static const skip = Color(0xFF455A64);
  static const felt = Color(0xFF1C5E4A);
}

// --------------------------------------------------------------- background
class MjTableBackground extends StatelessWidget {
  final Color felt;
  final Widget child;
  const MjTableBackground({super.key, required this.felt, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.1),
          radius: 1.05,
          colors: [
            Color.lerp(felt, Colors.white, 0.10)!,
            felt,
            Color.lerp(felt, Colors.black, 0.45)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: CustomPaint(painter: _ClothPainter(felt), child: child),
    );
  }
}

class _ClothPainter extends CustomPainter {
  final Color felt;
  _ClothPainter(this.felt);
  @override
  void paint(Canvas canvas, Size size) {
    // faint diagonal weave
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), p);
    }
    // wooden rim
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..shader = const LinearGradient(colors: [Color(0xFF3E2723), Color(0xFF6D4C41), Color(0xFF3E2723)])
          .createShader(Offset.zero & size);
    canvas.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(3), const Radius.circular(10)), rim);
  }

  @override
  bool shouldRepaint(covariant _ClothPainter old) => old.felt != felt;
}

// --------------------------------------------------------------- my hand
/// One tile in my hand. [tile] renders the face at a given width.
class MjHandTile {
  final Object id; // stable identity (tile id or code+index)
  final Widget Function(double width, {bool dim}) tile;
  final bool enabled; // may be discarded / selected now
  final bool drawn; // freshly drawn tile (placed apart, slides in)
  final bool marked; // e.g. riichi-able / 换三张 selection highlight
  const MjHandTile({
    required this.id,
    required this.tile,
    this.enabled = true,
    this.drawn = false,
    this.marked = false,
  });
}

/// 雀魂-style hand:
///  * 单击 mode: one click / tap discards immediately.
///  * 双击 mode: first click selects (lifts the tile), clicking the same tile
///    again discards; clicking another tile moves the selection.
///  * swipe up on a tile always discards; hovering lifts a tile slightly.
///  * the discarded tile is hidden at once (before the server replies) so
///    the hand never lags behind the table.
///  * the drawn tile sits apart and slides in from the right.
///
/// Taps are handled on pointer-up without a double-tap recognizer, so there
/// is no ~300 ms tap delay in either mode.
class MjHand extends StatefulWidget {
  final List<MjHandTile> tiles;
  final double tileWidth;
  final bool active; // my turn to discard
  final void Function(Object id) onDiscard;

  /// Selection-only mode (换三张 / 选缺 etc.): tap toggles [onToggle].
  final void Function(Object id)? onToggle;
  final Set<Object> selectedIds;

  /// Optional trailing widgets (melds, flowers) drawn after the tiles.
  final List<Widget> trailing;

  /// Called whenever the pre-selected tile changes (for 听牌 hints).
  final void Function(Object? id)? onSelect;
  const MjHand({
    super.key,
    required this.tiles,
    required this.tileWidth,
    required this.active,
    required this.onDiscard,
    this.onToggle,
    this.selectedIds = const {},
    this.trailing = const [],
    this.onSelect,
  });

  @override
  State<MjHand> createState() => _MjHandState();
}

class _MjHandState extends State<MjHand> {
  Object? _sel;
  Object? _hover;
  String _key = '';

  /// Tile just sent to the server: hidden until the next view arrives.
  Object? _thrown;
  Timer? _thrownTimer;

  /// Tile + position of the current pointer-down.
  (Object, Offset)? _down;

  /// Coordinate space for [_Glide] (the unscaled hand row).
  final _rowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    MjAutoState.doubleTap.addListener(_onMode);
  }

  @override
  void dispose() {
    MjAutoState.doubleTap.removeListener(_onMode);
    _thrownTimer?.cancel();
    super.dispose();
  }

  void _onMode() {
    if (mounted) setState(() => _sel = null);
  }

  void _setSel(Object? id) {
    if (_sel == id) return;
    setState(() => _sel = id);
    widget.onSelect?.call(id);
    if (id != null) HapticFeedback.selectionClick();
  }

  void _tap(MjHandTile t) {
    if (widget.onToggle != null) {
      widget.onToggle!(t.id);
      HapticFeedback.selectionClick();
      return;
    }
    if (!widget.active || !t.enabled || _thrown != null) return;
    if (!MjAutoState.doubleTap.value || _sel == t.id) {
      _discard(t);
    } else {
      _setSel(t.id);
    }
  }

  void _discard(MjHandTile t) {
    if (!widget.active || !t.enabled || _thrown != null) return;
    HapticFeedback.lightImpact();
    widget.onDiscard(t.id);
    _setSel(null);
    setState(() => _thrown = t.id);
    // If the server rejects the discard the view won't change: show it again.
    _thrownTimer?.cancel();
    _thrownTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _thrown = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    // reset selection when the hand changes
    final key = '${widget.active}|${widget.tiles.map((t) => t.id).join(',')}';
    if (key != _key) {
      _key = key;
      _sel = null;
      _thrown = null;
      _thrownTimer?.cancel();
    }
    final tw = widget.tileWidth;
    final th = tw * 4 / 3;
    final items = <Widget>[];
    for (final t in widget.tiles) {
      if (t.id == _thrown) continue;
      final selected = _sel == t.id || widget.selectedIds.contains(t.id);
      final hovered = _hover == t.id && widget.active && t.enabled && _thrown == null;
      final lift = selected ? tw * 0.42 : (hovered ? tw * 0.14 : 0.0);
      final dim = widget.onToggle == null && widget.active && !t.enabled;
      Widget face = t.tile(tw, dim: dim);
      if (t.marked) {
        face = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tw * 0.1),
            boxShadow: [BoxShadow(color: MjColors.riichi.withValues(alpha: 0.9), blurRadius: tw * 0.3)],
          ),
          child: face,
        );
      }
      if (selected) {
        face = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tw * 0.1),
            boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: tw * 0.35)],
          ),
          child: face,
        );
      }
      Widget w = AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, -lift, 0),
        child: face,
      );
      w = MouseRegion(
        cursor: (widget.active && t.enabled) || widget.onToggle != null ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = t.id),
        onExit: (_) => setState(() => _hover = _hover == t.id ? null : _hover),
        // Raw pointer handling instead of GestureDetector: no double-tap
        // delay, and a slightly shaky mouse click is never eaten by a drag.
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down = (t.id, e.position),
          onPointerCancel: (_) => _down = null,
          onPointerUp: (e) {
            final d = _down;
            _down = null;
            if (d == null || d.$1 != t.id) return;
            final delta = e.position - d.$2;
            if (widget.onToggle == null && delta.dy < -tw * 0.6 && delta.dy.abs() > delta.dx.abs()) {
              _discard(t); // swipe up to throw (雀魂 mobile gesture)
            } else if (delta.distance < tw * 0.5) {
              _tap(t);
            }
          },
          child: w,
        ),
      );
      if (t.drawn) {
        w = Padding(
          padding: EdgeInsets.only(left: tw * 0.4),
          child: _SlideIn(key: ValueKey('drawn-${t.id}'), dy: tw * 0.9, child: w),
        );
      }
      // _Glide keeps its state while the tile id stays the same, so a tile
      // slides to its new place when the hand is re-sorted or shrinks.
      items.add(_Glide(key: ValueKey(t.id), space: _rowKey, child: w));
    }
    // Reserve the drawn-tile slot (and the thrown tile's space) so the hand
    // keeps the same width/scale while drawing and discarding.
    final hasDrawn = widget.tiles.any((t) => t.drawn && t.id != _thrown);
    if (!hasDrawn && widget.onToggle == null) items.add(SizedBox(width: tw * 1.4));
    if (_thrown != null && !widget.tiles.any((t) => t.drawn && t.id == _thrown)) items.add(SizedBox(width: tw));
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: EdgeInsets.only(top: tw * 0.45),
        child: SizedBox(
          key: _rowKey,
          height: th + tw * 0.05,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            ...items,
            ...widget.trailing,
          ]),
        ),
      ),
    );
  }
}

class _SlideIn extends StatefulWidget {
  final Widget child;
  final double dy;
  const _SlideIn({super.key, required this.child, required this.dy});
  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        final t = Curves.easeOutBack.transform(v);
        return Opacity(
          opacity: (v * 2.5).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, -widget.dy * (1 - t)), child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// FLIP animation for one hand tile: after every layout it compares its
/// position (in [space]) with the previous one and glides from the old spot.
class _Glide extends StatefulWidget {
  final Widget child;
  final GlobalKey space;
  const _Glide({super.key, required this.child, required this.space});
  @override
  State<_Glide> createState() => _GlideState();
}

class _GlideState extends State<_Glide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))
    ..value = 1
    ..addListener(() => setState(() {}));
  Offset? _last;
  Offset _from = Offset.zero;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final space = widget.space.currentContext?.findRenderObject();
    if (box == null || space == null || !box.attached || !box.hasSize) return;
    final pos = box.localToGlobal(Offset.zero, ancestor: space);
    final last = _last;
    _last = pos;
    if (last == null || (last - pos).distance < 0.5) return;
    // continue from wherever the tile is currently drawn
    _from = last - pos + _offset;
    _c.forward(from: 0);
  }

  Offset get _offset => _from * (1 - Curves.easeOutCubic.transform(_c.value));

  @override
  Widget build(BuildContext context) {
    if (!_c.isAnimating) WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Transform.translate(offset: _offset, child: widget.child);
  }
}

// --------------------------------------------------------------- discard fly-in
/// Wraps the newest river tile: it is thrown from the owner side (river
/// boxes are rotated per seat, so +y points at the owner) along a short
/// arc, lands with a small bounce and a table shadow. Give it a key that
/// changes per discard.
class MjDiscardFly extends StatefulWidget {
  final Widget child;
  final bool highlight;
  const MjDiscardFly({super.key, required this.child, this.highlight = true});
  @override
  State<MjDiscardFly> createState() => _MjDiscardFlyState();
}

class _MjDiscardFlyState extends State<MjDiscardFly> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        // flight 0..0.7, landing squash 0.7..1
        final f = Curves.easeOutCubic.transform((v / 0.7).clamp(0.0, 1.0));
        final travel = (1 - f) * 90;
        final arc = sin(f * pi) * 10; // rises a little mid-flight
        final land = v < 0.7 ? 1.0 : 1 + sin((v - 0.7) / 0.3 * pi) * 0.07;
        final scale = (0.82 + 0.18 * f) * land;
        return Opacity(
          opacity: (v * 4).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, travel - arc),
            child: Transform.rotate(
              angle: (1 - f) * 0.12,
              child: Transform.scale(
                scale: scale,
                child: DecoratedBox(
                  decoration: BoxDecoration(boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35 * (1 - f)),
                      blurRadius: 10 * (1 - f) + 1,
                      offset: Offset(0, 8 * (1 - f)),
                    ),
                  ]),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: widget.highlight
          ? DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: MjColors.winGlow.withValues(alpha: 0.75), blurRadius: 8, spreadRadius: 1)],
              ),
              child: widget.child,
            )
          : widget.child,
    );
  }
}

// --------------------------------------------------------------- meld slide-in
/// A called meld (吃/碰/杠) slides in from the right and settles with a small
/// pop, like 雀魂. Key it by seat + meld index so only new melds animate.
class MjMeldIn extends StatefulWidget {
  final Widget child;
  const MjMeldIn({super.key, required this.child});
  @override
  State<MjMeldIn> createState() => _MjMeldInState();
}

class _MjMeldInState extends State<MjMeldIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final v = _c.value;
          final t = Curves.easeOutBack.transform(v);
          return Opacity(
            opacity: (v * 3).clamp(0.0, 1.0),
            child: FractionalTranslation(
              translation: Offset((1 - Curves.easeOutCubic.transform(v)) * 0.6, 0),
              child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
            ),
          );
        },
        child: widget.child,
      );
}

/// Wraps meld widgets of one seat with [MjMeldIn].
List<Widget> mjMelds(Object seat, List<Widget> melds, {double gap = 0}) => [
      for (var i = 0; i < melds.length; i++) ...[
        if (gap > 0) SizedBox(width: gap),
        MjMeldIn(key: ValueKey('meld-$seat-$i'), child: melds[i]),
      ],
    ];

// --------------------------------------------------------------- 摸切 marker
/// River tile that was discarded straight after being drawn (摸切): drawn
/// greyed like 雀魂 with a tiny "摸" corner tag, so 手切 tiles stand out.
class MjGiri extends StatelessWidget {
  final Widget child;
  final double width;
  const MjGiri({super.key, required this.child, required this.width});

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF455A64).withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(width * 0.1),
              ),
            ),
          ),
        ),
        if (width >= 14)
          Positioned(
            left: width * 0.04,
            bottom: width * 0.04,
            child: IgnorePointer(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(width * 0.08)),
                child: Text('摸',
                    style: TextStyle(
                        fontFamilyFallback: kFontFallback, fontSize: width * 0.26, height: 1.15, color: Colors.white70)),
              ),
            ),
          ),
      ]);
}

/// Wraps [t] in [MjGiri] when the river entry says it was 摸切.
Widget mjGiri(Widget t, Map d, double width) => d['tg'] == true ? MjGiri(width: width, child: t) : t;

// --------------------------------------------------------------- action bar
class MjAction {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? preview; // tiles shown on the button (chi options etc.)
  final bool primary; // 和/自摸: glowing + bigger
  const MjAction(this.label, this.color, this.onTap, {this.preview, this.primary = false});

  static MjAction win(String label, VoidCallback f) => MjAction(label, MjColors.win, f, primary: true);
  static MjAction call(String label, VoidCallback f, {Widget? preview}) =>
      MjAction(label, MjColors.call, f, preview: preview);
  static MjAction kan(String label, VoidCallback f, {Widget? preview}) =>
      MjAction(label, MjColors.kan, f, preview: preview);
  static MjAction riichi(String label, VoidCallback f) => MjAction(label, MjColors.riichi, f);
  static MjAction skip(VoidCallback f, [String label = '跳过']) => MjAction(label, MjColors.skip, f);
}

/// Row of big round buttons floating above the hand (right-aligned like 雀魂),
/// popping in with a staggered bounce.
class MjActionBar extends StatelessWidget {
  final List<MjAction> actions;
  final double scale;
  const MjActionBar({super.key, required this.actions, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    final sig = actions.map((a) => a.label).join('|');
    return Wrap(
      key: ValueKey(sig),
      alignment: WrapAlignment.end,
      spacing: 10 * scale,
      runSpacing: 8 * scale,
      children: [
        for (var i = 0; i < actions.length; i++) _PopIn(delayMs: i * 55, child: _MjButton(actions[i], scale)),
      ],
    );
  }
}

class _MjButton extends StatefulWidget {
  final MjAction a;
  final double scale;
  const _MjButton(this.a, this.scale);
  @override
  State<_MjButton> createState() => _MjButtonState();
}

class _MjButtonState extends State<_MjButton> with SingleTickerProviderStateMixin {
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _down = false;

  @override
  void initState() {
    super.initState();
    if (widget.a.primary) _glow.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final s = widget.scale * (a.primary ? 1.18 : 1.0);
    final base = a.color;
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) => AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(40 * s),
            boxShadow: [
              BoxShadow(color: Colors.black54, blurRadius: 6 * s, offset: Offset(0, 3 * s)),
              if (a.primary)
                BoxShadow(
                  color: MjColors.winGlow.withValues(alpha: 0.35 + 0.45 * _glow.value),
                  blurRadius: (10 + 14 * _glow.value) * s,
                  spreadRadius: 2 * s,
                ),
            ],
          ),
          child: child,
        ),
      ),
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(40 * s),
            onTap: () {
              HapticFeedback.mediumImpact();
              a.onTap();
            },
            child: Ink(
              padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: 9 * s),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(40 * s),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(base, Colors.white, 0.28)!, base, Color.lerp(base, Colors.black, 0.3)!],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2 * s),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (a.preview != null) ...[a.preview!, SizedBox(width: 6 * s)],
                Text(a.label,
                    style: TextStyle(
                      fontFamilyFallback: kFontFallback,
                      color: Colors.white,
                      fontSize: 19 * s,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: const [Shadow(blurRadius: 3, color: Colors.black87, offset: Offset(0, 1))],
                    )),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _PopIn({required this.child, this.delayMs = 0});
  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: Curves.easeOutBack.transform(_c.value).clamp(0.0, 1.3), child: child),
        ),
        child: widget.child,
      );
}

// --------------------------------------------------------------- call banner
/// Big flashing call text ("碰", "立直", "自摸", "荣和") shown over a seat when
/// anyone makes a call. Feed it the latest event; it animates when [eventKey]
/// changes.
class MjCallBanner extends StatefulWidget {
  final String? text;
  final Object? eventKey;
  final Alignment alignment;
  const MjCallBanner({super.key, required this.text, required this.eventKey, this.alignment = Alignment.center});
  @override
  State<MjCallBanner> createState() => _MjCallBannerState();
}

class _MjCallBannerState extends State<MjCallBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  Object? _last;

  @override
  void didUpdateWidget(covariant MjCallBanner old) {
    super.didUpdateWidget(old);
    _maybePlay();
  }

  @override
  void initState() {
    super.initState();
    _last = widget.eventKey; // don't replay on first build (e.g. reconnect)
  }

  void _maybePlay() {
    if (widget.text != null && widget.eventKey != _last) {
      _last = widget.eventKey;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static Color colorFor(String t) {
    if (t.contains('和') || t.contains('胡') || t.contains('自摸') || t.contains('荣')) return MjColors.win;
    if (t.contains('立直')) return MjColors.riichi;
    if (t.contains('杠')) return MjColors.kan;
    return MjColors.call;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          if (!_c.isAnimating || widget.text == null) return const SizedBox.shrink();
          // 雀魂-style: slam in (0-0.18), hold with a light sweep, slide/fade out (0.8-1)
          final v = _c.value;
          final slam = Curves.easeOutCubic.transform((v / 0.18).clamp(0.0, 1.0));
          final settle = v < 0.18 ? 0.0 : sin(((v - 0.18) / 0.14).clamp(0.0, 1.0) * pi) * 0.06;
          final out = Curves.easeInCubic.transform(((v - 0.8) / 0.2).clamp(0.0, 1.0));
          final sweep = ((v - 0.2) / 0.45).clamp(0.0, 1.0);
          final col = colorFor(widget.text!);
          final text = Text(
            widget.text!,
            style: TextStyle(
              fontFamilyFallback: kFontFallback,
              fontSize: 56,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              color: Colors.white,
              letterSpacing: 4,
              shadows: [
                Shadow(color: col, blurRadius: 18),
                Shadow(color: col, blurRadius: 4),
                const Shadow(color: Colors.black, blurRadius: 2, offset: Offset(2, 3)),
              ],
            ),
          );
          return Align(
            alignment: widget.alignment,
            child: Opacity(
              opacity: (slam * (1 - out)).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(out * 60, 0),
                child: Transform.scale(
                  scale: 2.2 - 1.2 * slam - settle,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: Stack(alignment: Alignment.center, children: [
                      // colour band behind the text
                      Container(
                        width: 240,
                        height: 76,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(40),
                          gradient: LinearGradient(colors: [
                            col.withValues(alpha: 0.0),
                            col.withValues(alpha: 0.8),
                            col.withValues(alpha: 0.8),
                            col.withValues(alpha: 0.0),
                          ], stops: const [0, 0.25, 0.75, 1]),
                        ),
                      ),
                      text,
                      // light sweep across the text
                      if (sweep > 0 && sweep < 1)
                        ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment(-1 + 3 * sweep - 0.4, -0.3),
                            end: Alignment(-1 + 3 * sweep + 0.4, 0.3),
                            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0)],
                          ).createShader(r),
                          child: text,
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// --------------------------------------------------------------- turn glow
/// Pulsing golden ring around a seat plate while that seat is acting.
class MjTurnGlow extends StatefulWidget {
  final bool active;
  final Widget child;
  final double radius;
  const MjTurnGlow({super.key, required this.active, required this.child, this.radius = 24});
  @override
  State<MjTurnGlow> createState() => _MjTurnGlowState();
}

class _MjTurnGlowState extends State<MjTurnGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant MjTurnGlow old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          boxShadow: [
            BoxShadow(
                color: MjColors.winGlow.withValues(alpha: 0.35 + 0.4 * _c.value), blurRadius: 8 + 10 * _c.value, spreadRadius: 1),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

// --------------------------------------------------------------- center panel
/// 雀魂 centre: dark rounded square, round name in the middle, remaining tiles,
/// the four seat winds on the edges facing each player with the active one lit
/// and a thin progress bar under it.
class MjCenterPanel extends StatelessWidget {
  final double size;
  final String title; // 东1局
  final String? subtitle; // 0本场 · 供托 1
  final int wall; // tiles left
  /// Per relative position (0=me/bottom,1=right,2=top,3=left): wind label, score, is dealer.
  final List<({String wind, String score, bool dealer, bool active, bool present})> edges;
  final Widget? extra; // dora indicators etc.
  const MjCenterPanel({
    super.key,
    required this.size,
    required this.title,
    required this.wall,
    required this.edges,
    this.subtitle,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final s = size;
    Widget edge(int rel) {
      if (rel >= edges.length || !edges[rel].present) return const SizedBox.shrink();
      final e = edges[rel];
      final label = Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(horizontal: s * 0.025),
          decoration: BoxDecoration(
            color: e.active ? MjColors.winGlow : (e.dealer ? MjColors.win : Colors.white12),
            borderRadius: BorderRadius.circular(s * 0.02),
          ),
          child: Text(e.wind,
              style: TextStyle(
                  fontFamilyFallback: kFontFallback,
                  color: e.active ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: s * 0.085)),
        ),
        SizedBox(width: s * 0.025),
        Text(e.score,
            style: TextStyle(
                fontFamilyFallback: kFontFallback,
                color: e.active ? MjColors.winGlow : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: s * 0.075)),
      ]);
      final bar = AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: s * 0.016,
        width: e.active ? s * 0.5 : 0,
        margin: EdgeInsets.only(top: s * 0.01),
        decoration: BoxDecoration(color: MjColors.winGlow, borderRadius: BorderRadius.circular(s)),
      );
      final col = Column(mainAxisSize: MainAxisSize.min, children: [label, bar]);
      return RotatedBox(quarterTurns: const [0, 3, 2, 1][rel], child: col);
    }

    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1A17).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(s * 0.1),
        border: Border.all(color: const Color(0xFFB08D57).withValues(alpha: 0.7), width: 2),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Stack(children: [
        Align(alignment: const Alignment(0, 0.94), child: edge(0)),
        Align(alignment: const Alignment(0.94, 0), child: edge(1)),
        Align(alignment: const Alignment(0, -0.94), child: edge(2)),
        Align(alignment: const Alignment(-0.94, 0), child: edge(3)),
        Center(
          child: SizedBox(
            width: s * 0.62,
            height: s * 0.56,
            child: FittedBox(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    style: const TextStyle(
                        fontFamilyFallback: kFontFallback,
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: const TextStyle(fontFamilyFallback: kFontFallback, color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                _WallCounter(wall),
                if (extra != null) ...[const SizedBox(height: 4), extra!],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _WallCounter extends StatelessWidget {
  final int n;
  const _WallCounter(this.n);
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: n.toDouble()),
      duration: const Duration(milliseconds: 300),
      builder: (_, v, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.layers, size: 14, color: Colors.white54),
        const SizedBox(width: 3),
        Text('余 ${v.round()}',
            style: TextStyle(
                fontFamilyFallback: kFontFallback,
                color: n <= 10 ? const Color(0xFFFF8A65) : MjColors.winGlow,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

// --------------------------------------------------------------- score delta
/// "+8000" / "-3900" floating number that rises and fades (hand settlement).
class MjScoreDelta extends StatelessWidget {
  final int delta;
  final double fontSize;
  const MjScoreDelta(this.delta, {super.key, this.fontSize = 18});
  @override
  Widget build(BuildContext context) {
    if (delta == 0) return const SizedBox.shrink();
    final up = delta > 0;
    return TweenAnimationBuilder<double>(
      key: ValueKey(delta),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => Opacity(
        opacity: min(1, t * 3),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Text('${up ? '+' : ''}$delta',
              style: TextStyle(
                  fontFamilyFallback: kFontFallback,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w900,
                  color: up ? const Color(0xFF69F0AE) : const Color(0xFFFF5252),
                  shadows: const [Shadow(blurRadius: 3, color: Colors.black)])),
        ),
      ),
    );
  }
}

/// Result panel entrance: slides up + fades, children stagger in.
class MjResultEntrance extends StatelessWidget {
  final Widget child;
  const MjResultEntrance({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        builder: (_, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 40 * (1 - t)), child: Transform.scale(scale: 0.94 + 0.06 * t, child: c)),
        ),
        child: child,
      );
}

/// Label for a mahjong event type from engine 'last' maps (riichi / chinese).
String? mjEventLabel(Object? t) => switch (t) {
      'chi' => '吃',
      'pon' || 'peng' => '碰',
      'kan' || 'gang' || 'ankan' || 'kakan' || 'minkan' || 'bugang' || 'angang' || 'zhigang' => '杠',
      'riichi' => '立直',
      'tsumo' || 'zimo' => '自摸',
      'ron' => '荣和',
      'hu' || 'win' => '胡',
      'kita' => '拔北',
      'flower' || 'buhua' => '补花',
      _ => null,
    };

// --------------------------------------------------------------- auto toggles
/// 雀魂 left-side quick toggles. Shared across all mahjong boards for the
/// session: 自动和牌 (auto win), 不吃碰杠 (auto-skip calls), 自动摸切 (auto
/// discard the drawn tile, e.g. after riichi or while AFK).
class MjAutoState {
  static final autoWin = ValueNotifier<bool>(false);
  static final noCall = ValueNotifier<bool>(false);
  static final tsumogiri = ValueNotifier<bool>(false);

  /// Discard input: false = 单击出牌, true = 双击出牌 (select, then tap again).
  /// Persisted in SharedPreferences under [doubleTapKey].
  static final doubleTap = ValueNotifier<bool>(true);
  static const doubleTapKey = 'mjDoubleTap';

  static void setDoubleTap(bool v) {
    doubleTap.value = v;
    SharedPreferences.getInstance().then((p) => p.setBool(doubleTapKey, v));
  }

  static Future<void> load(SharedPreferences p) async {
    doubleTap.value = p.getBool(doubleTapKey) ?? true;
  }
}

/// Runs an auto-action at most once per [key] (e.g. phase|turn|tile), after a
/// short human-like delay so the table animation is still visible.
class MjAutoRunner {
  String _done = '';
  void run(String key, VoidCallback act, {int delayMs = 450}) {
    if (key == _done) return;
    _done = key;
    Future.delayed(Duration(milliseconds: delayMs), act);
  }
}

class MjAutoToggles extends StatefulWidget {
  const MjAutoToggles({super.key});
  @override
  State<MjAutoToggles> createState() => _MjAutoTogglesState();
}

class _MjAutoTogglesState extends State<MjAutoToggles> {
  static bool _open = false; // remembered for the session

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([MjAutoState.autoWin, MjAutoState.noCall, MjAutoState.tsumogiri]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final anyOn = MjAutoState.autoWin.value || MjAutoState.noCall.value || MjAutoState.tsumogiri.value;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Material(
        color: anyOn ? MjColors.riichi : Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(side: BorderSide(color: Colors.white30)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(_open ? Icons.chevron_left : Icons.smart_toy_outlined, size: 18, color: anyOn ? Colors.black : Colors.white70),
          ),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 180),
        child: _open
            ? Padding(padding: const EdgeInsets.only(top: 6), child: const _MjAutoToggleList())
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

class _MjAutoToggleList extends StatelessWidget {
  const _MjAutoToggleList();

  Widget _t(String label, IconData icon, ValueNotifier<bool> n) => ValueListenableBuilder<bool>(
        valueListenable: n,
        builder: (_, on, _) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: on ? MjColors.riichi.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.45),
            shape: StadiumBorder(side: BorderSide(color: on ? Colors.white : Colors.white30)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () {
                n.value = !on;
                HapticFeedback.selectionClick();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 14, color: on ? Colors.black : Colors.white70),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          fontFamilyFallback: kFontFallback,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: on ? Colors.black : Colors.white70)),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _t('自动和牌', Icons.emoji_events, MjAutoState.autoWin),
        _t('不吃碰杠', Icons.block, MjAutoState.noCall),
        _t('自动摸切', Icons.autorenew, MjAutoState.tsumogiri),
        const MjDiscardModeToggle(),
      ]);
}

/// 单击出牌 / 双击出牌 switch (also in 设置).
class MjDiscardModeToggle extends StatelessWidget {
  const MjDiscardModeToggle({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: MjAutoState.doubleTap,
        builder: (_, dbl, _) => Material(
          color: Colors.black.withValues(alpha: 0.45),
          shape: const StadiumBorder(side: BorderSide(color: Colors.white30)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () {
              MjAutoState.setDoubleTap(!dbl);
              HapticFeedback.selectionClick();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(dbl ? Icons.ads_click : Icons.touch_app, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Text(dbl ? '双击出牌' : '单击出牌',
                    style: const TextStyle(
                        fontFamilyFallback: kFontFallback, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              ]),
            ),
          ),
        ),
      );
}

/// Status-bar hint for the current discard mode.
String mjDiscardHint() => MjAutoState.doubleTap.value ? '点两次或上滑打出' : '单击或上滑打出';
