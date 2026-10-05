"""Write the standalone art manifest; no game integration is changed."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
pack = root / 'assets/voxel-icons-2'
manifest = json.loads((pack / 'manifest.json').read_text(encoding='utf-8'))
uploads = json.loads((pack / 'uploads.json').read_text(encoding='utf-8'))
powers = ['Vanish','Radar','BearTrap','Shield','Decoy','Flash','Barricade','Mimic']
lines = ['--!strict', '-- Transparent icon art only. Claude builds and wires the simple menus/world signs.',
    '-- Wheel is the training/hamster wheel; use the existing VoxelUi.Hud.Spin for the prize wheel.',
    'export type Asset = { Image: string, AssetId: number, Size: Vector2, File: string }',
    'local assets: { [string]: Asset } = {']
for row in manifest['Assets']:
    name = row['Name']
    image = uploads[name]
    asset_id = int(image.split('://')[1])
    row.update(Image=image, AssetId=asset_id)
    lines += [f'\t["{name}"] = {{',f'\t\tImage = "{image}",',f'\t\tAssetId = {asset_id},',
        '\t\tSize = Vector2.new(512, 512),',f'\t\tFile = "assets/voxel-icons-2/{row["File"]}",','\t},']
lines += ['}', '', 'local icons: { [string]: string } = {}',
    'for name, asset in assets do', '\ticons[name] = asset.Image', 'end', '',
    'local powers: { [string]: string } = {']
for name in powers:
    lines.append(f'\t{name} = icons.{name},')
lines += ['\t["Bear Trap"] = icons.BearTrap,','}', '', 'return {', '\tVersion = 1,',
    '\tAssets = assets,','\tIcons = icons,','\tPowers = powers,','}']
(root/'src/shared/Config/VoxelIcons2.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(pack/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(f'Wrote {len(manifest["Assets"])} uploaded icon records')
