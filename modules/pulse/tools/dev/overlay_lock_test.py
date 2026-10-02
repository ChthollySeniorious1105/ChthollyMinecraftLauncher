"""Checks overlay lock (click-through) toggling in-process.   python tools/dev/overlay_lock_test.py"""
import ctypes as C, os, time

D = os.path.join(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')), '_build', 'native') + os.sep
lib = C.CDLL(D + 'pulse_native.dll')
CB = C.CFUNCTYPE(None, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_uint8), C.c_int32)
cb = CB(lambda *a: None)
lib.pn_init.argtypes = [CB, C.c_char_p]; lib.pn_init(cb, D.encode())
lib.pn_overlay_config.argtypes = [C.c_int32, C.c_float, C.c_float, C.c_int32, C.c_int32]
lib.pn_overlay_roster_begin.argtypes = [C.c_char_p, C.c_uint32]
lib.pn_overlay_roster_add.argtypes = [C.c_uint32, C.c_char_p, C.c_uint32, C.c_int32]
lib.pn_overlay_roster_begin('测试'.encode(), 1); lib.pn_overlay_roster_add(1, b'A', 0xFF5865F2, 0); lib.pn_overlay_roster_commit()
lib.pn_overlay_show(1); time.sleep(0.4)
u = C.windll.user32
u.GetWindowLongPtrW.restype = C.c_ssize_t
def ex():
    h = 0
    while True:
        h = u.FindWindowExW(None, h, 'PulseSpeakerOverlay', None)
        if not h: return None
        pid = C.c_ulong(); u.GetWindowThreadProcessId(h, C.byref(pid))
        if pid.value == os.getpid(): return u.GetWindowLongPtrW(h, -20)
print('unlocked click-through:', bool(ex() & 0x20))
lib.pn_overlay_config(1, 0.6, 1.3, 1, 0); time.sleep(0.3)
print('locked click-through:  ', bool(ex() & 0x20))
lib.pn_overlay_config(0, 0.85, 1.0, 0, 0); time.sleep(0.3)
print('unlocked again:        ', bool(ex() & 0x20))
lib.pn_overlay_show(0); lib.pn_shutdown()
