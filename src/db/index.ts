import { drizzle } from "drizzle-orm/node-postgres/driver";
import { Pool } from "pg";
import { databasePoolConfiguration } from "./config";

const databaseUrl = process.env.DATABASE_URL;

if (!databaseUrl) {
  throw new Error("DATABASE_URL is required");
}

const globalForDb = globalThis as typeof globalThis & {
  __arenaNextJsPostgresqlPool?: Pool;
};

export const pool =
  globalForDb.__arenaNextJsPostgresqlPool ??
  new Pool({
    connectionString: databaseUrl,
    ...databasePoolConfiguration(),
    application_name: "performance-tracker-web",
  });

pool.on("error", () => {
  console.error("PostgreSQL pool emitted an idle-client error");
});

if (process.env.NODE_ENV !== "production") {
  globalForDb.__arenaNextJsPostgresqlPool = pool;
}

export const db = drizzle(pool);
