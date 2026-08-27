import { randomUUID } from "node:crypto";
import pg from "pg";
import { BASELINE_TEMPLATE } from "../src/lib/evaluation/baseline-template.ts";

const { Client } = pg;
const [tenantId, accountId] = process.argv.slice(2);
if (!process.env.DATABASE_URL || !tenantId || !accountId) {
  throw new Error("Usage: DATABASE_URL=... node --experimental-strip-types scripts/provision-baseline-local.mjs <tenant-id> <account-id>");
}

const client = new Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  await client.query("BEGIN");
  await client.query("SELECT set_config('app.tenant_id',$1,true),set_config('app.account_id',$2,true)", [tenantId, accountId]);
  const existing = await client.query("SELECT t.id template_id,v.id version_id FROM evaluation_templates t JOIN template_versions v ON v.tenant_id=t.tenant_id AND v.template_id=t.id WHERE t.tenant_id=$1 AND t.is_baseline ORDER BY v.version_no DESC LIMIT 1", [tenantId]);
  let templateId=existing.rows[0]?.template_id,versionId=existing.rows[0]?.version_id;
  if (!versionId) {
    templateId=randomUUID();versionId=randomUUID();
    await client.query("INSERT INTO evaluation_templates(id,tenant_id,name,is_baseline,created_by_account_id)VALUES($1,$2,$3,true,$4)", [templateId,tenantId,BASELINE_TEMPLATE.name,accountId]);
    await client.query("INSERT INTO template_versions(id,tenant_id,template_id,version_no,status,effective_from,published_at,created_by_account_id)VALUES($1,$2,$3,$4,'PUBLISHED',current_date,clock_timestamp(),$5)", [versionId,tenantId,templateId,BASELINE_TEMPLATE.version,accountId]);
    for (const [sectionIndex,section] of BASELINE_TEMPLATE.sections.entries()) {
      const sectionId=randomUUID();
      await client.query("INSERT INTO template_sections(id,tenant_id,template_version_id,name,display_order)VALUES($1,$2,$3,$4,$5)",[sectionId,tenantId,versionId,section.name,sectionIndex+1]);
      for (const [criterionIndex,criterion] of section.criteria.entries()) {
        await client.query("INSERT INTO criteria(id,tenant_id,template_version_id,section_id,code,name,description,display_order,is_unit_specific,applicable_categories,requires_rating)VALUES($1,$2,$3,$4,$5,$6,$7,$8,false,$9::text[],true)",[randomUUID(),tenantId,versionId,sectionId,criterion.code,criterion.name,criterion.description,criterionIndex+1,criterion.applicableCategories]);
      }
    }
    await client.query("INSERT INTO template_reporting_details(tenant_id,template_version_id,updated_by_account_id)VALUES($1,$2,$3)",[tenantId,versionId,accountId]);
  }
  await client.query(`WITH years(year_no) AS(VALUES(2027),(2028)),quarters(quarter_no,start_month,end_month,end_day)AS(VALUES(1,1,3,31),(2,4,6,30),(3,7,9,30),(4,10,12,31)),schedule AS(SELECT year_no,quarter_no,make_date(year_no,start_month,1)starts_on,make_date(year_no,end_month,end_day)ends_on FROM years CROSS JOIN quarters) INSERT INTO evaluation_cycles(tenant_id,template_version_id,name,cycle_type,starts_on,ends_on,status,opened_at,created_by_account_id)SELECT $1,$2,'Q'||quarter_no||' '||year_no,'QUARTERLY',starts_on,ends_on,CASE WHEN current_date>=starts_on THEN 'OPEN'::cycle_status ELSE 'DRAFT'::cycle_status END,CASE WHEN current_date>=starts_on THEN clock_timestamp() ELSE NULL END,$3 FROM schedule s WHERE NOT EXISTS(SELECT 1 FROM evaluation_cycles e WHERE e.tenant_id=$1 AND e.cycle_type='QUARTERLY' AND e.starts_on=s.starts_on AND e.ends_on=s.ends_on)`,[tenantId,versionId,accountId]);
  await client.query("COMMIT");
  process.stdout.write("baseline_and_cycles_ready\n");
} catch (error) {
  await client.query("ROLLBACK");
  throw error;
} finally {
  await client.end();
}
