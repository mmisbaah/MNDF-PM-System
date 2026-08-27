import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
export async function recalculateEligibility(tenantId:string,accountId:string,personnelId:string){return withTenantTransaction(tenantId,accountId,async c=>{await c.query("SELECT recalculate_recommendations($1,$2)",[tenantId,personnelId]);const r=await c.query("SELECT * FROM recommendations WHERE tenant_id=$1 AND personnel_id=$2 ORDER BY recommendation_type",[tenantId,personnelId]);return r.rows;});}
export async function refreshTenantEligibility(tenantId:string){return withTenantTransaction(tenantId,null,async c=>{const r=await c.query<{count:number}>("SELECT refresh_tenant_recommendations($1) AS count",[tenantId]);return r.rows[0]?.count??0;});}
export async function transitionRecommendation(tenantId:string,accountId:string,id:string,action:"nominate"|"approve"|"reject",reason:string){
  if(!reason.trim())throw new EvaluationDomainError("A reason is required",422,"REASON_REQUIRED");const status={nominate:"NOMINATED",approve:"APPROVED",reject:"REJECTED"}[action];
  return withTenantTransaction(tenantId,accountId,async c=>{const r=await c.query(`UPDATE recommendations SET status=$3::recommendation_status,
    nomination_reason=CASE WHEN $3='NOMINATED' THEN $4 ELSE nomination_reason END,decision_reason=CASE WHEN $3 IN ('APPROVED','REJECTED') THEN $4 ELSE decision_reason END
    WHERE tenant_id=$1 AND id=$2 RETURNING *`,[tenantId,id,status,reason.trim()]);if(!r.rows[0])throw new EvaluationDomainError("Recommendation not found",404,"RECOMMENDATION_NOT_FOUND");return r.rows[0];});}
