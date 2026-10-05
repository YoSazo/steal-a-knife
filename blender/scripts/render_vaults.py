"""Render/export the exact transforms emitted by tools/export_vaults.studio.luau."""
import json
import re
import copy
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/vaults"
data = json.loads((OUT / "geometry.json").read_text(encoding="utf-8"))
assert len(data["Scenes"]) == 11
assert all(len(s["Parts"]) > 300 for s in data["Scenes"][:8]), "Incomplete Studio geometry export"
# Closeups are cut from the exact exported floor-one geometry, including each
# upgrade's current corner hardware. No separately approximated preview models.
for tier_scene in data["Scenes"][:8]:
    parts = []
    for part in tier_scene["Parts"]:
        x, y, z = part["CFrame"][:3]
        if part["Group"] == "PlateDetails1" or (part["Group"] == "PlateTierHardware" and abs(x+12) < 3.6 and abs(z+17) < 3.6 and y < 2):
            local = copy.deepcopy(part)
            local["CFrame"][0] += 12
            local["CFrame"][1] -= .6
            local["CFrame"][2] += 17
            parts.append(local)
    data["Scenes"].append({"Name": "Plate " + tier_scene["Name"], "Height": .6, "Parts": parts})
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
cube = bpy.data.meshes.new("UnitBlock")
cube.from_pydata([(x,y,z) for x in [-.5,.5] for y in [-.5,.5] for z in [-.5,.5]], [],
                [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])
basis = Matrix(((1,0,0),(0,0,-1),(0,1,0)))
materials, meshes = {}, {}
collections = []

def linear(s):
    return s/12.92 if s <= .04045 else ((s+.055)/1.055)**2.4

for index, scene_spec in enumerate(data["Scenes"]):
    coll = bpy.data.collections.new(f"{index+1:02d} {scene_spec['Name']}")
    bpy.context.scene.collection.children.link(coll)
    collections.append(coll)
    for spec in scene_spec["Parts"]:
        color = tuple(round(v,6) for v in spec["Color"])
        key = color + (spec["Neon"],)
        if key not in materials:
            mat = bpy.data.materials.new(f"Vault finish {len(materials)+1}")
            mat.diffuse_color = tuple(linear(v) for v in color)+(1,)
            mat.use_nodes = True
            shader = mat.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Base Color"].default_value = mat.diffuse_color
            shader.inputs["Roughness"].default_value = .65
            if spec["Neon"]:
                shader.inputs["Emission Color"].default_value = mat.diffuse_color
                shader.inputs["Emission Strength"].default_value = .4
            mesh = cube.copy()
            mesh.materials.append(mat)
            materials[key], meshes[key] = mat, mesh
        obj = bpy.data.objects.new(spec["Name"], meshes[key])
        coll.objects.link(obj)
        cf = spec["CFrame"]
        rotation = Matrix((cf[3:6], cf[6:9], cf[9:12]))
        obj.rotation_euler = (basis @ rotation @ basis.transposed()).to_euler()
        obj.location = basis @ Vector(cf[:3])
        sx,sy,sz = spec["Size"]
        obj.scale = (sx,sz,sy)
        obj["VaultGroup"] = spec["Group"]
        obj["RobloxMaterial"] = "Neon" if spec["Neon"] else "SmoothPlastic"
    bpy.ops.object.select_all(action="DESELECT")
    for obj in coll.objects:
        obj.select_set(True)
    (OUT / "models").mkdir(exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", scene_spec["Name"].lower()).strip("-")
    bpy.ops.export_scene.gltf(filepath=str(OUT / "models" / f"{index+1:02d}-{slug}.glb"), use_selection=True)
    bpy.ops.object.select_all(action="DESELECT")

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 1024
scene.render.resolution_y = 768
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value = (.8,.8,.8,1)
scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value = .75
bpy.ops.mesh.primitive_plane_add(size=1000, location=(0,0,-.56))
ground = bpy.context.object
ground.name = "Preview backdrop"
mat = bpy.data.materials.new("Preview gray")
mat.diffuse_color = (.84,.85,.87,1)
ground.data.materials.append(mat)
bpy.ops.object.camera_add()
cam = bpy.context.object
cam.data.type = "ORTHO"
scene.camera = cam
for pos, energy, size in [((20,-55,100),12000,45),((-60,-10,75),10000,40),((5,60,100),14000,40)]:
    bpy.ops.object.light_add(type="AREA", location=pos)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0,0,30))-light.location).to_track_quat('-Z','Y').to_euler()
for coll in collections:
    coll.hide_render = True
    coll.hide_viewport = True
for i in sorted(range(len(collections)), key=lambda index: index < 10):
    spec, coll = data["Scenes"][i], collections[i]
    height = spec["Height"]
    if i >= 10:
        cam.location = (8,-10,14)
        target = Vector((0,0,.15))
        cam.data.ortho_scale = 10.7
    else:
        cam.location = (57,-98,height*.58+32)
        target = Vector((0,0,height/2))
        cam.data.ortho_scale = max(75,height*1.9)
    cam.rotation_euler = (target-cam.location).to_track_quat('-Z','Y').to_euler()
    coll.hide_render = False
    scene.render.filepath = str(OUT / f"{i+1:02d}-preview.png")
    bpy.ops.render.render(write_still=True)
    coll.hide_render = True
collections[1].hide_viewport = False
collections[1].hide_render = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "vault-upgrades.blend"))
