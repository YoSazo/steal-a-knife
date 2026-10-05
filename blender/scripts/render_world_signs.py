"""Render the exact shared cuboids used by WorldSignModel, one gallery image per group."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'assets/world-signs'
GEOMETRY=json.loads((OUT/'geometry.json').read_text())['Signs']
(OUT/'renders').mkdir(exist_ok=True)
scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH'
scene.render.resolution_x=1200;scene.render.resolution_y=750;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
scene.view_settings.view_transform='Standard'
shade=scene.display.shading;shade.light='FLAT';shade.studiolight_rotate_z=.5;shade.color_type='MATERIAL'
shade.show_shadows=False;shade.show_cavity=True;shade.cavity_type='BOTH';shade.curvature_ridge_factor=1.2;shade.curvature_valley_factor=1.3
shade.show_object_outline=True;shade.object_outline_color=(.06,.08,.12)
materials={}
def mat(c):
 key=tuple(c)
 if key not in materials:
  m=bpy.data.materials.new(str(key));m.diffuse_color=tuple(v/255 for v in c)+(1,);materials[key]=m
 return materials[key]
def box(name,pos,size,color):
 bpy.ops.mesh.primitive_cube_add(size=1,location=(pos[0],-pos[2],pos[1]))
 obj=bpy.context.object;obj.name=name;obj.scale=(size[0],size[2],size[1]);obj.data.materials.append(mat(color));return obj
for name,spec in GEOMETRY.items():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 w,h=spec['Width'],spec['Height']
 for p in spec['Parts']:box(p['Name'],p['Position'],p['Size'],p['Color'])
 if name not in ('CollectPad','SellSign'):box('Backing',(0,0,-.12),(w,h,.4),spec['FaceColor'])
 fh=h*(.18 if name=='HauntedWheel' else .39 if name=='VaultOwner' else .23 if name=='FreeChestLabel' else .77)
 fy=h*(-.4 if name=='HauntedWheel' else -.24 if name=='VaultOwner' else -.34 if name=='FreeChestLabel' else 0)
 if name not in ('ShopMortimer','ShopVesper','SafeZone','ProjectorScreen'):
  box('LiveTextFace',(0,fy,.39),(w*(.83 if name in ('CollectPad','SellSign') else .91),fh,.08),spec['FaceColor'])
 objs=[o for o in scene.objects if o.type=='MESH']
 coords=[o.matrix_world@Vector(v) for o in objs for v in o.bound_box]
 lo=Vector(tuple(min(v[i] for v in coords) for i in range(3)));hi=Vector(tuple(max(v[i] for v in coords) for i in range(3)));center=(lo+hi)/2
 extent=hi-lo
 bpy.ops.object.camera_add(location=center+Vector((w*.13,-w*2.2,w*.55)))
 camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=max(extent.z*1.6,extent.x)*1.35
 camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
 scene.render.filepath=str(OUT/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'renders'/f'{name}.blend'))
print('Rendered',len(GEOMETRY),'physical sign groups from the runtime cuboids')
