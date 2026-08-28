import test from "node:test";
import assert from "node:assert/strict";
import { databasePoolConfiguration } from "../src/db/config";

test("database pool uses bounded pilot defaults", () => {
  assert.deepEqual(databasePoolConfiguration({}), {
    max: 15,
    connectionTimeoutMillis: 5_000,
    idleTimeoutMillis: 30_000,
    maxLifetimeSeconds: 1_800,
    statement_timeout: 15_000,
    query_timeout: 20_000,
  });
});

test("database pool accepts guarded production overrides", () => {
  const result = databasePoolConfiguration({
    DB_POOL_MAX: "20",
    DB_CONNECT_TIMEOUT_MS: "6000",
    DB_IDLE_TIMEOUT_MS: "45000",
    DB_MAX_LIFETIME_SECONDS: "1200",
    DB_STATEMENT_TIMEOUT_MS: "10000",
    DB_QUERY_TIMEOUT_MS: "12000",
  });
  assert.equal(result.max, 20);
  assert.equal(result.query_timeout, 12_000);
});

test("database pool rejects unsafe limits and timeout ordering", () => {
  assert.throws(() => databasePoolConfiguration({ DB_POOL_MAX: "0" }), /between 2 and 50/);
  assert.throws(() => databasePoolConfiguration({ DB_POOL_MAX: "many" }), /must be an integer/);
  assert.throws(
    () => databasePoolConfiguration({ DB_STATEMENT_TIMEOUT_MS: "20000", DB_QUERY_TIMEOUT_MS: "20000" }),
    /must be greater/,
  );
});
