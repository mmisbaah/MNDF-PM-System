import { NextRequest, NextResponse } from "next/server";
import { clearAuthCookies } from "@/lib/auth/cookies";
import { authenticateRequest, authErrorResponse } from "@/lib/auth/session";
import { revokeSession } from "@/lib/auth/repository";
import { isSameOrigin } from "@/lib/auth/http";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) {
    return NextResponse.json({ success: false, error: "Cross-origin request denied" }, { status: 403 });
  }
  try {
    const principal = await authenticateRequest(request);
    await revokeSession(principal.tenantId, principal.accountId, principal.sessionId);
    await clearAuthCookies();
    return NextResponse.json({ success: true });
  } catch (error) {
    await clearAuthCookies();
    return authErrorResponse(error) ?? NextResponse.json({ success: false, error: "Logout failed" }, { status: 500 });
  }
}
