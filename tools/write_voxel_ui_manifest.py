"""Publish only art configuration after every individual PNG has an upload ID."""
import hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/voxel-ui"
catalog = json.loads((OUT / "catalog.json").read_text())
uploads = json.loads((OUT / "uploads.json").read_text())
assets = catalog["Assets"]
assert len(uploads) == len(assets)
assert len(assets) in (82, 106, 107)
lines = ['--!strict', '-- Standalone voxel UI art. UI layouts and behaviours are wired by the caller.',
 'export type Asset = { Image: string, AssetId: number, Size: Vector2, SliceCenter: Rect?, SliceScale: number? }',
 'local assets: { [string]: Asset } = {']
record = []
for e in assets:
    item = uploads[e["Id"]]
    uri = item["Image"]
    assert uri.startswith("rbxassetid://") and uri.removeprefix("rbxassetid://").isdigit(), (e["Id"],uri)
    asset_id = int(uri.removeprefix("rbxassetid://"))
    assert asset_id>0
    w,h=e["Size"]
    fields = [f'Image = "{uri}"', f'AssetId = {asset_id}',f'Size = Vector2.new({w}, {h})']
    if e["SliceCenter"]:
        fields.append('SliceCenter = Rect.new('+', '.join(map(str,e["SliceCenter"]))+')')
    if e.get('RecommendedSliceScale'):
        fields.append('SliceScale = '+str(e['RecommendedSliceScale']))
    lines.append(f'\t["{e["Id"]}"] = {{ '+', '.join(fields)+' },')
    record.append({**e,"Image":uri,"AssetId":asset_id,"SHA256":hashlib.sha256((OUT/e["File"]).read_bytes()).hexdigest()})
lines += ['}', 'return {', '\tVersion = '+str(catalog.get("Version",1))+',', '\tAssets = assets,']
for group in dict.fromkeys(e["Group"] for e in assets):
    lines.append(f'\t{group} = {{')
    for e in assets:
        if e["Group"]==group:
            lines.append(f'\t\t{e["Name"]} = assets["{e["Id"]}"].Image,')
    lines.append('\t},')
lines += ['\tRarityColors = {']
for name,color in catalog["RarityColors"].items():
    lines.append(f'\t\t{name} = Color3.fromRGB('+', '.join(map(str,color))+'),')
lines += ['\t},','}']
(ROOT/'src/shared/Config/VoxelUi.luau').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(OUT/'manifest.json').write_text(json.dumps(dict(Version=catalog.get("Version",1),Assets=record),indent=2),encoding='utf-8')
print(f"Wrote {len(record)} verified upload IDs and standalone knife configuration")
