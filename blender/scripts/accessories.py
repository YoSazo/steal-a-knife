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


def hair_shell(bm, puff=1.0):
    """Classic Roblox blocky hair: a rounded slab over the top, a panel down the back and sideburn
    panels, all hugging the head (which is ~1.16 cubed)."""
    p = puff
    merge(bm, blob((1.3 * p, 1.3 * p, 0.42), (0, 0.03, 0.5), 0.14))  # top
    merge(bm, blob((1.3 * p, 0.2, 1.0), (0, 0.6 * p, 0.05), 0.08))  # back
    for x in (-0.62 * p, 0.62 * p):
        merge(bm, blob((0.18, 0.95, 0.62), (x, 0.12, 0.2), 0.07))  # sides
    merge(bm, blob((1.24 * p, 0.2, 0.2), (0, -0.6 * p, 0.38), 0.06))  # hairline at the front


def build_hair_long(root):
    bm = bmesh.new()
    hair_shell(bm, puff=1.04)
    back = add_box(bm, (1.3, 0.24, 1.5), (0, 0.62, -0.55))
    for v in back:
        if v.co.z < -1.2:
            v.co.z += 0.12 * math.sin(v.co.x * 9)
    for x in (-0.62, 0.62):
        add_box(bm, (0.2, 0.42, 1.05), (x * 1.05, -0.02, -0.45))
    add_box(bm, (1.0, 0.16, 0.32), (0.1, -0.64, 0.3), rot=Matrix.Rotation(math.radians(-12), 4, "Y"))
    mesh_object("Hair", bm, material("HairLong", rgb(110, 60, 30), roughness=0.7), root)


def build_hair_bob(root):
    bm = bmesh.new()
    hair_shell(bm, puff=1.06)
    for x in (-0.63, 0.63):
        add_box(bm, (0.2, 0.95, 0.85), (x * 1.04, 0.1, -0.2))
    add_box(bm, (1.34, 0.22, 0.85), (0, 0.64, -0.2))
    add_box(bm, (1.24, 0.14, 0.26), (0, -0.66, 0.34))
    mesh_object("Hair", bm, material("HairBob", rgb(30, 25, 20), roughness=0.7), root)


def build_hair_spiky(root):
    bm = bmesh.new()
    hair_shell(bm, puff=1.0)
    spikes = [(0, -0.2, 0.62, 0), (-0.35, -0.05, 0.55, -25), (0.35, -0.05, 0.55, 25), (0, 0.3, 0.55, 0),
              (-0.3, 0.35, 0.45, -30), (0.3, 0.35, 0.45, 30), (0, -0.5, 0.45, 0), (-0.5, 0.15, 0.3, -50),
              (0.5, 0.15, 0.3, 50)]
    for x, y, z, tilt in spikes:
        cone = cylinder(bm, 0.18, 0.5, (0, 0, 0.25), segments=5, radius2=0.0)
        xform(bm, cone, Matrix.Rotation(math.radians(tilt), 4, "Y")
              @ Matrix.Rotation(math.radians(-20 if y < 0 else 15), 4, "X"))
        bmesh.ops.translate(bm, vec=Vector((x, y, z)), verts=cone)
    mesh_object("Hair", bm, material("HairSpiky", rgb(240, 200, 80), roughness=0.6), root)


def build_hair_ponytail(root):
    bm = bmesh.new()
    hair_shell(bm, puff=1.02)
    add_box(bm, (1.1, 0.14, 0.22), (0, -0.66, 0.36))
    tail = cylinder(bm, 0.2, 1.1, (0, 0, 0), segments=8, radius2=0.08)
    xform(bm, tail, Matrix.Rotation(math.radians(155), 4, "X"))
    bmesh.ops.translate(bm, vec=Vector((0, 1.05, -0.1)), verts=tail)
    tie = bmesh.new()
    torus(tie, 0.17, 0.06, (0, 0.76, 0.3), segments=10, sides=4, rot=ROT_X90)
    mesh_object("Hair", bm, material("HairPony", rgb(200, 70, 30), roughness=0.7), root)
    mesh_object("Tie", tie, material("HairTie", rgb(255, 80, 150)), root)


def build_hair_swoop(root):
    bm = bmesh.new()
    hair_shell(bm, puff=1.03)
    swoop = add_box(bm, (0.9, 0.16, 0.6), (-0.2, -0.66, 0.16), rot=Matrix.Rotation(math.radians(18), 4, "Y"))
    for v in swoop:
        if v.co.z < 0:
            v.co.x -= 0.15
    add_box(bm, (1.34, 0.22, 0.5), (0, 0.64, -0.12))
    mesh_object("Hair", bm, material("HairSwoop", rgb(20, 20, 24), roughness=0.7), root)


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


ACCESSORIES = {
    "HairLong": build_hair_long,
    "HairBob": build_hair_bob,
    "HairSpiky": build_hair_spiky,
    "HairPonytail": build_hair_ponytail,
    "HairSwoop": build_hair_swoop,
    "Beanie": build_beanie,
    "Cap": build_cap,
    "ShutterShades": build_shutter_shades,
    "RoundGlasses": build_round_glasses,
    "Headphones": build_headphones,
    "TopHat": build_top_hat,
    "CowboyHat": build_cowboy_hat,
}
