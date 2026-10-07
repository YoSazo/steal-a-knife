"""Reproducible imagegen-source cleanup + fixed-pivot aura flipbooks (art only).

Generated grayscale shading is encoded in alpha; RGB is white even at alpha=0.
Source shapes are cropped/centred ONCE, never separately per animation frame.
"""
from pathlib import Path
import json,math,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont,ImageFilter
from scipy import ndimage
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/aura-sprites';OUT.mkdir(exist_ok=True)
NAMES=['SlimeDrip','Spiral','LightningShard','LightningBolt','SmokeWisp','Star','Ember','RainbowArc','ShockRing','LightRays']
GRIDS={'SlimeDrip':4,'LightningBolt':4,'SmokeWisp':4,'Ember':2}
Y,X=np.mgrid[0:256,0:256].astype(float);TAU=math.tau

def rgba(alpha):
 a=np.clip(np.rint(alpha*255),0,255).astype('uint8');a[a<2]=0
 result=np.full((*a.shape,4),255,dtype='uint8');result[:,:,3]=a
 return Image.fromarray(result)

def cleaned(name,size=(256,256),extent=.78):
 raw=Image.open(OUT/'sources'/f'{name}.png').convert('RGBA');arr=np.array(raw,dtype=float)/255
 alpha=arr[:,:,3]*(arr[:,:,:3]@np.array([.2126,.7152,.0722]))
 # Suppress tiny disconnected imagegen speckles; retain deliberate drops/facets.
 mask=alpha>.04;comps,count=ndimage.label(mask);sizes=np.bincount(comps.ravel());cut=max(8,sizes[1:].max()*.0007)
 keep=np.where(sizes>=cut)[0];keep=keep[keep!=0]
 accepted=ndimage.binary_dilation(np.isin(comps,keep),iterations=3)
 alpha*=accepted;alpha=ndimage.gaussian_filter(alpha,.8)
 ys,xs=np.where(alpha>.018);assert len(xs),(name,'empty source')
 crop=[xs.min(),ys.min(),xs.max()+1,ys.max()+1]
 a=Image.fromarray(np.uint8(np.clip(alpha,0,1)*255)).crop(crop)
 factor=min(size[0]*extent/a.width,size[1]*extent/a.height)
 wh=(max(1,round(a.width*factor)),max(1,round(a.height*factor)))
 a=a.resize(wh,Image.Resampling.LANCZOS);canvas=Image.new('L',size,0);canvas.paste(a,((size[0]-wh[0])//2,(size[1]-wh[1])//2))
 result=np.array(canvas,dtype=float)/255
 result/=max(result.max(),.001)
 return result,{'Source':f'sources/{name}.png','SourceCrop':list(map(int,crop)),'SourceSize':list(raw.size),'FixedPivot':[size[0]/2,size[1]/2]}

def warp(a,sx,sy):
 return ndimage.map_coordinates(a,[sy,sx],order=1,mode='constant',cval=0)

def guard(a):
 # At least 8% empty margin in every 256px cell, including translucent glow.
 edge=np.minimum.reduce([X,Y,255-X,255-Y]);a*=np.clip((edge-21)/4,0,1)
 return np.clip(a,0,1)

def animated(name,a):
 count=GRIDS[name]**2;frames=[]
 for i in range(count):
  phase=TAU*i/count
  if name=='SlimeDrip':
   sx=128+(X-128)/(1-.035*math.sin(phase))+3*np.sin(Y/40+phase)*np.clip((Y-100)/130,0,1)
   sy=128+(Y-128)/(1+.04*math.sin(phase))
   body=warp(a,sx,sy)
   # A pinching neck and detached lower drop are periodic, not random frame offsets.
   pinch=max(0,math.sin(phase))**2
   neck=np.exp(-((X-109)/11)**2-((Y-193)/5)**2)
   body*=1-.90*pinch*neck
   drop=a*(Y>210);body*=Y<=210
   travel=5*(1-math.cos(phase));fall=warp(drop,X,Y-travel)
   body=np.maximum(body,fall*(.65+.35*math.cos(phase)))
  elif name=='SmokeWisp':
   sx=128+(X-128)/(1+.045*math.sin(phase))+4*np.sin(Y/38+phase)
   sy=128+(Y-128)/(1+.035*math.cos(phase))+3*np.sin(X/46+phase)
   body=warp(a,sx,sy)*(.88+.12*math.cos(phase))
  elif name=='Ember':
   weight=np.clip((208-Y)/176,0,1)
   sx=128+(X-128)/(1+.05*math.cos(phase))+7*math.sin(phase)*weight
   sy=128+(Y-128)/(1+.04*math.sin(phase))
   body=warp(a,sx,sy)
  else:
   # Fixed anchor, local zig-zag changes; branches pulse in the middle frames.
   flash=[.12,.48,1,.70,1,.32,.85,.46,1,.28,.90,.62,.48,.28,.10,0][i]
   sx=X+2.5*np.sin(Y/24+i*2.1)*np.clip((Y-30)/200,0,1)
   body=warp(a,sx,Y)*flash
   branch=np.abs(X-128)>25
   if not 4<=i<=11:body[branch]*=.38
  frames.append(rgba(guard(body)))
 return frames

def procedural(name,size):
 y,x=np.mgrid[0:size,0:size].astype(float);x=(x-(size-1)/2)/(size/2);y=(y-(size-1)/2)/(size/2);r=np.hypot(x,y)
 if name=='ShockRing':a=np.exp(-((r-.70)/.024)**2)+.14*np.exp(-((r-.70)/.07)**2)
 elif name=='Star':
  shape=(abs(x/.74)**.58+abs(y/.74)**.58)
  a=np.clip((1.035-shape)/.045,0,1)+.26*np.exp(-(r/.30)**2)
 else:
  angle=np.arctan2(y,x);a=.70*np.exp(-(r/.12)**2)
  for i in range(10):
   theta=TAU*i/10+.12*math.sin(i*2.7);length=.70+.09*math.sin(i*1.9);width=.035+.018*(.5+.5*math.cos(i*2.1))
   delta=np.angle(np.exp(1j*(angle-theta)))
   a+=.60*np.exp(-(delta/width)**2)*np.clip(1-r/length,0,1)**.9
 a=np.clip(a,0,1);margin=math.ceil(size*.08);a[:margin]=0;a[-margin:]=0;a[:,:margin]=0;a[:,-margin:]=0
 return rgba(a)

manifest=[];frames_by_name={}
for name in NAMES:
 if name in ('Star','ShockRing','LightRays'):
  image=procedural(name,512 if name=='LightRays' else 256);info={'Source':'procedural','FixedPivot':[image.width/2,image.height/2]};frames=[image]
 else:
  size=(512,256) if name=='RainbowArc' else (256,256)
  a,info=cleaned(name,size,.84 if name in ('Spiral','LightningShard','RainbowArc') else .76)
  py=math.ceil(size[1]*.08);px=math.ceil(size[0]*.08)
  a[:py]=0;a[-py:]=0;a[:,:px]=0;a[:,-px:]=0
  frames=animated(name,a) if name in GRIDS else [rgba(a)]
  if name in GRIDS:
   grid=GRIDS[name];image=Image.new('RGBA',(grid*256,grid*256),(255,255,255,0))
   for i,f in enumerate(frames):image.paste(f,((i%grid)*256,(i//grid)*256))
  else:image=frames[0]
 path=OUT/f'{name}.png';image.save(path);arr=np.array(image)
 assert np.all(arr[:,:,:3]==255),(name,'dark/coloured RGB fringe')
 boxes=[]
 for f in frames:
  bbox=f.getchannel('A').getbbox();boxes.append(bbox)
  if bbox:
   assert min(bbox[0]/f.width,bbox[1]/f.height,(f.width-bbox[2])/f.width,(f.height-bbox[3])/f.height)>=.08,(name,'frame padding',bbox)
 frame_a=[np.array(f.getchannel('A'),dtype=float)/255 for f in frames]
 loop=name in ('SlimeDrip','SmokeWisp','Ember')
 diffs=[float(np.abs(frame_a[i]-frame_a[i-1]).mean()) for i in range(1,len(frames))]
 wrap=float(np.abs(frame_a[-1]-frame_a[0]).mean()) if loop else None
 if loop:assert wrap<=max(diffs)*1.6+1e-5,(name,'loop seam',wrap,diffs)
 if len(frames)>1:assert max(diffs)>0,(name,'static flipbook')
 row=dict(Name=name,File=f'{name}.png',Size=list(image.size),CellSize=list(frames[0].size),FrameCount=len(frames),Flipbook=f'Grid{GRIDS[name]}x{GRIDS[name]}' if name in GRIDS else None,Loop=loop if name in GRIDS else None,WhiteRGB=True,StraightAlpha=True,PaddingPass=True,FrameBounds=boxes,LoopWrapMeanDifference=wrap,SourceInfo=info,SHA256=hashlib.sha256(path.read_bytes()).hexdigest())
 manifest.append(row);frames_by_name[name]=frames
 if name in GRIDS:
  previews=[]
  for f in frames:
   bg=Image.new('RGBA',f.size,(48,146,30,255));t=Image.new('RGBA',f.size,(195,55,255,255));t.putalpha(f.getchannel('A'));bg.alpha_composite(t);previews.append(bg.convert('RGB'))
  previews[0].save(OUT/f'{name}-preview.gif',save_all=True,append_images=previews[1:],duration=100,loop=0)

# Full grids are shown intact, three ways. No labels are baked into runtime sprites.
sheet=Image.new('RGB',(1620,10*540+80),(27,32,42));draw=ImageDraw.Draw(sheet)
font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',24);small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
draw.text((20,10),'AURA SPRITES / WHITE OVER BLACK / WHITE OVER GRASS / VIOLET OVER GRASS',font=font,fill='white')
for row,m in enumerate(manifest):
 name=m['Name'];im=Image.open(OUT/m['File']).convert('RGBA');im.thumbnail((500,500),Image.Resampling.LANCZOS)
 for col,(bgcolour,tint) in enumerate([((0,0,0),(255,255,255)),((48,146,30),(255,255,255)),((48,146,30),(195,55,255))]):
  tile=Image.new('RGBA',(500,500),(*bgcolour,255));paint=Image.new('RGBA',im.size,(*tint,255));paint.putalpha(im.getchannel('A'));tile.alpha_composite(paint,((500-im.width)//2,(500-im.height)//2));sheet.paste(tile.convert('RGB'),(20+col*535,70+row*540))
 draw.text((20,70+row*540+505),name+' / '+str(m['Size'])+' / '+str(m['FrameCount'])+' frames',font=small,fill='white')
sheet.save(OUT/'preview.png');(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps([{k:r[k] for k in ('Name','Size','FrameCount','WhiteRGB','PaddingPass','LoopWrapMeanDifference')} for r in manifest],indent=2))
