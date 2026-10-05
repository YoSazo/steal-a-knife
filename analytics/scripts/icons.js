// Puts a real icon on every Robux product and pass (Roblox shows a grey cube until one is set):
// Codex's voxel art from assets/ (the same pictures the in-game Shop draws). `npm run icons`;
// `npm run icons -- SpeedPotion VIP` does just those. Reads the root .env.
import { existsSync, readFileSync } from "node:fs";
import { env } from "../src/env.js";
import { client } from "../src/roblox.js";

const ROOT = new URL("../../", import.meta.url);
const HUD = "assets/voxel-ui/png/Hud/";
const CASES = "assets/voxel-ui/png/Cases/";
const BLOCKS = "assets/voxel-ui/png/LuckyBlocks/";
const ICONS = "assets/voxel-icons-2/png/";

// Store key -> picture
const ICON = {
  DoubleCash: HUD + "Cash.png",
  VIP: ICONS + "VIP.png",
  FastWheel: ICONS + "Wheel.png",
  PhantomTrail: ICONS + "Trail.png",
  AutoCollect: HUD + "Cash.png",
  Luck: CASES + "Legendary.png",
  OfflinePlus: ICONS + "Rebirth.png",
  ExtraFloor: ICONS + "Floor.png",
  Titan: ICONS + "Health.png",
  Starter: ICONS + "Gift.png",
  CashSmall: HUD + "Cash.png",
  CashMedium: HUD + "Cash.png",
  CashBig: HUD + "Cash.png",
  CaseEpic: CASES + "Epic.png",
  CaseLegendary: CASES + "Legendary.png",
  CaseGodly: CASES + "Godly.png",
  LuckyMythic: BLOCKS + "Mythic.png",
  LuckyGodly: BLOCKS + "Godly.png",
  LuckyCosmic: BLOCKS + "Cosmic.png",
  Spins3: HUD + "Spin.png",
  Spins10: HUD + "Spin.png",
  LuckPotion: CASES + "Legendary.png",
  LuckPotionBig: CASES + "Mythic.png",
  GiftLuckyMythic: ICONS + "Gift.png",
  GiftLuckyGodly: ICONS + "Gift.png",
  GiftSpins10: ICONS + "Gift.png",
  GiftLuckPotion: ICONS + "Gift.png",
  SpeedPotion: HUD + "Speed.png",
  SpeedPotionBig: HUD + "Speed.png",
  CashPotion: HUD + "Cash.png",
  CashPotionBig: HUD + "Cash.png",
  TrainingPotion: ICONS + "Wheel.png",
  Reroll3: HUD + "Powers.png",
  Reroll10: HUD + "Powers.png",
  CollectSession: HUD + "Cash.png",
  Escape3: ICONS + "Padlock.png",
  Escape10: ICONS + "Padlock.png",
  Insurance3: ICONS + "Shield.png",
  Insurance10: ICONS + "Shield.png",
  HeatRefill: HUD + "Heat.png",
  BossRestock: HUD + "Merchant.png",
  OfflineDouble: HUD + "Cash.png",
  StreakSave: HUD + "FreeChest.png",
  HealthBoost: ICONS + "Health.png",
  Mount: ICONS + "Floor.png",
  ServerLuck: CASES + "Godly.png",
  ChestRefill: HUD + "FreeChest.png",
  BloodMoon: CASES + "Mythic.png",
};

// (the grey cube has a real asset id too, so "already has an icon" can't be told apart: upload all,
// or only the keys named on the command line)
const only = process.argv.slice(2).filter((a) => !a.startsWith("-"));
const all = true;
const apiKey = env("ROBLOX_API_KEY");
if (!apiKey) throw new Error("ROBLOX_API_KEY missing in .env");
const rb = client({ apiKey });
const universeId = env("ROBLOX_UNIVERSE_ID") || (await rb.universeOf(env("ROBLOX_PLACE_ID", "119376992331481")));

// Store keys and ids from the game's own catalog
const text = readFileSync(new URL("src/shared/Config/Monetization.luau", ROOT), "utf8");
const productsAt = text.indexOf("Monetization.Products = {");
const entries = [...text.matchAll(/Key = "(\w+)",\s*Id = (\d+),/g)].map((m) => ({
  key: m[1],
  id: Number(m[2]),
  kind: m.index > productsAt ? "product" : "pass",
}));

const [products, passes] = await Promise.all([rb.listProducts(universeId), rb.listPasses(universeId)]);
const iconOf = new Map([
  ...products.map((p) => [`product:${p.productId}`, p.iconImageAssetId]),
  ...passes.map((p) => [`pass:${p.gamePassId}`, p.iconAssetId]),
]);

let done = 0;
let skipped = 0;
const failed = [];
for (const entry of entries) {
  const file = ICON[entry.key];
  if (only.length && !only.includes(entry.key)) continue;
  if (!entry.id || !file) {
    failed.push(`${entry.key}: ${entry.id ? "no icon mapped" : "no id"}`);
    continue;
  }
  if (!all && iconOf.get(`${entry.kind}:${entry.id}`)) {
    skipped++;
    continue;
  }
  const path = new URL(file, ROOT);
  if (!existsSync(path)) {
    failed.push(`${entry.key}: missing ${file}`);
    continue;
  }
  const form = { imageFile: new Blob([readFileSync(path)], { type: "image/png" }) };
  try {
    if (entry.kind === "product") await rb.updateProduct(universeId, entry.id, form);
    else await rb.updatePass(universeId, entry.id, form);
    done++;
    console.log(`✓ ${entry.key}`);
  } catch (err) {
    failed.push(`${entry.key}: ${err.message}`);
  }
  await new Promise((r) => setTimeout(r, 400));
}
console.log(`\n${done} icons uploaded, ${skipped} already had one${failed.length ? `, ${failed.length} failed:\n  ${failed.join("\n  ")}` : ""}`);
process.exit(failed.length ? 1 : 0);
