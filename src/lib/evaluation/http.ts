import { NextResponse } from "next/server";
import { authErrorResponse } from "@/lib/auth/session";
import { EvaluationDomainError } from "./errors";

export function evaluationErrorResponse(error: unknown): NextResponse {
  const authResponse = authErrorResponse(error);
  if (authResponse) return authResponse;
  if (error instanceof EvaluationDomainError) {
    return NextResponse.json(
      { success: false, error: error.message, code: error.code },
      { status: error.status },
    );
  }
  console.error("Evaluation workflow error", error);
  return NextResponse.json({ success: false, error: "Evaluation workflow request failed" }, { status: 500 });
}
