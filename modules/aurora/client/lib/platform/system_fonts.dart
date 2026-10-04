import 'system_fonts_io.dart' if (dart.library.js_interop) 'system_fonts_web.dart' as impl;

/// An installed font family. [family] is what goes into `TextStyle.fontFamily`; [localName] is the
/// Chinese name when the font has one (e.g. Microsoft YaHei → 微软雅黑).
class SystemFont {
  final String family;
  final String? localName;
  const SystemFont(this.family, [this.localName]);

  String get label => localName == null ? family : '$family（$localName）';
  bool matches(String query) =>
      family.toLowerCase().contains(query) || (localName?.toLowerCase().contains(query) ?? false);
}

/// Font families installed on this machine, sorted and de-duplicated. Cached after the first call.
/// Always empty in the browser (CanvasKit can only draw fonts it has loaded itself).
Future<List<SystemFont>> systemFontFamilies() => _cache ??= impl.listSystemFonts().then((all) {
      final seen = <String>{};
      final out = [
        for (final f in all)
          if (f.family.isNotEmpty &&
              !f.family.startsWith('@') &&
              !f.family.startsWith('.') &&
              seen.add(f.family.toLowerCase()))
            f,
      ];
      out.sort((a, b) => a.family.toLowerCase().compareTo(b.family.toLowerCase()));
      return out;
    }).catchError((_) => <SystemFont>[]);

Future<List<SystemFont>>? _cache;
