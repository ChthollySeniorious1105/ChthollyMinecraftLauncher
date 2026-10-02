import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../state/screen_share.dart';
import '../theme/themes.dart';
import '../widgets/common.dart';

/// Pick a monitor / window and quality, then start sharing.
Future<void> shareScreenDialog(BuildContext context, AppState app) async {
  final src = app.screen.sources();
  final monitors = [for (final m in (src['monitors'] as List? ?? const [])) m as Map<String, dynamic>];
  final windows = [for (final w in (src['windows'] as List? ?? const [])) w as Map<String, dynamic>];
  if (monitors.isEmpty && windows.isEmpty) {
    app.toast('没有找到可共享的屏幕或窗口');
    return;
  }
  var tab = 0;
  String? sel = monitors.isNotEmpty ? '${monitors.first['id']}' : null;
  var selName = monitors.isNotEmpty ? '${monitors.first['name']}' : '';
  var preset = app.screen.preset;
  final thumbs = <String, Image?>{};
  Image? thumb(String id) => thumbs.putIfAbsent(id, () {
        final r = app.native.screenThumbnail(id, maxW: 320, maxH: 180);
        if (r == null) return null;
        return Image.memory(rgbaToBmp(r.$1, r.$2, r.$3), fit: BoxFit.contain, gaplessPlayback: true);
      });
  final ok = await showDialog<bool>(useRootNavigator: false, 
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final t = PulseColors.of(c);
      final items = tab == 0 ? monitors : windows;
      Widget tile(Map<String, dynamic> it) {
        final id = '${it['id']}';
        final name = tab == 0 ? '${it['name']}${it['primary'] == true ? '（主显示器）' : ''}' : '${it['title']}';
        final selected = sel == id;
        return InkWell(
          onTap: () => set(() {
            sel = id;
            selName = tab == 0 ? '${it['name']}' : '${it['title']}';
          }),
          onDoubleTap: () {
            sel = id;
            selName = tab == 0 ? '${it['name']}' : '${it['title']}';
            Navigator.pop(c, true);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected ? t.accent.withValues(alpha: 0.18) : t.input,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? t.accent : Colors.transparent, width: 2),
            ),
            child: Column(children: [
              Expanded(child: Container(color: Colors.black, alignment: Alignment.center, child: thumb(id) ?? Icon(tab == 0 ? Icons.monitor : Icons.web_asset, color: t.muted, size: 40))),
              const SizedBox(height: 4),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.text)),
              if (tab == 1 && '${it['exe']}'.isNotEmpty) Text('${it['exe']}', maxLines: 1, style: TextStyle(fontSize: 11, color: t.muted)),
              if (tab == 0) Text('${it['w']} × ${it['h']}', style: TextStyle(fontSize: 11, color: t.muted)),
            ]),
          ),
        );
      }

      return AlertDialog(
        title: const Text('共享屏幕'),
        content: SizedBox(
          width: 720,
          height: 470,
          child: Column(children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, icon: const Icon(Icons.monitor), label: Text('屏幕（${monitors.length}）')),
                ButtonSegment(value: 1, icon: const Icon(Icons.web_asset), label: Text('窗口（${windows.length}）')),
              ],
              selected: {tab},
              onSelectionChanged: (v) => set(() => tab = v.first),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('没有可共享的${tab == 0 ? '屏幕' : '窗口'}', style: TextStyle(color: t.muted)))
                  : GridView.count(crossAxisCount: 3, childAspectRatio: 1.35, mainAxisSpacing: 10, crossAxisSpacing: 10, children: [for (final it in items) tile(it)]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Text('画质'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: preset,
                items: [for (var i = 0; i < streamPresets.length; i++) DropdownMenuItem(value: i, child: Text('${streamPresets[i].$1}（${streamPresets[i].$5 ~/ 1000} Mbps 上行）'))],
                onChanged: (v) => set(() => preset = v ?? preset),
              ),
              const Spacer(),
              Flexible(child: Text('画面经服务器转发，只有点击观看的人才会接收', style: TextStyle(color: t.muted, fontSize: 11.5), textAlign: TextAlign.right)),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton.icon(onPressed: sel == null ? null : () => Navigator.pop(c, true), icon: const Icon(Icons.screen_share), label: const Text('开始共享')),
        ],
      );
    }),
  );
  if (ok == true && sel != null) app.screen.start(sel!, selName, preset);
}

/// Wraps tightly packed RGBA in a 32-bit BMP so Image.memory can show it.
Uint8List rgbaToBmp(Uint8List rgba, int w, int h) {
  final size = 54 + w * h * 4;
  final b = Uint8List(size);
  final d = ByteData.sublistView(b);
  b[0] = 0x42;
  b[1] = 0x4D;
  d.setUint32(2, size, Endian.little);
  d.setUint32(10, 54, Endian.little);
  d.setUint32(14, 40, Endian.little);
  d.setInt32(18, w, Endian.little);
  d.setInt32(22, -h, Endian.little); // top-down
  d.setUint16(26, 1, Endian.little);
  d.setUint16(28, 32, Endian.little);
  d.setUint32(34, w * h * 4, Endian.little);
  var o = 54;
  for (var i = 0; i < w * h * 4; i += 4) {
    b[o++] = rgba[i + 2];
    b[o++] = rgba[i + 1];
    b[o++] = rgba[i];
    b[o++] = 255;
  }
  return b;
}

/// Watched streams above the chat (resizable split).
class StreamSplit extends StatefulWidget {
  final Widget chat;
  const StreamSplit({super.key, required this.chat});
  @override
  State<StreamSplit> createState() => _StreamSplitState();
}

class _StreamSplitState extends State<StreamSplit> {
  double _frac = 0.62;
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    if (_full) return _StreamArea(onFull: () => setState(() => _full = false), full: true);
    return LayoutBuilder(builder: (context, c) {
      final top = (c.maxHeight * _frac).clamp(160.0, c.maxHeight - 160);
      return Column(children: [
        SizedBox(height: top, child: _StreamArea(onFull: () => setState(() => _full = true), full: false)),
        MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) => setState(() => _frac = ((top + d.delta.dy) / c.maxHeight).clamp(0.2, 0.85)),
            child: Container(height: 6, color: t.rail, alignment: Alignment.center, child: Container(width: 40, height: 2, color: t.divider)),
          ),
        ),
        Expanded(child: widget.chat),
      ]);
    });
  }
}

class _StreamArea extends StatelessWidget {
  final VoidCallback onFull;
  final bool full;
  const _StreamArea({required this.onFull, required this.full});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final sc = app.screen;
    final ids = sc.watching.keys.toList();
    final main = sc.focused != null && sc.watching.containsKey(sc.focused) ? sc.focused! : ids.first;
    final others = ids.where((x) => x != main).toList();
    return Container(
      color: Colors.black,
      child: Column(children: [
        Expanded(child: _StreamTile(main, big: true, onFull: onFull, full: full)),
        if (others.isNotEmpty)
          Container(
            height: 96,
            color: t.rail,
            padding: const EdgeInsets.all(6),
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final id in others)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 150,
                    child: GestureDetector(onTap: () => app.screen.watch(id), child: _StreamTile(id, big: false, onFull: onFull, full: full)),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _StreamTile extends StatelessWidget {
  final int uid;
  final bool big, full;
  final VoidCallback onFull;
  const _StreamTile(this.uid, {required this.big, required this.onFull, required this.full});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final sc = app.screen;
    final tex = sc.watching[uid];
    final size = sc.sizes[uid];
    final m = app.members[uid];
    final st = app.streams[uid];
    final mine = uid == app.me;
    Widget video;
    if (tex == null || size == null) {
      video = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          if (big) ...[const SizedBox(height: 8), Text('正在连接 ${m?.display ?? ''} 的直播…', style: const TextStyle(color: Colors.white70))],
        ]),
      );
    } else {
      video = Center(child: AspectRatio(aspectRatio: size.$1 / size.$2, child: Texture(textureId: tex, filterQuality: FilterQuality.medium)));
    }
    return Stack(children: [
      Positioned.fill(child: video),
      Positioned(
        left: 8,
        top: 8,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(3)),
              child: const Text('直播', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            Text(mine ? '我的共享（预览）' : (m?.display ?? '#$uid'), style: const TextStyle(color: Colors.white, fontSize: 12.5)),
            if (big && st != null && st.title.isNotEmpty) Text(' · ${st.title}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            if (big && size != null) Text(' · ${size.$1}×${size.$2}', style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
            if (big && st != null && st.viewers.isNotEmpty) ...[
              const SizedBox(width: 6),
              const Icon(Icons.visibility, size: 13, color: Colors.white70),
              Text(' ${st.viewers.length}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ]),
        ),
      ),
      if (big)
        Positioned(
          right: 8,
          top: 8,
          child: Row(children: [
            if (mine && sc.sharing)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  '${(sc.status['fps'] as num?)?.toStringAsFixed(0) ?? '-'} fps · ${((sc.status['kbps'] as num?) ?? 0) ~/ 1000} Mbps · ${sc.status['hw'] == true ? '硬件编码' : '软件编码'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ),
            _btn(full ? Icons.fullscreen_exit : Icons.fullscreen, full ? '退出全屏' : '放大', onFull),
            _btn(Icons.close, mine ? '关闭预览' : '停止观看', () => mine ? sc.togglePreview() : sc.unwatch(uid)),
          ]),
        ),
    ]);
  }

  Widget _btn(IconData i, String tip, VoidCallback f) => Tooltip(
        message: tip,
        child: Material(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(onTap: f, child: Padding(padding: const EdgeInsets.all(5), child: Icon(i, color: Colors.white, size: 18))),
        ),
      );
}

/// "Watch" banner for voice channels with live streams (shown in the voice panel area).
class LiveStreamsBar extends StatelessWidget {
  const LiveStreamsBar({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final ch = app.voiceChannel;
    if (ch == null) return const SizedBox.shrink();
    final list = app.streamsIn(ch).where((s) => s.uid != app.me && !app.screen.watching.containsKey(s.uid)).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final s in list)
        HoverTile(
          onTap: () => app.screen.watch(s.uid),
          child: Row(children: [
            Icon(Icons.live_tv, size: 16, color: t.danger),
            const SizedBox(width: 6),
            Expanded(child: Text('观看 ${app.members[s.uid]?.display ?? ''} 的屏幕', overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 12.5))),
          ]),
        ),
    ]);
  }
}
