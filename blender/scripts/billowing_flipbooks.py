"""Original rolling cartoon fire rendered from editable implicit-field contours.

Run with Blender --background --factory-startup --python this_file.py.
Three grayscale 64-frame atlases share independent layer colors in Roblox.
No reference-image pixels are sampled or copied.
"""

import math
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "blender" / "textures" / "aura"
GRID = 144
AXIS = np.linspace(-2, 2, GRID)
X, Y = np.meshgrid(AXIS, AXIS)


def blob(x, y, rx, ry, amount=1):
    return amount * np.exp(-2 * (((X-x)/rx)**2 + ((Y-y)/ry)**2))


def field(layer, phase):
    heat = np.clip((Y+.9)/2.5, 0, 1)
    bend = .27*np.sin(Y*3-phase) * heat
    if layer == "smoke":
        value = np.zeros_like(X)
        for offset, strength in ((0, 1), (.24, .62), (-.21, .45)):
            path = .37*np.sin(Y*2.9-phase*.9+offset*4) + offset
            width = .07 + .08*(1-(Y+1.5)/3.1)
            ribbon = np.exp(-2*((X-path)/np.maximum(.035, width))**2)
            taper = np.maximum(0, np.sin(np.clip((Y+1.55)/3.15, 0, 1)*math.pi))**.55
            value += ribbon * taper * strength
        return value
    core = layer == "core"
    value = blob(0, -.68, .55 if core else .95, .43 if core else .52, 1.15)
    count = 4 if core else 5
    for i in range(count):
        u = (phase/math.tau + i/count) % 1
        envelope = math.sin(math.pi*u)**.65
        x = (.36 if core else .67)*math.sin(u*math.tau*1.05+i*1.7)
        y = -.83 + (2 if core else 2.22)*u
        radius = (.37 if core else .57)*(.65+.35*envelope)
        value += blob(x, y, radius, radius*(1.15+.5*u), envelope*1.35)
    # Rising thin tongues merge with the broad lobes and then peel away.
    path = .33*np.sin(Y*3.4-phase) + bend
    value += np.exp(-2*((X-path)/(.12+.1*(1-heat)))**2) * np.exp(-2*((Y-.12)/.93)**2)*.7
    # Advected negative pockets open and close inside the rolling silhouette.
    for i in range(2):
        u = (phase/math.tau + i*.5+.15) % 1
        radius = (.19 if core else .3)*math.sin(math.pi*u)**.7
        if radius > .01:
            value -= blob(.25*math.sin(u*math.tau+i*2), -.45+1.34*u,
                          radius, radius*1.5, 1.35*math.sin(math.pi*u))
    value *= np.clip((Y+1.38)*8, 0, 1) * np.clip((1.67-Y)*5, 0, 1)
    return value


# Marching squares converts the original scalar art into Blender's native 2D curves.
EDGES = {1: [(3, 0)], 2: [(0, 1)], 3: [(3, 1)], 4: [(1, 2)],
         5: [(3, 2), (0, 1)], 6: [(0, 2)], 7: [(3, 2)], 8: [(2, 3)],
         9: [(0, 2)], 10: [(0, 3), (1, 2)], 11: [(1, 2)],
         12: [(1, 3)], 13: [(0, 1)], 14: [(0, 3)]}


def contours(value, threshold=.42):
    graph = {}
    coordinates = {}
    a, b = value[:-1, :-1], value[:-1, 1:]
    c, d = value[1:, 1:], value[1:, :-1]
    cases = (a >= threshold).astype(int) + (b >= threshold)*2 + (c >= threshold)*4 + (d >= threshold)*8
    for row, col in np.argwhere((cases > 0) & (cases < 15)):
        values = (a[row, col], b[row, col], c[row, col], d[row, col])
        points = ((col, row), (col+1, row), (col+1, row+1), (col, row+1))
        def crossing(edge):
            first, second = edge, (edge+1) % 4
            p, q = points[first], points[second]
            key = tuple(sorted((p, q)))
            t = (threshold-values[first])/(values[second]-values[first])
            coordinates[key] = ((p[0]+t*(q[0]-p[0]))/(GRID-1)*4-2,
                                (p[1]+t*(q[1]-p[1]))/(GRID-1)*4-2)
            return key
        for first, second in EDGES[int(cases[row, col])]:
            p, q = crossing(first), crossing(second)
            graph.setdefault(p, []).append(q)
            graph.setdefault(q, []).append(p)
    paths = []
    visited = set()
    for start in graph:
        if start in visited:
            continue
        path = []
        previous, current = None, start
        while current not in visited:
            visited.add(current)
            path.append(coordinates[current])
            neighbors = graph[current]
            next_point = next((n for n in neighbors if n != previous), start)
            previous, current = current, next_point
        if current == start and len(path) > 6:
            paths.append(path)
    return paths


def sprite(layer, frame, material):
    curve = bpy.data.curves.new(f"{layer}_{frame:02}", "CURVE")
    curve.dimensions = "2D"
    curve.fill_mode = "BOTH"
    for points in contours(field(layer, frame*math.tau/64)):
        spline = curve.splines.new("POLY")
        spline.points.add(len(points)-1)
        for point, (x, y) in zip(spline.points, points):
            point.co = (x, y, 0, 1)
        spline.use_cyclic_u = True
    obj = bpy.data.objects.new(curve.name, curve)
    obj.location = (-14+(frame % 8)*4, 14-(frame // 8)*4, 0)
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
    material = bpy.data.materials.new("WhiteMask")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1, 1, 1, 1)
    material.node_tree.links.new(emission.outputs[0], output.inputs["Surface"])
    camera = bpy.data.cameras.new("AtlasCamera")
    camera.type = "ORTHO"
    camera.ortho_scale = 32
    obj = bpy.data.objects.new("AtlasCamera", camera)
    obj.location = (0, 0, 30)
    bpy.context.collection.objects.link(obj)
    scene.camera = obj
    scene.use_nodes = True
    compositor = scene.node_tree
    compositor.nodes.clear()
    layers = compositor.nodes.new("CompositorNodeRLayers")
    blur = compositor.nodes.new("CompositorNodeBlur")
    blur.filter_type = "GAUSS"
    blur.size_x = blur.size_y = 2
    composite = compositor.nodes.new("CompositorNodeComposite")
    compositor.links.new(layers.outputs["Image"], blur.inputs["Image"])
    compositor.links.new(blur.outputs["Image"], composite.inputs["Image"])
    for layer in ("outer", "core", "smoke"):
        objects = [sprite(layer, frame, material) for frame in range(64)]
        scene.render.filepath = str(OUT / f"billow_{layer}_8x8.png")
        bpy.ops.render.render(write_still=True)
        for sprite_obj in objects:
            bpy.data.objects.remove(sprite_obj, do_unlink=True)
    print(f"Rendered rolling outer/core/smoke atlases to {OUT}")


if __name__ == "__main__":
    main()
