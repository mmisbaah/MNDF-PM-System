import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { hasPermission } from "@/lib/auth/rbac";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { getComplaint } from "@/lib/grievance/service";
export const runtime = "nodejs";
export async function GET(request: NextRequest, context: { params: Promise<{ complaintId: string }> }) {
  try {
    const principal = await authenticateRequest(request); const { complaintId } = await context.params;
    const complaint = await getComplaint(principal.tenantId, principal.accountId, complaintId, hasPermission(principal, "grievance.manage"));
    return NextResponse.json({ success: true, complaint });
  } catch (error) { return evaluationErrorResponse(error); }
}
