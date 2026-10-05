"""Cartoon flame flipbook for the knife auras (Steal An Egg volcano style).

64 looping frames in an 8x8 grid (1024 px, 128 px cells), drawn 2x and downsampled.
A tall middle tongue and two shorter side tongues sway and lick upward; inside there are three soft
toon bands (dim edge, mid, hot core) and a faint glow halo outside. Grayscale + alpha, so the
particle Color tints it (KnifeAura layers an orange-red body with a yellow core).

    python tools/make_cartoon_flame.py
"""

import math
import os

import numpy as np
from PIL import Image

GRID, CELL, SS = 8, 128, 2
FRAMES = GRID * GRID
BEAM_FRAMES = 8
OUT = os.path.join(os.path.dirname(__file__), "..", "blender", "textures", "aura", "cartoon_flame_8x8.png")


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tongue(u, v, t, x0, base, top, width, sway, phase, speed):
    """Inside-ness field of one teardrop tongue: > 0 inside, 0 on the edge."""
    s = (v - base) / (top - base)
    inside = (s > 0) & (s < 1)
    s = np.clip(s, 1e-4, 1 - 1e-4)
    # round bulb low down, long pointed tip (peak of s^0.5 (1-s)^1.5 normalised to 1)
    half = width * (s**0.5) * ((1 - s) ** 1.5) / 0.3237
    # the tip whips more than the base; whole-number speeds keep the loop seamless
    wave = math.tau * (speed * t + phase)
    centre = x0 + sway * (s**1.4) * (np.sin(wave - s * 3.2) + 0.35 * np.sin(2 * wave - s * 6.0))
    field = 1 - np.abs(u - centre) / np.maximum(half, 1e-4)
    return np.where(inside, field, -1.0)


def frame(t, cell=CELL):
    n = cell * SS
    ys, xs = np.mgrid[0:n, 0:n]
    u = (xs + 0.5) / n * 2 - 1  # -1..1 across
    v = 1 - (ys + 0.5) / n  # 0 bottom .. 1 top
    # flicker the heights a little (whole-number frequencies: loops)
    k = math.tau * t
    tall = 0.93 + 0.03 * math.sin(2 * k)
    fields = [
        tongue(u, v, t, 0.0, 0.05, tall, 0.62, 0.16, 0.0, 1),
        tongue(u, v, t, -0.3, 0.05, 0.62 + 0.06 * math.sin(3 * k + 1.0), 0.4, 0.13, 0.33, 2),
        tongue(u, v, t, 0.32, 0.05, 0.66 + 0.06 * math.sin(2 * k + 2.4), 0.4, 0.13, 0.66, 1),
    ]
    field = np.maximum.reduce(fields)
    # soft wobble along the outline so it never looks vector-perfect
    field = field + 0.06 * np.sin(u * 9 + v * 7 - 4 * k) * np.sin(v * 11 + 3 * k)
    # the hot core: a smaller tongue of its own, low and centred
    core = tongue(u, v, t, 0.0, 0.07, 0.62 + 0.04 * math.sin(2 * k + 0.7), 0.36, 0.1, 0.15, 1)

    body = smoothstep(-0.04, 0.06, field)
    halo = 0.28 * smoothstep(-0.55, 0.0, field) * (1 - body)
    alpha = np.clip(body + halo, 0, 1)
    # toon bands: dim rim, mid body, bright core
    value = 0.58 + 0.2 * smoothstep(0.28, 0.36, field) + 0.22 * smoothstep(0.0, 0.1, core)
    value = np.where(body > 0.01, value, 1.0)  # the halo is a pale glow
    gray = (np.clip(value, 0, 1) * 255).astype(np.uint8)
    a = (alpha * 255).astype(np.uint8)
    image = Image.fromarray(np.dstack([gray, gray, gray, a]))
    return image.resize((cell, cell), Image.LANCZOS)


def main():
    atlas = Image.new("RGBA", (GRID * CELL, GRID * CELL), (0, 0, 0, 0))
    for i in range(FRAMES):
        atlas.paste(frame(i / FRAMES), ((i % GRID) * CELL, (i // GRID) * CELL))
    atlas.save(OUT)
    print("wrote", os.path.normpath(OUT))
    # Beam frames (KnifeAura sews the flame onto the knife with a Beam). A beam lays the image's
    # height along its length, so these stay upright (KnifeAura picks which end is the guard).
    # Cycled by client/AuraFlicker.
    beams = os.path.join(os.path.dirname(OUT), "beam")
    os.makedirs(beams, exist_ok=True)
    for i in range(BEAM_FRAMES):
        image = frame(i / BEAM_FRAMES, 256)
        image.save(os.path.join(beams, f"flame_beam_{i}.png"))
    print("wrote", BEAM_FRAMES, "beam frames")


if __name__ == "__main__":
    main()
