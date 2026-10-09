# UI assets and Blender Speed coin

Project files:
- `blender/speed_coin.blend` and `blender/scripts/make_props.py`: blue token, white rim, raised sneaker on both faces. Export with Blender 4.5: `blender -b --factory-startup --python blender/scripts/make_props.py -- SpeedCoin`.
- `blender/previews/speed_coin.png`: preview; mesh model asset 88760594831841, parts in `Config/PropMeshes`.
- `assets/ui/cartoon-pack-v2/Speed.png`: generated clean shoe icon (no +). Decal 80908349607922; image 74716351276486.
- `inferno-banner.png`: Decal 109982635719936; image 123834927187003.
- `speed-gift-bag.png`: Decal 123907592022770; image 74015651442016.
- `like-instructions.png`: exact owner-supplied screenshot, copied unchanged. Decal 93542820133062; image 109848101855793.
- `gold-frame.png`: generated flat frame; `gold-frame-trace.json` / `gold-frame-trace.png` / `Config/FeaturedFrameTrace` are traced native rectangles. Regenerate with `python tools/build_featured_frame.py`.

The new illustration assets used the built-in imagegen tool, not the API fallback. Original generated files remain in Codex's generated_images directory; project copies live here. The attached Like screenshot was uploaded unchanged. Model/image assets were granted Use permission to universe 10768911594 using Roblox's [asset permissions API](https://create.roblox.com/docs/cloud/reference/features/assets).

## Inferno banner (inferno-banner.png)

Create a polished wide landscape 3:1 background illustration for a Roblox children's game featured knife-coffin shop card. Original cheerful cartoon style: chunky toy shapes, thick dark outlines, warm glowing lava in an Inferno cavern, glowing amber crystals and blue sparkles at the edges, dark purple rock background. At far left a large friendly closed wooden coffin-shaped treasure box with gold bands and a small golden knife emblem, tilted slightly, brilliant warm halo. The central and right 70 percent must be calm dark purple negative space for live UI overlays. No characters or pets. No words, no letters, no numbers, no buttons, no frame. Bright magical treasure feeling, not scary, highly legible silhouette at small mobile size. Landscape wide 3:1 composition, full bleed opaque.

## Gold frame (gold-frame.png)

Create one isolated flat 2D cartoon UI rectangular frame for a Roblox game featured shop banner, wide 3:1 shape, front orthographic view. Thin golden beveled rails with very bold near-black outlines, angular bright gold corner brackets and tiny cyan diamond studs at the four corners. Friendly toy treasure aesthetic. Rails occupy only the outer 5 percent, the entire center is truly transparent, exterior is also transparent. Square corners, perfectly straight edges, no texture, no gradients, no shadows, no glow, no words, no letters, no numbers. Use a small palette of solid gold yellow, pale yellow, orange, near-black, cyan. Designed to be traced into sharp native rectangles.

## Speed gift bag (speed-gift-bag.png)

One isolated cartoon game icon on a genuinely transparent background: a big blue sports duffel bag overflowing with chunky cyan and royal-blue sneakers with bright white soles and white laces. White lightning emblem on the front of the bag, small gold zipper, bold thick black outline, glossy toy highlights, friendly vibrant Roblox children's game aesthetic. Three-quarter front view, centered fills 85% of square canvas, whole bag and shoes inside frame. No text, no numbers, no plus badge, no border, no background or shadow. This is a free Speed reward icon, readable at mobile size.
