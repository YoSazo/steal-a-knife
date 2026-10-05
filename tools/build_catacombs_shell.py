"""Leo's Catacombs. Asset authoring only; Claude owns world integration."""
from pathlib import Path
from collections import Counter
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Catacombs';OUT.mkdir(parents=True,exist_ok=True)
STONE=(123,68,17); AMBER=(158,87,13); EDGE=(179,101,15); GOLD=(194,112,12)
WALNUT=(68,37,22); BRONZE=(115,63,18); DARK=(27,20,15)
TEAL=(7,72,68); GEM=(9,116,102); GLINT=(38,152,120); WATER=(6,67,74); FLOOR=(117,67,20)
groups={n:[] for n in ('LeftWall','RightWall','Entrance','Exit','Treasury','Floor')}
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
def face(group,name,x,y,z,d,h,w,c,detail=False):box(group,name,(d,h,w),(x,y,z),c,detail)
def wall(side,name,u,y,z,d,h,w,c,detail=False):face('LeftWall' if side<0 else 'RightWall',name,side*(80-u),y,z,d,h,w,c,detail)
def inset(group,name,x,y,z,h,w,detail=True):
    inward=-1 if x>0 else 1
    face(group,name+'DarkSocket',x,y,z,.8,h,w,DARK,detail)
    for sign in (-1,1):
        face(group,name+'GoldJamb',x+inward*.5,y,z+sign*(w/2-.6),1,h,1.2,GOLD,detail)
        face(group,name+'GoldCap',x+inward*.5,y+sign*(h/2-.6),z,1,1.2,w,GOLD,detail)
    face(group,name+'TealInset',x+inward*.6,y,z,.5,h*.58,w*.57,TEAL,detail)
    face(group,name+'LensGlint',x+inward*.95,y+h*.13,z-w*.13,.35,h*.22,w*.17,GEM,detail)
def coin(group,name,x,y,z,s,detail=True):
    inward=-1 if x>0 else 1
    for i,w in enumerate((3,5,7,7,7,5,3)):
        face(group,name+'MergedGoldRow',x,y+(3-i)*s,z,.8,s,w*s,GOLD,detail)
        if i in (1,2,3,4,5):face(group,name+'InsetRow',x+inward*.5,y+(3-i)*s,z,.4,s,(w-2)*s,BRONZE,detail)
    face(group,name+'RelicSpine',x+inward*.9,y,z,.5,3*s,s,EDGE,detail)
def monocle(group,name,x,y,z,s,detail=False):
    inward=-1 if x>0 else 1
    widths=(3,7,9,11,11,11,11,11,9,7,3)
    for i,w in enumerate(widths):
        inner=max(0,w-4) if 2<=i<=8 else 0
        yy=y+(5-i)*s
        if inner:
            for sign in (-1,1):face(group,name+'GoldRingRun',x,yy,z+sign*(inner/2+1)*s,1.5,s,2*s,GOLD,detail)
            face(group,name+'DarkTealLensRow',x-inward*.9,yy,z,.5,s,inner*s,TEAL,detail)
        else:face(group,name+'GoldRingRun',x,yy,z,1.5,s,w*s,GOLD,detail)
    face(group,name+'LensSquareHighlight',x-inward*.5,y+s,z-2*s,.4,2*s,s,GEM,True)
    for i in range(9):
        face(group,name+'ChainLink',x,y-(5.4+i)*s,z+(3+(.6 if i%2 else 0))*s,.8,s*.8,s*.55,GOLD,True)
    inset(group,name+'ChainFob',x-inward*1.2,y-15.2*s,z+3*s,2.4*s,2*s,True)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'AmberRetainingBacking',-2,60,110,4,120,220,STONE)
    for name,y,h,d,c in (('WalnutFoundation',3,6,7,WALNUT),('BronzeFootCourse',6.5,1,8,GOLD),
        ('RelicShelfCourse',21,3,8,BRONZE),('GoldLowerLip',23.4,1.4,9,GOLD),('MergedMiddleSandstone',39,4,8,AMBER),
        ('GoldMiddleLip',42,1.5,9,GOLD),('UpperSandstoneLintel',103,5,8,AMBER),('UpperGoldLip',107,1.2,9,GOLD),
        ('ParapetStoneCourse',117,6,8,STONE),('ParapetGoldLip',121,1.2,10,GOLD)):
        spans=((0,104),(160,220)) if side>0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,name,2,y,(a+b)/2,d,h,b-a,c)
    piers=(10,44,80,116,152,210) if side<0 else (10,44,96,168,210)
    for z in piers:
        wall(side,'WalnutRelicPier',3.5,63,z,7,114,7,WALNUT)
        wall(side,'PierAmberFlute',7.4,66,z,.8,99,3.2,AMBER)
        wall(side,'PierBronzeEdge',8,66,z-1.3,.6,99,.6,BRONZE,True)
        for y in (9,39,107,120):wall(side,'PierMergedGoldCap',5,y,z,11,2.4,11,GOLD)
        coin(group,'PierRelicMedallion',side*70.5,78,z,1.05)
        inset(group,'PierTealGem',side*70.5,28,z,8,5,False)
        for y,w,c in ((125,9,AMBER),(129,6,GOLD),(133,4,BRONZE),(136,2,EDGE)):
            wall(side,'RelicUrnSkylineTier',3,y,z,w,3.5,w,c)
        inset(group,'SkylineUrnGem',side*73.6,129,z,3.5,3.5,True)
    bays=((27,23),(62,23),(98,23),(134,23),(178,35)) if side<0 else ((27,23),(70,33),(184,27))
    for z,w in bays:
        wall(side,'RelicVaultShadow',1.4,64,z,1,63,w,DARK)
        for sign in (-1,1):
            wall(side,'RelicArchJamb',3.4,61,z+sign*w/2,3,54,2.5,BRONZE)
            for i in range(6):wall(side,'RelicSteppedArch',4,88+i*2.1,z+sign*(w/2-i*w/12),3,2.2,w/6+.4,GOLD,True)
        wall(side,'RelicShelfSill',4,34,z,5,2,w+5,AMBER)
        for yy in (48,):wall(side,'RelicDisplayShelf',6,yy,z,8,2,w*.85,BRONZE,True)
        for yy in (53,):
            for dz in (-w*.24,w*.24):
                wall(side,'ArchiveUrnBody',7,yy,z+dz,4,6,4,AMBER,True)
                wall(side,'ArchiveUrnLid',7,yy+3.5,z+dz,4.8,1.5,4.8,GOLD,True)
                inset(group,'ArchiveUrnGem',side*70.5,yy,z+dz,3.2,2.5,True)
        for y,h,d,ww,c in ((8,8,11,w*.8,WALNUT),(13,2,13,w*.88,GOLD),(16,4,10,w*.73,AMBER),(19,2,7,w*.55,GOLD)):
            wall(side,'AntiqueCofferTier',10,y,z,d,h,ww,c)
        inset(group,'CofferTealLock',side*63.8,9,z,7,5,False)
        for dz in (-w*.23,w*.23):wall(side,'CofferGoldStrap',15.3,10,z+dz,.6,8,1.2,GOLD,True)
    spans=((0,168),(212,220)) if side<0 else ((0,104),(160,220))
    for a,b in spans:
        length=b-a;z=(a+b)/2
        box(group,'TealCanalBed',(5,.6,length),(side*60,.55,z),DARK)
        box(group,'MatteTealWater',(3.5,.15,length),(side*60,.97,z),WATER,WaterFace='Top')
        for x in (57.7,62.3):box(group,'CanalGoldBank',(.8,.8,length),(side*x,.8,z),BRONZE)
        for zz in range(a+8,b-4,22):
            box(group,'CanalSquarePost',(2.2,4,2.2),(side*57.8,2.5,zz),WALNUT)
            box(group,'CanalGoldCap',(2.8,.8,2.8),(side*57.8,5,zz),GOLD,True)
    for y in range(8,118,10):wall(side,'FineMasonryLong',.2,y,110,.2,.16,220,BRONZE,True)
    for z in range(6,220,14):wall(side,'FineMasonryVertical',.2,64,z,.2,111,.12,BRONZE,True)

# Leo's stage and entire approach are clear on the RIGHT (+X) side.
for z in (102,162):
    wall(1,'CollectorPortalPier',5,55,z,9,74,7,WALNUT)
    wall(1,'PortalAmberFlute',10,57,z,.9,61,2,GOLD)
for sign in (-1,1):
    for i in range(9):wall(1,'CollectorPortalArch',6.3,85+i*1.8,132+sign*(28-i*3.1),8,2,4,GOLD)
wall(1,'LairHighRelicRecess',.6,64,132,1,60,53,DARK)
monocle('RightWall','CollectorPortalMonocle',70.8,112,132,1.4,False)

# Entrance uses ONLY CryptExit_ structural pieces, preserving all depths and colours.
previous=json.loads((ROOT/'assets/biome-shells/Crypts/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('CryptExit_')]
assert len(previous_exit)==75
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','CryptsSeam_'+p['Name'],(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False))
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];c=GOLD if p['Color']==[145,91,32] else AMBER
    box('Exit','CatacombExit_'+p['Name'],(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
for i,w in enumerate((3,7,9,7,3)):box('Exit','ExitRelicCrest',(w,1.8,.8),(0,108+i*1.8,208.4),GOLD,True)

# Large coffer-like treasury built into the far LEFT retaining wall, outside the lane.
for y,h,d,w,c in ((3,5,24,42,WALNUT),(6.5,2,24,42,GOLD),(11,7,21,39,STONE),(16,2,23,41,GOLD),
    (43,52,17,35,WALNUT),(71,4,21,39,GOLD),(85,24,17,35,STONE),(99,4,22,40,GOLD),
    (111,20,15,32,AMBER),(124,4,20,39,GOLD),(129,5,18,36,STONE),(133,3,16,33,GOLD)):
    box('Treasury','TreasuryMergedTier',(d,h,w),(-68,y,190),c)
for sign in (-1,1):
    face('Treasury','TwinTreasuryPier',-59,72,190+sign*14,4,102,4,AMBER)
    face('Treasury','TreasuryPierGoldEdge',-56.7,73,190+sign*14,.5,101,1.2,GOLD)
    for y in (20,51,99,126):face('Treasury','PierBronzeClamp',-58.5, y,190+sign*14,5,2,6,GOLD)
    inset('Treasury','TreasuryPierGem',-57.8,34,190+sign*14,11,6,False)
monocle('Treasury','GreatCollectorMonocle',-57,88,190,2.5,False)
for y in range(23,123,8):face('Treasury','TreasuryMortarRun',-59.2,y,190,.3,.16,30,BRONZE,True)
for z in (181,190,199):
    for y,d,w,h,c in ((139,7,7,6,AMBER),(143,8.5,8.5,2,GOLD),(147,5,5,6,STONE),(151,6,6,2,GOLD)):
        box('Treasury','ThreeRelicUrnTier',(d,h,w),(-68,y,z),c)
    inset('Treasury','UrnTealRelic',-64,146,z,4,4,True)
for z in (176,204):
    for y,h,w,c in ((131,4,8,EDGE),(140,14,5,WALNUT),(148,2,7,GOLD),(151,4,4,AMBER),(154,2,2,GOLD)):
        box('Treasury','CornerArchivePillar',(w,h,w),(-59,y,z),c)
    inset('Treasury','CornerRelic',-56.4,140,z,6,3.5,True)
for z in (182,198):inset('Treasury','FriezeTealRelic',-59.7,113,z,7,6,True)

box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.5,2.5,GOLD),(52.5,1.2,BRONZE),(51.2,1.2,WALNUT)):box('Floor','MergedFloorBorder',(w,.008,220),(side*x,.222,110),c)
for z in (24,66,108,150,192):
    for row in range(-5,6):
        w=(5-abs(row))*2+1
        box('Floor','RelicDiamondGold',(w*1.8,.005,1.8),(0,.228,z+row*1.8),GOLD)
        if w>2:box('Floor','RelicDiamondBronze',((w-2)*1.8,.005,1.8),(0,.233,z+row*1.8),BRONZE)
    box('Floor','InlaidTealGem',(3.6,.004,3.6),(0,.239,z),TEAL)
for x in range(-48,49,12):box('Floor','FinePavingLong',(.06,.003,220),(x,.226,110),BRONZE,True)
for z in range(10,220,12):box('Floor','FinePavingCross',(98,.003,.06),(0,.226,z),BRONZE,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
geo={'Version':1,'Name':'CatacombsShell','BiomeIndex':4,'Rarity':'Legendary','Boss':'Leo','BossTitle':'The Collector','BossWear':['Monocle'],
    'Origin':[0,0,660],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[73,0,132],'WorldCenter':[73,0,792],'ClearX':[62,80],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'CryptsShell','PreviousExitWorldZ':660,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'CryptExit_','ExitProfilePrefix':'CatacombExit_','ExitAccentPrefix':'ExitRelicCrest',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[-10,48,174],'Fov':68},
        'mid':{'Position':[-20,23,75],'Target':[73,69,132],'Fov':70},
        'landmark':{'Position':[38,44,128],'Target':[-67,86,190],'Fov':72},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,80,110],'Target':[-80,80,110],'Ortho':246},
        'right-wall':{'Position':[-170,73,110],'Target':[80,73,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/ToyGeometry/CatacombsShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?}\n'
for n,rows in groups.items():
    s='--!strict\n-- Native blocks; regenerate tools/build_catacombs_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    s+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{n}.luau').write_text(s)
s='--!strict\n-- Zone 4 entrance is world (0,0,660); block offsets are local.\nreturn {\n'
for n in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','Bounds','ClearLane','ReservedLair','Seam'):s+=n+'='+lua(geo[n])+',\n'
s+='Groups={'+','.join(n+'=require(script.Parent.CatacombsShell.'+n+')' for n in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/CatacombsShellData.luau').write_text(s)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'Groups':{n:len(v) for n,v in groups.items()}}))
