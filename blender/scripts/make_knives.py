"""Procedurally build the Steal a Knife knife lineup and export one FBX per knife.

Run headless:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --factory-startup \
      --python blender/scripts/make_knives.py

Each knife is exported as separate meshes (Blade, Guard, Handle, Pommel) so every
part becomes its own MeshPart in Roblox and can be colored/materialed there.
Origin sits at the grip so it works directly as a Tool Handle.
Low poly on purpose (a few hundred tris) - Roblox likes that.
"""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
EXPORT_DIR = ROOT / "blender" / "exports"
PREVIEW_DIR = ROOT / "blender" / "previews"

# name: blade length, blade height, guard width, colors (blade, guard, handle), rarity
KNIVES = {
    "RustyShank":   dict(length=1.2, height=0.28, guard=0.18, curve=0.3, rarity="Common",
                         colors=((0.45, 0.30, 0.20), (0.30, 0.25, 0.22), (0.35, 0.22, 0.12))),
    "KitchenKnife": dict(length=1.5, height=0.38, guard=0.10, curve=0.5, rarity="Common",
                         colors=((0.80, 0.82, 0.85), (0.15, 0.15, 0.15), (0.12, 0.12, 0.12))),
    "HunterBlade":  dict(length=1.7, height=0.34, guard=0.30, curve=0.7, rarity="Rare",
                         colors=((0.70, 0.74, 0.78), (0.55, 0.40, 0.18), (0.38, 0.20, 0.08))),
    "Cleaver":      dict(length=1.4, height=0.70, guard=0.08, curve=0.15, rarity="Epic",
                         colors=((0.60, 0.62, 0.66), (0.20, 0.20, 0.22), (0.50, 0.10, 0.10))),
    "GoldenDagger": dict(length=1.9, height=0.30, guard=0.42, curve=1.0, rarity="Legendary",
                         colors=((1.00, 0.78, 0.20), (0.85, 0.10, 0.10), (0.10, 0.05, 0.02))),
    "VoidEdge":     dict(length=2.2, height=0.36, guard=0.50, curve=1.2, rarity="Godly",
                         colors=((0.45, 0.10, 0.90), (0.05, 0.05, 0.08), (0.20, 0.00, 0.35))),
}


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            block.remove(item)


def material(name, rgb, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
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


def build_blade(length, height, curve, thickness=0.045, stations=12):
    """Triangular cross-section blade: thick spine on top, sharp edge on bottom, along +X."""
    bm = bmesh.new()
    rows = []
    for i in range(stations):
        s = i / stations
        x = length * s
        top = height if s < 0.7 else height - (s - 0.7) / 0.3 * height * 0.45
        bot = 0.0 if s < 0.55 else ((s - 0.55) / 0.45) ** (1.0 + curve) * height * 0.55
        t = thickness * (1 - 0.6 * s * s)
        rows.append((
            bm.verts.new((x, -t, top)),   # spine left
            bm.verts.new((x, t, top)),    # spine right
            bm.verts.new((x, 0.0, bot)),  # edge
        ))
    tip = bm.verts.new((length, 0.0, height * 0.55))
    for a, b in zip(rows, rows[1:]):
        bm.faces.new((a[0], b[0], b[2], a[2]))  # left flat
        bm.faces.new((a[2], b[2], b[1], a[1]))  # right flat
        bm.faces.new((a[1], b[1], b[0], a[0]))  # spine
    last = rows[-1]
    bm.faces.new((last[0], tip, last[2]))
    bm.faces.new((last[2], tip, last[1]))
    bm.faces.new((last[1], tip, last[0]))
    bm.faces.new((rows[0][0], rows[0][2], rows[0][1]))  # base cap
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def build_box(size, center):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(size) * 0.2, segments=1, affect="EDGES")
    return bm


def build_handle(length, radius, x_start, z):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=radius, radius2=radius * 0.85, depth=length)
    # cone is built along Z; lay it along -X
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0),
                     matrix=__import__("mathutils").Matrix.Rotation(math.radians(-90), 3, "Y"))
    bmesh.ops.translate(bm, vec=Vector((x_start - length / 2, 0, z)), verts=bm.verts)
    return bm


def build_pommel(radius, center):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=radius)
    bmesh.ops.translate(bm, vec=Vector(center), verts=bm.verts)
    return bm


def build_knife(name, spec):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    blade_rgb, guard_rgb, handle_rgb = spec["colors"]
    h = spec["height"]
    handle_len = 0.75
    grip_z = h * 0.5

    blade = mesh_object("Blade", build_blade(spec["length"], h, spec["curve"]),
                        material(f"{name}_Blade", blade_rgb, metallic=1.0, roughness=0.25), root)
    guard = mesh_object("Guard", build_box((0.10, spec["guard"] * 2 + 0.12, h * 1.25), (-0.05, 0, grip_z)),
                        material(f"{name}_Guard", guard_rgb, metallic=0.6), root)
    handle = mesh_object("Handle", build_handle(handle_len, 0.075, -0.10, grip_z),
                         material(f"{name}_Handle", handle_rgb, roughness=0.8), root)
    pommel = mesh_object("Pommel", build_pommel(0.1, (-0.10 - handle_len - 0.05, 0, grip_z)),
                         material(f"{name}_Pommel", guard_rgb, metallic=0.6), root)

    # Put the origin in the middle of the grip so the whole thing works as a Tool handle
    offset = Vector((0.10 + handle_len / 2, 0, -grip_z))
    for obj in (blade, guard, handle, pommel):
        obj.data.transform(__import__("mathutils").Matrix.Translation(offset))
    return root, (blade, guard, handle, pommel)


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


def render_lineup(path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x, scene.render.resolution_y = 1000, 1300
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W") if not scene.world else scene.world
    scene.world = world
    world.color = (0.08, 0.08, 0.1)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 6.6
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.3, -10, -2.35)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main():
    EXPORT_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    clear_scene()
    manifest = {}
    for row, (name, spec) in enumerate(KNIVES.items()):
        root, parts = build_knife(name, spec)
        path = EXPORT_DIR / f"{name}.fbx"
        export_fbx(root, parts, path)
        root.location = (0, 0, -row * 1.0)  # stack them for the preview render
        manifest[name] = {
            "rarity": spec["rarity"],
            "fbx": f"blender/exports/{name}.fbx",
            "colors": {"Blade": spec["colors"][0], "Guard": spec["colors"][1],
                       "Handle": spec["colors"][2], "Pommel": spec["colors"][1]},
        }
        print(f"exported {path}")
    (ROOT / "blender" / "knives.json").write_text(json.dumps(manifest, indent=2))
    render_lineup(PREVIEW_DIR / "lineup.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "blender" / "knives.blend"))


main()
