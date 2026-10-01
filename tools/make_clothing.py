"""Paint the disguise outfits as real Roblox classic clothing templates (585x559 shirt / pants PNGs)
and cartoon face decals, so round characters look like proper 2013-era Roblox avatars (The Mad
Murderer's cast): striped shirts, ripped jeans, studded wristbands, checkered belts, sneakers...

Run:  python tools/make_clothing.py      -> blender/textures/clothing/*.png

Template layout (classic shirt/pants): torso faces in the top middle, arms (shirt) / legs (pants)
in the two blocks at the bottom. Pants use the same layout: the "torso" is the hips/belt area.
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "blender" / "textures" / "clothing"
W, H = 585, 559

# (x, y, w, h)
TORSO = {"U": (231, 8, 128, 64), "F": (231, 74, 128, 128), "R": (165, 74, 64, 128), "B": (427, 74, 128, 128),
         "L": (361, 74, 64, 128), "D": (231, 204, 128, 64)}
RIGHT = {"U": (217, 289, 64, 64), "D": (217, 485, 64, 64), "L": (19, 355, 64, 128), "B": (85, 355, 64, 128),
         "R": (151, 355, 64, 128), "F": (217, 355, 64, 128)}
LEFT = {"U": (308, 289, 64, 64), "D": (308, 485, 64, 64), "F": (308, 355, 64, 128), "L": (374, 355, 64, 128),
        "B": (440, 355, 64, 128), "R": (506, 355, 64, 128)}
LIMB_SIDES = ["L", "B", "R", "F"]

try:
    FONT = ImageFont.truetype("arialbd.ttf", 30)
    FONT_SMALL = ImageFont.truetype("arialbd.ttf", 18)
except OSError:
    FONT = ImageFont.load_default()
    FONT_SMALL = FONT

rng = random.Random(7)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def new():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def rect(d, box, color):
    x, y, w, h = box
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=color)


def fabric(img, box, strength=10):
    """Soft noise + a little vertical shading so flat colours read as cloth."""
    x, y, w, h = box
    px = img.load()
    for j in range(h):
        for i in range(w):
            r, g, b, a = px[x + i, y + j]
            if a == 0:
                continue
            n = rng.randint(-strength, strength)
            f = 1.0 - 0.12 * (j / h)
            px[x + i, y + j] = (max(0, min(255, int(r * f) + n)), max(0, min(255, int(g * f) + n)),
                                max(0, min(255, int(b * f) + n)), a)


def all_boxes(parts):
    for part in parts:
        for face in part.values():
            yield face


def fill_parts(img, parts, color):
    d = ImageDraw.Draw(img)
    for box in all_boxes(parts):
        rect(d, box, color)


def stripes(img, parts, c1, c2, band=14, offset=0):
    """Horizontal stripes that line up across every face of the given parts."""
    d = ImageDraw.Draw(img)
    for box in all_boxes(parts):
        x, y, w, h = box
        for j in range(h):
            c = c1 if ((j + offset) // band) % 2 == 0 else c2
            d.line([(x, y + j), (x + w - 1, y + j)], fill=c)


def plaid(img, parts, base, line1, line2, size=16):
    d = ImageDraw.Draw(img)
    for box in all_boxes(parts):
        x, y, w, h = box
        rect(d, box, base)
        for i in range(0, w, size):
            d.rectangle([x + i, y, x + i + size // 3, y + h - 1], fill=line1)
        for j in range(0, h, size):
            d.rectangle([x, y + j, x + w - 1, y + j + size // 3], fill=line1)
        for i in range(size // 2, w, size):
            d.line([(x + i, y), (x + i, y + h - 1)], fill=line2, width=2)
        for j in range(size // 2, h, size):
            d.line([(x, y + j), (x + w - 1, y + j)], fill=line2, width=2)


def camo(img, parts, colors):
    d = ImageDraw.Draw(img)
    for box in all_boxes(parts):
        x, y, w, h = box
        rect(d, box, colors[0])
        for _ in range(w * h // 180):
            cx, cy = x + rng.randint(0, w), y + rng.randint(0, h)
            rx, ry = rng.randint(5, 14), rng.randint(4, 10)
            d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=rng.choice(colors[1:]))
        # keep inside the face
        img.paste(Image.new("RGBA", (1, 1), (0, 0, 0, 0)), (0, 0))


def clip_to_template(img, parts):
    """Anything drawn outside the face boxes (blobs spilling over) is erased."""
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    for box in all_boxes(parts):
        x, y, w, h = box
        md.rectangle([x, y, x + w - 1, y + h - 1], fill=255)
    out = new()
    out.paste(img, (0, 0), mask)
    return out


def limb_band(img, limb, y0, y1, color, sides=LIMB_SIDES):
    """A horizontal band across a limb (wristbands, cuffs, socks). y in limb-face pixels (0..128)."""
    d = ImageDraw.Draw(img)
    for s in sides:
        x, y, w, h = limb[s]
        d.rectangle([x, y + y0, x + w - 1, y + y1], fill=color)


def studs(img, limb, y, color, dot):
    """A studded wristband: a dark band with little square studs."""
    limb_band(img, limb, y, y + 9, color)
    d = ImageDraw.Draw(img)
    for s in LIMB_SIDES:
        x, yy, w, h = limb[s]
        for i in range(3, w - 3, 8):
            d.rectangle([x + i, yy + y + 3, x + i + 3, yy + y + 6], fill=dot)


def sleeves(img, length, skin):
    """Short sleeves: skin below `length` pixels on both arms (and the arm bottoms)."""
    d = ImageDraw.Draw(img)
    for limb in (RIGHT, LEFT):
        for s in LIMB_SIDES:
            x, y, w, h = limb[s]
            d.rectangle([x, y + length, x + w - 1, y + h - 1], fill=skin)
        x, y, w, h = limb["D"]
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=skin)
        if length <= 0:
            x, y, w, h = limb["U"]
            d.rectangle([x, y, x + w - 1, y + h - 1], fill=skin)


def tank_top(img, color, skin, strap_color=None):
    """Bare shoulders and arms, a tank top with straps."""
    sleeves(img, 0, skin)
    d = ImageDraw.Draw(img)
    for f in ("F", "B"):
        x, y, w, h = TORSO[f]
        d.rectangle([x, y, x + w - 1, y + 22], fill=skin)
        d.rectangle([x + 18, y, x + 36, y + 24], fill=strap_color or color)
        d.rectangle([x + w - 37, y, x + w - 19, y + 24], fill=strap_color or color)
        d.pieslice([x + 34, y - 18, x + w - 34, y + 40], 0, 180, fill=skin)
    for f in ("L", "R"):
        x, y, w, h = TORSO[f]
        d.rectangle([x, y, x + w - 1, y + 26], fill=skin)
    x, y, w, h = TORSO["U"]
    d.rectangle([x, y, x + w - 1, y + h - 1], fill=skin)
    d.rectangle([x + 18, y, x + 36, y + h - 1], fill=strap_color or color)
    d.rectangle([x + w - 37, y, x + w - 19, y + h - 1], fill=strap_color or color)


def hoodie_details(img, color, strings=True, pocket=True):
    d = ImageDraw.Draw(img)
    x, y, w, h = TORSO["F"]
    dark = shade(color, 0.75)
    # hood edge round the neck
    d.arc([x + 22, y - 30, x + w - 22, y + 34], 0, 180, fill=dark, width=6)
    if strings:
        d.line([(x + 52, y + 14), (x + 50, y + 54)], fill=(240, 240, 240), width=3)
        d.line([(x + 76, y + 14), (x + 78, y + 54)], fill=(240, 240, 240), width=3)
    if pocket:
        d.rounded_rectangle([x + 26, y + 80, x + w - 26, y + 118], radius=8, outline=dark, width=3, fill=shade(color, 0.92))
    # cuffs
    for limb in (RIGHT, LEFT):
        limb_band(img, limb, 118, 127, dark)
    x, y, w, h = TORSO["F"]
    d.rectangle([x, y + h - 10, x + w - 1, y + h - 1], fill=dark)


def text_on(img, face_box, text, color, font=None, dy=0):
    d = ImageDraw.Draw(img)
    x, y, w, h = face_box
    f = font or FONT
    bbox = d.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((x + (w - tw) / 2, y + (h - th) / 2 + dy), text, font=f, fill=color, stroke_width=2, stroke_fill=(20, 20, 24))


def seams(img, parts, color):
    d = ImageDraw.Draw(img)
    for box in all_boxes(parts):
        x, y, w, h = box
        d.rectangle([x, y, x + w - 1, y + h - 1], outline=color)


# --- pants ---------------------------------------------------------------------------------

def jeans(img, color, rips=False, skin=None, cuff=None):
    fill_parts(img, [TORSO, RIGHT, LEFT], color)
    img2 = img
    fabric(img2, (0, 0, W, H), 8)
    d = ImageDraw.Draw(img)
    # seams down the legs, pockets on the hips
    for limb in (RIGHT, LEFT):
        for s in ("L", "R"):
            x, y, w, h = limb[s]
            d.line([(x + w // 2, y), (x + w // 2, y + h)], fill=shade(color, 0.7), width=2)
    x, y, w, h = TORSO["F"]
    d.arc([x + 4, y + 70, x + 44, y + 120], 270, 360, fill=shade(color, 0.6), width=3)
    d.arc([x + w - 44, y + 70, x + w - 4, y + 120], 180, 270, fill=shade(color, 0.6), width=3)
    d.line([(x + w // 2, y + 74), (x + w // 2, y + h)], fill=shade(color, 0.6), width=3)
    if rips and skin:
        for limb in (RIGHT, LEFT):
            x, y, w, h = limb["F"]
            for ry in (rng.randint(28, 44), rng.randint(70, 90)):
                rx = rng.randint(14, 30)
                d.ellipse([x + rx, y + ry, x + rx + 22, y + ry + 9], fill=(250, 250, 250))
                d.ellipse([x + rx + 3, y + ry + 2, x + rx + 19, y + ry + 7], fill=skin)
    if cuff:
        for limb in (RIGHT, LEFT):
            limb_band(img, limb, 100, 112, cuff)


def shoes(img, color, sole=(245, 245, 245), lace=None, height=18):
    for limb in (RIGHT, LEFT):
        limb_band(img, limb, 128 - height, 127, color)
        limb_band(img, limb, 124, 127, sole)
        x, y, w, h = limb["D"]
        ImageDraw.Draw(img).rectangle([x, y, x + w - 1, y + h - 1], fill=sole)
        if lace:
            d = ImageDraw.Draw(img)
            x, y, w, h = limb["F"]
            for i in range(3):
                d.line([(x + 22, y + 128 - height + 3 + i * 4), (x + 42, y + 128 - height + 3 + i * 4)], fill=lace, width=2)


def belt(img, color, buckle=(220, 200, 120), checker=None):
    d = ImageDraw.Draw(img)
    for f in ("F", "B", "L", "R"):
        x, y, w, h = TORSO[f]
        d.rectangle([x, y + 4, x + w - 1, y + 16], fill=color)
        if checker:
            for i in range(0, w, 8):
                for row in (0, 1):
                    if (i // 8 + row) % 2 == 0:
                        d.rectangle([x + i, y + 4 + row * 6, x + i + 7, y + 9 + row * 6], fill=checker)
    x, y, w, h = TORSO["F"]
    d.rectangle([x + w // 2 - 10, y + 2, x + w // 2 + 10, y + 18], outline=buckle, width=4)


def shorts(img, color, skin, length=60):
    fill_parts(img, [TORSO, RIGHT, LEFT], color)
    fabric(img, (0, 0, W, H), 8)
    for limb in (RIGHT, LEFT):
        limb_band(img, limb, length, 127, skin)
        x, y, w, h = limb["D"]
        ImageDraw.Draw(img).rectangle([x, y, x + w - 1, y + h - 1], fill=skin)
        limb_band(img, limb, length - 6, length - 1, shade(color, 0.7))


def skirt(img, color, skin, length=56, pleats=True):
    shorts(img, color, skin, length)
    if pleats:
        d = ImageDraw.Draw(img)
        for limb in (RIGHT, LEFT):
            for s in LIMB_SIDES:
                x, y, w, h = limb[s]
                for i in range(8, w, 12):
                    d.line([(x + i, y), (x + i, y + length - 6)], fill=shade(color, 0.75), width=2)


# --- the cast -------------------------------------------------------------------------------

SKIN = [rgb("ffcc99"), rgb("eab892"), rgb("cc8e69"), rgb("7c5c46"), rgb("f5cd30")]


def outfit_rose():
    """Red & white striped long-sleeve (one bare shoulder), black wristband, ripped light jeans."""
    skin = SKIN[1]
    shirt = new()
    stripes(shirt, [TORSO, RIGHT, LEFT], rgb("d8262f"), rgb("f2f2f2"), band=12)
    shirt = clip_to_template(shirt, [TORSO, RIGHT, LEFT])
    fabric(shirt, (0, 0, W, H), 6)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.polygon([(x, y), (x + 34, y), (x, y + 30)], fill=skin)  # off-shoulder
    d.rectangle([x + 8, y, x + 16, y + 26], fill=(20, 20, 24))  # bra strap
    limb_band(shirt, LEFT, 98, 104, (25, 25, 28))
    limb_band(shirt, LEFT, 108, 114, (25, 25, 28))
    pants = new()
    jeans(pants, rgb("9fc3e6"), rips=True, skin=skin)
    shoes(pants, rgb("6b6b70"), sole=rgb("3a3a3e"), height=28)
    return shirt, pants


def outfit_kate():
    """White tank top, studded wristbands, checkered belt, dark denim shorts, black & white sneakers."""
    skin = SKIN[1]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("f4f4f4"))
    fabric(shirt, (0, 0, W, H), 10)
    tank_top(shirt, rgb("f4f4f4"), skin, strap_color=(40, 40, 44))
    studs(shirt, RIGHT, 108, (25, 25, 28), (230, 230, 235))
    studs(shirt, LEFT, 30, (25, 25, 28), (230, 230, 235))
    pants = new()
    shorts(pants, rgb("3b4a63"), skin, length=58)
    belt(pants, (30, 30, 32), checker=(240, 240, 240))
    shoes(pants, (25, 25, 28), lace=(240, 240, 240), height=20)
    return shirt, pants


def outfit_nick():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("14bec8"))
    fabric(shirt, (0, 0, W, H))
    hoodie_details(shirt, rgb("14bec8"))
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.line([(x + w // 2, y + 26), (x + w // 2, y + h)], fill=(200, 200, 200), width=3)  # zip
    pants = new()
    jeans(pants, rgb("1b2a35"))
    shoes(pants, (240, 240, 240), lace=(120, 120, 130))
    return shirt, pants


def outfit_frank():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("26262a"))
    fabric(shirt, (0, 0, W, H), 6)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.polygon([(x + 34, y), (x + w - 34, y), (x + w - 46, y + h), (x + 46, y + h)], fill=(240, 240, 240))  # tee under jacket
    d.polygon([(x + 34, y), (x + 50, y + 40), (x + 40, y + 46)], fill=rgb("3a3a40"))  # lapels
    d.polygon([(x + w - 34, y), (x + w - 50, y + 40), (x + w - 40, y + 46)], fill=rgb("3a3a40"))
    for i in range(4):
        d.ellipse([x + 30, y + 54 + i * 16, x + 36, y + 60 + i * 16], fill=(170, 170, 175))
    pants = new()
    jeans(pants, rgb("2c3440"))
    shoes(pants, rgb("5b3a22"), sole=rgb("2a1a10"), height=24)
    return shirt, pants


def outfit_lucy():
    skin = SKIN[0]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("9a5ac8"))
    fabric(shirt, (0, 0, W, H))
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    # a big heart
    d.ellipse([x + 36, y + 40, x + 66, y + 70], fill=rgb("ff6fae"))
    d.ellipse([x + 62, y + 40, x + 92, y + 70], fill=rgb("ff6fae"))
    d.polygon([(x + 38, y + 60), (x + 90, y + 60), (x + 64, y + 96)], fill=rgb("ff6fae"))
    limb_band(shirt, RIGHT, 112, 127, shade(rgb("9a5ac8"), 0.75))
    limb_band(shirt, LEFT, 112, 127, shade(rgb("9a5ac8"), 0.75))
    pants = new()
    skirt(pants, rgb("2c2f5a"), skin, length=60)
    for limb in (RIGHT, LEFT):
        stripes_box = limb
        d2 = ImageDraw.Draw(pants)
        for s in LIMB_SIDES:
            x, y, w, h = limb[s]
            for j in range(64, 110, 10):
                d2.rectangle([x, y + j, x + w - 1, y + j + 4], fill=(240, 240, 240))
    shoes(pants, rgb("c8264a"), sole=(250, 250, 250), height=16)
    return shirt, pants


def outfit_jake():
    skin = SKIN[2]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("f0f0f0"))
    fabric(shirt, (0, 0, W, H))
    sleeves(shirt, 46, skin)
    for limb in (RIGHT, LEFT):
        limb_band(shirt, limb, 36, 45, rgb("cc2a2a"))
    text_on(shirt, TORSO["F"], "23", rgb("cc2a2a"), dy=6)
    text_on(shirt, TORSO["B"], "JAKE", rgb("cc2a2a"), font=FONT_SMALL, dy=-30)
    text_on(shirt, TORSO["B"], "23", rgb("cc2a2a"), dy=10)
    pants = new()
    jeans(pants, rgb("3c5aa0"))
    shoes(pants, rgb("cc2a2a"), sole=(250, 250, 250), lace=(250, 250, 250))
    return shirt, pants


def outfit_emma():
    shirt = new()
    plaid(shirt, [TORSO, RIGHT, LEFT], rgb("2f8f4e"), rgb("226b39"), rgb("8fd6a0"))
    shirt = clip_to_template(shirt, [TORSO, RIGHT, LEFT])
    fabric(shirt, (0, 0, W, H), 6)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.line([(x + w // 2, y), (x + w // 2, y + h)], fill=(30, 50, 35), width=3)
    for i in range(5):
        d.ellipse([x + w // 2 + 4, y + 14 + i * 22, x + w // 2 + 9, y + 19 + i * 22], fill=(240, 240, 230))
    pants = new()
    jeans(pants, rgb("6b4a30"))
    shoes(pants, rgb("3a2516"), sole=rgb("1e140c"), height=30)
    return shirt, pants


def outfit_oscar():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("ff9a28"))
    fabric(shirt, (0, 0, W, H))
    hoodie_details(shirt, rgb("ff9a28"))
    text_on(shirt, TORSO["F"], "OZ", (30, 30, 30), dy=-12)
    pants = new()
    fill_parts(pants, [TORSO, RIGHT, LEFT], rgb("1e1e22"))
    fabric(pants, (0, 0, W, H))
    for limb in (RIGHT, LEFT):
        d = ImageDraw.Draw(pants)
        for s in ("L", "R"):
            x, y, w, h = limb[s]
            d.rectangle([x + w // 2 - 4, y, x + w // 2 + 4, y + h - 1], fill=(240, 240, 240))
    shoes(pants, (240, 240, 240), lace=(30, 30, 30))
    return shirt, pants


def outfit_mia():
    skin = SKIN[0]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("ffe25a"))
    fabric(shirt, (0, 0, W, H))
    sleeves(shirt, 40, skin)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.ellipse([x + 38, y + 30, x + 90, y + 82], outline=(40, 40, 40), width=4)  # smiley
    d.ellipse([x + 52, y + 44, x + 58, y + 52], fill=(40, 40, 40))
    d.ellipse([x + 70, y + 44, x + 76, y + 52], fill=(40, 40, 40))
    d.arc([x + 50, y + 50, x + 78, y + 72], 20, 160, fill=(40, 40, 40), width=4)
    # crop: skin at the bottom
    for f in ("F", "B", "L", "R"):
        x, y, w, h = TORSO[f]
        d.rectangle([x, y + h - 18, x + w - 1, y + h - 1], fill=skin)
    pants = new()
    jeans(pants, rgb("78aee6"), cuff=rgb("a8cdf2"))
    shoes(pants, (250, 250, 250), lace=(255, 120, 180))
    return shirt, pants


def outfit_leo():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("a81e2c"))
    fabric(shirt, (0, 0, W, H), 6)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.polygon([(x + 40, y), (x + w - 40, y), (x + w // 2, y + 70)], fill=(245, 245, 245))  # shirt V
    d.polygon([(x + w // 2 - 6, y + 4), (x + w // 2 + 6, y + 4), (x + w // 2 + 8, y + 50), (x + w // 2, y + 60), (x + w // 2 - 8, y + 50)], fill=(20, 20, 20))  # tie
    for i in range(2):
        d.ellipse([x + 54, y + 80 + i * 18, x + 60, y + 86 + i * 18], fill=(220, 190, 90))
    for limb in (RIGHT, LEFT):
        limb_band(shirt, limb, 116, 127, (245, 245, 245))
    pants = new()
    fill_parts(pants, [TORSO, RIGHT, LEFT], rgb("1c1c22"))
    fabric(pants, (0, 0, W, H), 5)
    shoes(pants, (15, 15, 18), sole=(5, 5, 5), height=16)
    return shirt, pants


def outfit_zoe():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("3cc8e6"))
    fabric(shirt, (0, 0, W, H))
    d = ImageDraw.Draw(shirt)
    for limb in (RIGHT, LEFT):
        for s in ("L", "R"):
            x, y, w, h = limb[s]
            for k in range(3):
                d.rectangle([x + 18 + k * 10, y, x + 22 + k * 10, y + h - 1], fill=(250, 250, 250))
    x, y, w, h = TORSO["F"]
    d.line([(x + w // 2, y), (x + w // 2, y + h)], fill=(240, 240, 240), width=4)
    pants = new()
    fill_parts(pants, [TORSO, RIGHT, LEFT], rgb("f2f2f2"))
    fabric(pants, (0, 0, W, H))
    for limb in (RIGHT, LEFT):
        d2 = ImageDraw.Draw(pants)
        for s in ("L", "R"):
            x, y, w, h = limb[s]
            d2.rectangle([x + w // 2 - 3, y, x + w // 2 + 3, y + h - 1], fill=rgb("3cc8e6"))
    shoes(pants, rgb("3cc8e6"), sole=(250, 250, 250), lace=(250, 250, 250))
    return shirt, pants


def outfit_max():
    shirt = new()
    camo(shirt, [TORSO, RIGHT, LEFT], [rgb("4a6b3a"), rgb("2f4a26"), rgb("6b8a4a"), rgb("8a7a52")])
    shirt = clip_to_template(shirt, [TORSO, RIGHT, LEFT])
    pants = new()
    fill_parts(pants, [TORSO, RIGHT, LEFT], rgb("a08a5e"))
    fabric(pants, (0, 0, W, H))
    d = ImageDraw.Draw(pants)
    for limb in (RIGHT, LEFT):
        for s in ("L", "R"):
            x, y, w, h = limb[s]
            d.rectangle([x + 8, y + 40, x + w - 8, y + 70], outline=shade(rgb("a08a5e"), 0.7), width=3)  # cargo pocket
    belt(pants, rgb("3a2a18"))
    shoes(pants, rgb("3a2a18"), sole=(20, 15, 10), height=30)
    return shirt, pants


def outfit_ruby():
    skin = SKIN[1]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("c8283c"))
    fabric(shirt, (0, 0, W, H), 8)
    tank_top(shirt, rgb("c8283c"), skin)
    d = ImageDraw.Draw(shirt)
    for f in ("F", "B", "L", "R"):
        x, y, w, h = TORSO[f]
        d.rectangle([x, y + 70, x + w - 1, y + 78], fill=(20, 20, 20))  # waist ribbon
    studs(shirt, LEFT, 104, (20, 20, 22), (240, 200, 90))
    pants = new()
    skirt(pants, rgb("b01e32"), skin, length=70)
    shoes(pants, (20, 20, 22), sole=(10, 10, 10), height=34)
    return shirt, pants


def outfit_sam():
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("7a7a84"))
    fabric(shirt, (0, 0, W, H))
    hoodie_details(shirt, rgb("7a7a84"))
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    # skull print
    d.ellipse([x + 44, y + 34, x + 84, y + 70], fill=(240, 240, 240))
    d.rectangle([x + 52, y + 62, x + 76, y + 78], fill=(240, 240, 240))
    d.ellipse([x + 52, y + 46, x + 62, y + 56], fill=(40, 40, 46))
    d.ellipse([x + 66, y + 46, x + 76, y + 56], fill=(40, 40, 46))
    pants = new()
    fill_parts(pants, [TORSO, RIGHT, LEFT], rgb("3c3c46"))
    fabric(pants, (0, 0, W, H))
    for limb in (RIGHT, LEFT):
        limb_band(pants, limb, 112, 127, rgb("2a2a32"))
    shoes(pants, (240, 240, 240), lace=(40, 40, 40))
    return shirt, pants


def outfit_ivy():
    skin = SKIN[2]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("fafafa"))
    fabric(shirt, (0, 0, W, H), 6)
    sleeves(shirt, 50, skin)
    d = ImageDraw.Draw(shirt)
    x, y, w, h = TORSO["F"]
    d.polygon([(x + 44, y + 6), (x + 64, y + 18), (x + 44, y + 30)], fill=rgb("7a3ca0"))  # bow
    d.polygon([(x + 84, y + 6), (x + 64, y + 18), (x + 84, y + 30)], fill=rgb("7a3ca0"))
    d.ellipse([x + 58, y + 12, x + 70, y + 24], fill=rgb("5a2a80"))
    for limb in (RIGHT, LEFT):
        limb_band(shirt, limb, 42, 49, rgb("e0d0f0"))
    pants = new()
    skirt(pants, rgb("7a3ca0"), skin, length=60)
    shoes(pants, (250, 250, 250), sole=(200, 200, 210), height=14)
    return shirt, pants


def outfit_ben():
    skin = SKIN[4]
    shirt = new()
    fill_parts(shirt, [TORSO, RIGHT, LEFT], rgb("ffffff"))
    fabric(shirt, (0, 0, W, H), 8)
    tank_top(shirt, rgb("ffffff"), skin)
    text_on(shirt, TORSO["F"], "BEN", rgb("c8282c"), dy=10)
    limb_band(shirt, RIGHT, 100, 110, rgb("c8282c"))
    pants = new()
    shorts(pants, rgb("a8222a"), skin, length=54)
    shoes(pants, (240, 240, 240), lace=rgb("a8222a"))
    for limb in (RIGHT, LEFT):
        limb_band(pants, limb, 96, 108, (250, 250, 250))  # tall socks
    return shirt, pants


OUTFITS = {
    "Rose": outfit_rose, "Kate": outfit_kate, "Nick": outfit_nick, "Frank": outfit_frank, "Lucy": outfit_lucy,
    "Jake": outfit_jake, "Emma": outfit_emma, "Oscar": outfit_oscar, "Mia": outfit_mia, "Leo": outfit_leo,
    "Zoe": outfit_zoe, "Max": outfit_max, "Ruby": outfit_ruby, "Sam": outfit_sam, "Ivy": outfit_ivy, "Ben": outfit_ben,
}


# --- faces ------------------------------------------------------------------------------------

def face(kind):
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = (20, 20, 22)
    ex, ey = 88, 100  # eye centres: (128 +- 40, 100)
    if kind in ("Smile", "Smirk", "Happy", "Grin", "Freckles", "Lashes", "Cool"):
        for x in (128 - 40, 128 + 40):
            d.ellipse([x - 9, ey - 16, x + 9, ey + 16], fill=ink)
            d.ellipse([x - 4, ey - 12, x + 1, ey - 5], fill=(255, 255, 255))
    if kind == "Lashes":
        for x in (88, 168):
            for i in (-1, 0, 1):
                d.line([(x + i * 6, ey - 15), (x + i * 9, ey - 26)], fill=ink, width=3)
    if kind == "Chill":
        for x in (88, 168):
            d.chord([x - 14, ey - 10, x + 14, ey + 14], 0, 180, fill=ink)
            d.line([(x - 16, ey + 1), (x + 16, ey + 1)], fill=ink, width=4)
    if kind == "Angry":
        for x, s in ((88, 1), (168, -1)):
            d.ellipse([x - 9, ey - 10, x + 9, ey + 16], fill=ink)
            d.line([(x - 18 * s, ey - 26), (x + 14 * s, ey - 12)], fill=ink, width=7)
    mouth_y = 168
    if kind in ("Smile", "Lashes", "Freckles", "Cool"):
        d.arc([88, mouth_y - 40, 168, mouth_y + 10], 25, 155, fill=ink, width=7)
    elif kind == "Smirk":
        d.arc([100, mouth_y - 30, 176, mouth_y + 10], 20, 120, fill=ink, width=7)
    elif kind == "Happy":
        d.chord([86, mouth_y - 40, 170, mouth_y + 24], 10, 170, fill=ink)
        d.chord([104, mouth_y - 4, 152, mouth_y + 22], 20, 160, fill=(220, 70, 80))
    elif kind == "Grin":
        d.chord([80, mouth_y - 44, 176, mouth_y + 20], 10, 170, fill=ink)
        d.rectangle([92, mouth_y - 12, 164, mouth_y], fill=(255, 255, 255))
    elif kind == "Chill":
        d.line([(100, mouth_y), (156, mouth_y - 6)], fill=ink, width=7)
    elif kind == "Angry":
        d.arc([96, mouth_y - 6, 160, mouth_y + 34], 200, 340, fill=ink, width=7)
    if kind == "Freckles":
        for x0 in (70, 168):
            for dx, dy in ((0, 0), (10, 4), (4, 12), (14, 14)):
                d.ellipse([x0 + dx, 128 + dy, x0 + dx + 4, 132 + dy], fill=(190, 110, 80))
    if kind in ("Lashes", "Freckles", "Happy"):
        for x0 in (60, 172):
            d.ellipse([x0, 128, x0 + 26, 144], fill=(255, 120, 130, 120))
    # Features drawn small; crop the middle and blow it up so they fill a Roblox head nicely
    return img.crop((40, 46, 216, 222)).resize((S, S), Image.LANCZOS)


FACES = ["Smile", "Smirk", "Happy", "Grin", "Chill", "Angry", "Freckles", "Lashes"]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in OUTFITS.items():
        shirt, pants = build()
        shirt.save(OUT / f"{name}_shirt.png")
        pants.save(OUT / f"{name}_pants.png")
    for kind in FACES:
        face(kind).save(OUT / f"face_{kind}.png")
    # A contact sheet to eyeball everything
    sheet = Image.new("RGBA", (W * 4 // 2, (H // 2) * 8), (30, 28, 40, 255))
    for i, name in enumerate(OUTFITS):
        shirt = Image.open(OUT / f"{name}_shirt.png").resize((W // 2, H // 2))
        sheet.alpha_composite(shirt, ((i % 4) * (W // 2), (i // 4) * (H // 2)))
    sheet.save(ROOT / "blender" / "previews" / "clothing_sheet.png")
    print("done", len(OUTFITS), "outfits")


main()
