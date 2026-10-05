"""Ivy's measured Gardens shell. Authoring/export only; Claude owns integration."""
from pathlib import Path
from collections import Counter
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Gardens'; OUT.mkdir(parents=True,exist_ok=True)
FOREST=(18,61,24); LEAF=(34,105,28); BRIGHT=(64,130,32); MOSS=(30,77,26)
SHADOW=(13,26,43); BLUE=(18,49,137); BLUE_LIGHT=(32,88,175)
WOOD=(61,33,24); BARK=(132,52,9); BRONZE=(143,93,23); GOLD=(188,126,21)
PLUM=(68,0,35); PINK=(172,7,69); CORAL=(173,18,15); WATER=(12,78,119)
groups={name:[] for name in ('LeftWall','RightWall','Entrance','Exit','BlossomTree','Floor')}
counts=Counter(); omitted=[]

def box(group,name,size,pos,color,detail=False,**flags):
    lo=[pos[i]-size[i]/2 for i in range(3)]; hi=[pos[i]+size[i]/2 for i in range(3)]
    assert min(size)>0,name
    if lo[0]<80 and hi[0]>62 and lo[2]<159 and hi[2]>105 and lo[1]<32:
        omitted.append(name);return
    assert lo[2]>=(-3.001 if group=='Entrance' else -0.001) and hi[2]<=220.001,(name,'depth',lo,hi)
    if group!='Floor' and lo[0]<56 and hi[0]>-56:assert lo[1]>=70,(name,'lane clearance',lo)
    if group=='Floor':assert hi[1]<=.241,(name,'raised floor')
    counts[(group,name)]+=1
    row={'Name':f'{name}_{counts[(group,name)]:03}','Size':[round(x,4) for x in size],
        'Offset':[round(x,4) for x in pos],'Color':list(color)}
    if detail:row['Detail']=True
    row.update(flags); groups[group].append(row)

def wall(side,name,u,y,z,d,h,w,c,detail=False,**flags):
    box('LeftWall' if side<0 else 'RightWall',name,(d,h,w),(side*(80-u),y,z),c,detail,**flags)

def flower(group,name,x,y,z,r,c,detail=True):
    # Two merged petal runs plus square centre; silhouette is still made of blocks.
    back=x+(.55 if x>0 else -.55)
    box(group,name+'OutlineVertical',(.8,r*3+.6,r*1.45+.6),(back,y,z),PLUM if c in (PINK,CORAL) else SHADOW,detail)
    box(group,name+'OutlineHorizontal',(.8,r*1.45+.6,r*3+.6),(back,y,z),PLUM if c in (PINK,CORAL) else SHADOW,detail)
    box(group,name+'Vertical',(.8,r*3,r*1.45),(x,y,z),c,detail)
    box(group,name+'Horizontal',(.82,r*1.45,r*3),(x,y,z),c,detail)
    box(group,name+'Centre',(1,r*.8,r*.8),(x+(-.25 if x>0 else .25),y,z),GOLD,detail)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'MossCliffBacking',-2,60,110,4,120,220,FOREST)
    # Large continuous coloured runs rather than one part for every moss pixel.
    for name,y,d,h,c in [('RootStone',2,7,4,SHADOW),('RootBlueBand',4.4,8,.8,BLUE),
        ('HedgeLedge',15,10,3,WOOD),('HedgeMossCourse',17,9,2,LEAF),
        ('MiddleRetaining',39,7,4,FOREST),('MiddleBlueLip',41.5,8,1,BLUE),
        ('UpperRetaining',101,8,4,WOOD),('UpperCobaltBand',104,9,1.3,BLUE),
        ('SkylineHedge',117,10,6,FOREST),('SkylineBlueLip',121,11,1.2,BLUE)]:
        spans=[(0,104),(160,220)] if side>0 and y-h/2<32 else [(0,220)]
        for a,b in spans:wall(side,name,2.3,y,(a+b)/2,d,h,b-a,c)
    piers=(10,44,80,116,152,178,210) if side<0 else (10,44,96,168,210)
    for z in piers:
        wall(side,'TrellisPier',3,63,z,6,114,5,WOOD)
        wall(side,'PierCobaltFlute',6.3,65,z,.7,102,1.4,BLUE)
        for y in (8,39,104,119):wall(side,'PierTerraceCap',4,y,z,11,2.4,11,BRONZE)
        for y,w in ((125,11),(130,8),(134,5),(137,2.6)):
            wall(side,'SkylineTopiary',2,y,z,w,4,w,LEAF if w==8 else FOREST)
        for i in range(8):
            wall(side,'IvyRibbon',7,47+i*7,z+(i%3-1)*1.2,1,5,3,BRIGHT if i%3==0 else LEAF,True)
        for y in (52,87):flower(group,'PierFlower',side*71.6,y,z+2,1.3,PINK if z%3 else BLUE_LIGHT)
    bays=((27,25),(62,25),(98,25),(134,25),(165,18)) if side<0 else ((27,25),(70,32),(184,26))
    for z,w in bays:
        wall(side,'GardenTrellisShadow',1.6,67,z,1,58,w,SHADOW)
        for sign in (-1,1):wall(side,'TrellisFrame',3.2,63,z+sign*w/2,2.5,58,1.8,WOOD)
        wall(side,'TrellisBottomBeam',4,34,z,3,2,w+4,BRONZE)
        # Connected stepped top contour, exact same arched garden-window motif as reference.
        for i in range(6):
            for sign in (-1,1):wall(side,'TrellisArch',4,92+i*1.9,z+sign*(w/2-i*w/12),2.2,2.1,w/6+.4,BRONZE,True)
        for yy in (46,59,72):wall(side,'TrellisHorizontal',3,yy,z,1,1,w-.5,WOOD,True)
        for zz in (-.27,0,.27):wall(side,'TrellisUpright',3.1,64,z+zz*w,1,44,1,WOOD,True)
        for y,width in ((23,w*.7),(27,w*.48),(30,w*.26)):
            wall(side,'BayHedgeTier',6,y,z,7,3,width,LEAF if y==27 else FOREST)
        wall(side,'FlowerBedRun',9,20.5,z,2,2,w*.7,PINK)
        for j in (-1,0,1):flower(group,'BedBlossom',side*69.5,22,z+j*w*.24,1,CORAL)
    # Blue channels and clipped edge beds are part of continuous ledges, not loose props.
    spans=[(0,104),(160,220)] if side>0 else [(0,172),(216,220)]
    for start,end in spans:
        z=(start+end)/2;length=end-start
        for u,y,d,h,c in ((7,5,10,5,FOREST),(8,8.5,8,2.2,LEAF),(8,10.2,6,1.2,WOOD)):
            wall(side,'ContinuousHedge',u,y,z,d,h,length,c)
        box(group,'EdgeCanalBed',(5.6,.6,length),(side*61.6,.55,z),SHADOW)
        box(group,'EdgeCanalWater',(4.2,.15,length),(side*61.6,.97,z),WATER,WaterFace='Top')
        for x in (58.5,64.7):
            box(group,'CanalCobaltBank',(1,.8,length),(side*x,.78,z),BLUE)
            box(group,'CanalBronzeBank',(.3,.2,length),(side*(x-.6),1.15,z),BRONZE)
        for zz in range(start+8,end-4,20):
            box(group,'EdgeBloomRun',(3,1.6,11),(side*68,9.7,zz),PINK,True)
            box(group,'CanalPier',(2,3,2),(side*58.2,2.5,zz),BLUE)
            box(group,'CanalPierCap',(2.4,.6,2.4),(side*58.2,4.3,zz),GOLD,True)
    box(group,'PetalAnchor',(2,2,2),(side*67,28,64),PINK,True,Ambient=True,Hidden=True)

# Ivy's existing right-wall lair stays untouched, including approach, prompts and signs.
for z in (102,162):
    wall(1,'FlowerCrownPortalPier',5,50,z,8,64,6,WOOD)
    wall(1,'PortalBlueFlute',9.4,53,z,.8,54,1.3,BLUE)
for i in range(9):
    for sign in (-1,1):wall(1,'FlowerPortalArch',6.3,80+i*1.9,132+sign*(28-i*3.1),7.5,2.1,4,BRONZE)
wall(1,'LairHighRecess',1,62,132,1,60,52,SHADOW)
wall(1,'FlowerCrownVine',7,105,132,2,3,36,FOREST)
for z,y,r,c in ((118,107,3,BLUE_LIGHT),(127,111,4,PINK),(138,111,4,CORAL),(147,106,3,BLUE_LIGHT)):
    flower('RightWall','FlowerCrown',71.6,y,z,r,c,False)

# Physical seam: each collar's front exactly touches the positive-Z face of Courtyard's exit.
previous=json.loads((ROOT/'assets/biome-shells/Courtyard/geometry.json').read_text())
previous_exit=previous['Groups']['Exit']
for part in previous_exit:
    x,y,z=part['Offset'];sx,sy,sz=part['Size'];depth=3
    front=z+sz/2-220
    box('Entrance','CourtyardSeam_'+part['Name'],(sx,sy,depth),(x,y,front+depth/2),part['Color'],part.get('Detail',False))

# Gardens owns its exit arch; the next shell receives this same measured interface.
for part in previous_exit:
    x,y,z=part['Offset'];sx,sy,sz=part['Size']
    original=part['Color']
    c=BLUE if 'Brass' in part['Name'] or 'Gold' in part['Name'] else FOREST if 'Garden' in part['Name'] else WOOD
    box('Exit','GardenExit_'+part['Name'],(sx,sy,sz),(x,y,z),c,part.get('Detail',False))
box('Exit','ExitFlowerVertical',(5.8,12,.8),(0,111,208.5),PINK)
box('Exit','ExitFlowerHorizontal',(12,5.8,.82),(0,111,208.5),PINK)
box('Exit','ExitFlowerCentre',(3.2,3.2,1),(0,111,208.2),GOLD)

# Far wall landmark: huge flowering tree grows out of the -X retaining wall and edge pond.
box('BlossomTree','TreeRootTerrace',(21,3,43),(-69.5,1.8,194),SHADOW)
box('BlossomTree','TreeRootBlueBand',(21,1.2,43),(-69.5,4,194),BLUE)
box('BlossomTree','TreePond',(12,.2,37),(-65,4.9,194),WATER,WaterFace='Top')
for x in (-59,-72):box('BlossomTree','PondStoneBank',(1.2,1.4,41),(x,4.5,194),WOOD)
for z in (174,214):box('BlossomTree','PondEndBank',(14,1.4,1.2),(-65.5,4.5,z),BRONZE)
for i,(x,y,z,w,h,d) in enumerate(((-72,18,193,14,31,13),(-67,43,192,11,23,10),(-64,65,190,10,23,8),(-58,85,186,12,21,7))):
    box('BlossomTree','TrunkStep',(w,h,d),(x,y,z),BARK)
    box('BlossomTree','TrunkBarkRibbon',(1.3,h-1,d*.65),(x+w/2+.3,y,z),BARK,True)
for direction in (-1,1):
    for i in range(5):
        if direction==1 and i==0:continue
        box('BlossomTree','SteppedBough',(8,7,9),(-72+i*4.5,80+i*6,190+direction*i*4),BARK)
for i,(x,y,z,depth,width,height) in enumerate(((-62,98,171,34,30,16),(-56,119,193,50,42,20),(-72,126,207,36,22,16),(-67,142,183,42,35,18),(-37,127,174,32,28,15),(-38,110,207,28,17,15),(-49,145,204,28,25,13))):
    for layer,scale in enumerate((.5,.78,1,.78,.5)):
        c=PLUM if layer==0 else PINK if i%2==0 else CORAL
        box('BlossomTree','BlossomCanopyTier',(depth*scale,height/5,width*scale),(x,y+(layer-2)*height/5,z),c)
    face=x+depth/2+.5
    for ry,rz,r,c in ((0,0,3.4,PINK),(-4,-8,2,CORAL),(4,8,2.5,PINK),(2,-7,1.7,BLUE_LIGHT),(-3,6,1.7,BLUE)):
        flower('BlossomTree','CanopyFlower',face,y+ry,z+rz,r,c)
    for ry,rz in ((-5,0),(5,0)):
        flower('BlossomTree','CanopyBud',x+depth*.39+.5,y+ry,z+rz,.95,CORAL if i%2==0 else PINK)
    box('BlossomTree','CanopyLeafShelf',(depth*.7,3,width*.7),(x,y-height/2-1.3,z+4),FOREST)
    for j in (-1,1):box('BlossomTree','CanopyHighlightStep',(4,2,width*.3),(x+depth*.2,y+height/2+.5,z+j*width*.23),PINK,True)
for z in (179,188,203):
    for step in range(3):box('BlossomTree','RootHedge',(14-step*3,3,10-step*2),(-72,8+step*2.7,z),LEAF if step==1 else FOREST)
box('BlossomTree','TreeSpring',(1,33,4),(-61.8,22,182),WATER,WaterFace='Right')
box('BlossomTree','SpringHeader',(3,2,7),(-63,39,182),BLUE)

# One clear merged ground skin; coplanar inlays are decorative and non-queryable.
box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),FOREST,Stud=True)
for side in (-1,1):
    for x,width,c in ((54.5,2.5,BLUE),(52.5,1.2,BRONZE),(51.2,1.2,SHADOW)):
        box('Floor','LongInlaidBorder',(width,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    for row in range(-5,6):
        width=(5-abs(row))*2+1
        box('Floor','FlowerDiamondBorder',(width*1.8,.005,1.8),(0,.228,z+row*1.8),BRONZE)
        if width>2:box('Floor','FlowerDiamondBlue',((width-2)*1.8,.005,1.8),(0,.233,z+row*1.8),BLUE)
    box('Floor','FlowerInlayPetalVertical',(3.6,.005,10.8),(0,.237,z),PINK)
    box('Floor','FlowerInlayPetalHorizontal',(10.8,.005,3.6),(0,.237,z),CORAL)
    box('Floor','FlowerInlayCentre',(1.8,.004,1.8),(0,.239,z),GOLD)
for x in range(-48,49,12):box('Floor','PavingSeamLong',(.06,.003,220),(x,.226,110),SHADOW,True)
for z in range(10,220,12):box('Floor','PavingSeamCross',(98,.003,.06),(0,.226,z),SHADOW,True)

# Exact run merging: only co-linear, touching rows with identical colours/flags are combined.
merged=0
for name,parts in groups.items():
    changed=True
    while changed:
        changed=False
        for i,a in enumerate(parts):
            for j in range(i+1,len(parts)):
                b=parts[j]
                if {k:v for k,v in a.items() if k not in ('Name','Size','Offset')}!={k:v for k,v in b.items() if k not in ('Name','Size','Offset')}:continue
                if a['Name'].rsplit('_',1)[0]!=b['Name'].rsplit('_',1)[0]:continue
                for axis in range(3):
                    others=[k for k in range(3) if k!=axis]
                    if any(a['Size'][k]!=b['Size'][k] or a['Offset'][k]!=b['Offset'][k] for k in others):continue
                    if abs(abs(a['Offset'][axis]-b['Offset'][axis])-(a['Size'][axis]+b['Size'][axis])/2)>1e-5:continue
                    amin=a['Offset'][axis]-a['Size'][axis]/2;bmin=b['Offset'][axis]-b['Size'][axis]/2
                    size=a['Size'][axis]+b['Size'][axis]
                    a['Size'][axis]=round(size,4);a['Offset'][axis]=round(min(amin,bmin)+size/2,4)
                    parts.pop(j);merged+=1;changed=True;break
                if changed:break
            if changed:break
all_parts=[p for parts in groups.values() for p in parts];pivots=len(groups)+1
full=len(all_parts)+pivots;low=sum(not p.get('Detail') for p in all_parts)+pivots
assert full<=1500 and low<=800,(full,low)
geo={'Version':1,'Name':'GardensShell','BiomeIndex':2,'Rarity':'Rare','Boss':'Ivy','BossTitle':'The Gardener','BossWear':['FlowerCrown'],
    'Origin':[0,0,220],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[73,0,132],'WorldCenter':[73,0,352],'ClearX':[62,80],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'CourtyardShell','PreviousExitWorldZ':220,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,'ExitProfilePrefix':'GardenExit_','ExitAccentPrefix':'ExitFlower',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'MergedRuns':merged,'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[-10,49,174],'Fov':68},
        'mid':{'Position':[0,23,83],'Target':[-55,70,181],'Fov':70},
        'landmark':{'Position':[42,81,130],'Target':[-56,79,190],'Fov':82},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,73,110],'Target':[-80,73,110],'Ortho':246},
        'right-wall':{'Position':[-170,73,110],'Target':[80,73,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(value):
    if isinstance(value,dict):return '{'+','.join(k+'='+lua(v) for k,v in value.items())+'}'
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,bool):return 'true' if value else 'false'
    return json.dumps(value)
folder=ROOT/'src/shared/Config/ToyGeometry/GardensShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?}\n'
for name,parts in groups.items():
    text='--!strict\n-- Authored native blocks. Regenerate tools/build_gardens_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    text+='\n'.join('\t'+lua(p)+',' for p in parts)+'\n}\nreturn blocks\n'
    (folder/f'{name}.luau').write_text(text)
config='--!strict\n-- Zone 2 entrance is world (0,0,220); geometry offsets are LOCAL to that entrance.\nreturn {\n'
for name in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','Bounds','ClearLane','ReservedLair','Seam'):
    config+=name+'='+lua(geo[name])+',\n'
config+='Groups={'+','.join(name+'=require(script.Parent.GardensShell.'+name+')' for name in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/GardensShellData.luau').write_text(config)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'MergedRuns':merged,'Groups':{k:len(v) for k,v in groups.items()}}))
