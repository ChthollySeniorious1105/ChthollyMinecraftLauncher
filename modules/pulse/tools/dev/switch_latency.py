"""Measures click -> visible-change latency of settings switches with real mouse input.
Re-focuses Pulse before each click (and aborts a click if something else is under the mouse).

  python tools/dev/switch_latency.py name:y [name:y ...]     (switch knob client y; x = 1580)
"""
import ctypes as C, ctypes.wintypes as W, sys, time
from PIL import ImageGrab

u = C.windll.user32; u.SetProcessDPIAware()
top = u.FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Pulse')
view = u.FindWindowExW(top, None, 'FLUTTERVIEW', None)
X = 1580

def front():
    for _ in range(5):
        if u.GetForegroundWindow() == top: return True
        fg = u.GetForegroundWindow(); t1 = u.GetWindowThreadProcessId(fg, None); t2 = C.windll.kernel32.GetCurrentThreadId()
        u.AttachThreadInput(t2, t1, True); u.keybd_event(0x12, 0, 0, 0); u.BringWindowToTop(top); u.SetForegroundWindow(top)
        u.keybd_event(0x12, 0, 2, 0); u.AttachThreadInput(t2, t1, False); time.sleep(0.25)
    return False

def origin():
    p = W.POINT(0, 0); u.ClientToScreen(top, C.byref(p)); return p

def state(y):
    p = origin()
    img = ImageGrab.grab(bbox=(p.x + X - 40, p.y + y - 4, p.x + X + 40, p.y + y + 4), all_screens=True).convert('RGB')
    return sum(1 for i in range(80) if (lambda c: c[1] > 140 and c[0] < 90)(img.getpixel((i, 4)))) > 20

def click(y):
    if not front(): return 'nofocus'
    p = origin(); sx, sy = p.x + X, p.y + y
    u.SetCursorPos(sx, sy); time.sleep(0.3)
    if u.GetAncestor(u.WindowFromPoint(W.POINT(sx, sy)), 2) != top: return 'covered'
    b = state(y); t0 = time.perf_counter()
    u.mouse_event(2, 0, 0, 0, 0); time.sleep(0.03); u.mouse_event(4, 0, 0, 0, 0)
    while state(y) == b and time.perf_counter() - t0 < 4: pass
    return int((time.perf_counter() - t0) * 1000) if state(y) != b else 'NO-CHANGE'

ov = u.FindWindowW('PulseSpeakerOverlay', None)
for arg in sys.argv[1:]:
    name, y = arg.split(':'); y = int(y)
    res = []
    for _ in range(4):
        res.append(click(y)); time.sleep(0.4)
    print('%-14s %s   overlay visible=%s' % (name, res, bool(ov and u.IsWindowVisible(ov))), flush=True)
