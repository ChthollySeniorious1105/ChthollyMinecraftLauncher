import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Shared colours for race-package boards.
const List<Color> raceColors = [
  Color(0xFFE53935), // 红
  Color(0xFFFFB300), // 黄
  Color(0xFF1E88E5), // 蓝
  Color(0xFF43A047), // 绿
  Color(0xFF8E24AA), // 紫
  Color(0xFFFF7043), // 橙
];
const List<String> raceColorNames = ['红', '黄', '蓝', '绿', '紫', '橙'];

/// A small coloured dot used next to player tags.
Widget colorDot(Color c, {double size = 14}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.4),
          colors: [Color.lerp(c, Colors.white, 0.5)!, c, Color.lerp(c, Colors.black, 0.35)!],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0.5, 1))],
      ),
    );

/// Standard layout: player tags + status on top, a square board, and a
/// control panel that sits below (portrait) or to the right (landscape).
class RaceScaffold extends StatelessWidget {
  final List<Widget> tags;
  final String status;
  final bool highlight;
  final Widget board;
  final Widget? controls;
  final Widget? overlay;
  final double boardAspect;
  const RaceScaffold({
    super.key,
    required this.tags,
    required this.status,
    required this.board,
    this.highlight = false,
    this.controls,
    this.overlay,
    this.boardAspect = 1,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > c.maxHeight * 1.15 && c.maxWidth > 560;
      final tagWrap = Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: tags,
      );
      final boardBox = Center(child: AspectRatio(aspectRatio: boardAspect, child: board));
      Widget body;
      if (wide) {
        body = Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: boardBox)),
          SizedBox(
            width: (c.maxWidth * 0.32).clamp(220.0, 340.0),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                tagWrap,
                const SizedBox(height: 8),
                StatusBar(status, highlight: highlight),
                if (controls != null) ...[const SizedBox(height: 10), controls!],
              ]),
            ),
          ),
        ]);
      } else {
        body = Column(children: [
          const SizedBox(height: 4),
          tagWrap,
          const SizedBox(height: 6),
          StatusBar(status, highlight: highlight),
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: boardBox)),
          if (controls != null) Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: controls!),
        ]);
      }
      if (overlay == null) return body;
      return Stack(children: [
        Positioned.fill(child: body),
        Positioned(left: 0, right: 0, top: c.maxHeight * 0.25, child: Center(child: overlay!)),
      ]);
    });
  }
}

/// Result banner with a close button that dismisses it locally.
class DismissibleResult extends StatefulWidget {
  final String text;
  final Widget? child;
  const DismissibleResult(this.text, {super.key, this.child});
  @override
  State<DismissibleResult> createState() => _DismissibleResultState();
}

class _DismissibleResultState extends State<DismissibleResult> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox();
    return GestureDetector(
      onTap: () => setState(() => hidden = true),
      child: ResultBanner(widget.text,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ?widget.child,
            const SizedBox(height: 4),
            Text('点击关闭', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
          ])),
    );
  }
}
