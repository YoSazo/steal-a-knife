"""Temporary Client-only native art gallery + pose/geometry contract checks."""
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]
name=sys.argv[1]
meta=json.loads((R/f'assets/creature-bosses/{name}/geometry.json').read_text())
code=["local rs=game.ReplicatedStorage;local old=rs:FindFirstChild('CreatureArtReviewShared');if old then old:Destroy()end;local shared=Instance.new('Folder');shared.Name='CreatureArtReviewShared';shared.Parent=rs;local function folder(n,p)local f=Instance.new('Folder');f.Name=n;f.Parent=p;return f end;local config=folder('Config',shared);local geom=folder('ToyGeometry',config);local assets=folder('Assets',shared)"]
for rel,parent in [(f'Config/ToyGeometry/{name}.luau','geom'),(f'Assets/{name}.luau','assets')]:
 code.append('do local m=Instance.new("ModuleScript");m.Name='+json.dumps(name)+';m.Source=[====['+(R/'src/shared'/rel).read_text()+']====];m.Parent='+parent+' end')
code.append(f'local A=require(assets.{name});local D=require(geom.{name});local m=A.Build(nil,CFrame.new(6000,10,100),"Awake");local count=0;local rest={{}};local roles={{}};local minY=math.huge;for _,p in m:GetDescendants()do if p:IsA("BasePart")then count+=1;rest[p]=p.CFrame;roles[p:GetAttribute("Role")]=true;assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery);if p.Name~="Root" and p.Transparency==0 then minY=math.min(minY,p.Position.Y-p.Size.Y/2)end end end;assert(count=={meta["PartCount"]});assert(math.abs(m:GetExtentsSize().Y-D.StandHeight)<.04,`height {{m:GetExtentsSize().Y}} / {{D.StandHeight}}`);assert(m.HeadCore:GetAttribute("JointGroup")=="Head");assert(roles.EyeLeft and roles.EyeRight);assert(math.abs(minY-10)<.04,`feet {{minY}}`);A.SetPose(m,"Asleep");for _,p in m:GetDescendants()do if p:IsA("BasePart") and (p:GetAttribute("Role")=="EyeLeft" or p:GetAttribute("Role")=="EyeRight")then assert(p:GetAttribute("Closed"))end end;A.SetPose(m,"Waking",.35);A.SetPose(m,"Awake");for p,cf in rest do assert((p.CFrame.Position-cf.Position).Magnitude<.001)end;local body=m.Torso.CFrame;A.SetRunPhase(m,math.pi/2);assert(m.Torso.CFrame==body and m.LegFrontLeft_Paw==nil or m.Torso.CFrame==body);A.SetPose(m,"Awake");m:ScaleTo(1.5);A.SetPose(m,"Asleep");A.SetPose(m,"Awake");assert(math.abs(m:GetExtentsSize().Y-D.StandHeight*1.5)<.07);m:Destroy()')
code.append('''local pg=game.Players.LocalPlayer.PlayerGui;local old=pg:FindFirstChild('CreatureArtGallery');if old then old:Destroy()end
local gui=Instance.new('ScreenGui');gui.Name='CreatureArtGallery';gui.IgnoreGuiInset=true;gui.DisplayOrder=10000;gui.Parent=pg
local bg=Instance.new('Frame');bg.Size=UDim2.fromScale(1,1);bg.BackgroundColor3=Color3.fromRGB(32,43,38);bg.Parent=gui
local views={{'Awake / front','Awake',Vector3.new(0,.4,-1)},{'Awake / three-quarter','Awake',Vector3.new(-.75,.55,-1)},{'Asleep / front','Asleep',Vector3.new(0,.3,-1)},{'Asleep / three-quarter','Asleep',Vector3.new(-.75,.5,-1)}}
for i,entry in views do
 local vp=Instance.new('ViewportFrame');vp.Position=UDim2.fromScale(((i-1)%2)*.5,math.floor((i-1)/2)*.5);vp.Size=UDim2.fromScale(.5,.5);vp.BackgroundColor3=Color3.fromRGB(213,220,211);vp.BorderSizePixel=2;vp.Ambient=Color3.fromRGB(145,145,145);vp.LightColor=Color3.fromRGB(220,220,205);vp.LightDirection=Vector3.new(-1,-1,-1);vp.Parent=bg
 local world=Instance.new('WorldModel');world.Parent=vp;local model=A.Build(world,CFrame.identity,entry[2]);local bound,size=model:GetBoundingBox();local stand=D.StandHeight;local target=bound.Position;local direction=entry[3].Unit;local facing=CFrame.lookAt(direction,Vector3.zero);local tangent=math.tan(math.rad(20));local aspect=vp.AbsoluteSize.X/math.max(1,vp.AbsoluteSize.Y);local distance=0
 for _,sx in {-1,1}do for _,sy in {-1,1}do for _,sz in {-1,1}do local delta=Vector3.new(size.X*sx,size.Y*sy,size.Z*sz)*.5;distance=math.max(distance,math.abs(delta:Dot(facing.UpVector))*1.14/tangent+delta:Dot(direction),math.abs(delta:Dot(facing.RightVector))*1.14/(tangent*aspect)+delta:Dot(direction))end end end
 local camera=Instance.new('Camera');camera.FieldOfView=40;camera.CFrame=CFrame.lookAt(target+direction*distance,target);camera.Parent=vp;vp.CurrentCamera=camera
 for _,s in {{Vector3.new(2,2,1),Vector3.new(-size.X/2-3,2.7,-2)},{Vector3.new(1.3,1.3,1.3),Vector3.new(-size.X/2-3,4.35,-2)},{Vector3.new(.8,1.7,1),Vector3.new(-size.X/2-3.5,.85,-2)},{Vector3.new(.8,1.7,1),Vector3.new(-size.X/2-2.5,.85,-2)}}do local p=Instance.new('Part');p.Size=s[1];p.Position=s[2];p.Anchored=true;p.Color=Color3.fromRGB(125,145,160);p.Parent=world end
 local label=Instance.new('TextLabel');label.Size=UDim2.new(1,0,0,30);label.BackgroundTransparency=1;label.Font=Enum.Font.GothamBold;label.TextSize=21;label.TextColor3=Color3.fromRGB(20,35,30);label.Text=model.Name..' / '..entry[1];label.Parent=vp
end
return {Result='PASS',Name=D.Name,Height=D.StandHeight,PartCount=count,Checks='roles, floor, extents, sleep eyes, pose restore, trot body stability, 1.5x scaling'}''')
# Access by FindFirstChild, not member indexing a missing scorpion Paw.
code=[s.replace('assert(m.Torso.CFrame==body and m.LegFrontLeft_Paw==nil or m.Torso.CFrame==body)','assert(m.Torso.CFrame==body)')for s in code]
(R/'.cache/stage_creature.luau').write_text('\n'.join(code))
print(name+' review staged')
