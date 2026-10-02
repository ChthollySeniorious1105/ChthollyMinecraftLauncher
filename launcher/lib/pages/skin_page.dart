import 'dart:io';
import 'dart:typed_data';

import 'package:cml_core/cml_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../state.dart';
import '../widgets/skin3d.dart';

/// Skin painter with live 3D preview, upload to the Microsoft account, and cape switching.
class SkinPage extends StatefulWidget {
  const SkinPage({super.key});
  @override
  State<SkinPage> createState() => _SkinPageState();
}

enum _Tool { pencil, eraser, picker, fill, darken, lighten }

class _SkinPageState extends State<SkinPage> {
  img.Image skin = SkinModel.blank();
  bool slim = false;
  bool overlay = true;
  int revision = 0;
  Color color = const Color(0xFF3B82F6);
  _Tool tool = _Tool.pencil;
  final undo = <Uint8List>[];
  final redo = <Uint8List>[];
  String? fileName;

  static const _palette = [
    Color(0xFF000000), Color(0xFF3F3F3F), Color(0xFF7F7F7F), Color(0xFFBFBFBF), Color(0xFFFFFFFF),
    Color(0xFFC68E6A), Color(0xFF8D5A3B), Color(0xFF5B3A24), Color(0xFFF4C7A1), Color(0xFFE53935),
    Color(0xFFFF9800), Color(0xFFFFEB3B), Color(0xFF4CAF50), Color(0xFF00A8A8), Color(0xFF2196F3),
    Color(0xFF3A3A9A), Color(0xFF9C27B0), Color(0xFFE88BAA), Color(0xFF795548), Color(0xFF263238),
  ];

  void _snapshot() {
    undo.add(Uint8List.fromList(skin.getBytes()));
    if (undo.length > 100) undo.removeAt(0);
    redo.clear();
  }

  void _restore(List<Uint8List> from, List<Uint8List> to) {
    if (from.isEmpty) return;
    to.add(Uint8List.fromList(skin.getBytes()));
    final b = from.removeLast();
    skin = img.Image.fromBytes(width: 64, height: 64, bytes: b.buffer, numChannels: 4);
    setState(() => revision++);
  }

  void _paint(int x, int y) {
    if (x < 0 || y < 0 || x >= 64 || y >= 64) return;
    switch (tool) {
      case _Tool.pencil:
        skin.setPixelRgba(x, y, (color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round(), (color.a * 255).round());
      case _Tool.eraser:
        skin.setPixelRgba(x, y, 0, 0, 0, 0);
      case _Tool.picker:
        final p = skin.getPixel(x, y);
        setState(() => color = Color.fromARGB(p.a.toInt(), p.r.toInt(), p.g.toInt(), p.b.toInt()));
        return;
      case _Tool.fill:
        _flood(x, y);
      case _Tool.darken || _Tool.lighten:
        final p = skin.getPixel(x, y);
        if (p.a == 0) return;
        final f = tool == _Tool.darken ? 0.9 : 1.1;
        skin.setPixelRgba(x, y, (p.r * f).clamp(0, 255).toInt(), (p.g * f).clamp(0, 255).toInt(), (p.b * f).clamp(0, 255).toInt(), p.a.toInt());
    }
    setState(() => revision++);
  }

  void _flood(int sx, int sy) {
    final target = skin.getPixel(sx, sy);
    final tr = target.r, tg = target.g, tb = target.b, ta = target.a;
    final nr = (color.r * 255).round(), ng = (color.g * 255).round(), nb = (color.b * 255).round(), na = (color.a * 255).round();
    if (tr == nr && tg == ng && tb == nb && ta == na) return;
    final stack = [(sx, sy)];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final (x, y) = stack.removeLast();
      if (x < 0 || y < 0 || x >= 64 || y >= 64 || !seen.add(y * 64 + x)) continue;
      final p = skin.getPixel(x, y);
      if (p.r != tr || p.g != tg || p.b != tb || p.a != ta) continue;
      skin.setPixelRgba(x, y, nr, ng, nb, na);
      stack.addAll([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]);
    }
  }

  Future<void> _open() async {
    final f = await openFile(acceptedTypeGroups: const [XTypeGroup(label: '皮肤 PNG', extensions: ['png'])]);
    if (f == null) return;
    try {
      _snapshot();
      final s = SkinModel.decode(await f.readAsBytes());
      setState(() {
        skin = s;
        slim = SkinModel.guessSlim(s);
        fileName = f.name;
        revision++;
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _loadCurrent() async {
    final app = App.read(context);
    final a = app.ctx.accounts.selected;
    final url = a?.activeSkin?.url;
    if (url == null) return toast(context, '当前账号没有自定义皮肤', error: true);
    try {
      final bytes = await app.ctx.http.bytes(Uri.parse(url));
      _snapshot();
      setState(() {
        skin = SkinModel.decode(bytes);
        slim = a!.activeSkin!.variant.toUpperCase() == 'SLIM';
        fileName = '${a.name}.png';
        revision++;
      });
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _save() async {
    final loc = await getSaveLocation(suggestedName: fileName ?? 'skin.png', acceptedTypeGroups: const [XTypeGroup(label: 'PNG', extensions: ['png'])]);
    if (loc == null) return;
    await File(loc.path).writeAsBytes(SkinModel.encode(skin));
    if (mounted) toast(context, '已保存');
  }

  Future<void> _upload() async {
    final app = App.read(context);
    var a = app.ctx.accounts.selected;
    if (a == null) return toast(context, '请先登录微软账号', error: true);
    if (!await confirm(context, '上传皮肤', '将当前皮肤（${slim ? '纤细 Alex' : '经典 Steve'} 模型）设置为 ${a.name} 的正版皮肤？')) return;
    await app.runTask('上传皮肤', (t) async {
      a = await app.ctx.auth.ensureValid(a!);
      await app.ctx.auth.uploadSkin(a!, SkinModel.encode(skin), slim: slim);
      app.ctx.accounts.upsert(a!);
      await app.ctx.accounts.save();
    }, onError: (e) => toast(context, errText(e), error: true));
    if (mounted) toast(context, '皮肤已更新');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(children: [
      // ---------------- 2D editor ----------------
      Expanded(
        flex: 5,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(icon: const Icon(Icons.folder_open, size: 16), label: const Text('打开'), onPressed: _open),
              OutlinedButton.icon(icon: const Icon(Icons.cloud_download_outlined, size: 16), label: const Text('读取当前皮肤'), onPressed: _loadCurrent),
              OutlinedButton.icon(icon: const Icon(Icons.save_outlined, size: 16), label: const Text('另存为'), onPressed: _save),
              OutlinedButton.icon(
                icon: const Icon(Icons.note_add_outlined, size: 16),
                label: const Text('新建'),
                onPressed: () {
                  _snapshot();
                  setState(() {
                    skin = SkinModel.blank();
                    revision++;
                  });
                },
              ),
              IconButton(onPressed: undo.isEmpty ? null : () => _restore(undo, redo), icon: const Icon(Icons.undo), tooltip: '撤销'),
              IconButton(onPressed: redo.isEmpty ? null : () => _restore(redo, undo), icon: const Icon(Icons.redo), tooltip: '重做'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              SegmentedButton<_Tool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _Tool.pencil, icon: Icon(Icons.edit, size: 16), tooltip: '画笔'),
                  ButtonSegment(value: _Tool.eraser, icon: Icon(Icons.auto_fix_normal, size: 16), tooltip: '橡皮'),
                  ButtonSegment(value: _Tool.fill, icon: Icon(Icons.format_color_fill, size: 16), tooltip: '填充'),
                  ButtonSegment(value: _Tool.picker, icon: Icon(Icons.colorize, size: 16), tooltip: '取色'),
                  ButtonSegment(value: _Tool.darken, icon: Icon(Icons.brightness_4, size: 16), tooltip: '加深'),
                  ButtonSegment(value: _Tool.lighten, icon: Icon(Icons.brightness_7, size: 16), tooltip: '减淡'),
                ],
                selected: {tool},
                onSelectionChanged: (s) => setState(() => tool = s.first),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () async {
                  final c = await _pickColor(context, color);
                  if (c != null) setState(() => color = c);
                },
                child: Container(width: 32, height: 32, decoration: BoxDecoration(color: color, border: Border.all(color: t.dividerColor), borderRadius: BorderRadius.circular(6))),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 4, runSpacing: 4, children: [
              for (final c in _palette)
                GestureDetector(
                  onTap: () => setState(() {
                    color = c;
                    if (tool == _Tool.eraser || tool == _Tool.picker) tool = _Tool.pencil;
                  }),
                  child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c, border: Border.all(color: c == color ? t.colorScheme.primary : t.dividerColor, width: c == color ? 2 : 1))),
                ),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(builder: (_, box) {
                final side = box.biggest.shortestSide;
                final cell = side / 64;
                return Center(
                  child: GestureDetector(
                    onPanStart: (d) {
                      _snapshot();
                      _paint(d.localPosition.dx ~/ cell, d.localPosition.dy ~/ cell);
                    },
                    onPanUpdate: tool == _Tool.fill || tool == _Tool.picker ? null : (d) => _paint(d.localPosition.dx ~/ cell, d.localPosition.dy ~/ cell),
                    onTapDown: (d) {
                      _snapshot();
                      _paint(d.localPosition.dx ~/ cell, d.localPosition.dy ~/ cell);
                    },
                    child: CustomPaint(size: Size(side, side), painter: _FlatPainter(skin, revision, t.dividerColor)),
                  ),
                );
              }),
            ),
          ]),
        ),
      ),
      const VerticalDivider(width: 1),
      // ---------------- 3D preview & account ----------------
      Expanded(
        flex: 4,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              SegmentedButton<bool>(
                segments: const [ButtonSegment(value: false, label: Text('经典 Steve')), ButtonSegment(value: true, label: Text('纤细 Alex'))],
                selected: {slim},
                onSelectionChanged: (s) => setState(() => slim = s.first),
              ),
              const Spacer(),
              const Text('外层'),
              Switch(value: overlay, onChanged: (v) => setState(() => overlay = v)),
            ]),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
              child: Stack(children: [
                Positioned.fill(child: Skin3DView(skin: skin, slim: slim, showOverlay: overlay, revision: revision)),
                Positioned(left: 12, bottom: 8, child: Text('拖动旋转 · 滚轮缩放 · 双击复位', style: t.textTheme.bodySmall)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(children: [
              Expanded(child: FilledButton.icon(icon: const Icon(Icons.cloud_upload_outlined), label: const Text('上传为正版皮肤'), onPressed: _upload)),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.flag_outlined), label: const Text('披风'), onPressed: () => showDialog(context: context, builder: (_) => const CapeDialog()))),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _FlatPainter extends CustomPainter {
  final img.Image skin;
  final int revision;
  final Color grid;
  _FlatPainter(this.skin, this.revision, this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 64;
    final checker = Paint()..color = const Color(0x14000000);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        if ((x + y).isOdd) canvas.drawRect(Rect.fromLTWH(x * c, y * c, c, c), checker);
        final p = skin.getPixel(x, y);
        if (p.a == 0) continue;
        canvas.drawRect(Rect.fromLTWH(x * c, y * c, c + 0.5, c + 0.5), Paint()..color = Color.fromARGB(p.a.toInt(), p.r.toInt(), p.g.toInt(), p.b.toInt()));
      }
    }
    // part outlines
    final line = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final slim in [false]) {
      for (final part in SkinModel.parts(slim: slim)) {
        for (final ov in [false, true]) {
          for (final f in part.faces(overlay: ov).values) {
            canvas.drawRect(Rect.fromLTWH(f.x * c, f.y * c, f.w * c, f.h * c), line);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_FlatPainter o) => o.revision != revision || !identical(o.skin, skin);
}

Future<Color?> _pickColor(BuildContext context, Color initial) async {
  final ctl = TextEditingController(text: initial.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase());
  var h = HSVColor.fromColor(initial);
  return showDialog<Color>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('选择颜色'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 48, color: h.toColor()),
            const SizedBox(height: 8),
            for (final (label, value, max, apply) in [
              ('色相', h.hue, 360.0, (double v) => h = h.withHue(v)),
              ('饱和度', h.saturation, 1.0, (double v) => h = h.withSaturation(v)),
              ('明度', h.value, 1.0, (double v) => h = h.withValue(v)),
            ])
              Row(children: [
                SizedBox(width: 56, child: Text(label)),
                Expanded(
                  child: Slider(
                    value: value,
                    max: max,
                    onChanged: (v) => set(() {
                      apply(v);
                      ctl.text = h.toColor().toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
                    }),
                  ),
                ),
              ]),
            TextField(
              controller: ctl,
              decoration: const InputDecoration(prefixText: '#', labelText: 'HEX'),
              onChanged: (v) {
                final n = int.tryParse(v, radix: 16);
                if (v.length == 6 && n != null) set(() => h = HSVColor.fromColor(Color(0xFF000000 | n)));
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, h.toColor()), child: const Text('确定')),
        ],
      ),
    ),
  );
}

/// "披风切换": lists the account's capes and equips/hides them.
class CapeDialog extends StatefulWidget {
  const CapeDialog({super.key});
  @override
  State<CapeDialog> createState() => _CapeDialogState();
}

class _CapeDialogState extends State<CapeDialog> {
  bool busy = false;

  Future<void> _set(String? id) async {
    final app = App.read(context);
    var a = app.ctx.accounts.selected!;
    setState(() => busy = true);
    try {
      a = await app.ctx.auth.ensureValid(a);
      await app.ctx.auth.setCape(a, id);
      app.ctx.accounts.upsert(a);
      await app.ctx.accounts.save();
      app.changed();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = App.of(context);
    final a = app.ctx.accounts.selected;
    return AlertDialog(
      title: const Text('披风'),
      content: SizedBox(
        width: 520,
        child: a == null
            ? const Text('请先登录微软账号')
            : a.capes.isEmpty
                ? const Text('这个账号没有任何披风（披风来自 Minecraft 活动、Migrator 等）。')
                : Wrap(spacing: 12, runSpacing: 12, children: [
                    _capeTile(context, null, '不显示', a.activeCape == null),
                    for (final c in a.capes) _capeTile(context, c, c.alias, c.active),
                  ]),
      ),
      actions: [
        if (busy) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        if (a != null)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      await app.ctx.auth.reloadProfile(a);
                      await app.ctx.accounts.save();
                    } catch (_) {}
                    if (mounted) setState(() => busy = false);
                  },
            child: const Text('刷新'),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  Widget _capeTile(BuildContext context, Cape? c, String label, bool active) {
    final t = Theme.of(context);
    return InkWell(
      onTap: busy || active ? null : () => _set(c?.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? t.colorScheme.primary : t.dividerColor, width: active ? 2 : 1),
        ),
        child: Column(children: [
          SizedBox(
            width: 40,
            height: 64,
            child: c == null
                ? const Icon(Icons.block, size: 32)
                : ClipRect(
                    // cape texture 64×32: front face is at (1,1) size 10×16
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        width: 10,
                        height: 16,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          maxWidth: 64,
                          maxHeight: 32,
                          child: Transform.translate(offset: const Offset(-1, -1), child: Image.network(c.url, width: 64, height: 32, filterQuality: FilterQuality.none)),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}
