import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show ImmutableBuffer, ImageDescriptor;

import '../main.dart';
import '../state/app_state.dart';
import '../state/avatars.dart';
import '../theme/themes.dart';
import 'common.dart';

/// Pick an image (file dialog / drag & drop), choose the square crop with pan + zoom,
/// upload. Also lets the user go back to a coloured letter avatar.
Future<void> showAvatarEditor(BuildContext context) => showDialog<void>(useRootNavigator: false, context: context, builder: (_) => const _AvatarEditor());

class _AvatarEditor extends StatefulWidget {
  const _AvatarEditor();
  @override
  State<_AvatarEditor> createState() => _AvatarEditorState();
}

class _AvatarEditorState extends State<_AvatarEditor> {
  Uint8List? _src;
  Size? _srcSize;
  double _zoom = 1, _cx = 0.5, _cy = 0.5;
  bool _busy = false, _dragOver = false;
  String? _error;

  static const _view = 260.0;

  Future<void> _pick() async {
    const group = XTypeGroup(label: '图片', extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']);
    final f = await openFile(acceptedTypeGroups: [group]);
    if (f != null) await _load(await f.readAsBytes());
  }

  Future<void> _load(Uint8List bytes) async {
    if (bytes.length > 20 * 1024 * 1024) {
      setState(() => _error = '图片太大（最多 20 MB）');
      return;
    }
    try {
      final size = await imageSizeOf(bytes);
      setState(() {
        _src = bytes;
        _srcSize = size;
        _zoom = 1;
        _cx = _cy = 0.5;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = '无法识别的图片格式');
    }
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    setState(() => _busy = true);
    final (out, err) = await prepareAvatar(_src!, cx: _cx, cy: _cy, zoom: _zoom);
    if (!mounted) return;
    if (out == null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    app.uploadAvatar(out);
    Navigator.pop(context);
    app.toast('头像已更新');
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    final me = app.myMember;
    return AlertDialog(
      title: const Text('修改头像'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropTarget(
            onDragEntered: (_) => setState(() => _dragOver = true),
            onDragExited: (_) => setState(() => _dragOver = false),
            onDragDone: (d) async {
              setState(() => _dragOver = false);
              if (d.files.isNotEmpty) await _load(await File(d.files.first.path).readAsBytes());
            },
            child: Container(
              width: _view + 20,
              height: _view + 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.sidebar,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _dragOver ? t.accent : t.divider, width: _dragOver ? 2 : 1),
              ),
              child: _src == null ? _placeholder(t) : _cropper(t),
            ),
          ),
          const SizedBox(height: 10),
          if (_src != null)
            Row(children: [
              Icon(Icons.zoom_out, size: 18, color: t.muted),
              Expanded(child: Slider(value: _zoom, min: 1, max: 4, onChanged: (v) => setState(() => _zoom = v))),
              Icon(Icons.zoom_in, size: 18, color: t.muted),
            ]),
          if (_src != null) Text('拖动图片调整位置，滚轮或滑块缩放', style: TextStyle(color: t.muted, fontSize: 12)),
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(color: t.danger))],
        ]),
      ),
      actions: [
        if (me != null && me.avatarHash.isNotEmpty)
          TextButton(
            onPressed: () {
              app.uploadAvatar(null);
              Navigator.pop(context);
            },
            child: Text('移除头像', style: TextStyle(color: t.danger)),
          ),
        TextButton(onPressed: _pick, child: Text(_src == null ? '选择图片…' : '换一张…')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _src == null || _busy ? null : _save,
          child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
        ),
      ],
    );
  }

  Widget _placeholder(PulseTheme t) => InkWell(
        onTap: _pick,
        child: SizedBox.expand(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_photo_alternate_outlined, size: 48, color: t.muted),
            const SizedBox(height: 8),
            Text('点击选择图片，或把图片拖到这里', style: TextStyle(color: t.muted)),
            const SizedBox(height: 4),
            Text('PNG / JPEG / WebP / GIF / BMP，会自动裁成正方形', style: TextStyle(color: t.muted, fontSize: 11.5)),
          ]),
        ),
      );

  /// Shows the source scaled so the crop square (= circle) fills the view; dragging
  /// moves the crop centre, wheel zooms.
  Widget _cropper(PulseTheme t) {
    final sz = _srcSize!;
    final short = sz.width < sz.height ? sz.width : sz.height;
    final scale = _view * _zoom / short; // source px -> view px
    final w = sz.width * scale, h = sz.height * scale;
    final left = -(w - _view) * _cx, top = -(h - _view) * _cy;
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) setState(() => _zoom = (_zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1)).clamp(1.0, 4.0));
      },
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          if (w > _view) _cx = (_cx - d.delta.dx / (w - _view)).clamp(0.0, 1.0);
          if (h > _view) _cy = (_cy - d.delta.dy / (h - _view)).clamp(0.0, 1.0);
        }),
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: SizedBox(
            width: _view,
            height: _view,
            child: ClipRect(
              child: Stack(children: [
                Positioned(left: left, top: top, width: w, height: h, child: Image.memory(_src!, fit: BoxFit.fill, gaplessPlayback: true)),
                // circular mask preview
                IgnorePointer(child: CustomPaint(size: const Size(_view, _view), painter: _CircleMask(t.sidebar.withValues(alpha: 0.75)))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  static Future<Size> imageSizeOf(Uint8List bytes) async {
    final buf = await ImmutableBuffer.fromUint8List(bytes);
    final desc = await ImageDescriptor.encoded(buf);
    final size = Size(desc.width.toDouble(), desc.height.toDouble());
    desc.dispose();
    buf.dispose();
    if (size.width < 1 || size.height < 1) throw const FormatException('empty image');
    return size;
  }
}

class _CircleMask extends CustomPainter {
  final Color color;
  _CircleMask(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Offset.zero & size);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(size.center(Offset.zero), size.width / 2 - 1, Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white70
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CircleMask old) => old.color != color;
}

/// Profile widget for settings: current avatar with an edit badge.
class AvatarEditButton extends StatelessWidget {
  final Member member;
  final double size;
  const AvatarEditButton(this.member, {super.key, this.size = 72});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    return Tooltip(
      message: '修改头像',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => showAvatarEditor(context),
        child: Stack(clipBehavior: Clip.none, children: [
          Avatar(member, size: size, showPresence: true),
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle, border: Border.all(color: t.sidebar, width: 2)),
              child: Icon(Icons.edit, size: 13, color: t.onAccent),
            ),
          ),
        ]),
      ),
    );
  }
}
