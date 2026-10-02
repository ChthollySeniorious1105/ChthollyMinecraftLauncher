import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// In-memory resource pack: path → bytes, with JSON / image helpers.
/// Paths always use `/` and are relative to the pack root.
class PackFiles {
  final Map<String, Uint8List> files;
  PackFiles([Map<String, Uint8List>? f]) : files = f ?? {};

  Iterable<String> get paths => files.keys;
  bool has(String p) => files.containsKey(p);
  Uint8List? operator [](String p) => files[p];
  void operator []=(String p, Uint8List v) => files[p] = v;
  Uint8List? remove(String p) => files.remove(p);

  void move(String from, String to) {
    final b = files.remove(from);
    if (b != null && !files.containsKey(to)) files[to] = b;
  }

  String? text(String p) => files[p] == null ? null : utf8.decode(files[p]!, allowMalformed: true);
  void setText(String p, String s) => files[p] = Uint8List.fromList(utf8.encode(s));

  /// Lenient JSON (Bedrock files often contain `//` comments and trailing commas).
  dynamic json(String p) {
    final t = text(p);
    if (t == null) return null;
    try {
      return jsonDecode(t);
    } on FormatException {
      try {
        return jsonDecode(stripJsonComments(t));
      } on FormatException {
        return null;
      }
    }
  }

  void setJson(String p, Object? v, {bool pretty = true}) => setText(p, pretty ? const JsonEncoder.withIndent('  ').convert(v) : jsonEncode(v));

  img.Image? image(String p) {
    final b = files[p];
    if (b == null) return null;
    try {
      return img.decodeImage(b)?.convert(numChannels: 4);
    } catch (_) {
      return null;
    }
  }

  void setPng(String p, img.Image im) => files[p] = Uint8List.fromList(img.encodePng(im));

  /// Java `.properties` (OptiFine) as a map.
  Map<String, String>? properties(String p) {
    final t = text(p);
    if (t == null) return null;
    return parseProperties(t);
  }
}

String stripJsonComments(String s) {
  final out = StringBuffer();
  var inStr = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inStr) {
      out.write(c);
      if (c == r'\' && i + 1 < s.length) {
        out.write(s[++i]);
      } else if (c == '"') {
        inStr = false;
      }
      continue;
    }
    if (c == '"') {
      inStr = true;
      out.write(c);
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      out.write('\n');
    } else if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      i += 2;
      while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
        i++;
      }
      i++;
    } else {
      out.write(c);
    }
  }
  // trailing commas
  return out.toString().replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m.group(1)!);
}

Map<String, String> parseProperties(String t) {
  final m = <String, String>{};
  String? pending;
  for (var line in const LineSplitter().convert(t)) {
    if (pending != null) {
      line = pending + line.trimLeft();
      pending = null;
    }
    final l = line.trim();
    if (l.isEmpty || l.startsWith('#') || l.startsWith('!')) continue;
    if (l.endsWith(r'\') && !l.endsWith(r'\\')) {
      pending = l.substring(0, l.length - 1);
      continue;
    }
    final i = l.indexOf(RegExp(r'[=:]'));
    if (i < 0) {
      m[l] = '';
      continue;
    }
    m[l.substring(0, i).trim()] = _unescape(l.substring(i + 1).trim());
  }
  return m;
}

String _unescape(String v) => v.replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})|\\(.)'), (m) {
      if (m.group(1) != null) return String.fromCharCode(int.parse(m.group(1)!, radix: 16));
      return switch (m.group(2)) { 'n' => '\n', 't' => '\t', _ => m.group(2)! };
    });

String writeProperties(Map<String, String> m) => [for (final e in m.entries) '${e.key}=${e.value}'].join('\n');

/// One user-visible conversion note.
class ConvertNote {
  final String text;
  final bool warning;
  const ConvertNote(this.text, {this.warning = false});
}

/// Accumulates statistics while converting.
class ConvertLog {
  final notes = <ConvertNote>[];
  final counts = <String, int>{};
  void count(String k, [int n = 1]) => counts[k] = (counts[k] ?? 0) + n;
  void note(String t) => notes.add(ConvertNote(t));
  void warn(String t) => notes.add(ConvertNote(t, warning: true));
}
