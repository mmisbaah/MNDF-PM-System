import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { submitEvaluatorStep } from "@/lib/evaluation/rating-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ appraisalId: string }> },
) {
  try {
    const principal = await authorizeRequest(request, "appraisal.evaluate");
    const { appraisalId } = await context.params;
    const result = await submitEvaluatorStep(principal.tenantId, principal.accountId, appraisalId);
    return NextResponse.json({ success: true, evaluatorStep: result });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
