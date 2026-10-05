"""Catalog every requested standalone UI asset and its per-asset ImageGen brief."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/voxel-ui"
OUT.mkdir(exist_ok=True)
PALETTE = {"Common": [190,202,218], "Rare": [65,135,255], "Epic": [160,75,240],
           "Legendary": [255,184,38], "Mythic": [247,60,73], "Godly": [255,95,185],
           "Celestial": [72,226,242], "Cosmic": [108,65,217]}
STYLE = ("One production UI asset in Roblox voxel toy style. Visible cubic steps and individual rectangular blocks, "
         "thick near-black navy outline, bright flat color faces, soft top-left highlight, very simple readable silhouette. "
         "No rounded cartoon curves, photorealism, metallic reflections, bevel-heavy geometry, scenery, letters, labels, "
         "watermark or other text. Transparent background, entire object visible, centered with 12 percent clear padding. ")
assets = []
def add(group, name, subject, size=(512,512), model=None, reference=None, slice_center=None):
    entry = dict(Id=f"{group}.{name}", Group=group, Name=name, Size=list(size),
                 File=f"png/{group}/{name}.png", Reference=f"references/{group}/{name}.png",
                 Prompt=STYLE + subject, Model=model, Input=reference, SliceCenter=slice_center)
    assets.append(entry)

geometry = json.loads((ROOT / "assets/toy-redesign/geometry.json").read_text())["Designs"]
for design in geometry:
    if design["Group"] not in ("knives", "lucky"):
        continue
    group = "Knives" if design["Group"] == "knives" else "LuckyBlocks"
    name = design["Name"] if group == "Knives" else design["Name"].removeprefix("Lucky")
    prefix = "knife" if group == "Knives" else "lucky"
    old_ref = f"assets/toy-redesign/references/{prefix}-{name}.png"
    assert (ROOT / old_ref).is_file(), old_ref
    add(group, name, f"UI icon reference for {name}. Input image is the actual existing voxel toy design reference. "
        "Preserve its stepped silhouette, thick blade, guard, pommel and colors" if group == "Knives" else
        f"UI icon reference for the {name} Lucky Block. Preserve the input block's colors and chunky corner caps. "
        "The only text allowed is the ivory pixel-block '?' on the visible faces.",
        model=design["Name"], reference=old_ref)
    assets[-1]["Prompt"] += " Three-quarter front view with visible thickness, isolated inventory product icon."

for rarity, color in PALETTE.items():
    add("Cases", rarity, f"Closed chunky voxel treasure chest, {rarity} rarity, main RGB {color}, near-black frame, "
        "oversized square corner caps like the Lucky Blocks, gold square latch, 3/4 angle. A chest silhouette: wide and low "
        "with a stepped lid and thick hinges; it must not look like a question cube.")

HUD = {
 "Shop": "cyan shopping cart with square basket, two dark square wheels and yellow handle",
 "Index": "open royal-blue voxel book, ivory page blocks, gold stepped bookmark",
 "More": "three horizontal ivory voxel bars stacked vertically; no enclosing box",
 "Knives": "single red-and-silver chunky stepped toy knife with oversized navy guard, diagonal blade upwards",
 "Players": "two distinct purple and lavender toy heads, one slightly behind the other, dark pixel eyes",
 "Powers": "single yellow voxel lightning bolt with orange side thickness, large zigzag silhouette",
 "Rebirth": "two mint and teal voxel arrows forming an open stepped square loop",
 "Stats": "gold voxel trophy cup with stepped handles, narrow stem, dark square plinth",
 "Upgrades": "one tall lime-green voxel up-arrow with thick blue base and three visibly stepped arrowhead courses",
 "Spin": "voxel prize wheel with eight chunky colored sectors, deep-blue octagonal border, gold top pointer and blue foot",
 "Merchant": "magenta and ivory striped voxel market tent, big triangular stepped canopy, two posts and little counter",
 "FreeChest": "warm amber voxel treasure chest with bright gold clasp and one large ivory four-point block sparkle above it",
 "Speed": "orange voxel sneaker with white sole, short cyan speed blocks behind, and a single white block '+' beside it; '+' is allowed",
 "Cash": "three emerald-green voxel banknote bundles stacked asymmetrically, ivory bands, a gold coin made of stepped blocks",
 "Heat": "coral-red and orange voxel flame with yellow block center, stepped pointed tip; no smooth curves",
 "MurdererChance": "dark crimson voxel knife crossed beside a large ivory dice cube with dark square pips",
 "Settings": "slate-blue voxel gear with eight large square teeth and a clearly open square center",
}
for name, subject in HUD.items():
    add("Hud", name, subject + ". Must remain unambiguous at 44x44 pixels, avoid tiny decoration.", (256,256))

FRAME_SPECS = {
 "PanelBody": ((512,512), [48,48,464,464], "large navy panel with dark stepped corners, cyan inset line and small square studs along inner border; uniform dark navy center"),
 "HeaderBar": ((512,128), [40,40,472,88], "wide deep-blue title bar, cyan top highlight, stepped ends, no text; flat dark-blue central title area"),
 "PrimaryButton": ((256,96), [24,24,232,72], "bright turquoise primary button with navy stepped border, aqua top-left highlight, flat turquoise center"),
 "SecondaryButton": ((256,96), [24,24,232,72], "slate-blue secondary button with navy stepped border, lavender top-left highlight, flat slate-blue center"),
 "Tab": ((256,96), [24,24,232,72], "indigo tab plate, square stepped top corners, cyan lower accent, empty uniform indigo middle"),
 "CloseButton": ((96,96), [24,24,72,72], "red square button blank background plate, dark stepped border and coral top-left highlight; no X or text baked in"),
 "Card": ((256,256), [32,32,224,224], "navy square item card, stepped corners, blue rim, square studs only in inner border, uniform dark center"),
 "OddsStrip": ((512,96), [24,24,488,72], "thin violet odds strip with dark stepped outline, square inset border, empty uniform dark-violet middle"),
}
for name, (size, rect, subject) in FRAME_SPECS.items():
    add("Frames", name, "Front-on flat nine-slice UI skin: " + subject + ". No perspective, no shadows outside the border. "
        "Center must be flat uniform color so it can stretch; all studs remain in edge bands. Transparent outside the silhouette.", size, slice_center=rect)
add("Unbox", "Background", "Front-on wide navy unboxing background plate with stepped outer corners, indigo inset, "
    "cyan corner studs and spacious EMPTY dark central area. No knives, titles or letters.", (1024,512), slice_center=[48,48,976,464])
add("Unbox", "ReelFrame", "Front-on very wide horizontal voxel reel border. EMPTY TRANSPARENT central opening for scrolling "
    "items, thick stepped navy/cyan outline, one bright gold downward pointer at the exact TOP CENTER and one small "
    "upward gold pointer at bottom center. No item cards or labels.", (1024,256))
for rarity, color in PALETTE.items():
    add("GlowBackplates", rarity, f"Flat front-on {rarity} rarity backplate in RGB {color}. Four nested stepped square/octagonal "
        "block outlines with decreasing opacity, a subtly tinted transparent center, no object or text. Voxel glow made "
        "of flat alpha bands, not smoke or round bloom. A knife will be placed in front.")
    add("Badges", rarity, f"Small front-on {rarity} rarity label plate, main RGB {color}, thick near-black stepped border, "
        "top-left bright inset highlight, EMPTY flat center reserved for a separate text label. No words or letters.", (256,96), slice_center=[24,24,232,72])
assert len(assets) == 82
for entry in assets:
    for key in ("File", "Reference"):
        (OUT / entry[key]).parent.mkdir(parents=True, exist_ok=True)
(OUT / "catalog.json").write_text(json.dumps(dict(Version=1, Assets=assets, RarityColors=PALETTE), indent=2), encoding="utf-8")
print(f"Prepared {len(assets)} asset briefs across {len(set(x['Group'] for x in assets))} groups")
