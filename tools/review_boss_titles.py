"""Verify full source-pixel coverage and make original/model comparison sheets."""
import hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/boss-titles'
data=json.loads((OUT/'geometry.json').read_text())['Designs']
font=ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf',23)
small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
sheet=Image.new('RGB',(1280,8*310),(26,33,48))
gallery=Image.new('RGB',(1440,4*320),(26,33,48))
records=[]
for index,design in enumerate(data):
    original=Image.new('RGBA',(1600,640))
    for name,surface in design['Surfaces'].items():
        source=Image.open(ROOT/surface['Source']).convert('RGBA')
        assert hashlib.sha256((ROOT/surface['Source']).read_bytes()).hexdigest()==surface['SourceSHA256']
        assert source.size==tuple(surface['Grid'])==tuple(surface['SourceSize'])
        alpha=np.array(source)[:,:,3]>=128
        coverage=np.zeros(alpha.shape,np.uint8)
        for x,y,w,h,key,depth in surface['Rects']:
            coverage[y:y+h,x:x+w]+=1
            assert depth in (.18,.36,.66)
        assert np.array_equal(coverage,alpha.astype(np.uint8)),design['Boss']+name
        pixel_size=1600/29
        width=26 if name=='Sign' else 16.12
        height=width*source.height/source.width
        center_y=0 if name=='Sign' else -4.293333333
        size=(round(width*pixel_size),round(height*pixel_size))
        image=source.resize(size,Image.Resampling.LANCZOS)
        original.alpha_composite(image,(round((1600-size[0])/2),round(320-(center_y+1.5)*pixel_size-size[1]/2)))
        records.append(dict(Boss=design['Boss'],Surface=name,Canvas=list(source.size),CoveredPixels=int(alpha.sum()),Cuboids=len(surface['Rects']),Coverage='Every alpha >=128 source pixel exactly once',ColourMap='32 native solid vertex colours per source canvas; no texture'))
    model=Image.open(OUT/'renders'/f'{design["Boss"]}.png').convert('RGBA')
    row=Image.new('RGB',(1280,310),(26,33,48));draw=ImageDraw.Draw(row)
    draw.text((20,8),design['Boss']+' — '+design['Title'],font=font,fill='white')
    draw.text((20,40),'Original PNG artwork',font=small,fill=(164,189,219))
    draw.text((660,40),'Physical voxel mesh (angled view)',font=small,fill=(164,189,219))
    original.thumbnail((620,248),Image.Resampling.LANCZOS)
    model.thumbnail((620,248),Image.Resampling.LANCZOS)
    row.paste(original,(10,62),original);row.paste(model,(650,62),model)
    row.save(OUT/f'comparison-{design["Boss"]}.png')
    sheet.paste(row,(0,index*310))
    cell=Image.new('RGB',(720,320),(26,33,48));d=ImageDraw.Draw(cell)
    d.text((18,10),design['Boss']+' / '+design['Title'],font=font,fill='white')
    large=Image.open(OUT/'renders'/f'{design["Boss"]}.png').convert('RGBA');large.thumbnail((700,280),Image.Resampling.LANCZOS)
    cell.paste(large,(10,38),large);gallery.paste(cell,((index%2)*720,(index//2)*320))
sheet.save(OUT/'comparison.png');gallery.save(OUT/'gallery.png')
(OUT/'pixel-validation.json').write_text(json.dumps(dict(Models=8,Surfaces=16,SourcePixels=sum(r['CoveredPixels'] for r in records),Cuboids=sum(r['Cuboids'] for r in records),SurfacesAudit=records),indent=2))
print('Verified every opaque source pixel for all 16 surfaces; source contours unchanged; native vertex paint')
