"""Export the exterior of the source-pixel voxel union, painted with native vertex colours."""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/boss-titles'
designs=json.loads((OUT/'geometry.json').read_text())['Designs']
chosen=set(sys.argv[sys.argv.index('--')+1:]) if '--' in sys.argv else set()
(OUT/'models').mkdir(exist_ok=True);(OUT/'renders').mkdir(exist_ok=True)
scene=bpy.context.scene;scene.unit_settings.system='NONE'
scene.render.engine='BLENDER_EEVEE_NEXT'
scene.render.resolution_x=1600;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
scene.view_settings.view_transform='Standard';scene.world.color=(.8,.8,.8)
manifest=[]
for design in designs:
    if chosen and design['Boss'] not in chosen:continue
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes,bpy.data.materials):
        for item in list(datablocks):
            if item.users==0:datablocks.remove(item)
    exported=[];chunks=[]
    material=bpy.data.materials.new('NativeVoxelPaint');material.use_nodes=True
    nodes=material.node_tree.nodes;shader=nodes.get('Principled BSDF')
    colour=nodes.new('ShaderNodeVertexColor');colour.layer_name='Color'
    material.node_tree.links.new(colour.outputs['Color'],shader.inputs['Base Color'])
    material.node_tree.links.new(colour.outputs['Color'],shader.inputs['Emission Color'])
    shader.inputs['Emission Strength'].default_value=.7;shader.inputs['Roughness'].default_value=1
    for name,data in design['Surfaces'].items():
        width=26 if name=='Sign' else 16.12
        gw,gh=data['Grid'];height=width*gh/gw
        def point(px,py,depth):return Vector(((.5-px/gw)*width,depth,(.5-py/gh)*height))
        quads=[]
        def add(points,normal,rgb):
            if (points[1]-points[0]).cross(points[2]-points[0]).dot(Vector(normal))<0:points=list(reversed(points))
            quads.append((points,rgb))
        for x,y,w,h,key,depth in data['Rects']:
            add([point(x,y,depth),point(x+w,y,depth),point(x+w,y+h,depth),point(x,y+h,depth)],(0,1,0),data['Palette'][key%32])
        for x,y,w,h in data['Back']:
            add([point(x,y,0),point(x+w,y,0),point(x+w,y+h,0),point(x,y+h,0)],(0,-1,0),(20,24,36))
        for direction,line,start,span,low,high,index in data['Sides']:
            if direction in ('Left','Right'):
                points=[point(line,start,low),point(line,start+span,low),point(line,start+span,high),point(line,start,high)]
                normal=(1 if direction=='Left' else -1,0,0)
            else:
                points=[point(start,line,low),point(start+span,line,low),point(start+span,line,high),point(start,line,high)]
                normal=(0,0,1 if direction=='Top' else -1)
            add(points,normal,[round(c*.82) for c in data['Palette'][index]])
        for index,start in enumerate(range(0,len(quads),7000)):
            rows=quads[start:start+7000];verts=[];faces=[];uvs=[];colours=[]
            for points,rgb in rows:
                base=len(verts);verts.extend(points);faces.append(tuple(range(base,base+4)))
                for p in points:
                    uvs.append((.5-p.x/width,p.z/height+.5));colours.append(tuple(c/255 for c in rgb)+(1,))
            mesh=bpy.data.meshes.new(f'{name}_{index:03d}');mesh.from_pydata(verts,[],faces);mesh.update()
            uv=mesh.uv_layers.new(name='SourceCanvasCoordinates')
            for loop,value in zip(uv.data,uvs):loop.uv=value
            paint=mesh.color_attributes.new(name='Color',type='BYTE_COLOR',domain='CORNER')
            mesh.color_attributes.active_color=paint
            for loop,value in zip(paint.data,colours):loop.color_srgb=value
            mesh.materials.append(material)
            obj=bpy.data.objects.new(mesh.name,mesh);scene.collection.objects.link(obj);exported.append(obj)
            lo=Vector(tuple(min(v[i] for v in verts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in verts) for i in range(3)))
            chunks.append(dict(Name=obj.name,Surface=name,Size=[hi.x-lo.x,hi.z-lo.z,hi.y-lo.y],Offset=[(hi.x+lo.x)/2,(hi.z+lo.z)/2,-(hi.y+lo.y)/2],VoxelCount=sum(1 for _,rgb in rows),Triangles=len(rows)*2))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in exported:obj.select_set(True)
    bpy.ops.export_scene.fbx(filepath=str(OUT/'models'/f'{design["Boss"]}.fbx'),use_selection=True,object_types={'MESH'},axis_forward='Z',axis_up='Y',apply_scale_options='FBX_SCALE_UNITS',global_scale=1,bake_space_transform=True,path_mode='AUTO',colors_type='SRGB',prioritize_active_color=True)
    manifest.append(dict(Boss=design['Boss'],Chunks=chunks))
    for obj in exported:
        if obj.name.startswith('SignRibbon_'):obj.location=(0,.1,-4.293333333)
    bpy.ops.object.camera_add(location=(1.8,42,10));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=29
    camera.rotation_euler=(Vector((0,0,-1.5))-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
    bpy.ops.object.light_add(type='AREA',location=(-10,20,30));lamp=bpy.context.object;lamp.data.energy=1300;lamp.data.shape='DISK';lamp.data.size=20
    lamp.rotation_euler=(Vector((0,0,-1))-lamp.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/'renders'/f'{design["Boss"]}.png');bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'models'/f'{design["Boss"]}.blend'))
(OUT/'mesh-layout.json').write_text(json.dumps(manifest,indent=2))
print('Exported',len(manifest),'native-colour boss models; no image textures')
