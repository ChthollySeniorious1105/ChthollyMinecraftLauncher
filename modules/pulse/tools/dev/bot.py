"""Protocol-level test client ("bot"): registers / logs in, posts a message, joins the first
voice channel and streams a 220 Hz tone (or speech.wav) as Opus for N seconds.

  python tools/dev/bot.py [host:port] [seconds] [--name 机器人] [--user bot]
"""
import base64, ctypes as C, hashlib, hmac, json, os, socket, struct, sys, threading, time
import numpy as np
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
args = [a for a in sys.argv[1:] if not a.startswith('--')]
opt = {sys.argv[i][2:]: sys.argv[i + 1] for i in range(1, len(sys.argv) - 1) if sys.argv[i].startswith('--')}
host, port = (args[0] if args else '127.0.0.1:7800').split(':')
dur = float(args[1]) if len(args) > 1 else 8
user, display = opt.get('user', 'bot'), opt.get('name', '测试机器人')

def frame(kind, p): return struct.pack('>IB', len(p) + 1, kind) + p
s = socket.create_connection((host, int(port)))
eph = X25519PrivateKey.generate(); cn = os.urandom(16); epk = eph.public_key().public_bytes_raw()
s.sendall(frame(0, json.dumps({'t': 'chello', 'v': 1, 'epk': base64.b64encode(epk).decode(), 'cn': base64.b64encode(cn).decode()}).encode()))
buf = b''
def read_frame():
    global buf
    while True:
        if len(buf) >= 4:
            n = struct.unpack('>I', buf[:4])[0]
            if len(buf) >= 4 + n:
                k, p, buf = buf[4], buf[5:4 + n], buf[4 + n:]
                return k, p
        d = s.recv(65536)
        if not d: raise SystemExit('closed')
        buf += d
_, p = read_frame(); sh = json.loads(p)
sE, sS, sn = (base64.b64decode(sh[k]) for k in ('epk', 'spk', 'sn'))
ee = eph.exchange(X25519PublicKey.from_public_bytes(sE)); es = eph.exchange(X25519PublicKey.from_public_bytes(sS))
tr = hashlib.sha256(epk + sE + sS + cn + sn).digest()
prk = hmac.new(cn + sn, ee + es, hashlib.sha256).digest(); okm = b''; t = b''; i = 1
while len(okm) < 64:
    t = hmac.new(prk, t + b'pulse-v1' + tr + bytes([i]), hashlib.sha256).digest(); okm += t; i += 1
c2s, s2c = ChaCha20Poly1305(okm[:32]), ChaCha20Poly1305(okm[32:64]); sc, rc = [0], [0]
lock = threading.Lock()
def nonce(c): return b'\0' * 4 + struct.pack('>Q', c)
def send(kind, p):
    with lock:
        c = sc[0]; sc[0] += 1
        s.sendall(frame(kind, struct.pack('>Q', c) + c2s.encrypt(nonce(c), p, bytes([kind]))))
def sj(m): send(0, json.dumps(m).encode())
state = {}
def reader():
    while True:
        k, p = read_frame(); c = struct.unpack('>Q', p[:8])[0]; rc[0] += 1
        d = s2c.decrypt(nonce(c), p[8:], bytes([k]))
        if k == 0:
            m = json.loads(d); state.setdefault(m['t'], []).append(m)
            if m['t'] == 'auth_err' and m.get('code') == 'taken': sj({'t': 'login', 'user': user, 'pass': 'password123', 'ver': 1})
        else:
            state.setdefault('voice', []).append(d)
threading.Thread(target=reader, daemon=True).start()
sj({'t': 'register', 'user': user, 'pass': 'password123', 'display': display, 'ver': 1})
while 'welcome' not in state: time.sleep(0.05)
w = state['welcome'][-1]
vch = [c for c in w['channels'] if c['kind'] == 'voice'][0]['id']
sj({'t': 'vjoin', 'ch': vch}); time.sleep(0.4)
op = C.CDLL(os.path.join(ROOT, 'client', 'native', 'bin', 'opus.dll'))
op.opus_encoder_create.restype = C.c_void_p
op.opus_encode_float.argtypes = [C.c_void_p, C.POINTER(C.c_float), C.c_int, C.c_char_p, C.c_int32]
err = C.c_int(); enc = op.opus_encoder_create(48000, 1, 2048, C.byref(err)); ob = C.create_string_buffer(1500)
t0 = time.time()
for i in range(int(dur * 50)):
    talk = (i // 75) % 2 == 0  # 1.5 s talk / 1.5 s pause so the highlight visibly toggles
    if talk:
        fr = (0.2 * np.sin(2 * np.pi * 220 * (np.arange(960) + i * 960) / 48000)).astype(np.float32)
        n = op.opus_encode_float(enc, fr.ctypes.data_as(C.POINTER(C.c_float)), 960, ob, 1500)
        send(1, struct.pack('>H', i & 0xFFFF) + ob.raw[:n])
    while time.time() - t0 < (i + 1) * 0.02: time.sleep(0.002)
print('done; voice packets received:', len(state.get('voice', [])))
