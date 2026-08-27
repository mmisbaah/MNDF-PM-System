import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import { assignCaseOfficer } from "@/lib/grievance/service";
export const runtime = "nodejs";
export async function POST(request: NextRequest, context: { params: Promise<{ complaintId: string }> }) {
  try {
    const principal = await authorizeRequest(request, "grievance.manage"); const { complaintId } = await context.params;
    const body = await request.json() as { accountId?: string };
    if (!body.accountId) throw new EvaluationDomainError("Case officer account ID is required", 422, "OFFICER_REQUIRED");
    const assignment = await assignCaseOfficer(principal.tenantId, principal.accountId, complaintId, body.accountId);
    return NextResponse.json({ success: true, assignment }, { status: 201 });
  } catch (error) { return evaluationErrorResponse(error); }
}
