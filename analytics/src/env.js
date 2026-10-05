// One env file for everything: the repo's root .env (also used by tools/upload_model.py), then
// analytics/.env. Real environment variables (Render) always win.
import { existsSync, readFileSync } from "node:fs";

for (const file of [new URL("../../.env", import.meta.url), new URL("../.env", import.meta.url)]) {
  if (!existsSync(file)) continue;
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && match[2] !== "") process.env[match[1]] ??= match[2].replace(/^["']|["']$/g, "");
  }
}

export const env = (name, fallback = "") => process.env[name] || fallback;
