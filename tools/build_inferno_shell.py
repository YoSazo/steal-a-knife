"""Ruby's Inferno. Measured asset authoring only; Claude integrates."""
from pathlib import Path
from collections import Counter
import json, hashlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/biome-shells/Inferno';OUT.mkdir(parents=True,exist_ok=True)
BASALT=(30,24,28); ROCK=(49,32,34); IRON=(58,48,51); BLACK=(13,11,16)
OXIDE=(114,25,14); RED=(158,30,9); EMBER=(207,57,7); LAVA=(185,37,4); HOT=(229,89,9)
FLOOR=(39,29,31); RIVET=(94,66,55)
groups={n:[] for n in ('LeftWall','RightWall','Entrance','Exit','HornedForge','Floor')}
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
def horn(group,name,x,y,z,s,direction,detail=False,rise=1):
    # Axis-aligned thick steps form a rising swept horn, no wedge/mesh dependency.
    last_offset=None;last_width=None
    for i,w in enumerate((5,5,4,3,2,1.3)):
        offset=min(i*1.9,8.95)
        if last_offset is not None:assert offset-last_offset < (w+last_width)/2, 'connected horn steps'
        face(group,name+'SweptStep',x,y+i*2.4*s*rise,z+direction*(offset*s),4*s,2.7*s*rise,w*s,OXIDE if i<3 else RED,detail)
        last_offset=offset;last_width=w
    face(group,name+'IronRootClamp',x-.5 if x>0 else x+.5,y,z,4.8*s,2*s,6*s,IRON,detail)
def emberBadge(group,name,x,y,z,s,detail=True):
    inward=-1 if x>0 else 1
    face(group,name+'IronBack',x,y,z,.8,7*s,5*s,BLACK,detail)
    for i,(shift,w) in enumerate(((0,1),(-.5,2),(.5,2),(0,3),(0,4),(0,3),(0,1))):
        face(group,name+'MergedEmberRow',x+inward*.7,y+(3-i)*s,z+shift*s,.6,s,w*s,EMBER if i%2 else RED,detail)
    face(group,name+'HotCore',x+inward*1.1,y-s,z,.3,2*s,s,HOT,detail)
def rivets(group,name,x,y,z,w,detail=True):
    inward=-1 if x>0 else 1
    face(group,name+'IronPlate',x,y,z,1,3,w,IRON,detail)
    for sign in (-1,1):face(group,name+'Rivet',x+inward*.7,y,z+sign*(w/2-1),.5,.8,.8,RIVET,detail)

for side in (-1,1):
    group='LeftWall' if side<0 else 'RightWall'
    wall(side,'BasaltRetainingBacking',-2,60,110,4,120,220,BASALT)
    for name,y,h,d,c in (('BlackFoundation',3,6,7,BLACK),('RedFootCourse',6.5,1,8,OXIDE),
        ('SlagShelfCourse',21,3,8,ROCK),('EmberLowerLip',23.4,1.4,9,RED),('MergedBasaltMiddle',39,4,8,IRON),
        ('OxideMiddleLip',42,1.5,9,OXIDE),('UpperBasaltLintel',103,5,8,IRON),('RedUpperCourse',107,2,9,OXIDE),
        ('JaggedParapetBase',117,6,8,BASALT),('OxideSkylineLip',121,1.2,10,RED)):
        spans=((0,104),(160,220)) if side<0 and y-h/2<32 else ((0,220),)
        for a,b in spans:wall(side,name,2,y,(a+b)/2,d,h,b-a,c)
    piers=(10,44,96,168,210) if side<0 else (10,44,80,116,152,210)
    for z in piers:
        wall(side,'BasaltForgeButtress',3.5,63,z,7,114,7,ROCK)
        wall(side,'BlackFissureSocket',7.4,66,z,.8,98,3.8,BLACK)
        wall(side,'LavaFissureVertical',8,61,z,.6,83,2.4,LAVA,WaterFace='Right' if side<0 else 'Left')
        for y in (9,39,107,120):wall(side,'ButtressIronCap',5,y,z,11,2.4,11,IRON)
        for y in (39,107):rivets(group,'ForgeCap',side*73.5,y,z,10)
        for i in range(8):wall(side,'FissureHotPixel',8.5,26+i*10,z+(i%3-1)*.8,.3,4.5,1.8,HOT,True)
        horn(group,'SkylineDevilHorn',side*77,122,z,.65,-1 if z%4 else 1)
        emberBadge(group,'PierEmberBadge',side*70.5,82,z,1.2)
    bays=((27,23),(70,33),(184,27)) if side<0 else ((27,23),(62,23),(98,23),(134,23),(178,35))
    for z,w in bays:
        wall(side,'FurnaceNicheShadow',1.4,64,z,1,63,w,BLACK)
        for sign in (-1,1):
            wall(side,'ForgeArchJamb',3.4,61,z+sign*w/2,3,54,2.5,OXIDE)
            for i in range(6):wall(side,'SteppedForgeArch',4,88+i*2.1,z+sign*(w/2-i*w/12),3,2.2,w/6+.4,RED,True)
        wall(side,'ForgeNicheSill',4,34,z,5,2,w+5,IRON)
        wall(side,'RecessedEmberCore',2.8,64,z,.9,41,w*.45,OXIDE)
        for i in range(7):
            wall(side,'NicheCoreStep',3.4,48+i*4,z+(i%3-1)*1.5,.8,4.1,w*.22+(i%2)*2,RED if i%2 else EMBER,True)
        for zz in (-.3,0,.3):wall(side,'FurnaceIronGrate',4.8,62,z+zz*w,1,43,1.1,IRON,True)
        for y,h,d,ww,c in ((8,8,11,w*.8,ROCK),(13,2,13,w*.88,IRON),(16,4,10,w*.73,OXIDE),(19,2,7,w*.55,BASALT)):
            wall(side,'PeripheralSlagTerrace',10,y,z,d,h,ww,c)
        # Squared anvil silhouette is assembled from broad merged blocks.
        for y,h,ww,c in ((22,3,10,IRON),(25,3,4,BASALT),(28,3,13,IRON)):
            wall(side,'PeripheralAnvil',10,y,z,6,h,ww,c)
        for dz in (-w*.23,w*.23):rivets(group,'SlagIronClamp',side*64.8,10,z+dz,4)
    spans=((0,104),(160,220)) if side<0 else ((0,168),(212,220))
    for a,b in spans:
        length=b-a;z=(a+b)/2
        box(group,'LavaChannelBed',(5,.6,length),(side*60,.55,z),BLACK)
        box(group,'MatteMoltenChannel',(3.5,.15,length),(side*60,.97,z),LAVA,WaterFace='Top')
        for x in (57.7,62.3):box(group,'BasaltChannelBank',(.8,.8,length),(side*x,.8,z),IRON)
        for zz in range(a+8,b-4,22):
            box(group,'LavaBankSquarePost',(2.2,4,2.2),(side*57.8,2.5,zz),BASALT)
            box(group,'LavaPostOxideCap',(2.8,.8,2.8),(side*57.8,5,zz),OXIDE,True)
            box(group,'MoltenSurfaceRun',(1.8,.018,8),(side*60,1.057,zz),EMBER,True)
    for y in range(8,118,10):wall(side,'FineBasaltLong',.2,y,110,.2,.16,220,BLACK,True)
    for z in range(6,220,14):wall(side,'FineBasaltVertical',.2,64,z,.2,111,.12,BLACK,True)

# Ruby's stage and approach on LEFT (-X) stay clear below32studs.
for z in (102,162):
    wall(-1,'FirestarterPortalPier',5,55,z,9,74,7,ROCK)
    wall(-1,'PortalRedFlute',10,57,z,.9,61,2,RED)
for sign in (-1,1):
    for i in range(9):wall(-1,'FirestarterPortalArch',6.3,85+i*1.8,132+sign*(28-i*3.1),8,2,4,OXIDE)
wall(-1,'LairHighForgeRecess',.6,64,132,1,60,53,BLACK)
wall(-1,'DevilCrestIronBridge',7,108,132,8,3,34,IRON)
horn('LeftWall','RubyDevilHornLeft',-73,110,121,.9,-1)
horn('LeftWall','RubyDevilHornRight',-73,110,143,.9,1)
emberBadge('LeftWall','RubyFirestarterCrest',-68.3,113,132,2,False)

# Exact outgoing Catacombs seam profile: upstream ExitRelicCrest accents excluded.
previous=json.loads((ROOT/'assets/biome-shells/Catacombs/geometry.json').read_text())
previous_exit=[p for p in previous['Groups']['Exit'] if p['Name'].startswith('CatacombExit_')]
assert len(previous_exit)==75
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];front=z+sz/2-220
    box('Entrance','CatacombsSeam_'+p['Name'],(sx,sy,3),(x,y,front+1.5),p['Color'],p.get('Detail',False))
for p in previous_exit:
    x,y,z=p['Offset'];sx,sy,sz=p['Size'];c=OXIDE if p['Color']==[194,112,12] else BASALT
    box('Exit','InfernoExit_'+p['Name'],(sx,sy,sz),(x,y,z),c,p.get('Detail',False))
for sign in (-1,1):
    for i,w in enumerate((9,8,6,4,2)):
        box('Exit','ExitHornAccent',(w,3,.8),(sign*(16-i*1.6),103.5+i*2.8,208.4),OXIDE,True)

def touching(a,b):
    return all(abs(a['Offset'][i]-b['Offset'][i]) <= (a['Size'][i]+b['Size'][i])/2 for i in range(3))
exit_horns=[p for p in groups['Exit'] if p['Name'].startswith('ExitHornAccent')]
for accent in (exit_horns[0],exit_horns[5]):
    assert any(touching(accent,p) for p in groups['Exit'] if p['Name'].startswith('InfernoExit_')), 'Exit horn must seat into the arch'
for half in (exit_horns[:5],exit_horns[5:]):
    assert all(touching(a,b) for a,b in zip(half,half[1:])), 'Exit horn steps must overlap'

# Horned furnace on far RIGHT wall; every low block stays outside the112studlane.
for y,h,d,w,c in ((3,5,24,42,BLACK),(6.5,2,24,42,OXIDE),(11,7,21,39,ROCK),(16,2,23,41,IRON),
    (42,49,17,35,ROCK),(69,4,21,39,IRON),(85,28,17,35,BASALT),(101,4,22,40,OXIDE),
    (112,18,15,32,ROCK),(123,4,20,39,IRON),(128,5,18,36,OXIDE)):
    box('HornedForge','FurnaceMergedTier',(d,h,w),(68,y,190),c)
for sign in (-1,1):
    face('HornedForge','TwinBasaltForgePier',59,70,190+sign*14,4,101,4,BASALT)
    face('HornedForge','ForgePierOxideEdge',56.7,73,190+sign*14,.5,101,1.2,OXIDE)
    for y in (20,51,101,123):rivets('HornedForge','PierIronClamp',57.5,y,190+sign*14,6)
    horn('HornedForge','GreatSweptDevilHorn',68,130,190+sign*8,2,sign,rise=1.5)
face('HornedForge','FurnaceMouthBlack',57.8,78,190,1,28,22,BLACK)
face('HornedForge','FurnaceMouthOxide',57.1,78,190,.5,21,16,OXIDE)
for sign in (-1,1):
    face('HornedForge','MouthRedJamb',57.4,78,190+sign*10,1.3,27,2,RED)
    face('HornedForge','MouthIronCap',57.4,78+sign*14,190,1.3,3,24,IRON)
for i in range(8):face('HornedForge','EmberMouthRow',56.8,69+i*2.3,190+(i%3-1)*1.3,.7,2.4,8+(i%2)*3,EMBER,True)
face('HornedForge','MoltenSpill',57.2,35.5,190,.8,59,5,LAVA,WaterFace='Left')
face('HornedForge','SpillHotRun',56.65,35.5,190,.25,59,1.7,EMBER,True)
box('HornedForge','LavaBasin',(16,.2,36),(65,5.5,190),LAVA,WaterFace='Top')
for x in (57,73):box('HornedForge','BasinIronSide',(1.2,1.8,38),(x,5,190),IRON)
for z in (171,209):box('HornedForge','BasinIronEnd',(17,1.8,1.2),(65,5,z),IRON)
for z in (182,198):
    for y,w,h,c in ((136,6,8,BASALT),(142,7,2,OXIDE),(152,4,18,BASALT),(162,5,2,OXIDE),(169,3,12,BASALT)):
        box('HornedForge','TwinForgeChimney',(6,h,w),(69,y,z),c)
for z in (173,207):
    for y,h,d,w,c in ((8,12,12,10,ROCK),(16,4,14,12,IRON),(23,10,9,8,OXIDE),(30,4,11,10,BASALT)):
        box('HornedForge','SlagCoolingButtress',(d,h,w),(70,y,z),c)
    for y in (16,30):rivets('HornedForge','CoolingIronClamp',62.3,y,z,9)
for yy in (64,92):rivets('HornedForge','MouthCapRivets',57,yy,190,22)
for y in (101,123):
    for z in (178,186,194,202):rivets('HornedForge','FurnaceLintelPlate',57.3,y,z,5)
for z in (178,186,194,202):
    box('HornedForge','BasinEmberStreak',(11,.02,1.1),(65,5.62,z),EMBER,True)
for y in range(23,119,8):face('HornedForge','ForgeMortarRun',59.2,y,190,.3,.16,30,BLACK,True)

box('Floor','ClearLaneFloor',(112,.015,220),(0,.2075,110),FLOOR,Stud=True)
for side in (-1,1):
    for x,w,c in ((54.5,2.5,OXIDE),(52.5,1.2,IRON),(51.2,1.2,BLACK)):box('Floor','MergedFloorBorder',(w,.008,220),(side*x,.222,110),c)
    for z in (24,66,108,150,192):
        for i in range(7):
            box('Floor','SteppedEmberCrack',(1.5,.005,5.8),(side*(43-(i%3)*2),.230,z+(i-3)*5.5),RED,True)
for z in (24,66,108,150,192):
    for i,w in enumerate((2,4,7,9,7,4,2)):
        box('Floor','AngularEmberSigil',(w*1.5,.005,1.5),(0,.233,z+(i-3)*1.5),OXIDE)
        if w>4:box('Floor','InlaidHotCore',((w-4)*1.5,.004,1.5),(0,.239,z+(i-3)*1.5),RED)
for x in range(-48,49,12):box('Floor','FinePavingLong',(.06,.003,220),(x,.226,110),BLACK,True)
for z in range(10,220,12):box('Floor','FinePavingCross',(98,.003,.06),(0,.226,z),BLACK,True)

parts=[p for rows in groups.values() for p in rows];pivots=len(groups)+1
full=len(parts)+pivots;low=sum(not p.get('Detail') for p in parts)+pivots
assert full<=1500 and low<=800,(full,low)
geo={'Version':1,'Name':'InfernoShell','BiomeIndex':5,'Rarity':'Mythic','Boss':'Ruby','BossTitle':'The Firestarter','BossWear':['DevilHorns'],
    'Origin':[0,0,880],'LocalOrigin':[0,0,0],'FrontAxis':'-Z; +Z goes deeper','PartCount':full,'LowPartCount':low,'FinePartCount':full-low,
    'Bounds':{'MinX':-80,'MaxX':80,'MinZ':0,'MaxZ':220,'WallHeight':120,'FloorTop':.2},
    'ClearLane':{'MinX':-56,'MaxX':56,'OverheadClearance':70},
    'ReservedLair':{'LocalCenter':[-73,0,132],'WorldCenter':[-73,0,1012],'ClearX':[-80,-62],'ClearZ':[105,159],'ClearHeight':32},
    'Seam':{'Previous':'CatacombsShell','PreviousExitWorldZ':880,'EntranceOverlap':3,'ExactXYProfile':True,'ExitCenter':214,
        'PreviousExitPrefix':'CatacombExit_','ExitProfilePrefix':'InfernoExit_','ExitAccentPrefix':'ExitHornAccent',
        'PreviousExitSha256':hashlib.sha256(json.dumps(previous_exit,sort_keys=True).encode()).hexdigest()},
    'OmittedForLair':omitted,'Groups':groups,
    'CameraViews':{'entrance':{'Position':[0,20,-28],'Target':[10,48,174],'Fov':68},
        'mid':{'Position':[20,23,75],'Target':[-73,69,132],'Fov':70},
        'landmark':{'Position':[-38,44,128],'Target':[67,86,190],'Fov':72},
        'top':{'Position':[0,390,110],'Target':[0,0,110],'Ortho':250},
        'left-wall':{'Position':[170,75,110],'Target':[-80,75,110],'Ortho':246},
        'right-wall':{'Position':[-170,90,110],'Target':[80,90,110],'Ortho':246}}}
(OUT/'geometry.json').write_text(json.dumps(geo,indent=2)+'\n')
def lua(v):
    if isinstance(v,dict):return '{'+','.join(k+'='+lua(x) for k,x in v.items())+'}'
    if isinstance(v,list):return '{'+','.join(lua(x) for x in v)+'}'
    if isinstance(v,bool):return 'true' if v else 'false'
    return json.dumps(v)
folder=ROOT/'src/shared/Config/ToyGeometry/InfernoShell';folder.mkdir(parents=True,exist_ok=True)
block_type='type Block={Name:string, Size:{number}, Offset:{number}, Color:{number}, Detail:boolean?, WaterFace:string?, Ambient:boolean?, Hidden:boolean?, Stud:boolean?}\n'
for n,rows in groups.items():
    s='--!strict\n-- Native blocks; regenerate tools/build_inferno_shell.py.\n'+block_type+'-- stylua: ignore\nlocal blocks: {Block} = {\n'
    s+='\n'.join('\t'+lua(p)+',' for p in rows)+'\n}\nreturn blocks\n';(folder/f'{n}.luau').write_text(s)
s='--!strict\n-- Zone 5 entrance is world (0,0,880); block offsets are local.\nreturn {\n'
for n in ('Version','Name','BiomeIndex','Rarity','Boss','BossTitle','BossWear','Origin','LocalOrigin','FrontAxis','PartCount','LowPartCount','Bounds','ClearLane','ReservedLair','Seam'):s+=n+'='+lua(geo[n])+',\n'
s+='Groups={'+','.join(n+'=require(script.Parent.InfernoShell.'+n+')' for n in groups)+'}\n}\n'
(ROOT/'src/shared/Config/ToyGeometry/InfernoShellData.luau').write_text(s)
print(json.dumps({'Full':full,'Low':low,'Fine':full-low,'Groups':{n:len(v) for n,v in groups.items()}}))
