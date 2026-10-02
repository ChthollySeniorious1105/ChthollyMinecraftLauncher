"""Real-mouse click test for one settings switch: brings Pulse to the front, clicks the switch N
times with a given gap and reads the switch's on/off state from the screen after every click.

  python tools/dev/switch_click_test.py x y [gap ...]     (client coords of the switch knob)
"""
import ctypes as C, ctypes.wintypes as W, sys, time
from PIL import ImageGrab

u = C.windll.user32; u.SetProcessDPIAware()
top = u.FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Pulse')
x, y = int(sys.argv[1]), int(sys.argv[2])
gaps = [float(g) for g in sys.argv[3:]] or [1.0, 0.5, 0.3]

def front():
    if u.GetForegroundWindow() == top: return True
    fg = u.GetForegroundWindow(); t1 = u.GetWindowThreadProcessId(fg, None); t2 = C.windll.kernel32.GetCurrentThreadId()
    u.AttachThreadInput(t2, t1, True); u.keybd_event(0x12, 0, 0, 0); u.BringWindowToTop(top); u.SetForegroundWindow(top)
    u.keybd_event(0x12, 0, 2, 0); u.AttachThreadInput(t2, t1, False); time.sleep(0.3)
    return u.GetForegroundWindow() == top

def state():
    p = W.POINT(0, 0); u.ClientToScreen(top, C.byref(p))
    img = ImageGrab.grab(bbox=(p.x + x - 40, p.y + y - 4, p.x + x + 40, p.y + y + 4), all_screens=True).convert('RGB')
    green = sum(1 for i in range(80) if (lambda c: c[1] > 140 and c[0] < 90)(img.getpixel((i, 4))))
    return 'ON' if green > 20 else 'off'

assert front(), 'cannot focus Pulse'
p = W.POINT(x, y); u.ClientToScreen(top, C.byref(p)); u.SetCursorPos(p.x, p.y); time.sleep(0.3)
total = ok = 0
for gap in gaps:
    res = []
    for _ in range(6):
        if not front(): res.append('!fg'); continue
        b = state(); u.mouse_event(2, 0, 0, 0, 0); time.sleep(0.04); u.mouse_event(4, 0, 0, 0, 0); time.sleep(gap); a = state()
        total += 1; ok += a != b
        res.append('%s>%s' % (b, a))
    print('gap %.2fs: %s' % (gap, ' '.join(res)))
print('registered %d / %d clicks' % (ok, total))
