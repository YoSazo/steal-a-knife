"""Export a temporary Studio fixture and eight-rarity art contract checks, no gameplay."""
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
RARITIES=['Common','Rare','Epic','Legendary','Mythic','Godly','Celestial','Cosmic']
meta=json.loads((ROOT/'assets/coffins/geometry.json').read_text())['Metadata']
lines=["local old=game.ReplicatedStorage:FindFirstChild('CoffinReviewShared');if old then old:Destroy()end;local shared=Instance.new('Folder');shared.Name='CoffinReviewShared';shared.Parent=game.ReplicatedStorage", "local function folder(n,p)local f=Instance.new('Folder');f.Name=n;f.Parent=p;return f end;local config=folder('Config',shared);local geom=folder('ToyGeometry',config);local assets=folder('Assets',shared)"]
for rel,parent in [('Assets/CoffinAssets.luau','assets')]+[(f'Config/ToyGeometry/Coffin_{r}.luau','geom')for r in RARITIES]:
 source=(ROOT/'src/shared'/rel).read_text();lines.append("do local m=Instance.new('ModuleScript');m.Name="+json.dumps(Path(rel).stem)+";m.Source=[====["+source+"]====];m.Parent="+parent+" end")
lines+= ["local old=workspace:FindFirstChild('CoffinArtReview');if old then old:Destroy()end;local review=folder('CoffinArtReview',workspace);local builder=require(assets.CoffinAssets);local summary={}"]
cursor=0
for r in RARITIES:
 m=meta['Coffin_'+r];width=m['BoundsSize'][0];x=6100-cursor-width/2;cursor+=width+1.8
 lines.append(f"do local m=builder.BuildCoffin('{r}',review,CFrame.new({x},10,100));assert(m:GetAttribute('BaseLength')=={m['Length']});local count,lid,glow,crack,minY=0,0,0,0,math.huge;local rest={{}};for _,p in m:GetDescendants()do if p:IsA('BasePart')then count+=1;assert(p.Anchored and not p.CanCollide and not p.CanTouch and not p.CanQuery);if p.Name~='Root' and p.Transparency==0 then minY=math.min(minY,p.Position.Y-p.Size.Y/2)end;local role=p:GetAttribute('Role');if role=='Lid'then lid+=1 else rest[p]=p.CFrame end;if role=='Glow'then glow+=1 elseif role=='Crack'then crack+=1 end end end;assert(count=={m['PartCount']} and lid>10 and glow>0 and crack==1);assert(math.abs(minY-10)<.001);builder.SetCoffinOpen(m,105);for p,cf in rest do assert(p.CFrame==cf)end;builder.SetCoffinOpen(m,0);local pivot=m:GetPivot();m:ScaleTo(1.7);builder.SetCoffinOpen(m,105);builder.SetCoffinOpen(m,0);m:ScaleTo(1);assert(m:GetPivot()==pivot);local gui=Instance.new('BillboardGui');gui.Adornee=m.PrimaryPart;gui.Size=UDim2.fromOffset(140,30);gui.StudsOffset=Vector3.new(0,1,-{m['Length']/2+1.5});gui.AlwaysOnTop=true;gui.Parent=m.PrimaryPart;local label=Instance.new('TextLabel');label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1;label.Text='{r}';label.TextColor3=Color3.new(1,1,1);label.TextStrokeTransparency=0;label.TextSize=18;label.Font=Enum.Font.GothamBold;label.Parent=gui;table.insert(summary,'{r}: '..count..' parts, Lid '..lid..', Glow '..glow..', Crack '..crack)end")
center=6100-(cursor-1.8)/2
lines.append(f"game:GetService('RunService'):UnbindFromRenderStep('ArtReviewCamera');game:GetService('RunService'):BindToRenderStep('ArtReviewCamera',9999,function()local c=workspace.CurrentCamera;c.CameraType=Enum.CameraType.Scriptable;c.CFrame=CFrame.lookAt(Vector3.new({center},35,57),Vector3.new({center},11,100))end);return table.concat(summary,'\\n')")
(ROOT/'.cache/stage_coffins.luau').write_text('\n'.join(lines));print('Coffin stage source written')
