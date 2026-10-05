"""Kate's Mount Olympus. Native cuboid asset authoring; Claude owns integration."""
from pathlib import Path
from collections import Counter
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/MountOlympus';OUT.mkdir(parents=True,exist_ok=True)
STONE=(162,151,126); MARBLE=(213,208,186); SHADE=(104,97,82); SHADOW=(39,37,43)
GOLD=(213,134,17); BRONZE=(96,65,23); BLUE=(25,52,121); BLUEHI=(37,71,155)
CORE=(255,241,153); HOT=(255,249,226); FLOOR=(136,132,116)
groups={n:[] for n in ('LeftWall','RightWall','Entrance','Exit','SunCrownShrine','Floor')}
counts=Counter();omitted=[]

def box(group,name,size,pos,color,detail=False,**flags):
    lo=[pos[i]-size[i]/2 for i in range(3)];hi=[pos[i]+size[i]/2 for i in range(3)]
    assert min(size)>0,name
    if lo[0]<80 and hi[0]>62 and lo[2]<159 and hi[2]>105 and lo[1]<32:
        omitted.append(name);return
    assert lo[2]>=(-3.001 if group=='Entrance' else -.001) and hi[2]<=220.001,(name,'depth',lo,hi)
    if group!='Floor' and lo[0]<56 and hi[0]>-56:assert lo[1]>=70,(name,'lane',lo)
    if group=='Floor':assert hi[1]<=.241,(name,'floor',hi)
    counts[(group,name)]+=1
    p={'Name':f'{name}_{counts[(group,name)]:03}','Size':[round(v,4) for v in size],'Offset':[round(v,4) for v in pos],'Color':list(color)}
    if detail:p['Detail']=True
    p.update(flags);groups[group].append(p)

def face(group,name,x,y,z,d,h,w,c,detail=False,**flags):box(group,name,(d,h,w),(x,y,z),c,detail,**flags)
def wall(side,name,u,y,z,d,h,w,c,detail=False,**flags):face('LeftWall' if side<0 else 'RightWall',name,side*(80-u),y,z,d,h,w,c,detail,**flags)

def crown(group,name,x,y,z,s,detail=False):
    # Flat crown emblem: all rows/tines touch; facing the runway along +/-X.
    inward=-1 if x>0 else 1
    face(group,name+'Base',x,y,z,.7*s,2*s,12*s,GOLD,detail)
    face(group,name+'LowerRim',x+inward*.1,y-1.4*s,z,.8*s,.8*s,12.5*s,BRONZE,detail)
    for shift,height in ((-5,5),(-2.5,3),(0,8),(2.5,3),(5,5)):
        face(group,name+'Tine',x,y+(height/2+.8)*s,z+shift*s,.7*s,height*s,2*s,GOLD,detail)
    face(group,name+'CentreJewel',x+inward*.45,y+6*s,z,.2*s,1.5*s,1.5*s,CORE,detail,Neon=True)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'MarbleRetainingBacking',-2,60,110,4,120,220,STONE)
    courses=(('ShadowFoundation',2.5,5,8,SHADE),('MarbleLowPlinth',6,2,10,MARBLE),
        ('GoldLowCornice',8,1.2,11,GOLD),('MarbleGalleryBand',32,3,8,MARBLE),('GoldGalleryLip',34,1,9,GOLD),
        ('UpperMarbleEntablature',101,6,10,MARBLE),('BronzeCorniceShadow',105,1,10,BRONZE),
        ('GoldUpperCornice',106.5,2,12,GOLD),('MarbleSkyline',116,12,8,MARBLE),('GoldSkylineLip',123,2,11,GOLD))
    for name,y,h,d,c in courses:
        spans=((0,104),(160,220)) if side>0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,name,2,y,(a+b)/2,d,h,b-a,c)
    piers=(10,44,80,116,152,210) if side<0 else (10,44,96,168,210)
    for z in piers:
        for y,h,d,w,c in ((5,4,12,13,SHADE),(8,2,12,14,GOLD),(12,6,10,11,MARBLE),
            (17,4,9,10,GOLD),(59,82,7,7,MARBLE),(101,2,9,10,GOLD),
            (104,4,11,13,MARBLE),(107,2,13,15,GOLD),(109,2,14,16,MARBLE)):
            wall(side,'GreekColumnLayer',6,y,z,d,h,w,c)
        for dz in (-2,0,2):wall(side,'FineColumnFlute',9.57,59,z+dz,.16,77,.3,SHADE,True)
        for dz in (-6,-2,2,6):wall(side,'CapitalGoldDentil',11.6,105,z+dz,.5,1.5,1.6,GOLD,True)
        wall(side,'GoldenLightOuterChute',9.7,58,z,.5,76,2.8,GOLD)
        wall(side,'GoldenLightWhiteCore',10.03,58,z,.2,76,1.2,CORE,Neon=True,WaterFace='Right' if side<0 else 'Left')
        for y in (19,97):wall(side,'ChuteMarbleSpout',11,y,z,4,2,5,MARBLE)
        for y in (35,75):wall(side,'FineLightShimmer',10.15,y,z,.08,5,.4,HOT,True,Neon=True)
        for i,w in enumerate((13,9,5)):
            wall(side,'SteppedRoofFinial',3,125.7+i*3.4,z,5,3.5,w,MARBLE)
        wall(side,'RoofGoldCap',3,134.6,z,5.5,1,5.5,GOLD)
    bays=((27,23),(62,23),(98,23),(134,23),(178,35)) if side<0 else ((27,23),(70,33),(184,27))
    for z,w in bays:
        wall(side,'TempleNicheShadow',1,62,z,2.05,61,w,SHADOW)
        wall(side,'RoyalBlueBanner',2,65,z,.5,52,w*.54,BLUE)
        for dz in (-w*.27,w*.27):wall(side,'BannerGoldSide',2.35,65,z+dz,.3,52,.8,GOLD)
        for i in range(5):
            wall(side,'BannerSteppedTail',2,38-i*1.6,z,.5,1.65,w*.54-i*w*.09,BLUE)
            for sign in (-1,1):wall(side,'BannerTailGoldTrim',2.35,38-i*1.6,z+sign*(w*.27-i*w*.045),.3,1.65,.8,GOLD,True)
        crown(group,'BannerCrown',side*77.4,63,z,1.05)
        for dz in (-w*.135,w*.135):wall(side,'BannerFineFold',2.22,68,z+dz,.1,37,.18,BLUEHI,True)
        wall(side,'TempleNicheLintel',4,94,z,7,4,w+5,MARBLE)
        wall(side,'TempleGoldLintel',8,91.5,z,.6,1,w+7,GOLD)
        for i in range(9):
            wall(side,'SteppedTemplePediment',5,96.5+i*1.5,z,6,1.55,w+8-i*(w+6)/9,MARBLE)
            if i%2==0:
                for sign in (-1,1):wall(side,'PedimentGoldEdge',8.3,96.5+i*1.5,z+sign*(w+8-i*(w+6)/9)/2,.45,3.05,2.6,GOLD,True)
        for dz in range(-int(w/2),int(w/2)+1,3):wall(side,'LintelFineDentil',8.5,92.5,z+dz,.5,1.5,1.5,GOLD,True)
        for y,h,d,ww,c in ((4,7,13,w*.82,SHADE),(8,1.5,15,w*.92,GOLD),(12,6,11,w*.72,MARBLE),(16,2,12,w*.78,GOLD)):
            wall(side,'PeripheralRoyalPlinth',11,y,z,d,h,ww,c)
        # A small crown cup and moving light, outside the lane and lair.
        wall(side,'RoyalCupStem',11,21,z,4,8,4,MARBLE)
        wall(side,'RoyalCupGoldBowl',11,26,z,7,3,9,GOLD)
        wall(side,'RoyalCupLight',11,32,z,3,10,4,CORE,Neon=True)
        for dz in (-3,0,3):wall(side,'CupCrownTine',11,29,z+dz,7,5,1.6,GOLD,True)
    spans=((0,168),(212,220)) if side<0 else ((0,104),(160,220))
    for a,b in spans:
        n=b-a;z=(a+b)/2
        box(group,'GoldenChannelShadow',(5,.6,n),(side*60,.6,z),BRONZE)
        box(group,'GoldenChannelOuter',(3.7,.15,n),(side*60,1,z),GOLD)
        box(group,'GoldenChannelCore',(2,.03,n),(side*60,1.09,z),CORE,Neon=True,WaterFace='Top')
        for x in (57.7,62.3):box(group,'MarbleChannelBank',(.8,.8,n),(side*x,.8,z),MARBLE)
        for zz in range(a+8,b-4,22):
            box(group,'LaneSideColumnPlinth',(2.2,4,2.2),(side*57.8,2.5,zz),STONE)
            box(group,'LaneSideGoldCap',(2.8,.8,2.8),(side*57.8,5,zz),GOLD,True)
    for y in range(9,118,7):wall(side,'FineMarbleHorizontalJoint',.05,y,110,.16,.1,220,SHADE,True)
    for z in range(8,218,14):
        for i in range(3):wall(side,'FineStaggeredMarbleJoint',.05,24+i*32,z+(i%2)*4,.16,31,.08,SHADE,True)

# Queen's lair: only high royal arch and crown above its clear right-side approach.
for z in (102,162):wall(1,'QueenPortalColumn',5,63,z,9,82,7,MARBLE)
for i in range(10):
    wall(1,'QueenPortalPediment',5,106+i*1.8,132,8,1.85,64-i*6,MARBLE)
    for sign in (-1,1):wall(1,'QueenPedimentGoldEdge',9.3,106+i*1.8,132+sign*(32-i*3),.5,1.85,1.8,GOLD,True)
wall(1,'QueenRoyalRecess',.6,66,132,1.25,58,53,BLUE)
crown('RightWall','QueenCrownCrest',70.7,120,132,1.5)

# Entrance touches all upstream positive-Z faces; never copy its horn accents.
previous=json.loads((ROOT/'assets/biome-shells/Inferno/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('InfernoExit_')]
assert len(previous_exit)==75
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','InfernoSeam_'+p['Name'],(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False))
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size']
    c=GOLD if p['Color']==list((114,25,14)) else MARBLE
    box('Exit','OlympusExit_'+p['Name'],(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
for i,w in enumerate((28,24,20,16,12,8,4)):
    box('Exit','ExitTemplePediment',(w,2,8),(0,103.4+i*1.9,214),MARBLE,True)

# Sun-Crown shrine farther down the LEFT wall; entire low silhouette outside lane.
g='SunCrownShrine'
for y,h,d,w,c in ((3,5,24,42,SHADE),(6.5,2,24,42,GOLD),(11,7,21,39,MARBLE),(16,2,23,41,GOLD),
    (49,62,16,35,STONE),(82,4,20,39,GOLD),(101,34,15,32,MARBLE),(120,4,22,40,GOLD),(126,8,18,36,MARBLE)):
    face(g,'ShrineBroadTier',-68,y,190,d,h,w,c)
face(g,'ShrineRoyalRecess',-59.4,68,190,1.25,92,25,BLUE)
for sign in (-1,1):
    for y,h,d,w,c in ((6,10,9,8,MARBLE),(12,2,11,10,GOLD),(62,98,7,6,MARBLE),(113,4,11,11,GOLD)):
        face(g,'ShrineGreekColumn',-63,y,190+sign*16,d,h,w,c)
    for i in range(5):face(g,'ShrineInnerArch',-59.05,101+i*3.2,190+sign*(12-i*2.3),.6,3.3,3.8,GOLD,True)
face(g,'ShrineLightOrangeEdge',-58.75,62,190,1,99,8,GOLD)
face(g,'ShrinePouringGoldLight',-58.17,62,190,.25,99,4.5,CORE,Neon=True,WaterFace='Right')
face(g,'ShrineWhiteHotSliver',-58.01,62,190,.08,99,1.2,HOT,True,Neon=True)
box(g,'ShrineLightBasin',(15,.2,36),(-65,5.5,190),GOLD)
box(g,'ShrineBasinWhiteCore',(11,.03,30),(-65,5.625,190),CORE,Neon=True,WaterFace='Top')
for z in (171,209):box(g,'ShrineBasinRim',(17,1.8,1.2),(-65,5,z),MARBLE)
for x in (-57,-73):box(g,'ShrineBasinSide',(1.2,1.8,38),(x,5,190),MARBLE)
# Giant square crown wrapping the waterfall's head: layered band and connected tines.
for y,h,d,w,c in ((128,3,21,40,BRONZE),(131,4,22,42,GOLD),(134,2,21,40,CORE)):
    face(g,'SunCrownBand',-66,y,190,d,h,w,c,Neon=(c==CORE))
for shift,height in ((-18,17),(-9,26),(0,34),(9,26),(18,17)):
    face(g,'SunCrownTine',-66,134+height/2,190+shift,8,height,4,GOLD)
    face(g,'SunCrownTineCap',-66,134+height,190+shift,10,2.5,6,MARBLE)
    face(g,'SunCrownLitJewel',-61.8,132+height,190+shift,.3,2,2,CORE,True,Neon=True)
face(g,'SunCrownCentreLight',-61.85,150,190,.4,28,2.5,CORE,Neon=True,WaterFace='Right')
for z in (174,180,186,194,200,206):
    for y,x in ((16,-56.65),(82,-57.85),(121,-56.85)):face(g,'ShrineGoldDentil',x,y,z,.35,1.5,1.5,GOLD,True)

box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.5,2.5,GOLD),(52.5,1.2,BRONZE),(51.2,1.2,MARBLE)):
        box('Floor','MergedRoyalFloorBorder',(w,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    # A horizontal stepped sun medallion; completely flat/non-colliding.
    for i,w in enumerate((2,4,7,10,14,18,14,10,7,4,2)):
        box('Floor','SunMedallionGoldRow',(w,.005,1.5),(0,.231,z+(i-5)*1.5),GOLD)
    for i,w in enumerate((2,4,6,4,2)):
        box('Floor','SunMedallionBrightCore',(w,.004,1.5),(0,.239,z+(i-2)*1.5),CORE,Neon=True)
    for sign in (-1,1):
        for i in range(3):
            box('Floor','FineSunRayStep',(2.2,.005,1.8),(sign*(10+i*1.7),.230,z+sign*i*1.3),GOLD,True)
            box('Floor','FineSunRayMirror',(2.2,.005,1.8),(sign*(10+i*1.7),.230,z-sign*i*1.3),GOLD,True)
for x in range(-48,49,12):box('Floor','FineMarblePavingLong',(.06,.003,220),(x,.226,110),SHADE,True)
for z in range(10,220,12):box('Floor','FineMarblePavingCross',(98,.003,.06),(0,.226,z),SHADE,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
flow=sum(bool(p.get('WaterFace')) for p in parts)
geo={'Version':1,'Name':'OlympusShell','BiomeIndex':6,'Rarity':'Godly','Boss':'Kate','BossTitle':'The Queen','BossWear':['Crown'],
    'Origin':[0,0,1100],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,'FlowFaces':flow,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[73,0,132],'WorldCenter':[73,0,1232],'ClearX':[62,80],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'InfernoShell','PreviousExitWorldZ':1100,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'InfernoExit_','ExitProfilePrefix':'OlympusExit_','ExitAccentPrefix':'ExitTemplePediment',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[-10,48,174],'Fov':68},
        'mid':{'Position':[-20,23,75],'Target':[73,69,132],'Fov':70},
        'landmark':{'Position':[38,44,128],'Target':[-67,86,190],'Fov':72},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,90,110],'Target':[-80,90,110],'Ortho':246},
        'right-wall':{'Position':[-170,75,110],'Target':[80,75,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/ToyGeometry/OlympusShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?, Neon:boolean?}\n'
for n,rows in groups.items():
    s='--!strict\n-- Native blocks; regenerate tools/build_olympus_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    s+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{n}.luau').write_text(s)
s='--!strict\n-- Zone 6 entrance is world (0,0,1100); block offsets are local.\nreturn {\n'
for n in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','FlowFaces','Bounds','ClearLane','ReservedLair','Seam'):
    s+=n+'='+lua(geo[n])+',\n'
s+='Groups={'+','.join(n+'=require(script.Parent.OlympusShell.'+n+')' for n in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/OlympusShellData.luau').write_text(s)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'FlowFaces':flow,'Groups':{n:len(v) for n,v in groups.items()}}))
