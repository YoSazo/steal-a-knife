"""Blender review of exactly the cuboids used by the runtime factory."""
import json, math, sys
from pathlib import Path
import bpy
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/toy-redesign'
data=json.loads((OUT/'geometry.json').read_text())['Designs']
specs={d['Name']:d for d in data}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
cube=bpy.data.meshes.new('Individual cuboid')
cube.from_pydata([(x,y,z) for x in (-.5,.5) for y in (-.5,.5) for z in (-.5,.5)],[],[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)])
meshes={};collections=[]
basis=Matrix(((1,0,0),(0,0,-1),(0,1,0)))
only=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
def bounds(name):
    verts=[]
    for row in specs[name]['Parts']:
        rotate=Matrix.Rotation(math.radians(row['Angle']),3,'Z')
        for a in (-.5,.5):
            for b in (-.5,.5):
                for c in (-.5,.5):verts.append(Vector(row['Offset'])+rotate@Vector((a*row['Size'][0],b*row['Size'][1],c*row['Size'][2])))
    lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
    return (lo+hi)/2,hi-lo
def linear(s):return s/12.92 if s<=.04045 else ((s+.055)/1.055)**2.4
def blocks(coll,name,offset=(0,0,0),scale=1,yaw=0,tilt=0,center=False,wood=None):
    rotate=Matrix.Rotation(yaw,3,'Y')@Matrix.Rotation(tilt,3,'Z')
    shift=rotate@(bounds(name)[0]*scale) if center else Vector((0,0,0))
    for row in specs[name]['Parts']:
        color=tuple(wood if wood and row['Name']=='Wood' else row['Color'])
        if color not in meshes:
            mat=bpy.data.materials.new(str(color));mat.diffuse_color=tuple(linear(v/255) for v in color)+(1,)
            mat.use_nodes=True;shader=mat.node_tree.nodes.get('Principled BSDF')
            shader.inputs['Base Color'].default_value=mat.diffuse_color;shader.inputs['Roughness'].default_value=.72
            mesh=cube.copy();mesh.materials.append(mat);meshes[color]=mesh
        obj=bpy.data.objects.new(row['Name'],meshes[color]);coll.objects.link(obj)
        obj.location=basis@(rotate@(Vector(row['Offset'])*scale)+Vector(offset)-shift)
        sx,sy,sz=row['Size'];obj.scale=(sx*scale,sz*scale,sy*scale)
        obj.rotation_euler=(basis@rotate@Matrix.Rotation(math.radians(row['Angle']),3,'Z')@basis.transposed()).to_euler()
        obj['RobloxPartName']=row['Name'];obj['KnifeRole']=row['Role'] or ''

show=[d for d in data if d['Group']!='plates']
lair_knives={'Frank':['RustyShank','KitchenKnife','PocketKnife'], 'Ivy':['HunterBlade','Switchblade','ThornDagger'],
 'Sam':['Cleaver','Machete','BoneCarver'],'Leo':['GoldenDagger','Katana','Reaper'],
 'Ruby':['InfernoFang','MagmaCleaver','DemonHorn'],'Kate':['ZeusBolt','AthenaBlade','OlympusEdge'],
 'Zoe':['HaloBlade','SeraphSword','AngelFeather'],'Nick':['VoidEdge','StarCleaver','GalaxyKatana']}
for design in show:
    coll=bpy.data.collections.new(design['Name']);bpy.context.scene.collection.children.link(coll);collections.append(coll)
    blocks(coll,design['Name'])
    if design['Group']=='lairs':
        boss=design['Name'][4:]
        for i,x in enumerate((-16,-8,0,8,16)):
            blocks(coll,'LairPlate'+boss,(x,.8,0))
            # Preview display knives stay in the game's five existing slot origins.
            knife=lair_knives[boss][i%3]
            blocks(coll,knife,(x,6,0),6/max(bounds(knife)[1]),tilt=math.radians(28),center=True)
    if design['Name']=='EventBoardDecor':
        # The exact existing blank UI canvas is included, with no UI text changes.
        specs['BoardCanvas']=dict(Parts=[dict(Name='EventBoard',Size=[52,15,1.4],Offset=[0,22.3,0],Color=[28,38,60],Role=None,Angle=0)])
        blocks(coll,'BoardCanvas')
    if design['Name']=='ShopMortimer':
        for i,knife in enumerate(('KitchenKnife','Katana','InfernoFang','VoidEdge')):blocks(coll,knife,(-3+i*2,6,2),2.6/max(bounds(knife)[1]),yaw=math.pi,tilt=math.radians(15))
        for i,x in enumerate((-3.5,-1.8,3.3)):blocks(coll,'FreeChest',(x,4.4,-3),.5,yaw=math.radians(180+(i-1)*15),wood=[(203,57,57),(77,151,98),(190,78,165)][i])
    bpy.ops.object.select_all(action='DESELECT')
    for obj in coll.objects:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'models'/f"{design['Name']}.glb"),use_selection=True)
    bpy.ops.object.select_all(action='DESELECT')
    coll.hide_render=True;coll.hide_viewport=True

scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=768;scene.render.resolution_y=768;scene.render.resolution_percentage=100
scene.view_settings.view_transform='Standard';scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.8,.8,.8,1)
scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.8
bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';scene.camera=cam
bpy.ops.mesh.primitive_plane_add(size=1000,location=(0,0,-1.02));ground=bpy.context.object
mat=bpy.data.materials.new('Preview gray');mat.diffuse_color=(.8,.82,.84,1);ground.data.materials.append(mat)
for pos,energy,size in [((15,-40,60),1800,35),((-30,-5,40),1200,25),((0,30,50),2000,30)]:
    bpy.ops.object.light_add(type='AREA',location=pos);light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((0,0,10))-light.location).to_track_quat('-Z','Y').to_euler()
for design,coll in zip(show,collections):
    if only and design['Name'] not in only:continue
    coll.hide_render=False
    vertices=[obj.matrix_world@Vector(v) for obj in coll.objects for v in obj.bound_box]
    lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
    center=(lo+hi)/2;size=hi-lo
    if design['Group']=='knives':
        direction=Vector((.20,1,.15));cam.data.ortho_scale=max(size.z*1.24,size.x*1.5);ground.location.z=lo.z-.01
    elif design['Group']=='lucky':
        direction=Vector((.7,1,.62));cam.data.ortho_scale=5.8;ground.location.z=lo.z-.01
    else:
        direction=Vector((.22,1,.40));cam.data.ortho_scale=max(size.x*1.21,size.z*1.4);ground.location.z=lo.z-.01
        if design['Group']=='shops':direction=Vector((.4,1,.24))
    cam.location=center+direction.normalized()*150
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/'previews'/f"{design['Name']}.png")
    bpy.ops.render.render(write_still=True);coll.hide_render=True
collections[0].hide_render=False;collections[0].hide_viewport=False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'toy-assets.blend'))
