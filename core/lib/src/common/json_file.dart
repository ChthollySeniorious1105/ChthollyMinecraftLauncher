import 'dart:convert';
import 'dart:io';

/// Atomic JSON persistence (write tmp then rename).
abstract class JsonFile {
  static Future<Object?> read(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } on FormatException {
      return null;
    }
  }

  static Future<void> write(String path, Object? value, {bool pretty = true}) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    final tmp = File('$path.tmp');
    final text = pretty ? const JsonEncoder.withIndent('  ').convert(value) : jsonEncode(value);
    await tmp.writeAsString(text, flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(path);
  }
}
