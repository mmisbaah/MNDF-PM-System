import{pool}from"@/db";
import{withTenantTransaction}from"@/lib/auth/repository";
import{processDeadlines}from"@/lib/grievance/service";
import{synchronizeQuarterlyCycles}from"@/lib/evaluation/cycle-service";
import{refreshTenantEligibility}from"@/lib/recommendations/service";

type JobType="GRIEVANCE_DEADLINES"|"CYCLE_LIFECYCLE"|"RECOMMENDATION_ELIGIBILITY";
const intervals:Record<JobType,number>={GRIEVANCE_DEADLINES:55_000,CYCLE_LIFECYCLE:15*60_000,RECOMMENDATION_ELIGIBILITY:60*60_000};

async function installationTenant(){const result=await pool.query<{tenant_id:string|null}>("SELECT tenant_id FROM read_installation_identity()");return result.rows[0]?.tenant_id??null}
async function due(tenantId:string,type:JobType){return withTenantTransaction(tenantId,null,async c=>{const result=await c.query<{last_success:Date|null}>(`SELECT max(finished_at)FILTER(WHERE succeeded)last_success FROM scheduled_job_runs WHERE tenant_id=$1 AND job_type=$2`,[tenantId,type]);const last=result.rows[0]?.last_success;return!last||Date.now()-new Date(last).getTime()>=intervals[type]})}
async function runOne(tenantId:string,type:JobType){
 const run=await withTenantTransaction(tenantId,null,async c=>(await c.query<{id:string}>(`INSERT INTO scheduled_job_runs(tenant_id,job_type)VALUES($1,$2)RETURNING id`,[tenantId,type])).rows[0]);
 try{
  const result=type==="GRIEVANCE_DEADLINES"?await processDeadlines(tenantId):type==="CYCLE_LIFECYCLE"?{cycles:await synchronizeQuarterlyCycles(tenantId,null)}:{personnelEvaluated:await refreshTenantEligibility(tenantId)};
  await withTenantTransaction(tenantId,null,c=>c.query(`UPDATE scheduled_job_runs SET finished_at=clock_timestamp(),succeeded=true,result=$3::jsonb WHERE tenant_id=$1 AND id=$2`,[tenantId,run.id,JSON.stringify(result)]).then(()=>undefined));
  return{type,succeeded:true,result};
 }catch(error){const message=error instanceof Error?error.message:"Scheduled job failed";await withTenantTransaction(tenantId,null,c=>c.query(`UPDATE scheduled_job_runs SET finished_at=clock_timestamp(),succeeded=false,error_message=$3 WHERE tenant_id=$1 AND id=$2`,[tenantId,run.id,message.slice(0,1000)]).then(()=>undefined));return{type,succeeded:false,error:message}}
}
export async function runDueScheduledJobs(){const tenantId=await installationTenant();if(!tenantId)return{tenantId:null,runs:[]};const types:JobType[]=["GRIEVANCE_DEADLINES","CYCLE_LIFECYCLE","RECOMMENDATION_ELIGIBILITY"];const runs=[];for(const type of types)if(await due(tenantId,type))runs.push(await runOne(tenantId,type));return{tenantId,runs}}
