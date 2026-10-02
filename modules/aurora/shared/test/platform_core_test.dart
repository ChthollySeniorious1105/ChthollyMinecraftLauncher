import 'dart:convert';
import 'dart:math';

import 'package:aurora_shared/aurora_shared.dart';
import 'package:test/test.dart';

void main() {
  test('json diff/patch round trip', () {
    final r = Random(3);
    Object? gen(int d) {
      final k = r.nextInt(d > 3 ? 4 : 7);
      if (k == 0) return r.nextInt(5);
      if (k == 1) return 'x${r.nextInt(3)}';
      if (k == 2) return r.nextBool();
      if (k == 3) return null;
      if (k == 4) return [for (var i = 0; i < r.nextInt(5); i++) gen(d + 1)];
      return {for (var i = 0; i < r.nextInt(5); i++) 'k${r.nextInt(6)}': gen(d + 1)};
    }

    Object? a = gen(0);
    for (var i = 0; i < 3000; i++) {
      final b = gen(0);
      final d = jsonDiff(a, b);
      final p = identical(d, jsonSame) ? a : jsonPatch(a, jsonDecode(jsonEncode(d)));
      expect(p, equals(b));
      a = b;
    }
  });

  test('recorder + replay', () {
    final rec = ReplayRecorder(2, minGapMs: 0);
    for (var i = 0; i < 50; i++) {
      rec.add(0, {'n': i, 'list': List.generate(i % 7, (j) => j), 'm': {'a': i ~/ 3}});
      rec.add(-1, {'n': i});
    }
    final doc = rec.finish((d) => ReplayMeta(
        id: 'x', game: 'g', gameName: 'G', startedAt: 0, durationMs: d, names: ['a', 'b'], avatars: [1, 2],
        bots: [false, true], options: {}, uids: ['', ''], ranking: [1, 2], room: 'R'));
    final rp = Replay.fromJson(jsonDecode(jsonEncode(doc)) as Map<String, dynamic>);
    final f = rp.frames(0);
    expect(f.last.$2['n'], 49);
    expect(f.last.$2['list'], []);
    expect(f[20].$2['list'], [0, 1, 2, 3, 4, 5]);
    expect(rp.frames(-1).last.$2['n'], 49);
  });

  test('png', () {
    final img = AiImage.fromStrokes([
      {'c': 0xFF000000, 'w': 8, 'p': [100, 100, 900, 900]}
    ], size: 64);
    expect(img.bytes.sublist(1, 4), ascii.encode('PNG'));
  });

  test('welcome game list fits in one frame with room to grow', () {
    final n = utf8.encode(jsonEncode([for (final g in gameRegistry) g.toJson()])).length;
    expect(n, lessThan(kMaxFrame ~/ 2), reason: 'GameDef.toJson too large ($n bytes)');
    for (final g in gameRegistry) {
      expect(g.rules.trim().length, greaterThanOrEqualTo(150), reason: '${g.id} rules');
    }
  });

  test('rank helpers', () {
    expect(rankByScore([3, 5, 5, 1]), [3, 1, 1, 4]);
    expect(rankWinners(3, [1]), [2, 1, 2]);
  });
}
