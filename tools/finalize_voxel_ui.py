"""Produce exact-size PNGs, stable nine-slice skins and group review sheets."""
import json, math, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/voxel-ui"
catalog = json.loads((OUT / "catalog.json").read_text())
NAVY = (13,18,36,255)

def stepped_rect(draw, box, fill, step=8):
    x,y,r,b = box
    draw.polygon([(x+step,y),(r-step,y),(r-step,y+step),(r,y+step),(r,b-step),
                  (r-step,b-step),(r-step,b),(x+step,b),(x+step,b-step),(x,b-step),(x,y+step),(x+step,y+step)], fill=fill)

def skin(size, color, accent, margin=8, border=6, transparent_center=False, studs=True):
    w,h = size
    image = Image.new("RGBA",size)
    d = ImageDraw.Draw(image)
    stepped_rect(d,(margin,margin,w-margin-1,h-margin-1),NAVY,8)
    inset = margin+border
    stepped_rect(d,(inset,inset,w-inset-1,h-inset-1),color,6)
    # Top-left light and right/bottom depth are block bars, not soft rounded bevels.
    d.rectangle((inset+8,inset+2,w-inset-9,inset+5),fill=accent)
    d.rectangle((inset+2,inset+8,inset+5,h-inset-9),fill=accent)
    d.rectangle((inset+8,h-inset-6,w-inset-9,h-inset-3),fill=(8,12,27,255))
    if studs:
        for x in (inset+2,w-inset-8):
            for y in (inset+2,h-inset-8):
                d.rectangle((x-2,y-2,x+7,y+7),fill=NAVY)
                d.rectangle((x,y,x+5,y+5),fill=accent)
    if transparent_center:
        d.rectangle((inset+14,inset+14,w-inset-15,h-inset-15),fill=(0,0,0,0))
    return image

def normalize_icon(source, size):
    image = Image.open(source).convert("RGBA")
    mask = image.getchannel("A")
    assert mask.getextrema()[0] == 0, f"Background is not transparent: {source}"
    # Remove sub-visible alpha noise in generated references before measuring padding.
    cutoff = 128 if source.parent.name == "Cases" else 8
    mask = mask.point(lambda value: 0 if value < cutoff else value)
    image.putalpha(mask)
    # Add a crisp silhouette stroke; preserve the model's internal block boundaries.
    radius = max(2, round(max(image.size)*.008))
    expanded = mask.filter(ImageFilter.MaxFilter(radius*2+1))
    stroke = Image.new("RGBA",image.size,NAVY)
    stroke.putalpha(expanded)
    stroke.alpha_composite(image)
    box = expanded.getbbox()
    assert box and box[0]>0 and box[1]>0 and box[2]<image.width and box[3]<image.height, f"Source cropped: {source}"
    crop = stroke.crop(box)
    available = (round(size[0]*.76), round(size[1]*.76))
    crop.thumbnail(available,Image.Resampling.LANCZOS)
    final = Image.new("RGBA",size)
    final.alpha_composite(crop,((size[0]-crop.width)//2,(size[1]-crop.height)//2))
    return final

def frame(entry):
    name,size = entry["Name"],tuple(entry["Size"])
    colors = {
      "PanelBody": ((37,43,65,255),(87,220,241,255)),
      "HeaderBar": ((35,73,116,255),(96,226,249,255)),
      "PrimaryButton": ((34,179,197,255),(118,249,239,255)),
      "SecondaryButton": ((70,89,133,255),(155,179,233,255)),
      "Tab": ((65,57,112,255),(117,177,244,255)),
      "CloseButton": ((215,58,85,255),(255,138,146,255)),
      "Card": ((34,40,61,255),(81,121,170,255)),
      "OddsStrip": ((59,45,91,255),(166,116,224,255)),
      "Background": ((24,30,49,255),(70,195,224,255)),
      "ReelFrame": ((42,64,91,255),(84,224,241,255)),
    }
    color,accent = colors[name]
    compact = size[0]<512 or size[1]<=128
    margin = 8 if compact else 12
    result = skin(size,color,accent,margin,6 if compact else 8,
                  transparent_center=name=="ReelFrame",studs=name not in ("CloseButton","OddsStrip"))
    if name != "CloseButton":
        d = ImageDraw.Draw(result)
        rect = entry["SliceCenter"] or [48,48,size[0]-48,size[1]-48]
        inset = margin+(6 if compact else 8)
        band = min(28,rect[0]-2,rect[1]-2)
        rim = tuple(round(v*.55+18) for v in color[:3])+(255,)
        for box in [(inset,inset,size[0]-inset-1,band),
                    (inset,size[1]-band-1,size[0]-inset-1,size[1]-inset-1),
                    (inset,inset,band,size[1]-inset-1),
                    (size[0]-band-1,inset,size[0]-inset-1,size[1]-inset-1)]:
            d.rectangle(box,fill=rim)
        d.rectangle((inset,inset,size[0]-inset-1,inset+2),fill=accent)
        d.rectangle((inset,inset,inset+2,size[1]-inset-1),fill=accent)
        # Block seams and square studs stay in border strips; the text/reel area stays clear.
        mid = (inset+band)//2
        for x in range(rect[0]+12,size[0]-rect[0],40):
            for y in (mid,size[1]-mid-1):
                d.rectangle((x-2,y-2,x+2,y+2),fill=accent)
                d.line((x-12,inset if y==mid else size[1]-band-1,
                        x-12,band if y==mid else size[1]-inset-1),fill=NAVY,width=1)
    # Raised block caps live entirely in the fixed corner slices, so their
    # square studs and highlights keep their shape when a panel is resized.
    if name != "CloseButton":
        d = ImageDraw.Draw(result)
        rect = entry["SliceCenter"] or [48,48,size[0]-48,size[1]-48]
        cx,cy = min(24,rect[0]//2+4),min(24,rect[1]//2+4)
        half = 5 if compact else 8
        dark = tuple(round(v*.65) for v in accent[:3])+(255,)
        light = tuple(round(v*.55+255*.45) for v in accent[:3])+(255,)
        for x in (cx,size[0]-cx-1):
            for y in (cy,size[1]-cy-1):
                d.rectangle((x-half-2,y-half-2,x+half+2,y+half+2),fill=NAVY)
                d.rectangle((x-half,y-half,x+half,y+half),fill=dark)
                d.rectangle((x-half,y-half,x+half-2,y+half-2),fill=accent)
                d.rectangle((x-half,y-half,x+half-2,y-half+2),fill=light)
    if name == "ReelFrame":
        d = ImageDraw.Draw(result)
        for flip in (False,True):
            cy = size[1]-1 if flip else 0
            direction = -1 if flip else 1
            x = size[0]//2
            d.polygon([(x-19,cy+direction*7),(x+19,cy+direction*7),(x+19,cy+direction*23),
                       (x+9,cy+direction*23),(x+9,cy+direction*34),(x,cy+direction*43),
                       (x-9,cy+direction*34),(x-9,cy+direction*23),(x-19,cy+direction*23)],fill=NAVY)
            d.polygon([(x-13,cy+direction*12),(x+13,cy+direction*12),(x+13,cy+direction*19),
                       (x+5,cy+direction*19),(x+5,cy+direction*29),(x,cy+direction*34),
                       (x-5,cy+direction*29),(x-5,cy+direction*19),(x-13,cy+direction*19)],fill=(255,206,70,255))
    return result

def glow(entry):
    image = Image.new("RGBA",tuple(entry["Size"]))
    d = ImageDraw.Draw(image)
    color = catalog["RarityColors"][entry["Name"]]
    for inset,opacity in [(48,30),(64,45),(80,65),(96,90)]:
        stepped_rect(d,(inset,inset,511-inset,511-inset),tuple(color)+(opacity,),24)
    stepped_rect(d,(112,112,399,399),tuple(color)+(32,),24)
    for x in (91,411):
        for y in (91,411):
            d.rectangle((x-7,y-7,x+7,y+7),fill=tuple(color)+(130,))
    return image

def main():
    checks = []
    partial = "--partial" in sys.argv
    entries = catalog["Assets"]
    if partial:
        entries = [e for e in entries if (OUT/e["Reference"]).is_file() and
                   (not e["Model"] or (OUT/"renders"/e["Group"]/(e["Name"]+".png")).is_file())]
    for entry in entries:
        assert (OUT / entry["Reference"]).is_file(), f"Missing per-asset generated reference: {entry['Id']}"
        group = entry["Group"]
        size = tuple(entry["Size"])
        if group in ("Knives","LuckyBlocks"):
            final = normalize_icon(OUT / "renders" / group / (entry["Name"]+".png"),size)
        elif group in ("Cases","Hud"):
            final = normalize_icon(OUT / entry["Reference"],size)
        elif group == "Frames" and catalog.get("Version",1) >= 3:
            # The accepted ImageGen exports must never regress to thin v2 skins.
            final = Image.open(OUT / entry["File"]).convert("RGBA")
        elif group == "Silhouettes":
            knife = Image.open(OUT / 'png/Knives' / (entry['Name']+'.png')).convert('RGBA')
            final = Image.new('RGBA',size,(9,15,29,255))
            final.putalpha(knife.getchannel('A'))
        elif group in ("Frames","Unbox"):
            final = frame(entry)
        elif group == "GlowBackplates":
            final = glow(entry)
        else:
            color = catalog["RarityColors"][entry["Name"]]
            accent = tuple(min(255,int(v*.65+255*.35)) for v in color)+(255,)
            final = skin(size,tuple(color)+(255,),accent,8,6,studs=False)
        path = OUT / entry["File"]
        final.save(path,optimize=True)
        assert final.size == size and final.mode == "RGBA"
        alpha = final.getchannel("A")
        assert alpha.getextrema()[0]==0
        box = alpha.getbbox()
        assert box and all(final.getpixel(p)[3]==0 for p in [(0,0),(size[0]-1,0),(0,size[1]-1),(size[0]-1,size[1]-1)])
        if group in ("Knives","LuckyBlocks","Cases","Hud"):
            assert box[0]>=size[0]*.11 and box[1]>=size[1]*.11 and box[2]<=size[0]*.89 and box[3]<=size[1]*.89
        rect = entry["SliceCenter"]
        if rect:
            x,y,r,b=rect
            assert 0<x<r<size[0] and 0<y<b<size[1]
            center = final.crop((x,y,r,b))
            assert len(center.getcolors(center.width*center.height) or []) == 1, f"Stretch center is not flat: {entry['Id']}"
        checks.append(dict(Id=entry["Id"],Size=list(size),AlphaBounds=list(box),SliceCenter=rect))
    (OUT / ("validation-partial.json" if partial else "validation.json")).write_text(json.dumps(dict(AssetCount=len(checks),Assets=checks),indent=2))
    review()
    print(f"Validated {len(checks)} exact-size transparent standalone PNGs")

def review():
    directory = OUT / "review"
    directory.mkdir(exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf",18)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf",14)
    for group in dict.fromkeys(e["Group"] for e in catalog["Assets"]):
        entries = [e for e in catalog["Assets"] if e["Group"]==group]
        if any(not (OUT/e["File"]).is_file() for e in entries):
            continue
        cols = 4 if group in ("Frames","Unbox") else 6
        cell = 240
        sheet = Image.new("RGB",(cols*cell,math.ceil(len(entries)/cols)*280),(35,41,61))
        d = ImageDraw.Draw(sheet)
        for i,e in enumerate(entries):
            x,y=(i%cols)*cell,(i//cols)*280
            d.rectangle((x+5,y+5,x+234,y+234),fill=(48,57,78))
            image = Image.open(OUT/e["File"])
            image.thumbnail((215,205),Image.Resampling.LANCZOS)
            sheet.paste(image,(x+(cell-image.width)//2,y+(240-image.height)//2),image)
            d.text((x+12,y+239),e["Name"],font=font,fill=(239,246,255))
            d.text((x+12,y+263),f"{e['Size'][0]} x {e['Size'][1]}",font=small,fill=(164,195,221))
        sheet.save(directory/(group+".png"))
    hud=[e for e in catalog["Assets"] if e["Group"]=="Hud"]
    if any(not (OUT/e["File"]).is_file() for e in hud):
        return
    sheet = Image.new("RGB",(1008,240),(24,30,45))
    d = ImageDraw.Draw(sheet)
    for i,e in enumerate(hud):
        x,y=(i%9)*112,(i//9)*105
        icon=Image.open(OUT/e["File"]).resize((44,44),Image.Resampling.LANCZOS)
        sheet.paste(icon,(x+14,y+12),icon)
        d.text((x+2,y+65),e["Name"][:10],font=small,fill=(240,244,255))
    sheet.save(directory/"Hud-44px.png")

if __name__=="__main__":
    main()
