"""Self-contained coffin family generator; preserves approved Common/Cosmic files."""
import copy,json,math,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
GEOM=ROOT/'src/shared/Config/ToyGeometry';OUT=ROOT/'assets/coffins';OUT.mkdir(exist_ok=True)
INK=[20,21,28];WHITE=[252,249,232];GOLD=[255,208,60];PINK=[229,80,140];NAVY=[17,26,46]
rows=[];models={};metadata={}
RARITIES=['Common','Rare','Epic','Legendary','Mythic','Godly','Celestial','Cosmic']
def b(name,size,pos,color,role=None,angle=0,hidden=False,**kw):
 row=dict(Name=name,Size=size,Offset=pos,Color=color,Role=role or 'Decoration')
 if angle:row['Angle']=angle
 if hidden:row['Hidden']=True
 row.update(kw);rows.append(row);return row

def bounds(parts):
 lo=[math.inf]*3;hi=[-math.inf]*3
 for p in parts:
  sx,sy,sz=p['Size'];a=math.radians(p.get('Angle',0));ex=abs(sx*math.cos(a))+abs(sy*math.sin(a));ey=abs(sx*math.sin(a))+abs(sy*math.cos(a))
  for j,v in enumerate((ex,ey,sz)):lo[j]=min(lo[j],p['Offset'][j]-v/2);hi[j]=max(hi[j],p['Offset'][j]+v/2)
 return lo,hi

def pixels(label,pattern,x,y,z,unit,color,role,plane='XY',hidden=False,**kw):
 # Merge horizontal pixel runs; shared boundaries of one expression cannot flicker.
 for j,line in enumerate(pattern):
  a=0
  while a<len(line):
   if line[a]!='#':a+=1;continue
   end=a+1
   while end<len(line) and line[end]=='#':end+=1
   px=x+((a+end)/2-len(line)/2)*unit;py=y+(len(pattern)/2-j-.5)*unit
   if plane=='XY':b(label+f'_{j}_{a}',[(end-a)*unit,unit,unit*.42],[px,py,z],color,role,hidden=hidden,**kw)
   else:b(label+f'_{j}_{a}',[(end-a)*unit,unit*.42,unit],[px,y,z+(len(pattern)/2-j-.5)*unit],color,role,hidden=hidden,**kw)
   a=end

def coffin(rarity,rank):
 rows.clear();length=[3,4,5.2,6.6,8.2,10,12,14][rank]
 width=length*.42;height=length*.22;th=length*.035
 color=[[99,66,38],[41,103,157],[89,49,136],[172,117,28],[104,36,38],[139,54,101],[98,163,186],[35,19,79]][rank]
 trim=[[47,49,56],[38,57,78],[55,33,85],[212,166,54],[201,67,27],[234,181,61],[217,230,220],[34,206,233]][rank]
 planks=[[143,88,43],[69,139,190],[145,77,187],[231,182,61],[183,62,30],[216,92,143],[154,215,230],[94,42,177]][rank]
 # Hollow box: separate bottom and four stepped wall sections, never a solid slab inside.
 segments=[(-.50,-.34,.72),(-.34,-.18,1.0),(-.18,.22,.90),(.22,.50,.62)]
 lid_y=height+th*2.4
 for i,(a,c,w) in enumerate(segments):
  z=(a+c)*length/2;d=(c-a)*length;sw=width*w
  b(f'BodyBottom_{i}',[sw,th,d],[0,th/2,z],color,'Body')
  for side in (-1,1):
   b(f'BodySide_{i}_{side}',[th,height-th,d],[side*(sw/2-th/2),height/2+th/2,z],color,'Body')
   for j in range(3):
    b(f'SidePlank_{i}_{side}_{j}',[th*.30,height*.23,d*.88],[side*(sw/2+th*.24),height*(.23+j*.25),z],planks,'Body')
   b(f'BaseRail_{i}_{side}',[th*1.4,th,d],[side*(sw/2-th/2),th*.65,z],trim,'Body')
   b(f'GlowSeam_{i}_{side}',[th*.45,th*.38,d],[side*(sw/2+th*.10),height+th*.50,z],trim,'Glow',Neon=rank>=4)
  b(f'LidPlate_{i}',[sw+th*.75,th*1.4,d],[0,lid_y,z],trim,'Lid')
  b(f'LidInlay_{i}',[sw-th*2,th*.36,d*.98],[0,lid_y+th*.91,z],planks,'Lid')
  for side in (-1,1):
   b(f'LidRim_{i}_{side}',[th*.65,th*.55,d],[side*(sw/2-th*.15),lid_y+th*1.12,z],trim,'Lid',Neon=rank>=4,Pulse=True)
 for i in range(len(segments)-1):
  za=segments[i][1]*length;wa=segments[i][2]*width;wb=segments[i+1][2]*width
  for side in (-1,1):
   x=side*(wa+wb)/4;sw=abs(wa-wb)/2+th
   b(f'ShoulderJoint_{i}_{side}',[sw,height-th,th],[x,height/2+th/2,za],color,'Body')
   b(f'LidShoulderJoint_{i}_{side}',[sw,th*.55,th*.70],[x,lid_y+th*1.12,za],trim,'Lid',Neon=rank>=4)
 for end,w in ((-.5,.72),(.5,.62)):
  b(f'EndWall_{end}',[width*w,height-th,th],[0,height/2+th/2,end*(length-th)],color,'Body')
 b('PeekCrack',[width*.55,th*.68,th*.35],[0,height+th*.78,-length/2-th*.16],INK,'Crack')
 for i,(x,y,sw,sh) in enumerate(((-width*.12,height*.46,th*.7,th*1.4),(width*.12,height*.46,th*.7,th*1.4),(0,height*.36,width*.31,th*.65))):
  b(f'FrontHandle_{i}',[sw,sh,th*.75],[x,y,-length/2-th*.85],trim,'Body')
 for side in (-1,1):
  for y in (height*.20,height*.80):b(f'FrontRivet_{side}_{y}',[th*.65,th*.65,th*.40],[side*width*.26,y,-length/2-th*.65],GOLD,'Body')
 for side in (-1,1):
  b(f'Peek_{side}',[width*.065,th*.38,th*.30],[side*width*.12,height+th*.79,-length/2-th*.40],GOLD,'Peek',hidden=True,Neon=True)
  for z in (-length*.25,length*.10):
   x=side*width*.50
   for k,(dy,dz,sy,sz) in enumerate(((0,-th*1.1,th*1.4,th*.7),(0,th*1.1,th*1.4,th*.7),(-th*.65,0,th*.6,th*2.9))):
    b(f'Handle_{side}_{z}_{k}',[th*.9,sy,sz],[x+side*th,height*.48+dy,z+dz],trim,'Body')
   b(f'Rivet_{side}_{z}',[th*.4,th*.60,th*.60],[x+side*th*.58,height*.76,z],GOLD,'Body')
 for side in (-1,1):
  for z in (-length*.39,length*.37):b(f'LidStud_{side}_{z}',[th*.9,th*.45,th*.9],[side*width*.23,lid_y+th*1.40,z],GOLD,'Lid')
 skull=['..#####..','.#######.','#########','##..#..##','##..#..##','.#######.','..#.#.#..','..#####..']
 star=['....#....','....#....','#..###..#','.#######.','..#####..','.#######.','###...###','.#.....#.']
 pixels('LidEmblem',skull if rank<3 else star,0,lid_y+th*1.75,-length*.15,length*.040,WHITE if rank<3 else GOLD,'Lid',plane='XZ')
 if rank==7:
  for i,(x,z) in enumerate(((-width*.24,-length*.38),(width*.24,-length*.38),(-width*.18,length*.37),(width*.18,length*.37))):
   pixels(f'CornerStar_{i}',['..#..','..#..','#####','..#..','..#..'],x,lid_y+th*1.7,z,th*.38,GOLD,'Lid',plane='XZ')
 name='Coffin_'+rarity;models[name]=copy.deepcopy(rows)
 lo,hi=bounds(rows);metadata[name]=dict(Rarity=rarity,Length=length,PartCount=len(rows)+1,Origin=[0,0,0],FrontAxis=[0,0,-1],BoundsSize=[hi[i]-lo[i] for i in range(3)],LidHinge=[0,lid_y,length/2],OpenAngle=105,CrackFrame=[0,height+th*.79,-length/2-th*.45])

def write(name,parts,folder):
 fields='Name:string,Size:Vector3,Offset:Vector3,Color:Color3,Role:string,Angle:number?,Hidden:boolean?,Neon:boolean?,Gloss:boolean?,Pulse:boolean?,Shape:string?'
 lines=['--!strict','-- Staged art only; regenerate tools/build_knife_characters.py. Floor pivot, front -Z.',f'export type Block = {{{fields}}}','local blocks:{Block}={']
 for p in parts:
  entries=[]
  for key,value in p.items():
   if key in ('Size','Offset'):v='Vector3.new('+','.join(str(round(x,6)) for x in value)+')'
   elif key=='Color':v='Color3.fromRGB('+','.join(map(str,value))+')'
   else:v=json.dumps(value)
   entries.append(key+'='+v)
  lines.append('{'+','.join(entries)+'},')
 lines+=['}','return blocks'];(folder/(name+'.luau')).write_text('\n'.join(lines)+'\n')
for rank,rarity in enumerate(RARITIES):
 coffin(rarity,rank)
 name='Coffin_'+rarity
 if rarity not in ('Common','Cosmic'):write(name,models[name],GEOM)
subprocess.run(['stylua',*[str(GEOM/('Coffin_'+r+'.luau')) for r in RARITIES if r not in ('Common','Cosmic')]],check=True)
(OUT/'geometry.json').write_text(json.dumps(dict(Models=models,Metadata=metadata),indent=2)+'\n')
print(json.dumps(metadata,indent=2))
