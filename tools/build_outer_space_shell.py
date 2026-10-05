"""Nick's Outer Space. Native cuboid asset only; Claude integrates."""
from pathlib import Path
from collections import Counter
import json,hashlib,re

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/OuterSpace';OUT.mkdir(parents=True,exist_ok=True)
NAVY=(23,27,63);PANEL=(36,31,83);VOID=(13,14,35);STEEL=(81,90,121)
SILVER=(154,166,191);VIOLET=(91,36,171);PURPLE=(128,47,211);MAGENTA=(238,51,221)
CYAN=(38,228,247);ICE=(127,239,255);MOON=(105,112,135);SHADOW=(47,47,76)
FLOOR=(30,32,78)
groups={n:[] for n in ('LeftWall','RightWall','Entrance','Exit','VoidStargate','Floor')}
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

def face(g,n,x,y,z,d,h,w,c,detail=False,**flags):box(g,n,(d,h,w),(x,y,z),c,detail,**flags)
def wall(side,n,u,y,z,d,h,w,c,detail=False,**flags):face('LeftWall' if side<0 else 'RightWall',n,side*(80-u),y,z,d,h,w,c,detail,**flags)

def octagon(g,n,x,y,z,r,cell,d,c,detail=False,inner=0,**flags):
    # Voxel outline, merged horizontal runs. Each row exactly follows the same octagonal mask.
    def inside(a,b,radius):return max(abs(a),abs(b))<=radius and abs(a)+abs(b)<=radius*1.5
    for a in range(-r,r+1):
        row=[b for b in range(-r,r+1) if inside(a,b,r) and not (inner and inside(a,b,inner))]
        runs=[]
        for b in row:
            if not runs or b>runs[-1][-1]+1:runs.append([b])
            else:runs[-1].append(b)
        for run in runs:face(g,n,x,y+a*cell,z+(run[0]+run[-1])*cell/2,d,cell,len(run)*cell,c,detail,**flags)

def star(g,n,x,y,z,s,c,detail=True):
    face(g,n+'Vertical',x,y,z,.15,4*s,.8*s,c,detail,Neon=True)
    face(g,n+'Horizontal',x,y,z,.15,.8*s,4*s,c,detail,Neon=True)

def moon_cluster(side,z,scale=1,detail=False):
    # Stacked cuboid lunar rocks; no smooth shapes or meshes.
    for u,dy,d,w,h,c in ((12,2,9,15,4,SHADOW),(14,5,8,11,5,MOON),(13,8,6,8,3,STEEL),(17,3,5,7,5,SILVER)):
        wall(side,'LunarStackedBlock',u,dy*scale,z,d*scale,h*scale,w*scale,c,detail)
    for dz,h in ((-3,6),(0,10),(4,4)):
        wall(side,'CyanCrystalDarkFoot',14,10*scale,z+dz*scale,3*scale,2*scale,3*scale,VIOLET,detail)
        wall(side,'CyanRectangularCrystal',14,(11+h/2)*scale,z+dz*scale,2*scale,h*scale,2*scale,CYAN,detail,Neon=True)
        wall(side,'CrystalBrightTop',14,(11+h)*scale,z+dz*scale,2*scale,1*scale,2*scale,ICE,True,Neon=True)
        wall(side,'CrystalFineFacet',15.03,13*scale,z+dz*scale,.12,3*scale,.5*scale,ICE,True,Neon=True)

for side in (-1,1):
    g='LeftWall' if side<0 else 'RightWall'
    wall(side,'DeepNavyStationRetainingWall',-2,60,110,4,120,220,NAVY)
    for n,y,h,d,c in (('MergedStationFoundation',3,6,10,SHADOW),('LowerVioletServiceRail',8,2,11,VIOLET),
        ('SilverBaySill',34,3,10,SILVER),('NavyStationHeader',105,6,10,STEEL),('VioletUpperBus',109,2,11,VIOLET),
        ('NavySkylineCap',116,12,9,NAVY)):
        spans=((0,104),(160,220)) if side>0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,n,2,y,(a+b)/2,d,h,b-a,c)
    piers=(10,48,92,132,210) if side<0 else (10,48,96,168,210)
    for z in piers:
        for y,h,d,w,c in ((4,6,13,14,SHADOW),(9,4,12,13,VIOLET),(61,100,8,8,STEEL),
            (35,3,12,12,SILVER),(96,3,12,12,SILVER),(108,7,12,12,NAVY),(116,6,10,10,STEEL)):
            wall(side,'StationButtressTier',5,y,z,d,h,w,c)
        wall(side,'ButtressDarkInset',9.2,65,z,.5,77,4.4,VOID)
        wall(side,'ButtressVioletConduitFrame',9.6,65,z,.3,75,2.6,VIOLET)
        wall(side,'ButtressCyanEnergyStrip',9.85,73,z,.15,49,1.2,CYAN,Neon=True,WaterFace='Right' if side<0 else 'Left')
        wall(side,'ButtressMagentaEnergyStrip',9.85,37,z,.15,21,1.2,MAGENTA,Neon=True)
        for dz in (-2.8,2.8):wall(side,'FineButtressSilverSeam',9.39,62,z+dz,.12,84,.4,SILVER,True)
        for y in (21,52,88):wall(side,'FineConduitCoupler',9.9,y,z,.2,1.3,3,PURPLE,True)
        for dz in (-4,4):
            for y in (11,103):wall(side,'FineButtressCornerBolt',11.08,y,z+dz,.2,.9,.9,SILVER,True)
    bays=((29,24),(70,30),(112,25),(183,62)) if side<0 else ((29,24),(72,30),(188,30))
    for z,w in bays:
        # Large merged void panel with stepped silver/violet corners.
        wall(side,'ObservatoryVoidPanel',1,66,z,2.3,62,w,VOID)
        for y in (35,97):wall(side,'BayVioletHorizontalRim',2.3,y,z,.6,2,w+2,VIOLET)
        for sign in (-1,1):
            wall(side,'BaySilverVerticalRim',2.8,66,z+sign*(w/2),.4,57,1.1,SILVER)
            for i in range(3):wall(side,'BaySteppedSilverCorner',3,95-i*2,z+sign*(w/2-i*1.8),.5,2.2,2.4,SILVER)
            wall(side,'BayThinMagentaInset',3.4,65,z+sign*(w/2-1.3),.14,48,.45,MAGENTA,True,Neon=True)
        for i in range(12):
            dz=((i*17+int(z))%int(w-6))-(w-6)/2;yy=44+(i*13)%43
            wall(side,'VoidPanelVoxelStar',3.25,yy,z+dz,.18,.65,.65,PURPLE if i%3 else ICE,True,Neon=True)
        star(g,'BayBrightCross',side*76.7,70,z,.8,MAGENTA)
    # Four peripheral energy-service runs. No hardware crosses Nick's approach.
    spans=((0,148),(216,220)) if side<0 else ((0,104),(160,220))
    for a,b in spans:
        z=(a+b)/2;n=b-a
        box(g,'EnergyServiceChannelShadow',(5,.6,n),(side*60,.6,z),VOID)
        box(g,'EnergyServicePurpleRim',(3.8,.18,n),(side*60,1,z),VIOLET)
        box(g,'EnergyServiceCyanCore',(2,.03,n),(side*60,1.115,z),CYAN,Neon=True,WaterFace='Top')
        for x in (57.7,62.3):box(g,'EnergyChannelSilverBank',(.8,.8,n),(side*x,.8,z),STEEL)
        for zz in range(a+8,b-4,24):
            box(g,'LowPeripheralSafetyPost',(2,3.1,2),(side*57.8,2,zz),STEEL)
            box(g,'PurpleSafetyPostCap',(2.6,.7,2.6),(side*57.8,3.8,zz),VIOLET)
            box(g,'PostCyanInset',(.3,1,1),(side*56.7,2.7,zz),CYAN,True,Neon=True)
        box(g,'MergedPurpleSafetyRail',(.6,.6,n),(side*57.8,3.3,z),PURPLE)
    for z in ((25,67,109) if side<0 else (25,70,183,206)):moon_cluster(side,z,.65)
    for z in (24,86,188):
        # Solar arrays are broad panels above the wall, grids in Detail only.
        wall(side,'SolarArrayNavySupport',6,132,z,5,29,5,NAVY)
        wall(side,'SolarArrayCyanSupportInset',8.65,132,z,.22,23,1.2,CYAN,Neon=True)
        wall(side,'SolarArrayVioletSlab',5,155,z,3.6,24,38,VIOLET)
        wall(side,'SolarArrayDarkCells',7,155,z,.35,20,34,PANEL)
        for yy in (-11,11):wall(side,'SolarArrayPurpleHorizontalEdge',7.35,155+yy,z,.4,2,39,PURPLE)
        for dz in (-18,18):wall(side,'SolarArrayPurpleVerticalEdge',7.35,155,z+dz,.4,22,2,PURPLE)
        for dz in range(-15,16,5):wall(side,'FineSolarGridVertical',7.55,155,z+dz,.12,20,.16,PURPLE,True)
        for yy in range(-8,9,4):wall(side,'FineSolarGridHorizontal',7.55,155+yy,z,.12,.16,34,PURPLE,True)
        for dz in (-18,18):
            for yy in (-11,11):wall(side,'FineSolarCornerBolt',7.62,155+yy,z+dz,.15,.7,.7,SILVER,True)
    # Panel courses use single merged long runs; sparse vertical joints are fine.
    for yy in (20,50,80):wall(side,'FineStationCourseJoin',.06,yy,110,.15,.14,220,STEEL,True)
    for z in range(8,219,14):
        for yy in (29,78):wall(side,'FineStationPanelJoin',.06,yy,z,.15,32,.12,STEEL,True)

# Nick's right-side helmet/lair bay. High trim stays above his unchanged stage.
for z in (102,162):wall(1,'NickBaySilverPier',5,64,z,9,80,7,STEEL)
wall(1,'NickUpperVoidRecess',1,65,132,2,65,53,VOID)
wall(1,'NickBayVioletHeader',10,46,132,5,7,63,VIOLET)
wall(1,'NickBaySilverLintel',13,50,132,3,2,65,SILVER)
for sign in (-1,1):
    for i in range(4):wall(1,'NickHelmetSteppedShoulder',13,64+i*5,132+sign*(27-i*2),5,5.1,5.4,VIOLET)
    wall(1,'HelmetSideRadioBlock',13,85,132+sign*29,7,12,5,PURPLE)
    wall(1,'HelmetSideCyanRadioInset',17.1,85,132+sign*29,.2,5,3,CYAN,Neon=True)
for yy,w,h in ((64,28,5),(70,43,7),(82,54,18),(94,45,7),(101,31,7)):
    wall(1,'HelmetPurpleShellRow',15,yy,132,4,h,w,VIOLET)
for yy,w,h in ((70,31,3),(74,41,5),(84,47,15),(95,37,5),(99,28,3)):
    wall(1,'HelmetSilverVisorRim',17.5,yy,132,1.2,h,w,SILVER)
for yy,w,h in ((74,30,3),(80,40,9),(89,38,9),(94,26,3)):
    wall(1,'HelmetBlackVisorRow',18.3,yy,132,.6,h,w,VOID)
wall(1,'HelmetCyanVisorGlint',18.8,91,125,.2,3,9,CYAN,Neon=True)
wall(1,'HelmetSmallVisorGlint',18.8,88,131,.2,3,3,ICE,Neon=True)
wall(1,'HelmetNeckSeal',15,59,132,5,5,24,NAVY)
wall(1,'HelmetSilverNeckRidge',17.65,58,132,.25,1.2,21,SILVER)
for dz in (-7,-3.5,0,3.5,7):wall(1,'FineHelmetChinVent',18.05,64,132+dz,.2,1.6,1.8,VOID,True)
for sign in (-1,1):
    for yy in (44,58,100):wall(1,'FineNickBaySilverJoint',10.9,yy,132+sign*30,.16,.7,2,SILVER,True)

# Exact Heavens interface; cloud crest is excluded. Short canonical names keep Studio's 100-char limit.
previous=json.loads((ROOT/'assets/biome-shells/Heavens/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('HeavensExit_')]
assert len(previous_exit)==75
for p in previous_exit:
    match=re.search(r'Gate[A-Za-z]+_\d{3}',p['Name']);assert match
    ident=match.group(0);x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','HeavensSeam_'+ident,(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False),ProfileSource=p['Name'])
    c=VIOLET if p['Color']==[226,155,33] else STEEL
    box('Exit','OuterSpaceExit_'+ident,(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
for i,w in enumerate((26,18,10)):
    box('Exit','ExitCosmicCrest',(w,3,7),(0,104+i*3,214),VIOLET,True)
box('Exit','ExitCosmicCore',(4,4,1),(0,107,210),MAGENTA,True,Neon=True)

# Left Void Stargate: actual voxel mask, not a texture. Core stars are cuboids.
g='VoidStargate'
for yy,h,d,w,c in ((3,5,20,63,SHADOW),(7,3,19,60,VIOLET),(10,2,18,57,SILVER),(17,11,14,51,NAVY),
    (31,14,12,26,STEEL),(43,8,11,22,VIOLET),(53,12,9,16,NAVY)):
    face(g,'PortalLayeredMountingTier',-68,yy,181,d,h,w,c)
for sign in (-1,1):
    for yy,h,d,w,c in ((8,12,12,10,STEEL),(44,62,9,7,NAVY),(79,8,12,11,SILVER),(108,49,7,6,STEEL)):
        face(g,'PortalSidePylonTier',-69,yy,181+sign*28,d,h,w,c)
    face(g,'PortalPylonPurpleFrame',-63.8,45,181+sign*28,.5,60,4,VIOLET)
    face(g,'PortalCyanPylonCore',-63.4,45,181+sign*28,.2,57,1.4,CYAN,Neon=True,WaterFace='Right')
octagon(g,'VoidDarkOctagonalInterior',-67,104,181,10,3,2,VOID)
octagon(g,'VoidPurpleSteppedHull',-64,104,181,12,3,4,VIOLET,inner=10)
octagon(g,'VoidSilverOuterBevel',-61.8,104,181,12,3,.35,SILVER,True,inner=11)
octagon(g,'VoidMagentaInnerRing',-61.3,104,181,10,3,.35,MAGENTA,inner=9,Neon=True)
for i in range(32):
    yy=((i*7)%43)-21;zz=((i*13)%41)-20
    face(g,'VoidInteriorVoxelStar',-65.85,104+yy,181+zz,.15,.65,.65,ICE if i%4==0 else PURPLE,True,Neon=True)
star(g,'VoidCentreCross',-65.6,104,181,1.8,MAGENTA,False)
for zz in (-28,-14,0,14,28):
    face(g,'FinePortalBasinSilverPlate',-57.8,8,181+zz,.3,3,10,SILVER,True)
    face(g,'PortalBasinCyanFace',-57.5,8,181+zz,.18,1.3,7,CYAN,Neon=True)
face(g,'PortalBasinMagentaFrame',-64,15,181,15,.2,55,VIOLET)
box(g,'PortalBasinEnergySurface',(12,.03,51),(-64,15.125,181),MAGENTA,Neon=True,WaterFace='Top')
for z in (153,209):box(g,'PortalBasinSilverEnd',(16,1.6,1),(-64,15,z),SILVER)
moon_cluster(-1,148,.55,True)

# Flat graphic geometry on the existing floor; no text, no collision.
box('Floor','ClearLaneStationFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.5,2.5,VIOLET),(52.7,.8,PURPLE),(51.7,.8,STEEL)):
        box('Floor','MergedStationFloorEdge',(w,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    for row,w in enumerate((2,4,7,11,15,11,7,4,2)):
        box('Floor','CosmicStarDiamondRow',(w,.004,1.3),(0,.230,z+(row-4)*1.3),VIOLET)
    for side in (-1,1):
        for i in range(4):box('Floor','CosmicStarSideRay',(4-i*.5,.004,1),(side*(7+i*1.5),.233,z),PURPLE,True)
    box('Floor','CosmicFloorCore',(2,.004,2),(0,.238,z),CYAN,Neon=True)
    for sign in (-1,1):box('Floor','CosmicFloorGlint',(.7,.004,1.3),(sign*2,.238,z),ICE,True,Neon=True)
for x in range(-48,49,12):box('Floor','FineStationPavingLong',(.06,.003,220),(x,.226,110),SHADOW,True)
for z in range(10,220,12):box('Floor','FineStationPavingCross',(98,.003,.06),(0,.226,z),SHADOW,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
assert all(len(p['Name'])<=100 for p in parts),'runtime part-name limit'
assert all(len({p['Name'] for p in rows})==len(rows) for rows in groups.values()),'unique part names'
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
flow=sum(bool(p.get('WaterFace')) for p in parts)
geo={'Version':1,'Name':'OuterSpaceShell','BiomeIndex':8,'Rarity':'Cosmic','Boss':'Nick','BossTitle':'The Void Walker','BossWear':['SpaceHelmet'],
    'Origin':[0,0,1540],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,'FlowFaces':flow,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[73,0,132],'WorldCenter':[73,0,1672],'ClearX':[62,80],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'HeavensShell','PreviousExitWorldZ':1540,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'HeavensExit_','ExitProfilePrefix':'OuterSpaceExit_','ExitAccentPrefix':'ExitCosmic',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[-8,50,172],'Fov':68},
        'mid':{'Position':[-30,44,100],'Target':[67,75,132],'Fov':80},
        'landmark':{'Position':[40,48,162],'Target':[-64,75,181],'Fov':80},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,90,110],'Target':[-80,90,110],'Ortho':246},
        'right-wall':{'Position':[-170,90,110],'Target':[80,90,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')

def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/ToyGeometry/OuterSpaceShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?, Neon:boolean?, ProfileSource:string?}\n'
for n,rows in groups.items():
    s='--!strict\n-- Native blocks; regenerate tools/build_outer_space_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    s+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{n}.luau').write_text(s)
s='--!strict\n-- Zone 8 entrance is world (0,0,1540); block offsets are local.\nreturn {\n'
for n in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','FlowFaces','Bounds','ClearLane','ReservedLair','Seam'):
    s+=n+'='+lua(geo[n])+',\n'
s+='Groups={'+','.join(n+'=require(script.Parent.OuterSpaceShell.'+n+')' for n in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/OuterSpaceShellData.luau').write_text(s)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'FlowFaces':flow,'Groups':{n:len(v) for n,v in groups.items()}}))
