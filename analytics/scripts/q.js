// Run SQL against the live analytics database: npm run q -- "select event, count(*) from events group by 1"
// Reads DATABASE_URL from the environment or analytics/.env (gitignored).
import pg from "pg";

import "../src/env.js"; // the root .env, then analytics/.env
const sql = process.argv.slice(2).join(" ");
if (!sql) {
  console.error('usage: npm run q -- "select ..."');
  process.exit(1);
}
const client = new pg.Client({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: true } });
await client.connect();
try {
  const result = await client.query(sql);
  console.table(result.rows);
} finally {
  await client.end();
}
