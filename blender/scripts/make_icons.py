"""Render the Murderer perk icons with Blender: chunky low-poly 3D symbols on a round badge,
outlined (Freestyle), transparent background, 256x256 PNGs in blender/textures/icons/.

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/make_icons.py [-- Name Name ...]

  Fury            a knife wreathed in flames
  Identifier      a watching eye
  Bulletproof     a shield with a flattened bullet
  ShapeShifter    a mask with swap arrows
  SpamKnife       an infinity sign with knives (unlimited throws)
  GhostKnife      a ghost with a knife passing through it
  Invisiknife     an eye struck through
  LaserKnife      a lightning bolt and a knife
  ExplodingKnife  a lit bomb
  Hellfire        a fireball with a knife
Then upload each (Studio MCP upload_image) and paste the ids into src/shared/Config/Textures.luau.
"""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "textures" / "icons"
SIZE = 256


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def srgb_to_linear(c):
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


# Scene ---------------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    # Thick dark outlines, cartoon style
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 3.2
    settings = scene.view_layers[0].freestyle_settings
    for old in list(settings.linesets):
        settings.linesets.remove(old)
    lineset = settings.linesets.new("Outline")
    lineset.select_by_visibility = True
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = False
    lineset.linestyle = bpy.data.linestyles.new("Ink")
    lineset.linestyle.color = (0.05, 0.03, 0.08)
    lineset.linestyle.thickness = 3.2
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.55, 0.6, 1)
    bg.inputs["Strength"].default_value = 0.7
    scene.world = world
    # Camera looking along +Y at the XZ plane
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.35
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0, -10, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    # Key light from the upper left, a softer fill from the right
    for name, energy, rot in (("Key", 4.0, (50, 0, -35)), ("Fill", 1.6, (70, 0, 50))):
        light_data = bpy.data.lights.new(name, "SUN")
        light_data.energy = energy
        light = bpy.data.objects.new(name, light_data)
        light.rotation_euler = tuple(math.radians(a) for a in rot)
        bpy.context.collection.objects.link(light)


def material(name, color, emission=0.0, metallic=0.0, roughness=0.45, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    linear = srgb_to_linear(rgb(color) if isinstance(color, str) else color)
    bsdf.inputs["Base Color"].default_value = (*linear, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*linear, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
    return mat


def obj_from_bmesh(name, bm, mat):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def place(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = tuple(math.radians(a) for a in rot)
    obj.scale = scale
    return obj


# Primitives (all built as fresh objects) ------------------------------------------------------

def cube(name, size, mat, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
    return place(obj_from_bmesh(name, bm, mat), loc, rot)


def sphere(name, radius, mat, loc=(0, 0, 0), scale=(1, 1, 1), segments=16, rings=10):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    return place(obj_from_bmesh(name, bm, mat), loc, (0, 0, 0), scale)


def cylinder(name, radius, depth, mat, loc=(0, 0, 0), rot=(0, 0, 0), segments=24, radius2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm, cap_ends=True, segments=segments, radius1=radius,
        radius2=radius if radius2 is None else radius2, depth=depth,
    )
    return place(obj_from_bmesh(name, bm, mat), loc, rot)


def torus(name, major, minor, mat, loc=(0, 0, 0), rot=(0, 0, 0), segments=32, sides=10, arc=360):
    bm = bmesh.new()
    rings = []
    count = segments if arc >= 360 else segments + 1
    for i in range(count):
        a = math.radians(arc) * i / segments
        center = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        ring = []
        for j in range(sides):
            b = 2 * math.pi * j / sides
            offset = Vector((math.cos(a), math.sin(a), 0)) * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor))
            ring.append(bm.verts.new(center + offset))
        rings.append(ring)
    for i in range(len(rings) - (0 if arc >= 360 else 1)):
        r0, r1 = rings[i], rings[(i + 1) % len(rings)]
        for j in range(sides):
            bm.faces.new((r0[j], r0[(j + 1) % sides], r1[(j + 1) % sides], r1[j]))
    if arc < 360:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    return place(obj_from_bmesh(name, bm, mat), loc, rot)


def prism(name, points, depth, mat, loc=(0, 0, 0), rot=(0, 0, 0)):
    """A flat polygon in the XZ plane (points are (x, z)), extruded `depth` along Y."""
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in points]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in points]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(points)
    for i in range(n):
        bm.faces.new((front[i], back[i], back[(i + 1) % n], front[(i + 1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return place(obj_from_bmesh(name, bm, mat), loc, rot)


def tube(name, path, radius, mat, sides=10):
    """A tube along a list of 3D points."""
    bm = bmesh.new()
    rings = []
    for i, p in enumerate(path):
        p = Vector(p)
        ahead = Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])
        ahead.normalize()
        side = ahead.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(ahead)
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * radius))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for j in range(sides):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return obj_from_bmesh(name, bm, mat)


def badge(color, rim="#1a1222"):
    """The round coin every icon sits on."""
    face = material("Badge", color, roughness=0.35)
    edge = material("Rim", rim, metallic=0.3, roughness=0.4)
    cylinder("Badge", 1.0, 0.18, face, loc=(0, 0.35, 0), rot=(90, 0, 0), segments=48)
    torus("BadgeRim", 1.0, 0.07, edge, loc=(0, 0.24, 0), rot=(90, 0, 0), segments=48, sides=8)


def knife(name, loc=(0, 0, 0), angle=0.0, length=1.4, blade="#e6eaf0", glow=0.0, alpha=1.0):
    """A knife in the XZ plane pointing up (+Z) before rotating by `angle` degrees about Y."""
    blade_mat = material(name + "Blade", blade, emission=glow, metallic=0.6, roughness=0.25, alpha=alpha)
    guard_mat = material(name + "Guard", "#3a3442", metallic=0.5, alpha=alpha)
    grip_mat = material(name + "Grip", "#7a3b26", alpha=alpha)
    L = length
    parts = [
        prism(name + "B", [(-0.13 * L, 0), (0.13 * L, 0), (0.1 * L, 0.45 * L), (0, 0.62 * L), (-0.1 * L, 0.45 * L)], 0.08, blade_mat),
        cube(name + "G", (0.42 * L, 0.12, 0.07 * L), guard_mat, bevel=0.01),
        cylinder(name + "H", 0.06 * L, 0.3 * L, grip_mat, loc=(0, 0, -0.18 * L), segments=10),
    ]
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for p in parts:
        p.parent = root
    root.location = loc
    root.rotation_euler = (0, math.radians(angle), 0)
    return root


def flame(name, loc, height, color, tilt=0.0):
    mat = material(name, color, emission=2.5)
    cone = cylinder(name, height * 0.28, height, mat, rot=(0, tilt, 0), segments=8, radius2=0.0)
    cone.location = loc
    return cone


# Icons -----------------------------------------------------------------------------------------

def icon_fury():
    badge("#c8283c")
    for x, h, t in ((-0.45, 0.9, -15), (0.0, 1.25, 0), (0.45, 0.9, 15), (-0.22, 0.7, -8), (0.24, 0.75, 8)):
        flame(f"Flame{x}", (x, 0.1, -0.15 + h / 2 - 0.3), h, "#ff8a1e" if h > 0.8 else "#ffd23c", t)
    knife("Knife", loc=(0, -0.2, -0.2), angle=0, length=1.25)


def icon_identifier():
    badge("#e0a91e")
    white = material("EyeWhite", "#fbfbff", roughness=0.3)
    sphere("Eye", 0.62, white, loc=(0, -0.05, 0), scale=(1.15, 0.35, 0.62))
    cylinder("Iris", 0.3, 0.12, material("Iris", "#2f8fff", emission=0.6), loc=(0, -0.3, 0), rot=(90, 0, 0))
    cylinder("Pupil", 0.14, 0.14, material("Pupil", "#0c0a14"), loc=(0, -0.37, 0), rot=(90, 0, 0))
    sphere("Shine", 0.06, material("Shine", "#ffffff", emission=3), loc=(0.1, -0.45, 0.1))
    lid = material("Lid", "#7a5a10")
    torus("Lid", 0.72, 0.06, lid, loc=(0, -0.1, -0.12), rot=(90, 0, 0), arc=180, segments=20)


def icon_bulletproof():
    badge("#3c6ea0")
    shield = material("Shield", "#c9d3df", metallic=0.7, roughness=0.3)
    prism("Shield", [(-0.55, 0.55), (0.55, 0.55), (0.55, -0.05), (0, -0.7), (-0.55, -0.05)], 0.22, shield, loc=(0, -0.05, 0.05))
    trim = material("ShieldTrim", "#ffc83c", metallic=0.8)
    prism("ShieldStripe", [(-0.08, 0.5), (0.08, 0.5), (0.08, -0.55), (-0.08, -0.55)], 0.26, trim, loc=(0, -0.06, 0.05))
    # A bullet bouncing off, with sparks where it hit
    brass = material("Bullet", "#e0a43a", metallic=0.9, roughness=0.25)
    bullet = bpy.data.objects.new("BulletRoot", None)
    bpy.context.collection.objects.link(bullet)
    for p in (
        cylinder("Bullet", 0.1, 0.28, brass, loc=(0, 0, 0), segments=12),
        cylinder("BulletTip", 0.1, 0.16, brass, loc=(0, 0, 0.22), segments=12, radius2=0.0),
    ):
        p.parent = bullet
    bullet.location = (0.62, -0.35, 0.55)
    bullet.rotation_euler = (0, math.radians(40), 0)
    spark = material("Spark", "#fff07a", emission=3)
    for i, a in enumerate((20, 60, 100)):
        r = math.radians(a)
        cube(f"Spark{i}", (0.22, 0.05, 0.05), spark, loc=(0.25 + math.cos(r) * 0.18, -0.35, 0.3 + math.sin(r) * 0.18), rot=(0, -a, 0))


def icon_shapeshifter():
    badge("#7a3cc8")
    mask = material("Mask", "#f2ecff", roughness=0.3)
    sphere("Mask", 0.62, mask, loc=(0, -0.05, 0.02), scale=(0.85, 0.3, 1.0))
    dark = material("Holes", "#1b1026")
    for x in (-0.2, 0.2):
        sphere(f"Hole{x}", 0.11, dark, loc=(x, -0.25, 0.18), scale=(1.3, 0.5, 0.8))
    torus("Smile", 0.22, 0.04, dark, loc=(0, -0.25, -0.12), rot=(90, 0, 180), arc=180, segments=14, sides=6)
    arrow = material("Arrow", "#ffd23c", emission=0.8)
    torus("SwapTop", 0.85, 0.06, arrow, loc=(0, -0.2, 0), rot=(90, 0, 20), arc=120, segments=18, sides=8)
    torus("SwapBottom", 0.85, 0.06, arrow, loc=(0, -0.2, 0), rot=(90, 0, 200), arc=120, segments=18, sides=8)
    cylinder("HeadTop", 0.15, 0.25, arrow, loc=(-0.75, -0.2, 0.42), rot=(0, -55, 0), segments=8, radius2=0.0)
    cylinder("HeadBottom", 0.15, 0.25, arrow, loc=(0.75, -0.2, -0.42), rot=(0, 125, 0), segments=8, radius2=0.0)


def icon_spamknife():
    badge("#d0263a")
    # The infinity sign: a lemniscate tube, glowing gold
    gold = material("Infinity", "#ffd23c", emission=1.6, metallic=0.4)
    points = []
    for i in range(97):
        t = 2 * math.pi * i / 96
        d = 1 + math.sin(t) ** 2
        points.append((0.78 * math.cos(t) / d, -0.15, 0.78 * math.sin(t) * math.cos(t) / d + 0.18))
    tube("Infinity", points, 0.085, gold, sides=10)
    # A fan of knives flying out underneath
    for i, angle in enumerate((-50, -17, 17, 50)):
        a = math.radians(angle)
        knife(
            f"Knife{i}",
            loc=(math.sin(a) * 0.42, -0.3, -0.55 + math.cos(a) * 0.2),
            angle=angle,
            length=0.7,
            blade="#ffffff",
            glow=0.9,
        )


def icon_ghostknife():
    badge("#1f9e9a")
    ghost_mat = material("Ghost", "#f4fbff", emission=0.4, alpha=0.85)
    sphere("GhostHead", 0.48, ghost_mat, loc=(0, 0, 0.18), scale=(1, 0.6, 1))
    points = [(-0.48, 0.18)]
    for i in range(7):
        x = -0.48 + i * 0.16
        points.append((x, -0.5 if i % 2 == 0 else -0.32))
    points.append((0.48, 0.18))
    prism("GhostBody", points, 0.5, ghost_mat, loc=(0, 0, 0))
    eye = material("GhostEye", "#101018")
    for x in (-0.16, 0.16):
        sphere(f"GhostEye{x}", 0.08, eye, loc=(x, -0.3, 0.25), scale=(0.8, 0.5, 1.2))
    knife("Knife", loc=(0.05, -0.45, -0.05), angle=-60, length=1.3, blade="#c8fff8", glow=0.4)


def icon_invisiknife():
    badge("#283c78")
    knife("Knife", loc=(0, -0.05, 0), angle=-35, length=1.45, blade="#bcd2ff", glow=0.3, alpha=0.45)
    white = material("EyeWhite", "#fbfbff", roughness=0.3)
    sphere("Eye", 0.36, white, loc=(0, -0.3, 0.05), scale=(1.2, 0.3, 0.65))
    cylinder("Iris", 0.16, 0.08, material("Iris", "#5a78ff"), loc=(0, -0.42, 0.05), rot=(90, 0, 0))
    slash = material("Slash", "#ff3c50", emission=0.8)
    cube("Slash", (1.25, 0.1, 0.12), slash, loc=(0, -0.5, 0.05), rot=(0, 35, 0), bevel=0.03)


def icon_laserknife():
    badge("#e6b414")
    bolt = material("Bolt", "#fff59a", emission=2.5)
    prism(
        "Bolt",
        [(0.12, 0.85), (-0.38, 0.0), (-0.05, 0.0), (-0.2, -0.85), (0.4, 0.12), (0.06, 0.12), (0.3, 0.85)],
        0.16,
        bolt,
        loc=(0.15, -0.05, 0),
    )
    knife("Knife", loc=(-0.35, -0.3, -0.05), angle=-40, length=1.1, blade="#ffffff", glow=1.0)


def icon_explodingknife():
    badge("#ff7a1e")
    bomb = material("Bomb", "#20202a", metallic=0.3, roughness=0.35)
    sphere("Bomb", 0.5, bomb, loc=(-0.05, -0.05, -0.12))
    sphere("BombShine", 0.1, material("BombShine", "#ffffff", emission=1.2), loc=(-0.25, -0.5, 0.1), scale=(1, 0.4, 1))
    cylinder("Cap", 0.16, 0.16, material("Cap", "#6a6a78", metallic=0.7), loc=(0.2, -0.05, 0.32), rot=(0, 30, 0), segments=10)
    tube("Fuse", [(0.26, -0.05, 0.4), (0.38, -0.05, 0.55), (0.32, -0.05, 0.7), (0.45, -0.05, 0.8)], 0.035, material("Fuse", "#c8a064"))
    spark = material("Spark", "#fff07a", emission=4)
    for i in range(6):
        a = i / 6 * math.pi * 2
        cube(f"Spark{i}", (0.3, 0.05, 0.06), spark, loc=(0.45 + math.cos(a) * 0.12, -0.1, 0.82 + math.sin(a) * 0.12), rot=(0, -math.degrees(a), 0))


def icon_hellfire():
    badge("#781414")
    sphere("Fireball", 0.45, material("Fireball", "#ff6a14", emission=2.0), loc=(0.15, -0.05, 0.15))
    sphere("FireCore", 0.28, material("FireCore", "#ffe678", emission=3.0), loc=(0.2, -0.3, 0.18))
    for i, (x, z, h, t) in enumerate(((-0.25, 0.45, 0.6, -40), (0.0, 0.62, 0.55, -20), (0.45, 0.55, 0.5, 15), (-0.35, 0.1, 0.5, -70))):
        flame(f"Tongue{i}", (x, 0.0, z), h, "#ff9a28", t)
    knife("Knife", loc=(-0.3, -0.4, -0.3), angle=45, length=1.0, blade="#ffb46a", glow=0.8)


ICONS = {
    "Fury": icon_fury,
    "Identifier": icon_identifier,
    "Bulletproof": icon_bulletproof,
    "ShapeShifter": icon_shapeshifter,
    "SpamKnife": icon_spamknife,
    "GhostKnife": icon_ghostknife,
    "Invisiknife": icon_invisiknife,
    "LaserKnife": icon_laserknife,
    "ExplodingKnife": icon_explodingknife,
    "Hellfire": icon_hellfire,
}


def main():
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in ICONS.items():
        if only and name not in only:
            continue
        reset()
        build()
        bpy.context.scene.render.filepath = str(OUT / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", name)


main()
