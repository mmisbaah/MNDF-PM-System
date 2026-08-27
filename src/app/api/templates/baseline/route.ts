import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { provisionBaselineTemplate } from "@/lib/evaluation/template-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const principal = await authorizeRequest(request, "template.manage");
    const result = await provisionBaselineTemplate(principal.tenantId, principal.accountId);
    return NextResponse.json({ success: true, template: result }, { status: result.created ? 201 : 200 });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
