import { NextRequest, NextResponse } from "next/server";
import { setMfaChallengeCookie } from "@/lib/auth/cookies";
import { isSameOrigin, requestIp, requestUserAgent } from "@/lib/auth/http";
import { issueSession } from "@/lib/auth/issue-session";
import { buildClaimsBase, signJwt } from "@/lib/auth/jwt";
import { verifyPassword } from "@/lib/auth/password";
import { requiresMfa } from "@/lib/auth/rbac";
import { accountRequiresPasswordChange, lookupLoginAccount, recordLoginEvent, tooManyLoginFailures } from "@/lib/auth/repository";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) return NextResponse.json({ success: false, error: "Cross-origin request denied" }, { status: 403 });
  const body = (await request.json().catch(() => null)) as { tenantCode?: string; email?: string; password?: string } | null;
  if (!body?.email || !body.password) {
    return NextResponse.json({ success: false, error: "Pilot login ID and password are required" }, { status: 400 });
  }

  try {
  const account = await lookupLoginAccount(body.tenantCode ?? "", body.email);
  if (!account || !account.isActive) {
    return NextResponse.json({ success: false, error: "Invalid credentials" }, { status: 401 });
  }

  const ipAddress = requestIp(request);
  if (await tooManyLoginFailures(account.tenantId, account.email, ipAddress)) {
    return NextResponse.json({ success: false, error: "Too many login attempts. Try again later." }, { status: 429 });
  }

  const passwordValid = await verifyPassword(body.password, account.passwordHash).catch(() => false);
  if (!passwordValid) {
    await recordLoginEvent(account.tenantId, account.accountId, account.email, ipAddress, false, "INVALID_PASSWORD");
    return NextResponse.json({ success: false, error: "Invalid credentials" }, { status: 401 });
  }

  await recordLoginEvent(account.tenantId, account.accountId, account.email, ipAddress, true, "PASSWORD_VERIFIED");
  if(await accountRequiresPasswordChange(account.tenantId,account.accountId)){
    const challenge=await signJwt({...buildClaimsBase(account.accountId,account.tenantId,account.roles,10*60),purpose:"mfa_challenge" as const,passwordVerified:true as const});
    await setMfaChallengeCookie(challenge);
    return NextResponse.json({success:true,next:"PASSWORD_CHANGE_REQUIRED"},{status:202});
  }
  if (requiresMfa(account.roles) || account.mfaEnabled) {
    const challenge = await signJwt({
      ...buildClaimsBase(account.accountId, account.tenantId, account.roles, 10 * 60),
      purpose: "mfa_challenge" as const,
      passwordVerified: true as const,
    });
    await setMfaChallengeCookie(challenge);
    return NextResponse.json(
      { success: true, next: account.mfaEnabled ? "MFA_VERIFY" : "MFA_SETUP_REQUIRED" },
      { status: 202 },
    );
  }

  await issueSession({
    accountId: account.accountId,
    tenantId: account.tenantId,
    roles: account.roles,
    mfa: false,
    ipAddress,
    userAgent: requestUserAgent(request),
  });
  return NextResponse.json({ success: true, next: "AUTHENTICATED" });
  } catch (error) {
    console.error("Authentication service failure", error);
    return NextResponse.json(
      { success: false, error: "Authentication service is temporarily unavailable" },
      { status: 503 },
    );
  }
}
