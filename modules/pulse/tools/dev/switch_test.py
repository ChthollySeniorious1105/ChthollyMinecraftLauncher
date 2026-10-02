"""Measures how long AI voice reconfiguration / toggling takes (python tools/dev/switch_test.py [provider])."""
import ctypes as C, json, os, sys, time
D = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '_build', 'native')) + os.sep
lib = C.CDLL(D + 'pulse_native.dll')
CB = C.CFUNCTYPE(None, C.c_int32, C.c_int32, C.c_int32, C.POINTER(C.c_uint8), C.c_int32)
VERBOSE = '-v' in sys.argv
@CB
def cb(t, a, b, d, n):
    data = bytes(d[:n]) if n > 0 else b''
    if d: lib.pn_free(d)
    if t == 6 and VERBOSE: print('   [log]', data.decode('utf-8', 'replace'))
lib.pn_init.argtypes = [CB, C.c_char_p]; lib.pn_init(cb, D.encode())
lib.pn_vc_status.restype = C.c_void_p
def st():
    p = lib.pn_vc_status(); s = json.loads(C.cast(p, C.c_char_p).value.decode()); lib.pn_free(C.c_void_p(p)); return s
lib.pn_vc_ai_config.argtypes = [C.c_char_p, C.c_char_p, C.c_int32, C.c_int32, C.c_int32]
VERBOSE = '-v' in sys.argv
prov = ([a for a in sys.argv[1:] if a != '-v'] or ['auto'])[0].encode()
_ = (sys.argv[1] if len(sys.argv) > 1 else 'auto').encode()
def wait(label, t0, block=None, ctx=None):
    # hot switches keep state=2 the whole time: wait until the requested config is live
    while True:
        s = st()
        if s['state'] == 3 or (s['state'] == 2 and not s.get('switching') and (block is None or s['blockMs'] == block) and (ctx is None or s['extraMs'] == ctx)): break
        time.sleep(0.005)
    print('%-32s %6.2fs  state=%d block=%s ctx=%s err=%s' % (label, time.time() - t0, s['state'], s['blockMs'], s['extraMs'], s['error'][:60]))
P = (C.c_int32 * 6)(100, 300, 200, 300, 300, 500)
lib.pn_vc_ai_prewarm(P, 3)
t = time.time(); lib.pn_vc_ai_config(prov, b'', 200, 300, 0); time.sleep(0.02); wait('initial load', t)
time.sleep(4)  # let presets pre-compile in the background
t = time.time(); lib.pn_vc_ai_config(prov, b'', 100, 300, 0); time.sleep(0.02); wait('block 200 -> 100', t, 100)
t = time.time(); lib.pn_vc_ai_config(prov, b'', 300, 500, 0); time.sleep(0.02); wait('block 300, context 500', t, 300, 500)
t = time.time(); lib.pn_vc_ai_unload()
while st()['state'] != 0: time.sleep(0.005)
print('%-32s %6.2fs' % ('unload', time.time() - t))
t = time.time(); lib.pn_vc_ai_config(prov, b'', 300, 500, 0); time.sleep(0.02); wait('re-enable after unload', t, 300, 500)
t = time.time()
for b in (150, 200, 250, 300, 350): lib.pn_vc_ai_config(prov, b'', b, 300, 0)
time.sleep(0.02); wait('5 rapid reconfigs (slider drag)', t, 350)
t = time.time(); lib.pn_vc_ai_config(prov, b'', 200, 300, 0); time.sleep(0.02); wait('back to 200 (seen before)', t, 200)
lib.pn_shutdown()
