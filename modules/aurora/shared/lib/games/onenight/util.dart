import '../../src/engine.dart' show GameHost;
import '../../src/protocol.dart' show sanitizeText;

/// Wall-clock epoch ms (used for client countdowns; the real timers are host.schedule).
int onNow() => DateTime.now().millisecondsSinceEpoch;

/// Sanitize free text from a client: strip control/bidi chars, collapse
/// whitespace, cap length (in runes).
String onCleanText(Object? raw, int maxLen) {
  if (raw is! String) return '';
  var t = sanitizeText(raw).replaceAll(RegExp(r'\s+'), ' ').trim();
  final runes = t.runes.toList();
  if (runes.length > maxLen) t = String.fromCharCodes(runes.take(maxLen));
  return t;
}

/// Mission team sizes shared by 抵抗组织 (same table as the base game).
const resistanceMissionSizes = {
  5: [2, 3, 2, 3, 3],
  6: [2, 3, 4, 3, 4],
  7: [2, 3, 3, 4, 4],
  8: [3, 4, 4, 5, 5],
  9: [3, 4, 4, 5, 5],
  10: [3, 4, 4, 5, 5],
};

const resistanceSpyCount = {5: 2, 6: 2, 7: 3, 8: 3, 9: 3, 10: 4};

/// A countdown driven by host.schedule ticks that compare against the wall
/// clock, so it only fires when real time has passed. Hosts that run callbacks
/// instantly (simulator / tests) are detected (a tick arriving after far less
/// than the requested delay) and the clock simply stops re-arming there; games
/// must be able to finish through player actions alone.
class OnClock {
  int endsAt = 0;
  int _epoch = 0;

  bool get running => endsAt > 0;

  void start(GameHost host, int ms, void Function() onExpire) {
    stop();
    endsAt = onNow() + ms;
    final ep = _epoch;
    void arm(int delay) {
      final armedAt = onNow();
      host.schedule(delay, () {
        if (ep != _epoch) return;
        final now = onNow();
        if (now - armedAt < delay ~/ 2) return; // instant host: never expire
        final left = endsAt - now;
        if (left <= 200) {
          endsAt = 0;
          _epoch++;
          onExpire();
          return;
        }
        arm(left > 15000 ? 15000 : left);
      });
    }

    arm(ms > 15000 ? 15000 : ms);
  }

  /// Stop the clock; returns remaining ms (0 if not running).
  int stop() {
    final left = endsAt > 0 ? endsAt - onNow() : 0;
    endsAt = 0;
    _epoch++;
    return left < 0 ? 0 : left;
  }
}
