import { createHash, randomBytes, randomUUID } from "node:crypto";
import type { PoolClient } from "pg";
import { pool } from "@/db";
import type { AuthenticatedAccount, SystemRole } from "./types";

type LoginLookupRow = {
  account_id: string;
  tenant_id: string;
  tenant_code: string;
  email: string;
  password_hash: string;
  is_active: boolean;
  mfa_enabled: boolean;
  roles: SystemRole[] | string;
};

function normalizeRoles(value: SystemRole[] | string | null | undefined): SystemRole[] {
  if (Array.isArray(value)) return value;
  if (!value || value === "{}") return [];
  return value.slice(1, -1).split(",").filter(Boolean) as SystemRole[];
}

export async function withTenantTransaction<T>(
  tenantId: string,
  accountId: string | null,
  callback: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.tenant_id', $1, true)", [tenantId]);
    await client.query("SELECT set_config('app.account_id', $1, true)", [accountId ?? ""]);
    await client.query("SELECT set_config('app.request_id', $1, true)", [randomUUID()]);
    const result = await callback(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function lookupLoginAccount(tenantCode: string, email: string): Promise<AuthenticatedAccount | null> {
  const result = await pool.query<LoginLookupRow>(
    "SELECT * FROM auth_lookup_login_account($1, $2)",
    [tenantCode.trim(), email.trim().toLowerCase()],
  );
  const row = result.rows[0];
  if (!row) return null;
  return {
    accountId: row.account_id,
    tenantId: row.tenant_id,
    tenantCode: row.tenant_code,
    email: row.email,
    passwordHash: row.password_hash,
    isActive: row.is_active,
    mfaEnabled: row.mfa_enabled,
    roles: normalizeRoles(row.roles),
  };
}

export async function tooManyLoginFailures(tenantId: string, email: string, ipAddress: string): Promise<boolean> {
  return withTenantTransaction(tenantId, null, async (client) => {
    const result = await client.query<{ blocked: boolean }>(
      `SELECT count(*) FILTER (WHERE event.succeeded = false) >= 5 AS blocked
       FROM accounts account
       LEFT JOIN auth_login_events event
         ON event.tenant_id=account.tenant_id AND event.account_id=account.id
        AND event.normalized_email=lower($2) AND event.ip_address=$3::inet
        AND event.occurred_at>=greatest(clock_timestamp()-interval '15 minutes',account.password_changed_at)
       WHERE account.tenant_id=$1 AND account.email=lower($2)`,
      [tenantId, email, ipAddress],
    );
    return result.rows[0]?.blocked ?? false;
  });
}

export async function recordLoginEvent(
  tenantId: string,
  accountId: string | null,
  email: string,
  ipAddress: string,
  succeeded: boolean,
  reason: string,
): Promise<void> {
  await withTenantTransaction(tenantId, accountId, async (client) => {
    await client.query(
      `INSERT INTO auth_login_events
       (tenant_id, account_id, normalized_email, ip_address, succeeded, reason)
       VALUES ($1, $2, lower($3), $4::inet, $5, $6)`,
      [tenantId, accountId, email, ipAddress, succeeded, reason],
    );
  });
}

export function newRefreshToken(): { token: string; hash: string; sessionId: string } {
  const sessionId = randomUUID();
  const secret = randomBytes(32).toString("base64url");
  const token = `${sessionId}.${secret}`;
  return { token, hash: createHash("sha256").update(token).digest("hex"), sessionId };
}

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export async function createSession(
  account: Pick<AuthenticatedAccount, "accountId" | "tenantId">,
  refreshHash: string,
  sessionId: string,
  ipAddress: string,
  userAgent: string,
): Promise<void> {
  await withTenantTransaction(account.tenantId, account.accountId, (client) =>
    client.query(
      `INSERT INTO auth_sessions
       (tenant_id, id, account_id, refresh_token_hash, ip_address, user_agent, expires_at, last_seen_at)
       VALUES ($1, $2, $3, $4, $5::inet, $6, now() + interval '7 days', now())`,
      [account.tenantId, sessionId, account.accountId, refreshHash, ipAddress, userAgent],
    ).then(() => undefined),
  );
}

export async function rotateSession(
  tenantId: string,
  sessionId: string,
  suppliedHash: string,
  replacementHash: string,
): Promise<{ accountId: string; roles: SystemRole[]; mfa: boolean } | null> {
  return withTenantTransaction(tenantId, null, async (client) => {
    const result = await client.query<{ account_id: string; roles: SystemRole[]; mfa_enabled: boolean }>(
      `UPDATE auth_sessions s
       SET refresh_token_hash = $4, rotated_at = now(), last_seen_at = now()
       FROM accounts a
       WHERE s.tenant_id = $1 AND s.id = $2 AND s.refresh_token_hash = $3
         AND s.revoked_at IS NULL AND s.expires_at > now()
         AND a.tenant_id = s.tenant_id AND a.id = s.account_id AND a.is_active
       RETURNING s.account_id, a.mfa_enabled,
         ARRAY(SELECT ar.role::text FROM account_roles ar
               WHERE ar.tenant_id = s.tenant_id AND ar.account_id = s.account_id
                 AND ar.valid_from <= now() AND (ar.valid_until IS NULL OR ar.valid_until > now())) AS roles`,
      [tenantId, sessionId, suppliedHash, replacementHash],
    );
    const row = result.rows[0];
    return row ? { accountId: row.account_id, roles: row.roles, mfa: row.mfa_enabled } : null;
  });
}

export async function revokeSession(tenantId: string, accountId: string, sessionId: string): Promise<void> {
  await withTenantTransaction(tenantId, accountId, (client) =>
    client.query(
      "UPDATE auth_sessions SET revoked_at = now() WHERE tenant_id = $1 AND id = $2 AND account_id = $3",
      [tenantId, sessionId, accountId],
    ).then(() => undefined),
  );
}

export async function sessionIsActive(tenantId: string, accountId: string, sessionId: string): Promise<boolean> {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query(
      `SELECT 1 FROM auth_sessions
       WHERE tenant_id = $1 AND id = $2 AND account_id = $3
         AND revoked_at IS NULL AND expires_at > now()`,
      [tenantId, sessionId, accountId],
    );
    return result.rowCount === 1;
  });
}

export async function loadActiveRoles(tenantId:string,accountId:string):Promise<SystemRole[]> {
  return withTenantTransaction(tenantId,accountId,async client=>(await client.query<{role:SystemRole}>(`SELECT role::text role FROM account_roles WHERE tenant_id=$1 AND account_id=$2 AND valid_from<=clock_timestamp() AND(valid_until IS NULL OR valid_until>clock_timestamp()) ORDER BY role`,[tenantId,accountId])).rows.map(row=>row.role));
}

export async function accountRequiresPasswordChange(tenantId:string,accountId:string):Promise<boolean>{
  return withTenantTransaction(tenantId,accountId,async client=>(await client.query<{must_change_password:boolean}>("SELECT must_change_password FROM accounts WHERE tenant_id=$1 AND id=$2",[tenantId,accountId])).rows[0]?.must_change_password??false);
}

export async function completeRequiredPasswordChange(tenantId:string,accountId:string,passwordHash:string):Promise<void>{
  await withTenantTransaction(tenantId,accountId,client=>client.query(`UPDATE accounts SET password_hash=$3,must_change_password=false,password_changed_at=clock_timestamp(),updated_at=clock_timestamp()WHERE tenant_id=$1 AND id=$2 AND must_change_password`,[tenantId,accountId,passwordHash]).then(()=>undefined));
}

export async function storePendingMfaSecret(tenantId: string, accountId: string, encryptedSecret: string): Promise<void> {
  await withTenantTransaction(tenantId, accountId, (client) =>
    client.query(
      `INSERT INTO account_mfa_factors (tenant_id, account_id, encrypted_secret, status)
       VALUES ($1, $2, $3, 'PENDING')
       ON CONFLICT (tenant_id, account_id)
       DO UPDATE SET encrypted_secret = EXCLUDED.encrypted_secret, status = 'PENDING', verified_at = NULL, updated_at = now()`,
      [tenantId, accountId, encryptedSecret],
    ).then(() => undefined),
  );
}

export async function loadMfaSecret(tenantId: string, accountId: string): Promise<{ encryptedSecret: string; active: boolean } | null> {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const result = await client.query<{ encrypted_secret: string; status: string }>(
      "SELECT encrypted_secret, status FROM account_mfa_factors WHERE tenant_id = $1 AND account_id = $2",
      [tenantId, accountId],
    );
    const row = result.rows[0];
    return row ? { encryptedSecret: row.encrypted_secret, active: row.status === "ACTIVE" } : null;
  });
}

export async function activateMfa(tenantId: string, accountId: string): Promise<void> {
  await withTenantTransaction(tenantId, accountId, async (client) => {
    await client.query(
      "UPDATE account_mfa_factors SET status = 'ACTIVE', verified_at = now(), updated_at = now() WHERE tenant_id = $1 AND account_id = $2",
      [tenantId, accountId],
    );
    await client.query("UPDATE accounts SET mfa_enabled = true, updated_at = now() WHERE tenant_id = $1 AND id = $2", [tenantId, accountId]);
  });
}

export async function mfaVerificationBlocked(tenantId:string,accountId:string):Promise<boolean>{
 return withTenantTransaction(tenantId,accountId,async client=>{const r=await client.query<{blocked:boolean}>(`SELECT count(*)FILTER(WHERE NOT succeeded)>=5 AS blocked FROM mfa_verification_attempts WHERE tenant_id=$1 AND account_id=$2 AND occurred_at>=clock_timestamp()-interval'10 minutes'`,[tenantId,accountId]);return r.rows[0]?.blocked??false});
}
export async function recordMfaVerification(tenantId:string,accountId:string,succeeded:boolean):Promise<void>{
 await withTenantTransaction(tenantId,accountId,client=>client.query(`INSERT INTO mfa_verification_attempts(tenant_id,account_id,succeeded)VALUES($1,$2,$3)`,[tenantId,accountId,succeeded]).then(()=>undefined));
}
