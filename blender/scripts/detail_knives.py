"""Fine, square-built knife details, batched into three meshes per knife.

All skins use one dagger silhouette and grip origin. Details are flat relief,
so skin changes never add horns, wings or otherwise change the outline.
The same finish manifest drives Roblox materials and previews.
Run with Blender --background --python blender/scripts/detail_knives.py.
"""
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "exports"
PREVIEW = ROOT / "blender" / "previews" / "knife_details.png"
source_path = ROOT / "blender" / "scripts" / "make_knives.py"
source = source_path.read_text(encoding="utf-8")
namespace = {"__file__": str(source_path)}
exec(compile(source[:source.rindex("main()")], str(source_path), "exec"), namespace)
KNIVES = namespace["KNIVES"]
box = namespace["box"]

# Blade / guard / grip / ornament / cutting edge / inlay / grip detail.
# Dark bodies let the luminous details read without flattening the silhouette.
PALETTES = {
    "RustyShank": [(137, 84, 51), (92, 83, 75), (88, 55, 35), (107, 93, 79), (193, 181, 159), (68, 45, 31), (155, 118, 77)],
    "KitchenKnife": [(163, 178, 189), (190, 205, 211), (29, 34, 39), (225, 218, 186), (235, 241, 243), (87, 108, 120), (71, 81, 88)],
    "PocketKnife": [(168, 183, 194), (121, 25, 35), (200, 44, 55), (215, 222, 224), (229, 241, 246), (86, 106, 118), (111, 24, 37)],
    "HunterBlade": [(142, 167, 175), (193, 150, 71), (94, 60, 34), (206, 180, 110), (228, 237, 226), (65, 98, 91), (185, 137, 72)],
    "Switchblade": [(76, 137, 176), (37, 61, 90), (31, 80, 135), (217, 235, 244), (199, 241, 251), (36, 71, 92), (88, 163, 204)],
    "ThornDagger": [(61, 121, 78), (93, 153, 75), (69, 49, 30), (155, 205, 105), (198, 234, 176), (144, 197, 91), (113, 140, 62)],
    "Cleaver": [(139, 156, 169), (64, 66, 75), (133, 35, 43), (45, 53, 62), (224, 231, 235), (71, 85, 99), (212, 170, 99)],
    "Machete": [(104, 83, 144), (67, 49, 93), (50, 114, 70), (140, 177, 113), (216, 197, 244), (60, 43, 87), (173, 188, 94)],
    "BoneCarver": [(200, 190, 157), (107, 91, 69), (64, 52, 44), (235, 221, 176), (246, 235, 199), (103, 90, 62), (162, 135, 89)],
    "GoldenDagger": [(212, 161, 47), (245, 197, 76), (84, 26, 36), (201, 47, 73), (255, 230, 132), (120, 62, 29), (238, 188, 79)],
    "Katana": [(178, 112, 146), (218, 174, 65), (43, 24, 49), (239, 204, 109), (255, 216, 232), (239, 169, 204), (172, 84, 124)],
    "Reaper": [(45, 52, 59), (159, 135, 71), (28, 24, 34), (231, 216, 165), (153, 191, 159), (116, 164, 121), (131, 115, 71)],
    "InfernoFang": [(124, 46, 31), (44, 32, 30), (84, 27, 29), (255, 173, 45), (255, 101, 35), (255, 210, 83), (165, 75, 45)],
    "MagmaCleaver": [(61, 46, 48), (102, 62, 40), (33, 28, 30), (255, 140, 32), (243, 90, 25), (255, 201, 62), (156, 93, 47)],
    "DemonHorn": [(105, 31, 44), (45, 25, 34), (50, 16, 26), (165, 69, 81), (237, 64, 82), (255, 125, 111), (116, 61, 72)],
    "ZeusBolt": [(80, 128, 170), (213, 195, 116), (43, 72, 121), (255, 228, 90), (255, 238, 141), (155, 231, 255), (208, 175, 78)],
    "AthenaBlade": [(167, 189, 196), (218, 180, 80), (43, 79, 117), (245, 208, 108), (226, 244, 245), (113, 214, 197), (191, 168, 95)],
    "OlympusEdge": [(174, 101, 145), (225, 186, 84), (228, 222, 209), (255, 164, 214), (252, 207, 230), (255, 224, 123), (122, 94, 128)],
    "HaloBlade": [(176, 192, 197), (234, 198, 103), (217, 224, 231), (255, 231, 132), (247, 253, 236), (255, 225, 132), (114, 139, 164)],
    "SeraphSword": [(102, 161, 184), (226, 191, 105), (221, 232, 238), (245, 235, 198), (199, 244, 255), (235, 250, 255), (118, 162, 181)],
    "AngelFeather": [(208, 222, 226), (133, 191, 206), (194, 158, 84), (161, 220, 239), (247, 251, 253), (115, 176, 198), (243, 220, 154)],
    "VoidEdge": [(43, 32, 69), (69, 50, 99), (37, 22, 58), (180, 106, 255), (154, 92, 242), (211, 169, 255), (117, 69, 147)],
    "StarCleaver": [(31, 71, 94), (58, 43, 79), (185, 151, 69), (255, 232, 150), (114, 227, 249), (153, 217, 243), (65, 93, 122)],
    "GalaxyKatana": [(73, 37, 104), (99, 190, 210), (31, 22, 54), (135, 230, 255), (248, 133, 222), (189, 158, 255), (140, 89, 164)],
}
SYMBOLS = {
    "RustyShank": ["10010", "00100", "01001", "10000"],
    "KitchenKnife": ["11100", "10100", "11111", "00101", "00111"],
    "PocketKnife": ["01110", "11011", "10001", "11011", "01110"],
    "HunterBlade": ["00100", "01110", "11111", "00100", "00100"],
    "Switchblade": ["10101", "10101", "11111", "00100", "00100"],
    "ThornDagger": ["00100", "10101", "01110", "10101", "00100"],
    "Cleaver": ["00100", "00100", "11111", "00100", "00100"],
    "Machete": ["10001", "01010", "00100", "01010", "10001"],
    "BoneCarver": ["11011", "11111", "01110", "00100", "01110"],
    "GoldenDagger": ["00100", "10101", "01110", "11111", "01110", "10101", "00100"],
    "Katana": ["01010", "11111", "01110", "11111", "01010"],
    "Reaper": ["01110", "11111", "10101", "11111", "01110", "01010"],
    "InfernoFang": ["00100", "00110", "01110", "11011", "11111", "01110"],
    "MagmaCleaver": ["10000", "01001", "00110", "01100", "10010", "10001"],
    "DemonHorn": ["10001", "11011", "01110", "10101", "01110"],
    "ZeusBolt": ["00111", "00110", "01100", "11111", "00110", "01100", "01000"],
    "AthenaBlade": ["10001", "11111", "10101", "11111", "01110", "00100"],
    "OlympusEdge": ["00100", "01110", "11111", "00100", "10101", "01110"],
    "HaloBlade": ["01110", "10001", "10101", "10001", "01110"],
    "SeraphSword": ["10001", "11011", "11111", "01110", "00100"],
    "AngelFeather": ["00100", "10100", "01101", "00110", "10100", "01100"],
    "VoidEdge": ["11001", "01110", "10101", "01110", "10011"],
    "StarCleaver": ["00100", "10101", "01110", "11111", "01010"],
    "GalaxyKatana": ["01110", "10001", "10101", "10001", "01110"],
}
ROLES = ["Blade", "Guard", "Grip", "Extra", "CuttingEdge", "Inlay", "GripDetail"]
ORGANIC = {"BoneCarver", "DemonHorn", "AngelFeather"}
FABRIC = {"RustyShank", "Machete", "ThornDagger", "Katana", "Reaper", "GalaxyKatana", "SeraphSword", "HaloBlade"}


def silhouette_spec(name):
    return {**KNIVES["GoldenDagger"], "extras": [], "colors": KNIVES[name]["colors"], "rarity": KNIVES[name]["rarity"]}


def finish(name):
    spec = KNIVES[name]
    high = spec["rarity"] == "Godly"
    styles = {}
    for role, rgb in zip(ROLES, PALETTES[name]):
        mat = "Metal"
        if role == "Grip":
            mat = "Fabric" if name in FABRIC else "Wood" if name in {"HunterBlade", "ThornDagger"} else "SmoothPlastic"
        elif role == "Blade" and name in ORGANIC:
            mat = "SmoothPlastic"
        elif role == "GripDetail":
            mat = "Fabric" if name in FABRIC else "Metal"
        elif high and role in {"CuttingEdge", "Inlay", "Extra"} and name not in {"DemonHorn", "AngelFeather"}:
            mat = "Neon"
        styles[role] = {"Color": rgb, "Material": mat}
    return styles


def surface(spec, s, fraction):
    top, bot, bend = spec["profile"](s)
    z = (bot + (top - bot) * fraction + bend) * spec["height"]
    t = 0.05 * (1 - 0.55 * s * s)
    y = t * (1 - abs(2 * fraction - 1)) if spec.get("double") else t * (0.9 * fraction / 0.75 if fraction <= 0.75 else 0.9 + 0.4 * (fraction - 0.75))
    return Vector((s * spec["length"], y, z))


def pixel(bm, spec, s, fraction, cell):
    p = surface(spec, s, fraction)
    for side in (-1, 1):
        box(bm, (cell, 0.009, cell), (p.x, side * (p.y + 0.006), p.z), bevel=0)


def edge_mesh(spec):
    bm = bmesh.new()
    # A fitted ribbon over the bevel, sampled at the original loft stations.
    for side in (-1, 1):
        for bottom in ([True, False] if spec.get("double") else [True]):
            previous = None
            for i in range(24):
                s = i / 24
                pair = []
                for frac in ([0.025, 0.16] if bottom else [0.84, 0.975]):
                    p = surface(spec, s, frac)
                    p.y = side * (p.y + 0.0025)
                    pair.append(bm.verts.new(p))
                if previous:
                    bm.faces.new((previous[0], previous[1], pair[1], pair[0]))
                previous = pair
    return bm


def inlay_mesh(name, spec):
    bm = bmesh.new()
    cell = min(0.034, spec["height"] / 11)
    symbol = SYMBOLS[name]
    # Small square maker's mark at the heel; enough relief to avoid z-fighting.
    for row, line in enumerate(symbol):
        for col, bit in enumerate(line):
            if bit == "1":
                s = 0.14 + col * cell / spec["length"]
                top, bot, _ = spec["profile"](s)
                frac = 0.58 + ((len(symbol) - 1) / 2 - row) * cell / ((top - bot) * spec["height"])
                pixel(bm, spec, s, frac, cell * 0.83)
    # Distinct longitudinal decorations. Each follows its own blade's curve.
    for i in range(22):
        s = 0.36 + i * 0.023
        fraction = 0.56
        if name in {"InfernoFang", "MagmaCleaver", "VoidEdge"}:
            fraction += [0.0, 0.08, 0.16, 0.08, -0.04, -0.12][i % 6]
        elif name in {"ThornDagger", "Machete", "OlympusEdge", "AngelFeather", "SeraphSword"}:
            fraction += (i % 5 - 2) * 0.055
        elif name in {"RustyShank", "BoneCarver", "Cleaver", "KitchenKnife", "PocketKnife", "Switchblade", "HunterBlade"}:
            if i % 3 != 0:
                continue
            fraction += (i % 5 - 2) * 0.055
        elif name in {"Katana", "GalaxyKatana", "HaloBlade", "AthenaBlade", "GoldenDagger", "Reaper", "ZeusBolt", "StarCleaver", "DemonHorn"}:
            fraction += math.sin(i * 0.6) * 0.07
            if name in {"Katana", "StarCleaver", "GalaxyKatana"} and i % 4 != 0:
                continue
        pixel(bm, spec, s, fraction, cell * 0.7)
        if name in {"MagmaCleaver", "ThornDagger", "AngelFeather", "SeraphSword"} and i % 4 == 0:
            for k in range(1, 4):
                pixel(bm, spec, s + k * cell / spec["length"], fraction + k * 0.065, cell * 0.7)
    return bm


def grip_mesh(name, spec):
    bm = bmesh.new()
    r, length = spec["handle_r"], spec["handle_len"]
    z = spec["height"] / 2
    count = max(6, int(length / 0.08))
    for side in (-1, 1):
        for i in range(count):
            x = -0.12 - i * (length - 0.18) / (count - 1)
            for j in (-1, 0, 1):
                if (i + j) % 2:
                    continue
                # Stepped diamond wrap / inset grip studs, one combined mesh.
                y = r * (0.87 if j else 1.06)
                if spec.get("flat_handle"):
                    y = r * 0.82
                box(bm, (0.032, 0.011, 0.032), (x, side * (y + 0.007), z + j * r * 0.57), bevel=0)
        # Paired screws near heel and cap, readable against the grip texture.
        for x in (-0.15, -length + 0.05):
            box(bm, (0.05, 0.015, 0.05), (x, side * r * 1.14, z), bevel=0.08)
    return bm


def build_details(name, spec, root):
    styles = finish(name)
    parts = []
    offset = Vector((0.05 + spec["handle_len"] / 2, 0, -spec["height"] / 2))
    for role, build in [("CuttingEdge", edge_mesh(spec)), ("Inlay", inlay_mesh(name, spec)), ("GripDetail", grip_mesh(name, spec))]:
        color = [v / 255 for v in styles[role]["Color"]]
        obj = namespace["mesh_object"](name + "_" + role, build, namespace["material"](name + role, color), root)
        obj.data.transform(Matrix.Translation(offset))
        parts.append(obj)
    return parts


def restyle(name, parts):
    styles = finish(name)
    for obj in parts:
        role = obj.name.split(".")[0]
        role = "Grip" if role == "Handle" else "Guard" if role == "Pommel" else role.removeprefix(name + "_")
        obj.data.materials.clear()
        obj.data.materials.append(namespace["material"](name + role + "Finish", [v / 255 for v in styles[role]["Color"]]))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    namespace["clear_scene"]()
    pack = bpy.data.objects.new("KnifeDetailPack", None)
    bpy.context.collection.objects.link(pack)
    manifest = {}
    preview_objects = []
    for name in KNIVES:
        spec = silhouette_spec(name)
        parts = build_details(name, spec, pack)
        for obj in parts:
            obj.data.calc_loop_triangles()
            triangles = len(obj.data.loop_triangles)
            assert triangles < 3000, (name, obj.name, triangles)
            vertices = [v.co for v in obj.data.vertices]
            low = [min(v[i] for v in vertices) for i in range(3)]
            high = [max(v[i] for v in vertices) for i in range(3)]
            manifest[obj.name] = {"triangles": triangles, "center": [(a + b) / 2 for a, b in zip(low, high)], "size": [b - a for a, b in zip(low, high)]}
        preview_objects.append((name, spec, parts))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=str(OUT / "KnifeDetailPack.fbx"), use_selection=True, object_types={"EMPTY", "MESH"}, apply_scale_options="FBX_SCALE_ALL", axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
    (OUT / "knife_detail_manifest.json").write_text(json.dumps(manifest, indent=2))
    (OUT / "knife_finishes.json").write_text(json.dumps({n: finish(n) for n in KNIVES}, indent=2))
    # Four columns, six rows, with labels outside the knife silhouettes.
    for index, (name, spec, details) in enumerate(preview_objects):
        root, base = namespace["build_knife"](name, spec)
        for detail in details:
            detail.parent = root
        restyle(name, base + details)
        root.location = ((index % 4) * 4.6, 0, -(index // 4) * 1.75)
        bpy.ops.object.text_add(location=root.location + Vector((-0.35, -0.25, -0.6)), rotation=(math.pi / 2, 0, 0))
        label = bpy.context.object
        label.data.body = name
        label.data.size = 0.16
        label.data.materials.append(namespace["material"]("Label", (0.85, 0.90, 0.92)))
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 19.4
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((8.0, 0, -4.25))
    cam.location = target + Vector((0, -25, 1.2))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.background_type = "WORLD"
    scene.world.color = (0.045, 0.065, 0.085)
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1400
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    print("DETAIL_MESHES", len(manifest), "TOTAL_TRIANGLES", sum(v["triangles"] for v in manifest.values()))


if __name__ == "__main__":
    main()
