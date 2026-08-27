import { NextRequest, NextResponse } from "next/server";
import { authenticateRequest, authErrorResponse } from "@/lib/auth/session";
import { getAdministratorAuthorizationState } from "@/lib/auth/administrator-authorization";

export async function GET(request: NextRequest) {
  try {
    const principal = await authenticateRequest(request);
    return NextResponse.json({ success: true, principal, administratorAuthorization: await getAdministratorAuthorizationState(principal) });
  } catch (error) {
    return authErrorResponse(error) ?? NextResponse.json({ success: false, error: "Unable to read session" }, { status: 500 });
  }
}
