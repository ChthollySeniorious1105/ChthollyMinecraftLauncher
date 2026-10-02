import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Responsive shell shared by the chess-family boards.
/// Portrait: opponent tag above the board, my tag below.
/// Landscape: board on the left, info panel (tags, status, actions, extra) on the right.
class BoardShell extends StatelessWidget {
  final Widget topTag;
  final Widget bottomTag;
  final String status;
  final bool statusHighlight;

  /// Board aspect ratio (width / height).
  final double aspect;
  final Widget board;
  final List<Widget> actions;
  final Widget? extra;
  final String? result;

  const BoardShell({
    super.key,
    required this.topTag,
    required this.bottomTag,
    required this.status,
    this.statusHighlight = false,
    this.aspect = 1,
    required this.board,
    this.actions = const [],
    this.extra,
    this.result,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight * 1.15;
      final boardBox = Center(child: AspectRatio(aspectRatio: aspect, child: board));
      final banner = result == null ? null : ResultBanner(result!);
      if (landscape) {
        final panelW = (c.maxWidth * 0.34).clamp(200.0, 340.0);
        return Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.all(6), child: boardBox)),
          SizedBox(
            width: panelW,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(alignment: Alignment.centerLeft, child: topTag),
                const SizedBox(height: 8),
                StatusBar(status, highlight: statusHighlight),
                ?banner,
                const SizedBox(height: 6),
                if (actions.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: actions),
                const SizedBox(height: 6),
                Expanded(child: extra ?? const SizedBox()),
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: bottomTag),
              ]),
            ),
          ),
        ]);
      }
      return Column(children: [
        const SizedBox(height: 4),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [Flexible(child: topTag)])),
        const SizedBox(height: 4),
        StatusBar(status, highlight: statusHighlight),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(4), child: boardBox)),
            if (banner != null) Positioned(left: 0, right: 0, top: 0, child: Center(child: banner)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Flexible(child: bottomTag),
            const SizedBox(width: 6),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, alignment: WrapAlignment.end, children: actions),
            ),
          ]),
        ),
        if (extra != null) SizedBox(height: 44, child: extra),
        const SizedBox(height: 4),
      ]);
    });
  }
}

/// Small pill-shaped action button.
Widget shellButton(BuildContext context, String label, IconData icon, VoidCallback? onTap, {bool primary = false}) {
  final style = ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
  );
  return primary
      ? FilledButton.icon(style: style, onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label))
      : FilledButton.tonalIcon(style: style, onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label));
}

Future<bool> confirmDialog(BuildContext context, String title, String text) async {
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

/// Resign / draw-offer buttons shared by chess and xiangqi.
List<Widget> resignDrawActions(BuildContext context, GameContext g) {
  final v = g.view;
  if (g.over || g.seat < 0 || g.seat > 1) return const [];
  final offer = v['drawOffer'] as int? ?? -1;
  return [
    if (offer == 1 - g.seat) ...[
      shellButton(context, '同意和棋', Icons.handshake, () => g.act({'type': 'acceptDraw'}), primary: true),
      shellButton(context, '拒绝', Icons.close, () => g.act({'type': 'declineDraw'})),
    ] else
      shellButton(context, offer == g.seat ? '已提和' : '提和', Icons.handshake_outlined,
          offer == g.seat ? null : () => g.act({'type': 'offerDraw'})),
    shellButton(context, '认输', Icons.flag, () async {
      if (await confirmDialog(context, '认输', '确定要认输吗？')) g.act({'type': 'resign'});
    }),
  ];
}

/// Horizontally scrolling move list (portrait) / wrapping list (landscape).
class MoveList extends StatelessWidget {
  final List<String> moves;
  final bool numbered;
  const MoveList(this.moves, {super.key, this.numbered = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = <String>[];
    for (var i = 0; i < moves.length; i += 2) {
      final a = moves[i];
      final b = i + 1 < moves.length ? moves[i + 1] : '';
      items.add('${i ~/ 2 + 1}. $a  $b');
    }
    return LayoutBuilder(builder: (context, c) {
      final vertical = c.maxHeight > 60;
      final list = ListView.builder(
        scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
        reverse: !vertical,
        padding: const EdgeInsets.all(6),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final idx = vertical ? i : items.length - 1 - i;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(items[idx],
                style: TextStyle(
                    fontSize: 13,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: idx == items.length - 1 ? FontWeight.bold : FontWeight.normal,
                    color: cs.onSurface)),
          );
        },
      );
      return Container(
        decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
        child: items.isEmpty ? Center(child: Text('暂无着法', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))) : list,
      );
    });
  }
}
