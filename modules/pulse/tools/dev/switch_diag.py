"""Separates the two possible failure modes of a settings switch click:
  A) the click never reaches Flutter          -> no 'savePrefs' line in pulse.log
  B) Flutter handled it but the screen did not update -> log line + frame, pixels unchanged
Uses real mouse input; records foreground before/after each click so runs where another
window stole focus can be discarded.

  python tools/dev/switch_diag.py <appdata> y [clicks]      (switch knob client y, x = 1580)
"""
import ctypes as C, ctypes.wintypes as W, os, sys, time
from PIL import ImageGrab

u = C.windll.user32; u.SetProcessDPIAware()
top = u.FindWindowW('FLUTTER_RUNNER_WIN32_WINDOW', 'Pulse')
log = os.path.join(sys.argv[1], 'Pulse', 'pulse.log')
Y = int(sys.argv[2]); N = int(sys.argv[3]) if len(sys.argv) > 3 else 8; X = 1580

def lines():
    try: return [l for l in open(log, encoding='utf-8') if 'savePrefs' in l]
    except FileNotFoundError: return []

def front():
    for _ in range(5):
        if u.GetForegroundWindow() == top: return True
        fg = u.GetForegroundWindow(); t1 = u.GetWindowThreadProcessId(fg, None); t2 = C.windll.kernel32.GetCurrentThreadId()
        u.AttachThreadInput(t2, t1, True); u.keybd_event(0x12, 0, 0, 0); u.BringWindowToTop(top); u.SetForegroundWindow(top)
        u.keybd_event(0x12, 0, 2, 0); u.AttachThreadInput(t2, t1, False); time.sleep(0.25)
    return False

def org():
    p = W.POINT(0, 0); u.ClientToScreen(top, C.byref(p)); return p

def on():
    p = org(); img = ImageGrab.grab(bbox=(p.x + X - 40, p.y + Y - 4, p.x + X + 40, p.y + Y + 4), all_screens=True).convert('RGB')
    return sum(1 for i in range(80) if (lambda c: c[1] > 140 and c[0] < 90)(img.getpixel((i, 4)))) > 20

for i in range(N):
    if not front(): print(i, 'cannot focus'); continue
    p = org(); u.SetCursorPos(p.x + X, p.y + Y); time.sleep(0.35)
    under = u.GetAncestor(u.WindowFromPoint(W.POINT(p.x + X, p.y + Y)), 2) == top
    n0 = len(lines()); s0 = on()
    u.mouse_event(2, 0, 0, 0, 0); time.sleep(0.04); u.mouse_event(4, 0, 0, 0, 0)
    time.sleep(0.6)
    fg_after = u.GetForegroundWindow() == top
    n1 = len(lines()); s1 = on()
    handled = (n1 - n0) // 2  # each toggle logs 'save' + 'next frame'
    verdict = 'OK' if handled and s1 != s0 else ('NOT-HANDLED(A)' if not handled else 'NO-REPAINT(B)')
    print('click %d: under=%d fgAfter=%d handled=%d pixels %s->%s  %s' % (i, under, fg_after, handled, 'ON' if s0 else 'off', 'ON' if s1 else 'off', verdict), flush=True)
    time.sleep(0.3)
