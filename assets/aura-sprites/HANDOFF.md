# Ten aura sprites — art ready for integration

Delivered PNGs, uploaded image IDs in `src/shared/Config/Textures.luau` under `AuraSprites`, source PNGs, deterministic `tools/make_aura_sprites.py`, `preview.png`, four animated preview GIFs, `manifest.json`, `uploads.json`, and native Studio captures under `studio/`. Existing `Textures.Glow` entries are unchanged. KnifeHaze and gameplay wiring were not edited; Claude integrates the layers.

| Sprite | Export | Playback |
| --- | --- | --- |
| SlimeDrip | 1024×1024, sixteen 256×256 cells | Grid4x4 / Loop |
| Spiral | 256×256 | Single |
| LightningShard | 256×256 | Single |
| LightningBolt | 1024×1024, sixteen 256×256 cells | Grid4x4 / OneShot |
| SmokeWisp | 1024×1024, sixteen 256×256 cells | Grid4x4 / Loop |
| Star | 256×256 | Single |
| Ember | 512×512, four 256×256 cells | Grid2x2 / Loop |
| RainbowArc | 512×256 | Single |
| ShockRing | 256×256 | Single |
| LightRays | 512×512 | Single |

All output pixels have white RGB, including fully transparent pixels. Grayscale volume from the generated sources is carried in alpha, so tinting cannot expose a dark RGB fringe. Alpha is straight, never premultiplied. Every cell has at least 8% empty padding. Generated shapes are cropped and centred once; animation samples a fixed 128,128 pivot rather than recentring each frame.

The previously generated slime was inspected: it was a single 1024×1536 source, not a flipbook, with dark RGB in transparent pixels. Its source drawing was usable. The exporter replaces those RGB values with white and constructs the wobble/stretch/pinch/drop animation; the original remains in `sources/SlimeDrip.png`. Other generated sources are Spiral, LightningShard, LightningBolt, SmokeWisp, Ember and RainbowArc. Star, ShockRing and LightRays are procedural, as permitted by the brief.

The slime/smoke/ember animations use periodic functions. Wrap-around frame differences are comparable to internal steps and verified by the script. Lightning flashes in frames 1–4, flickers/branches in 5–12 and fades to a fully transparent last frame. Frames are read left-to-right then top-to-bottom. Loop modes and grid sizes are included in the texture config; suggested demo loop FPS is 8. OneShot uses particle lifetime (1.6 seconds in the review) for its reveal/fade.

`preview.png` shows every finished asset (full grids for flipbooks) over black, grass RGB 48,146,30, and violet RGB 195,55,255 over grass. Individual `studio/<Name>.png` and `studio/all-playing.png` show actual ParticleEmitters with uploaded textures. All ten underlying assets are Image type and preloaded with Success. Flipbooks were configured with their actual Grid4x4/Grid2x2 and Loop/OneShot modes. Fixed canvases, padding and wrap continuity passed; no per-frame crop jitter is introduced. `tools/stage_aura_review.luau` is temporary Studio review tooling, not a runtime game script.

Bloom/light emission affects the in-game tint, so the Studio images can look brighter than the flat preview. Smoke was deliberately tinted dark for the review. Configure the final particle sizes, rates, rotations and culling in KnifeHaze; these textures supply shapes, not the full aura behaviour. RainbowArc is grayscale: any spatial rainbow layering is a wiring choice, not colours baked into this PNG.

Checks: exact sizes/frame counts, RGBA, white RGB at all alpha values, padding, visible frame variation, periodic wrap continuity, deterministic SHA256 regeneration, Studio content loading and emitter mode checks. Selene, StyLua, Luau type analysis and Rojo build passed. Temporary review objects were removed and camera restored. Studio Play was stopped; no Lighting settings were changed.

Built-in imagegen prompt set: white/grayscale-only standalone shapes on transparent backgrounds, chunky toy aura silhouettes, clean edges, no text/scene/dark outline; a glossy drip, tapered 2.5-turn spiral, angular faceted shard, branched zig-zag bolt, curling billowing wisp, flame tongue and broad shallow arc. Original generated sources are saved in the project. Cleanup and animation are fully reproducible from them.
