import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { initializeAppraisal } from "@/lib/evaluation/appraisal-service";
import { EvaluationDomainError } from "@/lib/evaluation/errors";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const principal = await authorizeRequest(request, "appraisal.initialize");
    const body = await request.json() as { cycleId?: string; personnelId?: string };
    if (!body.cycleId || !body.personnelId) {
      throw new EvaluationDomainError("Cycle and personnel IDs are required", 422, "APPRAISAL_CONTEXT_REQUIRED");
    }
    const result = await initializeAppraisal(
      principal.tenantId,
      principal.accountId,
      body.cycleId,
      body.personnelId,
    );
    return NextResponse.json({ success: true, appraisal: result }, { status: 201 });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
