import{NextRequest,NextResponse}from"next/server";import{authorizeRequest}from"@/lib/auth/session";import{evaluationErrorResponse}from"@/lib/evaluation/http";import{approveDisposal,approveRetentionPolicy,createLegalHold,createRetentionPolicy,decideControlledExport,loadRecordsGovernance,releaseLegalHold,requestControlledExport,requestDisposal}from"@/lib/records-lifecycle/service";
export const runtime="nodejs";
export async function GET(r:NextRequest){try{const p=await authorizeRequest(r,"audit.read");return NextResponse.json({success:true,governance:await loadRecordsGovernance(p.tenantId,p.accountId)},{headers:{"Cache-Control":"private, no-store"}})}catch(e){return evaluationErrorResponse(e)}}
export async function POST(r:NextRequest){try{const body=await r.json()as Record<string,unknown>,action=String(body.action??"");const permission=action==="APPROVE_DISPOSAL"?"grievance.manage":action==="REQUEST_EXPORT"?"personnel.manage":action.includes("DISPOSAL")||action.includes("HOLD")?"tenant.closure_approve":"tenant.export_approve";const p=await authorizeRequest(r,permission);let result;
 if(action==="CREATE_POLICY")result=await createRetentionPolicy(p.tenantId,p.accountId,{recordClass:String(body.recordClass??""),retainIndefinitely:Boolean(body.retainIndefinitely),retentionDays:body.retentionDays===undefined?undefined:Number(body.retentionDays),reason:String(body.reason??"")});
 else if(action==="APPROVE_POLICY")result=await approveRetentionPolicy(p.tenantId,p.accountId,String(body.id));
 else if(action==="CREATE_HOLD")result=await createLegalHold(p.tenantId,p.accountId,{scopeType:String(body.scopeType??""),scopeId:body.scopeId?String(body.scopeId):undefined,reason:String(body.reason??"")});
 else if(action==="RELEASE_HOLD")result=await releaseLegalHold(p.tenantId,p.accountId,String(body.id),String(body.reason??""));
 else if(action==="REQUEST_EXPORT")result=await requestControlledExport(p.tenantId,p.accountId,{exportScope:String(body.exportScope??""),scopeId:body.scopeId?String(body.scopeId):undefined,purpose:String(body.purpose??"")});
 else if(action==="DECIDE_EXPORT")result=await decideControlledExport(p.tenantId,p.accountId,String(body.id),Boolean(body.approved),String(body.reason??""));
 else if(action==="REQUEST_DISPOSAL")result=await requestDisposal(p.tenantId,p.accountId,{recordClass:String(body.recordClass??""),cutoffAt:String(body.cutoffAt??""),reason:String(body.reason??"")});
 else if(action==="APPROVE_DISPOSAL")result=await approveDisposal(p.tenantId,p.accountId,String(body.id),String(body.authorityRole),String(body.reason??""));
 else return NextResponse.json({success:false,error:"Valid records-governance action required"},{status:422});return NextResponse.json({success:true,result});
 }catch(e){return evaluationErrorResponse(e)}}
