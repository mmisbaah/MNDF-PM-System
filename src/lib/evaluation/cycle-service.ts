import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "./errors";

export async function synchronizeQuarterlyCycles(
  tenantId: string,
  accountId: string | null,
) {
  return withTenantTransaction(tenantId, accountId, async (client) => {
    const authority = accountId
      ? { id: accountId }
      : (
          await client.query<{ id: string }>(
            `SELECT ac.id FROM accounts ac
             JOIN account_roles ar ON ar.tenant_id=ac.tenant_id AND ar.account_id=ac.id
             WHERE ac.tenant_id=$1 AND ac.is_active AND ar.role='COMPANY_COMMANDER'
               AND ar.valid_from<=current_date
               AND (ar.valid_until IS NULL OR ar.valid_until>current_date)
             ORDER BY ar.valid_from LIMIT 1`,
            [tenantId],
          )
        ).rows[0];
    if (!authority)
      throw new EvaluationDomainError(
        "An active unit commander is required to create quarterly cycles",
        409,
        "CYCLE_AUTHORITY_REQUIRED",
      );

    const template = (
      await client.query<{ id: string }>(
        `SELECT tv.id FROM template_versions tv
         JOIN evaluation_templates et ON et.tenant_id=tv.tenant_id AND et.id=tv.template_id
         WHERE tv.tenant_id=$1 AND tv.status='PUBLISHED' AND et.is_baseline
         ORDER BY tv.version_no DESC LIMIT 1`,
        [tenantId],
      )
    ).rows[0];
    if (!template)
      throw new EvaluationDomainError(
        "A published baseline template is required",
        409,
        "PUBLISHED_TEMPLATE_REQUIRED",
      );

    await client.query(
      `WITH years AS (
         SELECT generate_series(GREATEST(2027,extract(year FROM current_date)::int),
                                GREATEST(2027,extract(year FROM current_date)::int)+1) AS year_no
       ), quarters(quarter_no,start_month,end_month,end_day) AS (
         VALUES (1,1,3,31),(2,4,6,30),(3,7,9,30),(4,10,12,31)
       ), schedule AS (
         SELECT year_no,quarter_no,
                make_date(year_no,start_month,1) starts_on,
                make_date(year_no,end_month,end_day) ends_on
         FROM years CROSS JOIN quarters
       )
       INSERT INTO evaluation_cycles
         (tenant_id,template_version_id,name,cycle_type,starts_on,ends_on,status,opened_at,created_by_account_id)
       SELECT $1,$2,'Q'||quarter_no||' '||year_no,'QUARTERLY',starts_on,ends_on,
              CASE WHEN current_date>=starts_on THEN 'OPEN'::cycle_status ELSE 'DRAFT'::cycle_status END,
              CASE WHEN current_date>=starts_on THEN clock_timestamp() ELSE NULL END,$3
       FROM schedule s
       WHERE NOT EXISTS (
         SELECT 1 FROM evaluation_cycles existing
         WHERE existing.tenant_id=$1 AND existing.cycle_type='QUARTERLY'
           AND existing.starts_on=s.starts_on AND existing.ends_on=s.ends_on
       )`,
      [tenantId, template.id, authority.id],
    );

    await client.query(
      `UPDATE evaluation_cycles
       SET status=CASE
             WHEN current_date>closure_due_on THEN 'CLOSED'::cycle_status
             WHEN current_date>ends_on THEN 'APPROVAL'::cycle_status
             WHEN current_date>=starts_on AND status='DRAFT' THEN 'OPEN'::cycle_status
             ELSE status
           END,
           opened_at=CASE WHEN current_date>=starts_on THEN COALESCE(opened_at,clock_timestamp()) ELSE opened_at END,
           closed_at=CASE WHEN current_date>closure_due_on THEN COALESCE(closed_at,clock_timestamp()) ELSE closed_at END
       WHERE tenant_id=$1 AND cycle_type='QUARTERLY' AND status NOT IN('CLOSED','ARCHIVED')`,
      [tenantId],
    );

    return (
      await client.query(
        `SELECT id,name,starts_on,ends_on,closure_due_on,status
         FROM evaluation_cycles WHERE tenant_id=$1 AND cycle_type='QUARTERLY'
         ORDER BY starts_on`,
        [tenantId],
      )
    ).rows;
  });
}
