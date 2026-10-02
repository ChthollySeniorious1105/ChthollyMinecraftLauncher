import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// NBT tag ids.
abstract class TagId {
  static const end = 0, byte = 1, short = 2, int_ = 3, long = 4, float = 5, double_ = 6;
  static const byteArray = 7, string = 8, list = 9, compound = 10, intArray = 11, longArray = 12;
}

/// Base NBT tag. Values are mutable so callers can edit level.dat etc. in place.
sealed class Tag {
  int get id;
  Object? get plain;
}

class ByteTag extends Tag {
  int value;
  ByteTag(this.value);
  @override
  int get id => TagId.byte;
  @override
  Object get plain => value;
}

class ShortTag extends Tag {
  int value;
  ShortTag(this.value);
  @override
  int get id => TagId.short;
  @override
  Object get plain => value;
}

class IntTag extends Tag {
  int value;
  IntTag(this.value);
  @override
  int get id => TagId.int_;
  @override
  Object get plain => value;
}

class LongTag extends Tag {
  int value;
  LongTag(this.value);
  @override
  int get id => TagId.long;
  @override
  Object get plain => value;
}

class FloatTag extends Tag {
  double value;
  FloatTag(this.value);
  @override
  int get id => TagId.float;
  @override
  Object get plain => value;
}

class DoubleTag extends Tag {
  double value;
  DoubleTag(this.value);
  @override
  int get id => TagId.double_;
  @override
  Object get plain => value;
}

class ByteArrayTag extends Tag {
  Uint8List value;
  ByteArrayTag(this.value);
  @override
  int get id => TagId.byteArray;
  @override
  Object get plain => value;
}

class StringTag extends Tag {
  String value;
  StringTag(this.value);
  @override
  int get id => TagId.string;
  @override
  Object get plain => value;
}

class ListTag extends Tag {
  int elementId;
  final List<Tag> value;
  ListTag(this.elementId, [List<Tag>? v]) : value = v ?? [];
  @override
  int get id => TagId.list;
  @override
  Object get plain => [for (final t in value) t.plain];
  int get length => value.length;
  Tag operator [](int i) => value[i];
  void add(Tag t) {
    if (value.isEmpty) elementId = t.id;
    value.add(t);
  }
}

class CompoundTag extends Tag {
  final Map<String, Tag> value;
  CompoundTag([Map<String, Tag>? v]) : value = v ?? {};
  @override
  int get id => TagId.compound;
  @override
  Object get plain => {for (final e in value.entries) e.key: e.value.plain};

  Tag? operator [](String k) => value[k];
  void operator []=(String k, Tag v) => value[k] = v;
  bool has(String k) => value.containsKey(k);
  Tag? remove(String k) => value.remove(k);

  int? getInt(String k) => switch (value[k]) {
        ByteTag t => t.value,
        ShortTag t => t.value,
        IntTag t => t.value,
        LongTag t => t.value,
        _ => null,
      };
  String? getString(String k) => (value[k] as StringTag?)?.value;
  CompoundTag? getCompound(String k) => value[k] is CompoundTag ? value[k] as CompoundTag : null;
  ListTag? getList(String k) => value[k] is ListTag ? value[k] as ListTag : null;
  Uint8List? getBytes(String k) => (value[k] is ByteArrayTag) ? (value[k] as ByteArrayTag).value : null;
  Int32List? getInts(String k) => (value[k] is IntArrayTag) ? (value[k] as IntArrayTag).value : null;
  Int64List? getLongs(String k) => (value[k] is LongArrayTag) ? (value[k] as LongArrayTag).value : null;

  /// Walks a dotted path like `Data.Version.Name`.
  Tag? at(String path) {
    Tag? cur = this;
    for (final part in path.split('.')) {
      if (cur is! CompoundTag) return null;
      cur = cur.value[part];
    }
    return cur;
  }
}

class IntArrayTag extends Tag {
  Int32List value;
  IntArrayTag(this.value);
  @override
  int get id => TagId.intArray;
  @override
  Object get plain => value;
}

class LongArrayTag extends Tag {
  Int64List value;
  LongArrayTag(this.value);
  @override
  int get id => TagId.longArray;
  @override
  Object get plain => value;
}

/// A named root tag.
class NamedTag {
  final String name;
  final CompoundTag tag;
  NamedTag(this.name, this.tag);
}

/// Byte order / variant of NBT encoding.
enum NbtFlavor {
  /// Java Edition (big-endian).
  java,

  /// Bedrock Edition files (little-endian: level.dat, .mcstructure, LevelDB values).
  bedrock,
}

/// NBT reader. Supports gzip/zlib detection via [Nbt.decodeAuto].
class NbtReader {
  final ByteData _d;
  final Uint8List _b;
  final Endian _e;
  int pos;
  NbtReader(Uint8List bytes, NbtFlavor flavor, [this.pos = 0])
      : _b = bytes,
        _d = ByteData.sublistView(bytes),
        _e = flavor == NbtFlavor.java ? Endian.big : Endian.little;

  bool get atEnd => pos >= _b.length;

  int _u8() => _b[pos++];
  int _i8() => _d.getInt8(pos++);
  int _i16() {
    final v = _d.getInt16(pos, _e);
    pos += 2;
    return v;
  }

  int _u16() {
    final v = _d.getUint16(pos, _e);
    pos += 2;
    return v;
  }

  int _i32() {
    final v = _d.getInt32(pos, _e);
    pos += 4;
    return v;
  }

  int _i64() {
    final v = _d.getInt64(pos, _e);
    pos += 8;
    return v;
  }

  double _f32() {
    final v = _d.getFloat32(pos, _e);
    pos += 4;
    return v;
  }

  double _f64() {
    final v = _d.getFloat64(pos, _e);
    pos += 8;
    return v;
  }

  String _str() {
    final n = _u16();
    final s = _decodeMutf8(Uint8List.sublistView(_b, pos, pos + n));
    pos += n;
    return s;
  }

  NamedTag readRoot() {
    final id = _u8();
    if (id != TagId.compound) throw FormatException('NBT root is not a compound (id=$id)');
    final name = _str();
    return NamedTag(name, _payload(id, 0) as CompoundTag);
  }

  Tag _payload(int id, int depth) {
    if (depth > 512) throw const FormatException('NBT too deep');
    switch (id) {
      case TagId.byte:
        return ByteTag(_i8());
      case TagId.short:
        return ShortTag(_i16());
      case TagId.int_:
        return IntTag(_i32());
      case TagId.long:
        return LongTag(_i64());
      case TagId.float:
        return FloatTag(_f32());
      case TagId.double_:
        return DoubleTag(_f64());
      case TagId.byteArray:
        final n = _len();
        final v = Uint8List.fromList(Uint8List.sublistView(_b, pos, pos + n));
        pos += n;
        return ByteArrayTag(v);
      case TagId.string:
        return StringTag(_str());
      case TagId.list:
        final el = _u8();
        final n = _len();
        final l = ListTag(el);
        for (var i = 0; i < n; i++) {
          l.value.add(_payload(el, depth + 1));
        }
        return l;
      case TagId.compound:
        final c = CompoundTag();
        while (true) {
          final t = _u8();
          if (t == TagId.end) break;
          final name = _str();
          c.value[name] = _payload(t, depth + 1);
        }
        return c;
      case TagId.intArray:
        final n = _len();
        final v = Int32List(n);
        for (var i = 0; i < n; i++) {
          v[i] = _i32();
        }
        return IntArrayTag(v);
      case TagId.longArray:
        final n = _len();
        final v = Int64List(n);
        for (var i = 0; i < n; i++) {
          v[i] = _i64();
        }
        return LongArrayTag(v);
      default:
        throw FormatException('Unknown NBT tag id $id at $pos');
    }
  }

  int _len() {
    final n = _i32();
    if (n < 0 || n > _b.length) throw const FormatException('Bad NBT length');
    return n;
  }
}

class NbtWriter {
  final BytesBuilder _out = BytesBuilder();
  final Endian _e;
  final _scratch = ByteData(8);
  NbtWriter(NbtFlavor flavor) : _e = flavor == NbtFlavor.java ? Endian.big : Endian.little;

  Uint8List takeBytes() => _out.takeBytes();

  void _u8(int v) => _out.addByte(v & 0xff);
  void _i16(int v) {
    _scratch.setInt16(0, v, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 2)));
  }

  void _i32(int v) {
    _scratch.setInt32(0, v, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 4)));
  }

  void _i64(int v) {
    _scratch.setInt64(0, v, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 8)));
  }

  void _f32(double v) {
    _scratch.setFloat32(0, v, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 4)));
  }

  void _f64(double v) {
    _scratch.setFloat64(0, v, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 8)));
  }

  void _str(String s) {
    final b = _encodeMutf8(s);
    _scratch.setUint16(0, b.length, _e);
    _out.add(Uint8List.fromList(Uint8List.sublistView(_scratch, 0, 2)));
    _out.add(b);
  }

  void writeRoot(String name, CompoundTag tag) {
    _u8(TagId.compound);
    _str(name);
    _payload(tag);
  }

  void _payload(Tag t) {
    switch (t) {
      case ByteTag t:
        _u8(t.value);
      case ShortTag t:
        _i16(t.value);
      case IntTag t:
        _i32(t.value);
      case LongTag t:
        _i64(t.value);
      case FloatTag t:
        _f32(t.value);
      case DoubleTag t:
        _f64(t.value);
      case ByteArrayTag t:
        _i32(t.value.length);
        _out.add(t.value);
      case StringTag t:
        _str(t.value);
      case ListTag t:
        _u8(t.value.isEmpty ? (t.elementId == 0 ? TagId.end : t.elementId) : t.value.first.id);
        _i32(t.value.length);
        for (final e in t.value) {
          _payload(e);
        }
      case CompoundTag t:
        for (final e in t.value.entries) {
          _u8(e.value.id);
          _str(e.key);
          _payload(e.value);
        }
        _u8(TagId.end);
      case IntArrayTag t:
        _i32(t.value.length);
        for (final v in t.value) {
          _i32(v);
        }
      case LongArrayTag t:
        _i32(t.value.length);
        for (final v in t.value) {
          _i64(v);
        }
    }
  }
}

enum NbtCompression { none, gzip, zlib }

abstract class Nbt {
  static NamedTag decode(Uint8List bytes, {NbtFlavor flavor = NbtFlavor.java}) => NbtReader(bytes, flavor).readRoot();

  static Uint8List encode(CompoundTag tag, {String name = '', NbtFlavor flavor = NbtFlavor.java}) =>
      (NbtWriter(flavor)..writeRoot(name, tag)).takeBytes();

  static NbtCompression detect(Uint8List b) {
    if (b.length >= 2 && b[0] == 0x1f && b[1] == 0x8b) return NbtCompression.gzip;
    if (b.length >= 2 && b[0] == 0x78 && (b[0] * 256 + b[1]) % 31 == 0) return NbtCompression.zlib;
    return NbtCompression.none;
  }

  static Uint8List decompress(Uint8List b) => switch (detect(b)) {
        NbtCompression.gzip => Uint8List.fromList(const GZipDecoder().decodeBytes(b)),
        NbtCompression.zlib => Uint8List.fromList(const ZLibDecoder().decodeBytes(b)),
        NbtCompression.none => b,
      };

  static Uint8List compress(Uint8List b, NbtCompression c) => switch (c) {
        NbtCompression.gzip => Uint8List.fromList(const GZipEncoder().encodeBytes(b)),
        NbtCompression.zlib => Uint8List.fromList(const ZLibEncoder().encodeBytes(b)),
        NbtCompression.none => b,
      };

  /// Decodes possibly-compressed Java NBT.
  static NamedTag decodeAuto(Uint8List bytes, {NbtFlavor flavor = NbtFlavor.java}) => decode(decompress(bytes), flavor: flavor);

  /// Bedrock level.dat: 4-byte storage version + 4-byte length header, then little-endian NBT.
  static (int, NamedTag) decodeBedrockLevelDat(Uint8List b) {
    final d = ByteData.sublistView(b);
    final version = d.getInt32(0, Endian.little);
    return (version, NbtReader(b, NbtFlavor.bedrock, 8).readRoot());
  }

  static Uint8List encodeBedrockLevelDat(int storageVersion, NamedTag root) {
    final body = encode(root.tag, name: root.name, flavor: NbtFlavor.bedrock);
    final out = Uint8List(8 + body.length);
    final d = ByteData.sublistView(out);
    d.setInt32(0, storageVersion, Endian.little);
    d.setInt32(4, body.length, Endian.little);
    out.setRange(8, out.length, body);
    return out;
  }

  /// Reads consecutive little-endian root compounds (Bedrock LevelDB values like block palettes).
  static List<NamedTag> decodeMany(Uint8List b, {NbtFlavor flavor = NbtFlavor.bedrock}) {
    final r = NbtReader(b, flavor);
    final out = <NamedTag>[];
    while (!r.atEnd) {
      out.add(r.readRoot());
    }
    return out;
  }
}

// Java's "modified UTF-8": NUL as C0 80, supplementary chars as surrogate pairs.
Uint8List _encodeMutf8(String s) {
  final out = BytesBuilder();
  for (final c in s.codeUnits) {
    if (c != 0 && c < 0x80) {
      out.addByte(c);
    } else if (c < 0x800) {
      out.addByte(0xC0 | (c >> 6));
      out.addByte(0x80 | (c & 0x3F));
    } else {
      out.addByte(0xE0 | (c >> 12));
      out.addByte(0x80 | ((c >> 6) & 0x3F));
      out.addByte(0x80 | (c & 0x3F));
    }
  }
  return out.takeBytes();
}

String _decodeMutf8(Uint8List b) {
  // fast path: plain ASCII
  var ascii = true;
  for (final x in b) {
    if (x >= 0x80 || x == 0) {
      ascii = false;
      break;
    }
  }
  if (ascii) return String.fromCharCodes(b);
  final units = <int>[];
  var i = 0;
  while (i < b.length) {
    final x = b[i];
    if (x < 0x80) {
      units.add(x);
      i++;
    } else if ((x & 0xE0) == 0xC0 && i + 1 < b.length) {
      units.add(((x & 0x1F) << 6) | (b[i + 1] & 0x3F));
      i += 2;
    } else if ((x & 0xF0) == 0xE0 && i + 2 < b.length) {
      units.add(((x & 0x0F) << 12) | ((b[i + 1] & 0x3F) << 6) | (b[i + 2] & 0x3F));
      i += 3;
    } else if ((x & 0xF8) == 0xF0 && i + 3 < b.length) {
      // Bedrock writes real UTF-8 4-byte sequences
      final cp = ((x & 0x07) << 18) | ((b[i + 1] & 0x3F) << 12) | ((b[i + 2] & 0x3F) << 6) | (b[i + 3] & 0x3F);
      units.addAll(String.fromCharCode(cp).codeUnits);
      i += 4;
    } else {
      units.add(0xFFFD);
      i++;
    }
  }
  return String.fromCharCodes(units);
}

/// Debug helper: SNBT-ish dump.
String nbtToJson(Tag t) => const JsonEncoder.withIndent('  ', _toEncodable).convert(t.plain);
Object? _toEncodable(Object? o) => o is TypedData ? (o as List).toList() : o.toString();
