import { NextRequest, NextResponse } from "next/server";
import { authErrorResponse, authorizeRequest } from "@/lib/auth/session";
import { withTenantTransaction } from "@/lib/auth/repository";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const principal = await authorizeRequest(request, "operations.emergency_account_recovery");
    const body = (await request.json().catch(() => null)) as {
      targetTenantId?: string;
      targetAccountId?: string;
      reason?: string;
    } | null;
    if (!body?.targetTenantId || !body.targetAccountId || !body.reason || body.reason.trim().length < 20) {
      return NextResponse.json({ success: false, error: "Target tenant, account, and a detailed reason are required" }, { status: 400 });
    }
    const reason = body.reason.trim();
    const requestId = await withTenantTransaction(principal.tenantId, principal.accountId, async (client) => {
      const result = await client.query<{ request_id: string }>(
        "SELECT record_operator_exception($1, $2, 'EMERGENCY_ACCOUNT_RECOVERY', $3) AS request_id",
        [body.targetTenantId, body.targetAccountId, reason],
      );
      return result.rows[0].request_id;
    });
    return NextResponse.json({ success: true, requestId, status: "RECORDED_FOR_AUTHORIZED_RECOVERY" }, { status: 202 });
  } catch (error) {
    return authErrorResponse(error) ?? NextResponse.json({ success: false, error: "Unable to record recovery request" }, { status: 500 });
  }
}
