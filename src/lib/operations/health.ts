import { timingSafeEqual } from "node:crypto";
import { pool } from "@/db";
import { databasePoolConfiguration } from "@/db/config";
import { withTenantTransaction } from "@/lib/auth/repository";

type Severity = "OK" | "WARNING" | "CRITICAL";
type Check = { name: string; severity: Severity; message: string; value?: number | string | null };

export function validMonitorSecret(value: string | null) {
  const expected = process.env.OPERATIONS_MONITOR_SECRET;
  const supplied = value?.replace(/^Bearer /, "");
  if (!expected || !supplied) return false;
  const a = Buffer.from(expected);
  const b = Buffer.from(supplied);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function operationsHealth() {
  const installation = await pool.query<{ tenant_id: string | null }>("SELECT tenant_id FROM read_installation_identity()");
  const tenantId = installation.rows[0]?.tenant_id;
  if (!tenantId) return { status: "CRITICAL" as const, checkedAt: new Date().toISOString(), checks: [{ name: "installation", severity: "CRITICAL" as const, message: "No installation tenant is configured" }] };

  return withTenantTransaction(tenantId, null, async (client) => {
    const jobs = await client.query<{ job_type: string; last_success: Date | null; recent_failures: string }>(`
        SELECT required.job_type,max(r.finished_at)FILTER(WHERE r.succeeded)last_success,
          count(*)FILTER(WHERE NOT r.succeeded AND r.started_at>=clock_timestamp()-interval '24 hours')::text recent_failures
        FROM (VALUES('GRIEVANCE_DEADLINES'),('CYCLE_LIFECYCLE'),('RECOMMENDATION_ELIGIBILITY'))required(job_type)
        LEFT JOIN scheduled_job_runs r ON r.tenant_id=$1 AND r.job_type::text=required.job_type GROUP BY required.job_type`, [tenantId]);
    const evidence = await client.query<{ stale_pending: string; recent_failed: string }>(`SELECT count(*)FILTER(WHERE malware_status='PENDING'AND created_at<clock_timestamp()-interval '10 minutes')::text stale_pending,count(*)FILTER(WHERE malware_status='FAILED'AND scanned_at>=clock_timestamp()-interval '24 hours')::text recent_failed FROM evidence_uploads WHERE tenant_id=$1`, [tenantId]);
    const mfa = await client.query<{ failed: string }>(`SELECT count(*)::text failed FROM mfa_verification_attempts WHERE tenant_id=$1 AND NOT succeeded AND occurred_at>=clock_timestamp()-interval '15 minutes'`, [tenantId]);
    const audit = await client.query<{ sensitive: string }>(`SELECT count(*)::text sensitive FROM audit_logs WHERE tenant_id=$1 AND occurred_at>=clock_timestamp()-interval '24 hours' AND(action LIKE 'TECHNICAL_OPERATOR_EXCEPTION%'OR restricted_access)`, [tenantId]);
    const clock = await client.query<{ server_time: Date }>("SELECT clock_timestamp() server_time");
    const checks: Check[] = [];
    const poolMaximum = databasePoolConfiguration().max;
    const waiting = pool.waitingCount;
    const utilization = poolMaximum ? pool.totalCount / poolMaximum : 1;
    checks.push({ name: "database-pool", severity: waiting > 0 || utilization >= 0.9 ? "WARNING" : "OK", message: `${pool.totalCount}/${poolMaximum} connections allocated, ${pool.idleCount} idle, ${waiting} waiting`, value: waiting });
    const maximumAge: Record<string, number> = { GRIEVANCE_DEADLINES: 5 * 60_000, CYCLE_LIFECYCLE: 30 * 60_000, RECOMMENDATION_ELIGIBILITY: 2 * 60 * 60_000 };
    for (const row of jobs.rows) {
      const age = row.last_success ? Date.now() - new Date(row.last_success).getTime() : Number.POSITIVE_INFINITY;
      const failures = Number(row.recent_failures);
      checks.push({ name: `scheduled-job:${row.job_type}`, severity: !row.last_success || age > maximumAge[row.job_type] ? "CRITICAL" : failures ? "WARNING" : "OK", message: !row.last_success ? "No successful execution recorded" : `Last success ${Math.round(age / 1000)} seconds ago; ${failures} failure(s) in 24 hours`, value: row.last_success?.toISOString() ?? null });
    }
    const stale = Number(evidence.rows[0]?.stale_pending ?? 0), scanFailures = Number(evidence.rows[0]?.recent_failed ?? 0);
    checks.push({ name: "evidence-scanner", severity: stale > 0 || scanFailures > 0 ? "CRITICAL" : "OK", message: `${stale} stale pending and ${scanFailures} failed scan(s)`, value: stale + scanFailures });
    const failedMfa = Number(mfa.rows[0]?.failed ?? 0);
    checks.push({ name: "authentication", severity: failedMfa >= 10 ? "CRITICAL" : failedMfa >= 5 ? "WARNING" : "OK", message: `${failedMfa} failed MFA attempt(s) in 15 minutes`, value: failedMfa });
    const sensitive = Number(audit.rows[0]?.sensitive ?? 0);
    checks.push({ name: "sensitive-audit-events", severity: sensitive ? "WARNING" : "OK", message: `${sensitive} restricted-access or exceptional-operator event(s) in 24 hours`, value: sensitive });
    const drift = Math.abs(Date.now() - new Date(clock.rows[0].server_time).getTime());
    checks.push({ name: "database-clock", severity: drift > 30_000 ? "CRITICAL" : drift > 5_000 ? "WARNING" : "OK", message: `${drift} ms application/database clock difference`, value: drift });
    const status = checks.some((check) => check.severity === "CRITICAL") ? "CRITICAL" : checks.some((check) => check.severity === "WARNING") ? "DEGRADED" : "HEALTHY";
    return { status, checkedAt: new Date().toISOString(), checks };
  });
}
