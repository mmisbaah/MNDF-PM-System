import { isAbsolute, resolve } from "node:path";

const requiredSecrets = ["AUTH_JWT_SECRET", "GRIEVANCE_CRON_SECRET", "EVIDENCE_SCANNER_SECRET"];
const placeholder = /replace-|change-me|example|password/i;
const failures = [];

let database;
try {
  database = new URL(process.env.DATABASE_URL ?? "");
  if (database.protocol !== "postgresql:" && database.protocol !== "postgres:") failures.push("DATABASE_URL must use PostgreSQL");
  if (!database.username) failures.push("DATABASE_URL must include a restricted application username");
  if (["postgres", "mndf_pms_migration_owner", "mndf_pms_backup"].includes(database.username)) failures.push("DATABASE_URL must not use an administrative, migration, or backup role");
  if (!database.password || placeholder.test(database.password)) failures.push("DATABASE_URL must contain a non-placeholder runtime password");
} catch {
  failures.push("DATABASE_URL must be a valid PostgreSQL URL");
}

const values = [];
for (const name of requiredSecrets) {
  const value = process.env[name] ?? "";
  if (value.length < 32 || placeholder.test(value)) failures.push(`${name} must be a unique non-placeholder value of at least 32 characters`);
  values.push(value);
}

const mfaKey = process.env.MFA_ENCRYPTION_KEY ?? "";
let decodedMfaKey;
try { decodedMfaKey = Buffer.from(mfaKey, "base64"); } catch { decodedMfaKey = Buffer.alloc(0); }
if (decodedMfaKey.length !== 32 || placeholder.test(mfaKey)) failures.push("MFA_ENCRYPTION_KEY must be a base64-encoded 32-byte key");
values.push(mfaKey);

const populatedSecrets = values.filter(Boolean);
if (new Set(populatedSecrets).size !== populatedSecrets.length) failures.push("Authentication, MFA, scanner, and scheduled-job secrets must all be different");

const evidenceRoot = process.env.EVIDENCE_STORAGE_ROOT ?? "";
if (!evidenceRoot || !isAbsolute(evidenceRoot)) failures.push("EVIDENCE_STORAGE_ROOT must be an absolute private path");
else {
  const normalized = resolve(evidenceRoot).toLowerCase();
  const current = resolve(process.cwd()).toLowerCase();
  if (normalized === current || normalized.startsWith(`${current}\\`) || normalized.startsWith(`${current}/`)) failures.push("EVIDENCE_STORAGE_ROOT must be outside the application directory");
}
const quarantineRoot = process.env.EVIDENCE_QUARANTINE_ROOT ?? "";
if (!quarantineRoot || !isAbsolute(quarantineRoot)) failures.push("EVIDENCE_QUARANTINE_ROOT must be an absolute private path");
else {
  const normalized = resolve(quarantineRoot).toLowerCase();
  const current = resolve(process.cwd()).toLowerCase();
  if (normalized === current || normalized.startsWith(`${current}\\`) || normalized.startsWith(`${current}/`)) failures.push("EVIDENCE_QUARANTINE_ROOT must be outside the application directory");
  if (evidenceRoot && normalized === resolve(evidenceRoot).toLowerCase()) failures.push("Evidence and quarantine roots must be different directories");
}

const hostname = process.env.HOSTNAME ?? "127.0.0.1";
if (!["127.0.0.1", "localhost", "::1"].includes(hostname)) failures.push("HOSTNAME must bind the Next.js process to loopback; expose only the HTTPS reverse proxy");
const port = Number(process.env.PORT ?? "3100");
if (!Number.isInteger(port) || port < 1024 || port > 65535) failures.push("PORT must be an unprivileged TCP port between 1024 and 65535");

if (failures.length) {
  console.error("Production configuration rejected:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log("Production environment validation passed.");
