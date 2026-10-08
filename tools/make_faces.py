"""Draw the round characters' faces (transparent PNGs for the head's face decal).

  python tools/make_faces.py          -> blender/textures/clothing/face_<Name>.png (512x512)
                                         + blender/previews/faces_sheet.png (on a skin tone)

Drawn at 4x and scaled down so every curve is smooth. Classic Roblox proportions: big expressive
eyes in the upper half (white, coloured iris, pupil, two highlights, a heavy upper lid), shaped
eyebrows, and a mouth with real shape (lips, teeth, tongue) in the lower half. The eyes sit a little
below the top third so hair fringes (which stop at the eyebrows) never cover them.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "blender" / "textures" / "clothing"
SIZE = 512
K = 4  # supersampling
S = SIZE * K

INK = (22, 18, 26, 255)
WHITE = (255, 255, 255, 255)
BLUSH = (255, 110, 130, 95)
TEETH = (250, 250, 245, 255)
TONGUE = (235, 90, 105, 255)
MOUTH = (70, 18, 30, 255)
LIP = (200, 90, 100, 255)

# Keep the boss names/awake expressions explicit; the sleeping guides use the SAME design
# coordinates and final crop as make(), including Angry's +1 and Determined's +0.5 eye offset.
BOSS_AWAKE = {
    "Frank": "Angry", "Ivy": "Smile", "Sam": "Surprised", "Leo": "Smirk",
    "Ruby": "Determined", "Kate": "Smirk", "Zoe": "Happy", "Nick": "Determined",
}
BOSS_SKIN = {
    "Frank": (234, 184, 146), "Ivy": (204, 142, 105), "Sam": (255, 204, 153),
    "Leo": (204, 142, 105), "Ruby": (234, 184, 146), "Kate": (234, 184, 146),
    "Zoe": (124, 92, 70), "Nick": (245, 205, 48),
}


def P(x, y):
    """Design space is 0..100 on both axes."""
    return (x / 100 * S, y / 100 * S)


def box(x0, y0, x1, y1):
    a, b = P(x0, y0), P(x1, y1)
    return [a[0], a[1], b[0], b[1]]


def w(v):
    return int(v / 100 * S)


def bezier(points, steps=40):
    """Quadratic/cubic bezier through control points (design space) -> list of pixel points."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        pts = [P(*p) for p in points]
        while len(pts) > 1:
            pts = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(pts, pts[1:])]
        out.append(pts[0])
    return out


def thick_curve(d, points, width, color):
    line = bezier(points)
    d.line(line, fill=color, width=w(width), joint="curve")
    r = w(width) / 2
    for x, y in (line[0], line[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def eye(d, cx, cy, iris=(90, 60, 40), look=(0.0, 0.0), open_=1.0, lashes=False, mirror=1):
    """An eye centred at (cx, cy): white, outlined, a big iris + pupil, two highlights, a heavy
    upper lid. open_ < 1 makes it sleepy/narrow."""
    ew, eh = 7.5, 9.0 * open_
    d.ellipse(box(cx - ew, cy - eh, cx + ew, cy + eh), fill=INK)
    d.ellipse(box(cx - ew + 1.1, cy - eh + 1.1, cx + ew - 1.1, cy + eh - 1.1), fill=WHITE)
    ix, iy = cx + look[0] * 2.2, cy + look[1] * 2.2 + 0.8
    ir = min(5.6, eh - 1.0)
    d.ellipse(box(ix - ir, iy - ir * 1.1, ix + ir, iy + ir * 1.1), fill=iris + (255,))
    # darker ring + pupil
    d.ellipse(box(ix - ir * 0.62, iy - ir * 0.7, ix + ir * 0.62, iy + ir * 0.7), fill=tuple(int(c * 0.55) for c in iris) + (255,))
    d.ellipse(box(ix - ir * 0.38, iy - ir * 0.42, ix + ir * 0.38, iy + ir * 0.42), fill=INK)
    # highlights
    d.ellipse(box(ix - ir * 0.75, iy - ir * 0.95, ix - ir * 0.05, iy - ir * 0.25), fill=WHITE)
    d.ellipse(box(ix + ir * 0.25, iy + ir * 0.3, ix + ir * 0.6, iy + ir * 0.65), fill=WHITE)
    # heavy upper lid (cuts the top of the white so the eye has a shape, not a circle)
    lid_y = cy - eh + 1.6
    d.chord(box(cx - ew - 0.6, cy - eh - 4, cx + ew + 0.6, lid_y + 2.4), 0, 180, fill=INK)
    if lashes:
        for i in range(3):
            x0 = cx + mirror * (ew - 0.5 - i * 2.2)
            thick_curve(d, [(x0, cy - eh + 1.5), (x0 + mirror * 1.6, cy - eh - 1.5), (x0 + mirror * 3.4, cy - eh - 2.2)],
                        1.0, INK)


def closed_eye(d, cx, cy, happy=True):
    """^ shaped (happy) or a soft down-curve (wink)."""
    if happy:
        thick_curve(d, [(cx - 6.5, cy + 2), (cx, cy - 5), (cx + 6.5, cy + 2)], 2.0, INK)
    else:
        thick_curve(d, [(cx - 6.5, cy - 1), (cx, cy + 4), (cx + 6.5, cy - 1)], 2.0, INK)


def brow(d, cx, cy, tilt=0.0, arch=1.5, width=2.4, mirror=1):
    """An eyebrow over an eye at cx. tilt > 0 = angry (inner end down)."""
    inner = cx - mirror * 6.5
    outer = cx + mirror * 6.5
    thick_curve(d, [(outer, cy + 0.5), (cx, cy - arch), (inner, cy + tilt)], width, INK)


def blush(d, cx, cy):
    d.ellipse(box(cx - 6, cy - 2.6, cx + 6, cy + 2.6), fill=BLUSH)


def freckles(d, cx, cy):
    for dx, dy in ((-3, 0), (0, 1.6), (3, 0.2), (-1.4, -1.6), (1.6, -1.2)):
        d.ellipse(box(cx + dx - 0.55, cy + dy - 0.55, cx + dx + 0.55, cy + dy + 0.55), fill=(170, 100, 70, 220))


def smile(d, cx, cy, width=15, depth=6, thickness=2.0):
    thick_curve(d, [(cx - width / 2, cy - 1), (cx, cy + depth), (cx + width / 2, cy - 1)], thickness, INK)
    # little dimples at the corners
    for s in (-1, 1):
        thick_curve(d, [(cx + s * (width / 2 + 0.2), cy - 2.2), (cx + s * (width / 2 + 1.1), cy - 0.6),
                        (cx + s * (width / 2 + 0.4), cy + 0.6)], 1.2, INK)


def open_mouth(d, cx, cy, width=18, depth=11, teeth=True, tongue=True):
    """A big open D-shaped smile with a top row of teeth and a tongue."""
    top = cy - 1
    pts = bezier([(cx - width / 2, top), (cx - width / 2 + 1, top + depth * 1.35), (cx + width / 2 - 1, top + depth * 1.35),
                  (cx + width / 2, top)], steps=48)
    d.polygon(pts, fill=MOUTH, outline=INK)
    d.line(pts + [pts[0]], fill=INK, width=w(1.6), joint="curve")
    if teeth:
        d.rectangle(box(cx - width / 2 + 1.6, top + 0.3, cx + width / 2 - 1.6, top + 2.8), fill=TEETH)
    if tongue:
        d.ellipse(box(cx - width * 0.28, top + depth * 0.55, cx + width * 0.28, top + depth * 1.1), fill=TONGUE)


def sleeping_eye(d, cx, cy, width=2.4, lashes=False, mirror=1):
    """Relaxed downward lid, centred where the awake eye is; never a happy ^ or a letter."""
    thick_curve(d, [(cx - 6.5, cy - 1.2), (cx, cy + 3.2), (cx + 6.5, cy - 1.2)], width, INK)
    if lashes:
        for i in range(3):
            x = cx + mirror * (6.3 - i * 1.8)
            thick_curve(d, [(x, cy - .7), (x + mirror * 1.2, cy - 1.6),
                            (x + mirror * 2.3, cy - 2.0)], 1.0, INK)


def drool(d, cx, cy, scale=1):
    """A tiny teardrop, not a stream; separate from the mouth so its slack shape stays clear."""
    left = bezier([(cx, cy), (cx - 1.8 * scale, cy + 2.3 * scale),
                   (cx - 1.8 * scale, cy + 4.5 * scale), (cx, cy + 4.8 * scale)])
    right = bezier([(cx, cy + 4.8 * scale), (cx + 1.8 * scale, cy + 4.5 * scale),
                    (cx + 1.8 * scale, cy + 2.3 * scale), (cx, cy)])
    points = left + right
    d.polygon(points, fill=(130, 211, 244, 235))
    d.line(points, fill=(48, 129, 175, 235), width=w(.5), joint="curve")
    thick_curve(d, [(cx - .45 * scale, cy + 2.9 * scale),
                    (cx - .45 * scale, cy + 3.5 * scale)], .48 * scale, (231, 250, 255, 225))


def sleeping_face(d, boss, lx, rx, ey, by, mx, my):
    awake = BOSS_AWAKE[boss]
    eye_y = ey + (1 if awake == "Angry" else .5 if awake == "Determined" else 0)
    brow_width = 3.0 if awake == "Angry" else 2.8 if awake == "Determined" else 2.4
    lid_width = 2.7 if awake == "Angry" else 2.5 if awake == "Determined" else 2.2
    for x, mirror in ((lx, -1), (rx, 1)):
        sleeping_eye(d, x, eye_y, lid_width, lashes=awake == "Lashes", mirror=mirror)
        # Angry/Determined retain their thick brows, with their inward frown removed.
        # Smirk retains the raised-brow asymmetry, softened and lowered on both sides.
        brow_y = by + (1.5 if awake == "Smirk" and mirror < 0 else 1.0)
        arch = .40 if awake == "Smirk" and mirror < 0 else .75 if awake in ("Smirk", "Surprised", "Happy") else .45
        brow(d, x, brow_y, tilt=.25, arch=arch, width=brow_width, mirror=mirror)

    if boss == "Frank":
        thick_curve(d, [(mx - 4.5, my + .8), (mx, my + 1.4), (mx + 4.5, my + .8)], 2.2, INK)
        drool(d, mx + 4.5, my + 2.0, .80)
    elif boss == "Ivy":
        thick_curve(d, [(mx - 4.5, my), (mx, my + 2.2), (mx + 4.5, my)], 1.8, INK)
        for x in (lx - 3, rx + 3):
            d.ellipse(box(x - 4.8, ey + 9.3, x + 4.8, ey + 13.2), fill=(255, 128, 149, 42))
    elif boss == "Sam":
        d.ellipse(box(mx - 2.6, my - 1.4, mx + 2.6, my + 4.4), fill=MOUTH, outline=INK, width=w(1.15))
    elif boss == "Leo":
        thick_curve(d, [(mx - 4.2, my + 1.1), (mx + 1, my + 1.7), (mx + 5, my + .3)], 1.9, INK)
        drool(d, mx + 4.3, my + 1.8, .64)
    elif boss == "Ruby":
        thick_curve(d, [(mx - 4, my + 1), (mx, my + 1.35), (mx + 4, my + 1)], 2.0, INK)
        drool(d, mx - 3.7, my + 2.1, .70)
    elif boss == "Kate":
        thick_curve(d, [(mx - 4.5, my + .3), (mx, my + 1.8), (mx + 4.5, my + 1)], 1.8, INK)
        drool(d, mx - 4.1, my + 1.8, .58)
    elif boss == "Zoe":
        for x, mirror in ((lx, -1), (rx, 1)):
            d.ellipse(box(x - mirror * 4 - 5.2, ey + 8.8, x - mirror * 4 + 5.2, ey + 13.2), fill=(255, 110, 130, 55))
        d.ellipse(box(mx - 2, my - 2, mx + 2, my + 2.8), fill=MOUTH, outline=INK, width=w(1.1))
    elif boss == "Nick":
        d.ellipse(box(mx - 2.25, my - 1.1, mx + 2.25, my + 4.0), fill=MOUTH, outline=INK, width=w(1.2))


def make(name):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lx, rx, ey = 35, 65, 40  # eye centres (design space)
    by = 27.5  # eyebrows
    mx, my = 50, 70  # mouth
    brown, blue, green, hazel = (110, 70, 40), (60, 130, 220), (70, 160, 90), (150, 110, 50)

    if name.startswith("Sleep"):
        sleeping_face(d, name[5:], lx, rx, ey, by, mx, my)
    elif name == "Smile":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, brown)
            brow(d, x, by, mirror=m)
        smile(d, mx, my)
    elif name == "Grin":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, blue, look=(0, -0.2))
            brow(d, x, by - 1, arch=2.2, mirror=m)
        open_mouth(d, mx, my - 2, width=22, depth=8, tongue=False)
    elif name == "Happy":
        for x, m in ((lx, -1), (rx, 1)):
            closed_eye(d, x, ey, happy=True)
            brow(d, x, by - 1.5, arch=2.0, mirror=m)
            blush(d, x - m * 4, ey + 11)
        open_mouth(d, mx, my - 2, width=18, depth=10)
    elif name == "Smirk":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, hazel, look=(0.4, 0), open_=0.85)
        brow(d, lx, by + 0.5, arch=0.8, mirror=-1)
        brow(d, rx, by - 2.5, arch=2.6, mirror=1)  # one raised
        thick_curve(d, [(mx - 6, my + 1), (mx + 3, my + 2.5), (mx + 9, my - 3)], 2.0, INK)
    elif name == "Chill":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey + 1.5, green, open_=0.55, look=(-0.3, 0.2))
            brow(d, x, by + 1.5, arch=0.6, mirror=m)
        thick_curve(d, [(mx - 7, my + 1), (mx, my + 1.6), (mx + 7, my - 0.4)], 2.0, INK)
    elif name == "Angry":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey + 1, brown, open_=0.8)
            brow(d, x, by + 1, tilt=5.0, arch=-0.5, width=3.0, mirror=m)
        # gritted teeth
        d.rounded_rectangle(box(mx - 9, my - 1, mx + 9, my + 5), radius=w(2), fill=TEETH, outline=INK, width=w(1.6))
        d.line([P(mx - 9, my + 2), P(mx + 9, my + 2)], fill=INK, width=w(0.9))
        for x in (-4.5, 0, 4.5):
            d.line([P(mx + x, my - 1), P(mx + x, my + 5)], fill=INK, width=w(0.9))
    elif name == "Freckles":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, green)
            brow(d, x, by, arch=1.8, mirror=m)
            freckles(d, x - m * 3, ey + 12)
            blush(d, x - m * 3, ey + 12)
        smile(d, mx, my, width=13, depth=5)
    elif name == "Lashes":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, blue, lashes=True, mirror=m)
            brow(d, x, by - 1.2, arch=2.2, width=1.8, mirror=m)
            blush(d, x - m * 3, ey + 12)
        smile(d, mx, my, width=12, depth=5)
        # a hint of lip colour
        thick_curve(d, [(mx - 3, my + 4.6), (mx, my + 5.6), (mx + 3, my + 4.6)], 1.4, LIP)
    elif name == "Wink":
        eye(d, lx, ey, brown)
        brow(d, lx, by, mirror=-1)
        closed_eye(d, rx, ey + 1, happy=False)
        brow(d, rx, by + 1.5, arch=0.8, mirror=1)
        smile(d, mx + 2, my, width=15, depth=7)
        blush(d, rx + 3, ey + 11)
    elif name == "Cheeky":
        for x, m in ((lx, -1), (rx, 1)):
            closed_eye(d, x, ey, happy=True)
            brow(d, x, by - 1, arch=2, mirror=m)
        smile(d, mx, my - 1, width=16, depth=5)
        # tongue poking out
        d.chord(box(mx - 3.5, my, mx + 5.5, my + 11), 0, 180, fill=TONGUE, outline=INK, width=w(1.3))
        d.line([P(mx + 1, my + 2), P(mx + 1, my + 7)], fill=(190, 60, 80, 255), width=w(0.8))
    elif name == "Surprised":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey, hazel, open_=1.15)
            brow(d, x, by - 3.5, arch=3.0, mirror=m)
        d.ellipse(box(mx - 4, my - 3, mx + 4, my + 6), fill=MOUTH, outline=INK, width=w(1.6))
    elif name == "Determined":
        for x, m in ((lx, -1), (rx, 1)):
            eye(d, x, ey + 0.5, blue, open_=0.85, look=(0, 0.1))
            brow(d, x, by + 0.5, tilt=2.6, arch=0.4, width=2.8, mirror=m)
        thick_curve(d, [(mx - 8, my + 1.5), (mx, my - 0.5), (mx + 8, my + 1.5)], 2.0, INK)
    # Zoom in on the features (~1.3x) so they read from across a room, like classic Roblox faces
    crop = [int(c) for c in box(12, 12, 88, 88)]
    return img.crop(crop).resize((SIZE, SIZE), Image.LANCZOS)


FACES = ["Smile", "Grin", "Happy", "Smirk", "Chill", "Angry", "Freckles", "Lashes", "Wink", "Cheeky", "Surprised",
         "Determined"]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    tiles = []
    for name in FACES:
        img = make(name)
        img.save(OUT / f"face_{name}.png")
        tiles.append(img)
    # preview sheet on a skin tone
    tile = 256
    sheet = Image.new("RGBA", (tile * 6, tile * 2), (234, 184, 146, 255))
    for i, img in enumerate(tiles):
        small = img.resize((tile, tile), Image.LANCZOS)
        sheet.paste(small, ((i % 6) * tile, (i // 6) * tile), small)
    sheet.save(ROOT / "blender" / "previews" / "faces_sheet.png")
    sleep_sheet = Image.new("RGBA", (1152, 1456), (22, 29, 40, 255))
    sd = ImageDraw.Draw(sleep_sheet)
    title = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 32)
    label = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 23)
    sd.text((24, 18), "BOSS FACES / AWAKE AND ASLEEP", font=title, fill=WHITE)
    sd.text((24, 62), "Same eye centres and crop / 512px transparent faces / 4x supersampling", font=label, fill=(214, 224, 235, 255))
    for i, (boss, awake) in enumerate(BOSS_AWAKE.items()):
        img = make("Sleep" + boss)
        img.save(OUT / f"face_Sleep{boss}.png")
        x, y = 24 + i % 2 * 564, 114 + i // 2 * 332
        sd.text((x, y), f"{boss} / {awake}", font=label, fill=WHITE)
        for offset, face_img in ((0, make(awake)), (268, img)):
            tile_img = Image.new("RGBA", (256, 256), BOSS_SKIN[boss] + (255,))
            tile_img.alpha_composite(face_img.resize((256, 256), Image.LANCZOS))
            sleep_sheet.alpha_composite(tile_img, (x + offset, y + 36))
        sd.text((x, y + 298), "AWAKE", font=label, fill=(214, 224, 235, 255))
        sd.text((x + 268, y + 298), "SLEEPING", font=label, fill=(214, 224, 235, 255))
    sleep_sheet.save(ROOT / "blender" / "previews" / "faces_sleep_sheet.png")
    print("faces:", ", ".join(FACES))
    print("sleeping bosses:", ", ".join(BOSS_AWAKE))


if __name__ == "__main__":
    main()
