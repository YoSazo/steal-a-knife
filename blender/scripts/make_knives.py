"""Procedurally build the whole Steal a Knife lineup (all 10 knives) and export one FBX per knife.

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/make_knives.py

Every knife has its own silhouette (serrated shank, chef's knife, clip-point hunter, cleaver,
flared machete, double-edged dagger, curved katana, jagged Void Edge, fang-shaped Inferno Fang).
Blades are lofted from a profile: a list of cross-section rings along +X, so the shape is just a
few numbers per knife.

Each knife exports as separate meshes (Blade, Guard, Handle, Pommel, Extra) so every part becomes
its own MeshPart in Roblox and gets its colour/material there (FBX colours don't carry over).
Origin sits in the middle of the grip; the blade points along +X. Low poly on purpose.
"""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
EXPORT_DIR = ROOT / "blender" / "exports"
PREVIEW_DIR = ROOT / "blender" / "previews"
ONLY = None  # set to a knife name to rebuild just that one while iterating


def clamp01(v):
    return max(0.0, min(1.0, v))


# --- Blade profiles ----------------------------------------------------------------------
# A profile returns (top, bottom, bend) for s in [0, 1] along the blade: the height of the spine,
# the height of the edge, and a vertical offset that curves the whole blade (katana, fang).
# All heights are fractions of the knife's blade height.

def chef(s):
    top = 1.0 if s < 0.6 else 1.0 - ((s - 0.6) / 0.4) ** 1.6 * 0.55
    bot = 0.0 if s < 0.35 else ((s - 0.35) / 0.65) ** 2.2 * 0.45
    return top, bot, 0.0


def shank(s):
    top, bot, bend = chef(s)
    # crude sawtooth spine
    teeth = 7
    if 0.1 < s < 0.8:
        top -= 0.18 * ((s * teeth) % 1.0)
    return top, bot * 1.2, bend


def clip_point(s):
    top = 1.0 if s < 0.55 else 1.0 - (s - 0.55) / 0.45 * 0.75
    bot = 0.0 if s < 0.5 else ((s - 0.5) / 0.5) ** 1.8 * 0.3
    return top, bot, 0.0


def slim(s):
    top = 1.0 if s < 0.7 else 1.0 - (s - 0.7) / 0.3 * 0.6
    bot = 0.05 if s < 0.6 else 0.05 + ((s - 0.6) / 0.4) ** 1.5 * 0.35
    return top, bot, 0.0


def cleaver(s):
    top = 1.0
    bot = 0.0 if s < 0.9 else (s - 0.9) / 0.1 * 0.08
    return top, bot, 0.0


def machete(s):
    # widens towards the tip, then an angled cut
    top = 0.75 + 0.35 * s if s < 0.85 else 1.05 - (s - 0.85) / 0.15 * 0.9
    bot = 0.0 if s < 0.8 else ((s - 0.8) / 0.2) ** 2 * 0.15
    return top, bot, 0.0


def dagger(s):
    # symmetric leaf shape, double edged
    w = 1.0 - s ** 1.4 * 0.95
    w *= 1.0 + 0.15 * math.sin(s * math.pi)
    return 0.5 + w * 0.5, 0.5 - w * 0.5, 0.0


def katana(s):
    top = 1.0 if s < 0.88 else 1.0 - (s - 0.88) / 0.12 * 0.5
    bot = 0.0 if s < 0.85 else ((s - 0.85) / 0.15) ** 1.5 * 0.7
    bend = s * s * 0.9  # upward sweep towards the tip
    return top, bot, bend


def void(s):
    # jagged double-edged blade: zig-zag teeth on both sides
    w = 1.0 - s ** 1.6 * 0.95
    zig = 0.22 * abs(((s * 6) % 1.0) - 0.5) * 2 if s < 0.85 else 0.0
    return 0.5 + (w * 0.5) + zig * 0.5, 0.5 - (w * 0.5) - zig * 0.35, 0.0


def fang(s):
    top = 1.0 - s ** 1.2 * 0.6
    bot = 0.0 + s ** 2 * 0.35
    bend = s ** 2.2 * 1.6  # hooks hard upwards like a fang
    return top, bot, bend


# The biome knives (Mythic / Godly / Celestial / Cosmic and the extra Common-Legendary ones)

def pocket(s):
    # a short drop point
    top = 1.0 if s < 0.55 else 1.0 - ((s - 0.55) / 0.45) ** 1.3 * 0.7
    bot = 0.05 + (s ** 2.5) * 0.3
    return top, bot, 0.0


def bone(s):
    # a knobbly bone-white spine that tapers
    w = 1.0 - s ** 1.5 * 0.85
    top = 0.15 + w * 0.85 + 0.1 * math.sin(s * math.pi * 6)
    return top, 0.0 + s ** 2 * 0.3, 0.0


def scythe(s):
    # the reaper's hook: sweeps down and back towards the tip
    top = 1.0 - s * 0.55
    bot = 0.0 + s * 0.25
    bend = -(s ** 1.7) * 1.9
    return top, bot, bend


def horn(s):
    # a demon's horn: thick at the base, curling up to a point
    w = 1.0 - s ** 1.1 * 0.97
    return 0.5 + w * 0.5, 0.5 - w * 0.5, s ** 1.8 * 1.3


def bolt(s):
    # a lightning bolt: the whole blade zig-zags
    w = 1.0 - s ** 1.8 * 0.9
    tri = abs(((s * 3.0) % 1.0) - 0.5) * 2 - 0.5
    return 0.5 + w * 0.5, 0.5 - w * 0.5, tri * 0.9


def leaf(s):
    # a Greek xiphos: narrow waist, wide belly, long point
    w = 0.65 + 0.45 * math.sin(math.pi * min(s / 0.75, 1.0)) if s < 0.75 else 1.1 * (1 - (s - 0.75) / 0.25)
    w = max(w, 0.04)
    return 0.5 + w * 0.5, 0.5 - w * 0.5, 0.0


def broad(s):
    # a wide double-edged sword with a sharp point
    w = 1.0 - s * 0.15 if s < 0.82 else 0.85 * (1 - (s - 0.82) / 0.18)
    return 0.5 + w * 0.5, 0.5 - w * 0.5, 0.0


def straight(s):
    # a slim holy sword
    w = 1.0 if s < 0.86 else 1 - (s - 0.86) / 0.14
    return 0.5 + w * 0.5, 0.5 - w * 0.5, 0.0


def feather(s):
    # a feather: a leaf with notches cut into its edges
    w = math.sin(math.pi * (0.15 + 0.85 * s)) * (1 - s * 0.3)
    notch = 0.18 * (((s * 7) % 1.0) < 0.35) if 0.15 < s < 0.85 else 0.0
    return 0.5 + w * 0.5 - notch * 0.5, 0.5 - w * 0.5 + notch * 0.3, s * s * 0.25


def build_blade(length, height, profile, thickness=0.05, stations=24, double_edged=False):
    """Loft rings along +X. Single-edged rings are a 5-sided wedge (flat spine, sharp edge);
    double-edged rings are a diamond."""
    bm = bmesh.new()
    rings = []
    for i in range(stations):
        s = i / stations
        top, bot, bend = profile(s)
        x = length * s
        z_top, z_bot = top * height + bend * height, bot * height + bend * height
        mid = (z_top + z_bot) / 2
        t = thickness * (1.0 - 0.55 * s * s)
        if double_edged:
            ring = [
                bm.verts.new((x, 0.0, z_top)),
                bm.verts.new((x, t, mid)),
                bm.verts.new((x, 0.0, z_bot)),
                bm.verts.new((x, -t, mid)),
            ]
        else:
            upper = z_top - (z_top - z_bot) * 0.25
            ring = [
                bm.verts.new((x, -t, z_top)),
                bm.verts.new((x, t, z_top)),
                bm.verts.new((x, t * 0.9, upper)),
                bm.verts.new((x, 0.0, z_bot)),
                bm.verts.new((x, -t * 0.9, upper)),
            ]
        rings.append(ring)
    top, bot, bend = profile(1.0)
    tip = bm.verts.new((length, 0.0, ((top + bot) / 2 + bend) * height))
    n = len(rings[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n):
            bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    last = rings[-1]
    for k in range(n):
        bm.faces.new((last[k], last[(k + 1) % n], tip))
    bm.faces.new(list(reversed(rings[0])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# --- Simple solids -------------------------------------------------------------------------

def box(bm, size, center, bevel=0.2):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    if bevel:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=min(size) * bevel, segments=1, affect="EDGES")


def cylinder_x(bm, length, r1, r2, x_center, z, segments=10):
    """A cylinder/cone lying along X."""
    geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r1, radius2=r2, depth=length)
    verts = geom["verts"]
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    bmesh.ops.translate(bm, vec=Vector((x_center, 0, z)), verts=verts)


def sphere(bm, radius, center, segs=10):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(4, segs // 2 + 1), radius=radius)
    bmesh.ops.translate(bm, vec=Vector(center), verts=geom["verts"])


def cone_up(bm, radius, height, base, tilt=0.0):
    geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=radius, radius2=0.0, depth=height)
    verts = geom["verts"]
    bmesh.ops.translate(bm, vec=Vector((0, 0, height / 2)), verts=verts)
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(tilt, 3, "Y"))
    bmesh.ops.translate(bm, vec=Vector(base), verts=verts)


# --- Knife specs ---------------------------------------------------------------------------
# length/height: blade size. guard: "box" | "disc" | "cross" | "none". handle_len in Blender units.
# extras: list of decoration names built on the Extra mesh.

KNIVES = {
    "RustyShank": dict(rarity="Common", profile=shank, length=1.2, height=0.3, guard="none",
                       handle_len=0.7, handle_r=0.075, wrap=True, extras=[],
                       colors=dict(Blade=(0.52, 0.33, 0.2), Guard=(0.34, 0.27, 0.23), Handle=(0.36, 0.22, 0.12))),
    "KitchenKnife": dict(rarity="Common", profile=chef, length=1.5, height=0.4, guard="bolster",
                         handle_len=0.8, handle_r=0.08, extras=["rivets"],
                         colors=dict(Blade=(0.85, 0.87, 0.9), Guard=(0.6, 0.62, 0.65), Handle=(0.12, 0.12, 0.14))),
    "HunterBlade": dict(rarity="Rare", profile=clip_point, length=1.7, height=0.36, guard="cross",
                        handle_len=0.8, handle_r=0.085, extras=["grooves"],
                        colors=dict(Blade=(0.72, 0.76, 0.8), Guard=(0.75, 0.55, 0.23), Handle=(0.43, 0.24, 0.1))),
    "Switchblade": dict(rarity="Rare", profile=slim, length=1.4, height=0.24, guard="none",
                        handle_len=1.0, handle_r=0.08, flat_handle=True, extras=["button"],
                        colors=dict(Blade=(0.47, 0.78, 1.0), Guard=(0.12, 0.24, 0.47), Handle=(0.16, 0.35, 0.67))),
    "Cleaver": dict(rarity="Epic", profile=cleaver, length=1.35, height=0.8, guard="none",
                    handle_len=0.8, handle_r=0.085, extras=["hole", "rivets"],
                    colors=dict(Blade=(0.82, 0.84, 0.88), Guard=(0.24, 0.24, 0.27), Handle=(0.59, 0.16, 0.16))),
    "Machete": dict(rarity="Epic", profile=machete, length=2.3, height=0.42, guard="box",
                    handle_len=0.85, handle_r=0.085, wrap=True, extras=[],
                    colors=dict(Blade=(0.75, 0.47, 1.0), Guard=(0.24, 0.12, 0.35), Handle=(0.31, 0.63, 0.27))),
    "GoldenDagger": dict(rarity="Legendary", profile=dagger, length=1.8, height=0.42, guard="cross",
                         handle_len=0.7, handle_r=0.08, double=True, extras=["gem", "fuller"],
                         colors=dict(Blade=(1.0, 0.8, 0.2), Guard=(0.9, 0.16, 0.24), Handle=(0.24, 0.12, 0.06))),
    "Katana": dict(rarity="Legendary", profile=katana, length=2.8, height=0.22, guard="disc",
                   handle_len=1.2, handle_r=0.08, wrap=True, extras=["habaki"],
                   colors=dict(Blade=(1.0, 0.7, 0.82), Guard=(1.0, 0.8, 0.2), Handle=(0.16, 0.08, 0.16))),
    "VoidEdge": dict(rarity="Godly", profile=void, length=2.3, height=0.5, guard="spikes",
                     handle_len=0.85, handle_r=0.085, double=True, extras=["crystals"],
                     colors=dict(Blade=(0.59, 0.24, 1.0), Guard=(0.08, 0.08, 0.12), Handle=(0.24, 0.0, 0.43))),
    "InfernoFang": dict(rarity="Godly", profile=fang, length=2.0, height=0.5, guard="spikes",
                        handle_len=0.85, handle_r=0.09, extras=["flames"],
                        colors=dict(Blade=(1.0, 0.43, 0.12), Guard=(0.16, 0.08, 0.08), Handle=(0.47, 0.08, 0.08))),
    # --- The biome knives ------------------------------------------------------------------
    "PocketKnife": dict(rarity="Common", profile=pocket, length=1.05, height=0.3, guard="none",
                        handle_len=0.85, handle_r=0.08, flat_handle=True, extras=["button", "rivets"],
                        colors=dict(Blade=(0.82, 0.84, 0.86), Guard=(0.67, 0.12, 0.12), Handle=(0.78, 0.16, 0.16))),
    "ThornDagger": dict(rarity="Rare", profile=dagger, length=1.6, height=0.38, guard="cross",
                        handle_len=0.75, handle_r=0.08, double=True, wrap=True, extras=["thorns"],
                        colors=dict(Blade=(0.47, 0.86, 0.43), Guard=(0.24, 0.43, 0.16), Handle=(0.27, 0.18, 0.1))),
    "BoneCarver": dict(rarity="Epic", profile=bone, length=2.0, height=0.42, guard="box",
                       handle_len=0.8, handle_r=0.09, extras=["knuckles"],
                       colors=dict(Blade=(0.92, 0.88, 0.78), Guard=(0.47, 0.43, 0.37), Handle=(0.27, 0.24, 0.22))),
    "Reaper": dict(rarity="Legendary", profile=scythe, length=2.1, height=0.55, guard="spikes",
                   handle_len=1.3, handle_r=0.08, wrap=True, extras=["skullcap"],
                   colors=dict(Blade=(0.24, 0.24, 0.28), Guard=(1.0, 0.78, 0.24), Handle=(0.1, 0.08, 0.1))),
    "MagmaCleaver": dict(rarity="Godly", profile=cleaver, length=1.4, height=0.85, guard="spikes",
                         handle_len=0.8, handle_r=0.09, extras=["drips"],
                         colors=dict(Blade=(1.0, 0.31, 0.08), Guard=(0.2, 0.1, 0.08), Handle=(0.12, 0.08, 0.08))),
    "DemonHorn": dict(rarity="Godly", profile=horn, length=2.2, height=0.5, guard="spikes",
                      handle_len=0.85, handle_r=0.09, double=True, extras=["ridges"],
                      colors=dict(Blade=(0.86, 0.08, 0.12), Guard=(0.1, 0.04, 0.04), Handle=(0.24, 0.0, 0.0))),
    "ZeusBolt": dict(rarity="Godly", profile=bolt, length=2.5, height=0.32, guard="disc",
                     handle_len=0.9, handle_r=0.08, double=True, extras=["sparks"],
                     colors=dict(Blade=(1.0, 0.94, 0.35), Guard=(0.94, 0.94, 1.0), Handle=(0.35, 0.55, 1.0))),
    "AthenaBlade": dict(rarity="Godly", profile=leaf, length=2.1, height=0.42, guard="cross",
                        handle_len=0.8, handle_r=0.08, double=True, extras=["owlwings", "fuller"],
                        colors=dict(Blade=(0.96, 0.96, 1.0), Guard=(1.0, 0.8, 0.24), Handle=(0.27, 0.43, 0.78))),
    "OlympusEdge": dict(rarity="Godly", profile=broad, length=2.4, height=0.5, guard="cross",
                        handle_len=0.85, handle_r=0.085, double=True, extras=["laurel", "gem"],
                        colors=dict(Blade=(1.0, 0.47, 0.78), Guard=(1.0, 0.84, 0.31), Handle=(1.0, 0.98, 0.94))),
    "HaloBlade": dict(rarity="Godly", profile=straight, length=2.6, height=0.3, guard="cross",
                      handle_len=0.9, handle_r=0.08, double=True, extras=["halo"],
                      colors=dict(Blade=(1.0, 0.98, 0.86), Guard=(1.0, 0.86, 0.35), Handle=(0.94, 0.94, 1.0))),
    "SeraphSword": dict(rarity="Godly", profile=straight, length=2.9, height=0.36, guard="box",
                        handle_len=1.0, handle_r=0.085, double=True, extras=["featherwings", "gem"],
                        colors=dict(Blade=(0.63, 0.94, 1.0), Guard=(1.0, 0.9, 0.55), Handle=(1.0, 1.0, 1.0))),
    "AngelFeather": dict(rarity="Godly", profile=feather, length=2.2, height=0.5, guard="none",
                         handle_len=0.8, handle_r=0.07, double=True, extras=["quill"],
                         colors=dict(Blade=(1.0, 1.0, 1.0), Guard=(0.59, 0.9, 1.0), Handle=(1.0, 0.84, 0.47))),
    "StarCleaver": dict(rarity="Godly", profile=cleaver, length=1.5, height=0.9, guard="none",
                        handle_len=0.85, handle_r=0.09, extras=["stars"],
                        colors=dict(Blade=(0.35, 0.86, 1.0), Guard=(0.12, 0.08, 0.24), Handle=(1.0, 0.9, 0.47))),
    "GalaxyKatana": dict(rarity="Godly", profile=katana, length=3.0, height=0.24, guard="disc",
                         handle_len=1.25, handle_r=0.08, wrap=True, extras=["orbs"],
                         colors=dict(Blade=(1.0, 0.35, 0.9), Guard=(0.24, 0.86, 1.0), Handle=(0.08, 0.04, 0.16))),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.objects, bpy.data.cameras):
        for item in list(block):
            block.remove(item)


def material(name, rgb, metallic=0.0, roughness=0.5, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = (*rgb, 1.0)  # used by the Workbench preview render
    return mat


def mesh_object(name, bm, mat, parent):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    me.materials.append(mat)
    obj.parent = parent
    return obj


def build_guard(spec, z):
    h, kind = spec["height"], spec["guard"]
    bm = bmesh.new()
    if kind == "box":
        box(bm, (0.1, 0.22, h * 1.3), (-0.05, 0, z))
    elif kind == "bolster":
        box(bm, (0.14, 0.16, h * 0.55), (-0.06, 0, z - h * 0.15), bevel=0.35)
    elif kind == "cross":
        box(bm, (0.1, 0.16, h * 2.2), (-0.05, 0, z))
        sphere(bm, 0.07, (-0.05, 0, z + h * 1.1), 8)
        sphere(bm, 0.07, (-0.05, 0, z - h * 1.1), 8)
    elif kind == "disc":
        cylinder_x(bm, 0.05, 0.22, 0.22, -0.03, z, segments=14)
    elif kind == "spikes":
        box(bm, (0.12, 0.18, h * 1.4), (-0.06, 0, z))
        # two horns sweeping out and slightly forward from the ends of the guard
        for side in (1, -1):
            depth = 0.32
            direction = Vector((0.4, 0, side)).normalized()
            angle = math.atan2(direction.x, direction.z)
            geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.08, radius2=0.0, depth=depth)
            verts = geom["verts"]
            bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(angle, 3, "Y"))
            base = Vector((-0.06, 0, z + side * h * 0.65))
            bmesh.ops.translate(bm, vec=base + direction * depth / 2, verts=verts)
    else:  # "none": a thin collar so the blade doesn't float
        box(bm, (0.06, 0.13, h * 0.5), (-0.03, 0, z - h * 0.1))
    return bm


def build_handle(spec, z):
    bm = bmesh.new()
    length, r = spec["handle_len"], spec["handle_r"]
    if spec.get("flat_handle"):
        box(bm, (length, r * 1.6, r * 2.6), (-length / 2 - 0.05, 0, z), bevel=0.3)
    else:
        cylinder_x(bm, length, r * 0.9, r, -length / 2 - 0.05, z, segments=10)
        if spec.get("wrap"):
            rings = int(length / 0.14)
            for i in range(rings):
                x = -0.12 - i * (length - 0.1) / rings
                cylinder_x(bm, 0.035, r * 1.12, r * 1.12, x, z, segments=10)
    return bm


def build_pommel(spec, z):
    bm = bmesh.new()
    x = -spec["handle_len"] - 0.1
    if spec["guard"] == "disc":
        cylinder_x(bm, 0.09, spec["handle_r"] * 1.15, spec["handle_r"] * 1.15, x + 0.02, z, segments=10)
    elif spec["guard"] == "spikes":
        geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.1, radius2=0.0, depth=0.28)
        verts = geom["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "Y"))
        bmesh.ops.translate(bm, vec=Vector((x - 0.08, 0, z)), verts=verts)
    else:
        sphere(bm, 0.1, (x, 0, z), 10)
    return bm


def build_extra(name, spec, z):
    """Decorations. Returns None when a knife has none."""
    extras = spec["extras"]
    if not extras:
        return None
    bm = bmesh.new()
    h, length = spec["height"], spec["length"]
    for extra in extras:
        if extra == "rivets":
            for i in range(3):
                x = -0.2 - i * (spec["handle_len"] - 0.3) / 2
                for side in (1, -1):
                    sphere(bm, 0.03, (x, side * spec["handle_r"] * 1.05, z), 6)
        elif extra == "grooves":
            for i in range(3):
                cylinder_x(bm, 0.05, spec["handle_r"] * 1.1, spec["handle_r"] * 1.1, -0.2 - i * 0.2, z, 10)
        elif extra == "button":
            box(bm, (0.12, 0.05, 0.08), (-0.25, 0, z + spec["handle_r"] * 1.3), bevel=0.3)
        elif extra == "hole":
            # the classic cleaver hanging hole: a dark disc pushed through the blade
            geom = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.08, radius2=0.08, depth=0.14)
            bmesh.ops.rotate(bm, verts=geom["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"))
            bmesh.ops.translate(bm, vec=Vector((length * 0.82, 0, h * 0.78)), verts=geom["verts"])
        elif extra == "gem":
            sphere(bm, 0.075, (-0.02, 0, z), 8)
            sphere(bm, 0.06, (-spec["handle_len"] - 0.1, 0, z), 8)
        elif extra == "fuller":
            # a raised ridge down the middle of the dagger
            box(bm, (length * 0.55, 0.075, 0.04), (length * 0.3, 0, h * 0.5), bevel=0.4)
        elif extra == "habaki":
            box(bm, (0.12, 0.08, h * 1.15), (0.06, 0, h * 0.55), bevel=0.3)
        elif extra == "crystals":
            for i, (x, tilt) in enumerate([(0.3, -0.3), (0.8, 0.2), (1.35, -0.15)]):
                cone_up(bm, 0.07, 0.3 - i * 0.05, (x, 0, h * 0.95), tilt)
                cone_up(bm, 0.06, 0.25 - i * 0.04, (x + 0.1, 0, h * 0.05), math.pi + tilt)
        elif extra == "flames":
            for i in range(4):
                s = 0.15 + i * 0.2
                top, _, bend = fang(s)
                cone_up(bm, 0.06, 0.22 + 0.06 * (i % 2), (length * s, 0, (top + bend) * h - 0.02), -0.5)
        elif extra in ("thorns", "drips", "sparks", "ridges", "stars", "orbs", "knuckles"):
            profile = spec["profile"]
            count = {"thorns": 6, "drips": 5, "sparks": 6, "ridges": 6, "stars": 3, "orbs": 4, "knuckles": 6}[extra]
            for i in range(count):
                s = 0.12 + i * 0.75 / max(count - 1, 1)
                top, bot, bend = profile(s)
                x = length * s
                z_top, z_bot = (top + bend) * h, (bot + bend) * h
                if extra == "thorns":
                    # little thorns off both edges, alternating
                    if i % 2 == 0:
                        cone_up(bm, 0.035, 0.13, (x, 0, z_top - 0.01), -0.6)
                    else:
                        cone_up(bm, 0.035, 0.13, (x, 0, z_bot + 0.01), math.pi + 0.6)
                elif extra == "drips":
                    # molten drips hanging off the edge
                    cone_up(bm, 0.05 + 0.02 * (i % 2), 0.16 + 0.08 * (i % 3), (x, 0, z_bot + 0.02), math.pi)
                elif extra == "sparks":
                    for side in (1, -1):
                        cone_up(bm, 0.03, 0.14, (x, 0, z_top if side > 0 else z_bot), (0.0 if side > 0 else math.pi) + side * 0.7)
                elif extra == "ridges":
                    radius = max((z_top - z_bot) * 0.55, 0.03)
                    cylinder_x(bm, 0.035, radius, radius, x, (z_top + z_bot) / 2, segments=8)
                elif extra == "stars":
                    # five-pointed stars set into the blade face (both sides)
                    cz = (z_top + z_bot) / 2 + (0.15 if i % 2 else -0.1) * h
                    for side in (1, -1):
                        pts = []
                        for k in range(10):
                            a = math.pi / 2 + k * math.pi / 5
                            r = 0.11 if k % 2 == 0 else 0.045
                            pts.append(bm.verts.new((x + math.cos(a) * r, side * 0.065, cz + math.sin(a) * r)))
                        bm.faces.new(pts if side > 0 else list(reversed(pts)))
                elif extra == "orbs":
                    # planets riding the spine of the blade
                    sphere(bm, 0.045 + 0.015 * (i % 2), (x, 0, z_top + 0.07), 8)
                elif extra == "knuckles":
                    sphere(bm, 0.05, (x, 0, z_top), 6)
        elif extra == "skullcap":
            # a skull on the pommel end of the reaper
            sphere(bm, 0.13, (-spec["handle_len"] - 0.22, 0, z + 0.02), 10)
            box(bm, (0.12, 0.16, 0.08), (-spec["handle_len"] - 0.2, 0, z - 0.1), bevel=0.3)
        elif extra == "owlwings":
            # Athena's owl wings spreading from the guard
            for side in (1, -1):
                for k in range(3):
                    box(bm, (0.06, 0.05, 0.22 - k * 0.04),
                        (-0.04 - k * 0.07, 0, z + side * (h * 1.05 + k * 0.08)), bevel=0.3)
        elif extra == "laurel":
            # a laurel wreath of little leaves around the guard
            for k in range(10):
                a = k / 10 * math.pi * 2
                sphere(bm, 0.04, (-0.05, math.cos(a) * 0.16, z + math.sin(a) * h * 0.9), 6)
        elif extra == "halo":
            # a ring floating around the blade, just in front of the guard
            ring_r, tube_r = h * 1.1, 0.025
            for k in range(16):
                a = k / 16 * math.pi * 2
                sphere(bm, tube_r * 1.6, (0.35, math.cos(a) * ring_r * 0.45, h * 0.5 + math.sin(a) * ring_r), 6)
        elif extra == "featherwings":
            # angel wings: fans of feathers sweeping back from the guard
            for side in (1, -1):
                for k in range(4):
                    tilt = side * (0.5 + k * 0.28)
                    cone_up(bm, 0.05, 0.38 - k * 0.05, (-0.05 - k * 0.04, 0, z + side * h * 0.6), tilt if side > 0 else math.pi + tilt)
        elif extra == "quill":
            # the feather's shaft running down the middle
            box(bm, (length * 0.9, 0.08, 0.035), (length * 0.45, 0, h * 0.5 + 0.03), bevel=0.4)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0001)
    return bm


def build_knife(name, spec):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    c = spec["colors"]
    godly = spec["rarity"] == "Godly"
    h = spec["height"]
    grip_z = h * 0.5

    blade = mesh_object(
        "Blade",
        build_blade(spec["length"], h, spec["profile"], double_edged=spec.get("double", False)),
        material(f"{name}_Blade", c["Blade"], metallic=0.9, roughness=0.25, emission=2.0 if godly else 0.0),
        root,
    )
    guard = mesh_object("Guard", build_guard(spec, grip_z), material(f"{name}_Guard", c["Guard"], metallic=0.6), root)
    handle = mesh_object("Handle", build_handle(spec, grip_z), material(f"{name}_Handle", c["Handle"], roughness=0.8), root)
    pommel = mesh_object("Pommel", build_pommel(spec, grip_z), material(f"{name}_Pommel", c["Guard"], metallic=0.6), root)
    parts = [blade, guard, handle, pommel]
    extra_bm = build_extra(name, spec, grip_z)
    if extra_bm is not None:
        extra_color = c["Blade"] if spec["extras"][0] in ("crystals", "flames", "gem") else c["Guard"]
        parts.append(mesh_object("Extra", extra_bm, material(f"{name}_Extra", extra_color, metallic=0.5,
                                                             emission=3.0 if godly else 0.0), root))

    # Origin in the middle of the grip, so it works directly as a Tool handle
    offset = Vector((0.05 + spec["handle_len"] / 2, 0, -grip_z))
    for obj in parts:
        obj.data.transform(Matrix.Translation(offset))
    return root, parts


def export_fbx(root, parts, path):
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for p in parts:
        p.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        object_types={"EMPTY", "MESH"},
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
    )


def render_lineup(path, count):
    """Two columns of knives on a dark background (the knives are laid out by main())."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    rows = (count + 1) // 2
    scene.render.resolution_x, scene.render.resolution_y = 1600, max(400, rows * 200)
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("W")
    scene.world = world
    world.color = (0.08, 0.08, 0.1)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 9.6
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (COLUMN_GAP / 2 + 0.6, -10, -(rows - 1) * ROW_GAP / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


COLUMN_GAP = 4.6
ROW_GAP = 1.2


def main():
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    manifest = {}
    items = [(n, s) for n, s in KNIVES.items() if ONLY in (None, n)]
    for row, (name, spec) in enumerate(items):
        root, parts = build_knife(name, spec)
        path = EXPORT_DIR / f"{name}.fbx"
        export_fbx(root, parts, path)
        # lay them out in two columns for the preview render
        root.location = ((row % 2) * COLUMN_GAP, 0, -(row // 2) * ROW_GAP)
        manifest[name] = {
            "rarity": spec["rarity"],
            "fbx": f"blender/exports/{name}.fbx",
            "parts": [p.name.split(".")[0] for p in parts],
            "colors": {**spec["colors"], "Pommel": spec["colors"]["Guard"]},
        }
        print(f"exported {path}")
    if ONLY is None:
        (ROOT / "blender" / "knives.json").write_text(json.dumps(manifest, indent=2))
    render_lineup(PREVIEW_DIR / "lineup.png", len(items))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender" / "knives.blend"))


main()
