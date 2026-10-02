"""Prepares a ready-to-use client profile without touching the GUI: registers an account
over the real protocol, then writes settings.json (pinned server key + DPAPI-encrypted
session token) into the given APPDATA folder, so pulse.exe auto-logs in on start.

  python tools/dev/make_profile.py <appdata-dir> [host:port] [user] [display]
"""
import base64, ctypes as C, hashlib, hmac, json, os, socket, struct, sys, threading, time
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
appdata = sys.argv[1]
addr = sys.argv[2] if len(sys.argv) > 2 else '127.0.0.1:7800'
user = sys.argv[3] if len(sys.argv) > 3 else 'admin'
display = sys.argv[4] if len(sys.argv) > 4 else 'Owner'
host, port = addr.split(':')

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
        buf += s.recv(65536)
_, p = read_frame(); sh = json.loads(p)
sE, sS, sn = (base64.b64decode(sh[k]) for k in ('epk', 'spk', 'sn'))
ee = eph.exchange(X25519PublicKey.from_public_bytes(sE)); es = eph.exchange(X25519PublicKey.from_public_bytes(sS))
tr = hashlib.sha256(epk + sE + sS + cn + sn).digest()
prk = hmac.new(cn + sn, ee + es, hashlib.sha256).digest(); okm = b''; t = b''; i = 1
while len(okm) < 64:
    t = hmac.new(prk, t + b'pulse-v1' + tr + bytes([i]), hashlib.sha256).digest(); okm += t; i += 1
c2s, s2c = ChaCha20Poly1305(okm[:32]), ChaCha20Poly1305(okm[32:64])
def nonce(c): return b'\0' * 4 + struct.pack('>Q', c)
sc = [0]
def sj(m):
    c = sc[0]; sc[0] += 1
    s.sendall(frame(0, struct.pack('>Q', c) + c2s.encrypt(nonce(c), json.dumps(m).encode(), b'\0')))
def recv():
    k, p = read_frame(); c = struct.unpack('>Q', p[:8])[0]
    return json.loads(s2c.decrypt(nonce(c), p[8:], bytes([k])))
sj({'t': 'register', 'user': user, 'pass': 'password123', 'display': display, 'ver': 1})
while True:
    m = recv()
    if m['t'] == 'auth_err' and m.get('code') == 'taken':
        sj({'t': 'login', 'user': user, 'pass': 'password123', 'ver': 1}); continue
    if m['t'] == 'auth_err': raise SystemExit(m)
    if m['t'] == 'auth_ok': token = m['token']; break
s.close()

# encrypt the token exactly like the client does (pn_protect = DPAPI, current user)
lib = C.CDLL(os.path.join(ROOT, '_build', 'native', 'pulse_native.dll'))
lib.pn_protect.restype = C.POINTER(C.c_uint8)
lib.pn_protect.argtypes = [C.c_char_p, C.c_int32, C.POINTER(C.c_int32)]
n = C.c_int32(); raw = token.encode(); ptr = lib.pn_protect(raw, len(raw), C.byref(n))
blob = base64.b64encode(bytes(ptr[:n.value])).decode()
d = os.path.join(appdata, 'Pulse'); os.makedirs(d, exist_ok=True)
f = os.path.join(d, 'settings.json')
cfg = json.load(open(f, encoding='utf-8')) if os.path.exists(f) else {}
cfg['servers'] = [{'address': addr, 'name': '', 'user': user, 'pin': base64.b64encode(sS).decode(), 'tok': blob, 'used': int(time.time() * 1000)}]
cfg['lastServer'] = addr
json.dump(cfg, open(f, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('profile ready for', user, '->', f)
