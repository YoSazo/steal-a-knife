"""Package exact geometry renders and unmodified generated reference crops for review."""
from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Courtyard'
font_path='C:/Windows/Fonts/arial.ttf'
font=ImageFont.truetype(font_path,26)
small=ImageFont.truetype(font_path,20)
data=json.loads((OUT/'geometry.json').read_text())
BG=(18,28,34);FG=(244,241,225)
views=('entrance','mid','landmark')
gallery=Image.new('RGB',(1952,744),BG)
draw=ImageDraw.Draw(gallery)
draw.text((20,14),'FRANK / THE GROUNDSKEEPER — COURTYARD NATIVE BLOCK BUILD',font=font,fill=FG)
draw.text((20,51),'2,428 full parts | 1,321 low-detail parts | six atomic sections | measured 160 x 220 studs',font=small,fill=FG)
for i,name in enumerate(views):
    image=Image.open(OUT/'renders'/f'{name}.png').convert('RGB').resize((632,632),Image.Resampling.LANCZOS)
    gallery.paste(image,(20+i*644,88));draw.text((30+i*644,694),name.upper(),font=small,fill=BG)
gallery.save(OUT/'gallery.png')

source=Image.open(OUT/'references/Views.png').convert('RGB')
rects=((0,0,804,727),(812,0,1544,727),(1552,0,2164,727))
comparison=Image.new('RGB',(1656,2550),BG);draw=ImageDraw.Draw(comparison)
draw.text((20,15),'ORIGINAL GENERATED REFERENCE',font=font,fill=FG)
draw.text((844,15),'ACTUAL SHARED BLOCK GEOMETRY',font=font,fill=FG)
for i,(name,rect) in enumerate(zip(views,rects)):
    y=60+i*820
    a=ImageOps.contain(source.crop(rect),(800,780),Image.Resampling.LANCZOS)
    b=Image.open(OUT/'renders'/f'{name}.png').convert('RGB').resize((800,800),Image.Resampling.LANCZOS)
    comparison.paste(a,(20+(800-a.width)//2,y+(800-a.height)//2));comparison.paste(b,(844,y))
    draw.text((24,y+780),name.upper(),font=small,fill=FG)
draw.text((20,2520),'Style comparison, not a pixel match: generated cameras/layout drift; original game coordinates are retained.',font=small,fill=FG)
comparison.save(OUT/'comparison.png')

measurements=Image.new('RGB',(1952,1120),BG);draw=ImageDraw.Draw(measurements)
draw.text((20,16),'MEASURED LAYOUT + COMPLETE WALL ELEVATIONS',font=font,fill=FG)
for i,name in enumerate(('top','left-wall','right-wall')):
    im=Image.open(OUT/'renders'/f'{name}.png').convert('RGB').resize((632,632),Image.Resampling.LANCZOS)
    measurements.paste(im,(20+i*644,65));draw.text((20+i*644,705),name.upper(),font=small,fill=FG)
lines=[
    'Playable box: X -80..80 / Z 0..220; existing boundary wall height 120.',
    'Centre 112 studs stay flat. Lowest cross-lane arch block: Y 70. Existing exit stays open.',
    'Frank stays at (-73, 0, 132). Reserved approach: X -80..-62 / Z 105..159 / Y below 32.',
    'Fountain: right-coordinate wall, X 68 / Z 195. Frank\'s unchanged shed is context only.',
    'All shell parts are anchored, non-colliding, non-touching and non-queryable.',
    'Preview uses the exact builder data. Studio runtime tests passed; phone FPS is not benchmarked.',
]
for i,line in enumerate(lines):draw.text((20,766+i*48),line,font=small,fill=FG)
measurements.save(OUT/'layout-gallery.png')

files=[ROOT/'src/shared/Assets/CourtyardShell.luau',ROOT/'src/shared/Config/CourtyardArt.luau',ROOT/'src/shared/Config/ToyGeometry/CourtyardShellData.luau']
files+=list((ROOT/'src/shared/Config/ToyGeometry/CourtyardShell').glob('*.luau'))
manifest={
    'Boss':'Frank','BossTitle':'The Groundskeeper','Zone':'Courtyard',
    'Status':'First-zone asset review; not integrated',
    'PartCount':data['PartCount'],'LowPartCount':data['LowPartCount'],'FinePartCount':data['FinePartCount'],
    'Groups':{k:{'GeometryParts':len(v),'PivotParts':1,'FineParts':sum(bool(p.get('Detail')) for p in v)} for k,v in data['Groups'].items()},
    'AssemblyPivotParts':1,'Origin':[0,0,0],'FrontAxis':'-Z; travel axis +Z',
    'WaterAssetId':103379861470897,'WaterTextureSize':[512,512],
    'StudioVerification':{'Passed':13638,'FullParts':2428,'LowParts':1321,'FineParts':1107,'AtomicGroups':6,'WaterFaces':12,'AmbientEmitters':2},
    'ReferenceCrops':{name:{'File':'references/Views.png','Rect':list(rect)} for name,rect in zip(views,rects)},
    'KnownLimitations':['Generated reference perspectives and lair/fountain screen-side placement are not metrically consistent; this is not a 1:1 pixel match.',
        'Blender previews use the exact native geometry but are not Studio screenshots.',
        'Water animation and geometry LOD require Claude-owned client hooks.',
        'Water image uploaded successfully; Edit-mode preload did not complete during the verification window.',
        'No phone frame-rate benchmark or live-world integration was performed.'],
    'Files':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'Gallery':str(OUT/'gallery.png'),'PartCount':data['PartCount'],'LowPartCount':data['LowPartCount']}))
