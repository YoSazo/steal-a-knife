# Codex prompt: the big chunky UI (Steal An Egg size and style)

Repo `C:\Users\samat\StealAKnife`, branch `main-eftg5w`. Read `CLAUDE.md` first (the One Loop and
show-don't-tell rules). The owner compared our screen with Steal An Egg's at the same 1920x1030:
theirs is about **twice our size** (their Speed/Cash numbers are ~50 px tall with big icons, their
buttons ~180x70; ours ~30 px and ~115x45), has no dark see-through bars, and every icon is one
glossy cartoon set. Ours got small because it was tuned to fit a 640x320 phone.

Do the steps in order. Test each in Studio at 1920x1080 AND the owner's 640x320 phone preset.

## 1. One size rule (code, do first)

Size the whole HUD by **screen height**, not fixed pixels: one `UIScale` on the HUD root (Ui.root /
Ui.feedback already have `Ui.Scale`) = `viewport.Y / 720`, clamped so a 1080p PC gets ~1.5x and a
phone stays at least the size it is now. Then tune the design sizes to match Steal An Egg on PC:
Speed/Cash numbers ~50 px with ~64 px icons, left buttons ~180x70, the top line ~44 px.
Phone tap targets stay at least 44 px. Make the **whole** Speed and Cash readout the tap target
for the shop (not the small + inside it, which the thumbstick hits), and keep it clear of the
dynamic thumbstick area.

## 2. No dark bars (code)

The objective line, the round timer and the SURVIVE ladder line sit on dark see-through bands.
Remove the bands: big white text with a thick black outline (UIStroke 3-4 px at 1080p), floating
over the world, one line at a time (Steal An Egg's "You earn $4.2B/Day offline!").

## 3. Generate the art (image gen), then trace it

Generate each picture with the prompts below, keep the PNGs in `assets/ui/cartoon-pack-v2/`, then:
- **flat shapes that must stay sharp at any size** (buttons, plates, badges, frames): trace them into
  merged native rectangles with the method in `tools/build_boss_titles.py` (`trace(path, width,
  colors)`), like the boss titles and the knife faces;
- **detailed icons** (shoe, cash, cart, book, coffin...): upload with Open Cloud
  (`tools/upload_model.py` / the image upload you used for cartoon-pack-v1) and put the ids in
  `src/shared/Config/CartoonArt.luau`.
Run `tools/outline_icon.py` on icons that need a cleaner outer outline. No text baked into icons
(words stay native so they scale and can change); titles may bake text like the lair signs do.

### Style (paste this in front of every prompt)

> Roblox simulator game UI icon, Steal An Egg / Pet Simulator style. Chunky, glossy cartoon, bright
> saturated colours, soft top-left highlight and a darker bottom-right shade, a thick even black
> outline (about 6% of the icon's width) around the whole silhouette, slight 3/4 view, playful and
> bold, readable at 40 px. Centered, filling ~85% of the frame, transparent background, 1024x1024
> PNG, no text, no watermark, no drop shadow outside the outline.

### Prompts

| Name (file) | Prompt (after the style line) | Used by |
|---|---|---|
| `Speed` | A blue and white running sneaker with motion lines and a little wing on the heel, mid-stride. **No plus badge.** | Speed readout (client/Hud), shoe showers (Transitions), prize cards |
| `SpeedPlus` | A round bright green button with a fat white plus sign. | the Speed/Cash shop tap hint (separate from the icon) |
| `Cash` | A thick stack of green dollar bills with a gold band, two bills fanned on top. | Cash readout, bills flying in (Ui.FlyIn) |
| `Shop` | A red shopping cart heaped with gold coins and a gem. | Shop button |
| `Index` | A chunky open blue book with a gold bookmark and a sparkle. | Index button |
| `Knives` | A small dark wooden coffin with a glowing cartoon knife character peeking out. | My Knives button |
| `More` | Three fat rounded purple bars stacked (a menu icon), glossy. | More button |
| `Codes` | A gold ticket with a star punched in it. | More → Codes tile |
| `Gift` | A pink gift box with a big gold bow, lid popping. | Free Gift card (client/GiftCard) |
| `Murderer` | A red cartoon knife, blade up, with a little shine. | role reveal, round card |
| `Sheriff` | A gold cartoon revolver with a sheriff star on the grip. | role reveal, round card |
| `Innocent` | A light blue shield with a white heart. | role reveal |
| `RoundTimer` | A crescent moon with a small red knife hanging from it. | the round countdown (bottom right / top) |
| `Ready` | A bright green round badge with a white check mark, bouncing pose. | READY coffins (client/Coffins), My Knives badge |
| `Golden` | A gold star with a running sneaker in it. | Golden Round event |
| `Luck` | A four-leaf clover, bright green, sparkling. | Luck Storm event |
| `SpeedRush` | A sneaker with fire trails. | Speed Rush event |
| `ButtonGreen` / `ButtonBlue` / `ButtonPurple` / `ButtonGold` / `ButtonRed` | A wide rounded rectangle button plate in that colour, glossy top half, thick black outline, flat face (9-slice friendly: plain middle, all detail in the corners and edges). 1024x384. | every button (trace these) |
| `Badge` | A red circle notification bubble with a white rim, plain middle. 256x256. | Shop / Index / My Knives badges (trace) |
| `CardFrame` | A dark purple rounded card with a gold rim and a glossy top edge, plain middle (9-slice). 1024x640. | VS card, prize card, kill card (trace) |

## 4. The round shoe pickups (Blender, not a sticker)

The pickups on the round floor reuse the HUD `Speed` icon, + badge and all, so they read as UI and
are easy to miss. Make a chunky **3D sneaker** prop (`blender/scripts/make_props.py` → upload →
`Config/PropMeshes`, `Props.Build`), about 3 studs, spinning and bobbing, with a soft light column
above it like Steal An Egg's coins. Keep the client pickup prediction (`trackCoin`/`flyCoinIn`).

## 5. Fewer words in the world

Per pen character: show `$/s` always, name + rarity only within ~25 studs (or only on the best one).
One aura per character, not stacked. Keep the money pops.

Commit each step separately; record what you tested in `docs/PLAN.md` Status.
