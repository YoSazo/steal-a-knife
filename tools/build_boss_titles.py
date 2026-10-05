"""Trace the original boss artwork into merged, extruded voxel rectangles."""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/ui/cartoon-pack-v1'
OUT = ROOT / 'assets/boss-titles'
BOSSES = {'Frank':'The Groundskeeper', 'Ivy':'The Gardener', 'Sam':'The Gravedigger', 'Leo':'The Collector', 'Ruby':'The Firestarter', 'Kate':'The Queen', 'Zoe':'The Angel', 'Nick':'The Void Walker'}

def trace(path, width=None, colors=32):
    original = Image.open(path).convert('RGBA')
    sampled = original if width is None else original.resize((width,round(width*original.height/original.width)),Image.Resampling.LANCZOS)
    a = np.array(sampled)
    mask = a[:,:,3]>=128
    rgb=a[:,:,:3]
    # Keep the original canvas pixels. Dark outline/base, decorations and pale lettering are
    # three physical heights; original image UVs supply exact, unquantized face colours.
    relief=np.where(rgb.max(2)<85,0,np.where((rgb.min(2)>145)&(rgb.max(2)>205)&((rgb.max(2)-rgb.min(2))<100),2,1)).astype(np.int16)
    # Native vertex colours replace the bitmap entirely. Quantize only the painted colour
    # regions, keeping every original alpha/letter-depth pixel at full source resolution.
    pixels=Image.fromarray(rgb[mask].reshape(1,-1,3))
    palette_source=pixels.quantize(colors=32,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
    indexed=sampled.convert('RGB').quantize(palette=palette_source,dither=Image.Dither.NONE)
    palette=np.array(indexed.getpalette(),np.uint8).reshape(-1,3)[:32]
    color_grid=np.array(indexed).astype(np.int16)
    grid=relief*32+color_grid
    grid[~mask]=-1
    used = np.zeros(grid.shape,dtype=bool)
    rects=[]
    h,w=grid.shape
    for y in range(h):
        for x in range(w):
            if used[y,x] or grid[y,x]<0:continue
            key=grid[y,x];right=x+1
            while right<w and not used[y,right] and grid[y,right]==key:right+=1
            bottom=y+1
            while bottom<h and np.all(~used[bottom,x:right]) and np.all(grid[bottom,x:right]==key):bottom+=1
            used[y:bottom,x:right]=True
            depth=(.18,.36,.66)[key//32]
            rects.append([x,y,right-x,bottom-y,int(key),depth])
    assert np.array_equal(used,mask)
    preview=np.zeros((h,w,4),dtype=np.uint8)
    preview[mask,:3]=rgb[mask]
    preview[mask,3]=255
    # Only exterior faces survive the voxel union: front colour rectangles, a plain closed
    # back and merged side walls at actual height changes. No internal coincident triangles.
    sides=[]
    tiers=np.where(mask,relief+1,0)
    heights=(0,.18,.36,.66)
    for direction,axis,delta in [('Left',1,-1),('Right',1,1),('Top',0,-1),('Bottom',0,1)]:
        neighbour=np.zeros_like(tiers)
        if axis==1 and delta==-1:neighbour[:,1:]=tiers[:,:-1]
        if axis==1 and delta==1:neighbour[:,:-1]=tiers[:,1:]
        if axis==0 and delta==-1:neighbour[1:,:]=tiers[:-1,:]
        if axis==0 and delta==1:neighbour[:-1,:]=tiers[1:,:]
        keys=np.where(tiers>neighbour,((tiers*4+neighbour)*32+color_grid),-1)
        scan=keys.T if axis==1 else keys
        for line in range(scan.shape[0]):
            start=0
            while start<scan.shape[1]:
                value=int(scan[line,start]);end=start+1
                if value<0:start=end;continue
                while end<scan.shape[1] and scan[line,end]==value:end+=1
                pair=value//32;high=pair//4;low=pair%4
                sides.append([direction,line+(1 if delta==1 else 0),start,end-start,heights[low],heights[high],value%32])
                start=end
    back=[]
    # Horizontal runs merge vertically when their intervals match, yielding a closed backing.
    active={}
    for yy in range(h):
        runs=[];xx=0
        while xx<w:
            if not mask[yy,xx]:xx+=1;continue
            end=xx+1
            while end<w and mask[yy,end]:end+=1
            runs.append((xx,end));xx=end
        current={}
        for interval in runs:
            if interval in active:
                entry=active[interval];entry[3]+=1
            else:
                entry=[interval[0],yy,interval[1]-interval[0],1];back.append(entry)
            current[interval]=entry
        active=current
    return dict(Source=str(path.relative_to(ROOT)).replace('\\','/'),SourceSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),SourceSize=list(original.size),Grid=[w,h],Palette=palette.tolist(),Rects=rects,Sides=sides,Back=back,ColourMode='Native vertex paint; no image textures'),Image.fromarray(preview)

if __name__=='__main__':
    import sys
    if '--measure' in sys.argv:
        for w in (512,1024):
            counts=[]
            for boss in BOSSES:
                for group,suffix,width in [('lair-signs','stash',w),('boss-ribbons','title',round(w*.75))]:
                    data,_=trace(ART/group/f'{boss.lower()}-{suffix}.png',width)
                    counts.append(len(data['Rects']))
            print(w,sum(counts),counts)
    else:
        OUT.mkdir(parents=True,exist_ok=True)
        (OUT/'previews').mkdir(exist_ok=True)
        designs=[]
        for boss,title in BOSSES.items():
            surfaces={}
            for group,suffix,name,width in [('lair-signs','stash','Sign',None),('boss-ribbons','title','SignRibbon',None)]:
                data,preview=trace(ART/group/f'{boss.lower()}-{suffix}.png',width)
                surfaces[name]=data
                preview.resize(tuple(data['SourceSize']),Image.Resampling.NEAREST).save(OUT/'previews'/f'{boss}-{name}.png')
            designs.append(dict(Boss=boss,Stash=boss.upper()+"'S STASH",Title=title,Surfaces=surfaces))
        (OUT/'geometry.json').write_text(json.dumps(dict(Designs=designs),separators=(',',':')))
        print('Generated',len(designs),'boss models;',sum(len(s['Rects']) for d in designs for s in d['Surfaces'].values()),'colour voxel regions;',sum(len(s['Rects'])+len(s['Sides'])+len(s['Back']) for d in designs for s in d['Surfaces'].values())*2,'exterior triangles')
