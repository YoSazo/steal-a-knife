"""Generate zones 2-8 native block art using the approved hedge-hound pose contract.
No service/config integration edits. Per-creature build_<name>.py wrappers regenerate one model.
"""
from pathlib import Path
import json,math,sys,subprocess
R=Path(__file__).resolve().parents[1]
COL={'leaf':(77,152,35),'lime':(134,194,42),'moss':(32,75,27),'cream':(238,225,189),'bone':(217,207,178),'white':(242,238,225),'dark':(25,27,35),'stone':(51,51,65),'pink':(225,63,128),'pinktop':(247,112,165),'gold':(191,145,45),'sand':(178,145,91),'brown':(105,78,47),'red':(109,35,28),'redtop':(161,52,32),'orange':(187,93,24),'blue':(83,149,184),'cyan':(57,153,177),'purple':(90,63,146),'violet':(42,26,87),'indigo':(26,19,52),'shine':(255,247,224)}
INFO=[('FlowerToad',2,14,'Ivy','The Gardener'),('BoneWolf',3,15.5,'Sam','The Gravedigger'),('GoldScorpion',4,17,'Leo','The Collector'),('LavaSalamander',5,18.5,'Ruby','The Firestarter'),('GoldenGriffin',6,20,'Kate','The Queen'),('SkyPegasus',7,21.5,'Zoe','The Angel'),('VoidBeast',8,23,'Nick','The Void Walker')]
class Creature:
 def __init__(self,name,zone,height,boss,title):
  self.name,self.zone,self.height,self.boss,self.title=name,zone,height,boss,title;self.parts=[];self.joints={};self.notes=[]
 def joint(self,n,awake,sleep,rotate=None):self.joints[n]=dict(Awake=awake,Asleep=sleep,AsleepRotation=rotate or [0,0,0])
 def b(self,n,g,size,pos,c,role=None,state='Both',angle=0,neon=False):
  self.parts.append(dict(Name=n,Group=g,Role=role or g,Size=list(size),Offset=list(pos),Color=COL[c] if isinstance(c,str) else c,State=state,Angle=angle,Neon=neon))
 def eyes(self,x,y,z,w,h,c,extras=False):
  for side in [-1,1]:
   role='EyeLeft' if side<0 else 'EyeRight';suf=f'_{x}_{y}_{side}'
   self.b(role+'Socket'+suf,'Head',(w+.6,h+.6,.3),(side*x,y,z),'dark',state='Awake')
   self.b(role+'Glow'+suf,'Head',(w,h,.2),(side*x,y,z-.25),c,role,state='Awake',neon=True)
   self.b(role+'Shine'+suf,'Head',(w*.22,h*.28,.12),(side*x-w*.2,y+h*.2,z-.42),'shine',role,state='Awake',neon=True)
   self.b(role+'Lid'+suf,'Head',(w+.3,.25,.2),(side*x,y,z-.25),'dark',role,state='Asleep',angle=side*5)
   if not extras:self.b('Brow'+suf,'Head',(w+.85,.55,.7),(side*x,y+h*.55+.4,z-.1),'dark',angle=side*13)
 def legs(self,hip=5.5,x=3.5,zf=-3,zb=4,body='leaf',toe='moss',wide=2.6):
  for group,s,z in [('LegFrontLeft',-1,zf),('LegFrontRight',1,zf),('LegBackLeft',-1,zb),('LegBackRight',1,zb)]:
   self.joint(group,[s*x,hip,z],[s*x,hip*.25,z])
   self.b(group+'_Upper',group,(wide,hip*.58,wide),(0,-hip*.22,0),body)
   self.b(group+'_Lower',group,(wide*.8,hip*.47,wide*.8),(0,-hip*.67,0),body)
   self.b(group+'_Paw',group,(wide*1.22,1.1,wide*1.3),(0,-hip+.55,-.35),body)
   for j in range(3):self.b(group+f'_Toe{j}',group,(wide*.31,.9,.65),((j-1)*wide*.38,-hip+.45,-wide*.8),toe)
 def quadruped(self,body='leaf',head='leaf',hip=5.5,headheight=8,width=8,depth=9):
  self.joint('Body',[0,hip+1.7,0],[0,2.8,0]);self.joint('Head',[0,headheight,-4],[0,3,-5]);self.joint('Tail',[0,hip+2,depth*.55],[0,3,depth*.55])
  self.b('Torso','Body',(width,4.8,depth),(0,0,1),body)
  self.b('BackCrown','Body',(width*.8,.9,depth*.9),(0,2.65,1),head)
  self.b('Chest','Body',(width*.65,3,2),(0,-.3,-depth*.48),head)
  self.b('HeadCore','Head',(width*.83,4.6,4.5),(0,1,-.2),head)
  self.b('Forehead','Head',(width*.7,.8,3.8),(0,3.7,-.2),head)
  self.legs(hip=hip,x=width*.42,body=body,toe=head)
 def export(self):
  # Scale all authored offsets/joints/sizes together; Root remains Roblox's minimum .05.
  maxy=max(self.joints[p['Group']]['Awake'][1]+p['Offset'][1]+(abs(math.sin(math.radians(p['Angle'])))*p['Size'][0]+abs(math.cos(math.radians(p['Angle'])))*p['Size'][1])/2 for p in self.parts)
  factor=(self.height-.025)/maxy
  for p in self.parts:
   for key in ['Size','Offset']:p[key]=[round(v*factor,6) for v in p[key]]
  for j in self.joints.values():
   for key in ['Awake','Asleep']:j[key]=[round(v*factor,6)for v in j[key]]
  out=R/'assets/creature-bosses'/self.name;out.mkdir(parents=True,exist_ok=True)
  def v(a):return 'Vector3.new('+','.join(map(str,a))+')'
  def cf(a,rot=None):return 'CFrame.new('+','.join(map(str,a))+')'+(' * CFrame.Angles('+','.join('math.rad('+str(x)+')'for x in rot)+')'if rot and any(rot) else '')
  lines=['--!strict','-- Generated native creature art; front -Z, floor-centre Root.','return {',f' StandHeight = {self.height},',f' WalkPivot = {v([0,5.5*factor,0])},',' Joints = {']
  for n,j in self.joints.items():lines.append(f' {n} = {{ Awake = {cf(j["Awake"])}, Asleep = {cf(j["Asleep"],j["AsleepRotation"])} }},')
  lines+=[' },',' Blocks = {']
  for p in self.parts:
   lines.append(' { '+', '.join(f'{k} = {json.dumps(p[k])}'for k in ['Name','Group','Role','State'])+f', Size = {v(p["Size"])}, Offset = {v(p["Offset"])}, Color = Color3.fromRGB({",".join(map(str,p["Color"]))}), Angle = {p["Angle"]}, Neon = {str(p["Neon"]).lower()} '+'},')
  lines+=[' },','}'];(R/f'src/shared/Config/ToyGeometry/{self.name}.luau').write_text('\n'.join(lines)+'\n')
  template=(R/'src/shared/Assets/HedgeHound.luau').read_text().replace('ToyGeometry.HedgeHound','ToyGeometry.'+self.name).replace('CourtyardHedgeHound',self.name).replace('Unknown hedge hound pose','Unknown creature pose').replace('"Zone", 1','"Zone", '+str(self.zone)).replace('Vector3.new(0, 5.5, 0)','Data.WalkPivot')
  (R/f'src/shared/Assets/{self.name}.luau').write_text(template)
  # Two passes settle StyLua's line wrapping on generated joint tables.
  for _ in range(2):subprocess.run(['stylua',str(R/f'src/shared/Assets/{self.name}.luau'),str(R/f'src/shared/Config/ToyGeometry/{self.name}.luau')],check=True)
  meta=dict(Name=self.name,Zone=self.zone,Boss=self.boss,Title=self.title,StandHeight=self.height,PartCount=len(self.parts)+1,FrontAxis='-Z',Root='floor centre under torso',Joints=self.joints,Blocks=self.parts,AnimationNotes=self.notes)
  (out/'geometry.json').write_text(json.dumps(meta,indent=2))
  return meta
def build(info):
 c=Creature(*info);n=c.name
 if n=='FlowerToad':
  c.quadruped('leaf','lime',hip=4.5,headheight=7,width=10,depth=10)
  c.b('Belly','Body',(8,2.1,7),(0,-1.6,0),'cream')
  c.b('Muzzle','Head',(10,2.1,2.3),(0,-.5,-3.1),'lime');c.b('Smile','Head',(8,.28,.2),(0,-1.2,-4.4),'moss','Mouth')
  for side in [-1,1]:
   c.b(f'EyeBump{side}','Head',(3.4,3.5,2.5),(side*3,3,-1.6),'lime')
   for j in range(4):c.b(f'ToadSpot{side}_{j}','Body',(.5,1,1.3),(side*5.2,.4+(j%2)*1.2,-2+j*2),'cyan')
  c.eyes(3,3.2,-3,2,2.25,'cyan')
  for side in [-1,1]:
   role='EyeLeft' if side<0 else 'EyeRight'
   c.b(f'ToadPupil{side}','Head',(1,1.4,.16),(side*3,3.2,-3.42),'dark',role,state='Awake')
   c.b(f'ToadPupilShine{side}','Head',(.48,.5,.12),(side*3-.25,3.7,-3.58),'shine',role,state='Awake',neon=True)
   group='LegBackLeft' if side<0 else 'LegBackRight'
   c.b(f'ToadHaunch{side}',group,(4.1,3.1,4.1),(side*.6,.1,.5),'leaf')
   c.b(f'ToadHaunchTop{side}',group,(3.4,.8,3.5),(side*.6,1.9,.5),'lime')
  for group in ['LegFrontLeft','LegFrontRight','LegBackLeft','LegBackRight']:
   c.b(group+'_WebbedFoot',group,(4.1,1.1,4.7),(0,-3.95,-.8),'lime')
  c.joint('Bloom',[0,10,2],[0,6.2,2]);c.notes=['Bloom can sway a few degrees; no Tail group. Four legs use the normal trot.']
  for i in range(8):
   a=i*math.pi/4;x,z=math.cos(a),math.sin(a)
   for k in range(3):c.b(f'Petal{i}_{k}','Bloom',(2.7,.7+k*.3,2.7),(x*(2.2+k),.4+k*.8,z*(2.2+k)),'pinktop' if k==2 else 'pink')
  c.b('FlowerCentre','Bloom',(3,1.5,3),(0,1,0),'gold')
  # Toads have no tails: remove the unused pivot.
  del c.joints['Tail']
 elif n=='BoneWolf':
  c.quadruped('stone','bone',hip=6,headheight=9,width=7,depth=10)
  c.b('Snout','Head',(3,1.8,4),(0,.2,-3.8),'cream');c.b('Nose','Head',(1.8,.9,.4),(0,.55,-5.9),'dark')
  c.b('Jaw','Head',(3.3,.7,3.8),(0,-1.25,-3.7),'bone');c.b('Mouth','Head',(3,.65,.2),(0,-.7,-5.75),'dark','Mouth',state='Awake')
  for side in [-1,1]:
   for j in range(3):c.b(f'Ear{side}_{j}','Head',(1.8-j*.45,1.1,1.3),(side*2.4,3.6+j*.9,.2),'cream')
   for j in range(5):
    c.b(f'RibSide{side}_{j}','Body',(.55,3.7, .8),(side*3.65,.1,-2.9+j*1.8),'cream')
    c.b(f'RibTop{side}_{j}','Body',(3.4,.45,.8),(side*1.8,2.8,-2.9+j*1.8),'bone')
   for j in range(3):c.b(f'Tooth{side}_{j}','Head',(.45,.5,.35),(side*1.1,-.65,-3.8-j*.8),'cream','Mouth',state='Awake')
  c.eyes(1.7,2,-2.7,1.15,1.2,'purple')
  for group in ['LegFrontLeft','LegFrontRight','LegBackLeft','LegBackRight']:
   c.b(group+'_BoneShin',group,(1.5,2.3,.45),(0,-3.4,-1.12),'cream')
   c.b(group+'_KneeBone',group,(2.2,1.1,.55),(0,-1.35,-1.38),'bone')
  for j in range(5):c.b(f'Vertebra{j}','Tail',(1.35,1.1,1.2),(0,.3+j*.35,j),'bone')
 elif n=='GoldScorpion':
  c.joint('Body',[0,3.5,0],[0,1.8,0]);c.joint('Head',[0,3.5,-5],[0,1.8,-5]);c.joint('Tail',[0,3.6,5],[0,2.4,5],[-58,0,0])
  c.b('Torso','Body',(7,3.4,10),(0,0,0),'brown')
  for j in range(6):c.b(f'ArmourSegment{j}','Body',(7.5-(j%2)*.5,1.5,1.5),(0,1.6,-4.2+j*1.65),'sand')
  c.b('HeadCore','Head',(6.6,3,3.5),(0,.4,-.6),'sand');c.eyes(1.8,.7,-2.55,1.1,.8,'gold')
  for group,side,z in [('LegFrontLeft',-1,-2),('LegFrontRight',1,-2),('LegBackLeft',-1,3),('LegBackRight',1,3)]:
   c.joint(group,[side*3,3.5,z],[side*3,.875,z])
   for k in range(2):
    c.b(group+f'_Reach{k}',group,(3.6,.9,1),(side*1.7,-.3,k*1.9),'sand')
    c.b(group+f'_Shin{k}',group,(1.1,2.7,1.1),(side*3,-1.9,k*1.9),'sand')
    c.b(group+f'_Foot{k}',group,(1.4,.55,1.5),(side*3,-3.225,k*1.9),'brown')
    c.b(group+f'_Band{k}',group,(1.4,.4,1.4),(side*3,-1.5,k*1.9),'gold')
  for side in [-1,1]:
   group='ClawLeft' if side<0 else 'ClawRight';c.joint(group,[side*3.3,3,-4],[side*3.3,1.6,-4])
   c.b(group+'_Arm',group,(1.4,1.2,3.7),(side,0,-1.6),'brown')
   c.b(group+'_Palm',group,(3.1,1.8,2.6),(side*1.3,.2,-4.1),'gold')
   for k in [-1,1]:
    c.b(group+f'_Finger{k}',group,(.9,1.5,2.8),(side*1.3+k*1.15,.2,-6.2),'sand')
    c.b(group+f'_Tip{k}',group,(1.1,1.3,1),(side*1.3+k*.8,.2,-7.8),'gold')
  for j,(y,z) in enumerate([(0,0),(2,1),(4,2),(6,2.8),(8,2.7),(10,1.7),(11,0),(10.7,-1.8)]):
   c.b(f'TailSegment{j}','Tail',(2.2,2.2,2.2),(0,y,z),'sand')
   c.b(f'TailBand{j}','Tail',(2.35,.4,2.35),(0,y+.8,z),'gold')
  c.b('BluntStinger','Tail',(1.7,2.5,1.7),(0,9.2,-2.7),'gold')
  c.notes=['Eight visible legs paired into four named trot groups. ClawLeft/ClawRight may open or bob. Tail folds backward in sleep; wag conservatively (large tail).']
 elif n=='LavaSalamander':
  c.quadruped('red','redtop',hip=4.8,headheight=7,width=9,depth=12)
  c.b('Muzzle','Head',(6.5,2.2,3),(0,-.1,-3.3),'redtop');c.b('Jaw','Head',(6.1,.7,3),(0,-1.8,-3.3),'red')
  c.b('Mouth','Head',(5.6,.6,.2),(0,-1.2,-4.9),'dark','Mouth',state='Awake')
  c.eyes(2.4,2,-2.7,1.3,1.1,'orange')
  for side in [-1,1]:
   for j in range(3):c.b(f'Teeth{side}_{j}','Head',(.6,.6,.3),(side*(1+j*.7),-1,-4.95),'cream','Mouth',state='Awake')
   c.b(f'HornNub{side}','Head',(1,1.2,1),(side*2.7,3.9,0),'red')
   for j in range(5):
    c.b(f'LavaCrack{side}_{j}','Body',(.25,3, .45),(side*4.6,0,-4+j*2.3),'orange',neon=True)
    c.b(f'RockPlate{side}_{j}','Body',(.7,2.2,1.6),(side*4.65,.9,-3.6+j*2.3),'redtop')
  for j in range(6):
   c.b(f'DorsalSpine{j}','Body',(1.8,1.6+(j%2)*.6,1.4),(0,3.4,-4+j*2),'orange')
  for j in range(8):
   c.b(f'TailChunk{j}','Tail',(3.2-j*.28,2-j*.13,1.7),(0,.3+math.sin(j*.4)*.7,1+j*1.5),'redtop')
   c.b(f'TailSeam{j}','Tail',(3.3-j*.28,.35,.5),(0,1+math.sin(j*.4)*.7,1+j*1.5),'orange',neon=True)
 elif n in ['GoldenGriffin','SkyPegasus']:
  horse=n=='SkyPegasus';c.quadruped('white','white',hip=7,headheight=11,width=7.6,depth=10.5)
  c.b('Neck','Body',(4.5,5.5,3),(0,3,-3.8),'white')
  c.b('Muzzle' if horse else 'Beak','Head',(3.3,2.7,4),(0,.1,-3.6),'white' if horse else 'gold')
  c.b('MuzzleTip','Head',(2.8,1.6,1.6),(0,-.8,-5.9),'white' if horse else 'gold')
  if not horse:c.b('BeakHook','Head',(1.4,1.8,1.25),(0,-1.75,-6.6),'gold')
  c.b('Mouth','Head',(2.6,.23,.2),(0,-1.1,-6.75),'dark','Mouth')
  c.eyes(2.1,2.1,-2.7,1.25,1.15,'cyan' if horse else 'gold')
  for side in [-1,1]:
   c.b(f'Ear{side}','Head',(1,2.7,1.3),(side*2.2,4.3,.1),'white' if horse else 'gold')
   c.b(f'Nostril{side}','Head',(.5,.6,.2),(side*.8,-.35,-6.77),'stone')
  for group in ['LegFrontLeft','LegFrontRight','LegBackLeft','LegBackRight']:
   c.b(group+'_GoldHoof',group,(3.25,1.25,3.25),(0,-6.375,-.35),'gold')
  c.joint('WingLeft',[-3.8,9,1],[-3.8,5.3,1],[0,65,20]);c.joint('WingRight',[3.8,9,1],[3.8,5.3,1],[0,-65,-20])
  for side in [-1,1]:
   group='WingLeft' if side<0 else 'WingRight'
   c.b(group+'_Shoulder',group,(2.7,3.2,3),(side*1,1,0),'blue' if horse else 'gold')
   for k in range(6):
    c.b(group+f'_Fan{k}',group,(7.4-k*.55,1.5,1.2),(side*(3.6+k*.25),.7+k*1.25,.4),'white')
   for j in range(7):
    c.b(group+f'_Feather{j}',group,(5.5,1.45,1.35),(side*(3.8+j*.65),.6+j*1.05,-.3-j*.12),'white' if horse else ('white' if j%2 else 'gold'),angle=side*26)
    c.b(group+f'_Tip{j}',group,(1.4,1.15,1.4),(side*(6.8+j*.65),2+j*1.05,1.8-j*.45),'blue' if horse else 'gold',angle=side*26)
  if horse:
   for j in range(7):c.b(f'Mane{j}','Head',(1.7,1.2,1.6),(0,3.7-j*.7,1.9+j*.25),'blue')
   c.joint('Halo',[0,18,-4],[0,9,-5])
   for k,(size,pos) in enumerate([((4,.5,.5),(0,0,-1.75)),((4,.5,.5),(0,0,1.75)),((.5,.5,3),(1.75,0,0)),((.5,.5,3),(-1.75,0,0))]):c.b(f'Halo{k}','Halo',size,pos,'gold')
   for j in range(7):c.b(f'TailMane{j}','Tail',(2.2-j*.15,1.7,1.6),(0,-.3+j*.15,1+j*.8),'blue')
  else:
   for j in range(5):c.b(f'GoldenCrest{j}','Head',(1.8,1.9-j*.18,1),(0,4.1,-.8+j*.8),'gold')
   for side in [-1,1]:
    for j in range(4):c.b(f'NeckFeather{side}_{j}','Body',(2,.7, .5),(side*1.3,4-j,-5.4),'gold',angle=side*10)
   for j in range(5):c.b(f'Tail{j}','Tail',(1.2,1.1,1.2),(0,j*.25,j),'white')
   c.b('TailTuft','Tail',(2.2,1.9,2),(0,1.6,4.5),'gold')
  c.notes=['WingLeft/WingRight have folded sleep pivots; flap around local Z. Ground trot remains four legs. '+('Halo is a separate group and may bob with Head.'if horse else 'Keep golden crest and beak moving with Head.')]
 elif n=='VoidBeast':
  c.quadruped('violet','purple',hip=6.5,headheight=9.5,width=10,depth=11)
  c.b('Muzzle','Head',(5.5,2.3,2.5),(0,-.4,-3.8),'violet');c.b('Nose','Head',(2,.7,.4),(0,.2,-5.2),'indigo')
  c.b('Mouth','Head',(3.6,.7,.2),(0,-1.4,-5.18),'dark','Mouth',state='Awake')
  c.eyes(2.6,1.65,-2.9,1.7,1.5,'purple');c.eyes(2.7,3.3,-2.9,.65,.55,'cyan',True);c.eyes(1.2,3.3,-2.9,.65,.55,'cyan',True)
  for side in [-1,1]:
   for j in range(3):c.b(f'Horn{side}_{j}','Head',(1.3-j*.2,1.4,1.3),(side*(3.9+j*.4),4+j*1.2,.3),'purple')
   c.b(f'HornGlow{side}','Head',(.4,2.1,.6),(side*4.2,5.3,-.5),'cyan',neon=True)
   for j in range(3):
    x,y,z=side*5.1,1.3,-2+j*3.5
    c.b(f'StarV{side}_{j}','Body',(.3,1.4,.4),(x,y,z),'cyan',neon=True);c.b(f'StarH{side}_{j}','Body',(.3,.4,1.4),(x,y,z),'cyan',neon=True)
  c.b('CrownSpike','Head',(1.5,3.8,1.6),(0,5.9,.2),'purple')
  for j in range(4):c.b(f'Tail{j}','Tail',(2.6-j*.35,2,1.6),(0,.3+j*.35,j*1.2),'violet')
  for group in ['LegFrontLeft','LegFrontRight','LegBackLeft','LegBackRight']:
   c.b(group+'_BigPaw',group,(4.3,1.3,3.8),(0,-5.85,-.55),'violet')
   for j in range(3):c.b(group+f'_CrystalClaw{j}',group,(.8,1.1,.7),((j-1)*1.4,-5.9,-2.6),'purple')
  c.notes=['Six eyes use EyeLeft/EyeRight roles; all close together. Tail wag only; crown stays with Head.']
 return c.export()
def main(only=None):
 results=[build(i)for i in INFO if only is None or i[0]==only]
 assert results,'Unknown creature'
 print(json.dumps([{k:d[k]for k in ['Name','Zone','StandHeight','PartCount']}for d in results]))
if __name__=='__main__':main(sys.argv[1]if len(sys.argv)>1 else None)
