import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { updateAppointmentDefinition } from "@/lib/organization/appointment-service";
export const runtime="nodejs";
export async function PATCH(request:NextRequest,context:{params:Promise<{appointmentId:string}>}){try{const principal=await authorizeRequest(request,"organization.manage"),{appointmentId}=await context.params;return NextResponse.json({success:true,appointment:await updateAppointmentDefinition(principal.tenantId,principal.accountId,appointmentId,await request.json())})}catch(error){return evaluationErrorResponse(error)}}
