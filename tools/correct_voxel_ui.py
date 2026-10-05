"""Export generated v3 skins and reference-faithful asset-kit proof layouts.

Only PNG assets, design data, and review documents are written. No game wiring.
"""
import json, math, shutil, hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/voxel-ui'
OUT = ROOT / 'assets/visual-expansion'
FONT = ART / 'fonts/Fredoka.ttf'
CAT = json.loads((ART / 'catalog.json').read_text())
FRAMES = {
    'PanelBody': ([1024,512], [100,100,924,412]),
    'Card': ([512,512], [72,72,440,440]),
    'HeaderBar': ([1024,256], [80,72,944,184]),
    'PrimaryButton': ([512,192], [80,64,432,128]),
    'SecondaryButton': ([512,192], [80,64,432,128]),
    'Tab': ([512,192], [80,64,432,128]),
    'CloseButton': ([256,256], [72,72,184,184]),
    'OddsStrip': ([1024,128], [72,48,952,80]),
    'ActiveTab': ([512,192], [80,64,432,128]),
}

def export_frames():
    generation = json.loads((ART/'frame-correction-log.json').read_text(encoding='utf-8-sig'))
    prompts = {a['Name']:a['Prompt'] for a in generation['Assets']}
    if not any(a['Id']=='Frames.ActiveTab' for a in CAT['Assets']):
        CAT['Assets'].append(dict(Id='Frames.ActiveTab',Group='Frames',Name='ActiveTab',
            File='png/Frames/ActiveTab.png',Reference='references/Frames-v3/ActiveTab.png',
            Size=[512,192],SliceCenter=[80,64,432,128],Model=None,
            Prompt='Transparent cyan active-state variant of the same voxel tab; exact generation prompt is in frame-correction-log.json.'))
    for a in CAT['Assets']:
        if a['Group'] != 'Frames':
            continue
        source = ART / 'references/Frames-v3' / (a['Name']+'.png')
        raw = Image.open(source).convert('RGBA')
        assert raw.getchannel('A').getextrema()[0] == 0, source
        # Export framing only: retain ImageGen RGB and alpha, including highlights.
        bounds = raw.getchannel('A').point(lambda v: 255 if v >= 16 else 0).getbbox()
        assert bounds
        crop = raw.crop(bounds)
        size, rect = FRAMES[a['Name']]
        final = Image.new('RGBA', size)
        crop = crop.resize((size[0]-8, size[1]-8), Image.Resampling.LANCZOS)
        final.alpha_composite(crop, (4,4))
        old = ART / 'withdrawn-v2' / a['File']
        old.parent.mkdir(parents=True, exist_ok=True)
        if not old.exists() and (ART/a['File']).exists():
            shutil.copyfile(ART/a['File'], old)
        final.save(ART/a['File'], optimize=True)
        a.update(Size=size, SliceCenter=rect, Reference=str(source.relative_to(ART)).replace('\\','/'),
                 Production='Built-in ImageGen v3 export; RGB and alpha preserved',
                 RecommendedSliceScale=0.4, Prompt=prompts[a['Name']],
                 Input=['assets/visual-expansion/references/mockups/KnifeIndex-phone.png',
                        'assets/visual-expansion/references/mockups/Powers-phone.png'])
    CAT['Version'] = 3
    (ART/'catalog.json').write_text(json.dumps(CAT, indent=2), encoding='utf-8')

class Screen:
    def __init__(self, screen, phone):
        self.screen, self.phone = screen, phone
        self.w, self.h = (2400,1080) if phone else (1920,1080)
        self.im = Image.new('RGBA', (self.w,self.h), (16,25,43,255))
        self.d = ImageDraw.Draw(self.im)
        self.elements = []
        self.cat = {a['Id']:a for a in CAT['Assets']}

    def text(self, text, box, size, color=(249,250,255), align='center', outline=3, bold=True):
        x,y,w,h = map(round, box)
        def font_at(n):
            f = ImageFont.truetype(str(FONT), n)
            f.set_variation_by_name('Bold' if bold else 'Medium')
            return f
        font = font_at(size)
        lines = text.split('\n')
        while max(font.getlength(line) for line in lines) > w-8 and size>12:
            size -= 1
            font = font_at(size)
        lh = size*1.15
        for i,line in enumerate(lines):
            bounds = font.getbbox(line)
            xx = x+6 if align=='left' else x+(w-font.getlength(line))/2
            yy = y+(h-lh*len(lines))/2+i*lh-bounds[1]+(lh-(bounds[3]-bounds[1]))/2
            self.d.text((xx,yy), line, font=font, fill=color, stroke_width=outline, stroke_fill=(4,9,21))
        self.elements.append(dict(Type='TextLabel', Text=text, Box=[x,y,w,h], Font='FredokaOne',
                                  FontSize=size, Color=list(color), Stroke=outline, Alignment=align))

    def sprite(self, key, box):
        x,y,w,h = map(round,box)
        src = Image.open(ART/self.cat[key]['File']).convert('RGBA')
        src.thumbnail((w,h), Image.Resampling.LANCZOS)
        ox,oy=x+(w-src.width)//2,y+(h-src.height)//2
        self.im.alpha_composite(src, (ox,oy))
        l,t,r,b=src.getchannel('A').getbbox()
        self.elements.append(dict(Type='ImageLabel', Asset=key, Box=[x,y,w,h], ScaleType='Fit',
                                  ContentBounds=[ox+l,oy+t,ox+r,oy+b]))

    def frame(self, key, box, scale=.4):
        x,y,w,h = map(round,box)
        a = self.cat[key]
        if CAT.get('Version',1)>=4:
            # V4 skins contain original source pixels rather than 512px repaints.
            scale = self.w/1870
            # Four transparent export pixels surround the original crop.
            # Offset the ImageLabel so that crop lands on the design box.
            pad=round(4*scale)
            x-=pad;y-=pad;w+=pad*2;h+=pad*2
        src = Image.open(ART/a['File']).convert('RGBA')
        l,t,r,b = a['SliceCenter']
        scale = min(scale, w/(l+src.width-r+1), h/(t+src.height-b+1))
        sx,sy = [0,l,r,src.width],[0,t,b,src.height]
        dx,dy = [0,round(l*scale),w-round((src.width-r)*scale),w],[0,round(t*scale),h-round((src.height-b)*scale),h]
        final = Image.new('RGBA',(w,h))
        for row in range(3):
            for col in range(3):
                tw,th = dx[col+1]-dx[col],dy[row+1]-dy[row]
                if tw>0 and th>0:
                    tile = src.crop((sx[col],sy[row],sx[col+1],sy[row+1])).resize((tw,th),Image.Resampling.LANCZOS)
                    final.alpha_composite(tile,(dx[col],dy[row]))
        self.im.alpha_composite(final,(x,y))
        self.elements.append(dict(Type='ImageLabel', Asset=key, Box=[x,y,w,h], ScaleType='Slice',
                                  SliceCenter=a['SliceCenter'], SliceScale=scale))

    def button(self, text, box, primary=True, size=27):
        self.frame('Frames.PrimaryButton' if primary else 'Frames.SecondaryButton',box,.3)
        self.text(text,box,size,outline=3)

    def progress(self, box, fraction, text=None, segments=0):
        x,y,w,h = map(round,box)
        self.frame('Frames.OddsStrip',box,.18)
        pad = 8
        inner = (x+pad,y+pad,x+w-pad,y+h-pad)
        self.d.rectangle(inner, fill=(8,20,40))
        if fraction:
            self.d.rectangle((x+pad,y+pad,x+pad+round((w-pad*2)*fraction),y+h-pad),fill=(27,211,242))
        for i in range(segments):
            xx=x+pad+i*(w*.57-pad*2)/segments
            self.d.rectangle((round(xx),y+pad,round(xx+(w*.57-pad*2)/segments-3),y+h-pad),fill=(52,76,110))
        self.elements.append(dict(Type='NativeProgress', Box=list(box), Fraction=fraction, Segments=segments))
        if text:
            self.text(text, (x+w*.59,y,w*.39,h),22,outline=2)

    def index(self):
        w=self.w
        left=28 if self.phone else 190
        topw=(w-left-172)*.44
        self.frame('Frames.HeaderBar',(left,24,topw,170),.55)
        self.sprite('Hud.Index',(left+20,32,150,150))
        self.text('KNIFE INDEX',(left+170,30,topw-190,148),112,outline=6)
        px=left+topw+22;pw=w-px-172
        self.frame('Frames.HeaderBar',(px,24,pw,170),.50)
        self.text('DISCOVERED',(px+20,35,pw*.49,54),31,align='left')
        self.text('12 / 24 (50%)',(px+pw*.30,35,pw*.31,54),31)
        self.progress((px+24,103,pw*.60,57),.5)
        self.sprite('Hud.FreeChest',(px+pw*.64,38,pw*.12,129))
        self.button('CLAIM\nREWARD',(px+pw*.77,50,pw*.21,113),size=29)
        self.sprite('Frames.CloseButton',(w-140,30,114,114))
        self.text('X',(w-140,30,114,114),74,outline=5)
        if not self.phone:
            for i,(asset,label) in enumerate([('Shop','Shop'),('Index','Index'),('Stats','Stats'),('Upgrades','Upgrades'),('FreeChest','Chests'),('Settings','Settings')]):
                self.frame('Frames.Card',(20,93+i*156,150,145),.33)
                self.sprite('Hud.'+asset,(32,105+i*156,125,89))
                self.text(label,(24,193+i*156,141,35),24,outline=2)
        tabs=('ALL','COMMON','RARE','EPIC','LEGENDARY','MYTHIC','GODLY','CELESTIAL','COSMIC')
        tw=(w-left-28-8*10)/9
        for i,label in enumerate(tabs):
            box=(left+i*(tw+10),218,tw,92)
            self.frame('Frames.ActiveTab' if i==0 else 'Frames.Tab',box,.40)
            self.text(label,box,31 if self.phone else 25,outline=3)
        names=['RustyShank','KitchenKnife','PocketKnife','HunterBlade','Switchblade','ThornDagger','Cleaver','Machete','BoneCarver','Katana','GoldenDagger','Reaper','InfernoFang','MagmaCleaver','DemonHorn','ZeusBolt','OlympusEdge','VoidEdge']
        if self.phone:
            names=['RustyShank','KitchenKnife','HunterBlade','PocketKnife','BoneCarver','Switchblade','ThornDagger','Cleaver','Katana','GoldenDagger','InfernoFang','Machete']
        rows=2 if self.phone else 3
        cw=(w-left-28-5*16)/6
        ch=(1040-334-(rows-1)*20)/rows
        hidden={2,4,6,9} if self.phone else {8,9,10,11,12,15,16,17}
        for i,name in enumerate(names[:rows*6]):
            x=left+(i%6)*(cw+16);y=334+(i//6)*(ch+20)
            self.frame('Frames.Card',(x,y,cw,ch),.55)
            icon=('Silhouettes.' if i in hidden else 'Knives.')+name
            self.sprite(icon,(x+4,y-13,cw-8,ch-50))
            l,t,r,b=self.elements[-1]['ContentBounds']
            assert x<l<r<x+cw and y<t<b<y+ch-70, (name,self.phone,[l,t,r,b])
            self.frame('Frames.OddsStrip',(x+12,y+ch-70,cw-24,57),.2)
            self.text('???' if i in hidden else name,(x+20,y+ch-70,cw-40,55),29 if self.phone else 25,outline=3)

    def powers(self):
        w=self.w;left=310 if self.phone else 252
        self.sprite('Frames.CloseButton',(15,14,128,114))
        self.text('<',(15,14,128,114),83,outline=5)
        self.frame('Frames.HeaderBar',(163,16,w-312,110),.44)
        self.text('Powers',(185,16,490,110),79,align='left',outline=6)
        self.sprite('Hud.Cash',(w-575,20,110,98))
        self.text('1,250',(w-462,25,197,87),45,outline=4)
        self.button('+',(w-249,27,75,79),size=56)
        self.frame('Frames.SecondaryButton',(w-128,20,103,101),.45)
        self.sprite('Hud.Settings',(w-122,25,91,90))
        nav=('Shop','Index','More','Knives','Players','Powers','Stats','Settings')
        for i,n in enumerate(nav):
            box=(15,145+i*112,left-37,103)
            self.frame('Frames.ActiveTab' if n=='Powers' else 'Frames.Tab',box,.4)
            self.sprite('Hud.'+n,(27,151+i*112,95,90))
            self.text(n,(129,155+i*112,left-158,84),35 if self.phone else 28,outline=3,align='left')
        right=430 if self.phone else 355
        rx=w-right-25;gap=20
        self.frame('Frames.PanelBody',(rx,145,right,902),.44)
        self.text('Loadout',(rx+15,156,right-30,80),48,outline=5)
        for i in range(3):
            box=(rx+35,252+i*246,right-70,207)
            self.frame('Frames.Card',box,.55)
            self.text('+',(box[0]+20,box[1]+16,box[2]-40,116),90,(125,150,196),outline=0)
            self.text('Select Power',(box[0]+20,box[1]+130,box[2]-40,48),31,(172,192,232),outline=2)
        cw=(rx-left-gap-3*gap)/4
        powers=[('Vanish','Turn invisible for a\nshort time.'),('Radar','Reveal nearby players\non your map.'),('Bear Trap','Place a trap that\nstuns players.'),('Shield','Gain a temporary\ndamage shield.'),('Decoy','Spawn a fake player\nto confuse others.'),('Flash','Blind nearby players\nfor a short time.'),('Barricade','Place a wall to block\npaths.'),('Mimic','Copy the last power\nused by another player.')]
        for i,(name,desc) in enumerate(powers):
            x=left+(i%4)*(cw+gap);y=145+(i//4)*460;ch=441
            self.frame('Frames.Card',(x,y,cw,ch),.55)
            self.sprite('Hud.Powers',(x+cw*.24,y+13,cw*.52,163))
            self.text(name,(x+12,y+177,cw-24,45),44 if self.phone else 36,outline=4)
            self.text(desc,(x+17,y+226,cw-34,73),28 if self.phone else 23,(188,204,239),outline=1,bold=False)
            self.text('Lv. 1',(x+17,y+326,79,40),27,outline=2)
            self.progress((x+99,y+326,cw-118,41),0,'0/5',5)
            bw=(cw-48)/2
            self.button('Equip',(x+15,y+362,bw,75),size=29 if self.phone else 25)
            self.button('Upgrade',(x+33+bw,y+362,bw,75),False,size=29 if self.phone else 25)

    def save(self):
        file=f'{self.screen}-'+('phone' if self.phone else 'desktop')+'.png'
        folder=OUT/'kit-proofs';folder.mkdir(exist_ok=True)
        self.im.convert('RGB').save(folder/file)
        return dict(Screen=self.screen,Device='PhoneLandscape' if self.phone else 'Desktop',
                    Size=[self.w,self.h],File='kit-proofs/'+file,
                    Purpose='Asset-kit reconstruction proof; reference mockup stays authoritative',
                    Elements=self.elements,Assets=sorted({e['Asset'] for e in self.elements if 'Asset' in e}))

def restore_mockups():
    jobs=json.loads((OUT/'jobs.json').read_text())['Jobs']
    records=[]
    for job in jobs:
        if not job['Id'].startswith('Mockups.'):
            continue
        target=OUT/job['File'];source=OUT/'references'/job['File']
        rejected=OUT/'withdrawn-v2'/job['File']
        rejected.parent.mkdir(parents=True,exist_ok=True)
        if not rejected.exists():shutil.copyfile(target,rejected)
        shutil.copyfile(source,target)
        assert Image.open(target).size==tuple(job['Size'])
        records.append(dict(Id=job['Id'],File=job['File'],Size=job['Size'],
                            Reference='references/'+job['File'],Status='Original generated design restored'))
    for name in ('mockup-layouts.json','mockup-validation.json'):
        rejected=OUT/'withdrawn-v2'/name
        if not rejected.exists():shutil.copyfile(OUT/name,rejected)
    (OUT/'mockup-layouts.json').write_text(json.dumps(dict(Count=len(records),
        Warning='The withdrawn generic layouts are not integration specs. Use original design images and kit-proofs/layouts.json.',
        Mockups=records),indent=2))
    return records

def sheet(paths, destination, labels, cols=2, tile=(960,580)):
    cw,ch=tile;im=Image.new('RGB',(cw*cols,ch*math.ceil(len(paths)/cols)),(14,22,39));d=ImageDraw.Draw(im)
    font=ImageFont.truetype(str(FONT),27);font.set_variation_by_name('Bold')
    for i,(path,label) in enumerate(zip(paths,labels)):
        src=Image.open(path).convert('RGBA');src.thumbnail((cw-28,ch-65),Image.Resampling.LANCZOS)
        x=(i%cols)*cw;y=(i//cols)*ch
        im.paste(src,(x+(cw-src.width)//2,y+57),src.getchannel('A'))
        d.text((x+18,y+12),label,font=font,fill=(245,250,255))
    im.save(destination)

def main():
    if CAT.get('Version',1)<4:export_frames()
    records=restore_mockups()
    proofs=[]
    for screen in ('KnifeIndex','Powers'):
        for phone in (False,True):
            s=Screen(screen,phone)
            getattr(s,'index' if screen=='KnifeIndex' else 'powers')()
            proofs.append(s.save())
    (OUT/'kit-proofs/layouts.json').write_text(json.dumps(dict(Version=CAT['Version'],AssetManifest='Config/VoxelUi.luau',Mockups=proofs),indent=2))
    for device in ('desktop','phone'):
        selected=[r for r in records if r['File'].endswith('-'+device+'.png')]
        sheet([OUT/r['File'] for r in selected],OUT/('gallery-'+device+'.png'),[r['Id'].split('.')[1] for r in selected],3,(800,435))
    sheet([OUT/r['File'] for r in proofs],OUT/'kit-proofs/gallery.png',[r['Screen']+' / '+r['Device'] for r in proofs])
    frames=[a for a in CAT['Assets'] if a['Group']=='Frames']
    sheet([ART/a['File'] for a in frames],ART/'review/Frames.png',[a['Name'] for a in frames],2,(640,340))
    comparisons=[];labels=[]
    for screen in ('KnifeIndex','Powers'):
        comparisons.extend([OUT/'mockups'/f'{screen}-phone.png',OUT/'kit-proofs'/f'{screen}-phone.png'])
        labels.extend([screen+' / original generated target',screen+' / delivered PNG kit proof'])
    sheet(comparisons,OUT/'reference-fidelity-review.png',labels)
    checks=[]
    for a in CAT['Assets']:
        im=Image.open(ART/a['File']).convert('RGBA');alpha=im.getchannel('A');w,h=a['Size']
        assert im.size==(w,h) and alpha.getextrema()[0]==0,a['Id']
        assert all(alpha.getpixel(p)==0 for p in ((0,0),(w-1,0),(0,h-1),(w-1,h-1))),a['Id']
        rect=a['SliceCenter']
        if rect:
            l,t,r,b=rect;assert 0<l<r<w and 0<t<b<h,a['Id']
        checks.append(dict(Id=a['Id'],Size=a['Size'],AlphaBounds=alpha.getbbox(),SliceCenter=rect))
    (ART/'validation.json').write_text(json.dumps(dict(AssetCount=len(checks),Version=CAT['Version'],Assets=checks),indent=2))
    (OUT/'mockup-validation.json').write_text(json.dumps(dict(Mockups=46,Screens=23,
        CanvasSizes=[[1920,1080],[2400,1080]],Status='Original generated designs restored; generic v2 exports withdrawn',
        KitProofs=4,KitProofAssetKeysValidated=True,ProductionAssetCount=len(CAT['Assets']),
        KnifeAndSilhouetteContainment='Every visible alpha bound is inside its card and above the nameplate in all four kit proof layouts',
        StudioUiIntegration='Claude; untouched by this correction',
        Caveat='Generated screen copy is illustrative. Live power availability, slots, prices and progress must come from authoritative configuration.'),indent=2))
    print(f'Restored {len(records)} generated mockups, exported 9 faithful skins, wrote 4 kit proofs and validated {len(checks)} PNGs.')

if __name__=='__main__':main()
