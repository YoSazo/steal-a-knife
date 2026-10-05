"""Print a detached Studio source/context packet; never edits integration or a running game."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
paths=['Assets/HeavensShell','Config/HeavensArt','Config/Textures','Config/GameConfig','Config/ToyGeometry/HeavensShellData']
paths += ['Config/ToyGeometry/HeavensShell/'+p.stem for p in sorted((ROOT/'src/shared/Config/ToyGeometry/HeavensShell').glob('*.luau'))]
sources={p:(ROOT/'src/shared'/f'{p}.luau').read_text() for p in paths}
sources['Verification']=(ROOT/'tests/HeavensShell.studio.luau').read_text()
old=json.loads((ROOT/'assets/biome-shells/MountOlympus/geometry.json').read_text())
exit=[p for p in old['Groups']['Exit'] if p['Name'].startswith('OlympusExit_')]
def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
sources['PreviousExit']='return '+lua(exit)
context=[]
for rows in old['Groups'].values():
    for p in rows:
        if p.get('Hidden'):continue
        x,y,z=p['Offset'];sx,sy,sz=p['Size'];lo=max(z-sz/2,190);hi=min(z+sz/2,220)
        if hi<=lo:continue
        r=dict(p);r['Offset']=[x,y,(lo+hi)/2-220];r['Size']=[sx,sy,hi-lo];context.append(r)
lair=[]
s=(ROOT/'src/shared/Config/ToyGeometry/LairZoe.luau').read_text()
for m in re.finditer(r'Name\s*=\s*"([^"]+)".*?Size\s*=\s*Vector3.new\(([^)]+)\).*?Offset\s*=\s*Vector3.new\(([^)]+)\).*?Color\s*=\s*Color3.fromRGB\(([^)]+)\)',s,re.S):
    name,sizes,offsets,colors=m.groups();sx,sy,sz=[float(v) for v in sizes.split(',')];lx,ly,lz=[float(v) for v in offsets.split(',')]
    lair.append({'Name':name,'Size':[sz,sy,sx],'Offset':[-73-lz,ly,132+lx],'Color':[int(v) for v in colors.split(',')]})
print(json.dumps({'Sources':sources,'PreviousContext':context,'LairContext':lair}))
