"""Generates the CML seven-colour flower (七色花) icon.

Outputs windows/runner/resources/app_icon.ico (16–256 px) and assets/logo.png (512 px).
Usage: python tool/gen_icon.py   (needs Pillow)
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
S = 1024  # supersampled canvas
C = S / 2

PETALS = ['#FF4D5E', '#FF9A3C', '#FFD43B', '#4CD964', '#38D1E0', '#3F7CFF', '#A35CFF']


def petal(color, angle):
    """One teardrop petal pointing outwards at [angle] degrees."""
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, h = S * 0.23, S * 0.40  # petal size
    cy = C - S * 0.235          # petal centre above the flower centre
    box = [C - w / 2, cy - h / 2, C + w / 2, cy + h / 2]
    d.ellipse(box, fill=color)
    # lighter inner stripe for depth
    lw, lh = w * 0.42, h * 0.62
    light = tuple(min(255, int(int(color[i:i + 2], 16) * 0.55 + 255 * 0.45)) for i in (1, 3, 5)) + (200,)
    d.ellipse([C - lw / 2, cy - lh / 2 - h * 0.08, C + lw / 2, cy + lh / 2 - h * 0.08], fill=light)
    return layer.rotate(-angle, resample=Image.BICUBIC, center=(C, C))


def build():
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # soft shadow
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    for i, col in enumerate(PETALS):
        shadow.alpha_composite(petal('#000000', i * 360 / 7))
    shadow = shadow.point(lambda v: v)  # noqa
    alpha = shadow.getchannel('A').point(lambda a: a * 0.28)
    shadow.putalpha(alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(S * 0.02))
    img.alpha_composite(shadow, (0, int(S * 0.015)))
    for i, col in enumerate(PETALS):
        img.alpha_composite(petal(col, i * 360 / 7))
    d = ImageDraw.Draw(img)
    r = S * 0.13
    d.ellipse([C - r, C - r, C + r, C + r], fill='#FFE7A0', outline='#F0B429', width=int(S * 0.018))
    r2 = S * 0.065
    d.ellipse([C - r2, C - r2 - S * 0.02, C + r2, C + r2 - S * 0.02], fill='#FFF8E1')
    return img


def main():
    big = build()
    (ROOT / 'assets').mkdir(exist_ok=True)
    big.resize((512, 512), Image.LANCZOS).save(ROOT / 'assets' / 'logo.png')
    ico = ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
    big.resize((256, 256), Image.LANCZOS).save(ico, sizes=[(s, s) for s in (16, 20, 24, 32, 40, 48, 64, 128, 256)])
    print('wrote', ico, ROOT / 'assets' / 'logo.png')


if __name__ == '__main__':
    main()
