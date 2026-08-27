import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { createAppointmentDefinition } from "@/lib/organization/appointment-service";
export const runtime="nodejs";
export async function POST(request:NextRequest){try{const principal=await authorizeRequest(request,"organization.manage");return NextResponse.json({success:true,appointment:await createAppointmentDefinition(principal.tenantId,principal.accountId,await request.json())},{status:201})}catch(error){return evaluationErrorResponse(error)}}
