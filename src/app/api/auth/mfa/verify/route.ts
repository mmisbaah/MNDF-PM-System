import { NextRequest, NextResponse } from "next/server";
import { MFA_COOKIE } from "@/lib/auth/cookies";
import { isSameOrigin, requestIp, requestUserAgent } from "@/lib/auth/http";
import { issueSession } from "@/lib/auth/issue-session";
import { verifyJwt } from "@/lib/auth/jwt";
import { activateMfa, loadMfaSecret, mfaVerificationBlocked, recordMfaVerification } from "@/lib/auth/repository";
import { decryptSecret } from "@/lib/auth/secrets";
import { verifyTotp } from "@/lib/auth/totp";
import type { MfaChallengeClaims } from "@/lib/auth/types";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) return NextResponse.json({ success: false, error: "Cross-origin request denied" }, { status: 403 });
  const token = request.cookies.get(MFA_COOKIE)?.value;
  const body = (await request.json().catch(() => null)) as { code?: string } | null;
  if (!token || !body?.code) return NextResponse.json({ success: false, error: "MFA challenge and code are required" }, { status: 400 });

  try {
    const claims = await verifyJwt<MfaChallengeClaims>(token, "mfa_challenge");
    if(await mfaVerificationBlocked(claims.tenantId,claims.sub))
      return NextResponse.json({success:false,error:"Too many MFA attempts. Start again after ten minutes."},{status:429});
    const factor = await loadMfaSecret(claims.tenantId, claims.sub);
    if (!factor || !verifyTotp(decryptSecret(factor.encryptedSecret), body.code)) {
      await recordMfaVerification(claims.tenantId,claims.sub,false);
      return NextResponse.json({ success: false, error: "Invalid authentication code" }, { status: 401 });
    }
    await recordMfaVerification(claims.tenantId,claims.sub,true);
    if (!factor.active) await activateMfa(claims.tenantId, claims.sub);
    await issueSession({
      accountId: claims.sub,
      tenantId: claims.tenantId,
      roles: claims.roles,
      mfa: true,
      ipAddress: requestIp(request),
      userAgent: requestUserAgent(request),
    });
    return NextResponse.json({ success: true, next: "AUTHENTICATED" });
  } catch {
    return NextResponse.json({ success: false, error: "Invalid or expired MFA challenge" }, { status: 401 });
  }
}
