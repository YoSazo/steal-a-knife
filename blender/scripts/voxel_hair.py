"""Make a fine, stepped version of all eight existing hair silhouettes in one FBX pack.

Run with Blender --background --factory-startup --python blender/scripts/voxel_hair.py.
Only exposed voxel faces are exported; there are no per-cube physics parts in the game.
"""
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hair

CELL = 0.085
OUT = ROOT / "blender" / "exports" / "characters"
PREVIEW = ROOT / "blender" / "previews" / "voxel_hair.png"
COLORS = {
    "HairSwoop": (0.41, 0.16, 0.12), "HairSpiky": (0.98, 0.84, 0.35),
    "HairLong": (0.78, 0.23, 0.12), "HairBob": (0.12, 0.10, 0.09),
    "HairPonytail": (0.35, 0.21, 0.12), "HairAfro": (0.16, 0.10, 0.08),
    "HairBuns": (1.0, 0.59, 0.78), "HairMessy": (0.47, 0.31, 0.18),
}


def voxel_mesh(bm):
    bm.verts.ensure_lookup_table()
    tree = BVHTree.FromBMesh(bm)
    low = [min(v.co[i] for v in bm.verts) for i in range(3)]
    high = [max(v.co[i] for v in bm.verts) for i in range(3)]
    ranges = [range(math.floor(low[i] / CELL) - 1, math.ceil(high[i] / CELL) + 1) for i in range(3)]
    occupied = set()
    for x in ranges[0]:
        for y in ranges[1]:
            for z in ranges[2]:
                point = Vector(((x + 0.5) * CELL, (y + 0.5) * CELL, (z + 0.5) * CELL))
                nearest, _, _, distance = tree.find_nearest(point)
                if nearest is not None and distance <= CELL * 0.57:
                    occupied.add((x, y, z))
    vertices, faces, indices = [], [], {}
    # Outward winding for the six exposed faces of a cell.
    sides = [
        ((-1, 0, 0), [(0, 0, 0), (0, 0, 1), (0, 1, 1), (0, 1, 0)]),
        ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
        ((0, -1, 0), [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)]),
        ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
        ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
        ((0, 0, 1), [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)]),
    ]
    for x, y, z in sorted(occupied):
        for step, corners in sides:
            if (x + step[0], y + step[1], z + step[2]) in occupied:
                continue
            face = []
            for dx, dy, dz in corners:
                key = (x + dx, y + dy, z + dz)
                if key not in indices:
                    indices[key] = len(vertices)
                    vertices.append(tuple(value * CELL for value in key))
                face.append(indices[key])
            faces.append(face)
    return vertices, faces, len(occupied)


def material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    return mat


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    pack = bpy.data.objects.new("VoxelHairPack", None)
    bpy.context.collection.objects.link(pack)
    stats, objects = {}, []
    for name, build in hair.STYLES.items():
        source = bmesh.new()
        build(source)
        verts, faces, cells = voxel_mesh(source)
        assert len(faces) * 2 <= 12000, f"{name} exceeds the hair mesh budget"
        source.free()
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts, [], faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.parent = pack
        obj.data.materials.append(material(name + "Color", COLORS[name]))
        objects.append(obj)
        # FBX imports this part's geometry centered; the manifest keeps its pivot offset.
        min_xyz = [min(v[i] for v in verts) for i in range(3)]
        max_xyz = [max(v[i] for v in verts) for i in range(3)]
        stats[name] = {"cells": cells, "triangles": len(faces) * 2,
                       "center": [(a + b) / 2 for a, b in zip(min_xyz, max_xyz)],
                       "size": [b - a for a, b in zip(min_xyz, max_xyz)]}
    bpy.ops.object.select_all(action="DESELECT")
    pack.select_set(True)
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(OUT / "VoxelHairPack.fbx"), use_selection=True,
                             object_types={"EMPTY", "MESH"}, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
    (OUT / "voxel_hair_manifest.json").write_text(json.dumps(stats, indent=2))
    # Preview each style on a neutral head, with the front hairline clearly visible.
    for index, obj in enumerate(objects):
        position = Vector(((index % 4) * 2.9, 0, -(index // 4) * 3.0))
        obj.location = position
        bpy.ops.mesh.primitive_cube_add(size=1, location=position)
        head = bpy.context.object
        head.dimensions = (1.16, 1.16, 1.18)
        head.data.materials.append(material("Skin", (0.83, 0.60, 0.43)))
        bevel = head.modifiers.new("HeadCorners", "BEVEL")
        bevel.width = 0.08
        bevel.segments = 1
    camera_data = bpy.data.cameras.new("Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 12.5
    camera = bpy.data.objects.new("Camera", camera_data)
    bpy.context.collection.objects.link(camera)
    target = Vector((4.35, 0, -1.15))
    camera.location = target + Vector((1.2, -20, 5))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.16, 0.18, 0.21)
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    print(json.dumps(stats))


main()
