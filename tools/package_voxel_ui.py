"""Package the delivered UI art and its reviewed manifest, excluding large references."""
import hashlib
import json
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/voxel-ui"
manifest = json.loads((OUT / "manifest.json").read_text())
assets = manifest["Assets"]
expected = dict(Knives=24, LuckyBlocks=7, Cases=8, Hud=17, Frames=9, Unbox=2, GlowBackplates=8, Badges=8, Silhouettes=24)
assert Counter(e["Group"] for e in assets) == expected
assert len({e["Id"] for e in assets}) == 107
assert len({e["AssetId"] for e in assets}) == 107
for entry in assets:
    assert (OUT / entry["Reference"]).is_file(), entry["Id"]
    assert hashlib.sha256((OUT / entry["File"]).read_bytes()).hexdigest() == entry["SHA256"], entry["Id"]
files = [OUT / e["File"] for e in assets]
files += sorted((OUT / "review").glob("*.png"))
files += [OUT / name for name in ("manifest.json", "catalog.json", "validation.json", "README.md", "verification.json")]
files += sorted((OUT / 'references/Frames-v4').glob('*.png'))
files += sorted((OUT / 'fonts').glob('*'))
destination = OUT / "voxel-ui-art-pack.zip"
with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as package:
    for path in files:
        package.write(path, path.relative_to(OUT).as_posix())
    package.write(ROOT / "src/shared/Config/VoxelUi.luau", "Config/VoxelUi.luau")
    audit = ROOT / 'assets/visual-expansion/pixel-audit'
    for path in sorted(audit.glob('*-comparison.png')):
        package.write(path,'pixel-audit/'+path.name)
    package.write(audit/'frame-pixel-validation.json','pixel-audit/frame-pixel-validation.json')
    package.write(ROOT/'assets/visual-expansion/HANDOFF.md','HANDOFF.md')
    package.write(ROOT/'assets/visual-expansion/UI_COVERAGE.md','UI_COVERAGE.md')
with zipfile.ZipFile(destination, "r") as package:
    assert package.testzip() is None
print(f"Packaged {len(assets)} PNGs, {len(list((OUT/'review').glob('*.png')))} reviews and verified metadata ({destination.stat().st_size:,} bytes)")
