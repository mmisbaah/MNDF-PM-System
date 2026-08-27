import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import type { SessionPrincipal } from "@/lib/auth/types";

export type AdministratorAuthorizationState={required:boolean;state:"NOT_APPLICABLE"|"NOT_CONFIGURED"|"REQUEST_REQUIRED"|"PENDING"|"VALID";authorizationId?:string;requestedAt?:string;validUntil?:string;operators?:Array<{personnelId:string;name:string;appointment:string}>};

async function operators(client:any,tenantId:string){return(await client.query(`SELECT DISTINCT pe.id personnel_id,pe.full_name,atype.name appointment
 FROM personnel pe JOIN personnel_appointments pa ON pa.tenant_id=pe.tenant_id AND pa.personnel_id=pe.id AND pa.starts_on<=current_date AND(pa.ends_on IS NULL OR pa.ends_on>=current_date)
 JOIN appointments ap ON ap.tenant_id=pa.tenant_id AND ap.id=pa.appointment_id AND ap.active
 JOIN appointment_types atype ON atype.tenant_id=ap.tenant_id AND atype.id=ap.appointment_type_id AND atype.active AND atype.system_administrator_operator
 WHERE pe.tenant_id=$1 AND pe.status='ACTIVE' ORDER BY pe.id`,[tenantId])).rows}

export async function getAdministratorAuthorizationState(principal:SessionPrincipal):Promise<AdministratorAuthorizationState>{
 if(!principal.roles.includes("UNIT_ADMINISTRATOR"))return{required:false,state:"NOT_APPLICABLE"};
 return withTenantTransaction(principal.tenantId,principal.accountId,async client=>{
  const account=(await client.query("SELECT personnel_id FROM accounts WHERE tenant_id=$1 AND id=$2",[principal.tenantId,principal.accountId])).rows[0];
  if(account?.personnel_id)return{required:false,state:"NOT_APPLICABLE"};
  const holders=await operators(client,principal.tenantId);
  if(!holders.length)return{required:true,state:"NOT_CONFIGURED",operators:[]};
  const ids=holders.map((x:any)=>x.personnel_id);
  await client.query(`UPDATE system_administrator_authorizations SET status='EXPIRED',decided_at=COALESCE(decided_at,clock_timestamp())
   WHERE tenant_id=$1 AND administrator_account_id=$2 AND status='APPROVED' AND(valid_until<=clock_timestamp() OR operator_personnel_ids<>$3::uuid[])`,[principal.tenantId,principal.accountId,ids]);
  const row=(await client.query(`SELECT id,status,requested_at,valid_until,operator_personnel_ids FROM system_administrator_authorizations
   WHERE tenant_id=$1 AND administrator_account_id=$2 AND status IN('PENDING','APPROVED') ORDER BY requested_at DESC LIMIT 1`,[principal.tenantId,principal.accountId])).rows[0];
  if(!row)return{required:true,state:"REQUEST_REQUIRED",operators:holders.map((x:any)=>({personnelId:x.personnel_id,name:x.full_name,appointment:x.appointment}))};
  return{required:true,state:row.status==='APPROVED'?"VALID":"PENDING",authorizationId:row.id,requestedAt:row.requested_at,validUntil:row.valid_until,operators:holders.map((x:any)=>({personnelId:x.personnel_id,name:x.full_name,appointment:x.appointment}))};
 });
}

export async function requireAdministratorAuthorization(principal:SessionPrincipal){const state=await getAdministratorAuthorizationState(principal);if(state.required&&!['VALID','NOT_CONFIGURED'].includes(state.state))throw new EvaluationDomainError("System Administrator access requires current Authorizer approval",403,"ADMIN_AUTHORIZATION_REQUIRED")}

export async function requestAdministratorAuthorization(principal:SessionPrincipal){
 if(!principal.mfa)throw new EvaluationDomainError("Administrator MFA verification is required",403,"ADMIN_MFA_REQUIRED");
 const state=await getAdministratorAuthorizationState(principal);
 if(!state.required)throw new EvaluationDomainError("This is not the dedicated Administrator account",403,"NOT_DEDICATED_ADMINISTRATOR");
 if(state.state==='NOT_CONFIGURED')throw new EvaluationDomainError("Assign at least one eligible Administrator operator appointment first",409,"ADMIN_OPERATOR_REQUIRED");
 if(state.state==='PENDING'||state.state==='VALID')return state;
 return withTenantTransaction(principal.tenantId,principal.accountId,async client=>{
  const holders=await operators(client,principal.tenantId),ids=holders.map((x:any)=>x.personnel_id);
  const row=(await client.query(`INSERT INTO system_administrator_authorizations(tenant_id,administrator_account_id,operator_personnel_ids)VALUES($1,$2,$3::uuid[])RETURNING id,requested_at`,[principal.tenantId,principal.accountId,ids])).rows[0];
  return{required:true,state:"PENDING" as const,authorizationId:row.id,requestedAt:row.requested_at,operators:holders.map((x:any)=>({personnelId:x.personnel_id,name:x.full_name,appointment:x.appointment}))};
 });
}

export async function decideAdministratorAuthorization(tenantId:string,authorizerId:string,id:string,input:{decision?:string;reason?:string}){
 const decision=input.decision==='APPROVE'?'APPROVED':input.decision==='REJECT'?'REJECTED':null;
 if(!decision)throw new EvaluationDomainError("A valid approval decision is required",422,"ADMIN_DECISION_REQUIRED");
 if(!input.reason?.trim()||input.reason.trim().length>1000)throw new EvaluationDomainError("Decision reason must contain 1-1000 characters",422,"ADMIN_DECISION_REASON_REQUIRED");
 const reason=input.reason.trim();
 return withTenantTransaction(tenantId,authorizerId,async client=>{
  const row=(await client.query(`UPDATE system_administrator_authorizations SET status=$4,decided_by_account_id=$2,decided_at=statement_timestamp(),decision_reason=$5,
   valid_until=CASE WHEN $4='APPROVED' THEN statement_timestamp()+interval '7 days' ELSE NULL END
   WHERE tenant_id=$1 AND id=$3 AND status='PENDING' RETURNING *`,[tenantId,authorizerId,id,decision,reason])).rows[0];
  if(!row)throw new EvaluationDomainError("Pending Administrator authorization not found",404,"ADMIN_AUTHORIZATION_NOT_FOUND");return row;
 });
}
