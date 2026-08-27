import { NextRequest, NextResponse } from "next/server";
import { REFRESH_COOKIE, setAccessCookie, setRefreshCookie } from "@/lib/auth/cookies";
import { buildClaimsBase, signJwt } from "@/lib/auth/jwt";
import { hashRefreshToken, newRefreshToken, rotateSession } from "@/lib/auth/repository";
import { isSameOrigin } from "@/lib/auth/http";
import { requiresMfa } from "@/lib/auth/rbac";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) return NextResponse.json({ success: false, error: "Cross-origin request denied" }, { status: 403 });
  const stored = request.cookies.get(REFRESH_COOKIE)?.value;
  const parts = stored?.split(".") ?? [];
  if (parts.length !== 3) return NextResponse.json({ success: false, error: "Refresh session required" }, { status: 401 });
  const [tenantId, sessionId, secret] = parts;
  const currentToken = `${sessionId}.${secret}`;
  const replacement = newRefreshToken();
  // Preserve the stable session ID while rotating only its secret.
  const replacementToken = `${sessionId}.${replacement.token.split(".")[1]}`;
  const rotated = await rotateSession(tenantId, sessionId, hashRefreshToken(currentToken), hashRefreshToken(replacementToken));
  if (!rotated) return NextResponse.json({ success: false, error: "Refresh session invalid or reused" }, { status: 401 });
  if (requiresMfa(rotated.roles) && !rotated.mfa) {
    return NextResponse.json({ success: false, error: "Multi-factor authentication enrollment required" }, { status: 403 });
  }

  const access = await signJwt({
    ...buildClaimsBase(rotated.accountId, tenantId, rotated.roles, 15 * 60),
    sessionId,
    mfa: rotated.mfa,
    purpose: "access" as const,
  });
  await setAccessCookie(access);
  await setRefreshCookie(tenantId, replacementToken);
  return NextResponse.json({ success: true });
}
