"""Render the exact shared blocks; no game integration or replacement geometry."""
from pathlib import Path
import json, math, re
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/biome-shells/OuterSpace'
data=json.loads((OUT/'geometry.json').read_text())
(OUT/'renders').mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=960;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard'
scene.world=bpy.data.worlds.new('ClearDay');scene.world.use_nodes=True
nodes=scene.world.node_tree.nodes;links=scene.world.node_tree.links
bg=nodes.get('Background');bg.inputs['Color'].default_value=(1,1,1,1);bg.inputs['Strength'].default_value=.8
sky=nodes.new('ShaderNodeBackground');sky.inputs['Color'].default_value=(.35,.65,.95,1)
path=nodes.new('ShaderNodeLightPath');mix=nodes.new('ShaderNodeMixShader')
links.new(path.outputs['Is Camera Ray'],mix.inputs[0]);links.new(bg.outputs[0],mix.inputs[1]);links.new(sky.outputs[0],mix.inputs[2])
links.new(mix.outputs[0],nodes.get('World Output').inputs['Surface'])
materials={}
foam=bpy.data.images.load(str(OUT/'textures/WaterFoam.png'))
def linear(v):
    v=v/255;return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def material(color,water=False,water_face=None,size=None,neon=False):
    key=(tuple(color),water,water_face,tuple(size) if size else None,neon)
    if key in materials:return materials[key]
    m=bpy.data.materials.new('Water' if water else str(color));m.use_nodes=True
    rgb=tuple(linear(v) for v in color);m.diffuse_color=(*rgb,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*rgb,1)
    p.inputs['Roughness'].default_value=.9
    if neon:
        p.inputs['Emission Color'].default_value=(*rgb,1);p.inputs['Emission Strength'].default_value=3
    if water:
        p.inputs['Emission Color'].default_value=(*rgb,1);p.inputs['Emission Strength'].default_value=3 if neon else 0
        nodes=m.node_tree.nodes;links=m.node_tree.links
        coords=nodes.new('ShaderNodeTexCoord');separate=nodes.new('ShaderNodeSeparateXYZ')
        links.new(coords.outputs['Generated'],separate.inputs[0])
        combine=nodes.new('ShaderNodeCombineXYZ')
        axes=('Y','Z') if water_face in ('Left','Right') else ('X','Y')
        dims=(size[2],size[1]) if water_face in ('Left','Right') else (size[0],size[2])
        for i,(axis,dim) in enumerate(zip(axes,dims)):
            mul=nodes.new('ShaderNodeMath');mul.operation='MULTIPLY';mul.inputs[1].default_value=dim/12
            links.new(separate.outputs[axis],mul.inputs[0]);links.new(mul.outputs[0],combine.inputs[i])
        tex=nodes.new('ShaderNodeTexImage');tex.image=foam;tex.extension='REPEAT'
        links.new(combine.outputs[0],tex.inputs['Vector'])
        alpha=nodes.new('ShaderNodeMath');alpha.operation='MULTIPLY';alpha.inputs[1].default_value=.55
        links.new(tex.outputs['Alpha'],alpha.inputs[0])
        mix=nodes.new('ShaderNodeMixRGB');mix.inputs[1].default_value=(*rgb,1)
        links.new(alpha.outputs[0],mix.inputs[0]);tint=nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1;tint.inputs[2].default_value=(*[linear(v) for v in (116,231,255)],1)
        links.new(tex.outputs['Color'],tint.inputs[1]);links.new(tint.outputs[0],mix.inputs[2]);links.new(mix.outputs[0],p.inputs['Base Color'])
    materials[key]=m;return m
bpy.ops.mesh.primitive_cube_add(size=1)
cube=bpy.context.object;mesh=cube.data; bpy.data.objects.remove(cube,do_unlink=True)
group_collections={}
for name,parts in data['Groups'].items():
    coll=bpy.data.collections.new(name);scene.collection.children.link(coll);group_collections[name]=coll
    for row in parts:
        if row.get('Hidden'):continue
        x,y,z=row['Offset'];sx,sy,sz=row['Size']
        obj=bpy.data.objects.new(name+'.'+row['Name'],mesh);coll.objects.link(obj)
        obj.location=(x,-z,y);obj.scale=(sx,sz,sy)
        obj.visible_shadow=False # Builder uses CastShadow=false on every shell block.
        obj.data=mesh
        if not obj.data.materials:obj.data.materials.append(material(row['Color'],neon=bool(row.get('Neon'))))
        obj.material_slots[0].link='OBJECT';obj.material_slots[0].material=material(row['Color'],bool(row.get('WaterFace')),row.get('WaterFace'),row['Size'] if row.get('WaterFace') else None,neon=bool(row.get('Neon')))
        obj['SharedGeometry']=True;obj['Detail']=row.get('Detail',False)

# Existing lair for CONTEXT ONLY: exact unchanged native data, not new shell parts.
seam_context=bpy.data.collections.new('ApprovedHeavensSeam_CONTEXT_ONLY');scene.collection.children.link(seam_context)
old=json.loads((ROOT/'assets/biome-shells/Heavens/geometry.json').read_text())
for rows in old['Groups'].values():
    for row in rows:
        if row.get('Hidden'):continue
        x,y,z=row['Offset'];sx,sy,sz=row['Size'];lo=max(z-sz/2,190);hi=min(z+sz/2,220)
        if hi<=lo:continue
        obj=bpy.data.objects.new('PreviousSeam.'+row['Name'],mesh);seam_context.objects.link(obj)
        obj.location=(x,220-(lo+hi)/2,y);obj.scale=(sx,hi-lo,sy);obj.visible_shadow=False
        obj.material_slots[0].link='OBJECT';obj.material_slots[0].material=material(row['Color'])
context=bpy.data.collections.new('ExistingNickLair_CONTEXT_ONLY');scene.collection.children.link(context)
source=(ROOT/'src/shared/Config/ToyGeometry/LairNick.luau').read_text()
for i,match in enumerate(re.finditer(r'Name\s*=\s*"([^"]+)".*?Size\s*=\s*Vector3.new\(([^)]+)\).*?Offset\s*=\s*Vector3.new\(([^)]+)\).*?Color\s*=\s*Color3.fromRGB\(([^)]+)\)',source,re.S)):
    name,sizes,offsets,colors=match.groups()
    sx,sy,sz=[float(v) for v in sizes.split(',')];lx,ly,lz=[float(v) for v in offsets.split(',')]
    obj=bpy.data.objects.new('ContextOnly.'+name,mesh);context.objects.link(obj)
    obj.location=(73+lz,-132+lx,ly);obj.scale=(sz,sx,sy)
    obj.material_slots[0].link='OBJECT';obj.material_slots[0].material=material(tuple(int(v) for v in colors.split(',')))

bpy.ops.object.light_add(type='SUN',location=(0,0,200));sun=bpy.context.object
sun.data.energy=2.1;sun.data.angle=.12;sun.rotation_euler=(math.radians(24),math.radians(-30),math.radians(-20))
bpy.ops.object.camera_add();camera=bpy.context.object;scene.camera=camera
def coord(v):return Vector((v[0],-v[2],v[1]))
for name,view in data['CameraViews'].items():
    camera.location=coord(view['Position']);target=coord(view['Target'])
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO' if 'Ortho' in view else 'PERSP'
    if 'Ortho' in view:camera.data.ortho_scale=view['Ortho']
    else:camera.data.angle=math.radians(view['Fov'])
    # Elevations isolate the relevant wall; other renders use the full exact assembly.
    for group,coll in group_collections.items():
        coll.hide_render=(name=='left-wall' and group not in ('LeftWall','VoidStargate')) or (name=='right-wall' and group not in ('RightWall',))
    context.hide_render=name in ('left-wall','right-wall')
    seam_context.hide_render=name in ('left-wall','right-wall','top')
    scene.render.filepath=str(OUT/'renders'/f'{name}.png')
    bpy.ops.render.render(write_still=True)
for coll in group_collections.values():coll.hide_render=False
context.hide_render=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'OuterSpaceShell.blend'))
print('Rendered six views from exact shared OuterSpace native block geometry')
