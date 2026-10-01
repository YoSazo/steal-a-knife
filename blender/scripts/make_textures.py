"""Render the game's custom textures with Blender (transparent PNGs, uploaded as decals).

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/make_textures.py

  knife_trail.png   speed trail: a row of flying knife silhouettes with motion streaks
                    (white, so the Trail's Color tints it per speed tier)
  slash.png         a crescent slash arc for swing effects
"""

import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "textures"


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def emission(name, strength=1.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    em = nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    em.inputs["Strength"].default_value = strength
    if alpha < 1:
        mix = nodes.new("ShaderNodeMixShader")
        tr = nodes.new("ShaderNodeBsdfTransparent")
        mix.inputs["Fac"].default_value = alpha
        mat.node_tree.links.new(tr.outputs[0], mix.inputs[1])
        mat.node_tree.links.new(em.outputs[0], mix.inputs[2])
        mat.node_tree.links.new(mix.outputs[0], out.inputs["Surface"])
        mat.blend_method = "BLEND"
    else:
        mat.node_tree.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def flat_object(name, verts2d, faces, mat, z=0.0):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(x, y, z) for x, y in verts2d], [], faces)
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    return obj


def knife_silhouette(cx, cy, length, angle, mat, name):
    """A simple knife: blade (pointed) + guard + handle, as flat polygons, pointing along +X."""
    L = length
    blade = [(0.0, -0.09), (L * 0.62, -0.1), (L * 0.78, -0.02), (L * 0.62, 0.1), (0.0, 0.11)]
    guard = [(-0.03, -0.2), (0.05, -0.2), (0.05, 0.2), (-0.03, 0.2)]
    handle = [(-0.38 * L / 1.6, -0.06), (-0.03, -0.07), (-0.03, 0.07), (-0.38 * L / 1.6, 0.06)]
    parts = []
    for i, poly in enumerate((blade, guard, handle)):
        rot = Matrix.Rotation(angle, 2)
        pts = [tuple(rot @ Vector(p) + Vector((cx, cy))) for p in poly]
        parts.append(flat_object(f"{name}_{i}", pts, [list(range(len(pts)))], mat))
    return parts


def streak(x0, x1, y, width, mat, name):
    # tapered streak: thin at the back
    pts = [(x0, y - width * 0.15), (x1, y - width / 2), (x1, y + width / 2), (x0, y + width * 0.15)]
    return flat_object(name, pts, [[0, 1, 2, 3]], mat, z=-0.01)


def render(path, width_px, height_px, ortho_scale, center):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x = width_px
    scene.render.resolution_y = height_px
    scene.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (center[0], center[1], 10)
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def knife_trail():
    clear()
    solid = emission("Solid", 1.0)
    faint = emission("Faint", 1.0, alpha=0.45)
    # 4 knives flying left->right across a 8 x 2 strip, alternating tilt, with streaks behind
    for i in range(4):
        x = 0.9 + i * 2.0
        y = 0.25 if i % 2 == 0 else -0.25
        knife_silhouette(x, y, 1.15, math.radians(8 if i % 2 == 0 else -8), solid, f"k{i}")
        streak(x - 1.5, x - 0.45, y, 0.18, faint, f"s{i}")
    render(OUT / "knife_trail.png", 1024, 256, 8.0, (4.0, 0.0))


def slash():
    clear()
    mat = emission("Slash", 1.0)
    # crescent: outer arc minus inner arc
    pts = []
    segs = 24
    for i in range(segs + 1):
        a = math.radians(-70 + 140 * i / segs)
        pts.append((math.cos(a) * 1.0, math.sin(a) * 1.0))
    for i in range(segs, -1, -1):
        a = math.radians(-70 + 140 * i / segs)
        t = 1 - abs(i / segs - 0.5) * 2  # thickest in the middle
        r = 1.0 - 0.28 * t
        pts.append((math.cos(a) * r + 0.06 * t, math.sin(a) * r))
    flat_object("slash", pts, [list(range(len(pts)))], mat)
    render(OUT / "slash.png", 512, 512, 2.4, (0.4, 0.0))


OUT.mkdir(parents=True, exist_ok=True)
knife_trail()
slash()
