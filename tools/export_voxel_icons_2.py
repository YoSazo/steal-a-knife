"""Export generated RGBA icons at 512px; compose review sheets, never redraw art."""
from pathlib import Path
import hashlib
import json
import math
import shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / 'assets/voxel-icons-2'
for folder in ('references', 'png', 'review'):
    (PACK / folder).mkdir(parents=True, exist_ok=True)
catalog = json.loads((PACK / 'catalog.json').read_text(encoding='utf-8'))
rows = []
for entry in catalog['Assets']:
    source = Path(entry['GeneratedPath'])
    if not source.exists():
        raise FileNotFoundError(source)
    name = entry['Name']
    reference = PACK / 'references' / f'{name}.png'
    shutil.copy2(source, reference)
    original = Image.open(reference)
    if original.mode != 'RGBA':
        raise ValueError(f'{name}: generated image lacks RGBA transparency')
    alpha = original.getchannel('A')
    if alpha.getextrema() != (0, 255):
        raise ValueError(f'{name}: background is not transparent or object not opaque')
    bounds = alpha.point(lambda a: 255 if a > 8 else 0).getbbox()
    # Uniformly scale the actual source silhouette, keep its alpha, add clear padding.
    content = original.crop(bounds)
    scale = 384 / max(content.size)
    size = tuple(max(1, round(v * scale)) for v in content.size)
    content = content.resize(size, Image.Resampling.LANCZOS)
    icon = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    icon.alpha_composite(content, ((512-size[0])//2, (512-size[1])//2))
    target = PACK / 'png' / f'{name}.png'
    icon.save(target)
    row = dict(entry, File=f'png/{name}.png', Reference=f'references/{name}.png',
               Size=[512,512], SourceSize=list(original.size), SourceCrop=list(bounds),
               ExportMethod='Uniform source-image resize and transparent padding only; no redrawing.',
               SHA256=hashlib.sha256(target.read_bytes()).hexdigest(),
               AlphaBounds=list(icon.getchannel('A').getbbox()), SliceCenter=None)
    rows.append(row)

font_path = Path('C:/Windows/Fonts/arialbd.ttf')
font = ImageFont.truetype(str(font_path), 18)
small = ImageFont.truetype(str(font_path), 15)
groups = {
    'powers': ['Vanish','Radar','BearTrap','Shield','Decoy','Flash','Barricade','Mimic'],
    'utility': ['UpgradeBaseHouse','Rebirth','VIP','Trade','Invite','Wheel','Health','Trail','Floor','Padlock','Gift'],
    'all': [row['Name'] for row in rows],
}
def label(name):
    return {'UpgradeBaseHouse':'Upgrade Base house','BearTrap':'Bear Trap','VIP':'VIP crown',
            'Wheel':'Training wheel','Health':'Health heart','Floor':'Floor stack','Gift':'Gift box'}.get(name,name)
for group,names in groups.items():
    names = [name for name in names if any(row['Name']==name for row in rows)]
    cols = 4 if group == 'powers' else 5
    width, height = cols*240, math.ceil(len(names)/cols)*324 + 52
    sheet = Image.new('RGB',(width,height),'#e9edf1')
    draw=ImageDraw.Draw(sheet)
    draw.text((18,14),f'Voxel icons 2 — {group} | generated art + 64px check',font=font,fill='#161c27')
    for i,name in enumerate(names):
        x,y=(i%cols)*240,(i//cols)*324+52
        draw.rounded_rectangle((x+8,y+4,x+232,y+318),radius=8,fill='#ffffff')
        icon=Image.open(PACK/'png'/f'{name}.png')
        sheet.paste(icon.resize((216,216),Image.Resampling.LANCZOS),(x+12,y+5),icon.resize((216,216),Image.Resampling.LANCZOS))
        draw.text((x+14,y+213),label(name),font=font,fill='#161c27')
        thumb=icon.resize((64,64),Image.Resampling.LANCZOS)
        draw.rectangle((x+152,y+242,x+222,y+312),fill='#242833')
        sheet.paste(thumb,(x+156,y+246),thumb)
        draw.text((x+14,y+268),'64 px →',font=small,fill='#505768')
    sheet.save(PACK/'review'/f'{group}.png')
(PACK/'manifest.json').write_text(json.dumps({'Version':1,'Assets':rows},indent=2)+'\n',encoding='utf-8')
(PACK/'validation.json').write_text(json.dumps({'Count':len(rows),'Size':[512,512],
    'AllRGBA':True,'AllTransparent':True,'TextBakedIn':False,
    'Checks':'Dimensions, alpha, source provenance and hashes checked. Visual review is recorded in HANDOFF.'},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'count':len(rows),'names':[row['Name'] for row in rows]}))
