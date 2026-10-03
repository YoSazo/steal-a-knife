"""Pack Blender renders without resampling; write the tile manifest used by Roblox."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
folder = root / "blender/textures/ui"
manifest = json.loads((folder / "manifest.json").read_text())
tile, columns = manifest["tile"], manifest["columns"]
sheet = Image.new("RGBA", (columns * tile, columns * tile))
for index, name in enumerate(manifest["names"]):
    with Image.open(folder / f"{name}.png") as image:
        assert image.size == (tile, tile)
        sheet.paste(image, ((index % columns) * tile, (index // columns) * tile))
sheet.save(folder / "atlas.png", optimize=True)
print(f"Packed {len(manifest['names'])} tiles into {folder / 'atlas.png'}")
