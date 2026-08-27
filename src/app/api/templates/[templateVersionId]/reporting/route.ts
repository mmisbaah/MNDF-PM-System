import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { configureReportingDetails, type ReportingDetailsInput } from "@/lib/evaluation/template-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function PUT(
  request: NextRequest,
  context: { params: Promise<{ templateVersionId: string }> },
) {
  try {
    const principal = await authorizeRequest(request, "template.manage");
    const { templateVersionId } = await context.params;
    const body = await request.json() as ReportingDetailsInput;
    const result = await configureReportingDetails(
      principal.tenantId,
      principal.accountId,
      templateVersionId,
      body,
    );
    return NextResponse.json({ success: true, reporting: result });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
