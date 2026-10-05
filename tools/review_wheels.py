"""Make a contact sheet and a concept/model comparison from saved local assets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/wheels"
data = json.loads((OUT / "geometry.json").read_text())
font_path = Path("C:/Windows/Fonts/arialbd.ttf")
font = ImageFont.truetype(str(font_path), 21)
small = ImageFont.truetype(str(font_path), 16)
gallery = Image.new("RGB", (1600, 1760), "#edf0f4")
draw = ImageDraw.Draw(gallery)
comparison = Image.new("RGB", (1280, 7 * 362), "#edf0f4")
cdraw = ImageDraw.Draw(comparison)
early = Image.open(OUT / "concepts/01-creaky-to-cursed.png").convert("RGB")
middle = Image.open(OUT / "concepts/02-bone-to-infernal.png").convert("RGB")
late = Image.open(OUT / "concepts/03-olympian-to-cosmic.png").convert("RGB")

for i, tier in enumerate(data):
    preview = Image.open(OUT / f"{i+1:02d}-preview.png").convert("RGB")
    x, y = (i % 4) * 400, (i // 4) * 440
    gallery.paste(preview.resize((400, 400)), (x, y))
    draw.text((x+12, y+399), f"{i+1:02d}  {tier['Name']}", font=font, fill="#1d2436")
    if i < 3:
        source, bounds = early, (i/3, 0, (i+1)/3, .50)
    elif i < 5:
        source, bounds = early, ((i-3)/2, .50, (i-2)/2, 1)
    elif i < 9:
        source = middle
        k = i-5
        bounds = ((k%2)/2, (k//2)/2, (k%2+1)/2, (k//2+1)/2)
    else:
        source = late
        k = i-9
        bounds = ((k%2)/2, (k//2)/2, (k%2+1)/2, (k//2+1)/2)
    crop = source.crop(tuple(round(v*(source.width if j%2==0 else source.height)) for j,v in enumerate(bounds)))
    crop.thumbnail((312,312))
    cx, cy = (i%2)*640, (i//2)*362
    comparison.paste(crop, (cx+(320-crop.width)//2,cy+(312-crop.height)//2))
    comparison.paste(preview.resize((312,312)), (cx+324,cy))
    cdraw.text((cx+10, cy+313), f"{i+1:02d}  {tier['Name']}", font=font, fill="#1d2436")
    cdraw.text((cx+10, cy+340), "Generated concept", font=small, fill="#42516b")
    cdraw.text((cx+330, cy+340), "Native block model", font=small, fill="#42516b")
gallery.save(OUT / "gallery.png")
comparison.save(OUT / "concept-vs-model.png")
print("Saved gallery.png and concept-vs-model.png")
