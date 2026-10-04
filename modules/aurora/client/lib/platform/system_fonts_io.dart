import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' show GUIDFromString;

import 'system_fonts.dart';

Future<List<SystemFont>> listSystemFonts() async {
  if (Platform.isWindows) return _directWriteFonts();
  if (Platform.isMacOS) {
    // AppKit's family list, through JXA so no native plugin is needed.
    final r = await Process.run('osascript', [
      '-l',
      'JavaScript',
      '-e',
      "ObjC.import('AppKit'); "
          r"ObjC.deepUnwrap($.NSFontManager.sharedFontManager.availableFontFamilies).join('\n')",
    ]);
    if (r.exitCode != 0) return const [];
    return [for (final f in '${r.stdout}'.split('\n')) SystemFont(f.trim())];
  }
  final r = await Process.run('fc-list', [':', 'family']);
  if (r.exitCode != 0) return const [];
  // fc-list prints "Family,Localized family" per line.
  return [
    for (final line in '${r.stdout}'.split('\n'))
      if (line.trim().isNotEmpty)
        SystemFont(
          line.split(',').first.trim(),
          line.contains(',') ? line.split(',').last.trim() : null,
        ),
  ];
}

// Windows: the DirectWrite system collection, which is what Skia resolves family names against.
// (GDI's EnumFontFamiliesEx returns 31-character legacy names that Flutter cannot find.)

typedef _Release = Int32 Function(Pointer<IntPtr> self);

/// Function pointer at vtable slot [i] of COM object [obj].
Pointer<NativeFunction<T>> _slot<T extends Function>(Pointer<IntPtr> obj, int i) =>
    Pointer<NativeFunction<T>>.fromAddress(Pointer<IntPtr>.fromAddress(obj.value)[i]);

void _release(Pointer<IntPtr> obj) {
  if (obj.address != 0) _slot<_Release>(obj, 2).asFunction<int Function(Pointer<IntPtr>)>()(obj);
}

List<SystemFont> _directWriteFonts() {
  final create = DynamicLibrary.open('dwrite.dll').lookupFunction<
      Int32 Function(Int32, Pointer<Void>, Pointer<Pointer<IntPtr>>),
      int Function(int, Pointer<Void>, Pointer<Pointer<IntPtr>>)>('DWriteCreateFactory');
  final out = <SystemFont>[];
  final iid = GUIDFromString('{b859ee5a-d838-4b5b-a2e8-1adc7d93db48}'); // IID_IDWriteFactory
  final pp = calloc<Pointer<IntPtr>>();
  var factory = nullptr.cast<IntPtr>(), collection = nullptr.cast<IntPtr>();
  try {
    if (create(0 /* DWRITE_FACTORY_TYPE_SHARED */, iid.cast(), pp) < 0) return out;
    factory = pp.value;
    // IDWriteFactory::GetSystemFontCollection(collection, checkForUpdates)
    final getCollection = _slot<Int32 Function(Pointer<IntPtr>, Pointer<Pointer<IntPtr>>, Int32)>(factory, 3)
        .asFunction<int Function(Pointer<IntPtr>, Pointer<Pointer<IntPtr>>, int)>();
    if (getCollection(factory, pp, 0) < 0) return out;
    collection = pp.value;
    // IDWriteFontCollection::GetFontFamilyCount / GetFontFamily
    final count = _slot<Uint32 Function(Pointer<IntPtr>)>(collection, 3)
        .asFunction<int Function(Pointer<IntPtr>)>()(collection);
    final getFamily = _slot<Int32 Function(Pointer<IntPtr>, Uint32, Pointer<Pointer<IntPtr>>)>(collection, 4)
        .asFunction<int Function(Pointer<IntPtr>, int, Pointer<Pointer<IntPtr>>)>();
    for (var i = 0; i < count; i++) {
      if (getFamily(collection, i, pp) < 0) continue;
      final family = pp.value;
      try {
        // IDWriteFontFamily::GetFamilyNames
        final getNames = _slot<Int32 Function(Pointer<IntPtr>, Pointer<Pointer<IntPtr>>)>(family, 6)
            .asFunction<int Function(Pointer<IntPtr>, Pointer<Pointer<IntPtr>>)>();
        if (getNames(family, pp) < 0) continue;
        final names = pp.value;
        try {
          final en = _localized(names, 'en-us') ?? _localized(names, null);
          if (en == null) continue;
          final zh = _localized(names, 'zh-cn');
          out.add(SystemFont(en, zh == en ? null : zh));
        } finally {
          _release(names);
        }
      } finally {
        _release(family);
      }
    }
  } finally {
    _release(collection);
    _release(factory);
    calloc.free(pp);
    calloc.free(iid);
  }
  return out;
}

/// IDWriteLocalizedStrings lookup; [locale] null = the first entry.
String? _localized(Pointer<IntPtr> names, String? locale) => using((arena) {
      final index = arena<Uint32>();
      if (locale != null) {
        final exists = arena<Int32>();
        // FindLocaleName(localeName, index, exists)
        final find = _slot<Int32 Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Int32>)>(names, 4)
            .asFunction<int Function(Pointer<IntPtr>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Int32>)>();
        if (find(names, locale.toNativeUtf16(allocator: arena), index, exists) < 0 || exists.value == 0) {
          return null;
        }
      }
      final len = arena<Uint32>();
      // GetStringLength(index, length) / GetString(index, buffer, size)
      final getLength = _slot<Int32 Function(Pointer<IntPtr>, Uint32, Pointer<Uint32>)>(names, 7)
          .asFunction<int Function(Pointer<IntPtr>, int, Pointer<Uint32>)>();
      if (getLength(names, index.value, len) < 0) return null;
      final buf = arena<Uint16>(len.value + 1);
      final getString = _slot<Int32 Function(Pointer<IntPtr>, Uint32, Pointer<Uint16>, Uint32)>(names, 8)
          .asFunction<int Function(Pointer<IntPtr>, int, Pointer<Uint16>, int)>();
      if (getString(names, index.value, buf, len.value + 1) < 0) return null;
      return buf.cast<Utf16>().toDartString(length: len.value);
    });
