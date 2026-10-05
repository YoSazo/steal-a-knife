"""Confirm Roblox's model upload preserves native mesh vertex colours, without textures."""
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/boss-titles/models'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.mesh.primitive_cube_add()
obj=bpy.context.object;obj.name='VertexProbe'
layer=obj.data.color_attributes.new(name='Color',type='BYTE_COLOR',domain='CORNER')
obj.data.color_attributes.active_color=layer
colors=[(1,0,0,1),(0,1,0,1),(0,0,1,1),(1,1,0,1),(1,0,1,1),(0,1,1,1)]
for polygon,color in zip(obj.data.polygons,colors):
    for loop in polygon.loop_indices:layer.data[loop].color_srgb=color
material=bpy.data.materials.new('Native vertex paint');material.use_nodes=True
node=material.node_tree.nodes.new('ShaderNodeVertexColor');node.layer_name='Color'
material.node_tree.links.new(node.outputs['Color'],material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
obj.data.materials.append(material)
bpy.ops.export_scene.fbx(filepath=str(OUT/'vertex-probe.fbx'),use_selection=True,object_types={'MESH'},axis_forward='Z',axis_up='Y',apply_scale_options='FBX_SCALE_UNITS',colors_type='SRGB',prioritize_active_color=True)
