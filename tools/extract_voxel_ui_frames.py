"""Crop the original ImageGen pixels into reusable text-free nine-slice skins.

The user explicitly requested crop-based pixel comparison. Border pixels are
retained verbatim; only the interior formerly occupied by reference copy/icons
is replaced with a blank colour sampled from that same reference. No AI repaint.
"""
import json, math, shutil, hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageChops

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'assets/voxel-ui';OUT=ROOT/'assets/visual-expansion'
LOG=json.loads((OUT/'generation-log.json').read_text())
# Regions measured against the 2400x1080 review canvas, then mapped to original
# generation resolution. Keeping the original pixels avoids a resampling pass.
REGIONS={
 'PanelBody':('Powers',(1907,141,2384,1056),(26,28), (1947,960)),
 'HeaderBar':('KnifeIndex',(29,19,1009,211),(44,36), (975,117)),
 'Card':('Powers',(306,145,700,607),(30,32),(364,236)),
 'PrimaryButton':('KnifeIndex',(1900,57,2186,171),(16,14),(1938,110)),
 'SecondaryButton':('Powers',(508,514,686,591),(14,12),(535,553)),
 'Tab':('KnifeIndex',(317,225,573,329),(28,24),(348,275)),
 'ActiveTab':('KnifeIndex',(50,222,316,330),(32,24),(93,277)),
 'CloseButton':('Powers',(11,3,159,137),(23,25),(42,64)),
 'OddsStrip':('KnifeIndex',(55,604,407,659),(18,10),(82,630)),
}

def export_frames():
 catalog=json.loads((ART/'catalog.json').read_text())
 records=[];audit=OUT/'pixel-audit';audit.mkdir(exist_ok=True)
 for a in catalog['Assets']:
  if a['Group']!='Frames':continue
  screen,region,inset,sample=REGIONS[a['Name']]
  src=Path(LOG[f'Mockups.{screen}.Phone']['Source'])
  original=Image.open(src).convert('RGBA')
  # Persist originals in the project; no deliverable depends on a Codex cache.
  saved=OUT/'references/originals'/f'{screen}-phone.png';saved.parent.mkdir(parents=True,exist_ok=True)
  if not saved.exists():shutil.copyfile(src,saved)
  sx,sy=original.width/2400,original.height/1080
  x,y,r,b=region
  native=(math.floor(x*sx),math.floor(y*sy),math.ceil(r*sx),math.ceil(b*sy))
  crop=original.crop(native)
  original_region=audit/(a['Name']+'-source-crop.png');crop.save(original_region)
  frame_reference=ART/'references/Frames-v4'/(a['Name']+'.png')
  frame_reference.parent.mkdir(parents=True,exist_ok=True);crop.save(frame_reference)
  ix,iy=math.ceil(inset[0]*sx),math.ceil(inset[1]*sy)
  w,h=crop.size
  center=[ix,iy,w-ix,h-iy]
  background=original.getpixel((round(sample[0]*sx),round(sample[1]*sy)))
  retained=Image.new('L',(w,h),255)
  ImageDraw.Draw(retained).rectangle((center[0],center[1],center[2]-1,center[3]-1),fill=0)
  # Shapes in neighbouring controls overlap the crop's bounding rectangle.
  # Retain only the rails/cube areas belonging to this component, then check
  # every retained source byte. Sampled interiors never contain baked copy.
  if a['Name'] in ('Card','HeaderBar','PanelBody','OddsStrip'):
   retained=Image.new('L',(w,h),0);d=ImageDraw.Draw(retained)
   rails={'Card':(18,20,12,43), 'HeaderBar':(18,20,10,44),
          'PanelBody':(20,8,8,28), 'OddsStrip':(12,6,6,18)}
   side,top,bottom,corner=rails[a['Name']]
   side=math.ceil(side*sx);top=math.ceil(top*sy);bottom=math.ceil(bottom*sy)
   cx,cy=math.ceil(corner*sx),math.ceil(corner*sy)
   if a['Name']=='PanelBody':cx=math.ceil(44*sx)
   for box in ((0,0,w-1,top-1),(0,h-bottom,w-1,h-1),(0,0,side-1,h-1),(w-side,0,w-1,h-1),
               (0,0,cx-1,cy-1),(w-cx,0,w-1,cy-1),(0,h-cy,cx-1,h-1),(w-cx,h-cy,w-1,h-1)):
    d.rectangle(box,fill=255)
   if a['Name']=='Card':
    # Green/blue action button faces are not part of the card's corner cubes.
    for py in range(h-cy,h-bottom):
     for px in list(range(cx))+list(range(w-cx,w)):
      red,green,blue,_=crop.getpixel((px,py))
      if (green>80 and green>blue*1.25) or (blue>130 and blue>green*1.5):
       retained.putpixel((px,py),0)
   if a['Name']=='HeaderBar':
    # Preserve the cyan lower rail even where the reference book's shadow
    # overlaps its rectangular band. The book itself is a separate HUD icon.
    for py in range(h-math.ceil(24*sy),h-bottom):
     for px in range(cx,w-cx):
      red,green,blue,_=crop.getpixel((px,py))
      if green>80 and green>red*1.2 and green*.85<blue<green*1.5:
       retained.putpixel((px,py),255)
  clean=Image.new('RGBA',(w,h),background)
  clean.paste(crop,(0,0),retained)
  recovery=None
  if a['Name']=='SecondaryButton':
   # The source's parent card occludes the button's lower-right corner. The
   # unobstructed lower-left corner supplies the same stepped silhouette.
   cw,ch=math.ceil(24*sx),math.ceil(22*sy)
   tile=clean.crop((0,h-ch,cw,h)).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   clean.paste(tile,(w-cw,h-ch))
   ImageDraw.Draw(retained).rectangle((w-cw,h-ch,w-1,h-1),fill=0)
   assert clean.crop((w-cw,h-ch,w,h)).tobytes()==tile.tobytes()
   recovery=dict(SourceTile=[0,h-ch,cw,h],Destination=[w-cw,h-ch,w,h],
                 Transform='Horizontal mirror of opposite lower corner',ChangedMappedPixels=0,
                 Reason='Remove occluding parent-card cube from an independent button asset')
  pad=4
  final=Image.new('RGBA',(w+pad*2,h+pad*2))
  final.alpha_composite(clean,(pad,pad))
  path=ART/a['File']
  old=ART/'withdrawn-v3'/a['File'];old.parent.mkdir(parents=True,exist_ok=True)
  if not old.exists():shutil.copyfile(path,old)
  final.save(path,optimize=True)
  # Audit the two-dimensional retained mask, not a visual similarity score.
  diff=ImageChops.difference(crop,clean)
  maximum=max(channel.getextrema()[1] for channel in diff.split())
  for channel in diff.split():
   assert ImageChops.multiply(channel,retained).getbbox() is None,a['Name']
  retained_pixels=retained.histogram()[255]
  # A matched crop at native resolution makes the promise directly inspectable.
  panel=Image.new('RGB',(w*3,h),(15,24,40))
  panel.paste(crop.convert('RGB'),(0,0));panel.paste(clean.convert('RGB'),(w,0))
  overlay=Image.new('RGB',(w,h),(0,0,0))
  channels=[ImageChops.multiply(c,retained) for c in diff.split()[:3]]
  overlay=Image.merge('RGB',tuple(channels))
  panel.paste(overlay,(w*2,0));panel.save(audit/(a['Name']+'-comparison.png'))
  rect=[n+pad for n in center]
  a.update(Size=list(final.size),SliceCenter=rect,RecommendedSliceScale=1,
           Reference=str(frame_reference.relative_to(ART)).replace('\\','/'),
           Production='Original ImageGen pixels cropped at native resolution; blank sampled interior',
           OriginalScreen=f'{screen}-phone',SourceRegion=list(native),
           SourcePixelsVerified=retained_pixels,
           Prompt=next(j['Prompt'] for j in json.loads((OUT/'jobs.json').read_text())['Jobs'] if j['Id']==f'Mockups.{screen}.Phone'))
  records.append(dict(Id=a['Id'],Source='references/originals/'+saved.name,
     NativeSourceSize=list(original.size),NativeSourceRegion=list(native),
     Size=a['Size'],SliceCenter=rect,Background=list(background),
     RetainedPixels=retained_pixels,ChangedRetainedPixels=0,MaximumRetainedChannelError=0,
     Centre='Blank colour sampled from the original; source text/icons intentionally excluded',
     RecoveredCorner=recovery,
     Alpha='Four-pixel transparent export padding; crop itself retains original opaque pixels',
     Comparison='pixel-audit/'+a['Name']+'-comparison.png'))
 catalog['Version']=4
 (ART/'catalog.json').write_text(json.dumps(catalog,indent=2))
 (audit/'frame-pixel-validation.json').write_text(json.dumps(dict(Version=4,
    Method='Byte comparison of all retained original RGBA frame pixels. Comparison columns: original crop, text-free skin, retained-border difference (black means exact).',
    Assets=records,TotalRetainedPixels=sum(r['RetainedPixels'] for r in records),
    ChangedRetainedPixels=0,WholeScreenPixelIdentity='Original mockups are preserved; native live text and model-derived icon proof layouts are not pixel-identical screen renders.'),indent=2))
 print('Extracted',len(records),'original frame crops;',sum(r['RetainedPixels'] for r in records),'border pixels exactly preserved.')

if __name__=='__main__':export_frames()
