import '../../src/engine.dart';
import '../../src/protocol.dart' show sanitizeText;

/// Shared helpers for the party3 word games.

const OptionDef kAiOption =
    OptionDef('ai', 'AI 电脑', [OptionChoice(false, '关'), OptionChoice(true, '开（大模型扮演电脑玩家）')], false);

int p3Now() => DateTime.now().millisecondsSinceEpoch;

final RegExp _punct = RegExp(r'[\s　，。！？；：、,.!?;:“”‘’"\x27`~·…—\-_（）()【】\[\]{}《》<>「」『』/\\|]+');
final RegExp _hanOnly = RegExp(r'^[一-鿿]+$');

bool isHan(String s) => s.isNotEmpty && _hanOnly.hasMatch(s);

/// Full-width → half-width, lowercase, no whitespace / punctuation.
String p3Norm(String s) {
  final b = StringBuffer();
  for (final r in sanitizeText(s).runes) {
    var c = r;
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    if (c == 0x3000) c = 0x20;
    b.writeCharCode(c);
  }
  return b.toString().toLowerCase().replaceAll(_punct, '');
}

/// Split a sentence on punctuation / whitespace into non-empty segments.
List<String> p3Segments(String s) =>
    [for (final t in sanitizeText(s).split(_punct)) if (t.trim().isNotEmpty) t.trim()];

/// Clean user / model text for display: single spaces, trimmed, clipped.
String p3Clean(String s, int max) {
  final t = sanitizeText(s).replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > max ? t.substring(0, max) : t;
}

bool shareChar(String a, String b) {
  final sa = a.runes.where((r) => r > 0x2E80).toSet();
  return b.runes.any(sa.contains);
}

/// Ranking rows [{'s','score','rank'}] from a sort key (higher = better).
List<Map<String, dynamic>> p3Ranking(List<int> seats, num Function(int) key, int Function(int) score) {
  final order = List.of(seats)..sort((a, b) => key(b) != key(a) ? key(b).compareTo(key(a)) : a - b);
  final out = <Map<String, dynamic>>[];
  var rank = 0;
  for (var i = 0; i < order.length; i++) {
    if (i == 0 || key(order[i]) != key(order[i - 1])) rank = i + 1;
    out.add({'s': order[i], 'score': score(order[i]), 'rank': rank});
  }
  return out;
}

/// Epoch-guarded timers on top of [GameHost.schedule]: [cancel] drops every
/// pending callback (a stale timer never fires into a later turn).
class P3Timers {
  int _epoch = 0;
  final List<void Function()> _cancels = [];
  void cancel() {
    _epoch++;
    for (final c in _cancels) {
      c();
    }
    _cancels.clear();
  }

  void after(GameHost host, int ms, void Function() fn) {
    final ep = _epoch;
    _cancels.add(host.schedule(ms, () {
      if (ep == _epoch) fn();
    }));
  }

  /// Fires [fn] after [ms], split into [stepMs] ticks. Chaining ticks
  /// (instead of one long timer) means hosts that run callbacks eagerly
  /// (simulator, tests) still give players several actions before the
  /// deadline hits.
  void countdown(GameHost host, int ms, void Function() fn, {int stepMs = 5000}) {
    var left = ms;
    void tick() {
      left -= stepMs;
      if (left <= 0) {
        fn();
      } else {
        after(host, left < stepMs ? left : stepMs, tick);
      }
    }

    after(host, ms < stepMs ? ms : stepMs, tick);
  }
}

/// Parse "a|b|c" lines (half/full-width bar), skipping comments / blanks.
List<List<String>> p3Lines(String data) => [
      for (final raw in data.split('\n'))
        if (raw.trim().isNotEmpty && !raw.trim().startsWith('#') && !raw.trim().startsWith('//'))
          [for (final p in raw.trim().split(RegExp(r'[|｜]'))) p.trim()],
    ];
