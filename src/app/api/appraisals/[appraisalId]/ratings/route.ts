import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { submitRating, type SubmitRatingInput } from "@/lib/evaluation/rating-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ appraisalId: string }> },
) {
  try {
    const principal = await authorizeRequest(request, "appraisal.evaluate");
    const { appraisalId } = await context.params;
    const body = await request.json() as SubmitRatingInput;
    const result = await submitRating(principal.tenantId, principal.accountId, appraisalId, body);
    return NextResponse.json({ success: true, rating: result }, { status: 201 });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
