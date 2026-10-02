"""Repaint probe that never touches the real mouse or other windows: mouse clicks are posted
as window messages straight to Pulse's Flutter view, and the window content is captured with
PrintWindow (works while the window is covered or not focused).

  python tools/dev/repaint_probe.py x,y[:label] ...      (client-area coordinates, physical px)
  python tools/dev/repaint_probe.py --wait 3 x,y:label   (also report pixels changed after N s)
"""
import ctypes as C, ctypes.wintypes as W, sys, time
from PIL import Image, ImageChops

u, g = C.windll.user32, C.windll.gdi32
u.SetProcessDPIAware()
top = u.FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Pulse')
if not top: raise SystemExit('no Pulse window')
view = u.FindWindowExW(top, None, 'FLUTTERVIEW', None) or top  # child that receives input

SCREEN = '--screen' in sys.argv
if SCREEN: sys.argv.remove('--screen')

def grab():
    if SCREEN:  # what is actually on the monitor (DWM output), not the window's own buffer
        from PIL import ImageGrab
        p = W.POINT(0, 0); u.ClientToScreen(top, C.byref(p)); r = W.RECT(); u.GetClientRect(top, C.byref(r))
        return ImageGrab.grab(bbox=(p.x, p.y, p.x + r.right, p.y + r.bottom), all_screens=True)
    r = W.RECT(); u.GetClientRect(top, C.byref(r)); w, h = r.right, r.bottom
    hdc = u.GetDC(top); mem = g.CreateCompatibleDC(hdc); bmp = g.CreateCompatibleBitmap(hdc, w, h)
    old = g.SelectObject(mem, bmp)
    u.PrintWindow(top, mem, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
    class BIH(C.Structure):
        _fields_ = [('biSize', C.c_uint32), ('biWidth', C.c_int32), ('biHeight', C.c_int32), ('biPlanes', C.c_uint16),
                    ('biBitCount', C.c_uint16), ('biCompression', C.c_uint32), ('biSizeImage', C.c_uint32),
                    ('a', C.c_int32), ('b', C.c_int32), ('c', C.c_uint32), ('d', C.c_uint32)]
    bi = BIH(); bi.biSize = C.sizeof(BIH); bi.biWidth = w; bi.biHeight = -h; bi.biPlanes = 1; bi.biBitCount = 32
    buf = C.create_string_buffer(w * h * 4)
    g.GetDIBits(mem, bmp, 0, h, buf, C.byref(bi), 0)
    g.SelectObject(mem, old); g.DeleteObject(bmp); g.DeleteDC(mem); u.ReleaseDC(top, hdc)
    return Image.frombuffer('RGBA', (w, h), buf, 'raw', 'BGRA', 0, 1)

FAST = 0.0
if '--fast' in sys.argv:
    i = sys.argv.index('--fast'); FAST = float(sys.argv[i + 1]); del sys.argv[i:i + 2]
REAL = '--real' in sys.argv
if REAL: sys.argv.remove('--real')

def real_click(x, y):
    p = W.POINT(x, y); u.ClientToScreen(top, C.byref(p))
    u.SetCursorPos(p.x, p.y); time.sleep(0.25)  # hover first, like a person
    u.mouse_event(2, 0, 0, 0, 0); time.sleep(0.06); u.mouse_event(4, 0, 0, 0, 0)

def lparam(x, y): return (y << 16) | (x & 0xFFFF)

def click(x, y):
    # coordinates are relative to the top window's client area == Flutter view client area
    u.PostMessageW(view, 0x0200, 0, lparam(x, y))       # WM_MOUSEMOVE
    time.sleep(0.03)
    u.PostMessageW(view, 0x0201, 1, lparam(x, y))       # WM_LBUTTONDOWN
    time.sleep(0.05)
    u.PostMessageW(view, 0x0202, 0, lparam(x, y))       # WM_LBUTTONUP

def diff(a, b):
    d = ImageChops.difference(a.convert('RGB'), b.convert('RGB')).convert('L').point(lambda v: 255 if v > 24 else 0)
    return int(sum(d.histogram()[255:]))

def drag(x1, y1, x2, y2, steps=15):
    u.PostMessageW(view, 0x0200, 0, lparam(x1, y1)); time.sleep(0.03)
    u.PostMessageW(view, 0x0201, 1, lparam(x1, y1)); time.sleep(0.05)
    for i in range(1, steps + 1):
        u.PostMessageW(view, 0x0200, 1, lparam(x1 + (x2 - x1) * i // steps, y1 + (y2 - y1) * i // steps)); time.sleep(0.02)
    u.PostMessageW(view, 0x0202, 0, lparam(x2, y2))

args = sys.argv[1:]
wait = 0.0
if args and args[0] == '--wait':
    wait = float(args[1]); args = args[2:]
for arg in args:
    xy, _, label = arg.partition(':')
    before = grab()
    if xy.startswith('wheel'):  # wheel@x,y,notches (negative = scroll down)
        x, y, n = map(int, xy[6:].split(','))
        r = W.RECT(); u.GetWindowRect(view, C.byref(r))
        for _ in range(abs(n)):
            u.PostMessageW(view, 0x020A, ((120 if n > 0 else -120) & 0xFFFF) << 16, lparam(r.left + x, r.top + y)); time.sleep(0.05)
    elif '>' in xy:  # x1,y1>x2,y2 = drag
        a1, a2 = xy.split('>')
        x1, y1 = map(int, a1.split(',')); x2, y2 = map(int, a2.split(','))
        drag(x1, y1, x2, y2)
    else:
        x, y = map(int, xy.split(','))
        (real_click if REAL else click)(x, y)
    if FAST: time.sleep(FAST); continue
    time.sleep(0.15); a = grab()
    time.sleep(0.6); b = grab()
    line = '%-18s fg=%d  +150ms=%7d  +750ms=%7d' % (label or xy, u.GetForegroundWindow() == top, diff(before, a), diff(before, b))
    if wait:
        time.sleep(wait); c = grab(); line += '  +%.1fs=%7d' % (wait + 0.75, diff(before, c))
    print(line, flush=True)
    b.save('D:/Server/Others/Pulse/_build/probe_%s.png' % (label or 'step'))
