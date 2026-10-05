"""Render the actual 24 knife and seven Lucky Block models as transparent UI art."""
import json, math, sys
from pathlib import Path
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/voxel-ui"
catalog = json.loads((OUT / "catalog.json").read_text())["Assets"]
designs = {d["Name"]: d for d in json.loads((ROOT / "assets/toy-redesign/geometry.json").read_text())["Designs"]}
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "FLAT"
scene.display.shading.studiolight_rotate_z = math.radians(25)
scene.display.shading.color_type = "MATERIAL"
scene.display.shading.show_shadows = False
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "BOTH"
scene.display.shading.curvature_ridge_factor = 1.15
scene.display.shading.curvature_valley_factor = 1.35
scene.display.shading.show_object_outline = True
scene.display.shading.object_outline_color = (.025,.03,.055)
scene.render.resolution_x = scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Raw"
basis = Matrix(((1,0,0),(0,0,-1),(0,1,0)))
cube = bpy.data.meshes.new("Voxel UI unit block")
cube.from_pydata([(x,y,z) for x in (-.5,.5) for y in (-.5,.5) for z in (-.5,.5)], [],
 [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])
cube.update()
materials = {}
light_direction = Vector((-.45,.65,1)).normalized()
bpy.ops.object.camera_add()
cam = bpy.context.object
cam.data.type = "ORTHO"
scene.camera = cam

for entry in catalog:
    if not entry["Model"]:
        continue
    if "--partial" in sys.argv and not (OUT / entry["Reference"]).is_file():
        continue
    assert (OUT / entry["Reference"]).is_file(), f"Generate reference first: {entry['Id']}"
    objects = []
    tilt = Matrix.Rotation(math.radians(-28), 3, "Y") if entry["Group"] == "Knives" else Matrix.Identity(3)
    for row in designs[entry["Model"]]["Parts"]:
        rotation = tilt @ basis @ Matrix.Rotation(math.radians(row["Angle"]),3,"Z") @ basis.transposed()
        mesh = cube.copy()
        # Flat toy faces with a controlled top-left highlight: preserve saturation
        # and the actual cuboid geometry without glossy studio-light reflections.
        for polygon in mesh.polygons:
            dot = (rotation @ polygon.normal).dot(light_direction)
            values = []
            for value in row["Color"]:
                bright = min(255,value*1.10)
                color = bright*(.82 if dot<=0 else 1-.08*dot) + (0 if dot<=0 else 255*.08*dot)
                values.append(round(color))
            key = tuple(values)
            if key not in materials:
                mat = bpy.data.materials.new(str(key))
                mat.diffuse_color = tuple(v/255 for v in key)+(1,)
                materials[key] = mat
            mesh.materials.append(materials[key])
            polygon.material_index = len(mesh.materials)-1
        obj = bpy.data.objects.new(row["Name"], mesh)
        scene.collection.objects.link(obj)
        obj.location = tilt @ basis @ Vector(row["Offset"])
        obj.rotation_euler = rotation.to_euler()
        sx,sy,sz = row["Size"]
        obj.scale = (sx,sz,sy)
        objects.append(obj)
    bpy.context.view_layer.update()
    points = [obj.matrix_world @ Vector(v) for obj in objects for v in obj.bound_box]
    lo = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (lo+hi)/2
    direction = Vector((.40,1,.20)) if entry["Group"] == "Knives" else Vector((.72,1,.65))
    cam.location = center + direction.normalized()*100
    cam.rotation_euler = (center-cam.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.view_layer.update()
    inverse = cam.matrix_world.inverted()
    projected = [inverse @ p for p in points]
    width = max(p.x for p in projected)-min(p.x for p in projected)
    height = max(p.y for p in projected)-min(p.y for p in projected)
    px = (max(p.x for p in projected)+min(p.x for p in projected))/2
    py = (max(p.y for p in projected)+min(p.y for p in projected))/2
    cam.location += cam.matrix_world.to_quaternion() @ Vector((px,py,0))
    cam.data.ortho_scale = max(width,height)/.72
    dest = OUT / "renders" / entry["Group"] / (entry["Name"]+".png")
    dest.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(dest)
    bpy.ops.render.render(write_still=True)
    for obj in objects:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.meshes.remove(mesh)
    print("Rendered actual model", entry["Id"], flush=True)
