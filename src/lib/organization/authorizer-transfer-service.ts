import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";

export async function transferSystemAuthorizer(tenantId:string,actorAccountId:string,input:{incomingAccountId?:string;reason?:string}){
  if(!input.incomingAccountId)throw new EvaluationDomainError("An incoming authorizer is required",422,"INCOMING_AUTHORIZER_REQUIRED");
  if(!input.reason?.trim()||input.reason.trim().length>1000)throw new EvaluationDomainError("Transfer reason must contain 1-1000 characters",422,"TRANSFER_REASON_REQUIRED");
  return withTenantTransaction(tenantId,actorAccountId,async client=>{
    const actorRole=(await client.query(`SELECT 1 FROM account_roles WHERE tenant_id=$1 AND account_id=$2 AND role='COMPANY_COMMANDER' AND valid_from<=clock_timestamp()AND(valid_until IS NULL OR valid_until>clock_timestamp())FOR UPDATE`,[tenantId,actorAccountId])).rows[0];
    if(!actorRole)throw new EvaluationDomainError("Only the active System Authorizer may transfer authority",403,"AUTHORIZER_TRANSFER_DENIED");
    if(input.incomingAccountId===actorAccountId)throw new EvaluationDomainError("The incoming authorizer must be a different person",422,"AUTHORIZER_TRANSFER_SELF");
    const successor=(await client.query(`SELECT ac.id account_id,ac.mfa_enabled FROM personnel pe JOIN personnel_appointments pa ON pa.tenant_id=pe.tenant_id AND pa.personnel_id=pe.id AND pa.is_primary AND pa.starts_on<=current_date AND(pa.ends_on IS NULL OR pa.ends_on>=current_date)JOIN appointments ap ON ap.tenant_id=pa.tenant_id AND ap.id=pa.appointment_id AND ap.active JOIN appointment_types type ON type.tenant_id=ap.tenant_id AND type.id=ap.appointment_type_id AND type.active AND type.leadership_priority IS NOT NULL LEFT JOIN accounts ac ON ac.tenant_id=pe.tenant_id AND ac.personnel_id=pe.id AND ac.is_active WHERE pe.tenant_id=$1 AND pe.status='ACTIVE' AND pe.id<>(SELECT personnel_id FROM accounts WHERE tenant_id=$1 AND id=$2) ORDER BY type.leadership_priority,pe.rank_precedence NULLS LAST,pe.date_of_rank NULLS LAST,pe.unit_service_started_on,pe.manual_precedence NULLS LAST,pe.full_name LIMIT 1`,[tenantId,actorAccountId])).rows[0];
    if(!successor?.account_id)throw new EvaluationDomainError("The current first eligible successor needs an active login account",409,"SUCCESSOR_LOGIN_REQUIRED");
    if(successor.account_id!==input.incomingAccountId)throw new EvaluationDomainError("Authority may only transfer to the current first eligible succession candidate",409,"SUCCESSOR_MISMATCH");
    if(!successor.mfa_enabled)throw new EvaluationDomainError("The incoming authorizer must enroll MFA before transfer",409,"SUCCESSOR_MFA_REQUIRED");
    const now=(await client.query("SELECT clock_timestamp() now")).rows[0].now;
    await client.query(`UPDATE account_roles SET valid_until=$3 WHERE tenant_id=$1 AND account_id=$2 AND valid_from<$3 AND(valid_until IS NULL OR valid_until>$3)`,[tenantId,actorAccountId,now]);
    await client.query(`INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id,valid_from,valid_until)VALUES($1,$2,'AUTHORIZER_HANDOVER',$2,$3,$3+interval '3 days')`,[tenantId,actorAccountId,now]);
    await client.query(`UPDATE account_roles SET valid_until=$3
      WHERE tenant_id=$1 AND account_id=$2
        AND role IN('APPRAISEE','SQUAD_LEADER','PLATOON_SERGEANT','PLATOON_LEADER','FIRST_SERGEANT','EXECUTIVE_OFFICER','GRIEVANCE_OFFICER')
        AND valid_from<$3 AND(valid_until IS NULL OR valid_until>$3)`,[tenantId,input.incomingAccountId,now]);
    await client.query(`INSERT INTO account_roles(tenant_id,account_id,role,granted_by_account_id,valid_from)VALUES($1,$2,'COMPANY_COMMANDER',$3,$4)`,[tenantId,input.incomingAccountId,actorAccountId,now]);
    return(await client.query(`INSERT INTO system_authorizer_transfers(tenant_id,outgoing_account_id,incoming_account_id,initiated_by_account_id,reason,transferred_at,handover_expires_at)VALUES($1,$2,$3,$2,$4,$5,$5+interval '3 days')RETURNING *`,[tenantId,actorAccountId,input.incomingAccountId,input.reason!.trim(),now])).rows[0];
  });
}
