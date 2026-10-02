"""Textures for the toy look (Steal An Egg / Tsunami style) and the knife effects.

  python tools/make_toy_textures.py -> blender/textures/toy/{stud,checker,swirl,money}.png

  stud.png     one embossed square stud (light top-left edge, dark bottom-right), transparent
               around it: tiled 1 per stud over floors and walls, tinted by the Texture's colour
  checker.png  a 2x2 checker of faint white / clear squares: tiled every 16 studs it gives the
               two-tone squares, whatever colour the surface is
  swirl.png    a soft three-armed swirl for the auras that spin around knives
  money.png    a little green bill with a $ for the money rising off knives
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "blender" / "textures" / "toy"


def stud():
    """Classic Roblox studs, 2x2 per image (tile every 2 studs = 1 stud each), crisp like Steal An
    Egg's: a small square ring per cell, dark on the top/left edges, light on the bottom/right."""
    s = 128
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s // 2
    a, b, w = 17, 47, 4  # ring from a to b, edge width w
    for ox in (0, c):
        for oy in (0, c):
            x0, y0, x1, y1 = ox + a, oy + a, ox + b, oy + b
            d.rectangle([x0, y0, x1, y0 + w - 1], fill=(0, 0, 0, 80))  # top
            d.rectangle([x0, y0, x0 + w - 1, y1], fill=(0, 0, 0, 80))  # left
            d.rectangle([x0 + w, y1 - w + 1, x1, y1], fill=(255, 255, 255, 70))  # bottom
            d.rectangle([x1 - w + 1, y0 + w, x1, y1], fill=(255, 255, 255, 70))  # right
    return img


def checker():
    """2x2 checker of two close shades: one square a touch lighter, the other a touch darker."""
    s = 256
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    h = s // 2
    d.rectangle([0, 0, h - 1, h - 1], fill=(255, 255, 255, 16))
    d.rectangle([h, h, s - 1, s - 1], fill=(255, 255, 255, 16))
    d.rectangle([h, 0, s - 1, h - 1], fill=(0, 0, 0, 12))
    d.rectangle([0, h, h - 1, s - 1], fill=(0, 0, 0, 12))
    return img


def swirl():
    s = 256
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    for arm in range(3):
        base = arm * 2 * math.pi / 3
        pts = []
        for i in range(120):
            t = i / 119
            a = base + t * 3.4
            r = 12 + t * 105
            pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
        for i in range(len(pts) - 1):
            t = i / (len(pts) - 1)
            width = int(4 + 14 * math.sin(t * math.pi))
            alpha = int(255 * math.sin(t * math.pi) ** 0.8)
            d.line([pts[i], pts[i + 1]], fill=(255, 255, 255, alpha), width=width)
    return img.filter(ImageFilter.GaussianBlur(3))


def money():
    w, h = 128, 72
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, w - 3, h - 3], radius=8, fill=(70, 190, 90, 255), outline=(30, 110, 50, 255), width=4)
    d.rounded_rectangle([12, 10, w - 13, h - 11], radius=6, outline=(180, 245, 180, 255), width=3)
    d.ellipse([w / 2 - 20, h / 2 - 20, w / 2 + 20, h / 2 + 20], fill=(120, 220, 130, 255), outline=(30, 110, 50, 255), width=3)
    try:
        font = ImageFont.truetype("arialbd.ttf", 34)
    except OSError:
        font = ImageFont.load_default()
    d.text((w / 2, h / 2 + 1), "$", fill=(25, 95, 40, 255), font=font, anchor="mm")
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in (("stud", stud), ("checker", checker), ("swirl", swirl), ("money", money)):
        make().save(OUT / f"{name}.png")
        print("wrote", name)


if __name__ == "__main__":
    main()
