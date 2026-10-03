# Illustrated menu direction

`concept.png` is the approved Shop / Knife Index / Rebirth design reference.
`menu-icons.png` and `menu-knives.png` are transparent sprite atlases generated with
the built-in image-generation tool. The menu uses native Roblox controls and live
game data; the concept image is not pasted over the interface.

## Artwork prompts

Icons: Extract and redraw the concept's gold, purple, and red wooden locked chests;
cash bundle; open book; red/cyan rebirth arrows; lightning bolt; flexed arm; and
clover. Preserve bold black outlines and saturated illustrated shading. Arrange
the nine isolated sprites in a regular 3-by-3 grid on transparent alpha, without
text or UI frames.

Knives: Transform the existing 24 knife renders into the concept's crisp outlined
illustrated style, preserving their silhouettes and recognizable colors. Arrange
24 isolated sprites in a regular 6-by-4 grid on transparent alpha, with diagonally
oriented blades, no labels, and no UI backgrounds.

Atlas asset IDs and the delivered texture dimensions are in
`src/shared/Config/MenuArtwork.luau`. Roblox resized the uploads; use the delivered
dimensions for `ImageRectOffset` / `ImageRectSize`, not the local PNG dimensions.
The illustrated assets are separate from the hotbar and world knife renders.

The same theme now covers the Shop / Index / More / Slow HUD controls, free-chest
notice, compact More and Upgrades menus, and world-space sell signs and collection
pads. Utility symbols use native outlined shapes; chest, cash, knife, and rebirth
icons reuse the illustrated atlases. Cash-pad amounts retain their suffix on one
line. The world signs are built by `shared/SignTheme.luau` without changing their
click detectors or collection hitboxes.

## Verification

- Client and server initialized successfully in an isolated unpublished Studio
  place, using temporary player data.
- Index discovered-state rendering and black silhouettes checked visually.
- Claiming the Rusty Shank reward updated cash and collection state, then disabled
  the claim action. The Legendary filter displayed exactly its three knives.
- Shop tab switching verified through actual GUI input.
- Rebirth displayed the real income/training/luck bonuses and disabled its action
  at $1.5B of the $2B requirement.
- Corrected atlas coordinates after visual inspection exposed Roblox resizing.
- Changed modules pass Selene and Luau type analysis; the Rojo project builds.
- More and Upgrades reviewed in the isolated Studio viewport. An upgrade click
  changed TreadmillLevel from 1 to 2, deducted $15K, and displayed the next $100K
  tier. Notification counts now have a separate bubble border and text outline.
- World collection check passed: walking onto the cash pad paid its $450 balance.
  The server's amount text contains no newline. The close-up world capture did
  not complete, so full-size inspection of the world signs remains unverified.
- Full-size desktop visual review was interrupted when the user stopped Computer
  Use. Final pixel equivalence at desktop size remains unverified.

`ui-preview.rbxlx` is a disposable build of the current working tree, including
the other sessions' changes. It is not a published release. `sourcemap.json` is
only the analysis map for these checks.
