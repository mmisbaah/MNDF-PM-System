import{NextRequest,NextResponse}from"next/server";
import{authorizeRequest}from"@/lib/auth/session";
import{evaluationErrorResponse}from"@/lib/evaluation/http";
import{EvaluationDomainError}from"@/lib/evaluation/errors";
import{transitionOperationalReport}from"@/lib/reports/service";

export const runtime="nodejs";
export async function POST(request:NextRequest,context:{params:Promise<{reportId:string}>}){
  try{
    const body=await request.json() as{action:"submit"|"confirm"};
    if(!["submit","confirm"].includes(body.action))throw new EvaluationDomainError("Valid report action required",422,"REPORT_ACTION_REQUIRED");
    const principal=await authorizeRequest(request,body.action==="submit"?"appraisal.comment":"activity.confirm");
    const{reportId}=await context.params;
    return NextResponse.json({success:true,report:await transitionOperationalReport(principal.tenantId,principal.accountId,reportId,body.action)});
  }catch(error){return evaluationErrorResponse(error);}
}
