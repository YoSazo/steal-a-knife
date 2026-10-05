// Entry point on Render: connect to Neon (runs the schema), serve, and pull Roblox's own analytics
// every 6 hours when ROBLOX_API_KEY is set.
import { env } from "./env.js";
import { connect } from "./db.js";
import { client } from "./roblox.js";
import { createApp } from "./server.js";
import { syncAll } from "./sync.js";

await connect();

let roblox = null;
if (env("ROBLOX_API_KEY")) {
  const rb = client({ apiKey: env("ROBLOX_API_KEY") });
  try {
    const universeId = env("ROBLOX_UNIVERSE_ID") || (await rb.universeOf(env("ROBLOX_PLACE_ID", "119376992331481")));
    roblox = { rb, universeId, running: false };
    const run = () => {
      if (roblox.running) return;
      roblox.running = true;
      syncAll(rb, universeId)
        .then((result) => console.log("roblox sync", result))
        .catch((err) => console.error("roblox sync", err))
        .finally(() => (roblox.running = false));
    };
    setTimeout(run, 30_000);
    setInterval(run, 6 * 3600_000);
  } catch (err) {
    console.error("Roblox setup failed (analytics sync off):", err.message);
  }
}

const port = parseInt(process.env.PORT || "3000", 10);
createApp({ roblox }).listen(port, () => console.log(`analytics listening on :${port}`));
