"""Voxel environmental detail pack; one mesh per material, origin at ground level.

Run with Blender --background --factory-startup --python blender/scripts/map_details.py.
All small blocks are baked together. Blender Z maps to Roblox Y on import.
"""

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "exports" / "map"
PREVIEW = ROOT / "blender" / "previews" / "map_details.png"


class Prop:
    def __init__(self, name, palette):
        self.name = name
        self.palette = palette
        self.meshes = {role: bmesh.new() for role in palette}

    def box(self, role, size, center, angle=0):
        bm = self.meshes[role]
        verts = bmesh.ops.create_cube(bm, size=1)["verts"]
        matrix = Matrix.Rotation(angle, 4, "Z") @ Matrix.Diagonal((*size, 1))
        bmesh.ops.transform(bm, matrix=matrix, verts=verts)
        bmesh.ops.translate(bm, vec=Vector(center), verts=verts)

    def ring(self, role, radius, z, thickness, height, segments=16):
        for i in range(segments):
            a = i * math.tau / segments
            self.box(role, (thickness, 2 * radius * math.tan(math.pi / segments) + .035, height),
                     (radius * math.cos(a), radius * math.sin(a), z), a)

    def steps(self, role, width, depth, levels, rise=.3, inset=.45, base=0):
        for i in range(levels):
            self.box(role, (width-i*inset*2, depth-i*inset*2, rise), (0, 0, base+rise*(i+.5)))

    def studs(self, role, width, depth, z, spacing=.8, size=.16):
        for x in range(int(width / spacing)):
            for y in range(int(depth / spacing)):
                self.box(role, (size, size, .06), ((x+.5)*spacing-width/2, (y+.5)*spacing-depth/2, z))

    def glyph(self, role, rows, center, cell=.18, back=False):
        x, y, z = center
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit == "#":
                    self.box(role, (cell*.88, .06, cell*.88),
                             (x+(c-(len(row)-1)/2)*cell, y, z+((len(rows)-1)/2-r)*cell))
                    if back:
                        self.box(role, (cell*.88, .06, cell*.88),
                                 (x+(c-(len(row)-1)/2)*cell, -y, z+((len(rows)-1)/2-r)*cell))


STONE = ((184, 199, 213), "SmoothPlastic")
LIGHT = ((239, 247, 251), "SmoothPlastic")
GOLD = ((243, 192, 63), "Metal")
IRON = ((48, 61, 75), "Metal")
WARM = ((255, 219, 133), "Neon")
SKULL = [".###.", "#####", "#.#.#", "#####", ".###.", ".#.#."]
STAR = ["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."]


def bench():
    p = Prop("DetailBench", {"Wood": ((181, 99, 56), "SmoothPlastic"), "Edges": ((231, 163, 89), "SmoothPlastic"), "Iron": IRON})
    for x in (-2.5, 2.5):
        for y in (-.65, .65):
            p.box("Iron", (.35, .35, 1.7), (x, y, .85))
            p.box("Iron", (.65, .6, .18), (x, y, .09))
        p.box("Iron", (.25, 1.8, .25), (x, 0, 1.5))
        p.box("Iron", (.25, .25, 2.2), (x, .78, 2.4))
        p.box("Iron", (.25, 1.7, .2), (x, -.1, 2.3))
    for y in (-.64, -.2, .24, .68):
        p.box("Wood", (6.5, .36, .25), (0, y, 1.72))
        for x in (-2.5, 2.5):
            p.box("Iron", (.12, .12, .045), (x, y, 1.865))
    for z in (2.2, 2.7, 3.2):
        p.box("Wood", (6.5, .24, .4), (0, .8, z))
        p.box("Edges", (6.5, .04, .05), (0, .65, z+.15))
        for x in (-2.5, 2.5):
            p.box("Iron", (.12, .055, .12), (x, .645, z))
    return p


def lamp():
    p = Prop("DetailLamp", {"Iron": IRON, "Trim": GOLD, "Glass": WARM})
    p.steps("Iron", 1.9, 1.9, 3, .2, .17)
    p.box("Iron", (.46, .46, 7.2), (0, 0, 4.2))
    for z in (1.2, 2, 6.8, 7.5):
        p.box("Trim", (.62, .62, .16), (0, 0, z))
    for x in (-.66, .66):
        for y in (-.66, .66):
            p.box("Iron", (.13, .13, 1.7), (x, y, 8.55))
    p.box("Glass", (1.08, 1.08, 1.35), (0, 0, 8.55))
    p.box("Iron", (1.65, 1.65, .2), (0, 0, 7.68))
    for z, w in ((9.45, 1.9), (9.68, 1.5), (9.91, 1.1), (10.14, .7)):
        p.box("Iron", (w, w, .23), (0, 0, z))
    p.box("Trim", (.28, .28, .4), (0, 0, 10.5))
    for x in (-.42, 0, .42):
        p.box("Trim", (.055, 1.14, .055), (x, 0, 8.55))
        p.box("Trim", (1.14, .055, .055), (0, x, 8.55))
    return p


def fountain():
    p = Prop("DetailFountain", {"Stone": STONE, "Carving": LIGHT, "Trim": GOLD, "Water": ((82, 211, 242), "SmoothPlastic")})
    p.steps("Stone", 12, 12, 3, .22, .25)
    for i in range(4):
        a = i*math.pi/2
        p.box("Stone", (11, .8, 1.1), (5.1*math.sin(a), 5.1*math.cos(a), 1.1), -a)
        for k in range(-5, 6):
            p.box("Carving", (.19, .05, .2),
                  (k*.85*math.cos(a)-5.52*math.sin(a), -k*.85*math.sin(a)-5.52*math.cos(a), 1.1), -a)
    p.box("Water", (9.3, 9.3, .14), (0, 0, 1.2))
    p.steps("Carving", 2.8, 2.8, 4, .25, .18, 1.27)
    p.box("Stone", (.9, .9, 3.3), (0, 0, 3.5))
    for z, w in ((3, 5), (5.5, 3.2)):
        p.box("Stone", (w, w, .35), (0, 0, z))
        p.box("Trim", (w+.14, w+.14, .1), (0, 0, z-.18))
        p.box("Water", (w-.4, w-.4, .12), (0, 0, z+.24))
        for side in (-1, 1):
            for k in (-1, 0, 1):
                p.box("Water", (.13, .17, 1.4), (side*(w/2-.12), k*.65, z-.5))
                p.box("Water", (.17, .13, 1.4), (k*.65, side*(w/2-.12), z-.5))
    p.box("Carving", (.6, .6, 1.1), (0, 0, 6.15))
    p.ring("Trim", 1, 6.8, .12, .17, 12)
    for i in range(12):
        a = i*math.tau/12
        p.box("Water", (.14, .14, .14), (math.cos(a)*2.2, math.sin(a)*2.2, 1.35))
    return p


def topiary():
    p = Prop("DetailTopiary", {"Pot": ((176, 82, 61), "SmoothPlastic"), "Trim": ((230, 135, 88), "SmoothPlastic"), "Leaf": ((41, 139, 87), "SmoothPlastic"), "Tips": ((90, 186, 109), "SmoothPlastic")})
    p.steps("Pot", 2.1, 2.1, 3, .3, -.1)
    p.box("Trim", (2.8, 2.8, .2), (0, 0, 1))
    p.box("Pot", (.35, .35, 2), (0, 0, 1.7))
    for z, w in ((2.7, 3.8), (4.7, 2.9), (6.3, 1.9)):
        p.box("Leaf", (w, w, w*.6), (0, 0, z))
        n = int(w/.5)
        for x in range(n):
            for y in range(n):
                if (x+y)%3 == 0:
                    p.box("Tips", (.38, .38, .14), ((x-(n-1)/2)*.5, (y-(n-1)/2)*.5, z+w*.3+.04))
        for side in (-1, 1):
            for k in range(n):
                p.box("Tips", (.2, .08, .28), ((k-(n-1)/2)*.5, side*(w/2+.01), z))
    return p


def gazebo():
    p = Prop("DetailGazebo", {"Frame": LIGHT, "Roof": ((61, 128, 174), "SmoothPlastic"), "Tiles": ((100, 173, 206), "SmoothPlastic"), "Trim": GOLD})
    p.steps("Frame", 15, 15, 3, .25, .28)
    for x in (-5.8, 5.8):
        for y in (-5.8, 5.8):
            p.box("Frame", (.65, .65, 8), (x, y, 4.7))
            for z in (1.1, 2, 8.1):
                p.box("Trim", (.8, .8, .12), (x, y, z))
    for y in (-5.8, 5.8):
        p.box("Frame", (12.4, .45, .45), (0, y, 8.55))
    for x in (-5.8, 5.8):
        p.box("Frame", (.45, 12.4, .45), (x, 0, 8.55))
        p.box("Frame", (.35, 11.3, .35), (x, 0, 3.2))
        for k in range(-7, 8):
            p.box("Frame", (.2, .2, 1.9), (x, k*.73, 2.1))
            p.box("Trim", (.25, .25, .15), (x, k*.73, 2.6))
    for i in range(9):
        w = 16-i*1.55
        z = 8.9+i*.48
        p.box("Roof", (w, w, .48), (0, 0, z))
        for k in range(int(w/.65)):
            a = (k+.5)*.65-w/2
            for side in (-1, 1):
                p.box("Tiles", (.55, .48, .1), (a, side*(w/2-.18), z+.285))
                p.box("Tiles", (.48, .55, .1), (side*(w/2-.18), a, z+.285))
    p.box("Trim", (.4, .4, 1), (0, 0, 13.25))
    return p


def tomb():
    p = Prop("DetailMausoleum", {"Stone": ((121, 134, 166), "SmoothPlastic"), "Masonry": ((164, 176, 202), "SmoothPlastic"), "Door": ((67, 61, 99), "SmoothPlastic"), "Trim": ((182, 147, 222), "Metal")})
    p.steps("Stone", 12, 12, 3, .3, .3)
    p.box("Stone", (9.6, 9.6, 8), (0, 0, 4.9))
    for side in (-1, 1):
        for row in range(8):
            for col in range(8):
                x = (col-3.5)*1.15 + (.28 if row%2 else 0)
                p.box("Masonry", (1.05, .14, .8), (x, side*4.87, 1.4+row*.95))
                p.box("Masonry", (.14, 1.05, .8), (side*4.87, x, 1.4+row*.95))
    p.box("Door", (3.4, .2, 5.6), (0, -5.02, 3.8))
    for x in (-2.1, 2.1):
        p.box("Stone", (.6, .75, 6.4), (x, -5, 4))
        for z in (1.15, 2.1, 6.3, 7):
            p.box("Trim", (.8, .85, .18), (x, -5, z))
    for x in (-.9, .9):
        p.box("Trim", (.08, .06, 4.8), (x, -5.16, 3.9))
    p.glyph("Trim", SKULL, (0, -5.17, 5.6), .27)
    p.box("Trim", (.22, .14, .22), (.65, -5.18, 3.1))
    for i in range(6):
        p.box("Stone", (12-i*1.6, 11.7, .45), (0, 0, 9.15+i*.45))
        p.box("Trim", (12.12-i*1.6, .13, .09), (0, -5.92, 9.4+i*.45))
    return p


def gravestone():
    p = Prop("DetailGravestone", {"Stone": ((122, 133, 162), "SmoothPlastic"), "Rim": ((172, 185, 207), "SmoothPlastic"), "Carving": ((68, 79, 104), "SmoothPlastic"), "Moss": ((95, 154, 103), "SmoothPlastic")})
    p.steps("Stone", 3.3, 2, 2, .25, .2)
    p.box("Stone", (2.4, .65, 3), (0, 0, 1.95))
    for i in range(3):
        p.box("Stone", (2.2-i*.6, .65, .3), (0, 0, 3.6+i*.3))
    for x in (-1.1, 1.1):
        p.box("Rim", (.12, .08, 2.7), (x, -.37, 2))
    p.glyph("Carving", SKULL, (0, -.36, 2.85), .2)
    for i, w in enumerate((1.2, .85, 1.05)):
        p.box("Carving", (w, .04, .09), (0, -.37, 1.55-i*.23))
    for x in (-.85, -.45, .6):
        p.box("Moss", (.3, .06, .16), (x, -.39, .7))
    return p


def column():
    p = Prop("DetailColumn", {"Stone": STONE, "Flutes": LIGHT, "Trim": GOLD, "Inset": ((91, 132, 158), "SmoothPlastic")})
    p.steps("Stone", 4.8, 4.8, 3, .35, .3)
    p.box("Stone", (2.7, 2.7, 19.6), (0, 0, 10.85))
    for side in (-1, 1):
        for a in (-.8, 0, .8):
            p.box("Flutes", (.25, .2, 18.6), (a, side*1.42, 10.7))
            p.box("Flutes", (.2, .25, 18.6), (side*1.42, a, 10.7))
        for z in (2.2, 18.8):
            p.glyph("Inset", ["..#..", ".###.", "#####", ".###.", "..#.."], (0, side*1.52, z), .16)
    for z, w in ((1.3, 3.4), (2, 3.1), (19.9, 3.2), (20.7, 4), (21.3, 4.8)):
        p.box("Trim", (w, w, .18), (0, 0, z))
    p.box("Stone", (4.8, 4.8, .65), (0, 0, 21.85))
    for side in (-1, 1):
        for k in range(-5, 6):
            p.box("Inset", (.19, .06, .25), (k*.37, side*2.43, 21.85))
    return p


def spire():
    p = Prop("DetailSpire", {"Rock": ((53, 48, 63), "SmoothPlastic"), "Facets": ((80, 67, 82), "SmoothPlastic"), "Cracks": ((255, 116, 36), "Neon"), "Embers": ((255, 208, 67), "Neon")})
    for i in range(12):
        w = 5.2-i*.38
        x = .12*i
        z = .6+i*1.15
        p.box("Rock", (w, w*.9, 1.3), (x, 0, z))
        for k in range(4):
            p.box("Facets", (.23, .09, .65), (x-w/2+.4+k*w/4, -w*.45-.02, z))
        p.box("Cracks", (.18, .09, .72), (x+math.sin(i*.8)*w*.23, -w*.45-.08, z))
        p.box("Cracks", (.6, .09, .13), (x+math.sin(i*.8)*w*.23+.2, -w*.45-.08, z+.36))
    for x, y, s in ((-3.1, 1, 1.2), (2.9, 1, .9), (-1.3, -2.7, .8)):
        p.box("Rock", (s, s, s*.8), (x, y, s*.4))
        p.box("Embers", (.15, s+.02, .12), (x, y, s*.8))
    return p


def angel():
    p = Prop("DetailAngel", {"Stone": LIGHT, "Feathers": ((206, 227, 242), "SmoothPlastic"), "Gold": GOLD, "Inset": ((109, 157, 191), "SmoothPlastic")})
    p.steps("Stone", 5, 5, 3, .35, .3)
    for i in range(10):
        w = 3.1-i*.09
        p.box("Stone", (w, 1.8, .5), (0, 0, 1.3+i*.5))
        for x in (-.7, 0, .7):
            p.box("Feathers", (.12, .06, .52), (x, -.94, 1.3+i*.5))
    p.box("Stone", (2.8, 1.9, 1.8), (0, 0, 7.1))
    p.box("Stone", (1.7, 1.7, 1.8), (0, 0, 9))
    for x in (-.37, .37):
        p.box("Inset", (.24, .05, .08), (x, -.88, 9.1))
    p.box("Stone", (.25, .18, .3), (0, -.91, 8.92))
    p.box("Gold", (.64, .06, .07), (0, -.9, 8.56))
    for side in (-1, 1):
        p.box("Stone", (.8, .9, 3.1), (side*1.8, -.35, 6.5))
        for feather in range(9):
            x = side*(1.55+feather*.47)
            z = 7.9+feather*.32
            h = 4.4-feather*.29
            p.box("Stone", (.6, .55, h), (x, .9, z))
            for k in range(int(h/.35)):
                p.box("Feathers", (.45, .08, .13), (x, .59, z-h/2+.25+k*.35))
            p.box("Gold", (.26, .08, .22), (x, .59, z+h/2-.1))
    p.ring("Gold", 1.15, 10.65, .18, .16, 20)
    p.glyph("Gold", STAR, (0, -2.03, .64), .09)
    return p


def orrery():
    p = Prop("DetailOrrery", {"Frame": IRON, "Trim": GOLD, "Planet": ((91, 177, 223), "SmoothPlastic"), "Stars": ((191, 237, 253), "Neon")})
    p.steps("Frame", 7, 7, 4, .28, .5)
    p.box("Frame", (.65, .65, 3), (0, 0, 2.6))
    p.box("Trim", (4, 4, .25), (0, 0, 4.1))
    for radius, z in ((1.3, 4.5), (2.2, 4.65), (3.1, 4.8)):
        p.ring("Trim", radius, z, .13, .1, 24)
    for i in range(24):
        a = i*math.tau/24
        p.box("Stars", (.12, .12, .07), (3.25*math.cos(a), 3.25*math.sin(a), 4.82))
    for x, y, w, z in ((0, 0, 1.4, 5), (1.1, .7, .5, 4.95), (-1.6, -1.5, .8, 5.2), (2.8, -1.3, .65, 5.3)):
        p.box("Planet", (w, w, w), (x, y, z))
        p.box("Stars", (w*.55, w+.03, .12), (x, y, z+w*.12))
        p.box("Trim", (.16, .16, .5), (x, y, z-.4))
    for side in (-1, 1):
        p.glyph("Stars", STAR, (0, side*2.05, .8), .15)
    return p


def gate_hardware():
    p = Prop("DetailGateHardware", {"Shell": IRON, "Plates": STONE, "Bolts": GOLD, "Power": ((91, 228, 242), "Neon")})
    for z in (1, 5.5, 10):
        p.box("Shell", (2.4, 2, .9), (0, 0, z))
        p.box("Plates", (2.1, .1, .65), (0, -1.06, z))
        for x in (-.85, .85):
            for dz in (-.22, .22):
                p.box("Bolts", (.12, .07, .12), (x, -1.14, z+dz))
    for i in range(7):
        z = 2.4+i*1.1
        p.box("Shell", (.8, .2, .65), (0, -1.04, z))
        p.box("Power", (.52, .07, .13), (0, -1.18, z))
    for x in (-.5, .5):
        p.box("Bolts", (.08, .09, 8.4), (x, -1.05, 5.5))
    return p


def window():
    p = Prop("DetailManorWindow", {"Stone": ((159, 164, 185), "SmoothPlastic"), "Trim": ((89, 70, 104), "SmoothPlastic"), "Gold": GOLD})
    for x in (-2.3, 2.3):
        for i in range(8):
            p.box("Stone", (.6, .6, .72), (x, 0, .4+i*.78))
        p.box("Trim", (.18, .3, 6.3), (x*.86, -.36, 3.3))
    p.box("Stone", (5.5, 1.05, .4), (0, -.15, .1))
    p.box("Stone", (5.1, .6, .5), (0, 0, 6.65))
    for i in range(4):
        p.box("Trim", (5.6-i*.7, .75, .17), (0, 0, 6.95+i*.17))
    p.box("Trim", (.16, .28, 6), (0, -.28, 3.35))
    p.box("Trim", (4, .28, .16), (0, -.28, 3.9))
    p.glyph("Gold", ["..#..", ".###.", "#####", ".###.", "..#.."], (0, -.43, 7.13), .14)
    return p


def flowerbed():
    p = Prop("DetailFlowerBed", {"Border": STONE, "Soil": ((83, 76, 58), "SmoothPlastic"),
                                "Leaf": ((69, 157, 85), "SmoothPlastic"),
                                "Petals": ((242, 153, 195), "SmoothPlastic"), "Centers": GOLD})
    p.box("Soil", (6.6, 2.6, .22), (0, 0, .11))
    for y in (-1.45, 1.45):
        p.box("Border", (7.2, .3, .45), (0, y, .225))
    for x in (-3.45, 3.45):
        p.box("Border", (.3, 2.6, .45), (x, 0, .225))
    for i in range(8):
        x = -2.5 + (i%4)*1.65
        y = -.68 + (i//4)*1.36
        z = 1.05+(i%3)*.14
        p.box("Leaf", (.14, .14, z-.3), (x, y, (z+.3)/2))
        p.box("Leaf", (.62, .25, .13), (x+.22, y, .65))
        p.box("Leaf", (.25, .55, .13), (x, y-.18, .8))
        for dx, dy in ((-.24, 0), (.24, 0), (0, -.24), (0, .24)):
            p.box("Petals", (.32, .32, .16), (x+dx, y+dy, z))
            p.box("Petals", (.18, .18, .1), (x+dx*1.6, y+dy*1.6, z-.04))
        p.box("Centers", (.23, .23, .13), (x, y, z+.06))
    return p


BUILDERS = [bench, lamp, fountain, topiary, gazebo, tomb, gravestone, column, spire, angel, orrery, gate_hardware, window, flowerbed]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    pack = bpy.data.objects.new("MapDetailPack", None)
    bpy.context.collection.objects.link(pack)
    manifest = {}
    groups = []
    for build in BUILDERS:
        p = build()
        objects = []
        for role, bm in p.meshes.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            name = p.name + "_" + role
            mesh = bpy.data.meshes.new(name)
            bm.to_mesh(mesh)
            bm.free()
            obj = bpy.data.objects.new(name, mesh)
            obj.parent = pack
            bpy.context.collection.objects.link(obj)
            color, material = p.palette[role]
            mat = bpy.data.materials.new(name)
            mat.diffuse_color = (*[v/255 for v in color], 1)
            mesh.materials.append(mat)
            mesh.calc_loop_triangles()
            triangles = len(mesh.loop_triangles)
            assert 0 < triangles < 10000, (name, triangles)
            low = [min(v.co[i] for v in mesh.vertices) for i in range(3)]
            high = [max(v.co[i] for v in mesh.vertices) for i in range(3)]
            manifest[name] = {"prop": p.name, "role": role, "color": color, "material": material,
                              "triangles": triangles, "center": [(a+b)/2 for a,b in zip(low,high)],
                              "size": [b-a for a,b in zip(low,high)]}
            objects.append(obj)
        groups.append((p.name, objects))
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(filepath=str(OUT / "MapDetailPack.fbx"), use_selection=True,
                             object_types={"EMPTY", "MESH"}, apply_scale_options="FBX_SCALE_ALL",
                             axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE")
    (OUT / "map_detail_manifest.json").write_text(json.dumps(manifest, indent=2))
    for i, (name, objects) in enumerate(groups):
        root = bpy.data.objects.new(name, None)
        bpy.context.collection.objects.link(root)
        root.location = ((i%5)*18, (i//5)*23, 0)
        for obj in objects:
            obj.parent = root
        bpy.ops.object.text_add(location=root.location+Vector((-5,-7,.02)))
        label = bpy.context.object
        label.data.body = name.removeprefix("Detail")
        label.data.size = .8
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("World")
    scene.world.color = (.09, .12, .15)
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 109
    cam = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam)
    target = Vector((34, 21, 4))
    cam.location = target+Vector((18,-88,88))
    cam.rotation_euler = (target-cam.location).to_track_quat("-Z","Y").to_euler()
    scene.camera = cam
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1800
    scene.render.resolution_percentage = 100
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    print("MAP_DETAIL_MESHES", len(manifest), "TRIANGLES", sum(v["triangles"] for v in manifest.values()))


if __name__ == "__main__":
    main()
