"""Build review sheets from concept art and the actual native-geometry renders."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/vaults"
data = json.loads((OUT / "geometry.json").read_text())
font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 21)
small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
gallery = Image.new("RGB", (1600, 684), "#eef1f5")
draw = ImageDraw.Draw(gallery)
comparison = Image.new("RGB", (1280, 4 * 385), "#eef1f5")
cd = ImageDraw.Draw(comparison)
concept = Image.open(OUT / "concept-upgrades.png").convert("RGB")
for i, spec in enumerate(data["Scenes"][:8]):
    pic = Image.open(OUT / f"{i+1:02d}-preview.png").convert("RGB")
    x,y = (i%4)*400, (i//4)*342
    gallery.paste(pic.resize((400,300)), (x,y))
    draw.text((x+10,y+303), f"{i+1:02d} {spec['Name']}", font=font, fill="#202c42")
    box = ((i%4)*concept.width//4, (i//4)*concept.height//2,
           (i%4+1)*concept.width//4, (i//4+1)*concept.height//2)
    crop = concept.crop(box)
    crop.thumbnail((310,310))
    cx,cy = (i%2)*640,(i//2)*385
    comparison.paste(crop,(cx+(320-crop.width)//2,cy+(310-crop.height)//2))
    comparison.paste(pic.resize((320,240)),(cx+320,cy+35))
    cd.text((cx+10,cy+315), f"{i+1:02d} {spec['Name']}",font=font,fill="#202c42")
    cd.text((cx+10,cy+347), "Generated concept",font=small,fill="#526078")
    cd.text((cx+330,cy+347), "Native block geometry",font=small,fill="#526078")
details = Image.new("RGB", (1440,402), "#eef1f5")
dd = ImageDraw.Draw(details)
for col, idx in enumerate([10,8,9]):
    pic=Image.open(OUT/f"{idx+1:02d}-preview.png").convert("RGB")
    details.paste(pic.resize((480,360)),(col*480,0))
    dd.text((col*480+10,365),data["Scenes"][idx]["Name"],font=font,fill="#202c42")
gallery.save(OUT/"gallery.png")
comparison.save(OUT/"concept-vs-model.png")
details.save(OUT/"details.png")
print("Saved gallery.png, concept-vs-model.png, details.png")

plate_gallery = Image.new("RGB", (1600, 684), "#eef1f5")
pd = ImageDraw.Draw(plate_gallery)
for i, spec in enumerate(data["Scenes"][:8]):
    pic = Image.open(OUT / f"{i+12:02d}-preview.png").convert("RGB")
    x, y = (i % 4) * 400, (i // 4) * 342
    plate_gallery.paste(pic.resize((400, 300)), (x, y))
    pd.text((x+10, y+303), f"{i+1:02d} {spec['Name']}", font=font, fill="#202c42")
plate_gallery.save(OUT / "plates/upgrades.png")
review = Image.new("RGB", (1600, 720), "#eef1f5")
rd = ImageDraw.Draw(review)
for column, (path, label) in enumerate([(OUT / "plates/reference.png", "Generated modeling reference"), (OUT / "11-preview.png", "Actual block-built 3D plate")]):
    pic = Image.open(path).convert("RGB")
    pic.thumbnail((780, 640))
    review.paste(pic, (column*800+(800-pic.width)//2, (650-pic.height)//2))
    rd.text((column*800+24, 675), label, font=font, fill="#202c42")
review.save(OUT / "plates/reference-vs-model.png")
print("Saved plates/upgrades.png and plates/reference-vs-model.png")
