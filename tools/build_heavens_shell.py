"""Zoe's Heavens. Self-contained native cuboid authoring; Claude integrates."""
from pathlib import Path
from collections import Counter
import json,hashlib,re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Heavens';OUT.mkdir(parents=True,exist_ok=True)
WALL=(104,119,145); CLOUD=(200,209,220); CLOUDSHADE=(124,139,169)
LAVENDER=(105,69,170); RECESS=(82,70,128); DEEP=(53,47,90)
GOLD=(226,155,33); BRONZE=(108,76,32); MINT=(83,175,169)
WHITE=(237,255,246); GOLDCORE=(255,241,176); FLOOR=(117,136,158)
groups={n:[] for n in ('LeftWall','RightWall','Entrance','Exit','WingedHaloGate','Floor')}
counts=Counter();omitted=[]

def box(group,name,size,pos,color,detail=False,**flags):
    lo=[pos[i]-size[i]/2 for i in range(3)];hi=[pos[i]+size[i]/2 for i in range(3)]
    assert min(size)>0,name
    if lo[0]<-62 and hi[0]>-80 and lo[2]<159 and hi[2]>105 and lo[1]<32:
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

def halo(group,name,x,y,z,s,detail=False,core=True):
    # Eight overlapping axis-aligned segments create an octagonal stepped ring.
    rows=[(6,0,2,8),(-6,0,2,8),(0,6,8,2),(0,-6,8,2)]
    rows += [(a*4.5,b*4.5,3,3) for a in (-1,1) for b in (-1,1)]
    for yy,zz,h,w in rows:face(group,name+'GoldSegment',x,y+yy*s,z+zz*s,1.2*s,h*s,w*s,GOLD,detail)
    if core:
        inward=-1 if x>0 else 1
        for yy,zz,h,w in ((5.6,0,.55,7),(-5.6,0,.55,7),(0,5.6,7,.55),(0,-5.6,7,.55)):
            face(group,name+'BrightInnerRun',x+inward*.65*s,y+yy*s,z+zz*s,.15*s,h*s,w*s,GOLDCORE,True,Neon=True)

def wings(group,name,x,y,z,s,detail=False):
    # Three broad connected masses per side survive low detail; feather tips are fine.
    inward=-1 if x>0 else 1
    for sign in (-1,1):
        for i,(shift,w) in enumerate(((6,10),(10,10),(14,8))):
            face(group,name+'BroadWing',x,y+i*4*s,z+sign*shift*s,2*s,5*s,w*s,CLOUD,detail)
        for i in range(4):
            shift=(5.5+i*3.6)*s
            face(group,name+'FineFeatherStep',x+inward*1.02*s,y+(i*3.4-1)*s,z+sign*shift,.18*s,2.1*s,(5-i*.35)*s,CLOUD,True)
            face(group,name+'FeatherGoldRoot',x+inward*1.16*s,y+(i*3.4-1.8)*s,z+sign*shift,.13*s,.65*s,(3.6-i*.25)*s,GOLD,True)

def cloud(side,name,u,y,z,w,s=1,detail=False):
    for i,(width,shift) in enumerate(((w,0),(w*.78,-w*.04),(w*.48,w*.06))):
        wall(side,name+'MergedCloudTier',u+i*.15,y+i*3.5*s,z+shift,8*s,3.6*s,width,CLOUDSHADE if i==0 else CLOUD,detail)
    for shift in (w*.34,):wall(side,name+'SmallCloudPuff',u+2.1*s,y+3.7*s,z+shift,4*s,4*s,5*s,CLOUD,True)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'LavenderSkyRetainingWall',-2,60,110,4,120,220,WALL)
    for name,y,h,d,c in (('CloudFoundationShadow',2.5,5,8,DEEP),('CloudLowLedge',6,3,10,CLOUDSHADE),
        ('MergedGoldGroundRail',8,1.4,11,GOLD),('CloudMidGallery',37,4,10,CLOUD),
        ('GalleryGoldUnderline',34.8,.8,10.5,GOLD),('UpperCloudEntablature',101,6,10,CLOUDSHADE),
        ('GoldSkylineRail',105,2,11,GOLD),('CloudSkylineBacking',112,12,9,CLOUD)):
        spans=((0,104),(160,220)) if side<0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,name,2,y,(a+b)/2,d,h,b-a,c)
    for z in (14,46,78,110,142,174,206):cloud(side,'SkylineCloudBank',3,119,z,28)
    piers=(10,44,96,168,210) if side<0 else (10,44,80,116,152,210)
    for z in piers:
        for y,h,d,w,c in ((5,5,12,13,CLOUDSHADE),(8,1,13,14,GOLD),(12,7,10,11,LAVENDER),
            (61,91,8,8,CLOUDSHADE),(108,3,12,13,GOLD),(112,6,11,11,CLOUD),(117,4,10,9,CLOUD)):
            wall(side,'CloudLightTowerTier',5,y,z,d,h,w,c)
        wall(side,'TowerLavenderInset',9.15,62,z,.4,84,5,RECESS)
        wall(side,'TowerBeamGoldFrame',9.48,62,z,.3,81,3.8,GOLD)
        wall(side,'TowerWhiteLightCore',9.7,62,z,.18,78,2.4,WHITE,Neon=True,WaterFace='Right' if side<0 else 'Left')
        for dz in (-2.5,2.5):wall(side,'FineTowerFlute',9.39,63,z+dz,.12,82,.35,CLOUD,True)
        for y in (38,88):wall(side,'FineBeamGoldGlint',9.82,y,z,.09,5,.55,GOLDCORE,True,Neon=True)
        # Horizontally laid stepped halo, seated on the tower's white beam extension.
        wall(side,'SkyHaloLightStem',5,131,z,2,25,2,WHITE,Neon=True)
        for du,dz,d,w in ((0,-5,7,2),(0,5,7,2),(-5,0,2,7),(5,0,2,7),(-3.8,-3.8,3,3),(-3.8,3.8,3,3),(3.8,-3.8,3,3),(3.8,3.8,3,3)):
            wall(side,'TowerHaloHorizontalStep',5+du,142,z+dz,d,1.4,w,GOLD)
        cloud(side,'TowerSmallCloudShoulder',7,37,z,17,.8,True)
        for y,u in ((15,10.07),(105,9.08)):
            for dz in (-5,0,5):wall(side,'FineTowerGoldDentil',u,y,z+dz,.25,1,1,GOLD,True)
    bays=((27,23),(70,33),(184,27)) if side<0 else ((27,23),(62,23),(98,23),(134,23),(178,35))
    for z,w in bays:
        wall(side,'AngelAlcoveLavender',1,65,z,2.1,59,w,RECESS)
        for zz in (-w*.48,w*.48):wall(side,'AlcoveGoldBorder',2.12,65,z+zz,.24,59,.7,GOLD)
        cloud(side,'AlcoveCloudCanopy',4,97,z,w+6,.8)
        halo(group,'AlcoveHalo',side*77.5,78,z,.8)
        wings(group,'AlcoveAngelWing',side*77.5,55,z,.48)
        wall(side,'AlcoveFallingGoldFrame',2.2,49,z,.4,30,4,GOLD)
        wall(side,'AlcoveFallingWhiteCore',2.48,49,z,.22,29,1.8,GOLDCORE,Neon=True,WaterFace='Right' if side<0 else 'Left')
        for y,h,d,ww,c in ((4,7,13,w*.82,CLOUDSHADE),(9,3,12,w*.73,CLOUD),(12,2,10,w*.62,LAVENDER)):
            wall(side,'PeripheralCloudPlinth',11,y,z,d,h,ww,c)
        cloud(side,'CloudPlinthPuffs',11,15,z,w*.55,.6,True)
        # Mint toy flower bundles are peripheral small accents, no textures or animation.
        wall(side,'MintBudBox',11,17,z,4,2,5,GOLD,True)
        for dz,h in ((-1.6,2.5),(0,4)):wall(side,'MintBlockBud',11,18+h/2,z+dz,2,h,1.8,MINT,True)
    spans=((0,104),(160,220)) if side<0 else ((0,160),(208,220))
    for a,b in spans:
        n=b-a;z=(a+b)/2
        box(group,'CloudChannelShadow',(5,.6,n),(side*60,.6,z),DEEP)
        box(group,'CloudChannelGoldRim',(3.8,.15,n),(side*60,1,z),GOLD)
        box(group,'CloudChannelWhiteCore',(2,.03,n),(side*60,1.09,z),WHITE,Neon=True,WaterFace='Top')
        for x in (57.7,62.3):box(group,'CloudChannelBank',(.8,.8,n),(side*x,.8,z),CLOUD)
        for zz in range(a+8,b-4,22):
            box(group,'LaneGoldRailPost',(2,3.3,2),(side*57.8,2,zz),CLOUDSHADE)
            box(group,'LaneGoldPostCap',(2.6,.7,2.6),(side*57.8,4,zz),GOLD)
            box(group,'LanePostBrightInset',(.3,1.1,1.1),(side*56.8,2.7,zz),GOLDCORE,True,Neon=True)
        box(group,'MergedPeripheralGoldRail',(.5,.5,n),(side*57.8,3.2,z),GOLD)
    for z in (24,64,104,164,204):
        cloud(side,'GroundCloudBank',14,2.5,z,18,.7,True)
        for shift in (0,):wall(side,'CloudFineLowPuff',16,6.2,z+shift,3,3,4,CLOUD,True)
    # Broad cloud-layer panel joins and sparse stepped edges, merged long runs.
    for y in (18,49,80):wall(side,'FineCloudLayerJoint',.05,y,110,.16,.13,220,CLOUDSHADE,True)
    for z in range(8,218,14):
        for y in (30,78):wall(side,'FineCloudPanelJoint',.05,y,z,.16,31,.1,CLOUDSHADE,True)

# Left angel lair: high winged halo above an unobstructed original stage.
for z in (102,162):wall(-1,'AngelPortalCloudPier',5,64,z,9,80,7,CLOUDSHADE)
wall(-1,'AngelHighLavenderRecess',.6,67,132,1.25,58,53,LAVENDER)
cloud(-1,'AngelPortalCloudLintel',5,107,132,62)
halo('LeftWall','ZoePortalHalo',-63,122,132,1.15)
wings('LeftWall','ZoePortalWings',-62,101,132,1.1)

# Upstream Olympus interface is kept exact; its decorative temple crest is excluded.
previous=json.loads((ROOT/'assets/biome-shells/MountOlympus/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('OlympusExit_')]
assert len(previous_exit)==75
def profile_name(name):
    # Keep the original gate identity without stacking every upstream biome prefix.
    # Studio truncates Instance.Name at 100 characters.
    match=re.search(r'Gate[A-Za-z]+_\d{3}',name)
    assert match,name
    return match.group(0)
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','OlympusSeam_'+profile_name(p['Name']),(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False),ProfileSource=p['Name'])
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];c=GOLD if p['Color']==[213,134,17] else CLOUD
    box('Exit','HeavensExit_'+profile_name(p['Name']),(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
for i,w in enumerate((26,20,12)):
    box('Exit','ExitCloudCrest',(w,3.5,8),(0,104+i*3.4,214),CLOUD,True)

# Winged halo gate is on the far RIGHT wall, safely outside the runway.
g='WingedHaloGate'
for y,h,d,w,c in ((3,5,24,44,CLOUDSHADE),(6.5,2,24,44,GOLD),(11,7,21,40,CLOUD),(16,2,23,42,GOLD),
    (49,62,16,35,CLOUDSHADE),(82,4,20,39,GOLD),(104,40,15,34,LAVENDER),(127,6,22,40,CLOUD)):
    face(g,'GateBroadCloudTier',68,y,184,d,h,w,c)
face(g,'GateLavenderInnerFace',59.4,69,184,1.25,95,25,RECESS)
for sign in (-1,1):
    for y,h,d,w,c in ((6,10,9,8,CLOUD),(12,2,11,10,GOLD),(62,98,7,6,CLOUD),(113,4,11,11,GOLD)):
        face(g,'GateCloudPier',63,y,184+sign*16,d,h,w,c)
    for i in range(5):face(g,'GateFineArchStep',59.05,102+i*3,184+sign*(12-i*2.3),.6,3.1,3.8,GOLD,True)
face(g,'GateLightGoldFrame',58.75,62,184,1,99,8,GOLD)
face(g,'GatePouringWhiteLight',58.17,62,184,.25,99,4.5,WHITE,Neon=True,WaterFace='Left')
face(g,'GatePaleGoldShimmer',58.01,62,184,.08,99,1.2,GOLDCORE,True,Neon=True)
box(g,'GateCloudBasin',(15,.2,36),(65,5.5,184),MINT)
box(g,'GateBasinWhiteCore',(11,.03,30),(65,5.625,184),WHITE,Neon=True,WaterFace='Top')
for z in (165,203):box(g,'GateBasinCloudRim',(17,1.8,1.2),(65,5,z),CLOUD)
for x in (57,73):box(g,'GateBasinCloudSide',(1.2,1.8,38),(x,5,184),CLOUD)
halo(g,'GreatAngelHalo',54,147,184,3)
for sign in (-1,1):
    for i in range(7):
        shift=(8+i*2.3)*1.3;w=(13-i*1.2)*1.3;y=119+i*3*1.3
        face(g,'GreatWingLavenderUnderlay',55.9,y,184+sign*shift,7,4.1,w+1.2,CLOUDSHADE)
        face(g,'GreatWingFeather',52.1,y+.3,184+sign*shift,.5,3.9,w,CLOUD)
        face(g,'GreatWingFineGoldEdge',51.79,y-1.25,184+sign*shift,.18,.7,w-.5,GOLD,True)
face(g,'HaloGateHaloBeamStem',54,132,184,3,12,3,WHITE,Neon=True)
for sign in (-1,1):
    for y in (15,80,112):
        cloud(1,'GatePeripheralCloudPuff',12,y,184+sign*14,15,.65,True)

box('Floor','ClearLaneCloudFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.5,2.5,GOLD),(52.5,1.2,CLOUDSHADE),(51.2,1.2,CLOUD)):
        box('Floor','MergedCloudFloorBorder',(w,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    for yy,zz,h,w in ((6,0,2,8),(-6,0,2,8),(0,6,8,2),(0,-6,8,2),(-4.5,-4.5,3,3),(-4.5,4.5,3,3),(4.5,-4.5,3,3),(4.5,4.5,3,3)):
        box('Floor','HaloFloorRing',(w,.005,h),(zz,.231,z+yy),GOLD)
    for i,w in enumerate((2,4,6,4,2)):
        box('Floor','CloudFloorWhiteCore',(w,.004,1.5),(0,.239,z+(i-2)*1.5),WHITE,Neon=True)
    for side in (-1,1):
        for i in range(4):box('Floor','FineFloorFeatherInlay',(5-i*.4,.005,1.3),(side*(9+i*.8),.230,z+(i-2.5)*1.3),CLOUD,True)
for x in range(-48,49,12):box('Floor','FineCloudPavingLong',(.06,.003,220),(x,.226,110),CLOUDSHADE,True)
for z in range(10,220,12):box('Floor','FineCloudPavingCross',(98,.003,.06),(0,.226,z),CLOUDSHADE,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
assert all(len(p['Name'])<=100 for p in parts),'runtime part-name limit'
assert all(len({p['Name'] for p in rows})==len(rows) for rows in groups.values()),'unique part names'
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
flow=sum(bool(p.get('WaterFace')) for p in parts)
geo={'Version':1,'Name':'HeavensShell','BiomeIndex':7,'Rarity':'Celestial','Boss':'Zoe','BossTitle':'The Angel','BossWear':['Halo','AngelWings'],
    'Origin':[0,0,1320],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,'FlowFaces':flow,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[-73,0,132],'WorldCenter':[-73,0,1452],'ClearX':[-80,-62],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'OlympusShell','PreviousExitWorldZ':1320,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'OlympusExit_','ExitProfilePrefix':'HeavensExit_','ExitAccentPrefix':'ExitCloudCrest',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[10,48,174],'Fov':68},
        'mid':{'Position':[20,23,75],'Target':[-73,69,132],'Fov':70},
        'landmark':{'Position':[-38,44,128],'Target':[67,96,184],'Fov':72},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,90,110],'Target':[-80,90,110],'Ortho':246},
        'right-wall':{'Position':[-170,90,110],'Target':[80,90,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/ToyGeometry/HeavensShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?, Neon:boolean?, ProfileSource:string?}\n'
for n,rows in groups.items():
    s='--!strict\n-- Native blocks; regenerate tools/build_heavens_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    s+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{n}.luau').write_text(s)
s='--!strict\n-- Zone 7 entrance is world (0,0,1320); block offsets are local.\nreturn {\n'
for n in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','FlowFaces','Bounds','ClearLane','ReservedLair','Seam'):
    s+=n+'='+lua(geo[n])+',\n'
s+='Groups={'+','.join(n+'=require(script.Parent.HeavensShell.'+n+')' for n in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/HeavensShellData.luau').write_text(s)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'FlowFaces':flow,'Groups':{n:len(v) for n,v in groups.items()}}))
