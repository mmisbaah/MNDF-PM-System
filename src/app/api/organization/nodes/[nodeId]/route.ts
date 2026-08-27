import{NextRequest,NextResponse}from"next/server";import{authorizeRequest}from"@/lib/auth/session";import{evaluationErrorResponse}from"@/lib/evaluation/http";import{updateOrganizationNode}from"@/lib/organization/service";
export const runtime="nodejs";
export async function PATCH(r:NextRequest,c:{params:Promise<{nodeId:string}>}){try{const p=await authorizeRequest(r,"organization.manage");const{nodeId}=await c.params;return NextResponse.json({success:true,node:await updateOrganizationNode(p.tenantId,p.accountId,nodeId,await r.json())})}catch(e){return evaluationErrorResponse(e)}}
