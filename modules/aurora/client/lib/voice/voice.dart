import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';

import '../platform/sfx.dart';

const int kVoiceRate = 16000;

/// G.711 μ-law codec: halves bandwidth vs PCM16 with good speech quality.
class MuLaw {
  static final Int16List _decodeTable = _buildDecode();

  static Int16List _buildDecode() {
    final t = Int16List(256);
    for (var i = 0; i < 256; i++) {
      final u = ~i & 0xFF;
      final sign = u & 0x80;
      final exponent = (u >> 4) & 0x07;
      final mantissa = u & 0x0F;
      var sample = ((mantissa << 3) + 0x84) << exponent;
      sample -= 0x84;
      t[i] = sign != 0 ? -sample : sample;
    }
    return t;
  }

  static int encodeSample(int s) {
    const bias = 0x84, clip = 32635;
    var sign = 0;
    if (s < 0) {
      s = -s;
      sign = 0x80;
    }
    if (s > clip) s = clip;
    s += bias;
    var exponent = 7;
    for (var mask = 0x4000; (s & mask) == 0 && exponent > 0; mask >>= 1) {
      exponent--;
    }
    final mantissa = (s >> (exponent + 3)) & 0x0F;
    return ~(sign | (exponent << 4) | mantissa) & 0xFF;
  }

  static Uint8List encode(Int16List pcm) {
    final out = Uint8List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      out[i] = encodeSample(pcm[i]);
    }
    return out;
  }

  static Int16List decode(Uint8List data) {
    final out = Int16List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = _decodeTable[data[i]];
    }
    return out;
  }
}

/// Software noise suppression applied on top of the OS-provided suppressor:
///  1. DC-blocking high-pass (~100 Hz) removes rumble / hum fundamentals.
///  2. Adaptive noise-floor estimation (tracks the quietest recent frames).
///  3. Spectral-subtraction-style soft gain + smooth noise gate with hangover,
///     so steady background noise (fans, keyboards) is suppressed and silence
///     is not transmitted at all.
class NoiseSuppressor {
  double level; // 0 = off, 1 = light, 2 = normal, 3 = strong
  NoiseSuppressor(this.level);

  double _hpX = 0, _hpY = 0;
  double _noise = 300; // estimated noise RMS
  double _gain = 0;
  int _hang = 0;
  bool speaking = false;

  static const _frame = 320; // 20 ms @ 16 kHz

  /// Processes PCM in place. Returns false if the whole chunk is silence.
  bool process(Int16List pcm) {
    const a = 0.96; // high-pass coefficient
    final f = Float64List(pcm.length);
    for (var i = 0; i < pcm.length; i++) {
      final x = pcm[i].toDouble();
      _hpY = a * (_hpY + x - _hpX);
      _hpX = x;
      f[i] = _hpY;
    }
    if (level <= 0) {
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = f[i].round().clamp(-32768, 32767);
      }
      speaking = true;
      return true;
    }
    final threshMul = [1.0, 1.8, 2.5, 3.5][level.round().clamp(0, 3)];
    var anyVoice = false;
    for (var start = 0; start < f.length; start += _frame) {
      final end = min(start + _frame, f.length);
      var sum = 0.0;
      for (var i = start; i < end; i++) {
        sum += f[i] * f[i];
      }
      final rms = sqrt(sum / max(1, end - start));
      // noise floor: fall quickly, rise slowly
      if (rms < _noise) {
        _noise = _noise * 0.85 + rms * 0.15;
      } else {
        _noise = _noise * 0.998 + rms * 0.002;
      }
      _noise = _noise.clamp(40.0, 4000.0);
      final open = rms > _noise * threshMul + 120;
      if (open) {
        _hang = 15; // 300 ms hangover
      } else if (_hang > 0) {
        _hang--;
      }
      // spectral-subtraction style gain on the broadband signal
      final snrGain = rms <= 1 ? 0.0 : max(0.0, 1 - (_noise * (0.6 + level * 0.25)) / rms);
      final target = (_hang > 0) ? max(snrGain, 0.35) : 0.0;
      for (var i = start; i < end; i++) {
        _gain += (target - _gain) * (target > _gain ? 0.02 : 0.004);
        f[i] *= _gain;
      }
      if (_hang > 0) anyVoice = true;
    }
    for (var i = 0; i < pcm.length; i++) {
      pcm[i] = f[i].round().clamp(-32768, 32767);
    }
    speaking = anyVoice;
    return anyVoice || _gain > 0.01;
  }
}

/// Microphone capture + remote playback.
class VoiceEngine extends ChangeNotifier {
  final void Function(Uint8List) sendAudio;
  VoiceEngine(this.sendAudio);

  // created on first use so merely constructing the engine never touches the plugin
  late final AudioRecorder _rec = AudioRecorder();
  bool _recUsed = false;
  StreamSubscription<Uint8List>? _sub;
  bool micOn = false;
  bool deafened = false;
  bool speaking = false;
  double noiseLevel = 2;
  bool pushToTalk = false;
  bool pttHeld = false;
  double outputVolume = 1.0;

  /// Microphone input gain (0 = muted, 1 = unchanged, up to 3 = +9.5 dB),
  /// applied before noise suppression / transmission.
  double inputGain = 1.0;

  /// Current microphone level 0..1 (after gain), for the input meter.
  final micLevel = ValueNotifier<double>(0);
  String? error;
  final NoiseSuppressor _ns = NoiseSuppressor(2);
  final List<int> _carry = [];

  bool _soloudReady = false;
  final Map<int, AudioSource> _streams = {};
  final Map<int, DateTime> _lastPacket = {};
  final Set<int> talking = {};
  Timer? _talkTimer;

  void touch() => notifyListeners();

  void setOutputVolume(double v) {
    outputVolume = v;
    if (_soloudReady) SoLoud.instance.setGlobalVolume(v);
    notifyListeners();
  }

  void setInputGain(double v) {
    inputGain = v.clamp(0.0, 3.0);
    notifyListeners();
  }

  void setPtt(bool held) {
    pttHeld = held;
    notifyListeners();
  }

  Future<void> _ensurePlayback() async {
    if (_soloudReady) return;
    try {
      if (!await ensureSoLoud()) throw StateError('SoLoud init failed');
      _soloudReady = true;
      SoLoud.instance.setGlobalVolume(outputVolume);
      _talkTimer ??= Timer.periodic(const Duration(milliseconds: 300), (_) => _expireTalkers());
    } catch (e) {
      error = '音频输出初始化失败：$e';
      notifyListeners();
    }
  }

  void _expireTalkers() {
    final now = DateTime.now();
    var changed = false;
    for (final id in talking.toList()) {
      if (now.difference(_lastPacket[id] ?? now).inMilliseconds > 500) {
        talking.remove(id);
        changed = true;
      }
    }
    // tear down streams idle for 10s to release memory
    for (final id in _streams.keys.toList()) {
      if (now.difference(_lastPacket[id] ?? now).inSeconds > 10) {
        final s = _streams.remove(id)!;
        try {
          SoLoud.instance.setDataIsEnded(s);
          SoLoud.instance.disposeSource(s);
        } catch (_) {}
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> setMic(bool on) async {
    if (on == micOn) return;
    error = null;
    if (on) {
      try {
        _recUsed = true;
        if (!await _rec.hasPermission()) {
          error = '没有麦克风权限';
          notifyListeners();
          return;
        }
        // iOS: the session is configured in AppDelegate (playAndRecord + voiceChat)
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) await _rec.ios?.manageAudioSession(false);
        final stream = await _rec.startStream(RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: kVoiceRate,
          numChannels: 1,
          noiseSuppress: noiseLevel > 0,
          echoCancel: true,
          autoGain: true,
          streamBufferSize: 1280,
          // voiceCommunication = hardware AEC/NS on most devices; keep playback on the speaker
          androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            speakerphone: true,
          ),
        ));
        _sub = stream.listen(_onPcm, onError: (e) {
          error = '麦克风错误：$e';
          notifyListeners();
        });
        micOn = true;
      } catch (e) {
        error = '无法打开麦克风：$e';
      }
    } else {
      await _sub?.cancel();
      _sub = null;
      try {
        if (_recUsed) await _rec.stop();
      } catch (_) {}
      micOn = false;
      speaking = false;
      micLevel.value = 0;
    }
    notifyListeners();
  }

  void setNoiseLevel(double v) {
    noiseLevel = v;
    _ns.level = v;
    notifyListeners();
  }

  void _onPcm(Uint8List bytes) {
    _carry.addAll(bytes);
    const chunkBytes = 640 * 2; // 40 ms
    while (_carry.length >= chunkBytes) {
      final chunk = Uint8List.fromList(_carry.sublist(0, chunkBytes));
      _carry.removeRange(0, chunkBytes);
      final pcm = Int16List.view(chunk.buffer);
      _applyGain(pcm);
      final transmit = (!pushToTalk || pttHeld) && !deafened;
      final voiced = _ns.process(pcm);
      final nowSpeaking = transmit && _ns.speaking;
      if (nowSpeaking != speaking) {
        speaking = nowSpeaking;
        notifyListeners();
      }
      if (transmit && voiced) sendAudio(MuLaw.encode(pcm));
    }
  }

  void _applyGain(Int16List pcm) {
    final gain = inputGain;
    var peak = 0;
    for (var i = 0; i < pcm.length; i++) {
      final v = gain == 1.0 ? pcm[i] : (pcm[i] * gain).round().clamp(-32768, 32767);
      pcm[i] = v;
      final a = v.abs();
      if (a > peak) peak = a;
    }
    // meter: fast attack, slow release
    final lv = peak / 32768;
    final cur = micLevel.value;
    micLevel.value = lv > cur ? lv : cur * 0.8 + lv * 0.2;
  }

  Future<void> onRemoteAudio(int speaker, Uint8List data) async {
    if (deafened) return;
    await _ensurePlayback();
    if (!_soloudReady) return;
    final pcm = MuLaw.decode(data);
    var src = _streams[speaker];
    try {
      if (src == null) {
        src = SoLoud.instance.setBufferStream(
          maxBufferSizeDuration: const Duration(minutes: 30),
          bufferingType: BufferingType.released,
          bufferingTimeNeeds: 0.12,
          sampleRate: kVoiceRate,
          channels: Channels.mono,
          format: BufferType.s16le,
        );
        _streams[speaker] = src;
        SoLoud.instance.addAudioDataStream(src, pcm.buffer.asUint8List());
        SoLoud.instance.play(src);
      } else {
        SoLoud.instance.addAudioDataStream(src, pcm.buffer.asUint8List());
      }
    } catch (e) {
      _streams.remove(speaker);
    }
    _lastPacket[speaker] = DateTime.now();
    if (talking.add(speaker)) notifyListeners();
  }

  void setDeafened(bool v) {
    deafened = v;
    if (v) {
      for (final s in _streams.values) {
        try {
          SoLoud.instance.disposeSource(s);
        } catch (_) {}
      }
      _streams.clear();
      talking.clear();
    }
    notifyListeners();
  }

  Future<void> reset() async {
    for (final s in _streams.values) {
      try {
        SoLoud.instance.disposeSource(s);
      } catch (_) {}
    }
    _streams.clear();
    talking.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_recUsed) _rec.dispose();
    _talkTimer?.cancel();
    micLevel.dispose();
    super.dispose();
  }
}
