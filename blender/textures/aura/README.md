# Billowing Knife Auras

Original artwork, built from animated Blender curve contours rather than Roblox's default Fire. The reference informed the broad rolling silhouette, bright inner lobes and separate smoke curls; its pixels and assets are not copied.

Render the three padded 1024px, 8x8 RGBA atlases:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 4.5/blender.exe' --background --factory-startup --python blender/scripts/billowing_flipbooks.py
```

Upload through Studio MCP `upload_image`, then update `src/shared/Config/KnifeAuraArt.luau`. The ember atlas remains 4x4. Outer, core and smoke use 64 looping frames with frame blending.

`KnifeAuraVariants` contains 50 color/motion presets: ten palettes times five motion profiles. Six independent color pairs control Outer, Core, Tongues, Smoke, Glow and Embers. All presets share textures; there are not 50 additional atlas downloads. Display knives choose a stable preset from knife, mutation and size, ignoring combat perk. No stats or saved item strings are changed.

Recombine layers without modifying a shared preset:

```lua
local Variants = require(Shared.Config.KnifeAuraVariants)
local Aura = require(Shared.KnifeAura)
local mixed = Variants.Compose("volcano-rolling", {
    Outer = "glacier-rolling",
    Core = "solar-boiling",
    Smoke = "phantom-floating",
}, {
    Embers = { Start = Color3.fromRGB(255, 235, 180), Finish = Color3.fromRGB(255, 90, 140) },
})
Aura.Mount(anchor, power, ceilingClearance, mixed)
```

Run `tests/KnifeAura.studio.luau` and `tests/KnifeDetails.studio.luau` as temporary Studio server Scripts. They are not mapped into the published experience. Remove the fixtures after verification. The aura audit includes a strength/ceiling comparison and ten palette samples far outside the map.
