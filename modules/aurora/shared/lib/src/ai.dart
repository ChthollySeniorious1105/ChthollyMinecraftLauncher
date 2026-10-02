import 'dart:convert';
import 'dart:typed_data';

import 'strokes.dart';

/// An image attached to an LLM request.
class AiImage {
  final String mediaType;
  final Uint8List bytes;
  const AiImage(this.mediaType, this.bytes);
  String get base64Data => base64.encode(bytes);

  /// Rasterise 你画我猜-style strokes ({'c': argb, 'w': width, 'p': [x0,y0,x1,y1…]}
  /// in 0..1000 canvas units) into a white-background PNG of [size]×[size].
  factory AiImage.fromStrokes(List<Map<String, dynamic>> strokes, {int size = 256}) {
    final r = StrokeRaster(size, size, unit: size / 1000);
    for (final s in strokes) {
      final p = s['p'];
      if (p is! List || p.length < 2) continue;
      r.add(s['c'] is int ? s['c'] as int : 0xFF000000, s['w'] is num ? (s['w'] as num).toInt() : 6,
          [for (final v in p) (v as num).toInt()]);
    }
    final px = Uint8List(size * size * 3);
    for (var i = 0; i < size * size; i++) {
      final c = r.px[i];
      px[i * 3] = (c >> 16) & 0xFF;
      px[i * 3 + 1] = (c >> 8) & 0xFF;
      px[i * 3 + 2] = c & 0xFF;
    }
    return AiImage('image/png', encodePngRgb(px, size, size));
  }
}

/// One LLM call: a system prompt, a user prompt and optional images.
class AiRequest {
  final String system;
  final String prompt;
  final List<AiImage> images;
  final int maxTokens;
  const AiRequest({required this.system, required this.prompt, this.images = const [], this.maxTokens = 400});
}

/// LLM access provided by the server (configured in `.env`). Engines use it
/// through [AiSlot] from inside bot(); they must always have a non-AI
/// fallback because the service may be missing, slow, rate-limited or fail.
abstract class AiService {
  bool get available;

  /// Whether image input is supported (AI_VISION in .env). When false, don't
  /// build image requests — use a text-only strategy or the heuristic.
  bool get vision => true;

  /// Human readable provider/model, e.g. "anthropic · claude-opus-5".
  String get label;

  /// Returns the model's text reply, or null on any failure. Never throws.
  Future<String?> complete(AiRequest req);

}

/// Deterministic fake used by the simulator/tests: cycles through failure,
/// junk and plausible-looking replies so engines prove they validate and fall
/// back correctly. Every reply is synchronous.
class FakeAi extends AiService {
  int _n;
  final List<AiRequest> requests = [];
  FakeAi([int seed = 0]) : _n = seed;
  @override
  bool get available => true;
  @override
  String get label => 'fake';
  @override
  Future<String?> complete(AiRequest req) async => completeNow(req);

  static const _replies = <String?>[
    null,
    '苹果',
    '{"answer":"是","text":"我觉得是一种水果","clue":"水果","number":2,"target":1,"words":["苹果","香蕉"]}',
    '',
    '好的！我的回答是：\n「大象」',
    '{"broken json',
    '1',
    '我不知道。这是一个非常非常长的回答，' '超过了任何合理的长度限制，用来测试引擎是否正确截断或拒绝过长的文本输入内容，' '以免把奇怪的东西发到聊天或视图里。',
    '{"x":1,"y":2,"strokes":[[100,100,200,200,300,100]]}',
    '否',
  ];

  String? completeNow(AiRequest req) {
    requests.add(req);
    return _replies[_n++ % _replies.length];
  }
}

/// Result of [AiSlot.poll].
class AiPoll {
  /// Still waiting for the model: bot() should return null and try again later.
  final bool pending;

  /// Model reply (null = failed / timed out → use your heuristic fallback).
  final String? text;
  const AiPoll._(this.pending, this.text);
  static const waiting = AiPoll._(true, null);
}

/// One in-flight LLM request per engine decision, keyed by a string that
/// identifies the decision (e.g. `'guess:3:seat2'`). Typical bot() usage:
///
/// ```dart
/// if (aiOn) {
///   final r = _ai.poll(setup.ai!, 'desc:$round:$seat', () => AiRequest(system: …, prompt: …));
///   if (r.pending) return null;          // server re-asks the bot shortly
///   final t = r.text;
///   if (t != null) return {'type': 'describe', 'text': clean(t)};
/// }
/// return heuristicMove();
/// ```
///
/// Replies arrive asynchronously; the engine only reads them inside bot(), so
/// all state changes still go through handle().
class AiSlot {
  final Map<String, _Pending> _jobs = {};
  final int timeoutMs;
  AiSlot({this.timeoutMs = 25000});

  AiPoll poll(AiService ai, String key, AiRequest Function() build) {
    var j = _jobs[key];
    if (j == null) {
      if (_jobs.length > 64) _jobs.clear();
      final req = build();
      if (ai is FakeAi) {
        final t = ai.completeNow(req);
        _jobs[key] = _Pending(0)
          ..done = true
          ..text = t;
        return AiPoll._(false, t);
      }
      j = _jobs[key] = _Pending(DateTime.now().millisecondsSinceEpoch);
      final job = j;
      ai.complete(req).then((t) {
        job.text = t;
        job.done = true;
      }, onError: (_) {
        job.done = true;
      });
    }
    if (j.done) return AiPoll._(false, j.text);
    if (DateTime.now().millisecondsSinceEpoch - j.started > timeoutMs) return const AiPoll._(false, null);
    return AiPoll.waiting;
  }

  /// Start a request now (e.g. when a phase begins) so the answer is ready by
  /// the time bot() asks for it.
  void prefetch(AiService ai, String key, AiRequest Function() build) => poll(ai, key, build);

  void clear() => _jobs.clear();
}

class _Pending {
  final int started;
  bool done = false;
  String? text;
  _Pending(this.started);
}

/// Helpers for parsing model replies.
abstract class AiText {
  /// First line, trimmed, without surrounding quotes/brackets/punctuation.
  static String firstLine(String s, {int maxLen = 40}) {
    var t = s.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
    t = t.replaceAll(RegExp(r'^[「『“"\x27《【\[(（]+|[」』”"\x27》】\])）。.!！]+$'), '').trim();
    return t.length > maxLen ? t.substring(0, maxLen) : t;
  }

  /// Extract the first JSON object in [s] (models sometimes wrap it in ```json).
  static Map<String, dynamic>? json(String s) {
    final a = s.indexOf('{'), b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    try {
      final v = jsonDecode(s.substring(a, b + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------- tiny PNG

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _crc(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Encode 8-bit RGB pixels as PNG (zlib "stored" blocks: no compression
/// library needed, fine for small images).
Uint8List encodePngRgb(Uint8List rgb, int w, int h) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgb, y * w * 3, (y + 1) * w * 3));
  }
  final data = raw.takeBytes();
  final z = BytesBuilder()..add([0x78, 0x01]);
  var off = 0;
  while (off < data.length || off == 0) {
    final n = (data.length - off).clamp(0, 65535);
    final last = off + n >= data.length;
    z.addByte(last ? 1 : 0);
    z.add([n & 0xFF, n >> 8, (~n) & 0xFF, ((~n) >> 8) & 0xFF]);
    z.add(Uint8List.sublistView(data, off, off + n));
    off += n;
    if (last) break;
  }
  var a = 1, b = 0;
  for (final v in data) {
    a = (a + v) % 65521;
    b = (b + a) % 65521;
  }
  z.add([b >> 8, b & 0xFF, a >> 8, a & 0xFF]);

  final out = BytesBuilder()..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> body) {
    final len = body.length;
    out.add([len >> 24, (len >> 16) & 0xFF, (len >> 8) & 0xFF, len & 0xFF]);
    final tb = [...ascii.encode(type), ...body];
    out.add(tb);
    final c = _crc(tb);
    out.add([c >> 24, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF]);
  }

  chunk('IHDR', [w >> 24, (w >> 16) & 0xFF, (w >> 8) & 0xFF, w & 0xFF, h >> 24, (h >> 16) & 0xFF, (h >> 8) & 0xFF, h & 0xFF, 8, 2, 0, 0, 0]);
  chunk('IDAT', z.takeBytes());
  chunk('IEND', const []);
  return out.takeBytes();
}
