import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas.dart';
import 'widgets.dart';

enum DgMode { brush, eraser, fill }

/// Drawing tool state shared by the drawing boards: colour, brush width and
/// mode (brush / eraser / paint bucket).
class DgTool extends ChangeNotifier {
  int _color = kDgPalette.first;
  int _width = kDgWidths[1];
  DgMode _mode = DgMode.brush;

  /// Colours picked from the colour wheel, newest first (shared by all boards).
  static final List<int> recent = [];
  static const _maxRecent = 8;

  int get color => _color;
  int get width => _width;
  DgMode get mode => _mode;

  /// What the canvas should use.
  int get canvasColor => _mode == DgMode.eraser ? kCanvasBg : _color;
  int get canvasWidth => _mode == DgMode.eraser ? _width * 2 : _width;
  bool get fill => _mode == DgMode.fill;

  set color(int c) {
    _color = c;
    if (_mode == DgMode.eraser) _mode = DgMode.brush;
    notifyListeners();
  }

  set width(int w) {
    _width = w;
    if (_mode == DgMode.fill) _mode = DgMode.brush;
    notifyListeners();
  }

  set mode(DgMode m) {
    _mode = m;
    notifyListeners();
  }

  /// Toggles [m] on / back to the brush.
  void toggle(DgMode m) => mode = _mode == m ? DgMode.brush : m;

  void pickCustom(int c) {
    recent
      ..remove(c)
      ..insert(0, c);
    if (recent.length > _maxRecent) recent.removeLast();
    color = c;
  }

  /// Back to the brush (keeps colour and width), e.g. on a new round.
  void resetMode() {
    if (_mode == DgMode.brush) return;
    _mode = DgMode.brush;
    notifyListeners();
  }
}

/// Colours, widths, brush / eraser / fill, undo / redo / clear and the
/// Ctrl+Z / Ctrl+Y (Ctrl+Shift+Z) shortcuts while it is shown.
class DgToolbar extends StatefulWidget {
  final DgTool tool;
  final void Function(Map<String, dynamic> action) send;
  final int points;
  final int maxPoints;
  final bool canUndo;
  final bool canRedo;
  final WrapAlignment alignment;
  const DgToolbar({
    super.key,
    required this.tool,
    required this.send,
    required this.points,
    required this.maxPoints,
    this.canUndo = true,
    this.canRedo = true,
    this.alignment = WrapAlignment.center,
  });

  @override
  State<DgToolbar> createState() => _DgToolbarState();
}

class _DgToolbarState extends State<DgToolbar> {
  DgTool get tool => widget.tool;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    tool.addListener(_changed);
  }

  @override
  void didUpdateWidget(DgToolbar old) {
    super.didUpdateWidget(old);
    if (old.tool != tool) {
      old.tool.removeListener(_changed);
      tool.addListener(_changed);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    tool.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _undo() => widget.send({'type': 'undo'});
  void _redo() => widget.send({'type': 'redo'});

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    final kb = HardwareKeyboard.instance;
    if (!(kb.isControlPressed || kb.isMetaPressed) || kb.isAltPressed) return false;
    // leave text fields their own undo
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null && (focus.widget is EditableText || focus.findAncestorStateOfType<EditableTextState>() != null)) {
      return false;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyZ) {
      kb.isShiftPressed ? _redo() : _undo();
      return true;
    }
    if (k == LogicalKeyboardKey.keyY) {
      _redo();
      return true;
    }
    return false;
  }

  Future<void> _openWheel() async {
    final c = await showDialog<int>(useRootNavigator: false, context: context, builder: (_) => DgColorDialog(initial: tool.color));
    if (c != null) tool.pickCustom(c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paint = tool.mode != DgMode.eraser;

    Widget colorDot(int c, {double size = 24}) {
      final sel = paint && tool.color == c;
      return GestureDetector(
        onTap: () => tool.color = c,
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Color(c),
            shape: BoxShape.circle,
            border: Border.all(color: sel ? cs.primary : Colors.white70, width: sel ? 3 : 1.5),
            boxShadow: const [BoxShadow(blurRadius: 1, color: Colors.black26)],
          ),
        ),
      );
    }

    final custom = tool.color;
    final inPalette = kDgPalette.contains(custom);
    final wheel = Tooltip(
      message: '色盘：自选颜色',
      child: GestureDetector(
        onTap: _openWheel,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const SweepGradient(colors: _hueColors),
            border: Border.all(color: paint && !inPalette ? cs.primary : Colors.white70, width: paint && !inPalette ? 3 : 1.5),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: Color(custom), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
          ),
        ),
      ),
    );

    Widget widthBtn(int w) {
      final sel = tool.width == w && !tool.fill;
      return InkWell(
        onTap: () => tool.width = w,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? cs.primary.withValues(alpha: 0.25) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? cs.primary : cs.outline.withValues(alpha: 0.4)),
          ),
          child: Container(
              width: (w / 1.4).clamp(3, 22),
              height: (w / 1.4).clamp(3, 22),
              decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle)),
        ),
      );
    }

    Widget modeBtn(DgMode m, IconData icon, String tip) => IconButton(
          tooltip: tip,
          isSelected: tool.mode == m,
          visualDensity: VisualDensity.compact,
          icon: Icon(icon),
          onPressed: () => tool.toggle(m),
        );

    final recent = [for (final c in DgTool.recent) if (!kDgPalette.contains(c)) c];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: widget.alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Wrap(alignment: widget.alignment, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final c in kDgPalette) colorDot(c),
          for (final c in recent.take(4)) colorDot(c, size: 20),
          wheel,
        ]),
        Wrap(spacing: 4, children: [for (final w in kDgWidths) widthBtn(w)]),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          modeBtn(DgMode.brush, Icons.brush, '画笔'),
          modeBtn(DgMode.fill, Icons.format_color_fill, '填充'),
          modeBtn(DgMode.eraser, Icons.auto_fix_normal, '橡皮擦'),
          IconButton(
              tooltip: '撤销 (Ctrl+Z)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.undo),
              onPressed: widget.canUndo ? _undo : null),
          IconButton(
              tooltip: '重做 (Ctrl+Y)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.redo),
              onPressed: widget.canRedo ? _redo : null),
          IconButton(
              tooltip: '清空',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => widget.send({'type': 'clear'})),
          Text('${(widget.points * 100 / max(1, widget.maxPoints)).round()}%', style: TextStyle(fontSize: 11, color: cs.outline)),
        ]),
      ],
    );
  }
}

const _hueColors = [
  Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00), Color(0xFF00FFFF),
  Color(0xFF0000FF), Color(0xFFFF00FF), Color(0xFFFF0000),
];

/// HSV colour wheel (hue around, saturation outwards) + brightness slider.
class DgColorDialog extends StatefulWidget {
  final int initial;
  const DgColorDialog({super.key, required this.initial});
  @override
  State<DgColorDialog> createState() => _DgColorDialogState();
}

class _DgColorDialogState extends State<DgColorDialog> {
  late HSVColor _c = HSVColor.fromColor(Color(widget.initial));

  int get _argb => _c.toColor().toARGB32();

  void _pick(Offset p, double size) {
    final r = size / 2;
    final d = p - Offset(r, r);
    final hue = (atan2(d.dy, d.dx) * 180 / pi + 360) % 360;
    final sat = (d.distance / r).clamp(0.0, 1.0);
    setState(() => _c = _c.withHue(hue).withSaturation(sat));
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    final cs = Theme.of(context).colorScheme;
    final r = size / 2;
    final a = _c.hue * pi / 180;
    final marker = Offset(r + cos(a) * _c.saturation * r, r + sin(a) * _c.saturation * r);
    final presets = [...DgTool.recent, ...kDgPalette];
    return AlertDialog(
      title: const Text('色盘'),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: size + 40,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GestureDetector(
              onPanDown: (e) => _pick(e.localPosition, size),
              onPanUpdate: (e) => _pick(e.localPosition, size),
              child: SizedBox(
                width: size,
                height: size,
                child: CustomPaint(
                  painter: _WheelPainter(_c.value),
                  child: Stack(children: [
                    Positioned(
                      left: marker.dx - 9,
                      top: marker.dy - 9,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _c.toColor(),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black54)],
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.brightness_6, size: 18),
              Expanded(
                child: Slider(
                  value: _c.value,
                  onChanged: (v) => setState(() => _c = _c.withValue(v)),
                ),
              ),
            ]),
            Wrap(alignment: WrapAlignment.center, children: [
              for (final p in presets.toSet())
                GestureDetector(
                  onTap: () => setState(() => _c = HSVColor.fromColor(Color(p))),
                  child: Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Color(p),
                      shape: BoxShape.circle,
                      border: Border.all(color: p == _argb ? cs.primary : Colors.white70, width: p == _argb ? 3 : 1.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                width: 40,
                height: 28,
                decoration: BoxDecoration(
                  color: _c.toColor(),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.outline),
                ),
              ),
              const SizedBox(width: 10),
              SelectableText('#${(_argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                  style: const TextStyle(fontFamily: 'monospace')),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, _argb), child: const Text('使用此颜色')),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double value;
  _WheelPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()..shader = const SweepGradient(colors: _hueColors).createShader(rect));
    canvas.drawCircle(
        c, r, Paint()..shader = const RadialGradient(colors: [Colors.white, Color(0x00FFFFFF)]).createShader(rect));
    if (value < 1) canvas.drawCircle(c, r, Paint()..color = Colors.black.withValues(alpha: 1 - value));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black26);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.value != value;
}
