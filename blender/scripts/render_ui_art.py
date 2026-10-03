"""Render actual knives/cases plus toy UI symbols into a reproducible 512px-tile atlas.
Run Blender headless with --python blender/scripts/render_ui_art.py.
Packing is done separately by tools/pack_ui_art.py; no existing model exports are modified.
"""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender/textures/ui"
OUT.mkdir(parents=True, exist_ok=True)


def load_builders(filename, marker):
    source = (ROOT / "blender/scripts" / filename).read_text(encoding="utf-8")
    ns = {"__file__": str(ROOT / "blender/scripts" / filename)}
    exec(compile(source[:source.rindex(marker)], filename, "exec"), ns)
    return ns


knives = load_builders("make_knives.py", "main()")
props = load_builders("make_props.py", "\nimport sys  # noqa")
COLORS = {"Common": (200, 205, 215), "Rare": (70, 160, 255), "Epic": (170, 90, 255),
          "Legendary": (255, 190, 40), "Mythic": (255, 70, 50), "Godly": (255, 95, 185),
          "Celestial": (150, 240, 255), "Cosmic": (130, 80, 255)}
CASES_ONLY = "--cases-only" in sys.argv


def cube(name, location, scale, color):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*[v / 255 for v in color], 1)
    obj.data.materials.append(mat)
    return obj


def symbol(name):
    blue, white, gold = (58, 169, 255), (238, 247, 255), (255, 198, 44)
    if name in ("Index", "Stats"):
        cube("Cover", (0, 0, 0), (2.2, .4, 2.7), blue)
        cube("Pages", (.12, -.25, .05), (1.8, .15, 2.3), white)
        for z in (-.55, 0, .55): cube("Line", (.1, -.35, z), (1.25, .1, .12), blue)
    elif name in ("More", "Upgrades"):
        for i in range(3):
            cube("Bar", (0, 0, (i - 1) * .65), (2.1 - (i * .35 if name == "Upgrades" else 0), .45, .3), blue)
    elif name in ("VIP", "Rebirth"):
        cube("Crown", (0, 0, -.4), (2.6, .5, .6), gold)
        for x in (-.9, 0, .9): cube("Point", (x, 0, .25), (.45, .5, 1.3), gold)
    elif name == "Speed":
        cube("Boot", (0, 0, .1), (.9, .7, 1.7), blue)
        cube("Toe", (.45, 0, -.65), (1.8, .8, .55), white)
    elif name in ("Health", "Fortified"):
        cube("Shield", (0, 0, 0), (1.9, .5, 2.2), (240, 74, 103))
        cube("Cross", (0, -.3, 0), (.38, .2, 1.4), white)
        cube("Cross", (0, -.3, 0), (1.3, .2, .38), white)
    else:
        root = bpy.data.objects.new("Money", None)
        bpy.context.collection.objects.link(root)
        props["build_loot_sack"](root)


def render(name, diagonal=False):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (.03, .06, .1)
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    meshes = [o for o in scene.objects if o.type == "MESH"]
    bpy.context.view_layer.update()
    points = [o.matrix_world @ Vector(v) for o in meshes for v in o.bound_box]
    mins = Vector([min(p[i] for p in points) for i in range(3)])
    maxs = Vector([max(p[i] for p in points) for i in range(3)])
    center = (mins + maxs) / 2
    cam_data = bpy.data.cameras.new("UICamera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(maxs.x - mins.x, maxs.z - mins.z, maxs.y - mins.y) * 1.4
    cam = bpy.data.objects.new("UICamera", cam_data)
    scene.collection.objects.link(cam)
    cam.location = center + Vector((3, -10, 3) if diagonal else (0, -10, 0))
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    scene.render.filepath = str(OUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)


names = []
for name, spec in knives["KNIVES"].items():
    if CASES_ONLY:
        names.append(name)
        continue
    knives["clear_scene"]()
    root, _parts = knives["build_knife"](name, spec)
    root.rotation_euler = (0, math.radians(-40), 0)
    render(name)
    names.append(name)
for rarity, color in COLORS.items():
    props["clear_scene"]()
    root = bpy.data.objects.new("Chest", None)
    bpy.context.collection.objects.link(root)
    props["build_chest"](root)
    for mat in bpy.data.materials:
        if mat.name in ("Chest_Lock", "Chest_Seam"):
            mat.diffuse_color = (*[v / 255 for v in color], 1)
    name = f"Case{rarity}"
    render(name, True)
    names.append(name)
for name in ("Index", "Stats", "More", "Upgrades", "VIP", "Rebirth", "Speed", "Health", "Fortified", "Cash"):
    if CASES_ONLY:
        names.append(name)
        continue
    props["clear_scene"]()
    symbol(name)
    render(name, True)
    names.append(name)
(OUT / "manifest.json").write_text(json.dumps({"tile": 512, "columns": 8, "names": names}, indent=2))
