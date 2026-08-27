import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { addUnitSpecificCategory, type UnitCategoryInput } from "@/lib/evaluation/template-service";
import { evaluationErrorResponse } from "@/lib/evaluation/http";

export const runtime = "nodejs";

export async function POST(
  request: NextRequest,
  context: { params: Promise<{ templateVersionId: string }> },
) {
  try {
    const principal = await authorizeRequest(request, "template.manage");
    const { templateVersionId } = await context.params;
    const body = await request.json() as UnitCategoryInput;
    const result = await addUnitSpecificCategory(
      principal.tenantId,
      principal.accountId,
      templateVersionId,
      body,
    );
    return NextResponse.json({ success: true, category: result }, { status: 201 });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
