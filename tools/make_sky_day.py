"""Render the daytime skybox (Steal An Egg style): bright blue all the way round, deeper overhead, pale near
the horizon, blue again below (the map floats in the sky), with soft cartoon clouds around the horizon.

  python tools/make_sky_day.py   -> blender/textures/skybox/day_{Ft,Bk,Lf,Rt,Up,Dn}.png
                                    + blender/previews/skybox_day_cross.png

Every pixel is coloured from its 3D view direction (same face conventions as make_skybox.py), so the
faces line up. No sun is painted in: Roblox draws the real sun (Sky.CelestialBodiesShown) and it
matches the shadows.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from make_skybox import N, face_dirs, fbm

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "blender" / "textures" / "skybox"

# Matched to Egg's own sky, pixel-sampled from a real screenshot (not eyeballed): their clear sky
# sits at roughly G/B = 255 everywhere, fully saturated, with only Red varying - deep cyan overhead,
# paling toward near-white at the horizon. A believable realistic gradient (the old ZENITH/HORIZON
# below this comment, kept in git history) tops out nowhere near that; only a flat painted sky can
# hit it without wrecking the rest of the scene the way pushing global Saturation did.
ZENITH = np.array([60, 255, 255]) / 255
HORIZON = np.array([190, 255, 255]) / 255
BELOW = np.array([70, 230, 255]) / 255


def render(face):
    d = face_dirs(face)
    y = d[..., 1]
    up = np.clip(y, 0, 1) ** 0.4
    down = np.clip(-y, 0, 1) ** 0.6
    img = HORIZON + (ZENITH - HORIZON) * up[..., None]
    img = np.where((y < 0)[..., None], HORIZON + (BELOW - HORIZON) * down[..., None], img)
    # Clouds: puffy noise in a band just above and below the horizon, flat-bottomed like cartoon clouds
    n = fbm(d * np.array([2.2, 5.5, 2.2]) + 23.0, octaves=5)
    band = np.exp(-((y - 0.16) ** 2) / 0.012)
    cloud = np.clip((n - 0.6) * 8.0, 0, 1) * np.clip(band, 0, 1)  # a few small clouds, mostly clear
    shade = 0.86 + 0.14 * np.clip((y - 0.02) * 6 + 0.5, 0, 1)  # a touch darker underneath
    cloud_col = np.ones(3) * shade[..., None]
    img = img * (1 - cloud[..., None]) + cloud_col * cloud[..., None]
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    return out.filter(ImageFilter.GaussianBlur(0.8))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    faces = {}
    for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
        faces[face] = render(face)
        faces[face].save(OUT / f"day_{face}.png")
        print("rendered", face)
    s = 256
    cross = Image.new("RGB", (s * 4, s * 3), (40, 40, 40))
    layout = {"Up": (1, 0), "Lf": (0, 1), "Ft": (1, 1), "Rt": (2, 1), "Bk": (3, 1), "Dn": (1, 2)}
    for face, (cx, cy) in layout.items():
        cross.paste(faces[face].resize((s, s)), (cx * s, cy * s))
    cross.save(ROOT / "blender" / "previews" / "skybox_day_cross.png")


if __name__ == "__main__":
    main()
