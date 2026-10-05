// Run SQL against the live analytics database: npm run q -- "select event, count(*) from events group by 1"
// Reads DATABASE_URL from the root .env (then analytics/.env). Goes over HTTPS (Neon's serverless
// driver), so it works on networks that block Postgres' own port.
import { neon } from "@neondatabase/serverless";
import "../src/env.js";

const sql = process.argv.slice(2).join(" ");
if (!sql) {
  console.error('usage: npm run q -- "select ..."');
  process.exit(1);
}
const rows = await neon(process.env.DATABASE_URL).query(sql);
console.table(rows);
