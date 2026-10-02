"""Voice-changer mode toggling: checks the capture chain output stays continuous (no silence
gaps, no clicks) while switching OFF / DSP / AI rapidly, and that switching back to AI is
instant while the pipeline is kept warm.   python tools/dev/toggle_test.py [provider]"""
import ctypes as C, json, os, sys, time
import numpy as np, soundfile as sf

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
D = os.path.join(ROOT, '_build', 'native').replace(os.sep, '/') + '/'
lib = C.CDLL(D + 'pulse_native.dll')
CB = C.CFUNCTYPE(None, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_uint8), C.c_int32)
@CB
def cb(t, a, b, d, n):
    if d: lib.pn_free(d)
lib.pn_init.argtypes = [CB, C.c_char_p]; lib.pn_init(cb, D.encode())
lib.pn_vc_status.restype = C.c_void_p
def st():
    p = lib.pn_vc_status(); s = json.loads(C.cast(p, C.c_char_p).value.decode()); lib.pn_free(C.c_void_p(p)); return s
lib.pn_vc_ai_config.argtypes = [C.c_char_p, C.c_char_p, C.c_int32, C.c_int32, C.c_int32]
lib.pn_vc_set_pitch.argtypes = [C.c_float]
prov = ([a for a in sys.argv[1:] if not a.startswith('--')] or ['auto'])[0].encode()

x, sr = sf.read(os.path.join(ROOT, '_build', 'speech.wav')); x = (x * 0.5).astype(np.float32)
x = np.concatenate([x, x])  # ~18 s
lib.pn_set_noise_suppression(0)
lib.pn_debug_inline(1)
lib.pn_vc_ai_config(prov, b'', 200, 300, 0)
while st()['state'] not in (2, 3): time.sleep(0.01)
assert st()['state'] == 2, st()
lib.pn_vc_set_pitch(7.0)

F = 480
out = np.zeros_like(x)
schedule = {}  # frame index -> mode; switch every ~0.7 s through OFF/DSP/AI
modes = [0, 1, 2, 0, 2, 1, 2, 0, 2, 2, 1, 0, 2, 1, 0, 2, 0, 1, 2, 0, 2, 1, 0, 2, 0]
if '--ai-only' in sys.argv: modes = [2] * len(modes)
if '--log' in sys.argv: modes_log = True
for k, m in enumerate(modes): schedule[k * 70] = m
t0 = time.time()
for i in range(len(x) // F):
    if i in schedule: lib.pn_vc_set_mode(schedule[i])
    fr = np.ascontiguousarray(x[i * F:(i + 1) * F]); o = np.zeros(F, np.float32)
    lib.pn_debug_process(fr.ctypes.data_as(C.POINTER(C.c_float)), F, o.ctypes.data_as(C.POINTER(C.c_float)))
    out[i * F:(i + 1) * F] = o
el = time.time() - t0
sf.write(os.path.join(ROOT, '_build', 'toggle.wav'), out, 48000)

# gaps: 10 ms frames that are silent while the input is clearly speaking
fi = np.sqrt((x[:len(out) // F * F].reshape(-1, F) ** 2).mean(1)); fo = np.sqrt((out[:len(fi) * F].reshape(-1, F) ** 2).mean(1))
speaking = fi > 0.02
gapmask = (fo < fi * 0.05) & speaking
gaps = int(gapmask.sum())
seg = 70
per = [int(gapmask[k * seg:(k + 1) * seg].sum()) for k in range(len(modes))]
print('gaps per segment (mode:gaps):', ' '.join('%d:%d' % (m, g) for m, g in zip(modes, per)))
# clicks: sample-to-sample jumps much larger than the signal normally has
d = np.abs(np.diff(out)); thr = max(0.25, np.percentile(d, 99.99) * 1.5)
jumps = int((d > 0.25).sum())
print('processed %.1fs in %.1fs, %d mode switches' % (len(x) / 48000, el, len(modes)))
print('silent frames while speaking: %d of %d (%.1f%%)' % (gaps, speaking.sum(), 100 * gaps / max(1, speaking.sum())))
print('large sample jumps (>0.25): %d   max jump %.3f' % (jumps, d.max()))
print('AI status', {k: st()[k] for k in ('state', 'underruns', 'latencyMs', 'switching')})
lib.pn_shutdown()
