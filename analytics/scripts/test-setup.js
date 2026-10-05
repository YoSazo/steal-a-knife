// `npm run setup` against a fake Roblox + ingest server (scripts/fake-roblox.js), on a copy of the
// two game files it edits: everything gets created, ids land in the Luau, the secret decrypts, and a
// second run changes nothing.
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import sodium from "libsodium-wrappers";

await sodium.ready;
const repo = fileURLToPath(new URL("../../", import.meta.url));
const temp = mkdtempSync(join(tmpdir(), "sak-setup-"));
for (const file of ["src/shared/Config/Monetization.luau", "src/server/Services/Analytics.luau"]) {
  mkdirSync(join(temp, file, ".."), { recursive: true });
  copyFileSync(join(repo, file), join(temp, file));
}
const keys = sodium.crypto_box_keypair();
const log = join(temp, "requests.log");
const env = {
  ...process.env,
  SETUP_ROOT: temp,
  ROBLOX_API_KEY: "rbx",
  ROBLOX_PLACE_ID: "119376992331481",
  ROBLOX_UNIVERSE_ID: "",
  INGEST_URL: "https://stats.example.com/",
  INGEST_KEY: "secret123",
  DATABASE_URL: "", // (a real database isn't part of this test: that step reports itself as missing)
  FAKE_PK: sodium.to_base64(keys.publicKey, sodium.base64_variants.ORIGINAL),
  FAKE_LOG: log,
  FAKE_STATE: join(temp, "state.json"),
};
const run = () => {
  try {
    return execFileSync(process.execPath, ["--import", "./scripts/fake-roblox.js", "scripts/setup.js"], { env, encoding: "utf8" });
  } catch (err) {
    return err.stdout; // exits 1 because DATABASE_URL is missing: expected here
  }
};

const failures = [];
const check = (ok, what) => ok || failures.push(what);

const first = run();
const requests = readFileSync(log, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const luau = readFileSync(join(temp, "src/shared/Config/Monetization.luau"), "utf8");
const analytics = readFileSync(join(temp, "src/server/Services/Analytics.luau"), "utf8");
const state = JSON.parse(readFileSync(join(temp, "state.json"), "utf8"));
const original = readFileSync(join(repo, "src/shared/Config/Monetization.luau"), "utf8");
const entries = (original.match(/Key = "/g) || []).length;

check(analytics.includes('local URL = "https://stats.example.com/ingest"'), "Analytics.luau URL not set");
check(!/Id = 0,/.test(luau), "some store ids are still 0");
check(/Key = "VIP",\s*Id = 999,/.test(luau), "existing pass VIP not matched by name");
const creates = requests.filter((r) => r.method === "POST" && /(developer-products|game-passes)$/.test(r.path));
check(creates.length === entries - 1, `created ${creates.length}, expected ${entries - 1}`);
check(creates.every((r) => r.body.isForSale === "true" && Number(r.body.price) > 0), "a create without price / for sale");
check(requests.filter((r) => r.method === "PATCH").length === creates.length, "descriptions not set on every created item");
const secret = state.secrets.find((s) => s.id === "ingest_key");
check(secret && secret.domain === "stats.example.com" && secret.key_id === "kid-1", "secret missing / wrong domain");
if (secret) {
  const opened = sodium.crypto_box_seal_open(sodium.from_base64(secret.secret, sodium.base64_variants.ORIGINAL), keys.publicKey, keys.privateKey);
  check(sodium.to_string(opened) === "secret123", "secret doesn't decrypt to INGEST_KEY");
}
check(first.includes("Ingest server answers") && first.includes("Roblox Analytics API works"), "ingest / analytics checks didn't pass");
check(first.includes("Ads Manager API (optional)"), "ads warning missing");

// Second run: nothing new gets created
const before = requests.length;
const second = run();
const again = readFileSync(log, "utf8").trim().split("\n").slice(before).map((l) => JSON.parse(l));
check(!again.some((r) => r.method === "POST" && /(developer-products|game-passes)$/.test(r.path)), "second run created products again");
check(second.includes(`${entries} of ${entries} wired`), "second run doesn't report everything wired");

rmSync(temp, { recursive: true, force: true });
if (failures.length) {
  console.error(first);
  console.error("FAILED:\n" + failures.join("\n"));
  process.exit(1);
}
console.log(`ok: setup created ${creates.length} store items, matched 1, wired the secret and URL; second run idempotent`);
