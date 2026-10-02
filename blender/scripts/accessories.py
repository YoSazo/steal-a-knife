"""Disguise accessories for make_props.py: hair and hats sized for the default R15 head (~1.16 studs,
centre at the origin, face toward -Y). Each colourable part is its own mesh: Hair / Hat / Trim /
Frame / Lens / Tie / Pompom, so the game can recolour them per outfit."""

import math

import bmesh
from mathutils import Matrix, Vector


def install(ns):
    """Pull the helpers from make_props' namespace (sphere, cylinder, add_box, torus, xform, ...)."""
    g = globals()
    for name in ("sphere", "cylinder", "add_box", "torus", "xform", "mesh_object", "material", "rgb", "ROT_X90",
                 "ROT_Y90"):
        g[name] = ns[name]


def blob(size, center, bevel=0.1):
    """A rounded box as its own bmesh (merged into the caller's)."""
    b = bmesh.new()
    geom = bmesh.ops.create_cube(b, size=1.0)
    xform(b, b.verts, Matrix.Diagonal((*size, 1.0)))
    bmesh.ops.bevel(b, geom=list(b.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
    bmesh.ops.translate(b, vec=Vector(center), verts=b.verts)
    return b


def merge(into, other):
    """Append `other` bmesh into `into`."""
    mesh = __import__("bpy").data.meshes.new("tmp")
    other.to_mesh(mesh)
    into.from_mesh(mesh)
    other.free()


# --- Hair: sculpted in hair.py (a cap shaped to the head + tapered locks), one builder per style --

import sys as _sys
from pathlib import Path as _Path

_sys.path.insert(0, str(_Path(__file__).resolve().parent))
import hair  # noqa: E402

HAIR_COLORS = {
    "HairLong": (0.43, 0.24, 0.12),
    "HairBob": (0.12, 0.1, 0.08),
    "HairSpiky": (0.94, 0.78, 0.31),
    "HairPonytail": (0.78, 0.27, 0.12),
    "HairSwoop": (0.08, 0.08, 0.1),
    "HairAfro": (0.16, 0.1, 0.06),
    "HairBuns": (0.95, 0.55, 0.75),
    "HairMessy": (0.45, 0.3, 0.18),
}


def _hair_builder(style):
    def build(root):
        bm = bmesh.new()
        tie = bmesh.new() if style in hair.TIED else None
        if tie is not None:
            hair.STYLES[style](bm, tie)
        else:
            hair.STYLES[style](bm)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        obj = mesh_object("Hair", bm, material(f"{style}Mat", HAIR_COLORS[style], roughness=0.65), root)
        for poly in obj.data.polygons:
            poly.use_smooth = True
        if tie is not None:
            mesh_object("Tie", tie, material(f"{style}Tie", (1.0, 0.31, 0.59)), root)
    return build


def build_beanie(root):
    knit = blob((1.28, 1.28, 0.5), (0, 0.02, 0.55), 0.2)
    band = blob((1.34, 1.34, 0.24), (0, 0.02, 0.34), 0.08)
    pompom = bmesh.new()
    sphere(pompom, 0.2, (0, 0.02, 0.9), segments=8, rings=6)
    mesh_object("Hat", knit, material("BeanieKnit", rgb(200, 30, 40), roughness=1), root)
    mesh_object("Trim", band, material("BeanieBand", rgb(240, 240, 240), roughness=1), root)
    mesh_object("Pompom", pompom, material("BeaniePom", rgb(240, 240, 240), roughness=1), root)


def build_cap(root):
    cap = blob((1.26, 1.26, 0.4), (0, 0.02, 0.52), 0.16)
    sphere(cap, 0.07, (0, 0.02, 0.74), segments=6, rings=4)
    brim = blob((1.0, 0.62, 0.06), (0, -0.88, 0.36), 0.03)
    for v in brim.verts:
        v.co.z -= ((v.co.x / 0.5) ** 2) * 0.06
    mesh_object("Hat", cap, material("CapCrown", rgb(30, 60, 160), roughness=0.8), root)
    mesh_object("Trim", brim, material("CapBrim", rgb(30, 60, 160), roughness=0.8), root)


def build_shutter_shades(root):
    frame = bmesh.new()
    for x in (-0.27, 0.27):
        add_box(frame, (0.5, 0.05, 0.05), (x, -0.62, 0.2))
        add_box(frame, (0.5, 0.05, 0.05), (x, -0.62, -0.06))
        add_box(frame, (0.05, 0.05, 0.3), (x - 0.24, -0.62, 0.07))
        add_box(frame, (0.05, 0.05, 0.3), (x + 0.24, -0.62, 0.07))
        for i in range(4):
            add_box(frame, (0.46, 0.04, 0.03), (x, -0.62, 0.0 + i * 0.055))
    for x in (-0.6, 0.6):
        add_box(frame, (0.04, 0.6, 0.04), (x, -0.32, 0.17))
    mesh_object("Frame", frame, material("Shades", rgb(240, 240, 240)), root)


def build_round_glasses(root):
    frame = bmesh.new()
    for x in (-0.26, 0.26):
        torus(frame, 0.2, 0.03, (x, -0.62, 0.1), segments=14, sides=4, rot=ROT_X90)
    add_box(frame, (0.14, 0.04, 0.04), (0, -0.62, 0.14))
    for x in (-0.58, 0.58):
        add_box(frame, (0.04, 0.6, 0.04), (x, -0.32, 0.14))
    lens = bmesh.new()
    for x in (-0.26, 0.26):
        cylinder(lens, 0.19, 0.02, (x, -0.62, 0.1), segments=14, rot=ROT_X90)
    mesh_object("Frame", frame, material("GlassesFrame", rgb(25, 25, 28), metallic=0.4), root)
    mesh_object("Lens", lens, material("GlassesLens", rgb(180, 220, 255)), root)


def build_headphones(root):
    band = bmesh.new()
    torus(band, 0.8, 0.07, (0, 0.02, 0.05), segments=20, sides=5, rot=ROT_X90)
    doomed = [f for f in band.faces if f.calc_center_median().z < 0.0]
    bmesh.ops.delete(band, geom=doomed, context="FACES")
    cups = bmesh.new()
    for x in (-0.66, 0.66):
        cylinder(cups, 0.28, 0.2, (x * 1.06, 0.02, -0.05), segments=14, rot=ROT_Y90)
    mesh_object("Hat", band, material("PhonesBand", rgb(30, 30, 34)), root)
    mesh_object("Trim", cups, material("PhonesCups", rgb(230, 40, 60)), root)


def build_top_hat(root):
    hat = bmesh.new()
    cylinder(hat, 0.95, 0.06, (0, 0, 0.6), segments=18)
    cylinder(hat, 0.56, 1.0, (0, 0, 1.12), segments=18, radius2=0.6)
    ribbon = bmesh.new()
    cylinder(ribbon, 0.58, 0.18, (0, 0, 0.72), segments=18)
    mesh_object("Hat", hat, material("TopHat", rgb(25, 25, 28)), root)
    mesh_object("Trim", ribbon, material("TopHatRibbon", rgb(170, 30, 40)), root)


def build_cowboy_hat(root):
    hat = bmesh.new()
    brim = cylinder(hat, 1.15, 0.06, (0, 0, 0.5), segments=20)
    for v in brim:
        v.co.z += (abs(v.co.x) / 1.15) ** 3 * 0.32
    crown = cylinder(hat, 0.62, 0.7, (0, 0, 0.86), segments=16, radius2=0.5)
    for v in crown:
        if v.co.z > 1.1 and abs(v.co.x) < 0.3:
            v.co.z -= 0.12
    band = bmesh.new()
    cylinder(band, 0.64, 0.14, (0, 0, 0.6), segments=16)
    mesh_object("Hat", hat, material("Cowboy", rgb(130, 85, 45), roughness=0.9), root)
    mesh_object("Trim", band, material("CowboyBand", rgb(60, 35, 20)), root)


# --- Boss signature pieces (the biome bosses wear these on top of their usual outfit) ------------

def build_flower_crown(root):
    vine = bmesh.new()
    torus(vine, 0.66, 0.06, (0, 0.02, 0.64), segments=24, sides=5)
    flowers = bmesh.new()
    centers = bmesh.new()
    for i in range(9):
        a = i / 9 * math.pi * 2
        x, y = math.cos(a) * 0.64, math.sin(a) * 0.64 + 0.02
        for k in range(5):
            b = k / 5 * math.pi * 2
            sphere(flowers, 0.1, (x + math.cos(b) * 0.1, y + math.sin(b) * 0.1, 0.7), segments=6, rings=4,
                   scale=(1, 1, 0.5))
        sphere(centers, 0.07, (x, y, 0.75), segments=6, rings=4)
    for i in range(12):
        a = (i + 0.5) / 12 * math.pi * 2
        sphere(vine, 0.07, (math.cos(a) * 0.68, math.sin(a) * 0.68 + 0.02, 0.64), segments=5, rings=3,
               scale=(1.6, 0.6, 0.5))
    mesh_object("Vine", vine, material("CrownVine", rgb(70, 160, 60)), root)
    mesh_object("Flowers", flowers, material("CrownFlowers", rgb(255, 120, 190)), root)
    mesh_object("Centers", centers, material("CrownCenters", rgb(255, 225, 80)), root)


def build_monocle(root):
    frame = bmesh.new()
    torus(frame, 0.17, 0.025, (0.26, -0.64, 0.12), segments=16, sides=4, rot=ROT_X90)
    chain = bmesh.new()
    for i in range(10):
        t = i / 9
        sphere(chain, 0.022, (0.42 + t * 0.15, -0.62 + t * 0.2, 0.02 - math.sin(t * math.pi) * 0.25 - t * 0.2),
               segments=5, rings=3)
    lens = bmesh.new()
    cylinder(lens, 0.16, 0.015, (0.26, -0.64, 0.12), segments=16, rot=ROT_X90)
    mesh_object("Frame", frame, material("MonocleFrame", rgb(220, 180, 70), metallic=0.8), root)
    mesh_object("Chain", chain, material("MonocleChain", rgb(220, 180, 70), metallic=0.8), root)
    mesh_object("Lens", lens, material("MonocleLens", rgb(200, 230, 255)), root)


def build_devil_horns(root):
    horns = bmesh.new()
    for side in (-1, 1):
        # a curved horn: stacked rings that shrink and lean out then up
        pts = []
        for i in range(8):
            t = i / 7
            pts.append((side * (0.3 + t * 0.32), -0.08 + t * 0.06, 0.52 + t * 0.7 - (t * t) * 0.12,
                        0.17 * (1 - t) + 0.015))
        for (x0, y0, z0, r0), (x1, y1, z1, r1) in zip(pts, pts[1:]):
            mid = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            seg = cylinder(horns, (r0 + r1) / 2, math.dist((x0, y0, z0), (x1, y1, z1)) * 1.15, (0, 0, 0), segments=8)
            direction = Vector((x1 - x0, y1 - y0, z1 - z0)).normalized()
            xform(horns, seg, Vector((0, 0, 1)).rotation_difference(direction).to_matrix().to_4x4())
            bmesh.ops.translate(horns, vec=Vector(mid), verts=seg)
    mesh_object("Hat", horns, material("Horns", rgb(200, 25, 30), roughness=0.3), root)


def build_crown(root):
    crown = bmesh.new()
    cylinder(crown, 0.6, 0.22, (0, 0.02, 0.58), segments=24)
    for i in range(8):
        a = i / 8 * math.pi * 2
        cylinder(crown, 0.09, 0.26, (math.cos(a) * 0.56, math.sin(a) * 0.56 + 0.02, 0.8), segments=4, radius2=0.0)
        sphere(crown, 0.045, (math.cos(a) * 0.56, math.sin(a) * 0.56 + 0.02, 0.95), segments=6, rings=4)
    gems = bmesh.new()
    for i in range(8):
        a = (i + 0.5) / 8 * math.pi * 2
        sphere(gems, 0.06, (math.cos(a) * 0.61, math.sin(a) * 0.61 + 0.02, 0.58), segments=6, rings=4,
               scale=(1, 1, 1.3))
    mesh_object("Hat", crown, material("Crown", rgb(255, 200, 60), metallic=0.9, roughness=0.2), root)
    mesh_object("Gems", gems, material("CrownGems", rgb(220, 30, 70), emission=1.0), root)


def build_halo(root):
    halo = bmesh.new()
    torus(halo, 0.5, 0.06, (0, 0.05, 1.0), segments=28, sides=8)
    mesh_object("Halo", halo, material("Halo", rgb(255, 225, 120), emission=3.0), root)


def build_angel_wings(root):
    """Worn on the UpperTorso (origin = torso centre, back = +Y): two fans of long feathers."""
    wings = bmesh.new()
    for side in (-1, 1):
        for row in range(3):
            for k in range(5):
                length = 1.9 - k * 0.22 - row * 0.35
                angle = math.radians(18 + k * 16 + row * 6)
                feather = cylinder(wings, 0.16 - row * 0.03, length, (0, 0, 0), segments=6, radius2=0.04)
                xform(wings, feather, Matrix.Diagonal((1, 0.35, 1, 1)))
                xform(wings, feather, Matrix.Rotation(side * (math.pi / 2 - angle), 4, "Y"))
                base = Vector((side * (0.3 + row * 0.08), 0.62 + row * 0.04, 0.45 - row * 0.12))
                tip_dir = Vector((side * math.cos(angle), 0, math.sin(angle)))
                bmesh.ops.translate(wings, vec=base + tip_dir * length / 2, verts=feather)
    mesh_object("Wings", wings, material("Wings", rgb(250, 250, 255), roughness=0.4), root)


def build_space_helmet(root):
    glass = bmesh.new()
    sphere(glass, 0.98, (0, 0, 0.05), segments=20, rings=14)
    collar = bmesh.new()
    torus(collar, 0.62, 0.11, (0, 0, -0.62), segments=24, sides=8)
    antenna = bmesh.new()
    cylinder(antenna, 0.025, 0.5, (0.45, 0.2, 1.05), segments=6)
    sphere(antenna, 0.07, (0.45, 0.2, 1.32), segments=8, rings=5)
    mesh_object("Lens", glass, material("HelmetGlass", rgb(170, 220, 255)), root)
    mesh_object("Trim", collar, material("HelmetCollar", rgb(230, 230, 240), metallic=0.6), root)
    mesh_object("Antenna", antenna, material("HelmetAntenna", rgb(150, 90, 255), emission=2.0), root)


ACCESSORIES = {
    **{style: _hair_builder(style) for style in (
        "HairLong", "HairBob", "HairSpiky", "HairPonytail", "HairSwoop", "HairAfro", "HairBuns", "HairMessy"
    )},
    "Beanie": build_beanie,
    "Cap": build_cap,
    "ShutterShades": build_shutter_shades,
    "RoundGlasses": build_round_glasses,
    "Headphones": build_headphones,
    "TopHat": build_top_hat,
    "CowboyHat": build_cowboy_hat,
    "FlowerCrown": build_flower_crown,
    "Monocle": build_monocle,
    "DevilHorns": build_devil_horns,
    "Crown": build_crown,
    "Halo": build_halo,
    "AngelWings": build_angel_wings,
    "SpaceHelmet": build_space_helmet,
}
