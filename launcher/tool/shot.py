"""Starts cml.exe on a navigation page and saves a screenshot of its window.

Usage: python tool/shot.py <cml.exe> <page index> <out.png> [wait seconds] [extra cml args…]
Uses PrintWindow (PW_RENDERFULLCONTENT) so the window does not need to be in front.
"""
import ctypes
import subprocess
import sys
import time
from ctypes import wintypes

from PIL import Image

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
user32.SetProcessDPIAware()


def find_window(pid):
    found = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def cb(hwnd, _):
        p = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    return found[0] if found else None


def grab(hwnd):
    r = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    w, h = r.right - r.left, r.bottom - r.top
    hdc = user32.GetWindowDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mdc, bmp)
    user32.PrintWindow(hwnd, mdc, 2)
    buf = ctypes.create_string_buffer(w * h * 4)
    bi = (ctypes.c_uint32 * 10)(40, w, -h, 1 | (32 << 16), 0, 0, 0, 0, 0, 0)
    gdi32.GetDIBits(mdc, bmp, 0, h, buf, bi, 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mdc)
    user32.ReleaseDC(hwnd, hdc)
    return Image.frombuffer('RGBA', (w, h), buf, 'raw', 'BGRA', 0, 1).convert('RGB')


def main():
    exe, page, out = sys.argv[1], sys.argv[2], sys.argv[3]
    wait = float(sys.argv[4]) if len(sys.argv) > 4 else 8
    p = subprocess.Popen([exe, '--page', page, *sys.argv[5:]])
    try:
        hwnd = None
        for _ in range(60):
            time.sleep(0.5)
            hwnd = find_window(p.pid)
            if hwnd:
                break
        if not hwnd:
            sys.exit('window not found')
        time.sleep(wait)
        grab(hwnd).save(out)
        print(out)
    finally:
        p.kill()


if __name__ == '__main__':
    main()
