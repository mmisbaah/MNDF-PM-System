export type DatabasePoolConfiguration = {
  max: number;
  connectionTimeoutMillis: number;
  idleTimeoutMillis: number;
  maxLifetimeSeconds: number;
  statement_timeout: number;
  query_timeout: number;
};

type Environment = Record<string, string | undefined>;

function boundedInteger(env: Environment, name: string, fallback: number, minimum: number, maximum: number) {
  const raw = env[name];
  if (raw === undefined || raw === "") return fallback;
  if (!/^[0-9]+$/.test(raw)) throw new Error(`${name} must be an integer`);
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`${name} must be between ${minimum} and ${maximum}`);
  }
  return value;
}

export function databasePoolConfiguration(env: Environment = process.env): DatabasePoolConfiguration {
  const configuration = {
    max: boundedInteger(env, "DB_POOL_MAX", 15, 2, 50),
    connectionTimeoutMillis: boundedInteger(env, "DB_CONNECT_TIMEOUT_MS", 5_000, 1_000, 30_000),
    idleTimeoutMillis: boundedInteger(env, "DB_IDLE_TIMEOUT_MS", 30_000, 10_000, 300_000),
    maxLifetimeSeconds: boundedInteger(env, "DB_MAX_LIFETIME_SECONDS", 1_800, 60, 7_200),
    statement_timeout: boundedInteger(env, "DB_STATEMENT_TIMEOUT_MS", 15_000, 1_000, 120_000),
    query_timeout: boundedInteger(env, "DB_QUERY_TIMEOUT_MS", 20_000, 1_000, 150_000),
  };
  if (configuration.query_timeout <= configuration.statement_timeout) {
    throw new Error("DB_QUERY_TIMEOUT_MS must be greater than DB_STATEMENT_TIMEOUT_MS");
  }
  return configuration;
}
