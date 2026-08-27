import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { readRestrictedComments } from "@/lib/grievance/service";
export const runtime = "nodejs";
export async function GET(request: NextRequest, context: { params: Promise<{ complaintId: string }> }) {
  try {
    const principal = await authenticateRequest(request); const { complaintId } = await context.params;
    const comments = await readRestrictedComments(principal.tenantId, principal.accountId, complaintId, "VIEW");
    return NextResponse.json({ success: true, comments }, { headers: { "Cache-Control": "no-store, private" } });
  } catch (error) { return evaluationErrorResponse(error); }
}
