"""Compose review sheets without recolouring or repainting references or Studio captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import json, hashlib

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/biome-shells/Inferno'
geo=json.loads((OUT/'geometry.json').read_text())
BG=(16,27,31);FG=(240,238,221)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',25)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',19)
views=('entrance','mid','landmark')

def gallery(folder,extension,target,title):
    ims=[Image.open(OUT/folder/(name+extension)).convert('RGB') for name in views]
    height=round(632*ims[0].height/ims[0].width)
    sheet=Image.new('RGB',(1952,height+132),BG);draw=ImageDraw.Draw(sheet)
    draw.text((20,12),title,font=font,fill=FG)
    draw.text((20,48),f"Ruby / The Firestarter / Devil Horns | {geo['PartCount']} full / {geo['LowPartCount']} low | six atomic models",font=small,fill=FG)
    for i,(name,im) in enumerate(zip(views,ims)):
        im=ImageOps.contain(im,(632,height),Image.Resampling.LANCZOS)
        sheet.paste(im,(20+i*644,80));draw.text((20+i*644,87+height),name.upper(),font=small,fill=FG)
    sheet.save(OUT/target)

gallery('studio','.jpg','gallery.png','INFERNO — ACTUAL STUDIO / GAME LIGHTING 13.5 / ATMOSPHERE 0.32 / HAZE 2 / BLOOM 1')
gallery('renders','.png','geometry-gallery.png','INFERNO — EXACT NATIVE BLOCK GEOMETRY / NEUTRAL BLENDER LIGHTING')
ref=Image.open(OUT/'references/Views.png').convert('RGB')
px=ref.load();white=[x for x in range(100,ref.width-100) if sum(min(px[x,y])>220 for y in range(ref.height))>ref.height*.99]
runs=[]
for x in white:
    if not runs or x>runs[-1][-1]+1:runs.append([x])
    else:runs[-1].append(x)
assert len(runs)==2,(ref.size,runs)
rects=((0,0,runs[0][0],ref.height),(runs[0][-1]+1,0,runs[1][0],ref.height),(runs[1][-1]+1,0,ref.width,ref.height))
comparison=Image.new('RGB',(1656,2550),BG);draw=ImageDraw.Draw(comparison)
draw.text((20,16),'GENERATED REFERENCE',font=font,fill=FG);draw.text((844,16),'NATIVE STUDIO / REAL GAME LIGHTING',font=font,fill=FG)
for i,(name,rect) in enumerate(zip(views,rects)):
    y=60+i*820
    a=ImageOps.contain(ref.crop(rect),(800,780),Image.Resampling.LANCZOS)
    b=ImageOps.contain(Image.open(OUT/'studio'/f'{name}.jpg').convert('RGB'),(800,780),Image.Resampling.LANCZOS)
    comparison.paste(a,(20+(800-a.width)//2,y+(780-a.height)//2));comparison.paste(b,(844+(800-b.width)//2,y+(780-b.height)//2))
    draw.text((20,y+785),name.upper(),font=small,fill=FG)
draw.text((20,2520),'Measured game coordinates retained. Budgeted block build; generated reference is not an exact camera/pixel match.',font=small,fill=FG)
comparison.save(OUT/'comparison.png')

layout=Image.new('RGB',(1952,890),BG);draw=ImageDraw.Draw(layout)
draw.text((20,16),'INFERNO — MEASURED PLAN AND COMPLETE WALL ELEVATIONS',font=font,fill=FG)
for i,name in enumerate(('top','left-wall','right-wall')):
    im=Image.open(OUT/'renders'/f'{name}.png').convert('RGB').resize((632,632),Image.Resampling.LANCZOS)
    layout.paste(im,(20+i*644,65));draw.text((20+i*644,705),name.upper(),font=small,fill=FG)
for i,line in enumerate(('World origin (0,0,880) / 160 x 220 / existing 120-high walls. Centre 112 studs clear.',
    'Ruby world (-73,0,1012) / reserved left-side approach X-80..-62, local Z105..159, Y<32.',
    'Entrance touches all 75 CatacombExit_ structural profile faces; 3-stud decorative seam collar. No collision changes.')):
    draw.text((20,760+i*36),line,font=small,fill=FG)
layout.save(OUT/'layout-gallery.png')

files=[ROOT/'src/shared/Assets/InfernoShell.luau',ROOT/'src/shared/Config/InfernoArt.luau',ROOT/'src/shared/Config/ToyGeometry/InfernoShellData.luau']
files+=list((ROOT/'src/shared/Config/ToyGeometry/InfernoShell').glob('*.luau'))
manifest={'Zone':'Inferno','Index':5,'Rarity':'Mythic','Boss':'Ruby','BossTitle':'The Firestarter','BossWear':['DevilHorns'],
    'PartCount':geo['PartCount'],'LowPartCount':geo['LowPartCount'],'FinePartCount':geo['FinePartCount'],
    'Groups':{name:{'GeometryParts':len(rows),'PivotParts':1,'LowGeometryParts':sum(not p.get('Detail') for p in rows)} for name,rows in geo['Groups'].items()},
    'RootPivotParts':1,'Origin':geo['Origin'],'FrontAxis':geo['FrontAxis'],'ReservedLair':geo['ReservedLair'],'Seam':geo['Seam'],
    'Budget':{'FullMax':1500,'LowMax':800},'WaterAssetId':103379861470897,
    'StudioVerification':json.loads((OUT/'studio-verification.json').read_text()),
    'Lighting':{'ClockTime':13.5,'GeographicLatitude':3,'Brightness':3,'AtmosphereDensity':.32,'AtmosphereColor':[199,236,255],'AtmosphereDecay':[92,196,230],'AtmosphereOffset':.25,'AtmosphereGlare':4,'AtmosphereHaze':2,'BloomIntensity':1,'BloomSize':56,'BloomThreshold':1.6,'SunRaysIntensity':.28,'SunRaysSpread':.85,'LightingStyle':'Soft (live Studio value)'},
    'Preview':'Native Studio screenshots at the real zone origin; native game editor at the real zone origin; temporary geometry removed, original lighting restored and Play resumed.',
    'ReferenceCrops':{name:{'File':'references/Views.png','Rect':list(rect)} for name,rect in zip(views,rects)},
    'KnownLimits':['Real Studio captures use the intended strong cyan atmosphere without recolouring; distance tint is visible.',
        'Generated perspective/layout varies; this is a budgeted reconstruction, not a pixel-perfect match.',
        'Detail=false builds 588 actual parts; runtime visibility LOD hides 793 parts but retains those instances.',
        'Phone FPS is not benchmarked. MapService registration remains with Claude.'],
    'Files':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'Gallery':str(OUT/'gallery.png'),'Parts':geo['PartCount'],'Low':geo['LowPartCount'],'ReferenceSize':list(ref.size),'CropRects':rects}))
