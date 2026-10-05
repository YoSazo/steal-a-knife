"""Compose review sheets without recolouring or repainting references or Studio captures."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import json, hashlib

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/biome-shells/OuterSpace'
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
    draw.text((20,48),f"Nick / The Void Walker / SpaceHelmet | {geo['PartCount']} full / {geo['LowPartCount']} low | six atomic models",font=small,fill=FG)
    for i,(name,im) in enumerate(zip(views,ims)):
        im=ImageOps.contain(im,(632,height),Image.Resampling.LANCZOS)
        sheet.paste(im,(20+i*644,80));draw.text((20+i*644,87+height),name.upper(),font=small,fill=FG)
    sheet.save(OUT/target)

gallery('studio','.jpg','gallery.png','OUTER SPACE — ACTUAL STUDIO / GAME LIGHTING 13.5 / ATMOSPHERE 0.32 / HAZE 2 / BLOOM 1')
gallery('renders','.png','geometry-gallery.png','OUTER SPACE — EXACT NATIVE BLOCK GEOMETRY / NEUTRAL BLENDER LIGHTING')
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
draw.text((20,16),'OUTER SPACE — MEASURED PLAN AND COMPLETE WALL ELEVATIONS',font=font,fill=FG)
for i,name in enumerate(('top','left-wall','right-wall')):
    im=Image.open(OUT/'renders'/f'{name}.png').convert('RGB').resize((632,632),Image.Resampling.LANCZOS)
    layout.paste(im,(20+i*644,65));draw.text((20+i*644,705),name.upper(),font=small,fill=FG)
for i,line in enumerate(('World origin (0,0,1540) / 160 x 220 / existing 120-high walls. Centre 112 studs clear.',
    'Nick world (73,0,1672) / reserved right-side approach X62..80, local Z105..159, Y<32.',
    'Entrance touches all 75 HeavensExit_ structural profile faces; 3-stud decorative seam collar. No collision changes.')):
    draw.text((20,760+i*36),line,font=small,fill=FG)
layout.save(OUT/'layout-gallery.png')

files=[ROOT/'src/shared/Assets/OuterSpaceShell.luau',ROOT/'src/shared/Config/OuterSpaceArt.luau',ROOT/'src/shared/Config/ToyGeometry/OuterSpaceShellData.luau']
files+=list((ROOT/'src/shared/Config/ToyGeometry/OuterSpaceShell').glob('*.luau'))
manifest={'Zone':'Outer Space','Index':8,'Rarity':'Cosmic','Boss':'Nick','BossTitle':'The Void Walker','BossWear':['SpaceHelmet'],
    'PartCount':geo['PartCount'],'LowPartCount':geo['LowPartCount'],'FinePartCount':geo['FinePartCount'],
    'Groups':{name:{'GeometryParts':len(rows),'PivotParts':1,'LowGeometryParts':sum(not p.get('Detail') for p in rows)} for name,rows in geo['Groups'].items()},
    'RootPivotParts':1,'Origin':geo['Origin'],'FrontAxis':geo['FrontAxis'],'ReservedLair':geo['ReservedLair'],'Seam':geo['Seam'],
    'SeamNamePolicy':'Canonical original Gate identity; full upstream name retained in PreviousExitName',
    'StudioCameras':{
        'entrance':{'Position':[0,20,1512],'Target':[-8,50,1712],'Fov':68},
        'mid':{'Position':[-30,44,1640],'Target':[67,75,1672],'Fov':80},
        'landmark':{'Position':[40,48,1702],'Target':[-64,75,1721],'Fov':80}},
    'RepositoryChecks':{'AssetSelene':'0 errors, 0 warnings','AssetFormatting':'pass','RepositoryFormatting':'pass',
        'RepositorySelene':'0 errors, 3 existing warnings: Effects.luau:977 unused dt; ZoneLighting.luau:289 mood shadowing; Hud.luau:1177 toast shadowing',
        'LuauLsp':'pass; watched-file automatic registration unavailable',
        'RojoSourcemap':'pass','StandaloneRojoBuild':'pass','DefaultProjectRojoBuild':'pass'},
    'Budget':{'FullMax':1500,'LowMax':800},'WaterAssetId':103379861470897,
    'StudioVerification':json.loads((OUT/'studio-verification.json').read_text()),
    'Lighting':{'ClockTime':13.5,'GeographicLatitude':3,'Brightness':3,'AtmosphereDensity':.32,'AtmosphereColor':[199,236,255],'AtmosphereDecay':[92,196,230],'AtmosphereOffset':.25,'AtmosphereGlare':4,'AtmosphereHaze':2,'BloomIntensity':1,'BloomSize':56,'BloomThreshold':1.6,'SunRaysIntensity':.28,'SunRaysSpread':.85,'LightingStyle':'Soft (live Studio value)'},
    'Preview':'Native Studio screenshots at the real zone origin; temporary geometry removed and original lighting/camera restored. Studio left in Edit after it independently returned to Edit during captures.',
    'ReferenceCrops':{name:{'File':'references/Views.png','Rect':list(rect)} for name,rect in zip(views,rects)},
    'KnownLimits':['Real Studio captures use the intended strong cyan atmosphere without recolouring; distance tint is visible.',
        'Generated perspective/layout varies; this is a budgeted reconstruction, not a pixel-perfect match.',
        'Detail=false builds 715 actual parts; runtime visibility LOD hides 648 parts but retains those instances.',
        'Phone FPS is not benchmarked. MapService registration remains with Claude.'],
    'Files':{str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'Gallery':str(OUT/'gallery.png'),'Parts':geo['PartCount'],'Low':geo['LowPartCount'],'ReferenceSize':list(ref.size),'CropRects':rects}))
