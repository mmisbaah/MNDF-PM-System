import{NextRequest,NextResponse}from"next/server";import{authorizeRequest}from"@/lib/auth/session";import{evaluationErrorResponse}from"@/lib/evaluation/http";import{createOrganizationNode}from"@/lib/organization/service";
export const runtime="nodejs";
export async function POST(r:NextRequest){try{const p=await authorizeRequest(r,"organization.manage");return NextResponse.json({success:true,node:await createOrganizationNode(p.tenantId,p.accountId,await r.json())},{status:201})}catch(e){return evaluationErrorResponse(e)}}
