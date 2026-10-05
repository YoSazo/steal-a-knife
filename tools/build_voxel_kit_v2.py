"""Intentional mockup cut-outs, pixel provenance, state variants and reconstruction proofs.

No generated redraws. Normal artwork is sampled from the delivered 23 originals.
Hidden interiors use documented donor strips; state variants transform the same pixels.
"""
from pathlib import Path
import json, hashlib, colorsys, shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT=Path(__file__).resolve().parents[1]
MOCK=ROOT/'assets/visual-expansion/mockups'
OUT=ROOT/'assets/voxel-ui/kit-v2'
ART=ROOT/'assets/voxel-ui'
for folder in ('png','sources','masks','review','verification'):
 (OUT/folder).mkdir(parents=True,exist_ok=True)
RECORDS=[];LOOKUP={};LAYOUTS=[]
FONT=ART/'fonts/Fredoka.ttf'
SOURCES={}
def source(screen,device='phone'):
 key=f'{screen}-{device}'
 if key not in SOURCES:
  p=MOCK/(key+'.png');SOURCES[key]=Image.open(p).convert('RGBA')
 return SOURCES[key]

def cut(key,screen,rect,device='phone',inset=18,donor=None,mode='frame',family='Source',state='Normal'):
 """Rect is [left,top,right,bottom], at the exported mockup's actual resolution."""
 if key in LOOKUP:return LOOKUP[key]
 original=source(screen,device)
 x,y,r,b=map(int,rect);assert 0<=x<r<=original.width and 0<=y<b<=original.height,(key,rect)
 crop=original.crop((x,y,r,b));w,h=crop.size
 role=key.split('_')[-1].split('.')[-1]
 if any(s in key for s in ('Card','Panel','HudTile','StatTile','Timer','ListRow','LoadoutSlot','TitlePlate','OddsStrip','HealthTile','EnergyTile','ReelFrame','ToastPlate','RolePlate','RewardPlate')):
  inset=max(inset,40)
 ix=min(inset,w//4);iy=min(inset,h//4)
 # Use a visible blank vertical strip to restore the background formerly hidden
 # by text/icons. The entire interior remains an original-image pixel mapping.
 dx=donor if donor is not None else min(w-ix-2,ix+3)
 dx=max(0,min(w-2,dx))
 strip=crop.crop((dx,0,dx+2,h))
 # Corner blocks, nested controls and glyphs sometimes cross the donor column.
 # Use the dominant blank-face colour to reject those rows; replace them with
 # the nearest unobstructed original row, without painting any new pixels.
 column=np.array(strip);mid=column[min(iy+5,h//3):max(h-iy-5,h*2//3),:,:3].reshape(-1,3)
 typical=np.median(mid,axis=0)
 distances=np.linalg.norm(column[:,:,:3].astype(float)-typical,axis=2).max(axis=1)
 valid=np.where((distances<52)&(np.arange(h)>=min(iy+4,h//3))&(np.arange(h)<max(h-iy-4,h*2//3)))[0]
 if len(valid)<3:valid=np.argsort(distances)[:max(3,h//8)]
 mapped=np.array([valid[np.abs(valid-v).argmin()] for v in range(h)])
 strip=Image.fromarray(column[mapped]);clean=strip.resize((w,h),Image.Resampling.NEAREST)
 keep=Image.new('L',(w,h),0);d=ImageDraw.Draw(keep)
 if mode=='fill':
  keep=Image.new('L',(w,h),255);clean=crop.copy()
 else:
  # The artwork's rail widths and cap dimensions are kept at source scale.
  side=max(4,min(16,ix//2));top=max(4,min(20,iy));bottom=max(4,min(18,iy))
  if key=='Window':side,top,bottom=52,35,54
  for box in ((0,0,w-1,top-1),(0,h-bottom,w-1,h-1),(0,0,side-1,h-1),(w-side,0,w-1,h-1),
              (0,0,ix-1,iy-1),(w-ix,0,w-1,iy-1),(0,h-iy,ix-1,h-1),(w-ix,h-iy,w-1,h-1)):
   d.rectangle(box,fill=255)
  # Action faces in card lower corners are a separate layer, not card artwork.
  if 'Card' in key and not any(s in key for s in ('FloorCard','RewardCard','WinnerCard','InnerCard')):
   pixels=np.array(crop);km=np.array(keep)
   green=(pixels[:,:,1]>100)&(pixels[:,:,1]>pixels[:,:,2]*1.3)&(pixels[:,:,1]>pixels[:,:,0]*1.5)
   blue=(pixels[:,:,2]>145)&(pixels[:,:,2]>pixels[:,:,1]*1.6)
   bottom_region=np.arange(h)[:,None]>h-iy
   km[(green|blue)&bottom_region]=0;keep=Image.fromarray(km)
  clean.paste(crop,(0,0),keep)
 # Two export pixels of alpha clearance within the bounding rect keep source
 # backgrounds outside a stepped button/window silhouette out of the asset.
 alpha=Image.new('L',(w,h),255);a=ImageDraw.Draw(alpha)
 corner=min(6,max(2,inset//4))
 for box in ((0,0,corner-1,corner-1),(w-corner,0,w-1,corner-1),
             (0,h-corner,corner-1,h-1),(w-corner,h-corner,w-1,h-1)):
  a.rectangle(box,fill=0)
 if mode=='fill': alpha=Image.new('L',(w,h),255)
 # Components may have source text touching their outer rails. Such restorations
 # are explicitly defined below rather than silently included in the audit.
 repairs=[]
 def repair(box,donor_box,flip=False):
  tile=crop.crop(donor_box)
  if flip:tile=tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
  tile=tile.resize((box[2]-box[0],box[3]-box[1]),Image.Resampling.NEAREST)
  clean.paste(tile,(box[0],box[1]));ImageDraw.Draw(keep).rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=0)
  repairs.append({'SourceRect':[x+donor_box[0],y+donor_box[1],x+donor_box[2],y+donor_box[3]],'DestinationInCrop':list(box),'Method':'Clone visible rail/corner from same original component','HorizontalMirror':flip})
 if key=='Window':
  repair((480,0,1280,74),(160,0,162,74))
  repair((w-180,0,w,130),(0,0,180,130),True)
 if 'TitlePlate' in key and screen=='KnifeIndex':
  repair((40,h-38,min(255,w-ix),h),(w-ix-75,h-38,w-ix-73,h))
 if key=='SecondaryButton' or role=='Secondary':
  repair((w-23,h-23,w,h),(0,h-23,23,h),True)
 if key=='PrimaryButton' or role=='Primary':
  repair((0,h-23,23,h),(w-23,h-23,w,h),True)
 clean.putalpha(alpha)
 keep=Image.fromarray(np.minimum(np.array(keep),np.array(alpha)))
 final=clean.resize((w*2,h*2),Image.Resampling.NEAREST)
 rel='png/'+key.replace('.','/')+'.png';path=OUT/rel;path.parent.mkdir(parents=True,exist_ok=True)
 final.save(path,optimize=True)
 mp='masks/'+key.replace('.','/')+'.png';maskpath=OUT/mp;maskpath.parent.mkdir(parents=True,exist_ok=True);keep.save(maskpath)
 # Local source crops make every asset reviewable independently of cache files.
 sp='sources/'+key.replace('.','/')+'.png';srcpath=OUT/sp;srcpath.parent.mkdir(parents=True,exist_ok=True);crop.save(srcpath)
 arr=np.array(clean);orig=np.array(crop);mask=np.array(keep)>0
 changed=int(np.any(arr[mask]!=orig[mask],axis=1).sum())
 assert changed==0,key
 rec={'Key':key,'Family':family,'State':state,'File':rel,'Size':[w*2,h*2],
      'SourceMockup':f'assets/visual-expansion/mockups/{screen}-{device}.png','SourceCropRect':[x,y,r,b],
      'SourceSize':list(original.size),'SliceCenter':[ix*2,iy*2,(w-ix)*2,(h-iy)*2],
      'SliceScale':0.5,'SourceCrop':sp,'VisibleSourceMask':mp,'RetainedSourcePixels':int(mask.sum()),
      'ChangedRetainedPixels':changed,'Restoration':{'Method':'Nearest-neighbour horizontal replication of unobstructed original strip',
      'DonorRect':[x+dx,y,x+dx+2,b],'DonorRowMap':mapped.tolist(),'Destination':'Interior outside recorded retained rail/corner mask',
      'AdditionalRepairs':repairs},'Upscale':'2x nearest neighbour; source detail is preserved, not invented',
      'SHA256':hashlib.sha256(path.read_bytes()).hexdigest()}
 RECORDS.append(rec);LOOKUP[key]=rec
 return rec

def alter(key,base,state,hue=None):
 rec=LOOKUP[base];im=Image.open(OUT/rec['File']).convert('RGBA');arr=np.array(im)
 rgb=arr[:,:,:3].astype(float)/255
 if hue is not None:
  # Retain local value/highlight contrast and outline darkness; recolour only
  # chromatic pixels, leaving the original near-white glints intact.
  import cv2
  hsv=cv2.cvtColor(rgb.astype(np.float32),cv2.COLOR_RGB2HSV)
  colored=(hsv[:,:,1]>.18)&(hsv[:,:,2]>.13)
  hsv[:,:,0][colored]=hue
  rgb=cv2.cvtColor(hsv,cv2.COLOR_HSV2RGB).clip(0,1)
 if state=='Pressed':rgb*=.78
 elif state=='Disabled':
  luminance=rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722
  rgb=np.repeat(luminance[:,:,None],3,axis=2)*.68
 elif state in ('Selected','Active'):
  if hue is None:
   import cv2
   hsv=cv2.cvtColor(rgb.astype(np.float32),cv2.COLOR_RGB2HSV)
   colored=(hsv[:,:,1]>.18)&(hsv[:,:,2]>.13)
   hsv[:,:,0][colored]=185;hsv[:,:,1][colored]=np.maximum(.5,hsv[:,:,1][colored])
   hsv[:,:,2][colored]=np.minimum(1,hsv[:,:,2][colored]*1.22)
   rgb=cv2.cvtColor(hsv,cv2.COLOR_HSV2RGB).clip(0,1)
 arr[:,:,:3]=np.round(rgb*255).astype('uint8');out=Image.fromarray(arr)
 offset=[0,0]
 if state=='Pressed':
  # Constant canvas padding avoids clipping the translated silhouette.
  offset=[4,4];translated=Image.new('RGBA',(out.width+4,out.height+4));translated.alpha_composite(out,(4,4));out=translated
 rel='png/'+key.replace('.','/')+'.png';path=OUT/rel;path.parent.mkdir(parents=True,exist_ok=True);out.save(path,optimize=True)
 new={**rec,'Key':key,'File':rel,'Size':list(out.size),'State':state,'Base':base,
      'StateTransform':{'HueDegrees':hue,'Brightness':.78 if state=='Pressed' else 1,'Grayscale':state=='Disabled','OffsetAt2x':offset},
      'RetainedSourcePixels':0,'ChangedRetainedPixels':None,'SHA256':hashlib.sha256(path.read_bytes()).hexdigest()}
 if state=='Pressed':new['SliceCenter']=[v+4 for v in rec['SliceCenter']]
 RECORDS.append(new);LOOKUP[key]=new;return new

# The first four screens supply the family names Claude can swap in one config.
# Distinct source styles are kept as distinct pieces, not squeezed into a generic frame.
BASES=[
 ('Window','Rebirth',(326,128,2074,1040),80,60),
 ('Panel','Powers',(1909,139,2385,1056),24,26),
 ('TitlePlate','Powers',(168,9,2253,125),20,1000),
 ('TitlePlateBlue','Upgrades',(420,14,1854,158),32,1100),
 ('SubHeader','StorePasses',(487,177,2372,316),40,1450),
 ('Card','Powers',(313,145,694,601),22,25),
 ('CardIndex','KnifeIndex',(41,342,421,675),22,26),
 ('InnerCard','Rebirth',(901,298,1398,585),22,27),
 ('ListRow','Upgrades',(425,167,1849,382),22,26),
 ('PlayerRow','Players',(390,260,1680,399),18,27),
 ('Tab.Normal','KnifeIndex',(317,226,573,323),18,23),
 ('Tab.Active','KnifeIndex',(51,225,311,326),20,25),
 ('NavItem.Normal','Powers',(10,145,287,246),14,110),
 ('NavItem.Active','Powers',(8,680,294,799),14,110),
 ('HudTile','MainHud',(54,254,380,396),22,280),
 ('StatTile.Speed','MainHud',(55,77,315,208),20,237),
 ('StatTile.Cash','MainHud',(325,77,628,208),20,284),
 ('StatTile.Heat','MainHud',(640,77,881,208),20,222),
 ('StatTile.Chance','MainHud',(1538,76,1893,209),20,24),
 ('TimerPlate','MainHud',(896,11,1505,228),32,75),
 ('CurrencyPill','Powers',(1237,38,1488,116),'desktop',12,16),
 ('ProgressTrack','KnifeIndex',(1066,111,1716,175),15,615),
 ('ProgressTrack.Segmented','Upgrades',(1078,216,1451,288),13,322),
 ('ProgressFill.Cyan','KnifeIndex',(1081,121,1394,162),6,8),
 ('ProgressFill.Health','MainHud',(704,970,1148,1008),6,8),
 ('ProgressFill.Energy','MainHud',(1273,970,1712,1008),6,8),
 ('PrimaryButton','Powers',(335,518,509,583),12,16),
 ('SecondaryButton','Powers',(512,518,681,583),12,16),
 ('DangerButton','Rebirth',(1257,806,2007,974),22,27),
 ('GoldButton','Unbox',(1031,821,1568,1012),22,30),
 ('CloseButton','KnifeIndex',(2241,23,2376,148),16,20),
 ('BackButton','Powers',(13,8,149,123),16,19),
 ('SettingsButton','Powers',(2270,8,2390,124),16,20),
 ('LoadoutSlot','Powers',(1956,245,2353,459),20,24),
 ('NumberBadge','Powers',(778,937,825,980),'desktop',8,7),
 ('OddsStrip','Unbox',(1420,94,2354,248),20,24),
 ('NamePlate','KnifeIndex',(61,604,404,662),14,18),
 ('HealthTile','MainHud',(651,892,1194,1028),20,25),
 ('EnergyTile','MainHud',(1213,892,1755,1028),20,25),
 ('LoadoutPanel','Powers',(261,927,1905,1068),'desktop',22,26),
 ('ToggleTrack','Stats',(2077,598,2292,702),16,21),
 ('DailyTile','WelcomeDaily',(450,548,750,905),24,30),
 ('StreakNode','WelcomeDaily',(833,931,947,1036),16,22),
 ('ToastPlate','ToastsAnnouncements',(449,50,1950,225),64,77),
 ('RolePlate.Innocent','RevealInnocent',(535,112,1916,614),28,35),
 ('RolePlate.Murderer','RevealMurderer',(537,108,1801,619),28,35),
 ('RewardPlate','Unbox',(774,779,1622,1050),26,33),
 ('ReelFrame','Unbox',(16,286,2386,765),30,36),
 ('ReelTile','Unbox',(397,344,708,706),25,30),
 ('WinnerCard','RoundResults',(120,64,979,1020),28,36),
 ('ResultsRow','RoundResults',(1007,161,2287,336),18,24),
 ('FloorCard','Upgrades',(1868,80,2384,1048),22,26),
 ('FloorValue','Upgrades',(1902,654,2349,794),18,23),
 ('FloorValue.Active','Upgrades',(1904,861,2348,1008),18,23),
]

def bases():
 for spec in BASES:
  name,screen,rect,*rest=spec;device='phone'
  if rest[0]=='desktop':device=rest.pop(0)
  inset,donor=rest
  if screen=='MainHud':continue
  cut(name,screen,rect,device,inset,donor,'fill' if name.startswith('ProgressFill') else 'frame','Reusable')
 alter('ProgressFill.Health','ProgressFill.Cyan','Normal',355)
 alter('ProgressFill.Energy','ProgressFill.Cyan','Normal',49)
 # Exact coloured tabs are visible together in the desktop Index.
 bounds=[(399,186,575,258),(577,186,752,258),(755,186,932,258),(936,186,1128,258),
         (1130,186,1306,258),(1309,186,1490,258),(1494,186,1672,258),(1678,186,1854,258)]
 rarities=('Common','Rare','Epic','Legendary','Mythic','Godly','Celestial','Cosmic')
 hues=(215,208,275,47,348,316,185,280)
 for rarity,rect,hue in zip(rarities,bounds,hues):
  key='RarityTab.'+rarity;cut(key,'KnifeIndex',rect,'desktop',12,14,family='Reusable')
  alter('RarityBadge.'+rarity,'NamePlate','Normal',hue)
 # Every button/tab/nav control gets state exports. They are derived from the
 # source art, because the static mockups do not show pressed/disabled states.
 controls=('PrimaryButton','SecondaryButton','DangerButton','GoldButton','CloseButton','BackButton','SettingsButton',
           'Tab.Normal','Tab.Active','NavItem.Normal','NavItem.Active','ListRow','PlayerRow','CurrencyPill',
           'LoadoutSlot','NumberBadge','ToggleTrack','DailyTile')
 for key in controls:
  for state in ('Pressed','Disabled','Selected'):
   alter(key+'.'+state,key,state)
 for rarity in rarities:
  for state in ('Pressed','Disabled','Active'):
   alter('RarityTab.'+rarity+'.'+state,'RarityTab.'+rarity,state)

MANIFEST=json.loads((ART/'manifest.json').read_text())
ICONS={a['Id']:a for a in MANIFEST['Assets']}
class Proof:
 def __init__(self,name,device):
  self.name=name;self.device=device;self.ref=source(name,device)
  self.im=Image.new('RGBA',self.ref.size,(16,27,48,255));self.elements=[]
  self.struct=Image.new('RGBA',self.ref.size,(16,27,48,255))
  self.mask=Image.new('L',self.ref.size);self.over=Image.new('L',self.ref.size)
  self.index=0
 def skin(self,role,rect,inset=18,donor=None):
  self.index+=1;key=f'SourceVariants.{self.name}{self.device.title()}.{self.index:02d}_{role}'
  rec=cut(key,self.name,rect,self.device,inset,donor,family='SourceVariant')
  im=Image.open(OUT/rec['File']).convert('RGBA').resize((rect[2]-rect[0],rect[3]-rect[1]),Image.Resampling.NEAREST)
  self.im.alpha_composite(im,(rect[0],rect[1]));self.struct.alpha_composite(im,(rect[0],rect[1]))
  mask=Image.open(OUT/rec['VisibleSourceMask'])
  self.mask.paste(mask,(rect[0],rect[1]))
  self.elements.append({'Type':'Piece','Key':key,'Box':list(rect),'ScaleType':'Slice','SliceScale':.5})
 def icon(self,key,rect):
  x,y,r,b=rect;im=Image.open(ART/ICONS[key]['File']).convert('RGBA');im=im.crop(im.getchannel('A').getbbox());im.thumbnail((r-x,b-y),Image.Resampling.LANCZOS)
  xx=x+(r-x-im.width)//2;yy=y+(b-y-im.height)//2
  self.im.alpha_composite(im,(xx,yy));self.over.paste(255,(xx,yy,xx+im.width,yy+im.height),im.getchannel('A'))
  self.elements.append({'Type':'ExistingIcon','Key':key,'Box':list(rect)})
 def text(self,text,rect,size=28,color=(250,251,255),stroke=3):
  x,y,r,b=rect;f=ImageFont.truetype(str(FONT),size);f.set_variation_by_name('Bold')
  while max(f.getlength(s) for s in text.split('\n'))>r-x-8 and size>10:
   size-=1;f=ImageFont.truetype(str(FONT),size);f.set_variation_by_name('Bold')
  layer=Image.new('RGBA',self.im.size);d=ImageDraw.Draw(layer);lines=text.split('\n');lh=size*1.12
  for i,line in enumerate(lines):
   bounds=f.getbbox(line);xx=x+(r-x-f.getlength(line))/2;yy=y+(b-y-lh*len(lines))/2+i*lh-bounds[1]
   d.text((xx,yy),line,font=f,fill=color,stroke_width=stroke,stroke_fill=(3,8,20))
  self.im.alpha_composite(layer);self.over=ImageChops.lighter(self.over,layer.getchannel('A'))
  self.elements.append({'Type':'PlaceholderText','Text':text,'Box':list(rect),'Font':'FredokaOne','FontSize':size})
 def finish(self):
  folder=OUT/'verification';name=f'{self.name}-{self.device}'
  self.im.save(folder/(name+'-rebuilt.png'),optimize=True)
  # Full difference includes expected placeholder-font/model-icon/background
  # differences. Never use that as a pixel-perfect screen claim.
  diff=ImageChops.difference(self.ref.convert('RGB'),self.im.convert('RGB'))
  diff.save(folder/(name+'-difference.png'))
  pair=Image.new('RGB',(self.im.width*2,self.im.height));pair.paste(self.ref.convert('RGB'),(0,0));pair.paste(self.im.convert('RGB'),(self.im.width,0));pair.save(folder/(name+'-side-by-side.png'))
  retained=np.array(self.mask)>0
  # Compare the composed skin layer, and also the visible final layer. Overlays
  # are explicitly recorded, not silently used to conceal a mismatching rail.
  direct=np.array(self.ref)[:,:,:3];struct=np.array(self.struct)[:,:,:3]
  structural_changed=np.any(direct!=struct,axis=2)&retained
  final=np.array(self.im)[:,:,:3];visible=retained&(np.array(self.over)==0)
  final_changed=np.any(direct!=final,axis=2)&visible
  heat=np.zeros((*retained.shape,3),dtype=np.uint8);heat[structural_changed]=[255,0,80]
  Image.fromarray(heat).save(folder/(name+'-border-difference.png'))
  self.mask.save(folder/(name+'-border-mask.png'))
  stats={'Screen':self.name,'Device':self.device,'Size':list(self.im.size),'Source':f'assets/visual-expansion/mockups/{name}.png',
         'FullScreenChangedPixels':int(np.any(np.array(diff)!=0,axis=2).sum()),
         'RetainedStructuralPixels':int(retained.sum()),'ChangedStructuralPixels':int(structural_changed.sum()),
         'VisibleFinalBorderPixels':int(visible.sum()),'ChangedVisibleFinalBorderPixels':int(final_changed.sum()),
         'Layout':self.elements,'Scope':'Source-specific cutout variants preserve the original visible rails. Shared family skins and state variants are separately reusable. Placeholder text/existing icons differ from generated reference art.'}
  LAYOUTS.append(stats)
  return stats

def powers(device):
 p=Proof('Powers',device);phone=device=='phone'
 if phone:
  p.skin('TitlePlate',(168,9,2253,125),20,1000);p.text('Powers',(210,22,563,115),87)
  p.skin('BackButton',(13,8,149,123),16,19);p.text('‹',(32,16,131,106),90)
  p.skin('SettingsButton',(2270,8,2390,124),16,20);p.icon('Hud.Settings',(2287,22,2376,110))
  p.icon('Hud.Cash',(1870,20,1985,110));p.text('1,250',(1982,30,2135,110),49)
  p.skin('Plus',(2148,30,2227,106),10,14);p.text('+',(2160,34,2217,101),55)
  nav=['Shop','Index','More','Knives','Players','Powers','Stats','Settings']
  ys=[145,251,359,467,575,680,799,919]
  for i,(label,y) in enumerate(zip(nav,ys)):
   p.skin('NavActive' if i==5 else 'NavItem',(9,y,290,y+(116 if i==5 else 103)),14,110)
   p.icon('Hud.'+label,(29,y+12,111,y+93));p.text(label,(122,y+17,280,y+88),35)
  p.skin('Panel',(1909,139,2385,1056),24,26);p.text('Loadout',(1950,160,2307,227),55)
  for i,y in enumerate((245,474,702)):
   p.skin('LoadoutSlot',(1956,y,2353,y+214),20,24);p.text('+',(2091,y+36,2220,y+119),78,color=(130,151,188));p.text('Select Power',(2000,y+131,2315,y+184),32,color=(182,205,248))
  xs=[313,710,1108,1507];ys=[145,617];cw,ch=381,456
 else:
  p.skin('HeaderPanel',(248,13,1780,125),25,920);p.skin('TitlePlate',(251,11,925,124),23,620);p.text('POWERS',(370,20,799,106),82)
  p.icon('Hud.Powers',(293,24,360,109));p.skin('Close',(1793,24,1905,127),20,24);p.text('X',(1803,37,1889,107),69)
  p.skin('CurrencyPill',(1237,38,1488,116),12,16);p.icon('Hud.Cash',(1253,46,1337,104));p.text('12,450',(1336,46,1463,108),38)
  p.skin('CurrencyPill',(1500,39,1705,116),12,16);p.icon('Hud.Stats',(1512,49,1570,104));p.text('320',(1582,49,1685,105),39)
  nav=['Shop','Index','More','Knives','Players','Powers','Rebirth','Stats','Upgrades','Spin','Merchant','FreeChest','Speed','Settings']
  p.skin('NavPanel',(8,54,258,1063),18,230)
  for i,label in enumerate(nav):
   y=80+i*69;p.skin('NavItem',(27,y,243,y+67),10,194);p.icon('Hud.'+label,(34,y+3,114,y+63));p.text(label,(117,y+14,235,y+53),25)
  p.skin('CardsPanel',(263,135,1895,924),23,27)
  p.skin('LoadoutPanel',(263,932,1896,1066),23,27);p.text('LOADOUT',(331,955,744,1049),54)
  for i,x in enumerate((778,974,1171,1367)):
   p.skin('LoadoutSlot',(x,939,x+174,1052),13,17);p.skin('NumberBadge',(x,937,x+47,980),9,12);p.text(str(i+1),(x+6,941,x+39,974),31)
  p.icon('Hud.Powers',(826,954,913,1042))
  xs=[294,687,1080,1472];ys=[145,534];cw,ch=386,374
 labels=['Vanish','Radar','Bear Trap','Shield','Decoy','Flash','Barricade','Mimic']
 desc=['Turn invisible for a\nshort time.','Reveal nearby players\non your map.','Place a trap that\nstuns players.','Gain a temporary\ndamage shield.','Spawn a fake player\nto confuse others.','Blind nearby players\nfor a short time.','Place a wall to block\npaths.','Copy the last power\nused by another player.']
 for i,label in enumerate(labels):
  x,y=xs[i%4],ys[i//4];p.skin('Card',(x,y,x+cw,y+ch),22,25)
  p.icon('Hud.Powers',(x+90,y+20,x+cw-75,y+(170 if phone else 132)))
  p.text(label,(x+20,y+(174 if phone else 124),x+cw-20,y+(221 if phone else 165)),40 if phone else 35)
  p.text(desc[i],(x+22,y+(225 if phone else 164),x+cw-22,y+(290 if phone else 231)),29 if phone else 26,color=(177,200,244),stroke=1)
  by=y+ch-87;p.text('Lv. 1',(x+22,by-43,x+97,by-7),26)
  track=(x+103,by-46,x+cw-31,by-9);p.skin('ProgressTrack',track,9,track[2]-track[0]-14)
  p.text('0/5',(x+cw-96,by-43,x+cw-40,by-14),23)
  split=x+cw//2
  p.skin('Primary',(x+20,by,split-7,y+ch-20),12,16);p.text('Equip',(x+35,by+4,split-21,y+ch-25),28)
  p.skin('Secondary',(split+4,by,x+cw-17,y+ch-20),12,16);p.text('Upgrade',(split+13,by+4,x+cw-23,y+ch-25),28)
 return p.finish()

def index(device):
 p=Proof('KnifeIndex',device);phone=device=='phone'
 if phone:
  p.skin('TitlePlate',(30,18,1008,211),28,940);p.icon('Hud.Index',(78,45,252,187));p.text('KNIFE INDEX',(277,43,955,185),88)
  p.skin('ProgressPanel',(1028,24,2214,207),24,1000);p.text('DISCOVERED',(1071,55,1368,102),35);p.text('12 / 24 (50%)',(1472,57,1710,99),35)
  p.skin('ProgressTrack',(1066,111,1716,175),15,615)
  # Cyan fill comes from an unobstructed reference section, not a drawn rectangle.
  rec=LOOKUP['ProgressFill.Cyan'];im=Image.open(OUT/rec['File']).resize((313,41),Image.Resampling.NEAREST);p.im.alpha_composite(im,(1081,121))
  p.elements.append({'Type':'Piece','Key':'ProgressFill.Cyan','Box':[1081,121,1394,162]})
  p.skin('RewardCard',(1740,47,2180,180),16,22);p.icon('Hud.FreeChest',(1765,40,1901,174))
  p.skin('Primary',(1901,58,2170,169),16,20);p.text('CLAIM\nREWARD',(1912,64,2154,162),36)
  p.skin('Close',(2241,23,2376,148),16,20);p.text('X',(2258,36,2360,130),74)
  tx=[51,317,576,818,1071,1331,1594,1860,2126];tw=[260,256,240,250,257,260,263,264,227]
  for i,label in enumerate(['ALL','COMMON','RARE','EPIC','LEGENDARY','MYTHIC','GODLY','CELESTIAL','COSMIC']):
   p.skin('Tab',(tx[i],226,tx[i]+tw[i],323),18,23);p.text(label,(tx[i]+13,244,tx[i]+tw[i]-12,307),32)
  xs=[41,436,824,1207,1597,1981];ys=[342,695];cw,ch=380,333
  names=['RustyShank','KitchenKnife','HunterBlade','PocketKnife','BoneCarver','Switchblade','ThornDagger','Cleaver','Katana','GoldenDagger','InfernoFang','Machete'];hidden={2,4,6,9}
 else:
  p.skin('TitlePlate',(166,27,778,159),22,540);p.icon('Hud.Knives',(190,17,303,158));p.text('Knife Index',(315,39,742,142),70)
  p.skin('ProgressPanel',(799,31,1774,156),22,970-22);p.text('Collection Progress',(844,53,1190,88),30)
  p.skin('ProgressTrack',(843,96,1280,125),7,410);p.text('12 / 24',(1290,93,1388,133),30)
  p.skin('Primary',(1423,58,1743,136),14,18);p.icon('Hud.FreeChest',(1418,44,1522,135));p.text('Claim Reward',(1519,65,1734,124),33)
  p.skin('Close',(1797,48,1897,147),15,19);p.text('X',(1812,62,1880,127),66)
  p.skin('NavPanel',(13,78,161,1054),18,135)
  for i,label in enumerate(['Shop','Index','Stats','Upgrades','FreeChest','Settings']):
   y=97+i*164;p.skin('NavTile',(25,y,147,y+143),12,16);p.icon('Hud.'+label,(33,y+10,139,y+94));p.text(label,(31,y+96,143,y+134),27)
  p.skin('TabsPanel',(168,170,1893,264),18,1700);p.skin('CardsPanel',(168,268,1892,1055),20,23)
  tx=[208,399,577,755,936,1130,1309,1494,1678];tw=[185,176,175,177,192,176,181,178,176]
  for i,label in enumerate(['All','Common','Rare','Epic','Legendary','Mythic','Godly','Celestial','Cosmic']):
   p.skin('Tab',(tx[i],186,tx[i]+tw[i],258),12,14);p.text(label,(tx[i]+9,197,tx[i]+tw[i]-8,250),31)
  xs=[203,479,756,1032,1308,1585];ys=[281,536,786];cw,ch=263,243
  names=['RustyShank','KitchenKnife','PocketKnife','HunterBlade','Switchblade','ThornDagger','Cleaver','Machete','Katana','BoneCarver','Reaper','GoldenDagger','InfernoFang','MagmaCleaver','DemonHorn','ZeusBolt','HaloBlade','VoidEdge'];hidden={8,9,10,11,12,15,16,17}
 for i,name in enumerate(names):
  x,y=xs[i%6],ys[i//6];p.skin('Card',(x,y,x+cw,y+ch),20,24)
  p.icon(('Silhouettes.' if i in hidden else 'Knives.')+name,(x+40,y+24,x+cw-35,y+ch-76))
  if phone:p.skin('NamePlate',(x+19,y+ch-71,x+cw-20,y+ch-14),14,18)
  p.text('???' if i in hidden else name,(x+23,y+ch-64,x+cw-21,y+ch-21),31 if phone else 25)
 return p.finish()

def hud(device):
 p=Proof('MainHud',device);phone=device=='phone'
 # Background is deliberately a plain gameplay placeholder: no original image
 # or cutout of a complete populated screen is pasted behind the UI proof.
 if phone:
  nav=[('Shop',(54,254,380,396)),('Index',(54,413,380,547)),('More',(54,558,380,694)),
       ('FreeChest',(2020,243,2363,372)),('Upgrades',(2020,382,2363,508)),('Spin',(2020,519,2363,649)),('Merchant',(2020,657,2363,787))]
  stats=[('Speed',(55,77,315,208),'16'),('Cash',(325,77,628,208),'2,450'),('Heat',(640,77,881,208),'23'),('MurdererChance',(1538,76,1893,209),'12%')]
  timer=(896,11,1505,228)
  for label,rect,value in stats:
   p.skin('StatTile',rect,20,24);x,y,r,b=rect;p.icon('Hud.'+label,(x+10,y+8,x+145,b-8));p.text(label.replace('MurdererChance','Murderer\nChance'),(x+144,y+17,r-11,y+66),31);p.text(value,(x+145,y+67,r-11,b-15),45)
  for label,rect in nav:
   p.skin('HudTile',rect,22,25);x,y,r,b=rect;p.icon('Hud.'+label,(x+24,y+6,x+166,b-6));p.text(label,(x+164,y+22,r-13,b-23),38)
  for label,rect in [('Settings',(2074,75,2214,195)),('More',(2223,75,2361,195))]:
   p.skin('IconButton',rect,18,22);p.icon('Hud.'+label,(rect[0]+17,rect[1]+16,rect[2]-15,rect[3]-14))
  bars=[('Health',(651,892,1194,1028),(699,967,1148,1009),'ProgressFill.Health'),('Energy',(1213,892,1755,1028),(1267,967,1712,1009),'ProgressFill.Energy')]
 else:
  nav=[('Shop',(32,84,314,319)),('Index',(32,322,314,522)),('More',(32,527,313,733)),('FreeChest',(1575,57,1894,259)),('Upgrades',(1619,266,1895,445)),('Spin',(1619,448,1896,641)),('Merchant',(1619,647,1896,826))]
  timer=(638,21,1284,214)
  for label,rect in nav:
   p.skin('HudTile',rect,23,28);x,y,r,b=rect;p.icon('Hud.'+label,(x+35,y+16,r-31,b-53));p.text(label,(x+16,b-64,r-15,b-18),43)
  for label,x,value in [('Speed',529,'10'),('Cash',749,'2,450'),('Heat',966,'20'),('MurdererChance',1184,'12%')]:
   rect=(x,707,x+210,918);p.skin('StatTile',rect,19,24);p.icon('Hud.'+label,(x+26,715,x+188,824));p.text(label.replace('MurdererChance','Murderer\nChance'),(x+15,824,x+197,871),30);p.text(value,(x+28,867,x+190,907),41,color=(255,223,38))
  bars=[('Health',(384,950,956,1044),(482,976,924,1017),'ProgressFill.Health'),('Energy',(969,949,1537,1044),(1070,976,1503,1017),'ProgressFill.Energy')]
 p.skin('Timer',timer,30,36);x,y,r,b=timer;p.text('MURDER ROUND IN',(x+44,y+33,r-41,y+100),49 if phone else 46);p.text('00:42',(x+100,y+100,r-90,b-31),88 if phone else 78,color=(255,220,41))
 for label,rect,fill,key in bars:
  p.skin('BarTile',rect,20,25);x,y,r,b=rect
  p.icon('Hud.Heat' if label=='Health' else 'Hud.Powers',(x+21,y+14,x+116,b-36));p.text(label,(x+115,y+16,x+285,y+68),34);p.text('100 / 100',(r-181,y+18,r-27,y+65),31)
  im=Image.open(OUT/LOOKUP[key]['File']).resize((fill[2]-fill[0],fill[3]-fill[1]),Image.Resampling.NEAREST);p.im.alpha_composite(im,(fill[0],fill[1]));p.elements.append({'Type':'Piece','Key':key,'Box':list(fill)})
 return p.finish()

def upgrades(device):
 p=Proof('Upgrades',device);phone=device=='phone'
 labels=['Speed','Vault Walls','Mounts / Slots','Health'];icons=['Speed','Upgrades','Shop','Heat']
 if phone:
  p.skin('TitlePlate',(420,14,1854,158),32,1100);p.text('UPGRADES',(475,37,1240,134),88)
  nav=['Upgrades','Knives','FreeChest','Powers','Spin','Settings']
  for i,label in enumerate(nav):
   y=102+i*159;p.skin('NavItem',(14,y,414,y+155),23,29);p.icon('Hud.'+label,(44,y+18,160,y+136));p.text(label,(173,y+43,395,y+117),43)
  rows=[(425,167,1849,382),(425,395,1849,612),(425,623,1849,846),(425,858,1849,1068)]
  for i,(label,rect) in enumerate(zip(labels,rows)):
   p.skin('ListRow',rect,22,26);x,y,r,b=rect;p.icon('Hud.'+icons[i],(x+30,y+24,x+264,b-23));p.text(label,(x+281,y+7,x+662,y+71),49);p.text(['Level 3 / 10','Level 2 / 10','Level 1 / 5','Level 2 / 10'][i],(x+295,y+78,x+568,y+115),32,color=(64,224,251))
   p.text(['Run faster around the map.','Stronger vault walls\nfor higher floors.','Increase your mount\ninventory slots.','More health to survive\nlonger.'][i],(x+283,y+121,x+652,b-27),29,color=(172,202,235),stroke=1)
   track=(1078,y+49,1451,y+121);p.skin('ProgressTrack',track,13,322)
   p.text(['+15% Speed','+10% Wall Health','+1 Mount Slot','+25 Health'][i],(1110,y+132,1424,b-31),32)
   button=(1470,y+13,1825,b-16);p.skin('Primary',button,21,27);p.text('Upgrade',(1546,y+24,1814,y+81),42);p.icon('Hud.Cash',(1495,y+65,1646,b-24));p.text(['1,200','2,500','5,000','3,000'][i],(1652,y+82,1801,b-38),42)
  p.skin('FloorCard',(1868,80,2384,1048),22,26);p.skin('SubHeader',(1868,80,2384,191),22,26);p.text('NEXT FLOOR UNLOCK',(1899,99,2365,171),39)
  p.icon('Cases.Epic',(1947,213,2328,426));p.text('Reach Floor 10',(1916,438,2354,510),48);p.text('Unlocks the next floor\nwith better rewards\nand stronger vaults!',(1917,516,2348,633),35,color=(168,202,237))
  for label,rect,value in [('Current Floor',(1902,654,2349,794),'3'),('Next Floor',(1904,861,2348,1008),'10')]:
   p.skin('FloorValue',rect,18,23);p.text(label,(rect[0]+20,rect[1]+13,rect[2]-20,rect[1]+63),35);p.text(value,(rect[0]+45,rect[1]+65,rect[2]-45,rect[3]-15),63,color=(70,225,251) if value=='10' else (250,251,255))
 else:
  p.skin('NavPanel',(13,43,1909,228),24,28)
  nav=['Shop','Index','More','Knives','Players','Powers','Rebirth','Stats','Upgrades','Spin','Powers','Merchant','FreeChest','Speed','Cash','Heat','Settings']
  for i,label in enumerate(nav):
   x=35+i*103;p.skin('NavItem',(x,49,x+103,214),9,13);p.icon('Hud.'+label,(x+9,64,x+94,160));p.text(label,(x+4,171,x+99,208),22)
  p.skin('RowsPanel',(13,242,1444,1031),24,29);rows=[(33,273,1429,446),(33,455,1429,632),(33,636,1429,813),(33,824,1429,1001)]
  for i,(label,rect) in enumerate(zip(labels,rows)):
   p.skin('ListRow',rect,19,24);x,y,r,b=rect;p.icon('Hud.'+icons[i],(x+30,y+20,x+194,b-16));p.text(label,(x+191,y+29,x+518,y+82),43);p.text(['Move faster around the map!','Increase your vault durability!','Unlock more mount slots!','Increase your max health!'][i],(x+195,y+103,x+518,b-23),25,color=(158,210,247))
   p.text(['Level 3 / 10','Level 2 / 10','Level 1 / 5','Level 4 / 10'][i],(548,y+21,741,y+73),34);p.skin('ProgressTrack',(555,y+81,908,y+130),11,316)
   p.icon('Hud.Cash',(932,y+26,1024,y+142));p.text(['500','750','1,000','600'][i],(1025,y+53,1132,y+108),44)
   p.skin('Primary',(1151,y+31,1406,y+140),20,24);p.text('Upgrade',(1173,y+54,1386,y+122),43)
  p.skin('FloorCard',(1450,242,1909,1031),24,29);p.text('Next Floor Unlock',(1484,288,1879,353),44);p.text('Upgrade your Vault Walls\nto Level 5 to unlock\nthe next floor!',(1490,368,1874,474),32,color=(169,209,248));p.icon('Hud.More',(1540,498,1833,735));p.text('Next Unlock at\nVault Walls\nLevel 5',(1495,786,1856,956),44)
 return p.finish()

def gallery():
 base=[r for r in RECORDS if r['Family']=='Reusable' and r['State']=='Normal']
 cols=5;rows=(len(base)+cols-1)//cols;im=Image.new('RGB',(1500,rows*185),(23,30,48));d=ImageDraw.Draw(im)
 for i,r in enumerate(base):
  x=i%cols*300;y=i//cols*185;d.text((x+9,y+7),r['Key'],fill='white')
  pic=Image.open(OUT/r['File']);pic.thumbnail((278,145));im.paste(pic,(x+(300-pic.width)//2,y+30),pic)
 im.save(OUT/'review/pieces.png')
 controls=[r for r in RECORDS if r.get('Base')]
 im=Image.new('RGB',(1500,((len(controls)+5)//6)*120),(23,30,48));d=ImageDraw.Draw(im)
 for i,r in enumerate(controls):
  x=i%6*250;y=i//6*120;d.text((x+5,y+4),r['Key'],fill='white');pic=Image.open(OUT/r['File']);pic.thumbnail((236,87));im.paste(pic,(x+(250-pic.width)//2,y+27),pic)
 im.save(OUT/'review/states.png')
 previews=Image.new('RGB',(1600,8*245),(23,30,48));d=ImageDraw.Draw(previews)
 for i,r in enumerate(LAYOUTS):
  name=r['Screen']+'-'+r['Device'];d.text((7,i*245+5),name+' | ORIGINAL / REBUILT (placeholder text + existing icons)',fill='white')
  for j,suffix in enumerate(('side-by-side','difference')):
   pic=Image.open(OUT/'verification'/(name+'-'+suffix+'.png'));pic.thumbnail((1170 if j==0 else 390,210));previews.paste(pic,(8 if j==0 else 1190,i*245+26))
 previews.save(OUT/'review/screen-comparisons.png')

def main():
 bases()
 for device in ('phone','desktop'):
  for builder in (powers,index,upgrades):builder(device)
 gallery()
 for r in RECORDS:
  im=Image.open(OUT/r['File']);assert list(im.size)==r['Size'];l,t,rr,b=r['SliceCenter'];assert 0<l<rr<im.width and 0<t<b<im.height,r['Key']
  assert im.getchannel('A').getextrema()[0]==0 or r['Key'].startswith('ProgressFill'),r['Key']
 doc={'Version':2,'StyleSplit':'Menu/window pieces only. MainHud contributes only existing icons; Claude HudSkin owns bright rounded HUD buttons. Timer/chance/readouts/world pills and knife labels remain plain outlined 2D text.',
      'Workflow':'Cut original mockups; restore covered interiors from visible original pixels; export at 2x. No redrawn borders.',
      'MockupCount':23,'Assets':RECORDS,'Layouts':LAYOUTS,
      'ComparisonLimit':'Whole-screen differences include placeholder text, independently rendered existing icons and plain gameplay background. State variants are derived because those states are absent from the static originals.'}
 (OUT/'manifest.json').write_text(json.dumps(doc,indent=2)+'\n')
 (OUT/'verification/layouts.json').write_text(json.dumps(LAYOUTS,indent=2)+'\n')
 stats={'Assets':len(RECORDS),'SourceCutouts':sum('Base' not in r for r in RECORDS),'DerivedStatesOrColours':sum('Base' in r for r in RECORDS),
        'RetainedSourcePixels':sum(r['RetainedSourcePixels'] for r in RECORDS),'ChangedRetainedPixels':sum(r['ChangedRetainedPixels'] or 0 for r in RECORDS),
        'Screens':[{k:v for k,v in r.items() if k!='Layout'} for r in LAYOUTS]}
 (OUT/'verification/summary.json').write_text(json.dumps(stats,indent=2)+'\n')
 print(json.dumps({k:v for k,v in stats.items() if k!='Screens'}))

if __name__=='__main__':main()
