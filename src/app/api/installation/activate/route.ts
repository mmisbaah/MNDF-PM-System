import { NextRequest, NextResponse } from "next/server";
import { pool } from "@/db";
import { authenticateRequest, authErrorResponse } from "@/lib/auth/session";
import { provisionBaselineTemplate } from "@/lib/evaluation/template-service";
import { synchronizeQuarterlyCycles } from "@/lib/evaluation/cycle-service";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    // Provision first so activation cannot leave a tenant active without the
    // required immutable v1.0 baseline. The operation is idempotent on retry.
    await provisionBaselineTemplate(principal.tenantId, principal.accountId);
    await synchronizeQuarterlyCycles(principal.tenantId, principal.accountId);
    await pool.query("SELECT activate_single_organization($1,$2)", [principal.tenantId, principal.accountId]);
    return NextResponse.json({ success: true });
  } catch (error) {
    return authErrorResponse(error) ?? NextResponse.json({ success: false, error: error instanceof Error ? error.message : "Activation failed" }, { status: 422 });
  }
}
