"""Render the space skybox: six 1024px faces sampled from one 3D field, so the edges line up.

  python tools/make_skybox.py   -> blender/textures/skybox/space_{Ft,Bk,Lf,Rt,Up,Dn}.png
                                   + blender/previews/skybox_cross.png (the unfolded cube)

What's in it: a deep purple-black background, two big soft nebula clouds (violet/magenta and
teal/blue) built from fractal noise along a band across the sky (a "galactic plane"), a dense star
field (sizes and colours vary, brighter stars get a small glow + cross flare), and a few distant
spiral galaxies. Nothing is random per face - every pixel looks up its 3D direction - so seams
can't happen as long as the face orientations match Roblox's.
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "blender" / "textures" / "skybox"
N = 1024
rng = np.random.default_rng(1337)


def face_dirs(face):
    """Unit view directions for every pixel of a face (Roblox skybox conventions)."""
    a = (np.arange(N) + 0.5) / N * 2 - 1
    u, v = np.meshgrid(a, a)  # u: left -> right, v: top -> bottom
    one = np.ones_like(u)
    if face == "Ft":  # looking towards -Z
        d = np.stack([u, -v, -one], -1)
    elif face == "Bk":  # +Z
        d = np.stack([-u, -v, one], -1)
    elif face == "Lf":  # -X
        d = np.stack([-one, -v, -u], -1)
    elif face == "Rt":  # +X
        d = np.stack([one, -v, u], -1)
    elif face == "Up":  # +Y, front (-Z) at the bottom of the image
        d = np.stack([u, one, v], -1)
    else:  # "Dn": -Y, front at the top
        d = np.stack([u, -one, -v], -1)
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


# --- 3D value noise (smooth, tileable enough for a sky) -----------------------------------------
GRID = 32
LATTICE = rng.random((GRID, GRID, GRID)).astype(np.float32)


def value_noise(p):
    p = p % GRID
    i = np.floor(p).astype(int)
    f = p - i
    f = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * \
                    (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * LATTICE[(i[..., 0] + dx) % GRID, (i[..., 1] + dy) % GRID, (i[..., 2] + dz) % GRID]
    return out


def fbm(p, octaves=6):
    total, amp, freq = 0.0, 0.5, 1.0
    for _ in range(octaves):
        total = total + amp * value_noise(p * freq)
        amp *= 0.5
        freq *= 2.03
    return total


# Stars: a fixed list of directions (shared by every face)
STAR_COUNT = 30000
star_dirs = rng.normal(size=(STAR_COUNT, 3))
star_dirs /= np.linalg.norm(star_dirs, axis=1, keepdims=True)
star_mag = rng.power(0.12, STAR_COUNT)  # mostly faint, a few bright
star_tint = rng.choice([0, 1, 2, 3], STAR_COUNT, p=[0.6, 0.18, 0.14, 0.08])
TINTS = np.array([[1, 1, 1], [0.75, 0.85, 1.0], [1.0, 0.9, 0.7], [1.0, 0.7, 0.9]])

# Galaxies: (direction, size, tilt)
GALAXIES = [((0.55, 0.45, -0.7), 0.06, 0.6), ((-0.8, 0.25, 0.4), 0.045, 2.1), ((0.1, -0.35, 0.93), 0.05, 1.2)]


def render(face):
    d = face_dirs(face)
    # background gradient: a touch lighter near the "galactic plane"
    plane_n = np.array([0.35, 0.85, 0.2])
    plane_n /= np.linalg.norm(plane_n)
    band = np.exp(-(d @ plane_n) ** 2 / 0.12)
    base = np.array([0.025, 0.012, 0.05])
    img = np.ones(d.shape) * base
    # nebulae: fractal noise, strongest along the band
    n1 = fbm(d * 3.0 + 11.0)
    n2 = fbm(d * 4.5 + 47.0)
    warp = fbm(d * 1.6 + 5.0)
    neb1 = np.clip((n1 - 0.42 + warp * 0.15) * 2.4, 0, 1) ** 1.6 * (0.35 + 0.65 * band)
    neb2 = np.clip((n2 - 0.46) * 2.6, 0, 1) ** 1.8 * (0.25 + 0.75 * band)
    img += neb1[..., None] * np.array([0.42, 0.12, 0.55])  # violet / magenta
    img += neb2[..., None] * np.array([0.05, 0.3, 0.45])  # teal / blue
    dust = np.clip(fbm(d * 9.0 + 91.0) - 0.5, 0, 1)
    img *= (1 - dust[..., None] * 0.6)  # dark dust lanes
    img += band[..., None] * np.array([0.04, 0.025, 0.06])

    # stars: project each star onto this face's pixels
    flat = d.reshape(-1, 3)
    star_img = np.zeros_like(flat)
    facing = {"Ft": 2, "Bk": 2, "Lf": 0, "Rt": 0, "Up": 1, "Dn": 1}[face]
    sign = {"Ft": -1, "Bk": 1, "Lf": -1, "Rt": 1, "Up": 1, "Dn": -1}[face]
    for s in range(STAR_COUNT):
        sd = star_dirs[s]
        if sd[facing] * sign <= np.max(np.abs(np.delete(sd, facing))) * 0.999:
            continue  # not on this face
        # pixel position
        depth = abs(sd[facing])
        p = sd / depth
        if face == "Ft":
            u, v = p[0], -p[1]
        elif face == "Bk":
            u, v = -p[0], -p[1]
        elif face == "Lf":
            u, v = -p[2], -p[1]
        elif face == "Rt":
            u, v = p[2], -p[1]
        elif face == "Up":
            u, v = p[0], p[2]
        else:
            u, v = p[0], -p[2]
        x, y = int((u + 1) / 2 * N), int((v + 1) / 2 * N)
        bright = 0.35 + star_mag[s] * 2.5
        color = TINTS[star_tint[s]] * bright
        radius = 1 if star_mag[s] < 0.6 else (2 if star_mag[s] < 0.9 else 3)
        for oy in range(-radius * 3, radius * 3 + 1):
            for ox in range(-radius * 3, radius * 3 + 1):
                px, py = x + ox, y + oy
                if 0 <= px < N and 0 <= py < N:
                    r2 = ox * ox + oy * oy
                    glow = np.exp(-r2 / (0.6 * radius * radius))
                    if radius >= 3 and (ox == 0 or oy == 0):
                        glow += 0.35 * np.exp(-max(abs(ox), abs(oy)) / 3.0)  # cross flare
                    star_img[py * N + px] += color * glow
    img = img + star_img.reshape(img.shape)

    # galaxies: soft tilted ellipses with a bright core and two arms of noise
    for gdir, size, tilt in GALAXIES:
        g = np.array(gdir) / np.linalg.norm(gdir)
        cosang = d @ g
        mask = cosang > np.cos(size * 3)
        if not mask.any():
            continue
        # local tangent frame
        t1 = np.cross(g, [0, 1, 0])
        t1 /= np.linalg.norm(t1)
        t2 = np.cross(g, t1)
        x = d @ t1
        y = d @ t2
        c, s_ = np.cos(tilt), np.sin(tilt)
        xr, yr = x * c - y * s_, (x * s_ + y * c) * 2.6
        r = np.sqrt(xr ** 2 + yr ** 2) / size
        ang = np.arctan2(yr, xr)
        arms = 0.5 + 0.5 * np.cos(2 * ang - r * 5.0)
        glow = np.exp(-r ** 2 * 1.5) * (0.4 + 0.6 * arms) + np.exp(-r ** 2 * 40) * 2.0
        glow = np.where(cosang > 0, glow, 0)
        img += glow[..., None] * np.array([0.8, 0.7, 1.0]) * 0.6

    img = 1 - np.exp(-img * 1.6)  # soft tone map
    return Image.fromarray((np.clip(img, 0, 1) ** (1 / 1.1) * 255).astype(np.uint8))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    faces = {}
    for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
        faces[face] = render(face)
        faces[face].save(OUT / f"space_{face}.png")
        print("rendered", face)
    # unfolded cross for checking the seams by eye
    s = 256
    cross = Image.new("RGB", (s * 4, s * 3), (40, 40, 40))
    layout = {"Up": (1, 0), "Lf": (0, 1), "Ft": (1, 1), "Rt": (2, 1), "Bk": (3, 1), "Dn": (1, 2)}
    for face, (cx, cy) in layout.items():
        cross.paste(faces[face].resize((s, s)), (cx * s, cy * s))
    cross.save(ROOT / "blender" / "previews" / "skybox_cross.png")


if __name__ == "__main__":
    main()
