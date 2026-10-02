"""Starts cml.exe, performs clicks, and screenshots after each step — to check that the UI repaints
without switching pages.

Usage: python tool/clicktest.py <cml.exe> <page> <outprefix> <x,y> [<x,y> ...]
Coordinates are in screenshot pixels (window-relative, physical). Steps can also be `wait:<sec>`
or `key:<vk>`. Screenshots: <outprefix>_0.png (before), _1.png … (0.8 s after each step).
"""
import ctypes
import subprocess
import sys
import time
from ctypes import wintypes

sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
from shot import find_window, grab  # noqa: E402

user32 = ctypes.windll.user32


def click(hwnd, x, y):
    r = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    user32.SetForegroundWindow(hwnd)
    user32.SetCursorPos(r.left + x, r.top + y)
    time.sleep(0.05)
    user32.mouse_event(0x2, 0, 0, 0, 0)
    time.sleep(0.04)
    user32.mouse_event(0x4, 0, 0, 0, 0)


def main():
    exe, page, out = sys.argv[1], sys.argv[2], sys.argv[3]
    p = subprocess.Popen([exe, '--page', page])
    try:
        hwnd = None
        for _ in range(60):
            time.sleep(0.5)
            hwnd = find_window(p.pid)
            if hwnd:
                break
        time.sleep(7)
        grab(hwnd).save(f'{out}_0.png')
        for i, step in enumerate(sys.argv[4:], 1):
            if step.startswith('wait:'):
                time.sleep(float(step[5:]))
                continue
            if step.startswith('key:'):
                vk = int(step[4:], 0)
                user32.keybd_event(vk, 0, 0, 0)
                user32.keybd_event(vk, 0, 2, 0)
            else:
                x, y = map(int, step.split(','))
                click(hwnd, x, y)
            time.sleep(0.8)
            grab(hwnd).save(f'{out}_{i}.png')
            print(f'{out}_{i}.png')
    finally:
        p.kill()


if __name__ == '__main__':
    main()
