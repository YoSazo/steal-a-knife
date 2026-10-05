// Postgres access: Neon in production (DATABASE_URL), an in-memory PGlite for scripts/test.js.
import { readFileSync } from "node:fs";
import pg from "pg";

let backend = null;

export async function connect(options = {}) {
  if (options.pglite) {
    backend = { kind: "pglite", db: options.pglite };
  } else {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error("DATABASE_URL is not set");
    const pool = new pg.Pool({
      connectionString: url,
      ssl: url.includes("localhost") ? false : { rejectUnauthorized: true },
      max: 5,
    });
    backend = { kind: "pg", db: pool };
  }
  const schema = readFileSync(new URL("./schema.sql", import.meta.url), "utf8");
  await exec(schema);
}

// Several statements, no parameters (the schema)
export async function exec(sql) {
  if (backend.kind === "pglite") return backend.db.exec(sql);
  return backend.db.query(sql);
}

// One statement with $1.. parameters -> rows
export async function query(sql, params = []) {
  const result = await backend.db.query(sql, params);
  return result.rows;
}
