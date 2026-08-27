import { NextRequest, NextResponse } from "next/server";
import { MFA_COOKIE } from "@/lib/auth/cookies";
import { verifyJwt } from "@/lib/auth/jwt";
import { encryptSecret } from "@/lib/auth/secrets";
import { storePendingMfaSecret } from "@/lib/auth/repository";
import { generateTotpSecret, totpUri } from "@/lib/auth/totp";
import type { MfaChallengeClaims } from "@/lib/auth/types";
import { isSameOrigin } from "@/lib/auth/http";
import { loadMfaSecret } from "@/lib/auth/repository";
import { pool } from "@/db";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) return NextResponse.json({ success: false, error: "Cross-origin request denied" }, { status: 403 });
  const token = request.cookies.get(MFA_COOKIE)?.value;
  if (!token) return NextResponse.json({ success: false, error: "Password verification required" }, { status: 401 });
  try {
    const claims = await verifyJwt<MfaChallengeClaims>(token, "mfa_challenge");
    const existing = await loadMfaSecret(claims.tenantId, claims.sub);
    if (existing?.active) {
      return NextResponse.json({ success: false, error: "MFA is already enrolled; verified recovery is required to replace it" }, { status: 409 });
    }
    const body = (await request.json().catch(() => ({}))) as { tenantCode?: string; email?: string };
    if (!body.email) {
      return NextResponse.json({ success: false, error: "Pilot login ID is required" }, { status: 400 });
    }
    const installation = await pool.query("SELECT tenant_id,organization_name FROM read_installation_identity()");
    const identity = installation.rows[0];
    if (!identity || identity.tenant_id !== claims.tenantId) return NextResponse.json({ success: false, error: "Installation identity mismatch" }, { status: 403 });
    const organizationLabel = identity.organization_name || "Performance Tracker";
    const secret = generateTotpSecret();
    await storePendingMfaSecret(claims.tenantId, claims.sub, encryptSecret(secret));
    return NextResponse.json({
      success: true,
      secret,
      otpauthUri: totpUri(secret, organizationLabel, body.email),
      instruction: "Add this account to an authenticator app, then verify a six-digit code.",
    });
  } catch {
    return NextResponse.json({ success: false, error: "Invalid or expired MFA challenge" }, { status: 401 });
  }
}
