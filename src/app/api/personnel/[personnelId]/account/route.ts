import { NextRequest, NextResponse } from "next/server";
import { authorizeRequest } from "@/lib/auth/session";
import { evaluationErrorResponse } from "@/lib/evaluation/http";
import { createPersonnelAccount, resetPersonnelTemporaryPassword } from "@/lib/personnel/account-service";

export const runtime = "nodejs";
type Context = { params: Promise<{ personnelId: string }> };

export async function POST(request: NextRequest, context: Context) {
  try {
    const principal = await authorizeRequest(request, "accounts.provision");
    const { personnelId } = await context.params;
    return NextResponse.json({ success: true, account: await createPersonnelAccount(principal.tenantId, principal.accountId, personnelId, await request.json()) }, { status: 201 });
  } catch (error) { return evaluationErrorResponse(error); }
}

export async function PATCH(request: NextRequest, context: Context) {
  try {
    const principal = await authorizeRequest(request, "accounts.provision");
    const { personnelId } = await context.params;
    return NextResponse.json({ success: true, account: await resetPersonnelTemporaryPassword(principal.tenantId, principal.accountId, personnelId, await request.json()) });
  } catch (error) { return evaluationErrorResponse(error); }
}
