"""Render original curve-authored cartoon VFX masks, not stock fire textures.

Blender --background --factory-startup --python blender/scripts/flame_flipbooks.py
Each atlas is a padded 4x4, 1024px RGBA sheet. Frames loop in reading order.
The soft version is rendered from the same editable curves with a narrow edge blur.
"""

import math
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "textures" / "aura"

# Cubic contours give broad lobes, hooked tips and real transparent negative space.
FLAME = [
    ((0, -.95), (-.75, -.95), (-1.05, -.35), (-.7, .18)),
    ((-.7, .18), (-.68, -.08), (-.38, .04), (-.31, .35)),
    ((-.31, .35), (-.18, .75), (-.61, .99), (-.05, 1.4)),
    ((-.05, 1.4), (-.27, 1.04), (.39, 1.04), (.34, .61)),
    ((.34, .61), (.32, .31), (.08, .23), (.13, -.04)),
    ((.13, -.04), (.47, .14), (.67, .5), (.51, .75)),
    ((.51, .75), (1.22, .23), (1, -.95), (0, -.95)),
]
CUTOUT = [
    ((-.24, -.6), (-.67, -.44), (-.37, .01), (-.24, .2)),
    ((-.24, .2), (-.35, -.21), (-.04, -.2), (-.24, -.6)),
]
WISP = [
    ((-.25, -1.4), (-.9, -.63), (.59, -.27), (.39, .28)),
    ((.39, .28), (.22, .65), (-.62, .88), (-.06, 1.45)),
    ((-.06, 1.45), (-.35, .89), (.76, .68), (.74, .15)),
    ((.74, .15), (.79, -.43), (-.62, -.54), (-.25, -1.4)),
]
EMBER = [
    ((0, -.55), (-.4, -.12), (-.3, .22), (.08, .62)),
    ((.08, .62), (-.02, .28), (.43, .02), (0, -.55)),
]


def contour(segments, phase, scale=1):
    vertices = []
    for a, b, c, d in segments:
        for step in range(24):
            t = step / 24
            u = 1 - t
            x = u**3*a[0] + 3*u*u*t*b[0] + 3*u*t*t*c[0] + t**3*d[0]
            y = u**3*a[1] + 3*u*u*t*b[1] + 3*u*t*t*c[1] + t**3*d[1]
            weight = max(0, min(1, (y + .95) / 2.35))
            x += .27 * math.sin(phase + y * 2.1) * weight
            y += .055 * math.sin(phase * 2 + x * 3) * weight
            vertices.append((x * scale, y * scale, 0, 1))
    return vertices


def sprite(name, contours, center, phase, material):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    for segments in contours:
        points = contour(segments, phase)
        spline = curve.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for point, coordinate in zip(spline.points, points):
            point.co = coordinate
        spline.use_cyclic_u = True
    obj = bpy.data.objects.new(name, curve)
    obj.location = (*center, 0)
    curve.materials.append(material)
    bpy.context.collection.objects.link(obj)
    return obj


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    material = bpy.data.materials.new("WhiteAlphaMask")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 1, 1, 1)
    material.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
    camera = bpy.data.cameras.new("AtlasCamera")
    camera.type = "ORTHO"
    camera.ortho_scale = 16
    obj = bpy.data.objects.new("AtlasCamera", camera)
    obj.location = (0, 0, 25)
    bpy.context.collection.objects.link(obj)
    scene.camera = obj
    scene.use_nodes = True
    compositor = scene.node_tree
    compositor.nodes.clear()
    layers = compositor.nodes.new("CompositorNodeRLayers")
    blur = compositor.nodes.new("CompositorNodeBlur")
    blur.filter_type = "GAUSS"
    blur.size_x = blur.size_y = 3
    composite = compositor.nodes.new("CompositorNodeComposite")
    compositor.links.new(layers.outputs["Image"], blur.inputs["Image"])
    for name, contours in {"Flame": [FLAME, CUTOUT], "Wisp": [WISP], "Ember": [EMBER], "FlameSoft": [FLAME, CUTOUT]}.items():
        compositor.links.new(blur.outputs["Image"] if name == "FlameSoft" else layers.outputs["Image"], composite.inputs["Image"])
        objects = []
        for frame in range(16):
            center = (-6 + frame % 4 * 4, 6 - frame // 4 * 4)
            objects.append(sprite(f"{name}_{frame:02}", contours, center, frame * math.tau / 16, material))
        scene.render.filepath = str(OUT / f"{name.lower()}_4x4.png")
        bpy.ops.render.render(write_still=True)
        for sprite_obj in objects:
            bpy.data.objects.remove(sprite_obj, do_unlink=True)
    print(f"Rendered four original cartoon flipbooks to {OUT}")


if __name__ == "__main__":
    main()
