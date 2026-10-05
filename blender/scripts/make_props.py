"""Procedurally build the Steal and Murder props and export one FBX per prop.

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/make_props.py

Props (all low poly, cartoony, built in studs: 1 Blender unit = 1 stud, Z up, front faces -Y):
  Chest        the sealed case watchmen drop: planked chest, rounded lid, iron bands, lock
  LootSack     a burglar's swag bag with a big "$"
  BurglarMask  the classic domino mask
  Skull        for the Bone Fortress gate towers
  BoneSpike    curved horns along Bone Fortress walls
  Crystal      a cluster of cursed crystals (Cursed Citadel towers)
  Chandelier   wrought-iron ring of candles (vault ceilings)
  Sconce       gothic wall candle holder (vault walls)
  Lantern      hanging lantern (hub lamp posts)
  Camera       the old flash camera (Flash power)
  Throne       a little trophy pedestal under each mounted knife's aura

Each prop exports as separate meshes per material (named parts) so every part becomes its own
MeshPart in Roblox and gets its colour/material there. Object transforms are applied so every
MeshPart imports unrotated; the prop's origin is its pivot in game.
"""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
EXPORT_DIR = ROOT / "blender" / "exports" / "props"
PREVIEW_DIR = ROOT / "blender" / "previews"


# --- helpers ------------------------------------------------------------------------------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, color, metallic=0.0, roughness=0.6, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    mat.diffuse_color = (*color, 1.0)
    return mat


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255)


def mesh_object(name, bm, mat, parent):
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    return obj


def xform(bm, verts, matrix):
    bmesh.ops.transform(bm, matrix=matrix, verts=verts)


def box(bm, size, center, rot=None, bevel=0.0):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    xform(bm, verts, Matrix.Diagonal((*size, 1.0)))
    if bevel > 0:
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
        verts = [v for v in bm.verts if v.select or True]
    if rot is not None:
        xform(bm, geom["verts"], rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=geom["verts"])
    return geom["verts"]


def add_box(bm, size, center, rot=None):
    """A box as its own island (no bevel), optional rotation about its centre."""
    geom = bmesh.ops.create_cube(bm, size=1.0)
    verts = geom["verts"]
    xform(bm, verts, Matrix.Diagonal((*size, 1.0)))
    if rot is not None:
        xform(bm, verts, rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def cylinder(bm, radius, depth, center, segments=12, rot=None, radius2=None):
    geom = bmesh.ops.create_cone(
        bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius if radius2 is None else radius2, depth=depth
    )
    verts = geom["verts"]
    if rot is not None:
        xform(bm, verts, rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def sphere(bm, radius, center, segments=10, rings=7, scale=(1, 1, 1)):
    geom = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    verts = geom["verts"]
    xform(bm, verts, Matrix.Diagonal((*scale, 1.0)))
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts)
    return verts


def torus(bm, major, minor, center, segments=20, sides=6, rot=None):
    verts_all = []
    rings = []
    for i in range(segments):
        a = i / segments * math.tau
        ring = []
        for j in range(sides):
            b = j / sides * math.tau
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor * math.sin(b))))
        rings.append(ring)
        verts_all += ring
    for i in range(segments):
        a, b = rings[i], rings[(i + 1) % segments]
        for j in range(sides):
            bm.faces.new((a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j]))
    if rot is not None:
        xform(bm, verts_all, rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=verts_all)
    return verts_all


def text_mesh(text, size, depth, center, rot=None):
    """A 3D text glyph as a bmesh (for the "$" on the loot sack)."""
    curve = bpy.data.curves.new("txt", type="FONT")
    curve.body = text
    curve.size = size
    curve.extrude = depth
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    obj = bpy.data.objects.new("txt", curve)
    bpy.context.collection.objects.link(obj)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph))
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.objects.remove(obj)
    if rot is not None:
        xform(bm, bm.verts, rot)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


ROT_X90 = Matrix.Rotation(math.radians(90), 4, "X")
ROT_Y90 = Matrix.Rotation(math.radians(90), 4, "Y")


def wobble(bm, verts, amount, seed):
    """Organic lumpiness (sacks, bones)."""
    for i, v in enumerate(verts):
        n = math.sin(v.co.x * 7.1 + seed) * math.cos(v.co.y * 5.3 + seed * 2) * math.sin(v.co.z * 6.7 + seed * 3)
        v.co += v.normal * n * amount


# --- props --------------------------------------------------------------------------------

def build_chest(root):
    """2.8 x 1.9 x ~2.1. Origin at the centre of the box."""
    wood_bm = bmesh.new()
    # Body: planks (slightly offset, so it reads as wood)
    for i in range(4):
        z = -0.85 + i * 0.36
        add_box(wood_bm, (2.8 - (i % 2) * 0.04, 1.9 - (i % 2) * 0.04, 0.34), (0, 0, z + 0.17))
    # Rounded lid: half cylinder from slats
    slats = 8
    for i in range(slats):
        a0 = math.pi * i / slats
        a1 = math.pi * (i + 1) / slats
        a = (a0 + a1) / 2
        r = 0.98
        add_box(
            wood_bm,
            (2.86, 2 * r * math.sin(math.pi / slats / 2) * 1.05, 0.16),
            (0, math.cos(a) * r * 0.97, 0.57 + math.sin(a) * r * 0.62),
            rot=Matrix.Rotation(a - math.pi / 2, 4, "X"),
        )
    iron_bm = bmesh.new()
    # Iron bands around box and lid
    for x in (-0.95, 0.95):
        add_box(iron_bm, (0.22, 1.98, 1.5), (x, 0, -0.12))
        ring = torus(iron_bm, 1.0, 0.07, (x, 0, 0.57), segments=16, sides=4, rot=ROT_Y90)
        for v in ring:
            # follow the lid's flattened curve; the lower half hides inside the box
            v.co.z = 0.57 + (v.co.z - 0.57) * 0.64
    # Corner caps
    for x in (-1.42, 1.42):
        for y in (-0.96, 0.96):
            add_box(iron_bm, (0.2, 0.2, 1.55), (x, y, -0.12))
    # Handles on the ends
    for x in (-1.45, 1.45):
        torus(iron_bm, 0.28, 0.05, (x + (0.05 if x > 0 else -0.05), 0, 0.0), segments=10, sides=4, rot=ROT_Y90)
    lock_bm = bmesh.new()
    add_box(lock_bm, (0.55, 0.12, 0.62), (0, -1.0, 0.35))
    cylinder(lock_bm, 0.22, 0.1, (0, -1.08, 0.75), segments=10, rot=ROT_X90)
    seam_bm = bmesh.new()
    add_box(seam_bm, (2.84, 1.94, 0.08), (0, 0, 0.6))
    mesh_object("Wood", wood_bm, material("Chest_Wood", rgb(110, 70, 40), roughness=0.9), root)
    mesh_object("Iron", iron_bm, material("Chest_Iron", rgb(70, 66, 78), metallic=0.8), root)
    mesh_object("Lock", lock_bm, material("Chest_Lock", rgb(255, 200, 60), emission=2), root)
    mesh_object("Seam", seam_bm, material("Chest_Seam", rgb(255, 200, 60), emission=2), root)


def build_loot_sack(root):
    """~2.2 wide, 2.7 tall, origin at the bottom centre."""
    sack = bmesh.new()
    verts = sphere(sack, 1.0, (0, 0, 1.0), segments=14, rings=10, scale=(1.1, 0.95, 1.05))
    # Pinch the top into a neck
    for v in verts:
        if v.co.z > 1.6:
            t = (v.co.z - 1.6) / 0.5
            v.co.x *= 1 - 0.75 * t
            v.co.y *= 1 - 0.75 * t
        if v.co.z < 0.15:
            v.co.z = 0.15 + (v.co.z - 0.15) * 0.3  # flat bottom where it sits
    bmesh.ops.recalc_face_normals(sack, faces=sack.faces)
    wobble(sack, verts, 0.06, 1.3)
    # The floppy top above the tie
    top = cylinder(sack, 0.15, 0.4, (0, 0, 2.25), segments=8, radius2=0.42)
    tie = bmesh.new()
    torus(tie, 0.3, 0.09, (0, 0, 2.05), segments=12, sides=5)
    add_box(tie, (0.12, 0.08, 0.45), (0.25, -0.2, 1.85), rot=Matrix.Rotation(0.4, 4, "Y"))
    emblem = text_mesh("$", 1.0, 0.06, (0, -1.02, 1.0), rot=ROT_X90)
    mesh_object("Sack", sack, material("Sack_Cloth", rgb(160, 120, 75), roughness=1), root)
    mesh_object("Tie", tie, material("Sack_Rope", rgb(90, 60, 35), roughness=1), root)
    mesh_object("Emblem", emblem, material("Sack_Dollar", rgb(255, 215, 60), metallic=0.4), root)


def build_mask(root):
    """A band that wraps the front of a Roblox head (1.2 wide). Origin = centre of the head front."""
    bm = bmesh.new()
    # Curved band: a section of a cylinder around the head, with two eye holes
    segments = 14
    radius = 0.66
    height = 0.42
    rows = []
    for i in range(segments + 1):
        a = math.radians(-80 + 160 * i / segments)
        x = math.sin(a) * radius
        y = -math.cos(a) * radius + radius * 0.92
        rows.append((x, y))
    col_verts = []
    for x, y in rows:
        col_verts.append([bm.verts.new((x, y, -height / 2)), bm.verts.new((x, y, height / 2))])
    for i in range(segments):
        # skip two quads per eye
        mid = segments // 2
        if i in (mid - 3, mid - 2, mid + 1, mid + 2):
            # eye: only thin strips above and below
            a0, a1 = col_verts[i], col_verts[i + 1]
            for lo, hi in ((0.0, 0.18), (0.82, 1.0)):
                v = [
                    bm.verts.new(a0[0].co.lerp(a0[1].co, lo)),
                    bm.verts.new(a1[0].co.lerp(a1[1].co, lo)),
                    bm.verts.new(a1[0].co.lerp(a1[1].co, hi)),
                    bm.verts.new(a0[0].co.lerp(a0[1].co, hi)),
                ]
                bm.faces.new(v)
            continue
        a0, a1 = col_verts[i], col_verts[i + 1]
        bm.faces.new((a0[0], a1[0], a1[1], a0[1]))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.05)
    # Little knot at the back sides
    sphere(bm, 0.09, (0.66, 0.6, 0), segments=6, rings=4)
    sphere(bm, 0.09, (-0.66, 0.6, 0), segments=6, rings=4)
    mesh_object("Mask", bm, material("Mask_Cloth", rgb(18, 18, 22), roughness=1), root)


def build_skull(root):
    """~1.3 wide. Origin at the centre of the cranium, facing -Y."""
    bone = bmesh.new()
    cranium = sphere(bone, 0.65, (0, 0.05, 0.1), segments=12, rings=9, scale=(1.0, 1.05, 0.95))
    # Cheekbones / face plate
    face = sphere(bone, 0.45, (0, -0.28, -0.25), segments=10, rings=6, scale=(1.15, 0.8, 0.8))
    jaw = add_box(bone, (0.8, 0.55, 0.32), (0, -0.25, -0.62))
    # Teeth
    for i in range(6):
        add_box(bone, (0.09, 0.08, 0.14), (-0.25 + i * 0.1, -0.53, -0.45))
    eyes = bmesh.new()
    for x in (-0.24, 0.24):
        sphere(eyes, 0.17, (x, -0.5, 0.0), segments=8, rings=5, scale=(1, 0.6, 1.1))
    nose = add_box(eyes, (0.14, 0.08, 0.16), (0, -0.62, -0.22), rot=Matrix.Rotation(math.radians(45), 4, "Y"))
    mesh_object("Bone", bone, material("Skull_Bone", rgb(236, 228, 205), roughness=0.7), root)
    mesh_object("Eyes", eyes, material("Skull_Eyes", rgb(255, 40, 40), emission=4), root)


def build_bone_spike(root):
    """A curved horn ~2.6 tall, origin at its base."""
    bm = bmesh.new()
    rings = 8
    sides = 6
    prev = None
    first = None
    for i in range(rings + 1):
        t = i / rings
        radius = 0.28 * (1 - t) + 0.02
        cx = 0.6 * t * t  # curves outward
        cz = 2.6 * t
        ring = []
        for j in range(sides):
            a = j / sides * math.tau
            ring.append(bm.verts.new((cx + math.cos(a) * radius, math.sin(a) * radius, cz)))
        if prev:
            for j in range(sides):
                bm.faces.new((prev[j], prev[(j + 1) % sides], ring[(j + 1) % sides], ring[j]))
        else:
            first = ring
        prev = ring
    bm.faces.new(list(reversed(first)))
    bm.faces.new(prev)
    mesh_object("Bone", bm, material("Spike_Bone", rgb(232, 224, 200), roughness=0.6), root)


def build_crystal(root):
    """Cluster of 5 hexagonal crystals, ~2.6 tall, origin at the base."""
    bm = bmesh.new()
    specs = [(0, 0, 2.6, 0.38, 0, 0), (0.45, 0.15, 1.6, 0.26, 25, 10), (-0.4, 0.2, 1.8, 0.28, -22, 30),
             (0.1, -0.42, 1.3, 0.22, 15, -60), (-0.2, -0.3, 1.0, 0.2, -30, 200)]
    for x, y, h, r, tilt, yaw in specs:
        body = cylinder(bm, r, h * 0.78, (0, 0, h * 0.39), segments=6)
        tip = cylinder(bm, r, h * 0.22, (0, 0, h * 0.78 + h * 0.11), segments=6, radius2=0.0)
        rot = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(tilt), 4, "X")
        xform(bm, body + tip, rot)
        bmesh.ops.translate(bm, vec=Vector((x, y, 0)), verts=body + tip)
    mesh_object("Crystal", bm, material("Crystal_Glow", rgb(170, 70, 255), emission=3), root)


def build_chandelier(root):
    """Wrought-iron chandelier, 5.6 wide; origin at the top hook."""
    iron = bmesh.new()
    torus(iron, 2.4, 0.09, (0, 0, -3.2), segments=24, sides=5)
    torus(iron, 1.0, 0.07, (0, 0, -2.6), segments=16, sides=5)
    cylinder(iron, 0.12, 2.6, (0, 0, -1.6), segments=8)  # central rod
    sphere(iron, 0.3, (0, 0, -3.3), segments=8, rings=6)  # finial
    cylinder(iron, 0.06, 0.6, (0, 0, -0.3), segments=6)
    torus(iron, 0.18, 0.05, (0, 0, 0), segments=10, sides=4, rot=ROT_X90)
    candles = bmesh.new()
    flames = bmesh.new()
    count = 8
    for i in range(count):
        a = i / count * math.tau
        x, y = math.cos(a) * 2.4, math.sin(a) * 2.4
        # Arm from the rod to the ring, curling up
        arm = add_box(iron, (2.3, 0.08, 0.08), (math.cos(a) * 1.2, math.sin(a) * 1.2, -2.95),
                      rot=Matrix.Rotation(a, 4, "Z"))
        cylinder(iron, 0.16, 0.08, (x, y, -3.1), segments=8)  # drip cup
        cylinder(candles, 0.09, 0.55, (x, y, -2.8), segments=8)
        flame = sphere(flames, 0.09, (x, y, -2.42), segments=6, rings=4, scale=(1, 1, 1.9))
        # Chains up to the hook
        for k in range(5):
            t = (k + 0.5) / 5
            cx, cy, cz = x * (1 - t), y * (1 - t), -3.1 * (1 - t)
            torus(iron, 0.08, 0.025, (cx, cy, cz), segments=6, sides=3,
                  rot=Matrix.Rotation(a + (math.pi / 2 if k % 2 else 0), 4, "Z") @ ROT_X90)
    mesh_object("Iron", iron, material("Chandelier_Iron", rgb(40, 36, 46), metallic=0.7), root)
    mesh_object("Candles", candles, material("Chandelier_Wax", rgb(240, 230, 210)), root)
    mesh_object("Flames", flames, material("Chandelier_Flame", rgb(255, 180, 70), emission=5), root)


def build_sconce(root):
    """Gothic wall sconce; origin on the wall surface, sticks out along -Y."""
    iron = bmesh.new()
    # Backplate: pointed arch
    plate = bmesh.new()
    add_box(iron, (0.7, 0.12, 1.2), (0, 0, 0))
    add_box(iron, (0.5, 0.12, 0.5), (0, 0, 0.7), rot=Matrix.Rotation(math.radians(45), 4, "Y"))
    # Curling arm
    for i in range(6):
        t = i / 5
        add_box(iron, (0.12, 0.25, 0.12), (0, -0.15 - t * 0.9, -0.35 + math.sin(t * math.pi) * 0.35))
    cylinder(iron, 0.28, 0.12, (0, -1.05, -0.2), segments=10)
    cylinder(iron, 0.18, 0.25, (0, -1.05, -0.05), segments=10, radius2=0.26)
    plate.free()
    candle = bmesh.new()
    cylinder(candle, 0.1, 0.5, (0, -1.05, 0.3), segments=8)
    flame = bmesh.new()
    sphere(flame, 0.1, (0, -1.05, 0.68), segments=6, rings=4, scale=(1, 1, 2))
    mesh_object("Iron", iron, material("Sconce_Iron", rgb(45, 40, 50), metallic=0.7), root)
    mesh_object("Candle", candle, material("Sconce_Wax", rgb(240, 230, 210)), root)
    mesh_object("Flame", flame, material("Sconce_Flame", rgb(255, 170, 70), emission=5), root)


def build_lantern(root):
    """Hexagonal hanging lantern, 1.4 tall; origin at the centre of the glass."""
    iron = bmesh.new()
    cylinder(iron, 0.62, 0.12, (0, 0, -0.75), segments=6)
    cylinder(iron, 0.5, 0.35, (0, 0, 0.85), segments=6, radius2=0.12)
    cylinder(iron, 0.66, 0.08, (0, 0, 0.66), segments=6)
    torus(iron, 0.16, 0.04, (0, 0, 1.15), segments=10, sides=4, rot=ROT_X90)
    for j in range(6):
        a = j / 6 * math.tau + math.tau / 12
        add_box(iron, (0.06, 0.06, 1.4), (math.cos(a) * 0.55, math.sin(a) * 0.55, -0.05))
    glass = bmesh.new()
    cylinder(glass, 0.5, 1.3, (0, 0, -0.05), segments=6)
    mesh_object("Iron", iron, material("Lantern_Iron", rgb(40, 36, 46), metallic=0.7), root)
    mesh_object("Glass", glass, material("Lantern_Glass", rgb(255, 200, 120), emission=3), root)


def build_camera(root):
    """Old box camera with a flash dish on top; ~1.1 wide; origin at the body centre; lens -Y."""
    body = bmesh.new()
    add_box(body, (1.1, 0.55, 0.7), (0, 0, 0))
    add_box(body, (0.3, 0.3, 0.18), (-0.3, 0, 0.42))  # viewfinder
    lens = bmesh.new()
    cylinder(lens, 0.22, 0.35, (0.1, -0.42, -0.02), segments=12, rot=ROT_X90)
    cylinder(lens, 0.15, 0.06, (0.1, -0.62, -0.02), segments=12, rot=ROT_X90)
    flash = bmesh.new()
    cylinder(flash, 0.05, 0.4, (0.35, 0, 0.55), segments=6)
    dish = cylinder(flash, 0.05, 0.25, (0.35, -0.12, 0.85), segments=12, rot=ROT_X90, radius2=0.38)
    bulb = bmesh.new()
    sphere(bulb, 0.1, (0.35, -0.12, 0.85), segments=8, rings=5)
    mesh_object("Body", body, material("Camera_Body", rgb(35, 32, 36), roughness=0.5), root)
    mesh_object("Lens", lens, material("Camera_Lens", rgb(150, 150, 165), metallic=0.9), root)
    mesh_object("Dish", flash, material("Camera_Dish", rgb(200, 200, 210), metallic=1, roughness=0.2), root)
    mesh_object("Bulb", bulb, material("Camera_Bulb", rgb(255, 255, 220), emission=4), root)


def build_throne(root):
    """A little carved pedestal that sits under a mounted knife; origin at its top centre."""
    stone = bmesh.new()
    add_box(stone, (1.6, 0.6, 0.25), (0, 0, -0.12))
    add_box(stone, (1.2, 0.5, 0.2), (0, 0, -0.35))
    for x in (-0.72, 0.72):
        sphere(stone, 0.14, (x, -0.2, 0.05), segments=8, rings=5)
    gem = bmesh.new()
    sphere(gem, 0.12, (0, -0.31, -0.2), segments=6, rings=4, scale=(1, 0.5, 1))
    mesh_object("Stone", stone, material("Throne_Stone", rgb(90, 70, 50), roughness=0.8), root)
    mesh_object("Gem", gem, material("Throne_Gem", rgb(255, 255, 255), emission=3), root)


def build_pedestal(root):
    """Octagonal display pedestal a knife floats over (~3.4 wide, 1.3 tall); origin at the floor."""
    stone = bmesh.new()
    cylinder(stone, 1.75, 0.35, (0, 0, 0.175), segments=8)  # plinth
    cylinder(stone, 1.45, 0.6, (0, 0, 0.65), segments=8, radius2=1.3)  # body, tapering
    cylinder(stone, 1.6, 0.22, (0, 0, 1.06), segments=8)  # cap
    # little corner studs on the plinth
    for i in range(8):
        a = (i + 0.5) / 8 * math.tau
        add_box(stone, (0.22, 0.22, 0.18), (math.cos(a) * 1.62, math.sin(a) * 1.62, 0.44))
    trim = bmesh.new()
    torus(trim, 1.6, 0.06, (0, 0, 0.36), segments=8, sides=4)
    torus(trim, 1.62, 0.05, (0, 0, 1.17), segments=8, sides=4)
    glow = bmesh.new()
    cylinder(glow, 1.25, 0.06, (0, 0, 1.2), segments=8)  # the glowing top the knife hovers over
    # glowing rune slits round the body
    for i in range(8):
        a = i / 8 * math.tau
        add_box(glow, (0.08, 0.3, 0.32), (math.cos(a) * 1.39, math.sin(a) * 1.39, 0.7),
                rot=Matrix.Rotation(a, 4, "Z"))
    mesh_object("Stone", stone, material("Pedestal_Stone", rgb(70, 64, 82), roughness=0.85), root)
    mesh_object("Trim", trim, material("Pedestal_Trim", rgb(200, 160, 70), metallic=0.8), root)
    mesh_object("Glow", glow, material("Pedestal_Glow", rgb(90, 220, 255), emission=3), root)


def build_coin(root):
    """The round coin: 2.2 across, 0.32 thick, standing up and facing -Y. A raised rim, a notched
    edge and a little skull stamped on both faces. Origin at the centre."""
    gold = bmesh.new()
    cylinder(gold, 1.0, 0.24, (0, 0, 0), segments=28, rot=ROT_X90)
    rim = bmesh.new()
    for y in (-0.13, 0.13):
        torus(rim, 0.98, 0.08, (0, y, 0), segments=28, sides=6, rot=ROT_X90)
    # Notches around the edge, like a real coin
    for i in range(24):
        a = i / 24 * math.tau
        add_box(rim, (0.07, 0.3, 0.12), (math.cos(a) * 1.07, 0, math.sin(a) * 1.07),
                rot=Matrix.Rotation(-a, 4, "Y"))
    emblem = bmesh.new()
    eyes = bmesh.new()
    for side in (-1, 1):
        y = side * 0.13
        # cranium + jaw, raised off the face
        cylinder(emblem, 0.4, 0.06, (0, y, 0.1), segments=16, rot=ROT_X90)
        add_box(emblem, (0.46, 0.06, 0.3), (0, y, -0.28))
        for x in (-0.15, 0.15):
            sphere(eyes, 0.11, (x, y + side * 0.03, 0.08), segments=8, rings=5, scale=(1, 0.4, 1.15))
        add_box(eyes, (0.07, 0.04, 0.1), (0, y + side * 0.03, -0.1), rot=Matrix.Rotation(math.radians(45), 4, "Y"))
        for x in (-0.12, 0.0, 0.12):
            add_box(eyes, (0.035, 0.04, 0.16), (x, y + side * 0.03, -0.3))
    mesh_object("Gold", gold, material("Coin_Gold", rgb(255, 196, 40), metallic=0.9, roughness=0.3), root)
    mesh_object("Rim", rim, material("Coin_Rim", rgb(235, 160, 30), metallic=0.9, roughness=0.3), root)
    mesh_object("Emblem", emblem, material("Coin_Emblem", rgb(255, 225, 110), metallic=0.9, roughness=0.25), root)
    mesh_object("Eyes", eyes, material("Coin_Eyes", rgb(120, 70, 10), roughness=0.6), root)


PROPS = {
    "Coin": build_coin,
    "Pedestal": build_pedestal,
    "Chest": build_chest,
    "LootSack": build_loot_sack,
    "BurglarMask": build_mask,
    "Skull": build_skull,
    "BoneSpike": build_bone_spike,
    "Crystal": build_crystal,
    "Chandelier": build_chandelier,
    "Sconce": build_sconce,
    "Lantern": build_lantern,
    "Camera": build_camera,
    "Throne": build_throne,
}


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
    )


def render_sheet(path, roots):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    world = bpy.data.worlds.new("World")
    world.color = (0.05, 0.04, 0.07)
    scene.world = world
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 22
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (8, -30, -2)
    cam.rotation_euler = (math.radians(82), 0, 0)
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


import sys  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
import accessories  # noqa: E402

accessories.install(globals())
PROPS.update(accessories.ACCESSORIES)
ONLY = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else None


def main():
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    manifest = {}
    roots = []
    for index, (name, build) in enumerate([(n, b) for n, b in PROPS.items() if ONLY is None or n in ONLY]):
        root = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(root)
        build(root)
        parts = [c for c in root.children]
        path = EXPORT_DIR / f"{name}.fbx"
        export_fbx(root, parts, path)
        manifest[name] = {"fbx": f"blender/exports/props/{name}.fbx", "parts": [p.name.split(".")[0] for p in parts]}
        # Lay them out for the preview sheet
        root.location = ((index % 6) * 3.2, 0, -(index // 6) * 3.4)
        roots.append(root)
        print(f"exported {path}")
    if ONLY is None:
        (ROOT / "blender" / "props.json").write_text(json.dumps(manifest, indent=2))
    render_sheet(PREVIEW_DIR / "props.png", roots)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender" / "props.blend"))


main()
