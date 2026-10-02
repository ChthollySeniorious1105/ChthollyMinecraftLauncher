import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// One shared SoLoud initialisation for voice playback and sound effects.
/// Returns false (never throws) when audio output is unavailable.
Future<bool>? _soloudInit;
Future<bool> ensureSoLoud() {
  return _soloudInit ??= () async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init(sampleRate: 48000, bufferSize: 1024, channels: Channels.stereo);
      }
      return true;
    } catch (_) {
      _soloudInit = null; // allow a later retry
      return false;
    }
  }();
}

/// True under `flutter test`: never touch the audio plugin there.
final bool kUnderTest = Platform.environment.containsKey('FLUTTER_TEST');

enum SfxKind { turn, start, win, lose, over, emote, tick }

/// Short synthesized UI sounds (no asset files): tones generated as 16-bit
/// PCM WAV in memory and loaded into SoLoud once.
class Sfx {
  bool enabled = true;
  double volume = 0.7;

  final Map<SfxKind, AudioSource> _cache = {};
  final Map<SfxKind, DateTime> _last = {};
  bool _failed = false;
  bool _loading = false;

  /// Plays [kind]; silently does nothing when disabled or audio is broken.
  void play(SfxKind kind) {
    if (!enabled || volume <= 0 || _failed || kUnderTest) return;
    final now = DateTime.now();
    final last = _last[kind];
    if (last != null && now.difference(last).inMilliseconds < 120) return; // de-bounce bursts
    _last[kind] = now;
    unawaited(_play(kind));
  }

  Future<void> _play(SfxKind kind) async {
    try {
      if (!await ensureSoLoud()) return;
      var src = _cache[kind];
      if (src == null) {
        if (_loading) return;
        _loading = true;
        try {
          src = await SoLoud.instance.loadMem('aurora_sfx_${kind.name}.wav', wavFor(kind));
          _cache[kind] = src;
        } finally {
          _loading = false;
        }
      }
      SoLoud.instance.play(src, volume: volume * (kind == SfxKind.tick ? 0.35 : 1.0));
    } catch (_) {
      _failed = true;
    }
  }

  /// Note lists: (frequency Hz, duration ms, gain).
  static List<(double, int, double)> notes(SfxKind k) => switch (k) {
        SfxKind.turn => const [(880, 90, 0.5), (1318.5, 160, 0.5)],
        SfxKind.start => const [(523.25, 90, 0.45), (659.25, 90, 0.45), (783.99, 180, 0.45)],
        SfxKind.win => const [(523.25, 110, 0.5), (659.25, 110, 0.5), (783.99, 110, 0.5), (1046.5, 360, 0.55)],
        SfxKind.lose => const [(392, 170, 0.45), (329.63, 170, 0.45), (261.63, 360, 0.45)],
        SfxKind.over => const [(659.25, 140, 0.4), (523.25, 260, 0.4)],
        SfxKind.emote => const [(1200, 55, 0.4), (1600, 45, 0.3)],
        SfxKind.tick => const [(620, 35, 0.3)],
      };

  /// Mono 16-bit 22.05 kHz WAV for a sound kind.
  static Uint8List wavFor(SfxKind k) => synthWav(notes(k));

  static Uint8List synthWav(List<(double, int, double)> notes, {int rate = 22050}) {
    final samples = <int>[];
    for (final (f, ms, gain) in notes) {
      final n = rate * ms ~/ 1000;
      final attack = min(n, rate * 6 ~/ 1000);
      for (var i = 0; i < n; i++) {
        final t = i / rate;
        // soft attack, exponential decay; add an octave partial for a bell-ish tone
        final env = (i < attack ? i / max(1, attack) : 1.0) * exp(-3.2 * i / n);
        final v = sin(2 * pi * f * t) * 0.8 + sin(4 * pi * f * t) * 0.2;
        samples.add((v * env * gain * 32767).round().clamp(-32768, 32767));
      }
    }
    final dataLen = samples.length * 2;
    final b = ByteData(44 + dataLen);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        b.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataLen, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little);
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little);
    b.setUint16(32, 2, Endian.little);
    b.setUint16(34, 16, Endian.little);
    str(36, 'data');
    b.setUint32(40, dataLen, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      b.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }
}
