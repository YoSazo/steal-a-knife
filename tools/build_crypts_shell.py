"""Sam's Crypts: measured cuboid authoring only; Claude owns registration."""
from pathlib import Path
from collections import Counter
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Crypts';OUT.mkdir(parents=True,exist_ok=True)
STONE=(49,36,73); MID=(74,52,95); EDGE=(95,67,119); DARK=(20,14,38)
VIOLET=(111,37,155); GEM=(172,34,191); GOLD=(145,91,32); BRONZE=(103,62,27)
BONE=(167,128,77); WATER=(56,24,99); FLOOR=(54,42,73)
groups={name:[] for name in ('LeftWall','RightWall','Entrance','Exit','Mausoleum','Floor')}
counts=Counter();omitted=[]
def box(group,name,size,pos,color,detail=False,**flags):
    lo=[pos[i]-size[i]/2 for i in range(3)];hi=[pos[i]+size[i]/2 for i in range(3)]
    assert min(size)>0,name
    if lo[0]<-62 and hi[0]>-80 and lo[2]<159 and hi[2]>105 and lo[1]<32:
        omitted.append(name);return
    assert lo[2]>=(-3.001 if group=='Entrance' else -.001) and hi[2]<=220.001,(name,'depth',lo,hi)
    if group!='Floor' and lo[0]<56 and hi[0]>-56:assert lo[1]>=70,(name,'lane',lo)
    if group=='Floor':assert hi[1]<=.241
    counts[(group,name)]+=1
    row={'Name':f'{name}_{counts[(group,name)]:03}','Size':[round(x,4) for x in size],'Offset':[round(x,4) for x in pos],'Color':list(color)}
    if detail:row['Detail']=True
    row.update(flags);groups[group].append(row)
def wall(side,name,u,y,z,d,h,w,c,detail=False):
    box('LeftWall' if side<0 else 'RightWall',name,(d,h,w),(side*(80-u),y,z),c,detail)
def face(group,name,x,y,z,d,h,w,c,detail=False):box(group,name,(d,h,w),(x,y,z),c,detail)
def diamond(group,name,x,y,z,r,detail=True):
    for i,width in enumerate((1,3,5,3,1)):
        face(group,name+'Bronze',x,y+(i-2)*r/3,z,.8,r/3+.03,width*r/3,GOLD,detail)
        if width>1:face(group,name+'Gem',x+(-.5 if x>0 else .5),y+(i-2)*r/3,z,.4,r/3,width*r/3-.5,GEM,detail)
def skull(group,name,x,y,z,scale,detail=True):
    # Merge each horizontal bitmap run, preserving hollow eyes and separated teeth.
    rows=('001111100','011111110','111111111','100111001','100111001','111010111','011000110','001111100','001010100')
    for iy,row in enumerate(rows):
        start=None
        for iz,ch in enumerate(row+'0'):
            if ch=='1' and start is None:start=iz
            if ch=='0' and start is not None:
                face(group,name+'BoneRun',x,y+(4-iy)*scale,z+((start+iz-1)/2-4)*scale,1.2,scale,(iz-start)*scale,BONE,detail);start=None
    face(group,name+'DarkBacking',x+(.8 if x>0 else -.8),y,z,.5,9.5*scale,9.5*scale,DARK,detail)
def shovel(group,name,x,y,z,step,direction,detail=True):
    for i in range(9):face(group,name+'Handle',x,y+i*step,z+direction*i*step,1,step*1.25,step*1.25,BRONZE,detail)
    for i,w in enumerate((3,4,4,3,1)):
        face(group,name+'Spade',x-.3 if x>0 else x+.3,y+(8+i)*step,z+direction*(8+i)*step,1.2,step,w*step,BONE,detail)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'CryptRetainingBacking',-2,60,110,4,120,220,STONE)
    for name,y,h,d,c in (('Foundation',3,6,7,DARK),('BronzeFootCourse',6.5,1,8,GOLD),('LowerStoneBelt',20,3,7,MID),
        ('LowerPurpleBand',22,1,8,VIOLET),('CryptMiddleCourse',38,4,8,MID),('BronzeMiddleBand',41,1.5,9,BRONZE),
        ('UpperLintelRun',103,5,8,MID),('UpperBronzeLip',107,1.2,9,GOLD),('CrenellatedParapet',117,6,8,STONE)):
        spans=((0,104),(160,220)) if side<0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,name,2,y,(a+b)/2,d,h,b-a,c)
    piers=(10,44,96,168,210) if side<0 else (10,44,80,116,152,210)
    for z in piers:
        wall(side,'CryptButtress',3.5,64,z,7,116,7,MID)
        wall(side,'ButtressDarkInset',7.4,66,z,.8,99,3.6,DARK)
        wall(side,'ButtressVioletRibbon',8,61,z,.6,65,1.7,VIOLET)
        for y in (9,39,107,120):wall(side,'ButtressMergedCap',5,y,z,11,2.3,11,GOLD)
        skull(group,'ButtressSkull',side*70.6,78,z,1.05)
        for y in (30,99):diamond(group,'ButtressGem',side*70.5,y,z,2)
        for y,w,c in ((125,10,MID),(129,7,STONE),(133,4,VIOLET),(137,2,GEM)):
            wall(side,'CryptSkylineSpire',3,y,z,w,4,w,c)
    bays=((27,23),(70,33),(184,27)) if side<0 else ((27,23),(62,23),(98,23),(134,23),(178,35))
    for z,w in bays:
        wall(side,'RecessedTombShadow',1.4,64,z,1,63,w,DARK)
        for sign in (-1,1):
            wall(side,'TombArchJamb',3.4,61,z+sign*w/2,3,54,2.5,BRONZE)
            for i in range(6):wall(side,'SteppedTombArch',4,88+i*2.1,z+sign*(w/2-i*w/12),3,2.2,w/6+.4,GOLD,True)
        wall(side,'TombSill',4,34,z,5,2,w+5,MID)
        for zz in (-.25,0,.25):wall(side,'CryptIronBar',3.6,62,z+zz*w,1,43,1,VIOLET,True)
        wall(side,'IronCrossRail',4,53,z,1,1,w-.5,EDGE,True)
        if z==27:skull(group,'NicheSkull',side*74.8,73,z,1)
        # Every sarcophagus remains on the peripheral shelf, behind the clear lane.
        for y,h,d,ww,c in ((8,8,11,w*.8,MID),(13,2,13,w*.88,GOLD),(16,4,10,w*.73,STONE),(19,2,7,w*.55,EDGE)):
            wall(side,'SarcophagusTier',10,y,z,d,h,ww,c)
        diamond(group,'CoffinGem',side*63.8,10,z,1.7)
        for dz in (-w*.23,w*.23):wall(side,'CoffinBronzeCorner',15.3,9,z+dz,.6,7,1.2,BRONZE,True)
    spans=((0,104),(160,220)) if side<0 else ((0,168),(212,220))
    for a,b in spans:
        length=b-a;z=(a+b)/2
        box(group,'PurpleChannelBed',(5,.6,length),(side*60,.55,z),DARK)
        box(group,'MattePurpleWater',(3.5,.15,length),(side*60,.97,z),WATER,WaterFace='Top')
        for x in (57.7,62.3):box(group,'ChannelBronzeBank',(.8,.8,length),(side*x,.8,z),BRONZE)
        for zz in range(a+8,b-4,22):
            box(group,'ChannelSquaredPost',(2.2,4,2.2),(side*57.8,2.5,zz),MID)
            box(group,'ChannelPostGem',(1.4,.8,1.4),(side*57.8,5,zz),GEM,True)
    # Thin mortar scores are fine trim; full coloured courses are already merged.
    for y in range(8,118,10):wall(side,'MortarLongRun',.2,y,110,.2,.16,220,DARK,True)
    for z in range(6,220,14):wall(side,'MortarVerticalRun',.2,64,z,.2,111,.12,DARK,True)

# Sam's stage and approach occupy left X[-80,-62], Z[105,159], below32.
for z in (102,162):
    wall(-1,'GravediggerPortalPier',5,55,z,9,74,7,MID)
    wall(-1,'PortalPurpleFlute',10,57,z,.9,61,2,VIOLET)
for sign in (-1,1):
    for i in range(9):wall(-1,'GravediggerPortalArch',6.3,85+i*1.8,132+sign*(28-i*3.1),8,2,4,GOLD)
wall(-1,'LairHighCryptRecess',.6,64,132,1,60,53,DARK)
skull('LeftWall','GravediggerCrest',-70.8,111,132,2.1,False)
shovel('LeftWall','PortalShovelLeft',-70.4,94,114,1.15,1)
shovel('LeftWall','PortalShovelRight',-70.4,94,150,1.15,-1)

# Exact Gardens structural interface; upstream ExitFlower accents are not duplicated.
previous=json.loads((ROOT/'assets/biome-shells/Gardens/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('GardenExit_')]
assert len(previous_exit)==75
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','GardensSeam_'+p['Name'],(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False))
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size']
    c=GOLD if p['Color']==[18,49,137] else STONE
    box('Exit','CryptExit_'+p['Name'],(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
# Exit crest faces upstream and is not part of the next structural seam.
for i,w in enumerate((3,7,11,7,3)):
    box('Exit','ExitGemCrest',(w,2,.8),(0,107+i*2,208.4),GEM,True)

# A dimensional gravedigger mausoleum on the far +X wall, not an unrelated prop.
for y,h,depth,width,c in ((3,5,24,42,DARK),(6.5,2,24,42,GOLD),(11,7,21,39,MID),
    (16,2,23,41,BRONZE),(36,37,17,35,STONE),(57,4,20,39,GOLD),(75,32,15,32,MID),
    (94,4,19,36,BRONZE),(109,26,14,29,STONE),(124,4,18,35,GOLD)):
    box('Mausoleum','MausoleumMergedTier',(depth,h,width),(68, y,190),c)
face('Mausoleum','MausoleumDoorRecess',58.9,33,190,1,25,15,DARK)
for sign in (-1,1):
    face('Mausoleum','DoorJamb',58.3,33,190+sign*8,2,26,2,GOLD)
    for i in range(5):face('Mausoleum','DoorSteppedArch',58,47+i*1.5,190+sign*(7-i*1.5),2,1.7,2,GOLD,True)
    face('Mausoleum','TowerPilaster',59,88,190+sign*13,4,57,3,EDGE)
    face('Mausoleum','TowerVioletRibbon',56.8,88,190+sign*13,.6,45,1.6,VIOLET)
    diamond('Mausoleum','TowerGem',56.5,102,190+sign*13,2.8,False)
skull('Mausoleum','GreatSkull',59.8,79,190,2.8,False)
shovel('Mausoleum','CrossedShovelA',57.2,23,179,1.5,1,False)
shovel('Mausoleum','CrossedShovelB',57.2,23,201,1.5,-1,False)
for x in (59,76):
    for z in (176,204):
        for y,h,w,c in ((127,4,8,EDGE),(141,24,5,MID),(154,3,7,GOLD),(157,3,5,STONE),(160,3,3,VIOLET),(163,2,1.6,GEM)):
            box('Mausoleum','FourCornerSpire',(w,h,w),(x,y,z),c)
        diamond('Mausoleum','SpireGem',x-3,144,z,1.5)
for i,(w,y) in enumerate(((22,130),(17,134),(12,138),(7,142))):
    box('Mausoleum','SteppedTowerPediment',(13,4,w),(68,y,190),MID if i%2==0 else GOLD)
diamond('Mausoleum','PedimentGem',60.6,136,190,3.3,False)
for z in (174,206):
    for y in (19,41,64,92,116):face('Mausoleum','TierCornerClamp',57.6,y,z,1.2,2.4,2.4,GOLD,True)
for y in range(23,119,7):face('Mausoleum','LandmarkMortar',59.2,y,190,.3,.16,29,DARK,True)

box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,width,c in ((54.5,2.5,BRONZE),(52.5,1.2,VIOLET),(51.2,1.2,DARK)):
        box('Floor','MergedFloorBorder',(width,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    for row in range(-5,6):
        width=(5-abs(row))*2+1
        box('Floor','CryptDiamondBronze',(width*1.8,.005,1.8),(0,.228,z+row*1.8),BRONZE)
        if width>2:box('Floor','CryptDiamondViolet',((width-2)*1.8,.005,1.8),(0,.233,z+row*1.8),VIOLET)
    box('Floor','InlaidGemCentre',(3.6,.004,3.6),(0,.239,z),GEM)
for x in range(-48,49,12):box('Floor','FinePavingLong',(.06,.003,220),(x,.226,110),DARK,True)
for z in range(10,220,12):box('Floor','FinePavingCross',(98,.003,.06),(0,.226,z),DARK,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
geo={'Version':1,'Name':'CryptsShell','BiomeIndex':3,'Rarity':'Epic','Boss':'Sam','BossTitle':'The Gravedigger','BossWear':[],
    'Origin':[0,0,440],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[-73,0,132],'WorldCenter':[-73,0,572],'ClearX':[-80,-62],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'GardensShell','PreviousExitWorldZ':440,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'GardenExit_','ExitProfilePrefix':'CryptExit_','ExitAccentPrefix':'ExitGemCrest',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[10,48,174],'Fov':68},
        'mid':{'Position':[20,23,75],'Target':[-73,69,132],'Fov':70},
        'landmark':{'Position':[-38,44,128],'Target':[67,85,190],'Fov':72},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,73,110],'Target':[-80,73,110],'Ortho':246},
        'right-wall':{'Position':[-170,83,110],'Target':[80,83,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(value):
    if isinstance(value,dict):return '{'+','.join(k+'='+lua(v) for k,v in value.items())+'}'
    if isinstance(value,list):return '{'+','.join(lua(v) for v in value)+'}'
    if isinstance(value,bool):return 'true' if value else 'false'
    return json.dumps(value)
folder=ROOT/'src/shared/Config/ToyGeometry/CryptsShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?}\n'
for name,rows in groups.items():
    text='--!strict\n-- Native blocks; regenerate tools/build_crypts_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    text+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{name}.luau').write_text(text)
config='--!strict\n-- Zone 3 entrance is world (0,0,440); block offsets are local.\nreturn {\n'
for name in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','Bounds','ClearLane','ReservedLair','Seam'):
    config+=name+'='+lua(geo[name])+',\n'
config+='Groups={'+','.join(name+'=require(script.Parent.CryptsShell.'+name+')' for name in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/CryptsShellData.luau').write_text(config)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'Groups':{k:len(v) for k,v in groups.items()}}))
