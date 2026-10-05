"""Create reference/model comparisons, retaining the individual full-resolution artifacts."""
import json
from pathlib import Path
from PIL import Image,ImageOps,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/toy-redesign'
data=json.loads((OUT/'geometry.json').read_text())['Designs']
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
for group,cols in [('knives',6),('lairs',4),('shops',2),('lucky',4),('plaza',2)]:
    designs=[d for d in data if d['Group']==group]
    w,h=320,346
    canvas=Image.new('RGB',(w*cols,h*((len(designs)+cols-1)//cols)),'#e8ebef');draw=ImageDraw.Draw(canvas)
    for i,d in enumerate(designs):
        x=i%cols*w;y=i//cols*h
        im=ImageOps.contain(Image.open(OUT/'previews'/f"{d['Name']}.png").convert('RGB'),(w,h-34))
        canvas.paste(im,(x+(w-im.width)//2,y))
        draw.text((x+12,y+h-28),d['Name'].replace('Lair','').replace('Shop','').replace('Lucky',''),font=font,fill='#162637')
    canvas.save(OUT/f'{group}-gallery.jpg')
    # Full-size side-by-side proof sheets: reference left, native blocks right.
    width=1000;rowh=460
    comparison=Image.new('RGB',(width,rowh*len(designs)),'#e8ebef');draw=ImageDraw.Draw(comparison)
    refs=json.loads((OUT/('knife-references.json' if group=='knives' else 'landmark-references.json')).read_text())['references']
    for i,d in enumerate(designs):
        refname=d['Name']
        if group=='lairs':refname=refname[4:]
        if group=='shops':refname=refname[4:]
        if group=='lucky':refname=refname[5:]
        if refname=='EventBoardDecor':refname='EventBoard'
        r=next(r for r in refs if r['name']==refname)
        refpath=OUT/'references'/f"{'knife' if group=='knives' else group}-{refname}.png"
        for col,path in enumerate([refpath,OUT/'previews'/f"{d['Name']}.png"]):
            im=ImageOps.contain(Image.open(path).convert('RGB'),(490,420));comparison.paste(im,(col*500+(500-im.width)//2,i*rowh))
        draw.text((14,i*rowh+425),f"{refname} / generated reference",font=font,fill='#162637')
        draw.text((514,i*rowh+425),'Native cuboid reconstruction',font=font,fill='#162637')
    comparison.save(OUT/f'{group}-comparison.jpg',quality=92)
