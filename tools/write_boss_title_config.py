"""Record uploaded boss title models, their canvas bounds and native vertex colours."""
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/boss-titles'
geometry=json.loads((OUT/'geometry.json').read_text())['Designs']
layout=json.loads((OUT/'mesh-layout.json').read_text())
uploads=json.loads((ROOT/'blender/uploaded_assets.json').read_text())
version=hashlib.sha256((OUT/'geometry.json').read_bytes()+b''.join((OUT/'models'/f'{d["Boss"]}.fbx').read_bytes() for d in geometry)).hexdigest()[:16]
lines=['--!strict','-- Voxel relief meshes traced at the original 1024px/768px canvas resolution.',
       '-- Colours are baked into mesh vertices. No image textures or SurfaceGuis.',
       'export type Chunk = { Name: string, Surface: string, Size: Vector3, Offset: Vector3, Voxels: number }',
       'export type Design = { AssetId: number, Stash: string, Title: string, Chunks: { Chunk } }',
       'local designs: { [string]: Design } = {']
records=[]
for index,(design,model) in enumerate(zip(geometry,layout),1):
    boss=design['Boss'];assert model['Boss']==boss
    upload=uploads['BossTitle_'+boss]
    asset=int(upload['assetId']);assert asset>0
    lines += [f'\t{boss} = {{',f'\t\tAssetId = {asset},',f'\t\tStash = "{design["Stash"]}",',f'\t\tTitle = "{design["Title"]}",','\t\tChunks = {']
    for c in model['Chunks']:
        lines += ['\t\t\t{',f'\t\t\t\tName = "{c["Name"]}",',f'\t\t\t\tSurface = "{c["Surface"]}",','\t\t\t\tSize = Vector3.new('+', '.join(map(str,c['Size']))+'),','\t\t\t\tOffset = Vector3.new('+', '.join(map(str,c['Offset']))+'),',f'\t\t\t\tVoxels = {c["VoxelCount"]},','\t\t\t},']
    lines += ['\t\t},','\t},']
    records.append({**design,**model,'AssetId':asset,'ModelSHA256':hashlib.sha256((OUT/'models'/f'{boss}.fbx').read_bytes()).hexdigest()})
lines += ['}',f'return {{ Version = "{version}", Designs = designs }}']
(ROOT/'src/shared/Config/BossTitles.luau').write_text('\n'.join(lines)+'\n')
(OUT/'manifest.json').write_text(json.dumps(dict(Version=version,Designs=records),indent=2))
print('Recorded',len(records),'uploaded boss title models')
