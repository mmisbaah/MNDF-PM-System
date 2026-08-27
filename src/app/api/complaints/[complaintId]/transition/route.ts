import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import { transitionComplaint } from "@/lib/grievance/service";
export const runtime = "nodejs";
const actions = new Set(["accept", "return", "review", "decide", "close"]);
export async function POST(request: NextRequest, context: { params: Promise<{ complaintId: string }> }) {
  try {
    const principal = await authorizeRequest(request, "grievance.manage"); const { complaintId } = await context.params;
    const body = await request.json() as { action?: "accept"|"return"|"review"|"decide"|"close"; reason?: string; decision?: "UPHELD"|"PARTIALLY_UPHELD"|"REJECTED"|"WITHDRAWN" };
    if (!body.action || !actions.has(body.action)) throw new EvaluationDomainError("Valid transition action is required", 422, "ACTION_REQUIRED");
    const complaint = await transitionComplaint(principal.tenantId, principal.accountId, complaintId, body.action, body);
    return NextResponse.json({ success: true, complaint });
  } catch (error) { return evaluationErrorResponse(error); }
}
