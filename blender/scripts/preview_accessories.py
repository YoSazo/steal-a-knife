"""Render every disguise accessory on a stand-in head (3/4 view) to check the fit:
  blender -b --factory-startup --python blender/scripts/preview_accessories.py"""

import math
import sys
from pathlib import Path

import bmesh
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
ROOT = Path(__file__).resolve().parents[2]

# Reuse the builders without running make_props' main()
src = (Path(__file__).resolve().parent / "make_props.py").read_text()
src = src.replace("\nmain()\n", "\n")
ns = {"__file__": str(Path(__file__).resolve().parent / "make_props.py"), "__name__": "props"}
exec(compile(src, "make_props.py", "exec"), ns)
ns["clear_scene"]()
import accessories  # noqa: E402

skin = ns["material"]("Skin", ns["rgb"](245, 205, 140))
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
items = [(n, b) for n, b in accessories.ACCESSORIES.items() if not ONLY or n in ONLY]
for i, (name, build) in enumerate(items):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    build(root)
    if name == "AngelWings":  # worn on the torso, not the head
        for child in root.children:
            child.location.z -= 1.45
    head = bmesh.new()
    accessories.hair.cap(head, thickness=0.0, edge=0.0, line=lambda t: -0.62, top_puff=0.0)
    face_ink = bmesh.new()
    for x in (-0.2, 0.2):
        ns["add_box"](face_ink, (0.09, 0.02, 0.16), (x, -0.585, 0.2))
        ns["add_box"](face_ink, (0.2, 0.02, 0.04), (x, -0.585, 0.34))
    ns["add_box"](face_ink, (0.3, 0.02, 0.04), (0, -0.585, -0.12))
    ns["mesh_object"]("Face", face_ink, ns["material"]("Ink", (0.05, 0.05, 0.05)), root)
    torso = bmesh.new()
    ns["add_box"](torso, (1.95, 1.0, 1.7), (0, 0, -1.45))
    ns["mesh_object"]("Head", head, skin, root)
    ns["mesh_object"]("Torso", torso, ns["material"]("Shirt", (0.3, 0.3, 0.35)), root)
    root.location = ((i % 6) * 3.0, (i // 6) * 3.0, 0)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 1600
scene.render.resolution_y = 800
world = bpy.data.worlds.new("W")
world.color = (0.05, 0.04, 0.07)
scene.world = world
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 19
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = (7.5 - 14, 1.5 - 18, 9)
cam.rotation_euler = (math.radians(65), 0, math.radians(-38))
scene.camera = cam
scene.render.filepath = str(ROOT / "blender" / "previews" / "accessories.png")
bpy.ops.render.render(write_still=True)
