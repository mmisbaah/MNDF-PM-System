import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import { submitComplaint } from "@/lib/grievance/service";
export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    const body = await request.json() as { appraisalId?: string; grounds?: string };
    if (!body.appraisalId) throw new EvaluationDomainError("Appraisal ID is required", 422, "APPRAISAL_REQUIRED");
    const complaint = await submitComplaint(principal.tenantId, principal.accountId, body.appraisalId, body.grounds ?? "");
    return NextResponse.json({ success: true, complaint }, { status: 201 });
  } catch (error) { return evaluationErrorResponse(error); }
}
