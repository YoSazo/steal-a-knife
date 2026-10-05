"""Resize/pad generated wheel layers and compose review-only usage examples."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/lucky-wheel-art'
for directory in ('references','png','review'):
    (PACK/directory).mkdir(parents=True,exist_ok=True)
catalog = json.loads((PACK/'catalog.json').read_text(encoding='utf-8'))
records=[]
for entry in catalog['Assets']:
    name=entry['Name']
    original=Path(entry['GeneratedPath'])
    reference=PACK/'references'/f'{name}.png'
    shutil.copy2(original,reference)
    source=Image.open(reference)
    assert source.mode=='RGBA', f'{name} lacks generated alpha'
    assert source.getchannel('A').getextrema()==(0,255),f'{name} lacks transparency'
    crop=source.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
    content=source.crop(crop)
    longest=448 if name=='WheelRim' else 384
    scale=longest/max(content.size)
    size=tuple(round(v*scale) for v in content.size)
    content=content.resize(size,Image.Resampling.LANCZOS)
    icon=Image.new('RGBA',(512,512),(0,0,0,0))
    icon.alpha_composite(content,((512-size[0])//2,(512-size[1])//2))
    output=PACK/'png'/f'{name}.png'
    icon.save(output)
    alpha=np.asarray(icon.getchannel('A'))
    yy,xx=np.indices(alpha.shape)
    radius=np.hypot(xx-255.5,yy-255.5)
    rec=dict(entry,File=f'png/{name}.png',Reference=f'references/{name}.png',
        Size=[512,512],Center=[256,256],SourceSize=list(source.size),SourceCrop=list(crop),
        VisibleBounds=list(icon.getchannel('A').getbbox()),SliceCenter=None,
        SHA256=hashlib.sha256(output.read_bytes()).hexdigest(),
        ExportMethod='Uniform resize and transparent padding of generated source; no redrawing.')
    if name=='WheelRim':
        assert alpha[256,256]==0,'Rim has an opaque centre'
        # Generated alpha and resampling can leave 1/255-alpha edge dust.
        # Use a documented <=1 transparency threshold for hole geometry.
        rec['HoleAlphaThreshold']=1
        rec['ClearHoleRadius']=float(radius[alpha>1].min())
        region=Image.fromarray((alpha>1).astype(np.uint8)).copy()
        ImageDraw.floodfill(region,(256,256),2)
        hole=np.asarray(region)==2
        rec['MaximumHoleRadius']=float(radius[hole].max())
        rec['MaxHoleAlpha']=int(alpha[hole].max())
        rec['OpeningTopAtCenter']=int(np.where(hole[:,256])[0].min())
        rec['RecommendedPointerTip']=[256,rec['OpeningTopAtCenter']+10]
        rec['RecommendedWedgeRadius']=math.ceil(rec['MaximumHoleRadius'])+3
        assert rec['MaximumHoleRadius']<210,'Rim hole leaks into exterior transparency'
        rec['OuterRadius']=224
        rec['CircularityRatio']=round(min(size)/max(size),4)
        assert rec['ClearHoleRadius']>140,'Rim does not have a sufficiently large transparent hole'
        assert rec['CircularityRatio']>0.94,'Rim is too elliptical'
    elif name=='WheelPointer':
        ys,xs=np.where(alpha>16)
        bottom=ys.max()
        tip_x=float(xs[ys>=bottom-2].mean())
        rec['Tip']=[round(tip_x,2),int(bottom)]
        assert abs(tip_x-256)<28,'Pointer does not point straight downward'
    records.append(rec)

font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',22)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',17)
sheet=Image.new('RGB',(1200,458),'#e9edf1')
draw=ImageDraw.Draw(sheet)
draw.text((18,12),'Lucky Wheel — transparent voxel layers',font=font,fill='#151c28')
for i,rec in enumerate(records):
    x=i*400
    draw.rectangle((x+8,48,x+392,430),fill='#272c38')
    icon=Image.open(PACK/rec['File'])
    thumb=icon.resize((320,320),Image.Resampling.LANCZOS)
    sheet.paste(thumb,(x+40,52),thumb)
    draw.text((x+24,374),rec['Name']+' | 512 x 512',font=font,fill='white')
    draw.text((x+24,404),'No baked text / no prize wedges',font=small,fill='#bbc7db')
sheet.save(PACK/'review/gallery.png')

# Only these review examples draw coloured wedges. Exported assets contain none.
rim=next(rec for rec in records if rec['Name']=='WheelRim')
palette=['#ffce25','#ff8152','#fc67b1','#a16cef','#527aff','#29cbe9','#57df68','#b5f365','#ef6957','#63e0ca','#c39afa']
examples=Image.new('RGB',(1500,650),'#e9edf1')
draw=ImageDraw.Draw(examples)
draw.text((18,12),'Review only: same three PNGs with different dynamic prize counts',font=font,fill='#151c28')
for index,count in enumerate((5,8,11)):
    wheel=Image.new('RGBA',(512,512),(0,0,0,0))
    wedges=ImageDraw.Draw(wheel)
    r=rim['RecommendedWedgeRadius']
    box=(256-r,256-r,256+r,256+r)
    for wedge in range(count):
        start=-90-180/count+wedge*360/count
        wedges.pieslice(box,start,start+360/count,fill=palette[wedge%len(palette)],outline='#141a29',width=2)
    wheel.alpha_composite(Image.open(PACK/'png/WheelRim.png'))
    hub=Image.open(PACK/'png/WheelHub.png').resize((112,112),Image.Resampling.LANCZOS)
    wheel.alpha_composite(hub,(200,200))
    panel=Image.new('RGBA',(500,548),'#272c38')
    panel.alpha_composite(wheel.resize((480,480),Image.Resampling.LANCZOS),(10,52))
    pointer=Image.open(PACK/'png/WheelPointer.png').resize((96,96),Image.Resampling.LANCZOS)
    pointer_rec=next(rec for rec in records if rec['Name']=='WheelPointer')
    target=rim['RecommendedPointerTip']
    tip=pointer_rec['Tip']
    pointer_x=round(10+target[0]*480/512-tip[0]*96/512)
    pointer_y=round(52+target[1]*480/512-tip[1]*96/512)
    panel.alpha_composite(pointer,(pointer_x,pointer_y))
    examples.paste(panel.convert('RGB'),(index*500,48))
    draw.text((index*500+18,610),f'{count} prizes — identical artwork',font=font,fill='#151c28')
examples.save(PACK/'review/dynamic-wedges.png')
(PACK/'manifest.json').write_text(json.dumps({'Version':1,'Assets':records},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'Count':len(records),'Rim':rim}))
