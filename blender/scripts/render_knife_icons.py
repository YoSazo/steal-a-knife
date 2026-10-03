"""Render a hotbar icon for every knife (MM2 style: the knife on its own, diagonal, no background).

  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/render_knife_icons.py

Reuses make_knives.py's builders (without running its export), renders each knife alone with a
transparent background to blender/textures/knife_icons/<Name>.png (256x256), then they're uploaded
and their ids go in src/shared/Config/KnifeIcons.luau (Tool.TextureId).
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "blender" / "scripts"))
import detail_knives
OUT = ROOT / "blender" / "textures" / "knife_icons"

# Load make_knives' builders without running its main()
source = (ROOT / "blender" / "scripts" / "make_knives.py").read_text(encoding="utf-8")
source = source[: source.rindex("main()")]
namespace = {"__file__": str(ROOT / "blender" / "scripts" / "make_knives.py")}
exec(compile(source, "make_knives.py", "exec"), namespace)
KNIVES = namespace["KNIVES"]
build_knife = namespace["build_knife"]
clear_scene = namespace["clear_scene"]


def setup_render():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0.05, 0.05, 0.07)
    scene.render.resolution_x = scene.render.resolution_y = 256
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"


def frame_camera(objects):
    # The knife's bounds in world space
    mins = Vector((1e9, 1e9, 1e9))
    maxs = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        for corner in obj.bound_box:
            p = obj.matrix_world @ Vector(corner)
            mins = Vector(map(min, mins, p))
            maxs = Vector(map(max, maxs, p))
    center = (mins + maxs) / 2
    size = max(maxs.x - mins.x, maxs.z - mins.z)
    cam_data = bpy.data.cameras.new("IconCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size * 1.12
    cam = bpy.data.objects.new("IconCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (center.x, center.y - 10, center.z)
    cam.rotation_euler = (math.radians(90), 0, 0)
    bpy.context.scene.camera = cam


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    setup_render()
    for name, spec in KNIVES.items():
        spec = detail_knives.silhouette_spec(name)
        clear_scene()
        root, parts = build_knife(name, spec)
        parts += detail_knives.build_details(name, spec, root)
        detail_knives.restyle(name, parts)
        # Diagonal, blade up and to the right (like a hotbar icon)
        root.rotation_euler = (0, math.radians(-40), 0)
        bpy.context.view_layer.update()
        frame_camera(parts)
        bpy.context.scene.render.filepath = str(OUT / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print("icon", name)


main()
