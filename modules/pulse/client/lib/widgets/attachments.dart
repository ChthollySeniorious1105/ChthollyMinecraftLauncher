import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:pulse_shared/pulse_shared.dart';

import '../main.dart';
import '../state/app_state.dart';
import '../state/files.dart';
import '../theme/themes.dart';
import 'common.dart';

/// Attachment inside a message: inline image preview or a file card with
/// size, expiry and a download button / progress.
class AttachmentView extends StatelessWidget {
  final Attachment a;
  const AttachmentView(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app.files,
      builder: (context, _) {
        final thumb = a.isImage ? app.files.thumb(a) : null;
        if (thumb != null) return _image(context, app, thumb);
        return _card(context, app);
      },
    );
  }

  String _expiry() {
    if (a.expired) return '已过期';
    final left = Duration(milliseconds: a.expires - DateTime.now().millisecondsSinceEpoch);
    if (left.inDays >= 1) return '${left.inDays} 天后过期';
    if (left.inHours >= 1) return '${left.inHours} 小时后过期';
    return '${left.inMinutes + 1} 分钟后过期';
  }

  Widget _image(BuildContext context, AppState app, Uint8List thumb) {
    final t = PulseColors.of(context);
    // fit into 400 x 300 keeping the original aspect ratio
    var w = a.w.toDouble(), h = a.h.toDouble();
    final scale = [400 / w, 300 / h, 1.0].reduce((x, y) => x < y ? x : y);
    w *= scale;
    h *= scale;
    final task = app.files.downloads[a.id];
    return Tooltip(
      message: '${a.name} · ${formatBytes(a.size)} · ${_expiry()}\n单击查看原图',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openImage(context, app, thumb),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(children: [
              Image.memory(thumb, width: w, height: h, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
              if (task != null && !task.finished && task.error == null)
                Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: task.total == 0 ? null : task.done / task.total, minHeight: 3)),
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: t.rail.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4),
                  child: InkWell(
                    onTap: () => app.files.download(a),
                    child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.download, size: 18, color: t.text)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Full image viewer: shows the thumbnail at once, then the original once downloaded.
  void _openImage(BuildContext context, AppState app, Uint8List thumb) {
    final task = app.files.downloads[a.id];
    if (task == null || task.error != null) app.files.download(a);
    showDialog<void>(useRootNavigator: false, 
      context: context,
      barrierColor: Colors.black87,
      builder: (c) => ListenableBuilder(
        listenable: app.files,
        builder: (c, _) {
          final t = app.files.downloads[a.id];
          final full = t != null && t.finished ? FileImage(File(t.path)) : null;
          return GestureDetector(
            onTap: () => Navigator.pop(c),
            child: Stack(children: [
              Positioned.fill(
                child: InteractiveViewer(
                  maxScale: 8,
                  child: Center(
                    child: full != null
                        ? Image(image: full, fit: BoxFit.contain, gaplessPlayback: true)
                        : Image.memory(thumb, fit: BoxFit.contain, gaplessPlayback: true),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${a.name} · ${formatBytes(a.size)}', style: const TextStyle(color: Colors.white)),
                      if (t != null && !t.finished && t.error == null) ...[
                        const SizedBox(width: 10),
                        SizedBox(width: 80, child: LinearProgressIndicator(value: t.total == 0 ? null : t.done / t.total)),
                      ],
                      if (t != null && t.finished)
                        TextButton(onPressed: () => app.files.showInFolder(a.id), child: const Text('在文件夹中显示')),
                    ]),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context, AppState app) {
    final t = PulseColors.of(context);
    final task = app.files.downloads[a.id];
    final running = task != null && !task.finished && task.error == null;
    final gone = a.expired;
    return Container(
      width: 380,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.sidebar, borderRadius: BorderRadius.circular(8), border: Border.all(color: t.divider)),
      child: Row(children: [
        Icon(_icon(a.name), size: 36, color: gone ? t.muted : t.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: gone ? t.muted : const Color(0xFF00A8FC), fontWeight: FontWeight.w600, decoration: gone ? TextDecoration.lineThrough : null)),
            const SizedBox(height: 2),
            if (running) ...[
              LinearProgressIndicator(value: task.total == 0 ? null : task.done / task.total, minHeight: 4),
              const SizedBox(height: 2),
              Text('${formatBytes(task.done)} / ${formatBytes(task.total == 0 ? a.size : task.total)}', style: TextStyle(color: t.muted, fontSize: 11.5)),
            ] else
              Text(
                task?.error != null ? '下载失败：${task!.error}' : '${formatBytes(a.size)} · ${_expiry()}${task?.finished ?? false ? ' · 已下载' : ''}',
                style: TextStyle(color: task?.error != null ? t.danger : t.muted, fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ]),
        ),
        if (running)
          BarButton(Icons.close, '取消下载', () => app.files.cancelDownload(a.id))
        else if (task?.finished ?? false) ...[
          BarButton(Icons.open_in_new, '打开', () => app.files.download(a, open: true)),
          BarButton(Icons.folder_open, '在文件夹中显示', () => app.files.showInFolder(a.id)),
        ] else if (!gone)
          BarButton(Icons.download, task?.error != null ? '重试' : '下载', () => app.files.download(a), color: t.text),
      ]),
    );
  }

  static IconData _icon(String n) {
    final ext = n.contains('.') ? n.substring(n.lastIndexOf('.') + 1).toLowerCase() : '';
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Icons.image_outlined,
      'mp4' || 'mkv' || 'mov' || 'avi' || 'webm' => Icons.movie_outlined,
      'mp3' || 'wav' || 'flac' || 'ogg' || 'm4a' => Icons.audio_file_outlined,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => Icons.folder_zip_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'exe' || 'msi' => Icons.terminal,
      'txt' || 'md' || 'log' || 'json' || 'csv' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

/// Files waiting in the composer (upload progress, retry, remove).
class UploadTray extends StatelessWidget {
  final List<PendingUpload> ups;
  const UploadTray(this.ups, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final t = PulseColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        height: 104,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Color.lerp(t.input, t.rail, 0.25), borderRadius: BorderRadius.circular(8)),
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final u in ups)
            Container(
              width: 168,
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: t.input, borderRadius: BorderRadius.circular(6), border: Border.all(color: u.error != null ? t.danger : t.divider)),
              child: Stack(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Center(
                      child: u.preview != null
                          ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.memory(u.preview!, fit: BoxFit.cover))
                          : Icon(AttachmentView._icon(u.name), size: 34, color: t.muted),
                    ),
                  ),
                  Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text, fontSize: 12)),
                  if (u.error != null)
                    Text(u.error!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.danger, fontSize: 11))
                  else if (u.finished)
                    Text('${formatBytes(u.size)} · 已上传', style: TextStyle(color: t.online, fontSize: 11))
                  else ...[
                    const SizedBox(height: 3),
                    LinearProgressIndicator(value: u.id == null ? null : u.progress, minHeight: 3),
                    Text('${(u.progress * 100).toStringAsFixed(0)}% · ${formatBytes(u.size)}', style: TextStyle(color: t.muted, fontSize: 11)),
                  ],
                ]),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(children: [
                    if (u.error != null) _mini(Icons.refresh, '重试', () => app.files.retry(u), t),
                    _mini(Icons.close, '移除', () => app.files.remove(u), t),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _mini(IconData i, String tip, VoidCallback f, PulseTheme t) => Tooltip(
        message: tip,
        child: Material(
          color: t.rail.withValues(alpha: 0.8),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: f, child: Padding(padding: const EdgeInsets.all(3), child: Icon(i, size: 15, color: t.text))),
        ),
      );
}

/// Small coloured role badge.
class RoleChip extends StatelessWidget {
  final RoleDef r;
  final bool small;
  const RoleChip(this.r, {super.key, this.small = false});
  @override
  Widget build(BuildContext context) {
    final t = PulseColors.of(context);
    final c = r.color == 0 ? t.muted : Color(r.color);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 0 : 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(small ? 3 : 4), border: Border.all(color: c.withValues(alpha: 0.6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!small) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 5)],
        Text(r.name, style: TextStyle(color: small ? c : t.text, fontSize: small ? 10.5 : 12, fontWeight: small ? FontWeight.w600 : FontWeight.w500)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Windows clipboard

final _user32 = DynamicLibrary.open('user32.dll');
final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _openClipboard = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');
final _closeClipboard = _user32.lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
final _getClipboardData = _user32.lookupFunction<IntPtr Function(Uint32), int Function(int)>('GetClipboardData');
final _isFormatAvailable = _user32.lookupFunction<Int32 Function(Uint32), int Function(int)>('IsClipboardFormatAvailable');
final _globalLock = _kernel32.lookupFunction<Pointer<Uint8> Function(IntPtr), Pointer<Uint8> Function(int)>('GlobalLock');
final _globalUnlock = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');
final _globalSize = _kernel32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalSize');
final _dragQueryFile = _shell32.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<Utf16>, Uint32), int Function(int, int, Pointer<Utf16>, int)>('DragQueryFileW');

const _cfHdrop = 15, _cfDib = 8;

/// Files copied in Explorer (CF_HDROP).
Future<List<String>> clipboardFiles() async {
  if (_isFormatAvailable(_cfHdrop) == 0 || _openClipboard(0) == 0) return const [];
  try {
    final h = _getClipboardData(_cfHdrop);
    if (h == 0) return const [];
    final n = _dragQueryFile(h, 0xFFFFFFFF, nullptr, 0);
    final out = <String>[];
    final buf = malloc<Uint16>(1024).cast<Utf16>();
    try {
      for (var i = 0; i < n; i++) {
        final len = _dragQueryFile(h, i, buf, 1024);
        if (len > 0) out.add(buf.toDartString(length: len));
      }
    } finally {
      malloc.free(buf);
    }
    return out.where((p) => File(p).existsSync()).toList();
  } finally {
    _closeClipboard();
  }
}

/// Bitmap on the clipboard (screenshot) as PNG.
Future<Uint8List?> clipboardImagePng() async {
  if (_isFormatAvailable(_cfDib) == 0 || _openClipboard(0) == 0) return null;
  Uint8List dib;
  try {
    final h = _getClipboardData(_cfDib);
    if (h == 0) return null;
    final p = _globalLock(h);
    if (p == nullptr) return null;
    try {
      dib = Uint8List.fromList(p.asTypedList(_globalSize(h)));
    } finally {
      _globalUnlock(h);
    }
  } finally {
    _closeClipboard();
  }
  // wrap the DIB in a BMP file header and let `image` decode it
  final bd = ByteData.sublistView(dib);
  final hdrSize = bd.getUint32(0, Endian.little);
  final bpp = bd.getUint16(14, Endian.little);
  final compression = bd.getUint32(16, Endian.little);
  var colors = bd.getUint32(32, Endian.little);
  if (colors == 0 && bpp <= 8) colors = 1 << bpp;
  final masks = compression == 3 && hdrSize == 40 ? 12 : 0;
  final offset = 14 + hdrSize + masks + colors * 4;
  final bmp = Uint8List(14 + dib.length);
  final h = ByteData.sublistView(bmp);
  bmp[0] = 0x42;
  bmp[1] = 0x4D;
  h.setUint32(2, bmp.length, Endian.little);
  h.setUint32(10, offset, Endian.little);
  bmp.setRange(14, bmp.length, dib);
  final im = img.decodeBmp(bmp);
  if (im == null) return null;
  return img.encodePng(im);
}
