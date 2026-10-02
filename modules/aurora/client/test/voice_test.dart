import 'dart:math';
import 'dart:typed_data';

import 'package:aurora_client/voice/voice.dart';
import 'package:flutter_test/flutter_test.dart';

Int16List _chunk(double Function(int i) f, int n, int offset) =>
    Int16List.fromList([for (var i = 0; i < n; i++) f(offset + i).round().clamp(-32768, 32767)]);

double _rms(Int16List x) => sqrt(x.fold<double>(0, (s, v) => s + v * v) / x.length);

void main() {
  test('mu-law round trip keeps speech-level signals within ~3%', () {
    for (final v in [0, 50, -50, 1000, -1000, 8000, -8000, 30000, -30000]) {
      final back = MuLaw.decode(MuLaw.encode(Int16List.fromList([v])))[0];
      expect((back - v).abs(), lessThanOrEqualTo(max(8, v.abs() * 0.03)), reason: 'v=$v back=$back');
    }
  });

  test('noise suppressor gates steady noise and passes speech', () {
    final rng = Random(1);
    final ns = NoiseSuppressor(2);
    double noise(int i) => (rng.nextDouble() - 0.5) * 600; // fan-like hiss, rms ~170
    // 2 s of noise only: learns the floor, should end up (nearly) silent
    var sentNoise = 0;
    var lastNoiseRms = 0.0;
    for (var c = 0; c < 50; c++) {
      final x = _chunk(noise, 640, c * 640);
      if (ns.process(x)) sentNoise++;
      lastNoiseRms = _rms(x);
    }
    expect(lastNoiseRms, lessThan(20), reason: 'noise should be gated');
    expect(sentNoise, lessThan(15), reason: 'noise frames should mostly not be transmitted');

    // speech-like tone burst on top of noise → must pass with most energy kept
    var passed = 0;
    var outRms = 0.0;
    for (var c = 0; c < 25; c++) {
      final x = _chunk((i) => noise(i) + 6000 * sin(2 * pi * 300 * i / 16000), 640, c * 640);
      if (ns.process(x)) passed++;
      outRms = _rms(x);
    }
    expect(passed, greaterThan(20));
    expect(outRms, greaterThan(2500), reason: 'speech should not be crushed');
  });

  test('level 0 passes everything', () {
    final ns = NoiseSuppressor(0);
    final x = _chunk((i) => 300 * sin(i / 3), 640, 0);
    expect(ns.process(x), isTrue);
  });
}
