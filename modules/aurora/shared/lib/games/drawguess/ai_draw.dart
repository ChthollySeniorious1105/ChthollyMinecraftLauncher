import '../../src/ai.dart';

/// Helpers shared by 你画我猜 / 传话画画 for LLM-driven drawing.

const int kAiMaxStrokes = 12;
const int kAiMaxPointsPerStroke = 60;

const String kAiDrawSystem = '你是一个简笔画画手，在 1000×1000 的画布上用线条作画（左上角为 0,0，右下角为 1000,1000）。'
    '画面要简单、清楚、一眼能认出，只画轮廓和最关键的特征，不要写任何文字、字母或数字。'
    '只输出一个 JSON：{"strokes": [[x1,y1,x2,y2,...], ...]}，每一笔是一串连续的坐标点（折线）。'
    '最多 $kAiMaxStrokes 笔，每笔最多 $kAiMaxPointsPerStroke 个点，坐标为 0~1000 的整数。圆形请用 12~20 个点近似。';

AiRequest aiDrawRequest(String subject) => AiRequest(
      system: kAiDrawSystem,
      prompt: '请画：「$subject」。画面居中，占画布的大部分。只输出 JSON。',
      maxTokens: 2500,
    );

/// Parses and validates a model drawing: at most [kAiMaxStrokes] strokes of
/// 2..[kAiMaxPointsPerStroke] points, numbers clamped to 0..1000. Bad strokes
/// are dropped; returns null when nothing usable remains.
List<List<int>>? parseAiStrokes(String? reply) {
  if (reply == null) return null;
  final raw = AiText.json(reply)?['strokes'];
  if (raw is! List) return null;
  final out = <List<int>>[];
  for (final s in raw) {
    if (out.length >= kAiMaxStrokes) break;
    if (s is! List || s.length < 4) continue;
    final pts = <int>[];
    var ok = true;
    for (final v in s) {
      if (v is! num || !v.isFinite) {
        ok = false;
        break;
      }
      pts.add(v.round().clamp(0, 1000));
    }
    if (!ok) continue;
    if (pts.length.isOdd) pts.removeLast();
    if (pts.length > kAiMaxPointsPerStroke * 2) pts.length = kAiMaxPointsPerStroke * 2;
    if (pts.length >= 4) out.add(pts);
  }
  return out.isEmpty ? null : out;
}

/// Cleans a one-line model answer; null if unusable (empty, JSON, too long).
String? aiLine(String? reply, int maxLen) {
  if (reply == null) return null;
  final t = AiText.firstLine(reply, maxLen: 1000).replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t.runes.length > maxLen || t.contains('{') || t.contains('}')) return null;
  return t;
}
