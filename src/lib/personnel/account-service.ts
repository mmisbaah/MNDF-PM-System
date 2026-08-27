import { hashPassword } from "@/lib/auth/password";
import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";

function loginId(value: unknown): string {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (!normalized || normalized.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized)) {
    throw new EvaluationDomainError("Enter a valid login ID in email format", 422, "INVALID_LOGIN_ID");
  }
  return normalized;
}

async function temporaryPassword(value: unknown): Promise<string> {
  const password = String(value ?? "");
  if (password.length < 12) throw new EvaluationDomainError("Temporary password must contain at least 12 characters", 422, "WEAK_TEMPORARY_PASSWORD");
  return hashPassword(password);
}

export async function createPersonnelAccount(tenantId: string, actorId: string, personnelId: string, input: Record<string, unknown>) {
  const email = loginId(input.loginId);
  const passwordHash = await temporaryPassword(input.temporaryPassword);
  return withTenantTransaction(tenantId, actorId, async (client) => {
    const person = await client.query("SELECT id,status FROM personnel WHERE tenant_id=$1 AND id=$2 FOR UPDATE", [tenantId, personnelId]);
    if (!person.rows[0]) throw new EvaluationDomainError("Personnel record not found", 404, "PERSONNEL_NOT_FOUND");
    if (person.rows[0].status !== "ACTIVE") throw new EvaluationDomainError("Only active personnel can receive a login", 409, "PERSONNEL_INACTIVE");
    const linked = await client.query("SELECT id FROM accounts WHERE tenant_id=$1 AND personnel_id=$2", [tenantId, personnelId]);
    if (linked.rows[0]) throw new EvaluationDomainError("This person already has a login account", 409, "ACCOUNT_EXISTS");
    try {
      const account = (await client.query<{ id: string; email: string }>(
        `INSERT INTO accounts(tenant_id,personnel_id,email,password_hash,is_active,must_change_password)
         VALUES($1,$2,$3,$4,true,true) RETURNING id,email::text`,
        [tenantId, personnelId, email, passwordHash],
      )).rows[0];
      await client.query(
        `INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id)
         VALUES($1,$2,'APPRAISEE',$3)`,
        [tenantId, account.id, actorId],
      );
      return { ...account, mustChangePassword: true };
    } catch (error: any) {
      if (error?.code === "23505") throw new EvaluationDomainError("That login ID is already in use", 409, "LOGIN_ID_EXISTS");
      throw error;
    }
  });
}

export async function resetPersonnelTemporaryPassword(tenantId: string, actorId: string, personnelId: string, input: Record<string, unknown>) {
  const passwordHash = await temporaryPassword(input.temporaryPassword);
  return withTenantTransaction(tenantId, actorId, async (client) => {
    const account = (await client.query<{ id: string; email: string }>(
      `SELECT ac.id,ac.email::text FROM accounts ac
       WHERE ac.tenant_id=$1 AND ac.personnel_id=$2 AND ac.is_active FOR UPDATE`,
      [tenantId, personnelId],
    )).rows[0];
    if (!account) throw new EvaluationDomainError("No active login is linked to this person", 404, "ACCOUNT_NOT_FOUND");
    const protectedRole = await client.query(
      `SELECT 1 FROM account_roles WHERE tenant_id=$1 AND account_id=$2
       AND role IN('UNIT_ADMINISTRATOR','COMPANY_COMMANDER','TECHNICAL_OPERATOR')
       AND valid_from<=clock_timestamp() AND(valid_until IS NULL OR valid_until>clock_timestamp())`,
      [tenantId, account.id],
    );
    if (protectedRole.rows[0]) throw new EvaluationDomainError("This protected account must use the secure account-recovery workflow", 403, "PROTECTED_ACCOUNT");
    await client.query(
      `UPDATE accounts SET password_hash=$3,must_change_password=true,password_changed_at=clock_timestamp(),updated_at=clock_timestamp()
       WHERE tenant_id=$1 AND id=$2`,
      [tenantId, account.id, passwordHash],
    );
    await client.query("UPDATE auth_sessions SET revoked_at=clock_timestamp() WHERE tenant_id=$1 AND account_id=$2 AND revoked_at IS NULL", [tenantId, account.id]);
    return { ...account, mustChangePassword: true };
  });
}
