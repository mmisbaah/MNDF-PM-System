import { withTenantTransaction } from "@/lib/auth/repository";
import { EvaluationDomainError } from "@/lib/evaluation/errors";

type PersonnelInput={personnelCode?:string;fullName?:string;rankName?:string;personnelCategory?:string;rankPrecedence?:number|string;dateOfRank?:string;manualPrecedence?:number|string|null;dateJoinedService?:string;unitServiceStartedOn?:string;appointmentId?:string;additionalResponsibilities?:string};

function required(input:PersonnelInput){
  if(!input.personnelCode?.trim()||!/^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$/.test(input.personnelCode.trim()))throw new EvaluationDomainError("Unique ID must be 1-32 letters, numbers, dots, underscores, or hyphens",422,"PERSONNEL_CODE_INVALID");
  if(!input.fullName?.trim()||!input.rankName?.trim()||!input.appointmentId)throw new EvaluationDomainError("Designation, name, and appointment are required",422,"PERSONNEL_FIELDS_REQUIRED");
  if(!input.personnelCategory?.trim()||input.personnelCategory.trim().length>80)throw new EvaluationDomainError("Personnel category must contain 1-80 characters",422,"PERSONNEL_CATEGORY_REQUIRED");
  if(!Number.isInteger(Number(input.rankPrecedence))||Number(input.rankPrecedence)<1||Number(input.rankPrecedence)>1000)throw new EvaluationDomainError("Rank precedence must be between 1 and 1000",422,"RANK_PRECEDENCE_INVALID");
  if(!input.dateOfRank)throw new EvaluationDomainError("Date of rank or grade is required",422,"DATE_OF_RANK_REQUIRED");
  if(input.manualPrecedence!==undefined&&input.manualPrecedence!==null&&input.manualPrecedence!==""&&(!Number.isInteger(Number(input.manualPrecedence))||Number(input.manualPrecedence)<1||Number(input.manualPrecedence)>1000))throw new EvaluationDomainError("Manual precedence must be between 1 and 1000",422,"MANUAL_PRECEDENCE_INVALID");
  if((input.additionalResponsibilities?.trim().length??0)>1000)throw new EvaluationDomainError("Additional responsibilities must not exceed 1000 characters",422,"PERSONNEL_RESPONSIBILITIES_INVALID");
  if(!input.dateJoinedService||!input.unitServiceStartedOn||input.unitServiceStartedOn<input.dateJoinedService)throw new EvaluationDomainError("Valid organization dates are required and the assignment start cannot predate the entry date",422,"PERSONNEL_DATES_INVALID");
}

async function activeAppointment(client:any,tenantId:string,appointmentId:string){
  const appointment=(await client.query(`SELECT ap.id FROM appointments ap JOIN organizational_nodes n ON n.tenant_id=ap.tenant_id AND n.id=ap.organizational_node_id WHERE ap.tenant_id=$1 AND ap.id=$2 AND ap.active AND n.active`,[tenantId,appointmentId])).rows[0];
  if(!appointment)throw new EvaluationDomainError("Select an active appointment",422,"PERSONNEL_APPOINTMENT_REQUIRED");
}

export async function createPersonnel(tenantId:string,accountId:string,input:PersonnelInput){
  required(input);
  return withTenantTransaction(tenantId,accountId,async client=>{
    await activeAppointment(client,tenantId,input.appointmentId!);
    try{
      const person=(await client.query(`INSERT INTO personnel(tenant_id,personnel_code,full_name,rank_name,personnel_category,rank_precedence,date_of_rank,manual_precedence,date_joined_service,unit_service_started_on)VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)RETURNING *`,[tenantId,input.personnelCode!.trim(),input.fullName!.trim(),input.rankName!.trim(),input.personnelCategory!.trim(),Number(input.rankPrecedence),input.dateOfRank,input.manualPrecedence===""||input.manualPrecedence==null?null:Number(input.manualPrecedence),input.dateJoinedService,input.unitServiceStartedOn])).rows[0];
      await client.query(`INSERT INTO personnel_appointments(tenant_id,personnel_id,appointment_id,starts_on,is_primary,role_description)VALUES($1,$2,$3,$4,true,$5)`,[tenantId,person.id,input.appointmentId,input.unitServiceStartedOn,input.additionalResponsibilities?.trim()??""]);
      return person;
    }catch(error:any){if(error?.code==="23505")throw new EvaluationDomainError("Personnel unique ID already exists",409,"PERSONNEL_CODE_EXISTS");throw error}
  });
}

export async function updatePersonnel(tenantId:string,accountId:string,id:string,input:PersonnelInput){
  required(input);
  return withTenantTransaction(tenantId,accountId,async client=>{
    await activeAppointment(client,tenantId,input.appointmentId!);
    const person=(await client.query(`UPDATE personnel SET personnel_code=$3,full_name=$4,rank_name=$5,personnel_category=$6,rank_precedence=$7,date_of_rank=$8,manual_precedence=$9,date_joined_service=$10,unit_service_started_on=$11,updated_at=clock_timestamp()WHERE tenant_id=$1 AND id=$2 RETURNING *`,[tenantId,id,input.personnelCode!.trim(),input.fullName!.trim(),input.rankName!.trim(),input.personnelCategory!.trim(),Number(input.rankPrecedence),input.dateOfRank,input.manualPrecedence===""||input.manualPrecedence==null?null:Number(input.manualPrecedence),input.dateJoinedService,input.unitServiceStartedOn])).rows[0];
    if(!person)throw new EvaluationDomainError("Personnel record not found",404,"PERSONNEL_NOT_FOUND");
    const assignment=(await client.query(`SELECT pa.id FROM personnel_appointments pa WHERE pa.tenant_id=$1 AND pa.personnel_id=$2 AND pa.is_primary AND pa.ends_on IS NULL ORDER BY pa.starts_on DESC LIMIT 1 FOR UPDATE`,[tenantId,id])).rows[0];
    if(assignment)await client.query(`UPDATE personnel_appointments SET appointment_id=$3,role_description=$4 WHERE tenant_id=$1 AND id=$2`,[tenantId,assignment.id,input.appointmentId,input.additionalResponsibilities?.trim()??""]);
    else await client.query(`INSERT INTO personnel_appointments(tenant_id,personnel_id,appointment_id,starts_on,is_primary,role_description)VALUES($1,$2,$3,$4,true,$5)`,[tenantId,id,input.appointmentId,input.unitServiceStartedOn,input.additionalResponsibilities?.trim()??""]);
    return person;
  });
}

export async function transitionPersonnel(tenantId:string,accountId:string,id:string,action:"ACTIVATE"|"DEACTIVATE"|"REMOVE"){
  return withTenantTransaction(tenantId,accountId,async client=>{
    if(!["ACTIVATE","DEACTIVATE","REMOVE"].includes(action))throw new EvaluationDomainError("Valid personnel action is required",422,"PERSONNEL_ACTION_REQUIRED");
    if(action!=="ACTIVATE"&&await client.query(`SELECT 1 FROM accounts a JOIN account_roles r ON r.tenant_id=a.tenant_id AND r.account_id=a.id WHERE a.tenant_id=$1 AND a.personnel_id=$2 AND r.role='COMPANY_COMMANDER'AND(r.valid_until IS NULL OR r.valid_until>clock_timestamp())`,[tenantId,id]).then((result:any)=>Boolean(result.rows[0])))throw new EvaluationDomainError("The active System Authorizer cannot be deactivated or removed",409,"AUTHORIZER_PROTECTED");
    const status=action==="ACTIVATE"?"ACTIVE":action==="DEACTIVATE"?"SUSPENDED":"POSTED_OUT";
    const person=(await client.query(`UPDATE personnel SET status=$3::personnel_status,updated_at=clock_timestamp()WHERE tenant_id=$1 AND id=$2 RETURNING *`,[tenantId,id,status])).rows[0];
    if(!person)throw new EvaluationDomainError("Personnel record not found",404,"PERSONNEL_NOT_FOUND");
    await client.query(`UPDATE accounts SET is_active=$3,updated_at=clock_timestamp()WHERE tenant_id=$1 AND personnel_id=$2`,[tenantId,id,action==="ACTIVATE"]);
    if(action==="REMOVE")await client.query(`UPDATE personnel_appointments SET ends_on=current_date WHERE tenant_id=$1 AND personnel_id=$2 AND ends_on IS NULL`,[tenantId,id]);
    return person;
  });
}
