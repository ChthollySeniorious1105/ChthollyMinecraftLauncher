"""Shows the speaker overlay with a fake roster, feeds voice for one fake user so the
highlight appears, and saves a screenshot.   python tools/dev/overlay_test.py"""
import ctypes as C, os, time
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
D = os.path.join(ROOT, '_build', 'native').replace(os.sep, '/') + '/'
lib = C.CDLL(D + 'pulse_native.dll'); op = C.CDLL(D + 'opus.dll')
CB = C.CFUNCTYPE(None, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_uint8), C.c_int32)
ev = []
@CB
def cb(t, a, b, d, n):
    if d: lib.pn_free(d)
    ev.append(t)
lib.pn_init.argtypes = [CB, C.c_char_p]; lib.pn_init(cb, D.encode())
lib.pn_overlay_config.argtypes = [C.c_int32, C.c_float, C.c_float, C.c_int32, C.c_int32]
lib.pn_overlay_roster_begin.argtypes = [C.c_char_p, C.c_uint32]
lib.pn_overlay_roster_add.argtypes = [C.c_uint32, C.c_char_p, C.c_uint32, C.c_int32]
lib.pn_play_push.argtypes = [C.c_uint32, C.c_char_p, C.c_int32]
lib.pn_overlay_config(0, 0.85, 1.0, 0, 0)
lib.pn_overlay_roster_begin('大厅'.encode(), 1)
for uid, name, col, fl in [(1, 'Owner', 0xFFE67E22, 0), (2, '测试机器人', 0xFF00A8FC, 0), (3, '小明', 0xFF3BA55C, 1), (4, 'AFK 的人', 0xFF9B59B6, 2)]:
    lib.pn_overlay_roster_add(uid, name.encode(), col, fl)
lib.pn_overlay_roster_commit()
lib.pn_overlay_show(1)
print('playback', lib.pn_playback_start())
# stream a tone as user 2 so the overlay highlights them
op.opus_encoder_create.restype = C.c_void_p
op.opus_encode_float.argtypes = [C.c_void_p, C.POINTER(C.c_float), C.c_int, C.c_char_p, C.c_int32]
err = C.c_int(); enc = op.opus_encoder_create(48000, 1, 2048, C.byref(err)); buf = C.create_string_buffer(1500)
t0 = time.time()
for s in range(150):
    fr = (0.2 * np.sin(2 * np.pi * 220 * (np.arange(960) + s * 960) / 48000)).astype(np.float32)
    n = op.opus_encode_float(enc, fr.ctypes.data_as(C.POINTER(C.c_float)), 960, buf, 1500)
    p = bytes([s >> 8, s & 255]) + buf.raw[:n]; lib.pn_play_push(2, p, len(p))
    while time.time() - t0 < s * 0.02: time.sleep(0.002)
    if s % 20 == 0:
        uu = (C.c_uint32 * 8)(); ul = (C.c_float * 8)(); k = lib.pn_get_user_levels(uu, ul, 8)
        print('t=%.2f levels' % (time.time() - t0), [(uu[i], round(ul[i], 3)) for i in range(k)])
    if s == 30:  # screenshot in the background while audio keeps streaming
        import subprocess, threading
        threading.Thread(target=lambda: subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                         os.path.join(ROOT, 'tools', 'dev', 'shot_window.ps1'), '-cls', 'PulseSpeakerOverlay',
                         '-out', os.path.join(ROOT, '_build', 'overlay.png')])).start()
time.sleep(0.3)
lib.pn_overlay_show(0); time.sleep(0.2)
lib.pn_shutdown(); print('ok', ev)
