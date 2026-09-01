import { isAbsolute, resolve } from "node:path";
import { readFileSync } from "node:fs";
import { parseEnv } from "node:util";

let environment = process.env;
if (process.argv.length > 2) {
  if (process.argv.length !== 4 || process.argv[2] !== '--config-file') {
    console.error('Usage: validate-production-env.mjs [--config-file <path>]');
    process.exit(1);
  }
  try {
    // Deliberately do not merge shell variables: validate the candidate itself.
    environment = parseEnv(readFileSync(process.argv[3], 'utf8'));
  } catch {
    console.error('Production configuration file could not be read or parsed.');
    process.exit(1);
  }
}

const requiredSecrets = ["AUTH_JWT_SECRET", "GRIEVANCE_CRON_SECRET", "EVIDENCE_SCANNER_SECRET", "OPERATIONS_MONITOR_SECRET", "AUDIT_EXPORT_HMAC_KEY"];
const placeholder = /replace-|change-me|example|password/i;
const failures = [];
const values = [];
if (environment.NODE_ENV !== "production") failures.push("NODE_ENV must be production");

function boundedInteger(name, fallback, minimum, maximum) {
  const raw = environment[name];
  if (raw === undefined || raw === "") return fallback;
  if (!/^[0-9]+$/.test(raw)) { failures.push(`${name} must be an integer`); return fallback; }
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) failures.push(`${name} must be between ${minimum} and ${maximum}`);
  return value;
}
boundedInteger("DB_POOL_MAX", 15, 2, 50);
boundedInteger("DB_CONNECT_TIMEOUT_MS", 5_000, 1_000, 30_000);
boundedInteger("DB_IDLE_TIMEOUT_MS", 30_000, 10_000, 300_000);
boundedInteger("DB_MAX_LIFETIME_SECONDS", 1_800, 60, 7_200);
const statementTimeout = boundedInteger("DB_STATEMENT_TIMEOUT_MS", 15_000, 1_000, 120_000);
const queryTimeout = boundedInteger("DB_QUERY_TIMEOUT_MS", 20_000, 1_000, 150_000);
if (queryTimeout <= statementTimeout) failures.push("DB_QUERY_TIMEOUT_MS must be greater than DB_STATEMENT_TIMEOUT_MS");

let database;
try {
  database = new URL(environment.DATABASE_URL ?? "");
  if (database.protocol !== "postgresql:" && database.protocol !== "postgres:") failures.push("DATABASE_URL must use PostgreSQL");
  if (!database.username) failures.push("DATABASE_URL must include a restricted application username");
  if (["postgres", "mndf_pms_migration_owner", "mndf_pms_backup"].includes(database.username)) failures.push("DATABASE_URL must not use an administrative, migration, or backup role");
  if (!database.password || placeholder.test(database.password)) failures.push("DATABASE_URL must contain a non-placeholder runtime password");
  if (database.password) values.push(database.password);
} catch {
  failures.push("DATABASE_URL must be a valid PostgreSQL URL");
}

for (const name of requiredSecrets) {
  const value = environment[name] ?? "";
  if (value.length < 32 || placeholder.test(value)) failures.push(`${name} must be a unique non-placeholder value of at least 32 characters`);
  values.push(value);
}

const mfaKey = environment.MFA_ENCRYPTION_KEY ?? "";
let decodedMfaKey;
try { decodedMfaKey = Buffer.from(mfaKey, "base64"); } catch { decodedMfaKey = Buffer.alloc(0); }
if (decodedMfaKey.length !== 32 || placeholder.test(mfaKey)) failures.push("MFA_ENCRYPTION_KEY must be a base64-encoded 32-byte key");
values.push(mfaKey);

try {
  const auditDatabase = new URL(environment.AUDIT_DATABASE_URL ?? "");
  if (!["postgresql:", "postgres:"].includes(auditDatabase.protocol)) failures.push("AUDIT_DATABASE_URL must use PostgreSQL");
  if (!auditDatabase.username || ["postgres", "mndf_pms_migration_owner", "mndf_pms_app"].includes(auditDatabase.username)) failures.push("AUDIT_DATABASE_URL must use a dedicated audit-export login");
  if (!auditDatabase.password || placeholder.test(auditDatabase.password)) failures.push("AUDIT_DATABASE_URL must contain a non-placeholder password");
  if (auditDatabase.password) values.push(auditDatabase.password);
} catch { failures.push("AUDIT_DATABASE_URL must be a valid PostgreSQL URL"); }

const populatedSecrets = values.filter(Boolean);
if (new Set(populatedSecrets).size !== populatedSecrets.length) failures.push("Database, authentication, MFA, scanner, monitoring, audit, and scheduled-job secrets must all be different");

const evidenceRoot = environment.EVIDENCE_STORAGE_ROOT ?? "";
if (!evidenceRoot || !isAbsolute(evidenceRoot)) failures.push("EVIDENCE_STORAGE_ROOT must be an absolute private path");
else {
  const normalized = resolve(evidenceRoot).toLowerCase();
  const current = resolve(process.cwd()).toLowerCase();
  if (normalized === current || normalized.startsWith(`${current}\\`) || normalized.startsWith(`${current}/`)) failures.push("EVIDENCE_STORAGE_ROOT must be outside the application directory");
}
const quarantineRoot = environment.EVIDENCE_QUARANTINE_ROOT ?? "";
if (!quarantineRoot || !isAbsolute(quarantineRoot)) failures.push("EVIDENCE_QUARANTINE_ROOT must be an absolute private path");
else {
  const normalized = resolve(quarantineRoot).toLowerCase();
  const current = resolve(process.cwd()).toLowerCase();
  if (normalized === current || normalized.startsWith(`${current}\\`) || normalized.startsWith(`${current}/`)) failures.push("EVIDENCE_QUARANTINE_ROOT must be outside the application directory");
  if (evidenceRoot && normalized === resolve(evidenceRoot).toLowerCase()) failures.push("Evidence and quarantine roots must be different directories");
}

const hostname = environment.HOSTNAME ?? "127.0.0.1";
if (!["127.0.0.1", "localhost", "::1"].includes(hostname)) failures.push("HOSTNAME must bind the Next.js process to loopback; expose only the HTTPS reverse proxy");
const port = Number(environment.PORT ?? "3100");
if (!Number.isInteger(port) || port < 1024 || port > 65535) failures.push("PORT must be an unprivileged TCP port between 1024 and 65535");

try {
  const publicUrl = new URL(environment.PRODUCTION_PUBLIC_URL ?? "");
  if (publicUrl.protocol !== "https:") failures.push("PRODUCTION_PUBLIC_URL must use HTTPS");
  if (["localhost", "127.0.0.1", "::1"].includes(publicUrl.hostname)) failures.push("PRODUCTION_PUBLIC_URL must identify the organization-controlled reverse proxy, not loopback");
  if (publicUrl.username || publicUrl.password || publicUrl.search || publicUrl.hash) failures.push("PRODUCTION_PUBLIC_URL must not contain credentials, a query, or a fragment");
} catch { failures.push("PRODUCTION_PUBLIC_URL must be a valid HTTPS URL"); }

if (failures.length) {
  console.error("Production configuration rejected:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log("Production environment validation passed.");
