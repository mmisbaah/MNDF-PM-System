import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { listNotifications,markNotificationRead } from "@/lib/grievance/service";
export async function GET(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    return NextResponse.json({ success: true, notifications: await listNotifications(principal.tenantId, principal.accountId) });
  } catch (error) { return evaluationErrorResponse(error); }
}
export async function POST(request:NextRequest){
 try{
  const principal=await authenticateRequest(request);
  const body=await request.json() as{id?:string;source?:"GRIEVANCE"|"CORRECTION"};
  if(!body.id||!["GRIEVANCE","CORRECTION"].includes(body.source??""))return NextResponse.json({success:false,error:"Notification ID and source are required"},{status:422});
  return NextResponse.json({success:true,notification:await markNotificationRead(principal.tenantId,principal.accountId,body.id,body.source!)});
 }catch(error){return evaluationErrorResponse(error)}
}
