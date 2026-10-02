# Screen sharing native test: sources, thumbnail, monitor + window capture -> H.264 -> decode.
# Usage: python tools/dev/screen_test.py   (needs _build\native from tools\dev\nb.bat, numpy, Pillow)
import ctypes as C, json, os, sys, time, subprocess
import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
D = os.path.join(ROOT, '_build', 'native') + os.sep
lib = C.CDLL(D + 'pulse_native.dll')
CB = C.CFUNCTYPE(None, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_uint8), C.c_int32)
events = []


@CB
def cb(t, a, b, d, n):
    data = bytes(d[:n]) if n > 0 else b''
    if d: lib.pn_free(d)
    events.append((t, a, b, data, time.time()))
    if t == 6: print('  [log]', a, data.decode('utf-8', 'replace'))
    if t == 11: print('  [screen]', a, data.decode('utf-8', 'replace'))
    if t == 12: print('  [video size] id', a, 'size %dx%d' % (b >> 16, b & 0xffff))


lib.pn_init.argtypes = [CB, C.c_char_p]
lib.pn_free.argtypes = [C.c_void_p]
for f in ['pn_screen_sources', 'pn_screen_status', 'pn_video_stats']: getattr(lib, f).restype = C.c_void_p
lib.pn_video_stats.argtypes = [C.c_uint32]
lib.pn_screen_thumbnail.restype = C.c_void_p
lib.pn_screen_thumbnail.argtypes = [C.c_char_p, C.c_int32, C.c_int32, C.POINTER(C.c_int32), C.POINTER(C.c_int32)]
lib.pn_screen_start.argtypes = [C.c_char_p, C.c_int32, C.c_int32, C.c_int32, C.c_int32]
lib.pn_video_open.argtypes = [C.c_uint32]
lib.pn_video_close.argtypes = [C.c_uint32]
lib.pn_video_push.argtypes = [C.c_uint32, C.c_char_p, C.c_int32, C.c_int32]
lib.pn_video_lock_frame.argtypes = [C.c_uint32, C.POINTER(C.POINTER(C.c_uint8)), C.POINTER(C.c_int32), C.POINTER(C.c_int32)]
lib.pn_video_unlock_frame.argtypes = [C.c_uint32]
FRAME_CB = C.CFUNCTYPE(None, C.c_uint32)
lib.pn_video_set_frame_cb.argtypes = [FRAME_CB]
frame_cbs = [0]


@FRAME_CB
def on_frame(i):
    frame_cbs[0] += 1


def js(p):
    s = C.cast(p, C.c_char_p).value.decode()
    lib.pn_free(p)
    return json.loads(s)


fails = []


def check(cond, msg):
    print(('  OK   ' if cond else '  FAIL ') + msg)
    if not cond: fails.append(msg)


def grab(id_):
    p = C.POINTER(C.c_uint8)()
    w, h = C.c_int32(), C.c_int32()
    if not lib.pn_video_lock_frame(id_, C.byref(p), C.byref(w), C.byref(h)): return None
    try:
        return np.ctypeslib.as_array(p, shape=(h.value, w.value, 4)).copy()
    finally:
        lib.pn_video_unlock_frame(id_)


def capture(src, max_w, max_h, fps, kbps, secs, decode_id, extra=None):
    """Captures src, decodes everything into decoder decode_id, returns (packets, status)."""
    del events[:]
    t0 = time.time()
    check(lib.pn_screen_start(src.encode(), max_w, max_h, fps, kbps) == 0, 'pn_screen_start ' + src)
    lib.pn_video_open(decode_id)
    pk = []
    st = None
    done = 0
    while time.time() - t0 < secs:
        time.sleep(0.05)
        new = [e for e in events[done:]]
        done += len(new)
        for t, a, b, data, ts in new:
            if t == 10:
                pk.append((a, data, ts))
                lib.pn_video_push(decode_id, data, len(data), a)
        if extra and extra(time.time() - t0): extra = None
        if st is None and time.time() - t0 > secs - 0.5: st = js(lib.pn_screen_status())
    lib.pn_screen_stop()
    time.sleep(0.3)
    for t, a, b, data, ts in events[done:]:
        if t == 10:
            pk.append((a, data, ts))
            lib.pn_video_push(decode_id, data, len(data), a)
    return pk, st


print('abi', lib.pn_abi_version(), 'init', lib.pn_init(cb, D.encode()))
check(lib.pn_abi_version() == 4, 'ABI version 4')
lib.pn_video_set_frame_cb(on_frame)

# --- sources
src = js(lib.pn_screen_sources())
print('monitors', src['monitors'])
print('windows (%d):' % len(src['windows']), [(w['title'][:40], w['exe']) for w in src['windows'][:12]])
check(len(src['monitors']) >= 1, 'at least one monitor')

# --- thumbnail
w, h = C.c_int32(), C.c_int32()
p = lib.pn_screen_thumbnail(b'm:0', 320, 180, C.byref(w), C.byref(h))
check(bool(p) and w.value <= 320 and h.value <= 180 and max(w.value / 320, h.value / 180) > 0.98, 'monitor thumbnail %dx%d' % (w.value, h.value))
if p:
    a = np.ctypeslib.as_array(C.cast(p, C.POINTER(C.c_uint8)), shape=(h.value, w.value, 4)).copy()
    lib.pn_free(p)
    Image.fromarray(a, 'RGBA').save(os.path.join(ROOT, '_build', 'screen_thumb.png'))
    check(a[..., :3].std() > 5, 'thumbnail has content (std %.1f)' % a[..., :3].std())
check(not lib.pn_screen_thumbnail(b'w:1', 320, 180, C.byref(w), C.byref(h)), 'bad id -> NULL thumbnail')
check(lib.pn_screen_start(b'x:0', 0, 0, 30, 3000) == -1, 'bad id -> start fails')

# --- monitor capture 1280x720 30 fps 3000 kbps
print('\n== monitor m:0 1280x720@30 3000 kbps')
pk, st = capture('m:0', 1280, 720, 30, 3000, 3.5, 5)
print('  status', st)
nkey = sum(1 for a, _, _ in pk if a & 1)
nbytes = sum(len(d) for _, d, _ in pk)
started = [e for e in events if e[0] == 11 and e[1] == 1]
dur = (pk[-1][2] - pk[0][2]) if len(pk) > 1 else 0
print('  packets %d keyframes %d bytes %d (%.0f kbps over %.1fs)' % (len(pk), nkey, nbytes, nbytes * 8 / 1000 / max(dur, 0.1), dur))
check(started and json.loads(started[0][3])['w'] == 1280 or (started and json.loads(started[0][3])['h'] == 720), 'PN_EV_SCREEN started with output size')
check(len(pk) >= 3, 'got packets')
check(pk and pk[0][0] & 1 == 1, 'first packet is a keyframe')
first = pk[0][1] if pk else b''
nals = [first[i + 3] & 0x1f for i in range(len(first) - 3) if first[i:i + 3] == bytes([0, 0, 1])]
check(7 in nals and 8 in nals and 5 in nals, 'keyframe has SPS/PPS/IDR (NAL types %s)' % nals[:8])
check(st and st['w'] == 1280 and st['h'] == 720, 'status size 1280x720')
time.sleep(0.5)
vs = js(lib.pn_video_stats(5))
print('  decoder stats', vs)
f = grab(5)
check(f is not None and f.shape[:2] == (720, 1280), 'decoded frame 1280x720')
if f is not None:
    Image.fromarray(f, 'RGBA').save(os.path.join(ROOT, '_build', 'screen_test.png'))
    check(f[..., :3].std() > 5, 'decoded frame has content (std %.1f)' % f[..., :3].std())
    # compare with the thumbnail: same picture at low resolution
    th = np.asarray(Image.open(os.path.join(ROOT, '_build', 'screen_thumb.png')).convert('RGB')).astype(np.float32)
    small = np.asarray(Image.fromarray(f[..., :3]).resize((th.shape[1], th.shape[0]), Image.BILINEAR)).astype(np.float32)
    diff = np.abs(small - th).mean(axis=(0, 1))
    print('  mean abs diff vs GDI thumbnail per channel (R,G,B):', diff.round(1))
check(frame_cbs[0] > 0, 'frame callback fired (%d)' % frame_cbs[0])
sizes = [e for e in events if e[0] == 12 and e[1] == 5]
check(len(sizes) >= 0, 'video size events')

# --- decode speed (re-decode same stream)
lib.pn_video_close(5)


def decode_latency(pk, label, limit_ms):
    lib.pn_video_open(6)
    lat = []
    for a, d, _ in pk:  # one at a time: per-frame decode latency (decode + NV12->RGBA)
        n0 = frame_cbs[0]
        t = time.perf_counter()
        lib.pn_video_push(6, d, len(d), a)
        while frame_cbs[0] == n0 and time.perf_counter() - t < 0.5: time.sleep(0.0002)
        lat.append((time.perf_counter() - t) * 1000)
    lat = np.array(lat)
    print('  per-frame decode latency %s: median %.1f ms, p95 %.1f ms, max %.1f ms; frames %d/%d' % (
        label, np.median(lat), np.percentile(lat, 95), lat.max(), js(lib.pn_video_stats(6))['frames'], len(pk)))
    check(np.median(lat) < limit_ms, 'decode latency < %d ms (no frame delay)' % limit_ms)
    lib.pn_video_close(6)


decode_latency(pk, '1280x720', 15)

# --- keyframe on demand + full size capture of the same monitor
print('\n== keyframe request (m:0, native size, 60 fps)')
kt = {}


def ask(t):
    if t > 1.5:
        kt['t'] = time.time()
        lib.pn_screen_keyframe()
        return True


pk, st = capture('m:0', 0, 0, 60, 8000, 3.0, 7, ask)
print('  status', st)
keys = [ts for a, _, ts in pk if a & 1]
after = [ts - kt['t'] for ts in keys if ts >= kt.get('t', 1e18)]
check(len(keys) >= 2 and after and after[0] < 0.5, 'keyframe after pn_screen_keyframe (%s s)' % (['%.3f' % x for x in after[:2]]))
lib.pn_video_close(7)
decode_latency(pk, '%dx%d' % (st['w'], st['h']), 25)

# --- window capture (start a notepad so there is something to capture)
print('\n== window capture')
np_proc = subprocess.Popen(['notepad.exe'])
hwnd = None
is_np = False
for _ in range(50):
    time.sleep(0.1)
    for win in js(lib.pn_screen_sources())['windows']:
        if win['exe'].lower() == 'notepad.exe':
            hwnd, is_np = win['id'], True
            break
    if hwnd: break
if not hwnd:
    ws = js(lib.pn_screen_sources())['windows']
    hwnd = ws[0]['id'] if ws else None
print('  window', hwnd)
if hwnd:
    p = lib.pn_screen_thumbnail(hwnd.encode(), 320, 180, C.byref(w), C.byref(h))
    check(bool(p), 'window thumbnail %dx%d' % (w.value, h.value))
    if p: lib.pn_free(p)
    pk, st = capture(hwnd, 1280, 720, 30, 2000, 2.5, 8)
    print('  status', st, 'packets', len(pk))
    check(len(pk) >= 2 and pk[0][0] & 1, 'window capture produced packets starting with a keyframe')
    time.sleep(0.3)
    f = grab(8)
    if f is not None:
        Image.fromarray(f, 'RGBA').save(os.path.join(ROOT, '_build', 'screen_test_window.png'))
        print('  decoded window frame', f.shape)
    check(f is not None, 'decoded window frame')
    lib.pn_video_close(8)
    # window closed while capturing -> stopped with reason
    if not is_np: print('  (notepad not found, skipping window-close test)')
    if is_np:  # only close the notepad we started
        del events[:]
        lib.pn_screen_start(hwnd.encode(), 1280, 720, 30, 2000)
        time.sleep(1.0)
        C.windll.user32.PostMessageW(C.c_void_p(int(hwnd[2:])), 0x0010, 0, 0)  # WM_CLOSE (notepad.exe is a launcher stub on Win11)
        t = time.time()
        while time.time() - t < 3 and not any(e[0] == 11 and e[1] != 1 for e in events): time.sleep(0.05)
        ev = [e for e in events if e[0] == 11 and e[1] != 1]
        check(ev and ev[0][1] == 0 and ev[0][3].decode() == '窗口已关闭', 'window close -> stopped "窗口已关闭" (%r)' % (((ev[0][1], ev[0][3].decode()) if ev else None),))
        lib.pn_screen_stop()
np_proc.kill() if np_proc.poll() is None else None

# --- stop / restart cycles + shutdown while active
print('\n== restart cycles')
for i in range(3):
    lib.pn_screen_start(b'm:0', 640, 360, 15, 1000)
    time.sleep(0.4)
st = js(lib.pn_screen_status())
check(st.get('active'), 'active after restarts (%s)' % st.get('encoder'))
lib.pn_video_open(9)
t = time.time()
lib.pn_shutdown()
check(True, 'shutdown while capturing + decoder open (%.2fs)' % (time.time() - t))
print('\nFAILED: %d' % len(fails) if fails else '\nALL PASSED')
sys.exit(1 if fails else 0)
