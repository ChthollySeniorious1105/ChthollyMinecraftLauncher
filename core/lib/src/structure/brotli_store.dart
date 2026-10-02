import 'dart:typed_data';

/// Minimal Brotli *encoder* (RFC 7932) that emits uncompressed meta-blocks.
/// Output is a valid Brotli stream (decodable by any Brotli decoder), just not smaller.
/// Used for writing BDX files; the `brotli` package only decodes.
Uint8List brotliStore(List<int> data) {
  final w = _BitWriter();
  w.bits(0, 1); // WBITS = 16
  const chunk = 1 << 16;
  for (var off = 0; off < data.length; off += chunk) {
    final len = (data.length - off).clamp(0, chunk);
    w.bits(0, 1); // ISLAST = 0
    w.bits(0, 2); // MNIBBLES = 4
    w.bits(len - 1, 16); // MLEN - 1
    w.bits(1, 1); // ISUNCOMPRESSED
    w.align();
    w.bytes(data, off, off + len);
  }
  w.bits(1, 1); // ISLAST
  w.bits(1, 1); // ISLASTEMPTY
  w.align();
  return w.take();
}

class _BitWriter {
  final _out = BytesBuilder();
  int _acc = 0, _n = 0;

  void bits(int v, int count) {
    for (var i = 0; i < count; i++) {
      _acc |= ((v >> i) & 1) << _n;
      if (++_n == 8) {
        _out.addByte(_acc);
        _acc = 0;
        _n = 0;
      }
    }
  }

  void align() {
    if (_n > 0) {
      _out.addByte(_acc);
      _acc = 0;
      _n = 0;
    }
  }

  void bytes(List<int> d, int start, int end) => _out.add(d is Uint8List ? Uint8List.sublistView(d, start, end) : d.sublist(start, end));

  Uint8List take() => _out.takeBytes();
}
