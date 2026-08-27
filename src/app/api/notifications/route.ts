import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { listNotifications } from "@/lib/grievance/service";
export async function GET(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    return NextResponse.json({ success: true, notifications: await listNotifications(principal.tenantId, principal.accountId) });
  } catch (error) { return evaluationErrorResponse(error); }
}
