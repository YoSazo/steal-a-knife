"""Add upload IDs and write the standalone Lucky Wheel artwork config."""
from pathlib import Path
import json

root=Path(__file__).resolve().parents[1]
pack=root/'assets/lucky-wheel-art'
manifest=json.loads((pack/'manifest.json').read_text(encoding='utf-8'))
uploads=json.loads((pack/'uploads.json').read_text(encoding='utf-8'))
lines=['--!strict','-- Three transparent artwork layers only. Dynamic prize wedges stay code-drawn.',
    '-- Pixel coordinates are measured against a 512 x 512 rim canvas; Claude wires the UI.',
    'export type Asset = { Image: string, AssetId: number, Size: Vector2, SliceCenter: Rect? }',
    'local assets: { [string]: Asset } = {']
for row in manifest['Assets']:
    name=row['Name']
    image=uploads[name]
    row.update(Image=image,AssetId=int(image.split('://')[1]))
    lines += [f'\t{name} = {{',f'\t\tImage = "{image}",',f'\t\tAssetId = {row["AssetId"]},',
        '\t\tSize = Vector2.new(512, 512),','\t},']
rim=next(row for row in manifest['Assets'] if row['Name']=='WheelRim')
pointer=next(row for row in manifest['Assets'] if row['Name']=='WheelPointer')
lines += ['}','', 'return {','\tVersion = 1,','\tAssets = assets,','\tImages = {',
    '\t\tWheelRim = assets.WheelRim.Image,','\t\tWheelPointer = assets.WheelPointer.Image,',
    '\t\tWheelHub = assets.WheelHub.Image,','\t},','\tLayout = {',
    '\t\tReferenceSize = Vector2.new(512, 512),','\t\tWheelCenter = Vector2.new(256, 256),',
    f'\t\tWedgeRadius = {rim["RecommendedWedgeRadius"]},',
    '\t\tPointerCanvasSize = Vector2.new(96, 96),',
    f'\t\tPointerTip = Vector2.new({pointer["Tip"][0]}, {pointer["Tip"][1]}),',
    f'\t\tPointerTipTarget = Vector2.new({rim["RecommendedPointerTip"][0]}, {rim["RecommendedPointerTip"][1]}),',
    '\t\tHubCanvasSize = Vector2.new(112, 112),','\t},','}']
(root/'src/shared/Config/LuckyWheelArt.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(pack/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('Wrote three uploaded assets and measured layout hints to Config/LuckyWheelArt.luau')
