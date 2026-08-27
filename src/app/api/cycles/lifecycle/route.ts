import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { synchronizeQuarterlyCycles } from "@/lib/evaluation/cycle-service";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const principal = await authorizeRequest(request, "template.manage");
    const cycles = await synchronizeQuarterlyCycles(
      principal.tenantId,
      principal.accountId,
    );
    return NextResponse.json({ success: true, cycles });
  } catch (error) {
    return evaluationErrorResponse(error);
  }
}
