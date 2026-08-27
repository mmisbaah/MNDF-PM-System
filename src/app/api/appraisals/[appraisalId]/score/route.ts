import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { calculateAppraisalScore } from "@/lib/evaluation/score-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function GET(
  request: NextRequest,
  context: { params: Promise<{ appraisalId: string }> },
) {
  try {
    const principal = await authorizeRequest(request, "report.read");
    const { appraisalId } = await context.params;
    const score = await calculateAppraisalScore(principal.tenantId, principal.accountId, appraisalId);
    return NextResponse.json({ success: true, score });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
