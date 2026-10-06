"""Render the round skull coin (make_props.py build_coin - the same model that drops in rounds) as a
2D icon: 512x512, transparent, facing the camera with a slight tilt. Output:
blender/textures/icons/CoinIcon.png. Then upload it (Studio MCP upload_image) and put the id in
src/shared/Config/CoinIcon.luau.

  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \\
      --python blender/scripts/render_coin_icon.py
"""

import math
import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "blender" / "textures" / "icons" / "CoinIcon.png"

# Reuse make_props.py's builders without running its export (its last line is "main()")
sys.path.insert(0, str(HERE))
source = (HERE / "make_props.py").read_text(encoding="utf-8")
source = source[: source.rstrip().rfind("main()")]
namespace = {"__file__": str(HERE / "make_props.py"), "__name__": "make_props_lib"}
exec(compile(source, str(HERE / "make_props.py"), "exec"), namespace)

namespace["clear_scene"]()
root = bpy.data.objects.new("Coin", None)
bpy.context.collection.objects.link(root)
namespace["build_coin"](root)
# A slight 3/4 turn and tilt so it reads as a chunky coin, not a flat disc
root.rotation_euler = (math.radians(6), 0, math.radians(-16))


# Readable at 20 px: dark sockets, a deeper gold coin and a paler skull
for mat_name, rgb_ in (("Coin_Eyes", (0.02, 0.012, 0.004)), ("Coin_Gold", (0.85, 0.42, 0.02)), ("Coin_Rim", (0.7, 0.3, 0.01)), ("Coin_Emblem", (1.0, 0.92, 0.6))):
    mat = bpy.data.materials.get(mat_name)
    if mat:
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (*rgb_, 1)
        bsdf.inputs["Metallic"].default_value = 0.3

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [
    e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items
] else "BLENDER_EEVEE"
scene.render.resolution_x = scene.render.resolution_y = 512
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

# Camera straight at the coin's face (the coin faces -Y)
cam_data = bpy.data.cameras.new("Cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.75
cam = bpy.data.objects.new("Cam", cam_data)
cam.location = (0, -8, 0)
cam.rotation_euler = (math.radians(90), 0, 0)
bpy.context.collection.objects.link(cam)
scene.camera = cam

# Soft key + fill + a little world light so the gold reads bright and toy-like
for name, energy, loc in (("Key", 900, (-3, -5, 4)), ("Fill", 350, (4, -4, -1)), ("Rim", 500, (0, 4, 3))):
    light_data = bpy.data.lights.new(name, "AREA")
    light_data.energy = energy
    light_data.size = 4
    light = bpy.data.objects.new(name, light_data)
    light.location = loc
    direction = -light.location
    light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(light)
world = bpy.data.worlds.new("World")
world.use_nodes = True
background = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
background.inputs[0].default_value = (1, 1, 1, 1)
background.inputs[1].default_value = 0.25
scene.world = world

OUT.parent.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(OUT)
bpy.ops.render.render(write_still=True)
print(f"wrote {OUT}")
