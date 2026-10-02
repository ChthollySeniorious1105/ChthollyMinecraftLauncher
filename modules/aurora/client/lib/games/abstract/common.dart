import 'dart:math';

import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// 响应式外壳：竖屏时玩家在上、棋盘居中、按钮在下；横屏时棋盘在左、侧栏在右。
class AbsShell extends StatelessWidget {
  final List<Widget> tags;
  final String status;
  final bool statusHighlight;
  final double aspect;
  final Widget board;
  final List<Widget> actions;
  final List<String> info;
  final String? result;
  final String? resultSub;

  const AbsShell({
    super.key,
    required this.tags,
    required this.status,
    this.statusHighlight = false,
    this.aspect = 1,
    required this.board,
    this.actions = const [],
    this.info = const [],
    this.result,
    this.resultSub,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.15;
      final boardBox = Center(child: AspectRatio(aspectRatio: aspect, child: board));
      final banner = result == null
          ? null
          : ResultBanner(result!, child: resultSub == null ? null : Text(resultSub!, textAlign: TextAlign.center));
      if (landscape) {
        final panelW = (c.maxWidth * 0.32).clamp(200.0, 330.0);
        return Row(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: Padding(padding: const EdgeInsets.all(8), child: boardBox)),
              if (banner != null) Positioned(left: 0, right: 0, top: 0, child: Center(child: banner)),
            ]),
          ),
          SizedBox(
            width: panelW,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final t in tags) Padding(padding: const EdgeInsets.only(bottom: 6), child: t),
                    ]),
                  ),
                ),
                const SizedBox(height: 4),
                StatusBar(status, highlight: statusHighlight),
                const SizedBox(height: 6),
                if (actions.isNotEmpty)
                  Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: actions),
                const SizedBox(height: 6),
                Expanded(child: info.isEmpty ? const SizedBox() : AbsInfo(info)),
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 8, runSpacing: 4, alignment: WrapAlignment.center, children: tags),
        ),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: StatusBar(status, highlight: statusHighlight)),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(6), child: boardBox)),
            if (banner != null) Positioned(left: 0, right: 0, top: 0, child: Center(child: banner)),
          ]),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.center, children: actions),
          ),
        if (info.isNotEmpty) SizedBox(height: 60, child: AbsInfo(info)),
        const SizedBox(height: 4),
      ]);
    });
  }
}

class AbsInfo extends StatelessWidget {
  final List<String> lines;
  const AbsInfo(this.lines, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
      child: SingleChildScrollView(
        child: Text(lines.join('\n'), style: TextStyle(fontSize: 13, color: cs.onSurface)),
      ),
    );
  }
}

Widget absButton(BuildContext context, String label, IconData icon, VoidCallback? onTap, {bool primary = false}) {
  const style = ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
  );
  return primary
      ? FilledButton.icon(style: style, onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label))
      : FilledButton.tonalIcon(style: style, onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));
}

Future<bool> absConfirm(BuildContext context, String title, String text) async {
  final r = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
      ],
    ),
  );
  return r == true;
}

/// Resign lives in the platform's in-game toolbar (GameEngine.canResign).
Widget? absResign(BuildContext context, GameContext g, {String label = '认输'}) => null;

class AbsDot extends StatelessWidget {
  final Color color;
  final double size;
  const AbsDot(this.color, {super.key, this.size = 18});
  @override
  Widget build(BuildContext context) {
    final light = color.computeLuminance() > 0.5;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [Color.lerp(color, Colors.white, light ? 0.6 : 0.35)!, color],
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1))],
      ),
    );
  }
}

/// 带阴影的光泽棋子。
void absStone(Canvas canvas, Offset c, double r, Color base, {double opacity = 1, bool shadow = true}) {
  if (shadow) {
    canvas.drawCircle(
        c + Offset(r * 0.1, r * 0.16),
        r,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35 * opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(0.5, r * 0.15)));
  }
  final light = base.computeLuminance() > 0.5;
  final rect = Rect.fromCircle(center: c, radius: r);
  final hi = Color.lerp(base, Colors.white, light ? 0.8 : 0.35)!;
  final lo = Color.lerp(base, Colors.black, light ? 0.22 : 0.5)!;
  canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [hi.withValues(alpha: opacity), base.withValues(alpha: opacity), lo.withValues(alpha: opacity)],
          stops: const [0, 0.55, 1],
        ).createShader(rect));
}

const kAbsBlack = Color(0xFF1C1C1C);
const kAbsWhite = Color(0xFFF1F0EA);
const kAbsRed = Color(0xFFD84343);
const kAbsBlue = Color(0xFF2F6FD6);

BoxDecoration absWood({double radius = 8}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE8BF73), Color(0xFFD9A551), Color(0xFFE3B464)],
      ),
      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4))],
    );

TextPainter absText(String s, double size, Color color, {FontWeight weight = FontWeight.w600}) => TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontFamily: kFontFallback.first,
              fontFamilyFallback: kFontFallback,
              fontSize: size,
              color: color,
              fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();

void absTextAt(Canvas canvas, String s, Offset center, double size, Color color, {FontWeight weight = FontWeight.w600}) {
  final tp = absText(s, size, color, weight: weight);
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// 结果横幅文字。
String? absBanner(GameContext g, Map<String, dynamic> v) {
  if (v['over'] != true) return null;
  final w = v['winner'] as int;
  if (w == 2 || w < 0) return '和棋';
  return w == g.seat ? '你赢了！' : '${g.name(w)} 获胜';
}
