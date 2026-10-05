"""Courtyard phone-case shell: authored blocks from the generated reference.

Origin is zone-1 entrance centre, Y=0; +Z goes deeper, +X is right.
Produces shared geometry only. Does not edit MapService or integration files.
"""
from pathlib import Path
from collections import Counter
import json, math, re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Courtyard'
OUT.mkdir(parents=True,exist_ok=True)
CREAM=(239,222,182); LIGHT=(255,240,204); TAN=(195,161,104)
DARK=(25,58,56); TEAL=(39,96,90); GOLD=(224,175,55); HIGHLIGHT=(255,215,93)
GREEN=(39,118,64); LEAF=(79,169,75); DEEP=(23,77,49); WATER=(47,197,215)
WOOD=(131,90,48); SILVER=(163,183,169); GRASS=(94,157,71)
groups={name:[] for name in ('LeftWall','RightWall','Entrance','Exit','Fountain','Floor')}
counts=Counter()
omitted=[]
def box(group,name,size,pos,color,detail=False,**flags):
    assert all(v>0 for v in size),name
    lo=[pos[i]-size[i]/2 for i in range(3)]
    hi=[pos[i]+size[i]/2 for i in range(3)]
    # Preserve the real lair AND its approach margin. Floor inlays also leave it untouched.
    if lo[0]<-62 and hi[0]>-80 and lo[2]<159 and hi[2]>105 and lo[1]<32:
        omitted.append(name);return
    assert lo[2]>=-0.001 and hi[2]<=220.001,(name,lo,hi)
    if group!='Floor' and lo[0]<56 and hi[0]>-56:
        assert lo[1]>=52,(name,'intrudes into protected centre airspace',lo)
    if group=='Floor':assert hi[1]<=0.241,(name,'raised floor')
    counts[(group,name)]+=1
    row=dict(Name=f'{name}_{counts[(group,name)]:03}',Size=[round(v,4) for v in size],
        Offset=[round(v,4) for v in pos],Color=list(color))
    if detail:row['Detail']=True
    row.update(flags);groups[group].append(row)

def wall(side,name,u,y,z,depth,height,width,color,detail=False,**flags):
    box('LeftWall' if side<0 else 'RightWall',name,(depth,height,width),(side*(80-u),y,z),color,detail,**flags)

def long_course(side,name,y,depth,height,color):
    spans=[(0,104),(160,220)] if side<0 and y-height/2<32 else [(0,220)]
    for start,end in spans:wall(side,name,1.3,y,(start+end)/2,depth,height,end-start,color)

def topiary(side,z):
    group='LeftWall' if side<0 else 'RightWall';x=side*70
    box(group,'TopiaryPlanter',(11,2,12),(x,1.5,z),TEAL)
    box(group,'TopiaryPlanterLip',(11.6,.7,12.6),(x,2.6,z),GOLD)
    for n,(w,h) in enumerate(((9,3),(7,3),(5,3),(3,3))):
        box(group,'TopiaryStep',(w,h,w),(x,4.4+n*2.7,z),DEEP if n%2==0 else GREEN)
    box(group,'TopiaryLeafHighlight',(1.2,2,2),(x-side*2.1,9,z-1.3),LEAF,True)

def window(side,z,width,bay):
    label=f'Window{bay:02}'
    wall(side,label+'Shadow',.8,59,z,2.2,54,width+3,DARK)
    wall(side,label+'Recess',2,61,z,.5,53,width-1,TEAL)
    for sign in (-1,1):
        wall(side,label+'Jamb',3,59,z+sign*(width/2+1),2.8,54,2.2,CREAM)
        wall(side,label+'InnerTrim',4.3,59,z+sign*(width/2-.8),.9,51,.9,GOLD)
    # Pointed, visibly stepped arches; no image or mesh-plane window ornament.
    for step in range(6):
        half=(width/2)-step*(width/2)/6
        wall(side,label+'ArchRecess',.8,87+step*2,z,2.2,2.2,half*2+3,DARK)
        for sign in (-1,1):
            wall(side,label+'ArchStep',3.8,87+step*2,z+sign*half,2.8,2.2,2.8,CREAM)
            wall(side,label+'ArchGold',5.25,86.3+step*2,z+sign*half,.7,.8,2.3,GOLD,True)
    for y,depth,thickness,c in ((32,5,2,TAN),(34,6,1.3,LIGHT),(39,3.8,1,GOLD)):
        wall(side,label+'Sill',2.7,y,z,depth,thickness,width+7,c)
    wall(side,label+'TraceryStem',3.1,63,z,.7,37,.8,GOLD)
    wall(side,label+'TraceryCross',3.1,47,z,.7,.8,width*.55,GOLD)
    for col in (-1,0,1):
        for level in range(3):
            for sign in (-1,1):
                wall(side,label+'TraceryDiamond',3.1,43+level*.9,z+col*width*.2+sign*(1.2-level*.4),.7,1,.65,HIGHLIGHT,True)
    for sign in (-1,1):
        wall(side,label+'TracerySide',3.1,57,z+sign*width*.23,.7,22,.7,GOLD,True)
    for n in range(4):
        for sign in (-1,1):
            wall(side,label+'TraceryCrown',3.1,78+n*1.6,z+sign*(3.2-n*.8),.7,1.7,.9,HIGHLIGHT,True)
    wall(side,label+'FlowerBox',4.5,36.3,z,3,2,width*.75,GREEN)
    for i in range(5):
        wall(side,label+'BoxLeaf',6.3,37.7,z+(i-2)*width*.14,1,1.6,1.7,LEAF,True)

def pier(side,z,index):
    label=f'Pier{index:02}'
    wall(side,label+'Core',1.7,60,z,5.5,120,6,CREAM)
    wall(side,label+'ShadowFlute',4.6,67,z+1.7,.55,63,.55,TAN,True)
    wall(side,label+'HighlightFlute',4.6,67,z-1.7,.55,63,.55,LIGHT,True)
    for y,depth,w,h,c in ((3,9,9,6,TAN),(7,10,10,2,LIGHT),(29,8,9,3,TAN),
        (32,10,10,2,LIGHT),(103,8,9,3,TAN),(106,10,11,2,LIGHT),(118,10,12,4,CREAM),(121,11,13,2,GOLD)):
        wall(side,label+'CapitalCourse',2,y,z,depth,h,w,c)
    for j in range(3):
        wall(side,label+'CorniceTooth',6.1,111,z+(j-1)*2.4,1.5,2,1.5,TAN,True)
    wall(side,label+'TowerBody',0,126,z,12,8,12,CREAM)
    wall(side,label+'TowerWindow',6.2,126,z,.3,4,5,DARK)
    wall(side,label+'RoofSill',0,131,z,17,2,17,LIGHT)
    wall(side,label+'RoofGoldBand',0,132.4,z,18,.8,18,GOLD)
    for step,width in enumerate((18,16,13,10,7,4)):
        wall(side,label+'RoofStep',0,134+step*2,z,width,2,width,DEEP if step%2==0 else GREEN)
        wall(side,label+'RoofHighlight',width/2,134.8+step*2,z,.35,.4,width*.78,LEAF,True)
    wall(side,label+'FinialBase',0,146,z,2,2,2,GOLD)
    wall(side,label+'Finial',0,149,z,.8,4,.8,HIGHLIGHT)

def ivy(side,z,reverse=False):
    # Deliberate diagonal ribbons on piers; the course shapes connect into terrace planters.
    for i in range(13):
        y=40+i*4.5;zz=z+(i%5-2)*1.3*(-1 if reverse else 1)
        wall(side,'IvyStem',5.8,y,zz,.8,5,.8,DEEP,True)
        wall(side,'IvyLeaf',6.3,y+1.7,zz+(-1 if i%2 else 1)*1.7,1.1,2.7,2.9,LEAF if i%3==0 else GREEN,True)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    # Behind the original collision plane, fully covering its face; visible projection is layered.
    wall(side,'FacadeBacking',-2,60,110,4,120,220,TAN)
    for name,y,d,h,c in [('FootPlinth',2,6,4,TAN),('FootLip',4.5,7,1,LIGHT),
        ('TerraceCornice',28,6,3,TAN),('TerraceLip',30,8,1,LIGHT),('UpperCornice',106,6,3,TAN),
        ('UpperLip',109,8,2,LIGHT),('SkylineCornice',118,9,3,CREAM),('SkylineGold',120,9,.8,GOLD)]:
        long_course(side,name,y,d,h,c)
    for row in range(3):
        for col in range(12):
            z=9.2+col*18.4
            width=min(18.2,2*z,2*(220-z))
            wall(side,'LowerStoneCourse',.4,8+row*7,z,.8,6.7,width,CREAM if (row+col)%3 else LIGHT)
    piers=(10,44,80,102,162,182,210) if side<0 else (10,44,80,116,152,178,210)
    for i,z in enumerate(piers):pier(side,z,i+1)
    bays=((27,25),(62,25),(91,15),(172,13),(196,22)) if side<0 else ((27,25),(62,25),(98,25),(134,25),(165,18))
    for i,(z,width) in enumerate(bays):window(side,z,width,i+1)
    for z in (12,44,80,164,182,210):ivy(side,z,reverse=side>0)
    for z in range(20,207,10):
        wall(side,'CrownGardenRail',2,122,z,4,2.2,8,GREEN)
        wall(side,'CrownBrassPost',3,124,z,.8,3,.8,GOLD,True)
    spans=[(0,104),(160,220)] if side<0 else [(0,176),(214,220)]
    for start,end in spans:
        length=end-start;z=(start+end)/2
        for d,u,y,h,c in ((9,5,2,3,TEAL),(10,5,4,1,GOLD),(7,5,6,3,GREEN),(5,4.4,8.5,2,GREEN),(3,3.2,10.6,2,DEEP)):
            wall(side,'ContinuousHedgeTerrace',u,y,z,d,h,length,c)
        box(group,'EdgeChannelBasin',(6,.6,length),(side*63,0.6,z),TEAL)
        box(group,'EdgeChannelWater',(4.5,.18,length),(side*63,.98,z),WATER,WaterFace='Top')
        for bank in (59.5,66.5):
            box(group,'ChannelStoneBank',(1,.8,length),(side*bank,.75,z),CREAM)
            box(group,'ChannelBrassLip',(.35,.18,length),(side*(bank-.6),1.25,z),GOLD)
        for zz in range(math.ceil(start/8)*8+4,int(end)-3,8):
            wall(side,'TerraceLeafBlock',10.2,6.5,zz,1.4,2,4.5,LEAF,True)
        for zz in range(math.ceil(start/18)*18+6,int(end)-4,18):
            box(group,'ChannelMarkerBase',(2.3,.7,2.3),(side*58.5,.7,zz),TAN)
            box(group,'ChannelMarkerPost',(1.6,3.2,1.6),(side*58.5,2.65,zz),CREAM)
            box(group,'ChannelMarkerCap',(2.4,.5,2.4),(side*58.5,4.5,zz),GOLD)
    for z in ((27,62,92,174,200) if side<0 else (27,62,98,134,164)):topiary(side,z)
    box(group,'FireflyAnchor',(1,1,1),(side*62,9,66),LEAF,True,Ambient=True,Hidden=True)

# Frank's existing wood shed fits inside this larger opening; no new platform, prompts or knives.
for z in (102,162):
    wall(-1,'GroundskeeperPortalJamb',4.5,45,z,8,50,4.5,CREAM)
    wall(-1,'GroundskeeperPortalBrass',9,45,z,.7,50,.7,GOLD)
for i in range(8):
    for s in (-1,1):
        wall(-1,'GroundskeeperPortalArch',6,71+i*2.2,132+s*(28-i*3.2),8,2.4,4.2,GOLD)
wall(-1,'GroundskeeperPortalShadow',.5,62,132,1,60,51,DARK)
wall(-1,'ToolRackBeam',8.2,39,132,1.2,3,27,WOOD)
for z in (121,143):
    wall(-1,'GardenToolHandle',9,48,z,.7,16,.7,WOOD)
wall(-1,'GardenShovelBlade',9.5,41,121,1,4.5,4,SILVER)
wall(-1,'GardenRakeHead',9.5,55,143,1,1.2,7,SILVER)
for z in (140,142,144,146):wall(-1,'GardenRakeTooth',9.5,53.5,z,.8,2.4,.6,SILVER,True)
# Watering-can relief above the opening: native blocks, not text or a flat picture.
wall(-1,'WateringCanBody',9,96,132,2,7,9,GREEN)
wall(-1,'WateringCanLip',10,100,132,2.4,1.2,10,GOLD)
for y in (95,99):wall(-1,'WateringCanHandle',9,y,125,1,1,5,GOLD)
wall(-1,'WateringCanHandleBack',9,97,122.8,1,5,1,GOLD)
for n in range(3):wall(-1,'WateringCanSpout',9,94+n,139+n*1.5,1.2,1.4,2,GOLD)

for group,z in (('Entrance',6),('Exit',214)):
    for side in (-1,1):
        box(group,'GatePylon',(10,62,12),(side*70,31,z),CREAM)
        box(group,'GateBase',(14,4,12),(side*70,2,z),TAN)
        box(group,'GateBrassFlute',(.7,42,12),(side*63.8,33,z),GOLD,True)
        box(group,'GateCapital',(16,4,12),(side*70,63,z),LIGHT)
    # Each arch row is a wider horizontal bridge; lowest central soffit is 70.
    box(group,'GateMainBeam',(140,8,10),(0,95,z),CREAM)
    box(group,'GateUpperLip',(148,3,12),(0,101,z),LIGHT)
    box(group,'GateGoldCourse',(144,1.4,11),(0,103.3,z),GOLD)
    for side in (-1,1):
        box(group,'GateSpringer',(14,26,10),(side*64,82,z),CREAM)
    for step in range(11):
        for side in (-1,1):
            soffit=70+step*1.8
            box(group,'GateArchStep',(5.8,95-soffit,10),(side*(58-step*5.7),(95+soffit)/2,z),CREAM)
            box(group,'GateArchBrass',(5.8,.65,10.4),(side*(58-step*5.7),soffit+.325,z),GOLD)
    for x in range(-64,65,8):
        box(group,'GateCrownBaluster',(1.5,5,6),(x,106,z),GOLD,True)
    box(group,'GateCrownGarden',(138,3,8),(0,109,z),GREEN)

# The grand fountain is in the RIGHT rear wall, not a new obstacle at the exit.
box('Fountain','FountainNiche',(2,87,40),(79,44,195),DARK)
for z in (176,214):
    box('Fountain','FountainPier',(5,85,5),(75,42.5,z),CREAM)
    for y in (4,28,52,82):box('Fountain','FountainPierCapital',(7,2.6,7),(75,y,z),GOLD)
for level,(y,w,depth,x) in enumerate(((2,36,20,68),(20,28,14,71),(38,21,10,73),(56,14,7,74.5))):
    box('Fountain','BasinStep',(depth,1.2,w),(x,y,195),TAN)
    box('Fountain','BasinBrassRim',(depth+.4,.8,w+.4),(x,y+1,195),GOLD)
    box('Fountain','BasinLip',(depth+.2,.6,w+.2),(x,y+1.65,195),LIGHT)
    box('Fountain','BasinWater',(depth-1,.15,w-1),(x,y+2.05,195),WATER,WaterFace='Top')
    for zz in (-.4,.4):
        box('Fountain','BasinEndStud',(2.2,1.4,2.2),(x-depth/2+1,y+2,195+zz*w),HIGHLIGHT,True)
    if level:
        base_y=(2,20,38)[level-1]+2.2
        front=x-depth/2+.4
        box('Fountain','CascadingWaterCurtain',(.2,y-base_y,w*.72),(front,(y+base_y)/2,195),WATER,WaterFace='Left')
        for j in (-2,0,2):
            box('Fountain','CascadeFoamColumn',(.08,y-base_y,w*.06),(front-.14,(y+base_y)/2,195+j*w*.11),LIGHT,True)
    if level<3:
        box('Fountain','BasinSupport',(4,13,4),(76,y+9,195),TEAL)
box('Fountain','TopSpring',(.4,12,5),(74,64,195),WATER,WaterFace='Left')
box('Fountain','SpringCrown',(4,2,6),(74,70,195),GOLD)
# Leaf crest from a fixed pixel grid, each visible rectangle is physical geometry.
leaf=['....g....','...ggg...','..glll...','.gllllg..','ggllLllg.','.gllLllgg','..glLllg.','...gLlg..','....gg...']
for row in range(-9,10):
    half=9-abs(row)
    box('Fountain','CrestDiamondShadow',(1,1.9,(half*2+1)*1.8),(75.6,82+row*1.8,195),DARK)
    if half:
        box('Fountain','CrestDiamondInset',(.4,1.8,max(1,half*2-1)*1.8),(74.9,82+row*1.8,195),TEAL)
    for side in (-1,1):
        box('Fountain','CrestDiamondBrass',(.5,1.9,1.9),(74.6,82+row*1.8,195+side*half*1.8),GOLD)
for row,line in enumerate(leaf):
    for col,cell in enumerate(line):
        if cell!='.':
            box('Fountain','LeafCrestBlock',(1.3,1.8,1.8),(74,89-row*1.8,195+(col-4)*1.8),
                DEEP if cell=='g' else (143,212,90) if cell=='L' else LEAF)

# One continuous flat floor skin, inset stripe borders and five stepped diamond inlays.
box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),CREAM,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.8,2.4,TEAL),(52.8,1.5,GOLD),(50.8,1.5,LIGHT)):
        box('Floor','InlaidLongitudinalBorder',(w,.01,220),(side*x,.222,110),c)
    spans=[(0,104),(160,220)] if side<0 else [(0,220)]
    for lo,hi in spans:box('Floor','EdgeWalkway',(7,.015,hi-lo),(side*56.5,.2075,(lo+hi)/2),TAN)
for z in (24,66,108,150,192):
    # Run-length merged square pixels; same discrete stepped silhouette as the reference.
    for rz in range(-6,7):
        for ring,(rad,col) in enumerate(((6,GOLD),(4,TEAL),(2,CREAM))):
            w=rad-abs(rz)
            if w>=0:
                box('Floor','DiamondInlay',(max(1,2*w+1)*1.8,.007,1.8),(0,.225+ring*.004,z+rz*1.8),col)
    box('Floor','DiamondCentre',(1.8,.005,1.8),(0,.2385,z),GOLD)
for z in range(8,220,8):box('Floor','PavingSeamCross',(98,.003,.05),(0,.2265,z),TAN,True)
for x in range(-48,49,8):box('Floor','PavingSeamLength',(.05,.003,220),(x,.2265,110),TAN,True)

all_parts=[part for values in groups.values() for part in values]
total=len(all_parts)+7 # six atomic group pivots and one assembly pivot
assert total<3000,(total,'part budget exceeded')
geometry={'Version':1,'Name':'CourtyardShell','Boss':'Frank','BossTitle':'The Groundskeeper',
 'Origin':[0,0,0],'FrontAxis':'-Z at the entrance; travel/deeper axis +Z',
 'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
 'ClearLane':{'MinX':-56,'MaxX':56,'MinZ':0,'MaxZ':220,'OverheadClearance':52},
 'ReservedLair':{'Center':[-73,0,132],'StageX':[-80,-66],'StageZ':[111,153],
    'ClearX':[-80,-62],'ClearZ':[105,159],'ClearHeight':32},
 'Groups':groups,'PartCount':total,'GeometryPartCount':len(all_parts),
 'LowPartCount':sum(not p.get('Detail',False) for p in all_parts)+7,
 'FinePartCount':sum(p.get('Detail',False) for p in all_parts),
 'OmittedForLairClearance':omitted,
 'Features':{'FountainCenter':[68,0,195],'EntrancePlane':0,'ExitPlane':220,
    'GateCenters':[6,214],'PortalCenterZ':132},
 'CameraViews':{
    'entrance':{'Position':[0,20,-28],'Target':[0,32,150],'Fov':68},
    'mid':{'Position':[0,16,95],'Target':[50,35,190],'Fov':70},
    'landmark':{'Position':[0,49,154],'Target':[74,49,195],'Fov':75},
    'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':248},
    'left-wall':{'Position':[165,68,110],'Target':[-80,68,110],'Ortho':242},
    'right-wall':{'Position':[-165,68,110],'Target':[80,68,110],'Ortho':242}}}
(OUT/'geometry.json').write_text(json.dumps(geometry,indent=2)+'\n',encoding='utf-8')

def lua(value):
    if isinstance(value,dict):return '{'+','.join(f'[{json.dumps(k)}]={lua(v)}' for k,v in value.items())+'}'
    if isinstance(value,(tuple,list)):return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,bool):return 'true' if value else 'false'
    if value is None:return 'nil'
    return json.dumps(value)
folder=ROOT/'src/shared/Config/ToyGeometry/CourtyardShell';folder.mkdir(parents=True,exist_ok=True)
for name,parts in groups.items():
    block_type='type Block = {Name: string, Size: {number}, Offset: {number}, Color: {number}, Detail: boolean?, WaterFace: string?, Ambient: boolean?, Hidden: boolean?, Stud: boolean?}\n'
    rows='\n'.join('\t'+lua(part)+',' for part in parts)
    (folder/f'{name}.luau').write_text('--!strict\n-- Generated authored native blocks; regenerate with tools/build_courtyard_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'+rows+'\n}\nreturn blocks\n',encoding='utf-8')
config='--!strict\n-- Asset data only. Origin (0,0,0) = Courtyard entrance; +Z goes deeper.\nreturn {\n'
for name in ('Version','Name','Boss','BossTitle','Origin','FrontAxis','Bounds','ClearLane','ReservedLair','PartCount','LowPartCount','Features'):
    config+=f'{name}={lua(geometry[name])},\n'
config+='Groups={'+','.join(name+'=require(script.Parent.CourtyardShell.'+name+')' for name in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/CourtyardShellData.luau').write_text(config,encoding='utf-8')
print(json.dumps({'PartCount':total,'LowPartCount':geometry['LowPartCount'],
    'FineParts':geometry['FinePartCount'],'Groups':{k:len(v) for k,v in groups.items()}}))
